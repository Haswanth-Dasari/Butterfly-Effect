-- Returns the maximum cascade depth allowed for cascading rule triggers.
CREATE FUNCTION cascade_max_depth()
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 5;
$$;

-- Recursively resolves JSON template placeholders against an event context.
CREATE FUNCTION resolve_template(p_template JSONB, e event)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_type TEXT;
    v_str TEXT;
    v_key TEXT;
BEGIN
    IF p_template IS NULL THEN
        RETURN NULL;
    END IF;

    v_type := jsonb_typeof(p_template);

    IF v_type = 'object' THEN
        IF p_template = '{}'::jsonb THEN
            RETURN '{}'::jsonb;
        END IF;
        RETURN (
            SELECT jsonb_object_agg(key, resolve_template(value, e))
            FROM jsonb_each(p_template)
        );
    ELSIF v_type = 'array' THEN
        IF p_template = '[]'::jsonb THEN
            RETURN '[]'::jsonb;
        END IF;
        RETURN (
            SELECT jsonb_agg(resolve_template(elem, e) ORDER BY ord)
            FROM jsonb_array_elements(p_template) WITH ORDINALITY AS t(elem, ord)
        );
    ELSIF v_type = 'string' THEN
        v_str := jsonb_build_array(p_template)->>0;
        IF v_str LIKE '$%' THEN
            IF v_str = '$actor' THEN
                RETURN to_jsonb(e.actor_id);
            ELSIF v_str = '$tick' THEN
                RETURN to_jsonb(e.tick);
            ELSIF v_str = '$branch' THEN
                RETURN to_jsonb(e.branch_id);
            ELSIF v_str = '$event' THEN
                RETURN to_jsonb(e.event_id);
            ELSIF v_str LIKE '$payload.%' THEN
                v_key := substr(v_str, 10);
                RETURN COALESCE(e.payload -> v_key, 'null'::jsonb);
            ELSE
                RAISE EXCEPTION 'unknown template reference %', v_str;
            END IF;
        ELSE
            RETURN p_template;
        END IF;
    ELSE
        RETURN p_template;
    END IF;
END;
$$;

-- Evaluates whether a rule's conditions match an event context.
CREATE FUNCTION rule_matches(r "rule", e event)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    c JSONB;
    v_cond_key TEXT;
    v_cond_val JSONB;
    v_k TEXT;
    v_v JSONB;
    v_place_id INT;
    v_item_id INT;
    v_qty NUMERIC;
    v_stock_qty INT;
    v_entity_id INT;
    v_state_key TEXT;
    v_target_val NUMERIC;
    v_state JSONB;
BEGIN
    IF r.condition IS NULL THEN
        RETURN TRUE;
    END IF;

    c := resolve_template(r.condition::jsonb, e);

    FOR v_cond_key, v_cond_val IN SELECT key, value FROM jsonb_each(c) LOOP
        IF v_cond_key = 'payload_eq' THEN
            FOR v_k, v_v IN SELECT key, value FROM jsonb_each(v_cond_val) LOOP
                IF NOT (e.payload ? v_k) THEN
                    RETURN FALSE;
                END IF;
                IF (e.payload -> v_k) IS DISTINCT FROM v_v THEN
                    RETURN FALSE;
                END IF;
            END LOOP;

        ELSIF v_cond_key = 'payload_gte' THEN
            FOR v_k, v_v IN SELECT key, value FROM jsonb_each(v_cond_val) LOOP
                IF NOT (e.payload ? v_k) OR (e.payload ->> v_k) IS NULL THEN
                    RETURN FALSE;
                END IF;
                IF (e.payload ->> v_k)::numeric < (v_v#>>'{}')::numeric THEN
                    RETURN FALSE;
                END IF;
            END LOOP;

        ELSIF v_cond_key = 'stock_below' THEN
            v_place_id := (v_cond_val->>'place_id')::int;
            v_item_id := (v_cond_val->>'item_id')::int;
            v_qty := (v_cond_val->>'qty')::numeric;

            SELECT qty INTO v_stock_qty
            FROM stock
            WHERE place_id = v_place_id
              AND item_id = v_item_id
              AND branch_id = e.branch_id;

            IF NOT FOUND THEN
                RETURN FALSE;
            END IF;

            IF NOT (v_stock_qty < v_qty) THEN
                RETURN FALSE;
            END IF;

        ELSIF v_cond_key = 'stock_at_least' THEN
            v_place_id := (v_cond_val->>'place_id')::int;
            v_item_id := (v_cond_val->>'item_id')::int;
            v_qty := (v_cond_val->>'qty')::numeric;

            SELECT qty INTO v_stock_qty
            FROM stock
            WHERE place_id = v_place_id
              AND item_id = v_item_id
              AND branch_id = e.branch_id;

            IF NOT FOUND THEN
                RETURN FALSE;
            END IF;

            IF NOT (v_stock_qty >= v_qty) THEN
                RETURN FALSE;
            END IF;

        ELSIF v_cond_key = 'state_lt' THEN
            v_entity_id := (v_cond_val->>'entity_id')::int;
            v_state_key := v_cond_val->>'key';
            v_target_val := (v_cond_val->>'value')::numeric;

            SELECT state INTO v_state
            FROM entity_state
            WHERE entity_id = v_entity_id
              AND branch_id = e.branch_id
              AND upper_inf(valid_ticks);

            IF NOT FOUND THEN
                RETURN FALSE;
            END IF;

            IF (v_state ->> v_state_key) IS NULL THEN
                RETURN FALSE;
            END IF;

            IF NOT ((v_state ->> v_state_key)::numeric < v_target_val) THEN
                RETURN FALSE;
            END IF;

        ELSE
            RAISE EXCEPTION 'unknown condition key %', v_cond_key;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$;

-- Inserts a rule effect event, records causal provenance, and adds witnesses.
CREATE FUNCTION emit_effect(p_cause event, p_rule_id INT, p_effect JSONB, p_tick INT)
RETURNS event
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_event event;
    v_visibility TEXT;
BEGIN
    INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
    VALUES (
        p_cause.branch_id,
        p_tick,
        (p_effect->>'actor')::int,
        p_effect->>'action',
        COALESCE(p_effect->'payload', '{}'::jsonb)
    )
    RETURNING * INTO v_new_event;

    INSERT INTO event_cause (effect_id, cause_id, rule_id)
    VALUES (v_new_event.event_id, p_cause.event_id, p_rule_id);

    v_visibility := COALESCE(p_effect->>'visibility', default_visibility(p_effect->>'action'));
    PERFORM add_witnesses(v_new_event.event_id, v_visibility);

    RETURN v_new_event;
END;
$$;

-- Evaluates and triggers rules for an event up to the cascade max depth.
CREATE FUNCTION process_event_rules(e event, p_depth INT DEFAULT 0)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    r "rule";
    v_effect JSONB;
    v_new event;
BEGIN
    -- depth counts immediate hops since the last arrival; a root or a due scheduled effect starts at 0.
    IF p_depth >= cascade_max_depth() THEN
        RAISE NOTICE 'cascade depth limit reached at event %', e.event_id;
        RETURN;
    END IF;

    FOR r IN
        SELECT *
        FROM "rule"
        WHERE trigger_action_type = e.action_type
          AND is_active
        ORDER BY rule_id
    LOOP
        IF NOT rule_matches(r, e) THEN
            CONTINUE;
        END IF;

        v_effect := resolve_template(r.effect_template::jsonb, e);

        IF r.delay_ticks = 0 THEN
            v_new := emit_effect(e, r.rule_id, v_effect, e.tick);
            PERFORM process_event_rules(v_new, p_depth + 1);
        ELSE
            INSERT INTO scheduled_effect (branch_id, due_tick, source_event_id, rule_id, payload)
            VALUES (e.branch_id, e.tick + r.delay_ticks, e.event_id, r.rule_id, v_effect);
        END IF;
    END LOOP;
END;
$$;

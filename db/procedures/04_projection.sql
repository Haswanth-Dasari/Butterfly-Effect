-- Projects an event into current-world tables according to its action type.
CREATE FUNCTION project_event(e event)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_place_id INT;
    v_item_id INT;
    v_qty INT;
    v_target_actor INT;
    v_item_name TEXT;
    v_price NUMERIC(10,2);
    v_current_price NUMERIC(10,2);
    v_price_pct NUMERIC;
    v_entity_id INT;
    v_patch JSONB;
    v_open_state JSONB;
    v_k TEXT;
    v_v JSONB;
BEGIN
    CASE e.action_type
        WHEN 'arrive' THEN
            INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
            VALUES (
                e.actor_id,
                e.branch_id,
                int4range(e.tick, NULL),
                jsonb_build_object(
                    'mood', 'curious',
                    'trust', 50,
                    'coins', COALESCE((e.payload->>'coins')::int, 5),
                    'inv', '{}'::jsonb
                )
            );

        WHEN 'steal' THEN
            IF e.payload->>'qty' IS NULL OR (e.payload->>'qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            IF e.actor_id IS NULL THEN
                RAISE EXCEPTION 'steal needs an actor';
            END IF;

            v_place_id := (e.payload->>'place_id')::int;
            v_item_id := (e.payload->>'item_id')::int;
            v_qty := (e.payload->>'qty')::int;

            UPDATE stock
            SET qty = qty - v_qty
            WHERE place_id = v_place_id
              AND item_id = v_item_id
              AND branch_id = e.branch_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'no such stock';
            END IF;

            SELECT name INTO v_item_name FROM item WHERE item_id = v_item_id;

            PERFORM adjust_inventory(e.actor_id, e.branch_id, e.tick, v_item_name, v_qty);

        WHEN 'gift' THEN
            IF e.payload->>'qty' IS NULL OR (e.payload->>'qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            v_item_id := (e.payload->>'item_id')::int;
            v_qty := (e.payload->>'qty')::int;
            v_target_actor := (e.payload->>'target_actor')::int;

            SELECT name INTO v_item_name FROM item WHERE item_id = v_item_id;

            PERFORM adjust_inventory(e.actor_id, e.branch_id, e.tick, v_item_name, -v_qty);
            PERFORM adjust_inventory(v_target_actor, e.branch_id, e.tick, v_item_name, v_qty);

        WHEN 'set_price' THEN
            v_place_id := (e.payload->>'place_id')::int;
            v_item_id := (e.payload->>'item_id')::int;

            IF e.payload ? 'price' THEN
                v_price := (e.payload->>'price')::numeric;
                UPDATE stock
                SET price = v_price
                WHERE place_id = v_place_id
                  AND item_id = v_item_id
                  AND branch_id = e.branch_id;

                IF NOT FOUND THEN
                    RAISE EXCEPTION 'no such stock';
                END IF;
            ELSIF e.payload ? 'price_pct' THEN
                SELECT price INTO v_current_price
                FROM stock
                WHERE place_id = v_place_id
                  AND item_id = v_item_id
                  AND branch_id = e.branch_id;

                IF NOT FOUND THEN
                    RAISE EXCEPTION 'no such stock';
                END IF;

                v_price_pct := (e.payload->>'price_pct')::numeric;
                v_price := round(v_current_price * (100 + v_price_pct) / 100.0, 2);

                UPDATE stock
                SET price = v_price
                WHERE place_id = v_place_id
                  AND item_id = v_item_id
                  AND branch_id = e.branch_id;
            ELSE
                RAISE EXCEPTION 'set_price needs price or price_pct';
            END IF;

        WHEN 'state_change' THEN
            v_entity_id := (e.payload->>'entity_id')::int;
            v_patch := COALESCE(e.payload->'set', '{}'::jsonb);

            IF e.payload ? 'add' AND jsonb_typeof(e.payload->'add') = 'object' THEN
                SELECT state INTO v_open_state
                FROM entity_state
                WHERE entity_id = v_entity_id
                  AND branch_id = e.branch_id
                  AND upper_inf(valid_ticks);

                IF NOT FOUND THEN
                    PERFORM patch_entity_state(v_entity_id, e.branch_id, e.tick, '{}'::jsonb);
                END IF;

                FOR v_k, v_v IN SELECT key, value FROM jsonb_each(e.payload->'add') LOOP
                    v_patch := v_patch || jsonb_build_object(
                        v_k,
                        COALESCE((v_open_state->>v_k)::numeric, 0) + (v_v#>>'{}')::numeric
                    );
                END LOOP;
            END IF;

            PERFORM patch_entity_state(v_entity_id, e.branch_id, e.tick, v_patch);

        WHEN 'day_start' THEN
            NULL;

        ELSE
            -- other actions are recorded but not projected yet
            NULL;
    END CASE;
END;
$$;

-- Trigger function executing projection logic after event insertion.
CREATE FUNCTION event_project_trg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM project_event(NEW);
    RETURN NULL;
END;
$$;

CREATE TRIGGER event_project
AFTER INSERT ON event
FOR EACH ROW
EXECUTE FUNCTION event_project_trg();

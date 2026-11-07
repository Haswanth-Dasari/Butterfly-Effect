-- Adjusts stock quantity by delta at a given place and branch.
CREATE FUNCTION adjust_stock(p_place INT, p_item INT, p_branch INT, p_delta INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE stock
    SET qty = qty + p_delta
    WHERE place_id = p_place
      AND item_id = p_item
      AND branch_id = p_branch;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such stock';
    END IF;
END;
$$;

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
    v_total NUMERIC;
    v_wage NUMERIC;
    v_place_kind TEXT;
    v_grain_id INT;
    v_output_item_id INT;
    v_output_qty INT;
    v_input_item_id INT;
    v_input_qty INT;
    v_from_place INT;
    v_to_place INT;
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

        WHEN 'trade' THEN
            v_target_actor := (e.payload->>'target_actor')::int;
            IF e.actor_id IS NULL OR v_target_actor IS NULL THEN
                RAISE EXCEPTION 'trade needs an actor and a target_actor';
            END IF;

            IF e.payload->>'qty' IS NULL OR (e.payload->>'qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            v_place_id := (e.payload->>'place_id')::int;
            v_item_id := (e.payload->>'item_id')::int;
            v_qty := (e.payload->>'qty')::int;

            SELECT price INTO v_price
            FROM stock
            WHERE place_id = v_place_id
              AND item_id = v_item_id
              AND branch_id = e.branch_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'no such stock';
            END IF;

            v_total := v_price * v_qty;

            SELECT name INTO v_item_name FROM item WHERE item_id = v_item_id;

            PERFORM adjust_stock(v_place_id, v_item_id, e.branch_id, -v_qty);
            PERFORM adjust_coins(e.actor_id, e.branch_id, e.tick, -v_total);
            PERFORM adjust_coins(v_target_actor, e.branch_id, e.tick, v_total);
            PERFORM adjust_inventory(e.actor_id, e.branch_id, e.tick, v_item_name, v_qty);

        WHEN 'hire' THEN
            v_target_actor := (e.payload->>'target_actor')::int;
            IF v_target_actor IS NULL THEN
                RAISE EXCEPTION 'hire needs a target_actor';
            END IF;

            IF e.payload->>'wage' IS NULL OR (e.payload->>'wage')::numeric <= 0 THEN
                RAISE EXCEPTION 'wage must be positive';
            END IF;

            v_wage := (e.payload->>'wage')::numeric;

            PERFORM adjust_coins(e.actor_id, e.branch_id, e.tick, -v_wage);
            PERFORM adjust_coins(v_target_actor, e.branch_id, e.tick, v_wage);
            PERFORM patch_entity_state(v_target_actor, e.branch_id, e.tick, jsonb_build_object('employer', e.actor_id));

        WHEN 'help_harvest' THEN
            IF e.payload->>'qty' IS NULL OR (e.payload->>'qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            v_qty := (e.payload->>'qty')::int;
            IF v_qty > 10 THEN
                RAISE EXCEPTION 'qty too large';
            END IF;

            v_place_id := (e.payload->>'place_id')::int;

            SELECT kind INTO v_place_kind
            FROM place
            WHERE place_id = v_place_id;

            IF NOT FOUND OR v_place_kind != 'farm' THEN
                RAISE EXCEPTION 'not a farm';
            END IF;

            SELECT item_id INTO v_grain_id FROM item WHERE name = 'grain';

            PERFORM adjust_stock(v_place_id, v_grain_id, e.branch_id, v_qty);

        WHEN 'sabotage' THEN
            -- sabotage destroys goods; steal conserves them.
            IF e.payload->>'qty' IS NULL OR (e.payload->>'qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            v_place_id := (e.payload->>'place_id')::int;
            v_item_id := (e.payload->>'item_id')::int;
            v_qty := (e.payload->>'qty')::int;

            PERFORM adjust_stock(v_place_id, v_item_id, e.branch_id, -v_qty);

        WHEN 'produce' THEN
            IF e.payload->>'output_qty' IS NULL OR (e.payload->>'output_qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            v_place_id := (e.payload->>'place_id')::int;
            v_output_item_id := (e.payload->>'output_item_id')::int;
            v_output_qty := (e.payload->>'output_qty')::int;

            IF e.payload ? 'input_item_id' AND e.payload->>'input_item_id' IS NOT NULL THEN
                IF e.payload->>'input_qty' IS NULL OR (e.payload->>'input_qty')::int <= 0 THEN
                    RAISE EXCEPTION 'qty must be positive';
                END IF;

                v_input_item_id := (e.payload->>'input_item_id')::int;
                v_input_qty := (e.payload->>'input_qty')::int;

                PERFORM adjust_stock(v_place_id, v_input_item_id, e.branch_id, -v_input_qty);
            END IF;

            PERFORM adjust_stock(v_place_id, v_output_item_id, e.branch_id, v_output_qty);

        WHEN 'deliver' THEN
            IF e.payload->>'qty' IS NULL OR (e.payload->>'qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            v_from_place := (e.payload->>'from_place')::int;
            v_to_place := (e.payload->>'to_place')::int;
            v_item_id := (e.payload->>'item_id')::int;
            v_qty := (e.payload->>'qty')::int;

            PERFORM adjust_stock(v_from_place, v_item_id, e.branch_id, -v_qty);
            PERFORM adjust_stock(v_to_place, v_item_id, e.branch_id, v_qty);

        WHEN 'consume' THEN
            IF e.payload->>'qty' IS NULL OR (e.payload->>'qty')::int <= 0 THEN
                RAISE EXCEPTION 'qty must be positive';
            END IF;

            v_place_id := (e.payload->>'place_id')::int;
            v_item_id := (e.payload->>'item_id')::int;
            v_qty := (e.payload->>'qty')::int;

            PERFORM adjust_stock(v_place_id, v_item_id, e.branch_id, -v_qty);

        WHEN 'day_start' THEN
            NULL;

        ELSE
            -- social actions; effects come from rules
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

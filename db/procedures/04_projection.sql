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

            UPDATE stock
            SET price = (e.payload->>'price')::numeric
            WHERE place_id = v_place_id
              AND item_id = v_item_id
              AND branch_id = e.branch_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'no such stock';
            END IF;

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

BEGIN;

INSERT INTO place (name, kind, x, y)
VALUES ('constraint-test-place', 'village', 0, 0);

INSERT INTO home (place_id, family_name)
SELECT place_id, 'constraint-test-family'
FROM place
WHERE name = 'constraint-test-place';

INSERT INTO actor (name, kind, job, home_id)
SELECT 'constraint-test-player', 'player', NULL, home_id
FROM home
WHERE family_name = 'constraint-test-family';

INSERT INTO item (name)
VALUES ('constraint-test-item');

INSERT INTO action_type (action_type, description)
VALUES ('constraint_test_action', 'Constraint test action');

INSERT INTO branch (name)
VALUES ('constraint-test-branch');

INSERT INTO event (branch_id, tick, actor_id, action_type, payload, prev_hash, hash)
SELECT branch_id, 1, actor_id, 'constraint_test_action', '{}'::jsonb, NULL, '\x00'::bytea
FROM branch
CROSS JOIN actor
WHERE branch.name = 'constraint-test-branch'
  AND actor.name = 'constraint-test-player';

INSERT INTO event (branch_id, tick, actor_id, action_type, payload, prev_hash, hash)
SELECT branch_id, 2, actor_id, 'constraint_test_action', '{}'::jsonb, '\x00'::bytea, '\x00'::bytea
FROM branch
CROSS JOIN actor
WHERE branch.name = 'constraint-test-branch'
  AND actor.name = 'constraint-test-player';

DO $$
BEGIN
    BEGIN
        INSERT INTO event (branch_id, tick, action_type, payload, hash)
        SELECT branch_id, -1, 'constraint_test_action', '{}'::jsonb, '\x00'::bytea
        FROM branch
        WHERE name = 'constraint-test-branch';
        RAISE EXCEPTION 'FAIL: event with negative tick';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: event with negative tick';
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO event_cause (effect_id, cause_id)
        SELECT effect_event.event_id, cause_event.event_id
        FROM event AS effect_event
        JOIN event AS cause_event
          ON cause_event.branch_id = effect_event.branch_id
        JOIN branch ON branch.branch_id = effect_event.branch_id
        WHERE branch.name = 'constraint-test-branch'
          AND effect_event.tick = 1
          AND cause_event.tick = 2;
        RAISE EXCEPTION 'FAIL: event_cause with cause_id >= effect_id';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: event_cause with cause_id >= effect_id';
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
        SELECT 2147483647, branch_id, '[1,5)'::int4range, '{}'::jsonb
        FROM branch
        WHERE name = 'constraint-test-branch';
        INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
        SELECT 2147483647, branch_id, '[4,7)'::int4range, '{}'::jsonb
        FROM branch
        WHERE name = 'constraint-test-branch';
        RAISE EXCEPTION 'FAIL: overlapping entity_state valid_ticks';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE 'PASS: overlapping entity_state valid_ticks';
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO stock (place_id, item_id, branch_id, qty, price)
        SELECT place.place_id, item.item_id, branch.branch_id, -1, 0
        FROM place
        CROSS JOIN item
        CROSS JOIN branch
        WHERE place.name = 'constraint-test-place'
          AND item.name = 'constraint-test-item'
          AND branch.name = 'constraint-test-branch';
        RAISE EXCEPTION 'FAIL: stock with negative qty';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: stock with negative qty';
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO home (place_id, family_name)
        SELECT place_id, 'constraint-test-second-family'
        FROM place
        WHERE name = 'constraint-test-place';
        RAISE EXCEPTION 'FAIL: second home for the same place_id';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: second home for the same place_id';
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO event (branch_id, tick, action_type, payload, hash)
        SELECT branch_id, 3, 'constraint_test_missing_action', '{}'::jsonb, '\x00'::bytea
        FROM branch
        WHERE name = 'constraint-test-branch';
        RAISE EXCEPTION 'FAIL: event with nonexistent action_type';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'PASS: event with nonexistent action_type';
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO actor (name, kind)
        VALUES ('constraint-test-wizard', 'wizard');
        RAISE EXCEPTION 'FAIL: actor with kind wizard';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: actor with kind wizard';
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        INSERT INTO event_witness (event_id, actor_id)
        SELECT event.event_id, actor.actor_id
        FROM event
        CROSS JOIN actor
        JOIN branch ON branch.branch_id = event.branch_id
        WHERE branch.name = 'constraint-test-branch'
          AND event.tick = 1
          AND actor.name = 'constraint-test-player';
        INSERT INTO event_witness (event_id, actor_id)
        SELECT event.event_id, actor.actor_id
        FROM event
        CROSS JOIN actor
        JOIN branch ON branch.branch_id = event.branch_id
        WHERE branch.name = 'constraint-test-branch'
          AND event.tick = 1
          AND actor.name = 'constraint-test-player';
        RAISE EXCEPTION 'FAIL: duplicate event_witness';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate event_witness';
    END;
END
$$;

ROLLBACK;

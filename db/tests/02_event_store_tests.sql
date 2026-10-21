BEGIN;

INSERT INTO action_type (action_type, description)
VALUES ('test_gift', 'Give a gift')
ON CONFLICT DO NOTHING;

INSERT INTO branch (name)
VALUES ('test_main'), ('test_fork');

INSERT INTO event (branch_id, tick, action_type, payload)
SELECT branch_id, 0, 'test_gift', '{}'::jsonb
FROM branch
WHERE name = 'test_main';

DO $$
DECLARE
    v_event_id BIGINT;
BEGIN
    SELECT event.event_id INTO v_event_id
    FROM event
    JOIN branch ON branch.branch_id = event.branch_id
    WHERE branch.name = 'test_main'
    ORDER BY event.event_id
    LIMIT 1;

    BEGIN
        UPDATE event SET payload = '{"changed": true}'::jsonb WHERE event_id = v_event_id;
        RAISE EXCEPTION 'FAIL: update on event is rejected';
    EXCEPTION
        WHEN OTHERS THEN
            IF position('immutable' IN SQLERRM) > 0 THEN
                RAISE NOTICE 'PASS: update on event is rejected';
            ELSE
                RAISE;
            END IF;
    END;
END
$$;

DO $$
DECLARE
    v_event_id BIGINT;
BEGIN
    SELECT event.event_id INTO v_event_id
    FROM event
    JOIN branch ON branch.branch_id = event.branch_id
    WHERE branch.name = 'test_main'
    ORDER BY event.event_id
    LIMIT 1;

    BEGIN
        DELETE FROM event WHERE event_id = v_event_id;
        RAISE EXCEPTION 'FAIL: delete on event is rejected';
    EXCEPTION
        WHEN OTHERS THEN
            IF position('immutable' IN SQLERRM) > 0 THEN
                RAISE NOTICE 'PASS: delete on event is rejected';
            ELSE
                RAISE;
            END IF;
    END;
END
$$;

DO $$
BEGIN
    BEGIN
        TRUNCATE event;
        RAISE EXCEPTION 'FAIL: truncate on event is rejected';
    EXCEPTION
        WHEN OTHERS THEN
            IF position('immutable' IN SQLERRM) > 0 THEN
                RAISE NOTICE 'PASS: truncate on event is rejected';
            ELSE
                RAISE;
            END IF;
    END;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_event_id BIGINT;
    v_hash BYTEA;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'test_main';
    INSERT INTO event (branch_id, tick, action_type, payload)
    VALUES (v_branch_id, 3, 'test_gift', '{}'::jsonb)
    RETURNING event_id, hash INTO v_event_id, v_hash;

    IF octet_length(v_hash) = 32 THEN
        RAISE NOTICE 'PASS: insert without hashes generates a 32-byte hash';
    ELSE
        RAISE EXCEPTION 'FAIL: insert without hashes generates a 32-byte hash';
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_first_hash BYTEA;
    v_second_hash BYTEA;
    v_second_prev_hash BYTEA;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'test_main';
    SELECT hash INTO v_first_hash
    FROM event
    WHERE branch_id = v_branch_id
    ORDER BY event_id
    LIMIT 1;
    SELECT hash, prev_hash
    INTO v_second_hash, v_second_prev_hash
    FROM event
    WHERE branch_id = v_branch_id
    ORDER BY event_id
    LIMIT 1 OFFSET 1;

    IF v_second_prev_hash = v_first_hash AND octet_length(v_second_hash) = 32 THEN
        RAISE NOTICE 'PASS: second event links to first event hash';
    ELSE
        RAISE EXCEPTION 'FAIL: second event links to first event hash';
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_hash BYTEA;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'test_main';
    INSERT INTO event (branch_id, tick, action_type, payload, hash)
    VALUES (v_branch_id, 5, 'test_gift', '{}'::jsonb, '\xdeadbeef'::bytea)
    RETURNING hash INTO v_hash;

    IF octet_length(v_hash) = 32 AND v_hash <> '\xdeadbeef'::bytea THEN
        RAISE NOTICE 'PASS: client-supplied hash is overwritten';
    ELSE
        RAISE EXCEPTION 'FAIL: client-supplied hash is overwritten';
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_prev_hash BYTEA;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'test_fork';
    INSERT INTO event (branch_id, tick, action_type, payload)
    VALUES (v_branch_id, 0, 'test_gift', '{}'::jsonb)
    RETURNING prev_hash INTO v_prev_hash;

    IF v_prev_hash IS NULL THEN
        RAISE NOTICE 'PASS: event chains are per branch';
    ELSE
        RAISE EXCEPTION 'FAIL: event chains are per branch';
    END IF;
END
$$;

DO $$
DECLARE
    v_problem_count BIGINT;
BEGIN
    SELECT count(*) INTO v_problem_count FROM verify_event_chain();

    IF v_problem_count = 0 THEN
        RAISE NOTICE 'PASS: verifier accepts untampered data';
    ELSE
        RAISE EXCEPTION 'FAIL: verifier accepts untampered data (found % problems)', v_problem_count;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_first_event_id BIGINT;
    v_problem_event_id BIGINT;
    v_problem TEXT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'test_main';
    SELECT event_id INTO v_first_event_id
    FROM event
    WHERE branch_id = v_branch_id
    ORDER BY event_id
    LIMIT 1;

    ALTER TABLE event DISABLE TRIGGER event_immutable;
    UPDATE event
    SET payload = jsonb_build_object('tampered', true)
    WHERE event_id = v_first_event_id;
    ALTER TABLE event ENABLE TRIGGER event_immutable;

    SELECT v.event_id, v.problem
    INTO v_problem_event_id, v_problem
    FROM verify_event_chain() AS v
    WHERE v.branch_id = v_branch_id;

    IF v_problem_event_id = v_first_event_id AND v_problem = 'hash mismatch' THEN
        RAISE NOTICE 'Tamper detected at event_id %: %', v_problem_event_id, v_problem;
        RAISE NOTICE 'PASS: verifier detects tampered payload';
    ELSE
        RAISE EXCEPTION 'FAIL: verifier detects tampered payload';
    END IF;
END
$$;

ROLLBACK;

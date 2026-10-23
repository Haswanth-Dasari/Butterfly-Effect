-- Test Suite 10: Application-Level Recovery (Rebuild Projections from Event Store)

BEGIN;

CREATE TEMP TABLE ctx (
    k TEXT PRIMARY KEY,
    v BIGINT
);
GRANT ALL ON ctx TO PUBLIC;

CREATE TEMP TABLE ctxt (
    k TEXT PRIMARY KEY,
    v TEXT
);
GRANT ALL ON ctxt TO PUBLIC;

-- Setup (no output)
DO $$
DECLARE
    v_main INT;
    v_bakery INT;
    v_bread INT;
    v_hartley INT;
    v_test_a INT;
    v_test_b INT;
    v_latest_main BIGINT;
    v_child INT;
    v_dm TEXT;
    v_dc TEXT;
    v_sched_md5 TEXT;
BEGIN
    -- Look up main branch id once
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    IF v_main IS NULL THEN
        RAISE EXCEPTION 'main branch not found';
    END IF;
    INSERT INTO ctx (k, v) VALUES ('main', v_main);

    SELECT place_id INTO v_bakery FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread FROM item WHERE name = 'bread';
    SELECT place_id INTO v_hartley FROM place WHERE name = 'Hartley Farm';

    -- join_village 'test_a' and 'test_b'
    v_test_a := join_village(v_main, 'test_a');
    v_test_b := join_village(v_main, 'test_b');
    INSERT INTO ctx (k, v) VALUES ('test_a', v_test_a), ('test_b', v_test_b);

    -- test_a steals 1 bread from Maren's Bakery
    PERFORM apply_action(
        v_main,
        v_test_a,
        'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 1)
    );

    -- advance_day three times, after each advance test_b does help_harvest qty 1 at Hartley Farm
    FOR i IN 1..3 LOOP
        PERFORM advance_day(v_main);
        PERFORM apply_action(
            v_main,
            v_test_b,
            'help_harvest',
            jsonb_build_object('place_id', v_hartley, 'qty', 1)
        );
    END LOOP;

    -- fork_branch(main, <latest main event>, 'test_child', 'cow')
    SELECT max(event_id) INTO v_latest_main FROM event WHERE branch_id = v_main;
    v_child := fork_branch(v_main, v_latest_main, 'test_child', 'cow');
    INSERT INTO ctx (k, v) VALUES ('child', v_child);

    -- in the child test_b does help_harvest qty 1
    PERFORM apply_action(
        v_child,
        v_test_b,
        'help_harvest',
        jsonb_build_object('place_id', v_hartley, 'qty', 1)
    );

    -- Record main digest Dm and child digest Dc
    v_dm := branch_projection_digest(v_main);
    v_dc := branch_projection_digest(v_child);
    INSERT INTO ctxt (k, v) VALUES ('Dm', v_dm), ('Dc', v_dc);

    -- Record md5 of scheduled_effect table content ordered by scheduled_id
    SELECT md5(COALESCE(string_agg(t::text, ',' ORDER BY t.scheduled_id), '')) INTO v_sched_md5
    FROM scheduled_effect t;
    INSERT INTO ctxt (k, v) VALUES ('sched_md5', v_sched_md5);

    -- Record counts of closure rows, event_cause rows, and event rows
    INSERT INTO ctx (k, v) VALUES
        ('closure_count', (SELECT count(*) FROM causal_closure)),
        ('cause_count', (SELECT count(*) FROM event_cause)),
        ('event_count', (SELECT count(*) FROM event));
END;
$$;

-- Create saved snapshots of stock and entity_state for the main branch
CREATE TEMP TABLE saved_stock AS
SELECT place_id, item_id, branch_id, qty, price
FROM stock
WHERE branch_id = (SELECT v::int FROM ctx WHERE k = 'main');

CREATE TEMP TABLE saved_entity AS
SELECT entity_id, branch_id, valid_ticks, state
FROM entity_state
WHERE branch_id = (SELECT v::int FROM ctx WHERE k = 'main');

-- Test 1: Baseline sanity
DO $$
DECLARE
    v_main INT;
    v_dm TEXT;
    v_stock_cnt INT;
    v_entity_cnt INT;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_dm FROM ctxt WHERE k = 'Dm';

    IF branch_projection_digest(v_main) <> v_dm THEN
        RAISE EXCEPTION 'FAIL: baseline_sanity (digest mismatch: expected %, got %)', v_dm, branch_projection_digest(v_main);
    END IF;

    SELECT count(*) INTO v_stock_cnt FROM saved_stock;
    SELECT count(*) INTO v_entity_cnt FROM saved_entity;

    IF v_stock_cnt = 0 OR v_entity_cnt = 0 THEN
        RAISE EXCEPTION 'FAIL: baseline_sanity (empty saved tables: stock=%, entity=%)', v_stock_cnt, v_entity_cnt;
    END IF;

    RAISE NOTICE 'PASS: baseline_sanity';
END;
$$;

-- Test 2: Idempotent
DO $$
DECLARE
    v_main INT;
    v_dm TEXT;
    v_diff1 INT;
    v_diff2 INT;
    v_diff3 INT;
    v_diff4 INT;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_dm FROM ctxt WHERE k = 'Dm';

    PERFORM rebuild_projections(v_main);

    IF branch_projection_digest(v_main) <> v_dm THEN
        RAISE EXCEPTION 'FAIL: idempotent (digest mismatch after rebuild: expected %, got %)', v_dm, branch_projection_digest(v_main);
    END IF;

    SELECT count(*) INTO v_diff1 FROM (
        SELECT place_id, item_id, branch_id, qty, price FROM stock WHERE branch_id = v_main
        EXCEPT
        SELECT place_id, item_id, branch_id, qty, price FROM saved_stock
    ) d;

    SELECT count(*) INTO v_diff2 FROM (
        SELECT place_id, item_id, branch_id, qty, price FROM saved_stock
        EXCEPT
        SELECT place_id, item_id, branch_id, qty, price FROM stock WHERE branch_id = v_main
    ) d;

    SELECT count(*) INTO v_diff3 FROM (
        SELECT entity_id, branch_id, valid_ticks, state FROM entity_state WHERE branch_id = v_main
        EXCEPT
        SELECT entity_id, branch_id, valid_ticks, state FROM saved_entity
    ) d;

    SELECT count(*) INTO v_diff4 FROM (
        SELECT entity_id, branch_id, valid_ticks, state FROM saved_entity
        EXCEPT
        SELECT entity_id, branch_id, valid_ticks, state FROM entity_state WHERE branch_id = v_main
    ) d;

    IF v_diff1 <> 0 OR v_diff2 <> 0 OR v_diff3 <> 0 OR v_diff4 <> 0 THEN
        RAISE EXCEPTION 'FAIL: idempotent (row mismatch: stock diffs %, %; entity diffs %, %)', v_diff1, v_diff2, v_diff3, v_diff4;
    END IF;

    RAISE NOTICE 'PASS: idempotent';
END;
$$;

-- Test 3: Repair
DO $$
DECLARE
    v_main INT;
    v_test_a INT;
    v_dm TEXT;
    v_diff1 INT;
    v_diff2 INT;
    v_diff3 INT;
    v_diff4 INT;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v::int INTO v_test_a FROM ctx WHERE k = 'test_a';
    SELECT v INTO v_dm FROM ctxt WHERE k = 'Dm';

    UPDATE stock SET qty = 0 WHERE branch_id = v_main;
    DELETE FROM entity_state WHERE branch_id = v_main AND entity_id = v_test_a;

    IF branch_projection_digest(v_main) = v_dm THEN
        RAISE EXCEPTION 'FAIL: repair (digest unchanged after corruption)';
    END IF;

    PERFORM rebuild_projections(v_main);

    IF branch_projection_digest(v_main) <> v_dm THEN
        RAISE EXCEPTION 'FAIL: repair (digest mismatch after rebuild: expected %, got %)', v_dm, branch_projection_digest(v_main);
    END IF;

    SELECT count(*) INTO v_diff1 FROM (
        SELECT place_id, item_id, branch_id, qty, price FROM stock WHERE branch_id = v_main
        EXCEPT
        SELECT place_id, item_id, branch_id, qty, price FROM saved_stock
    ) d;

    SELECT count(*) INTO v_diff2 FROM (
        SELECT place_id, item_id, branch_id, qty, price FROM saved_stock
        EXCEPT
        SELECT place_id, item_id, branch_id, qty, price FROM stock WHERE branch_id = v_main
    ) d;

    SELECT count(*) INTO v_diff3 FROM (
        SELECT entity_id, branch_id, valid_ticks, state FROM entity_state WHERE branch_id = v_main
        EXCEPT
        SELECT entity_id, branch_id, valid_ticks, state FROM saved_entity
    ) d;

    SELECT count(*) INTO v_diff4 FROM (
        SELECT entity_id, branch_id, valid_ticks, state FROM saved_entity
        EXCEPT
        SELECT entity_id, branch_id, valid_ticks, state FROM entity_state WHERE branch_id = v_main
    ) d;

    IF v_diff1 <> 0 OR v_diff2 <> 0 OR v_diff3 <> 0 OR v_diff4 <> 0 THEN
        RAISE EXCEPTION 'FAIL: repair (row mismatch: stock diffs %, %; entity diffs %, %)', v_diff1, v_diff2, v_diff3, v_diff4;
    END IF;

    RAISE NOTICE 'PASS: repair';
END;
$$;

-- Test 4: Wipe and rebuild
DO $$
DECLARE
    v_main INT;
    v_child INT;
    v_dm TEXT;
    v_dc TEXT;
    v_rebuilt INT;
    v_diff1 INT;
    v_diff2 INT;
    v_diff3 INT;
    v_diff4 INT;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v::int INTO v_child FROM ctx WHERE k = 'child';
    SELECT v INTO v_dm FROM ctxt WHERE k = 'Dm';
    SELECT v INTO v_dc FROM ctxt WHERE k = 'Dc';

    TRUNCATE stock, entity_state;

    IF branch_projection_digest(v_main) = v_dm THEN
        RAISE EXCEPTION 'FAIL: wipe_and_rebuild (digest unchanged after truncate)';
    END IF;

    v_rebuilt := rebuild_all_projections();
    IF v_rebuilt <> 2 THEN
        RAISE EXCEPTION 'FAIL: wipe_and_rebuild (expected 2 branches rebuilt, got %)', v_rebuilt;
    END IF;

    IF branch_projection_digest(v_main) <> v_dm THEN
        RAISE EXCEPTION 'FAIL: wipe_and_rebuild (main digest mismatch: expected %, got %)', v_dm, branch_projection_digest(v_main);
    END IF;

    IF branch_projection_digest(v_child) <> v_dc THEN
        RAISE EXCEPTION 'FAIL: wipe_and_rebuild (child digest mismatch: expected %, got %)', v_dc, branch_projection_digest(v_child);
    END IF;

    SELECT count(*) INTO v_diff1 FROM (
        SELECT place_id, item_id, branch_id, qty, price FROM stock WHERE branch_id = v_main
        EXCEPT
        SELECT place_id, item_id, branch_id, qty, price FROM saved_stock
    ) d;

    SELECT count(*) INTO v_diff2 FROM (
        SELECT place_id, item_id, branch_id, qty, price FROM saved_stock
        EXCEPT
        SELECT place_id, item_id, branch_id, qty, price FROM stock WHERE branch_id = v_main
    ) d;

    SELECT count(*) INTO v_diff3 FROM (
        SELECT entity_id, branch_id, valid_ticks, state FROM entity_state WHERE branch_id = v_main
        EXCEPT
        SELECT entity_id, branch_id, valid_ticks, state FROM saved_entity
    ) d;

    SELECT count(*) INTO v_diff4 FROM (
        SELECT entity_id, branch_id, valid_ticks, state FROM saved_entity
        EXCEPT
        SELECT entity_id, branch_id, valid_ticks, state FROM entity_state WHERE branch_id = v_main
    ) d;

    IF v_diff1 <> 0 OR v_diff2 <> 0 OR v_diff3 <> 0 OR v_diff4 <> 0 THEN
        RAISE EXCEPTION 'FAIL: wipe_and_rebuild (row mismatch: stock diffs %, %; entity diffs %, %)', v_diff1, v_diff2, v_diff3, v_diff4;
    END IF;

    RAISE NOTICE 'PASS: wipe_and_rebuild';
END;
$$;

-- Test 5: Queue untouched
DO $$
DECLARE
    v_sched_md5 TEXT;
    v_cur_md5 TEXT;
BEGIN
    SELECT v INTO v_sched_md5 FROM ctxt WHERE k = 'sched_md5';

    SELECT md5(COALESCE(string_agg(t::text, ',' ORDER BY t.scheduled_id), '')) INTO v_cur_md5
    FROM scheduled_effect t;

    IF v_cur_md5 = v_sched_md5 THEN
        RAISE NOTICE 'PASS: queue_untouched';
    ELSE
        RAISE EXCEPTION 'FAIL: queue_untouched (scheduled_effect altered: expected %, got %)', v_sched_md5, v_cur_md5;
    END IF;
END;
$$;

-- Test 6: Derived structures
DO $$
DECLARE
    v_main INT;
    v_closure_cnt BIGINT;
    v_cause_cnt BIGINT;
    v_exp_closure BIGINT;
    v_exp_cause BIGINT;
    v_bad_causal INT;
    v_leaderboard_cnt INT;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_exp_closure FROM ctx WHERE k = 'closure_count';
    SELECT v INTO v_exp_cause FROM ctx WHERE k = 'cause_count';

    PERFORM rebuild_world(v_main);

    SELECT count(*) INTO v_closure_cnt FROM causal_closure;
    SELECT count(*) INTO v_cause_cnt FROM event_cause;

    IF v_closure_cnt <> v_exp_closure THEN
        RAISE EXCEPTION 'FAIL: derived_structures (causal_closure count: expected %, got %)', v_exp_closure, v_closure_cnt;
    END IF;

    IF v_cause_cnt <> v_exp_cause THEN
        RAISE EXCEPTION 'FAIL: derived_structures (event_cause count: expected %, got %)', v_exp_cause, v_cause_cnt;
    END IF;

    SELECT count(*) INTO v_bad_causal FROM verify_causal_structures();
    IF v_bad_causal <> 0 THEN
        RAISE EXCEPTION 'FAIL: derived_structures (verify_causal_structures reported % issues)', v_bad_causal;
    END IF;

    SELECT count(*) INTO v_leaderboard_cnt FROM mv_leaderboard WHERE branch_id = v_main;
    IF v_leaderboard_cnt < 1 THEN
        RAISE EXCEPTION 'FAIL: derived_structures (mv_leaderboard has no rows for main branch)';
    END IF;

    RAISE NOTICE 'PASS: derived_structures';
END;
$$;

-- Test 7: Isolation
DO $$
DECLARE
    v_main INT;
    v_child INT;
    v_dc TEXT;
    v_cur_dc TEXT;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v::int INTO v_child FROM ctx WHERE k = 'child';
    SELECT v INTO v_dc FROM ctxt WHERE k = 'Dc';

    PERFORM rebuild_projections(v_main);

    v_cur_dc := branch_projection_digest(v_child);
    IF v_cur_dc = v_dc THEN
        RAISE NOTICE 'PASS: isolation';
    ELSE
        RAISE EXCEPTION 'FAIL: isolation (child digest changed from % to %)', v_dc, v_cur_dc;
    END IF;
END;
$$;

-- Test 8: Event log untouched
DO $$
DECLARE
    v_chain_errors INT;
    v_cur_events BIGINT;
    v_exp_events BIGINT;
BEGIN
    SELECT count(*) INTO v_chain_errors FROM verify_event_chain();
    IF v_chain_errors <> 0 THEN
        RAISE EXCEPTION 'FAIL: event_log_untouched (verify_event_chain reported % problems)', v_chain_errors;
    END IF;

    SELECT count(*) INTO v_cur_events FROM event;
    SELECT v INTO v_exp_events FROM ctx WHERE k = 'event_count';

    IF v_cur_events = v_exp_events THEN
        RAISE NOTICE 'PASS: event_log_untouched';
    ELSE
        RAISE EXCEPTION 'FAIL: event_log_untouched (event row count changed from % to %)', v_exp_events, v_cur_events;
    END IF;
END;
$$;

-- Test 9: Owner-only
DO $$
DECLARE
    v_main INT;
    v_dm TEXT;
    v_roles TEXT[] := ARRAY['player_role', 'game_master_role', 'auditor_role'];
    v_role TEXT;
    v_errs INT := 0;
    v_digest TEXT;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_dm FROM ctxt WHERE k = 'Dm';

    FOREACH v_role IN ARRAY v_roles LOOP
        EXECUTE 'SET LOCAL ROLE ' || quote_ident(v_role);

        BEGIN
            EXECUTE format('SELECT rebuild_projections(%s)', v_main);
            RAISE EXCEPTION 'rebuild_projections succeeded unexpectedly for %', v_role;
        EXCEPTION WHEN insufficient_privilege THEN
            v_errs := v_errs + 1;
        END;

        BEGIN
            EXECUTE 'SELECT rebuild_all_projections()';
            RAISE EXCEPTION 'rebuild_all_projections succeeded unexpectedly for %', v_role;
        EXCEPTION WHEN insufficient_privilege THEN
            v_errs := v_errs + 1;
        END;

        BEGIN
            EXECUTE format('SELECT rebuild_world(%s)', v_main);
            RAISE EXCEPTION 'rebuild_world succeeded unexpectedly for %', v_role;
        EXCEPTION WHEN insufficient_privilege THEN
            v_errs := v_errs + 1;
        END;

        IF v_role = 'auditor_role' THEN
            EXECUTE format('SELECT branch_projection_digest(%s)', v_main) INTO v_digest;
            IF v_digest <> v_dm THEN
                EXECUTE 'RESET ROLE';
                RAISE EXCEPTION 'auditor branch_projection_digest mismatch (expected %, got %)', v_dm, v_digest;
            END IF;
        END IF;

        EXECUTE 'RESET ROLE';
    END LOOP;

    IF v_errs = 9 THEN
        RAISE NOTICE 'PASS: owner_only';
    ELSE
        RAISE EXCEPTION 'FAIL: owner_only (caught % of 9 expected privilege errors)', v_errs;
    END IF;
END;
$$;

-- Test 10: Errors
DO $$
DECLARE
    v_caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        PERFORM rebuild_projections(999999);
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%unknown branch%' THEN
            v_caught := TRUE;
        ELSE
            RAISE EXCEPTION 'FAIL: errors (unexpected error message: %)', SQLERRM;
        END IF;
    END;

    IF v_caught THEN
        RAISE NOTICE 'PASS: errors';
    ELSE
        RAISE EXCEPTION 'FAIL: errors (rebuild_projections(999999) did not raise exception)';
    END IF;
END;
$$;

ROLLBACK;

-- Test Suite 08: Branching (Parallel Villages)

BEGIN;

CREATE TEMP TABLE ctx (
    k TEXT PRIMARY KEY,
    v BIGINT
);

CREATE TEMP TABLE ctxt (
    k TEXT PRIMARY KEY,
    v TEXT
);

-- Setup: S1, S2, S3 (no PASS output)
DO $$
DECLARE
    v_main INT;
    v_test_a INT;
    v_test_b INT;
    v_maren INT;
    v_bakery INT;
    v_bread INT;
    v_steal_id BIGINT;
    v_H0 BIGINT;
    v_D0 TEXT;
    v_H1 BIGINT;
    v_D1 TEXT;
    v_H2 BIGINT;
    v_D2 TEXT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    INSERT INTO ctx (k, v) VALUES ('main', v_main);

    SELECT place_id INTO v_bakery FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread FROM item WHERE name = 'bread';
    SELECT actor_id INTO v_maren FROM actor WHERE name = 'Maren';
    INSERT INTO ctx (k, v) VALUES ('bakery', v_bakery), ('bread', v_bread), ('maren', v_maren);

    -- S1: test_a joins and steals 1 bread
    v_test_a := join_village(v_main, 'test_a');
    v_steal_id := apply_action(
        v_main,
        v_test_a,
        'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 1)
    );
    INSERT INTO ctx (k, v) VALUES ('test_a', v_test_a), ('steal_id', v_steal_id);

    SELECT max(event_id) INTO v_H0 FROM event WHERE branch_id = v_main;
    v_D0 := branch_state_digest(v_main);
    INSERT INTO ctx (k, v) VALUES ('H0', v_H0);
    INSERT INTO ctxt (k, v) VALUES ('D0', v_D0);

    -- S2: advance to tick 1; test_b joins and trades 1 bread with Maren; snapshot
    PERFORM advance_day(v_main);

    v_test_b := join_village(v_main, 'test_b');
    INSERT INTO ctx (k, v) VALUES ('test_b', v_test_b);

    PERFORM apply_action(
        v_main,
        v_test_b,
        'trade',
        jsonb_build_object(
            'place_id', v_bakery,
            'item_id', v_bread,
            'qty', 1,
            'target_actor', v_maren
        )
    );

    SELECT max(event_id) INTO v_H1 FROM event WHERE branch_id = v_main;
    v_D1 := branch_state_digest(v_main);
    INSERT INTO ctx (k, v) VALUES ('H1', v_H1);
    INSERT INTO ctxt (k, v) VALUES ('D1', v_D1);

    PERFORM create_snapshot(v_main);

    -- S3: advance to tick 2
    PERFORM advance_day(v_main);

    SELECT max(event_id) INTO v_H2 FROM event WHERE branch_id = v_main;
    v_D2 := branch_state_digest(v_main);
    INSERT INTO ctx (k, v) VALUES ('H2', v_H2);
    INSERT INTO ctxt (k, v) VALUES ('D2', v_D2);
END;
$$;

-- 1. Snapshots
DO $$
DECLARE
    v_main INT;
    v_count INT;
    v_valid_keys BOOLEAN;
    v_raised BOOLEAN := false;
    v_count_after INT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';

    SELECT count(*) INTO v_count
    FROM snapshot
    WHERE branch_id = v_main;

    SELECT bool_and(state ? 'stock' AND state ? 'entities' AND state ? 'pending')
    INTO v_valid_keys
    FROM snapshot
    WHERE branch_id = v_main;

    -- Rolling back the nested block on unique_violation reverts the first snapshot call, keeping later tests unaffected.
    BEGIN
        PERFORM create_snapshot(v_main);
        PERFORM create_snapshot(v_main);
    EXCEPTION WHEN unique_violation THEN
        v_raised := true;
    END;

    SELECT count(*) INTO v_count_after
    FROM snapshot
    WHERE branch_id = v_main;

    IF v_count = 2 AND v_valid_keys AND v_raised AND v_count_after = 2 THEN
        RAISE NOTICE 'PASS: snapshots';
    ELSE
        RAISE EXCEPTION 'FAIL: snapshots (count=%, valid_keys=%, raised=%, after=%)',
            v_count, v_valid_keys, v_raised, v_count_after;
    END IF;
END;
$$;

-- 2. Digest
DO $$
DECLARE
    v_main INT;
    v_D0 TEXT;
    v_D2 TEXT;
    v_d_call1 TEXT;
    v_d_call2 TEXT;
    v_d_base TEXT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_D0 FROM ctxt WHERE k = 'D0';
    SELECT v INTO v_D2 FROM ctxt WHERE k = 'D2';

    v_d_call1 := branch_state_digest(v_main);
    v_d_call2 := branch_state_digest(v_main);

    SELECT encode(digest(state::text, 'sha256'), 'hex') INTO v_d_base
    FROM snapshot
    WHERE branch_id = v_main AND tick = 0;

    IF v_d_call1 = v_d_call2
       AND v_d_call1 = v_D2
       AND v_D2 <> v_D0
       AND v_D2 <> v_d_base THEN
        RAISE NOTICE 'PASS: digest';
    ELSE
        RAISE EXCEPTION 'FAIL: digest (call1=%, call2=%, D2=%, D0=%, base=%)',
            v_d_call1, v_d_call2, v_D2, v_D0, v_d_base;
    END IF;
END;
$$;

-- 3. Fork at the head (H2) with all three strategies
DO $$
DECLARE
    v_main INT;
    v_H2 BIGINT;
    v_D2 TEXT;
    v_c_rep INT;
    v_c_snap INT;
    v_c_cow INT;
    v_d_rep TEXT;
    v_d_snap TEXT;
    v_d_cow TEXT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_H2 FROM ctx WHERE k = 'H2';
    SELECT v INTO v_D2 FROM ctxt WHERE k = 'D2';

    v_c_rep := fork_branch(v_main, v_H2, 'test_head_replay', 'replay');
    v_c_snap := fork_branch(v_main, v_H2, 'test_head_snap', 'snapshot_delta');
    v_c_cow := fork_branch(v_main, v_H2, 'test_head_cow', 'cow');

    v_d_rep := branch_state_digest(v_c_rep);
    v_d_snap := branch_state_digest(v_c_snap);
    v_d_cow := branch_state_digest(v_c_cow);

    IF v_d_rep = v_D2 AND v_d_snap = v_D2 AND v_d_cow = v_D2 THEN
        RAISE NOTICE 'PASS: fork at head with all three strategies';
    ELSE
        RAISE EXCEPTION 'FAIL: fork at head (d_rep=%, d_snap=%, d_cow=%, expected=%)',
            v_d_rep, v_d_snap, v_d_cow, v_D2;
    END IF;
END;
$$;

-- 4. Fork in the PAST at H0
DO $$
DECLARE
    v_main INT;
    v_H0 BIGINT;
    v_D0 TEXT;
    v_D2 TEXT;
    v_c_rep INT;
    v_c_snap INT;
    v_d_rep TEXT;
    v_d_snap TEXT;
    v_h0_tick INT;
    v_tick_rep INT;
    v_tick_snap INT;
    v_sched_rep INT;
    v_sched_snap INT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_H0 FROM ctx WHERE k = 'H0';
    SELECT v INTO v_D0 FROM ctxt WHERE k = 'D0';
    SELECT v INTO v_D2 FROM ctxt WHERE k = 'D2';

    SELECT tick INTO v_h0_tick FROM event WHERE event_id = v_H0;

    v_c_rep := fork_branch(v_main, v_H0, 'test_past0_replay', 'replay');
    v_c_snap := fork_branch(v_main, v_H0, 'test_past0_snap', 'snapshot_delta');

    v_d_rep := branch_state_digest(v_c_rep);
    v_d_snap := branch_state_digest(v_c_snap);

    v_tick_rep := current_tick(v_c_rep);
    v_tick_snap := current_tick(v_c_snap);

    SELECT count(*) INTO v_sched_rep FROM scheduled_effect WHERE branch_id = v_c_rep AND NOT processed;
    SELECT count(*) INTO v_sched_snap FROM scheduled_effect WHERE branch_id = v_c_snap AND NOT processed;

    IF v_d_rep = v_D0 AND v_d_snap = v_D0
       AND v_d_rep <> v_D2 AND v_d_snap <> v_D2
       AND v_tick_rep = v_h0_tick AND v_tick_snap = v_h0_tick
       AND v_sched_rep = 1 AND v_sched_snap = 1 THEN
        RAISE NOTICE 'PASS: fork in the past at H0';
    ELSE
        RAISE EXCEPTION 'FAIL: fork in the past at H0 (d_rep=%, d_snap=%, D0=%, tick_rep=%, tick_snap=%, h0_tick=%, sched_rep=%, sched_snap=%)',
            v_d_rep, v_d_snap, v_D0, v_tick_rep, v_tick_snap, v_h0_tick, v_sched_rep, v_sched_snap;
    END IF;
END;
$$;

-- 5. Fork in the PAST at H1
DO $$
DECLARE
    v_main INT;
    v_H1 BIGINT;
    v_D1 TEXT;
    v_c_snap INT;
    v_c_rep INT;
    v_d_snap TEXT;
    v_d_rep TEXT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_H1 FROM ctx WHERE k = 'H1';
    SELECT v INTO v_D1 FROM ctxt WHERE k = 'D1';

    v_c_snap := fork_branch(v_main, v_H1, 'test_past1_snap', 'snapshot_delta');
    v_c_rep := fork_branch(v_main, v_H1, 'test_past1_replay', 'replay');

    v_d_snap := branch_state_digest(v_c_snap);
    v_d_rep := branch_state_digest(v_c_rep);

    IF v_d_snap = v_D1 AND v_d_rep = v_D1 THEN
        RAISE NOTICE 'PASS: fork in the past at H1';
    ELSE
        RAISE EXCEPTION 'FAIL: fork in the past at H1 (d_snap=%, d_rep=%, expected=%)',
            v_d_snap, v_d_rep, v_D1;
    END IF;
END;
$$;

-- 6. COW at a past event raises 'latest event'
DO $$
DECLARE
    v_main INT;
    v_H1 BIGINT;
    v_b_before INT;
    v_b_after INT;
    v_raised BOOLEAN := FALSE;
    v_msg TEXT := '';
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_H1 FROM ctx WHERE k = 'H1';

    SELECT count(*) INTO v_b_before FROM branch;

    BEGIN
        PERFORM fork_branch(v_main, v_H1, 'test_cow_fail', 'cow');
    EXCEPTION WHEN OTHERS THEN
        v_raised := TRUE;
        v_msg := SQLERRM;
    END;

    SELECT count(*) INTO v_b_after FROM branch;

    IF v_raised AND v_msg LIKE '%latest event%' AND v_b_before = v_b_after THEN
        RAISE NOTICE 'PASS: cow at past event rejected';
    ELSE
        RAISE EXCEPTION 'FAIL: cow at past event (raised=%, msg=%, before=%, after=%)',
            v_raised, v_msg, v_b_before, v_b_after;
    END IF;
END;
$$;

-- 7. Validation
DO $$
DECLARE
    v_main INT;
    v_H2 BIGINT;
    v_c_rep INT;
    v_foreign_ev BIGINT;
    v_b_before INT;
    v_b_after INT;
    v_raised1 BOOLEAN := FALSE;
    v_raised2 BOOLEAN := FALSE;
    v_msg1 TEXT := '';
    v_msg2 TEXT := '';
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_H2 FROM ctx WHERE k = 'H2';
    SELECT branch_id INTO v_c_rep FROM branch WHERE name = 'test_head_replay';
    SELECT min(event_id) INTO v_foreign_ev FROM event WHERE branch_id = v_c_rep;

    SELECT count(*) INTO v_b_before FROM branch;

    BEGIN
        PERFORM fork_branch(v_main, v_H2, 'test_bogus', 'bogus');
    EXCEPTION WHEN OTHERS THEN
        v_raised1 := TRUE;
        v_msg1 := SQLERRM;
    END;

    BEGIN
        PERFORM fork_branch(v_main, v_foreign_ev, 'test_foreign', 'replay');
    EXCEPTION WHEN OTHERS THEN
        v_raised2 := TRUE;
        v_msg2 := SQLERRM;
    END;

    SELECT count(*) INTO v_b_after FROM branch;

    IF v_raised1 AND v_msg1 LIKE '%unknown strategy%'
       AND v_raised2 AND v_msg2 LIKE '%must belong to the parent%'
       AND v_b_before = v_b_after THEN
        RAISE NOTICE 'PASS: fork validation';
    ELSE
        RAISE EXCEPTION 'FAIL: fork validation (r1=%, msg1=%, r2=%, msg2=%, before=%, after=%)',
            v_raised1, v_msg1, v_raised2, v_msg2, v_b_before, v_b_after;
    END IF;
END;
$$;

-- 8. Isolation
DO $$
DECLARE
    v_main INT;
    v_c_cow INT;
    v_test_b INT;
    v_bakery INT;
    v_bread INT;
    v_D2 TEXT;
    v_main_bread_before INT;
    v_child_bread_before INT;
    v_main_events_before INT;
    v_main_bread_after INT;
    v_child_bread_after INT;
    v_main_events_after INT;
    v_main_digest_after TEXT;
    v_child_digest_after TEXT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_test_b FROM ctx WHERE k = 'test_b';
    SELECT v INTO v_bakery FROM ctx WHERE k = 'bakery';
    SELECT v INTO v_bread FROM ctx WHERE k = 'bread';
    SELECT v INTO v_D2 FROM ctxt WHERE k = 'D2';

    SELECT branch_id INTO v_c_cow FROM branch WHERE name = 'test_head_cow';

    SELECT qty INTO v_main_bread_before FROM stock WHERE branch_id = v_main AND place_id = v_bakery AND item_id = v_bread;
    SELECT qty INTO v_child_bread_before FROM stock WHERE branch_id = v_c_cow AND place_id = v_bakery AND item_id = v_bread;
    SELECT count(*) INTO v_main_events_before FROM event WHERE branch_id = v_main;

    -- In child 'test_head_cow', test_b steals 2 bread
    PERFORM apply_action(
        v_c_cow,
        v_test_b,
        'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 2)
    );

    SELECT qty INTO v_main_bread_after FROM stock WHERE branch_id = v_main AND place_id = v_bakery AND item_id = v_bread;
    SELECT qty INTO v_child_bread_after FROM stock WHERE branch_id = v_c_cow AND place_id = v_bakery AND item_id = v_bread;
    SELECT count(*) INTO v_main_events_after FROM event WHERE branch_id = v_main;

    v_main_digest_after := branch_state_digest(v_main);
    v_child_digest_after := branch_state_digest(v_c_cow);

    IF v_child_bread_after = v_child_bread_before - 2
       AND v_main_bread_after = v_main_bread_before
       AND v_main_digest_after = v_D2
       AND v_child_digest_after <> v_D2
       AND v_main_events_after = v_main_events_before THEN
        RAISE NOTICE 'PASS: branch isolation';
    ELSE
        RAISE EXCEPTION 'FAIL: branch isolation (c_bread=%, m_bread=%, m_events_diff=%, m_dig=%, c_dig=%)',
            v_child_bread_after - v_child_bread_before,
            v_main_bread_after - v_main_bread_before,
            v_main_events_after - v_main_events_before,
            v_main_digest_after = v_D2,
            v_child_digest_after = v_D2;
    END IF;
END;
$$;

-- 9. Cross-branch causality
DO $$
DECLARE
    v_main INT;
    v_c_p0_rep INT;
    v_steal_id BIGINT;
    v_main_events_before INT;
    v_main_events_after INT;
    v_sp_ev event;
    v_cause_id BIGINT;
    v_root_actor TEXT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_steal_id FROM ctx WHERE k = 'steal_id';
    SELECT branch_id INTO v_c_p0_rep FROM branch WHERE name = 'test_past0_replay';

    SELECT count(*) INTO v_main_events_before FROM event WHERE branch_id = v_main;

    PERFORM advance_day(v_c_p0_rep);

    SELECT count(*) INTO v_main_events_after FROM event WHERE branch_id = v_main;

    SELECT * INTO v_sp_ev
    FROM event
    WHERE branch_id = v_c_p0_rep AND action_type = 'set_price';

    SELECT cause_id INTO v_cause_id
    FROM event_cause
    WHERE effect_id = v_sp_ev.event_id;

    SELECT actor_name INTO v_root_actor
    FROM ask_why(v_sp_ev.event_id)
    WHERE step = 1;

    IF v_main_events_after = v_main_events_before
       AND v_sp_ev.branch_id = v_c_p0_rep
       AND v_cause_id = v_steal_id
       AND v_root_actor = 'test_a' THEN
        RAISE NOTICE 'PASS: cross-branch causality';
    ELSE
        RAISE EXCEPTION 'FAIL: cross-branch causality (main_ev_diff=%, sp_branch=%, cause=%, steal=%, root_actor=%)',
            v_main_events_after - v_main_events_before, v_sp_ev.branch_id, v_cause_id, v_steal_id, v_root_actor;
    END IF;
END;
$$;

-- 10. Scores (same-branch descendant counting)
DO $$
DECLARE
    v_main INT;
    v_steal_id BIGINT;
    v_score INT;
    v_direct_score INT;
    v_vas_score INT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_steal_id FROM ctx WHERE k = 'steal_id';

    v_score := butterfly_score(v_steal_id);

    SELECT count(*) INTO v_direct_score
    FROM causal_closure cc
    JOIN event ed ON ed.event_id = cc.descendant_id
    WHERE cc.ancestor_id = v_steal_id
      AND cc.depth > 0
      AND ed.branch_id = v_main;

    SELECT score INTO v_vas_score
    FROM v_action_scores
    WHERE event_id = v_steal_id AND branch_id = v_main;

    IF v_score = v_direct_score AND v_vas_score = v_direct_score THEN
        RAISE NOTICE 'PASS: butterfly score same-branch rule';
    ELSE
        RAISE EXCEPTION 'FAIL: butterfly score same-branch rule (score=%, direct=%, vas=%)',
            v_score, v_direct_score, v_vas_score;
    END IF;
END;
$$;

-- 11. branch_diff
DO $$
DECLARE
    v_main INT;
    v_c_rep INT;
    v_c_cow INT;
    v_diff_rep_cnt INT;
    v_stock_diff_cnt INT;
    v_entity_diff_cnt INT;
BEGIN
    SELECT v INTO v_main FROM ctx WHERE k = 'main';
    SELECT branch_id INTO v_c_rep FROM branch WHERE name = 'test_head_replay';
    SELECT branch_id INTO v_c_cow FROM branch WHERE name = 'test_head_cow';

    SELECT count(*) INTO v_diff_rep_cnt
    FROM branch_diff(v_main, v_c_rep);

    SELECT count(*) INTO v_stock_diff_cnt
    FROM branch_diff(v_main, v_c_cow)
    WHERE kind = 'stock';

    SELECT count(*) INTO v_entity_diff_cnt
    FROM branch_diff(v_main, v_c_cow)
    WHERE kind = 'entity';

    IF v_diff_rep_cnt = 0 AND v_stock_diff_cnt >= 1 AND v_entity_diff_cnt >= 1 THEN
        RAISE NOTICE 'PASS: branch diff';
    ELSE
        RAISE EXCEPTION 'FAIL: branch diff (rep_cnt=%, stock_diff=%, entity_diff=%)',
            v_diff_rep_cnt, v_stock_diff_cnt, v_entity_diff_cnt;
    END IF;
END;
$$;

-- 12. Integrity checks
DO $$
DECLARE
    v_chain_errs INT;
    v_causal_errs INT;
    v_fork_missing INT;
BEGIN
    SELECT count(*) INTO v_chain_errs FROM verify_event_chain();
    SELECT count(*) INTO v_causal_errs FROM verify_causal_structures();

    SELECT count(*) INTO v_fork_missing
    FROM branch b
    WHERE b.parent_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM event e
          WHERE e.branch_id = b.branch_id
            AND e.event_id = (SELECT min(event_id) FROM event WHERE branch_id = b.branch_id)
            AND e.action_type = 'world_start'
            AND (e.payload->>'fork_of')::int = b.parent_id
      );

    IF v_chain_errs = 0 AND v_causal_errs = 0 AND v_fork_missing = 0 THEN
        RAISE NOTICE 'PASS: integrity';
    ELSE
        RAISE EXCEPTION 'FAIL: integrity (chain_errs=%, causal_errs=%, fork_missing=%)',
            v_chain_errs, v_causal_errs, v_fork_missing;
    END IF;
END;
$$;

ROLLBACK;

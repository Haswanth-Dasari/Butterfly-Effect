-- Test Suite 07: Ask Why Layer (Causal closure, materialized paths, provenance, and daily views)

BEGIN;

CREATE TEMP TABLE ctx (
    k TEXT PRIMARY KEY,
    v BIGINT
);

-- Setup: register thief, steal bread from bakery, advance day twice to tick 2 (reproducing ripple)
DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_bakery_id INT;
    v_bread_id INT;
    v_steal_id BIGINT;
    v_set_price_id BIGINT;
    v_sc_id BIGINT;
    v_rumor_id BIGINT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;
    INSERT INTO ctx (k, v) VALUES ('branch_id', v_branch_id);

    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';

    v_thief_id := join_village(v_branch_id, 'test_thief');
    INSERT INTO ctx (k, v) VALUES ('thief_id', v_thief_id);

    v_steal_id := apply_action(
        v_branch_id,
        v_thief_id,
        'steal',
        jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 1)
    );
    INSERT INTO ctx (k, v) VALUES ('steal_id', v_steal_id);

    PERFORM advance_day(v_branch_id); -- tick 1

    SELECT e.event_id INTO v_set_price_id
    FROM event e
    JOIN event_cause ec ON ec.effect_id = e.event_id
    WHERE e.branch_id = v_branch_id
      AND e.tick = 1
      AND e.action_type = 'set_price'
      AND ec.cause_id = v_steal_id;
    INSERT INTO ctx (k, v) VALUES ('set_price_id', v_set_price_id);

    PERFORM advance_day(v_branch_id); -- tick 2

    SELECT e.event_id INTO v_sc_id
    FROM event e
    JOIN event_cause ec ON ec.effect_id = e.event_id
    WHERE e.branch_id = v_branch_id
      AND e.tick = 2
      AND e.action_type = 'state_change'
      AND ec.cause_id = v_set_price_id;
    INSERT INTO ctx (k, v) VALUES ('state_change_id', v_sc_id);

    SELECT e.event_id INTO v_rumor_id
    FROM event e
    JOIN event_cause ec ON ec.effect_id = e.event_id
    WHERE e.branch_id = v_branch_id
      AND e.tick = 2
      AND e.action_type = 'rumor'
      AND ec.cause_id = v_sc_id;
    INSERT INTO ctx (k, v) VALUES ('rumor_id', v_rumor_id);
END;
$$;

-- 1. Closure maintained by trigger
DO $$
DECLARE
    v_s BIGINT; v_sp BIGINT; v_sc BIGINT; v_r BIGINT;
    v_count INT;
    v_d_s_sp INT; v_d_s_sc INT; v_d_s_r INT;
    v_d_sp_sc INT; v_d_sp_r INT; v_d_sc_r INT;
    v_self_s INT; v_self_sp INT; v_self_sc INT; v_self_r INT;
BEGIN
    SELECT v INTO v_s FROM ctx WHERE k = 'steal_id';
    SELECT v INTO v_sp FROM ctx WHERE k = 'set_price_id';
    SELECT v INTO v_sc FROM ctx WHERE k = 'state_change_id';
    SELECT v INTO v_r FROM ctx WHERE k = 'rumor_id';

    SELECT count(*) INTO v_count
    FROM causal_closure
    WHERE ancestor_id IN (v_s, v_sp, v_sc, v_r)
      AND descendant_id IN (v_s, v_sp, v_sc, v_r)
      AND depth > 0;

    SELECT depth INTO v_d_s_sp FROM causal_closure WHERE ancestor_id = v_s AND descendant_id = v_sp;
    SELECT depth INTO v_d_s_sc FROM causal_closure WHERE ancestor_id = v_s AND descendant_id = v_sc;
    SELECT depth INTO v_d_s_r FROM causal_closure WHERE ancestor_id = v_s AND descendant_id = v_r;
    SELECT depth INTO v_d_sp_sc FROM causal_closure WHERE ancestor_id = v_sp AND descendant_id = v_sc;
    SELECT depth INTO v_d_sp_r FROM causal_closure WHERE ancestor_id = v_sp AND descendant_id = v_r;
    SELECT depth INTO v_d_sc_r FROM causal_closure WHERE ancestor_id = v_sc AND descendant_id = v_r;

    SELECT depth INTO v_self_s FROM causal_closure WHERE ancestor_id = v_s AND descendant_id = v_s;
    SELECT depth INTO v_self_sp FROM causal_closure WHERE ancestor_id = v_sp AND descendant_id = v_sp;
    SELECT depth INTO v_self_sc FROM causal_closure WHERE ancestor_id = v_sc AND descendant_id = v_sc;
    SELECT depth INTO v_self_r FROM causal_closure WHERE ancestor_id = v_r AND descendant_id = v_r;

    IF v_count = 6
       AND v_d_s_sp = 1 AND v_d_s_sc = 2 AND v_d_s_r = 3
       AND v_d_sp_sc = 1 AND v_d_sp_r = 2 AND v_d_sc_r = 1
       AND v_self_s = 0 AND v_self_sp = 0 AND v_self_sc = 0 AND v_self_r = 0 THEN
        RAISE NOTICE 'PASS: closure maintained by the trigger';
    ELSE
        RAISE EXCEPTION 'FAIL: closure maintained by the trigger (count=%, s_sp=%, s_sc=%, s_r=%, sp_sc=%, sp_r=%, sc_r=%)',
            v_count, v_d_s_sp, v_d_s_sc, v_d_s_r, v_d_sp_sc, v_d_sp_r, v_d_sc_r;
    END IF;
END;
$$;

-- 2. causal_path of the rumor event
DO $$
DECLARE
    v_s BIGINT; v_sp BIGINT; v_sc BIGINT; v_r BIGINT;
    v_path TEXT;
    v_expected TEXT;
BEGIN
    SELECT v INTO v_s FROM ctx WHERE k = 'steal_id';
    SELECT v INTO v_sp FROM ctx WHERE k = 'set_price_id';
    SELECT v INTO v_sc FROM ctx WHERE k = 'state_change_id';
    SELECT v INTO v_r FROM ctx WHERE k = 'rumor_id';

    SELECT path INTO v_path FROM causal_path WHERE event_id = v_r;
    v_expected := v_s || '/' || v_sp || '/' || v_sc || '/' || v_r;

    IF v_path = v_expected THEN
        RAISE NOTICE 'PASS: causal_path of rumor event';
    ELSE
        RAISE EXCEPTION 'FAIL: causal_path of rumor event (actual=%, expected=%)', v_path, v_expected;
    END IF;
END;
$$;

-- 3. Parity of why_ids_cte, why_ids_closure, and why_ids_path
DO $$
DECLARE
    v_s BIGINT; v_sp BIGINT; v_sc BIGINT; v_r BIGINT;
    v_cte_diff INT;
    v_closure_diff INT;
    v_path_diff INT;
BEGIN
    SELECT v INTO v_s FROM ctx WHERE k = 'steal_id';
    SELECT v INTO v_sp FROM ctx WHERE k = 'set_price_id';
    SELECT v INTO v_sc FROM ctx WHERE k = 'state_change_id';
    SELECT v INTO v_r FROM ctx WHERE k = 'rumor_id';

    WITH expected(event_id, depth) AS (
        VALUES (v_s, 3), (v_sp, 2), (v_sc, 1)
    )
    SELECT count(*) INTO v_cte_diff
    FROM (
        (SELECT event_id, depth FROM why_ids_cte(v_r) EXCEPT SELECT event_id, depth FROM expected)
        UNION ALL
        (SELECT event_id, depth FROM expected EXCEPT SELECT event_id, depth FROM why_ids_cte(v_r))
    ) d;

    WITH expected(event_id, depth) AS (
        VALUES (v_s, 3), (v_sp, 2), (v_sc, 1)
    )
    SELECT count(*) INTO v_closure_diff
    FROM (
        (SELECT event_id, depth FROM why_ids_closure(v_r) EXCEPT SELECT event_id, depth FROM expected)
        UNION ALL
        (SELECT event_id, depth FROM expected EXCEPT SELECT event_id, depth FROM why_ids_closure(v_r))
    ) d;

    WITH expected(event_id, depth) AS (
        VALUES (v_s, 3), (v_sp, 2), (v_sc, 1)
    )
    SELECT count(*) INTO v_path_diff
    FROM (
        (SELECT event_id, depth FROM why_ids_path(v_r) EXCEPT SELECT event_id, depth FROM expected)
        UNION ALL
        (SELECT event_id, depth FROM expected EXCEPT SELECT event_id, depth FROM why_ids_path(v_r))
    ) d;

    IF v_cte_diff = 0 AND v_closure_diff = 0 AND v_path_diff = 0 THEN
        RAISE NOTICE 'PASS: why_ids functions parity';
    ELSE
        RAISE EXCEPTION 'FAIL: why_ids functions parity (cte_diff=%, closure_diff=%, path_diff=%)',
            v_cte_diff, v_closure_diff, v_path_diff;
    END IF;
END;
$$;

-- 4. ask_why chronicle
DO $$
DECLARE
    v_r BIGINT;
    v_narr_steal TEXT; v_narr_sp TEXT; v_narr_sc TEXT;
    r1 RECORD; r2 RECORD; r3 RECORD; r4 RECORD;
BEGIN
    SELECT v INTO v_r FROM ctx WHERE k = 'rumor_id';

    SELECT narrative_template INTO v_narr_steal FROM rule WHERE trigger_action_type = 'steal' AND delay_ticks = 1;
    SELECT narrative_template INTO v_narr_sp FROM rule WHERE trigger_action_type = 'set_price' AND delay_ticks = 1;
    SELECT narrative_template INTO v_narr_sc FROM rule WHERE trigger_action_type = 'state_change' AND delay_ticks = 0;

    SELECT * INTO r1 FROM ask_why(v_r) WHERE step = 1;
    SELECT * INTO r2 FROM ask_why(v_r) WHERE step = 2;
    SELECT * INTO r3 FROM ask_why(v_r) WHERE step = 3;
    SELECT * INTO r4 FROM ask_why(v_r) WHERE step = 4;

    IF r1.depth = 3 AND r1.action_type = 'steal' AND r1.actor_name = 'test_thief' AND r1.narrative = v_narr_steal
       AND r2.depth = 2 AND r2.action_type = 'set_price' AND r2.narrative = v_narr_sp
       AND r3.depth = 1 AND r3.action_type = 'state_change' AND r3.narrative = v_narr_sc
       AND r4.depth = 0 AND r4.action_type = 'rumor' AND r4.narrative IS NULL AND r4.rule_id IS NULL THEN
        RAISE NOTICE 'PASS: ask_why chronicle';
    ELSE
        RAISE EXCEPTION 'FAIL: ask_why chronicle (r1=%, r2=%, r3=%, r4=%)', r1, r2, r3, r4;
    END IF;
END;
$$;

-- 5. butterfly_score
DO $$
DECLARE
    v_s BIGINT; v_sp BIGINT; v_sc BIGINT; v_r BIGINT;
    v_b_s INT; v_b_sp INT; v_b_sc INT; v_b_r INT;
BEGIN
    SELECT v INTO v_s FROM ctx WHERE k = 'steal_id';
    SELECT v INTO v_sp FROM ctx WHERE k = 'set_price_id';
    SELECT v INTO v_sc FROM ctx WHERE k = 'state_change_id';
    SELECT v INTO v_r FROM ctx WHERE k = 'rumor_id';

    v_b_s := butterfly_score(v_s);
    v_b_sp := butterfly_score(v_sp);
    v_b_sc := butterfly_score(v_sc);
    v_b_r := butterfly_score(v_r);

    IF v_b_s = 3 AND v_b_sp = 2 AND v_b_sc = 1 AND v_b_r = 0 THEN
        RAISE NOTICE 'PASS: butterfly_score';
    ELSE
        RAISE EXCEPTION 'FAIL: butterfly_score (steal=%, set_price=%, state_change=%, rumor=%)',
            v_b_s, v_b_sp, v_b_sc, v_b_r;
    END IF;
END;
$$;

-- 6. DAG maintenance
DO $$
DECLARE
    v_s BIGINT; v_sp BIGINT; v_sc BIGINT; v_r BIGINT;
    v_depth INT;
    v_diff INT;
    v_score INT;
    v_path TEXT;
    v_expected_path TEXT;
BEGIN
    SELECT v INTO v_s FROM ctx WHERE k = 'steal_id';
    SELECT v INTO v_sp FROM ctx WHERE k = 'set_price_id';
    SELECT v INTO v_sc FROM ctx WHERE k = 'state_change_id';
    SELECT v INTO v_r FROM ctx WHERE k = 'rumor_id';

    -- Insert shortcut edge
    INSERT INTO event_cause (cause_id, effect_id, rule_id)
    VALUES (v_s, v_r, NULL);

    SELECT depth INTO v_depth FROM causal_closure WHERE ancestor_id = v_s AND descendant_id = v_r;

    SELECT count(*) INTO v_diff
    FROM (
        (SELECT event_id, depth FROM why_ids_cte(v_r) EXCEPT SELECT event_id, depth FROM why_ids_closure(v_r))
        UNION ALL
        (SELECT event_id, depth FROM why_ids_closure(v_r) EXCEPT SELECT event_id, depth FROM why_ids_cte(v_r))
    ) d;

    v_score := butterfly_score(v_s);

    SELECT path INTO v_path FROM causal_path WHERE event_id = v_r;
    v_expected_path := v_s || '/' || v_sp || '/' || v_sc || '/' || v_r;

    IF v_depth = 1 AND v_diff = 0 AND v_score = 3 AND v_path = v_expected_path THEN
        RAISE NOTICE 'PASS: DAG maintenance';
    ELSE
        RAISE EXCEPTION 'FAIL: DAG maintenance (depth=%, diff=%, score=%, path=%, expected=%)',
            v_depth, v_diff, v_score, v_path, v_expected_path;
    END IF;
END;
$$;

-- 7. verify_causal_structures after DAG
DO $$
DECLARE
    v_err_count INT;
BEGIN
    SELECT count(*) INTO v_err_count FROM verify_causal_structures();

    IF v_err_count = 0 THEN
        RAISE NOTICE 'PASS: verify_causal_structures';
    ELSE
        RAISE EXCEPTION 'FAIL: verify_causal_structures (err_count=%)', v_err_count;
    END IF;
END;
$$;

-- 8. Repair and rebuild causal structures
DO $$
DECLARE
    v_s BIGINT; v_sp BIGINT;
    v_count_before INT;
    v_errs_corrupt INT;
    v_errs_rebuilt INT;
    v_count_after INT;
BEGIN
    SELECT v INTO v_s FROM ctx WHERE k = 'steal_id';
    SELECT v INTO v_sp FROM ctx WHERE k = 'set_price_id';

    SELECT count(*) INTO v_count_before FROM causal_closure;

    DELETE FROM causal_closure WHERE ancestor_id = v_s AND descendant_id = v_sp;
    UPDATE causal_path SET path = 'broken' WHERE event_id = v_sp;

    SELECT count(*) INTO v_errs_corrupt FROM verify_causal_structures();

    PERFORM rebuild_causal_structures();

    SELECT count(*) INTO v_errs_rebuilt FROM verify_causal_structures();
    SELECT count(*) INTO v_count_after FROM causal_closure;

    IF v_errs_corrupt >= 2 AND v_errs_rebuilt = 0 AND v_count_after = v_count_before THEN
        RAISE NOTICE 'PASS: repair and rebuild';
    ELSE
        RAISE EXCEPTION 'FAIL: repair and rebuild (errs_corrupt=%, errs_rebuilt=%, count_before=%, count_after=%)',
            v_errs_corrupt, v_errs_rebuilt, v_count_before, v_count_after;
    END IF;
END;
$$;

-- 9. Views (action scores and ranking)
DO $$
DECLARE
    v_branch_id INT;
    v_helper_id INT;
    v_builder_id INT;
    v_farm_id INT;
    v_help_event_id BIGINT;
    v_s_row RECORD;
    v_h_row RECORD;
    v_arrive_count INT;
BEGIN
    SELECT v INTO v_branch_id FROM ctx WHERE k = 'branch_id';

    v_helper_id := join_village(v_branch_id, 'test_helper');
    INSERT INTO ctx (k, v) VALUES ('helper_id', v_helper_id);

    v_builder_id := join_village(v_branch_id, 'test_builder');
    INSERT INTO ctx (k, v) VALUES ('builder_id', v_builder_id);

    SELECT place_id INTO v_farm_id FROM place WHERE name = 'Hartley Farm';

    v_help_event_id := apply_action(
        v_branch_id,
        v_helper_id,
        'help_harvest',
        jsonb_build_object('place_id', v_farm_id, 'qty', 1)
    );
    INSERT INTO ctx (k, v) VALUES ('help_event_id', v_help_event_id);

    SELECT * INTO v_s_row FROM v_action_scores WHERE action_type = 'steal' AND branch_id = v_branch_id;
    SELECT * INTO v_h_row FROM v_action_scores WHERE action_type = 'help_harvest' AND branch_id = v_branch_id;

    SELECT count(*) INTO v_arrive_count FROM v_action_scores WHERE action_type = 'arrive';

    IF v_s_row.score = 3 AND v_s_row.score_rank = 1
       AND v_h_row.score = 1 AND v_h_row.score_rank = 2
       AND v_arrive_count = 0 THEN
        RAISE NOTICE 'PASS: action scores views';
    ELSE
        RAISE EXCEPTION 'FAIL: action scores views (s_score=%, s_rank=%, h_score=%, h_rank=%, arrive_cnt=%)',
            v_s_row.score, v_s_row.score_rank, v_h_row.score, v_h_row.score_rank, v_arrive_count;
    END IF;
END;
$$;

-- 10. Materialized views
DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_helper_id INT;
    v_thief_lb RECORD;
    v_helper_lb RECORD;
    v_eb RECORD;
    v_exp_total INT;
    v_exp_cascade INT;
    v_exp_cum INT;
BEGIN
    SELECT v INTO v_branch_id FROM ctx WHERE k = 'branch_id';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';
    SELECT v INTO v_helper_id FROM ctx WHERE k = 'helper_id';

    PERFORM refresh_daily_views();

    SELECT * INTO v_thief_lb FROM mv_leaderboard WHERE branch_id = v_branch_id AND actor_id = v_thief_id;
    SELECT * INTO v_helper_lb FROM mv_leaderboard WHERE branch_id = v_branch_id AND actor_id = v_helper_id;

    SELECT * INTO v_eb FROM mv_evening_bell WHERE branch_id = v_branch_id AND tick = 2;

    SELECT count(*) INTO v_exp_total FROM event WHERE branch_id = v_branch_id AND tick = 2;
    SELECT count(*) INTO v_exp_cascade FROM event e
    WHERE e.branch_id = v_branch_id AND e.tick = 2
      AND EXISTS (SELECT 1 FROM event_cause ec WHERE ec.effect_id = e.event_id);
    SELECT count(*) INTO v_exp_cum FROM event WHERE branch_id = v_branch_id AND tick <= 2;

    IF v_thief_lb.total_score = 3 AND v_thief_lb.leaderboard_rank = 1
       AND v_helper_lb.total_score = 1 AND v_helper_lb.leaderboard_rank = 2
       AND v_eb.events_total = v_exp_total
       AND v_eb.cascade_events = v_exp_cascade
       AND v_eb.events_cumulative = v_exp_cum THEN
        RAISE NOTICE 'PASS: materialized views';
    ELSE
        RAISE EXCEPTION 'FAIL: materialized views (thief=%, helper=%, eb_tot=%, exp_tot=%, eb_casc=%, exp_casc=%, eb_cum=%, exp_cum=%)',
            v_thief_lb, v_helper_lb, v_eb.events_total, v_exp_total, v_eb.cascade_events, v_exp_cascade, v_eb.events_cumulative, v_exp_cum;
    END IF;
END;
$$;

-- 11. Staleness and refresh
DO $$
DECLARE
    v_branch_id INT;
    v_builder_id INT;
    v_rows_before INT;
    v_rows_after INT;
    v_builder_lb RECORD;
BEGIN
    SELECT v INTO v_branch_id FROM ctx WHERE k = 'branch_id';
    SELECT v INTO v_builder_id FROM ctx WHERE k = 'builder_id';

    PERFORM apply_action(
        v_branch_id,
        v_builder_id,
        'build',
        jsonb_build_object('what', 'stall')
    );

    SELECT count(*) INTO v_rows_before FROM mv_leaderboard WHERE branch_id = v_branch_id;

    PERFORM refresh_daily_views();

    SELECT count(*) INTO v_rows_after FROM mv_leaderboard WHERE branch_id = v_branch_id;
    SELECT * INTO v_builder_lb FROM mv_leaderboard WHERE branch_id = v_branch_id AND actor_id = v_builder_id;

    IF v_rows_before = 2
       AND v_rows_after = 3
       AND v_builder_lb.total_score = 0
       AND v_builder_lb.leaderboard_rank = 3 THEN
        RAISE NOTICE 'PASS: staleness and refresh';
    ELSE
        RAISE EXCEPTION 'FAIL: staleness and refresh (before=%, after=%, builder=%)',
            v_rows_before, v_rows_after, v_builder_lb;
    END IF;
END;
$$;

-- 12. Integrity checks
DO $$
DECLARE
    v_branch_id INT;
    v_chain_errors INT;
    v_causal_errors INT;
BEGIN
    SELECT v INTO v_branch_id FROM ctx WHERE k = 'branch_id';

    SELECT count(*) INTO v_chain_errors FROM verify_event_chain(v_branch_id);
    SELECT count(*) INTO v_causal_errors FROM verify_causal_structures();

    IF v_chain_errors = 0 AND v_causal_errors = 0 THEN
        RAISE NOTICE 'PASS: integrity checks';
    ELSE
        RAISE EXCEPTION 'FAIL: integrity checks (chain_errors=%, causal_errors=%)',
            v_chain_errors, v_causal_errors;
    END IF;
END;
$$;

ROLLBACK;

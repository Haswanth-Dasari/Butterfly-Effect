-- Test Suite 09: Database Security, Roles, Row Level Security, and Privileges
BEGIN;

-- Context table shared across role switches
CREATE TEMP TABLE ctx (
    k TEXT PRIMARY KEY,
    v BIGINT
);
GRANT ALL ON ctx TO PUBLIC;

-- Setup as superuser (no output)
DO $$
DECLARE
    v_main INT;
    v_thief INT;
    v_witness INT;
    v_outsider INT;
    v_bakery INT;
    v_bread INT;
    v_steal_id BIGINT;
    v_set_price_id BIGINT;
    v_state_change_id BIGINT;
    v_rumor_id BIGINT;
    v_total_events BIGINT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT place_id INTO v_bakery FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread FROM item WHERE name = 'bread';

    -- join_village for test_thief, test_witness, and test_outsider (BEFORE any day advances)
    v_thief := join_village(v_main, 'test_thief');
    v_witness := join_village(v_main, 'test_witness');
    v_outsider := join_village(v_main, 'test_outsider');

    -- thief steals 1 bread from Maren's Bakery (secret act)
    v_steal_id := apply_action(
        v_main,
        v_thief,
        'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 1)
    );

    -- advance_day twice
    PERFORM advance_day(v_main);
    PERFORM advance_day(v_main);

    -- Locate cascade events
    SELECT event_id INTO v_set_price_id
    FROM event
    WHERE branch_id = v_main AND tick = 1 AND action_type = 'set_price'
    ORDER BY event_id DESC LIMIT 1;

    SELECT event_id INTO v_state_change_id
    FROM event
    WHERE branch_id = v_main AND tick = 2 AND action_type = 'state_change'
    ORDER BY event_id DESC LIMIT 1;

    SELECT event_id INTO v_rumor_id
    FROM event
    WHERE branch_id = v_main AND tick = 2 AND action_type = 'rumor'
    ORDER BY event_id DESC LIMIT 1;

    SELECT count(*) INTO v_total_events FROM event;

    INSERT INTO ctx (k, v) VALUES
        ('main', v_main),
        ('test_thief', v_thief),
        ('test_witness', v_witness),
        ('test_outsider', v_outsider),
        ('steal', v_steal_id),
        ('set_price', v_set_price_id),
        ('state_change', v_state_change_id),
        ('rumor', v_rumor_id),
        ('total_events', v_total_events);
END;
$$;

-- Test 1: Roles exist and are NOLOGIN
DO $$
DECLARE
    v_cnt INT;
BEGIN
    SELECT count(*) INTO v_cnt
    FROM pg_roles
    WHERE rolname IN ('player_role', 'game_master_role', 'auditor_role')
      AND NOT rolcanlogin;

    IF v_cnt = 3 THEN
        RAISE NOTICE 'PASS: roles';
    ELSE
        RAISE EXCEPTION 'FAIL: roles (expected 3 NOLOGIN roles, found %)', v_cnt;
    END IF;
END;
$$;

-- Test 2: RLS enabled on exactly 5 tables with 2 policies each
DO $$
DECLARE
    v_rls_cnt INT;
    v_pol_cnt INT;
BEGIN
    SELECT count(*) INTO v_rls_cnt
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('event', 'event_witness', 'entity_state', 'event_cause', 'causal_closure')
      AND c.relrowsecurity;

    IF v_rls_cnt <> 5 OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relrowsecurity) <> 5 THEN
        RAISE EXCEPTION 'FAIL: rls (relrowsecurity not set on exactly the 5 tables)';
    END IF;

    SELECT count(*) INTO v_pol_cnt
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('event', 'event_witness', 'entity_state', 'event_cause', 'causal_closure');

    IF v_pol_cnt = 10 AND (SELECT count(*) FROM pg_policies WHERE schemaname = 'public') = 10 THEN
        RAISE NOTICE 'PASS: rls';
    ELSE
        RAISE EXCEPTION 'FAIL: rls (expected 10 policies, found %)', v_pol_cnt;
    END IF;
END;
$$;

-- Test 3: Peek (outsider sees 0 steals; thief sees 1)
SELECT set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_outsider'), true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_steal BIGINT;
    v_outsider_cnt INT;
    v_thief_cnt INT;
BEGIN
    SELECT v INTO v_steal FROM ctx WHERE k = 'steal';
    SELECT count(*) INTO v_outsider_cnt FROM event WHERE event_id = v_steal;

    PERFORM set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_thief'), true);
    SELECT count(*) INTO v_thief_cnt FROM event WHERE event_id = v_steal;

    IF v_outsider_cnt = 0 AND v_thief_cnt = 1 THEN
        RAISE NOTICE 'PASS: peek';
    ELSE
        RAISE EXCEPTION 'FAIL: peek (outsider_cnt=%, thief_cnt=%)', v_outsider_cnt, v_thief_cnt;
    END IF;
END;
$$;
RESET ROLE;

-- Test 4: Public vs hidden events
SELECT set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_outsider'), true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_pub_cnt INT;
    v_hid_cnt INT;
BEGIN
    SELECT count(*) INTO v_pub_cnt
    FROM event
    WHERE event_id IN (SELECT v FROM ctx WHERE k IN ('set_price', 'rumor'));

    SELECT count(*) INTO v_hid_cnt
    FROM event
    WHERE event_id = (SELECT v FROM ctx WHERE k = 'state_change');

    IF v_pub_cnt = 2 AND v_hid_cnt = 0 THEN
        RAISE NOTICE 'PASS: public_vs_hidden';
    ELSE
        RAISE EXCEPTION 'FAIL: public_vs_hidden (expected pub=2, hid=0; got pub=%, hid=%)', v_pub_cnt, v_hid_cnt;
    END IF;
END;
$$;
RESET ROLE;

-- Test 5: No identity, no data
SELECT set_config('app.actor_id', '', true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_c1 BIGINT; v_c2 BIGINT; v_c3 BIGINT; v_c4 BIGINT; v_c5 BIGINT;
BEGIN
    SELECT count(*) INTO v_c1 FROM event;
    SELECT count(*) INTO v_c2 FROM event_witness;
    SELECT count(*) INTO v_c3 FROM entity_state;
    SELECT count(*) INTO v_c4 FROM event_cause;
    SELECT count(*) INTO v_c5 FROM causal_closure;

    IF v_c1 = 0 AND v_c2 = 0 AND v_c3 = 0 AND v_c4 = 0 AND v_c5 = 0 THEN
        RAISE NOTICE 'PASS: no_identity_no_data';
    ELSE
        RAISE EXCEPTION 'FAIL: no_identity_no_data (counts: event=%, witness=%, state=%, cause=%, closure=%)',
            v_c1, v_c2, v_c3, v_c4, v_c5;
    END IF;
END;
$$;
RESET ROLE;

-- Test 6: State privacy and public mood view
SELECT set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_outsider'), true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_state_cnt INT;
    v_own_entity INT;
    v_outsider_id INT;
    v_mood_cnt INT;
    v_thief_mood TEXT;
BEGIN
    SELECT v::int INTO v_outsider_id FROM ctx WHERE k = 'test_outsider';
    SELECT count(*) INTO v_state_cnt FROM entity_state;
    SELECT entity_id INTO v_own_entity FROM entity_state LIMIT 1;

    SELECT count(*) INTO v_mood_cnt
    FROM v_village_mood
    WHERE branch_id = (SELECT v::int FROM ctx WHERE k = 'main');

    SELECT mood INTO v_thief_mood
    FROM v_village_mood
    WHERE branch_id = (SELECT v::int FROM ctx WHERE k = 'main')
      AND actor_name = 'test_thief';

    IF v_state_cnt = 1 AND v_own_entity = v_outsider_id AND v_mood_cnt = 33 AND v_thief_mood = 'shunned' THEN
        RAISE NOTICE 'PASS: state_privacy';
    ELSE
        RAISE EXCEPTION 'FAIL: state_privacy (state_cnt=%, own=%, mood_cnt=%, thief_mood=%)',
            v_state_cnt, v_own_entity, v_mood_cnt, v_thief_mood;
    END IF;
END;
$$;
RESET ROLE;

-- Test 7: Write protection as test_outsider
SELECT set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_outsider'), true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_errs INT := 0;
    v_rule_cnt INT;
BEGIN
    -- 1. INSERT event
    BEGIN
        EXECUTE 'INSERT INTO event (branch_id, tick, action_type, payload) VALUES (1, 1, ''arrive'', ''{}'')';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 2. UPDATE event
    BEGIN
        EXECUTE 'UPDATE event SET payload = ''{}''';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 3. DELETE event
    BEGIN
        EXECUTE 'DELETE FROM event WHERE event_id = 1';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 4. TRUNCATE event
    BEGIN
        EXECUTE 'TRUNCATE event';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 5. INSERT stock
    BEGIN
        EXECUTE 'INSERT INTO stock (place_id, item_id, branch_id, qty, price) VALUES (1, 1, 1, 10, 1.0)';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 6. UPDATE stock
    BEGIN
        EXECUTE 'UPDATE stock SET qty = 10';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 7. SELECT * FROM rule
    BEGIN
        EXECUTE 'SELECT * FROM rule';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 8. SELECT * FROM scheduled_effect
    BEGIN
        EXECUTE 'SELECT * FROM scheduled_effect';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- 9. SELECT * FROM snapshot
    BEGIN
        EXECUTE 'SELECT * FROM snapshot';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- SELECT rule_id, narrative_template FROM rule succeeds with 15 rows
    SELECT count(*) INTO v_rule_cnt FROM (SELECT rule_id, narrative_template FROM rule) r;

    IF v_errs = 9 AND v_rule_cnt = 15 THEN
        RAISE NOTICE 'PASS: write_protection';
    ELSE
        RAISE EXCEPTION 'FAIL: write_protection (caught % of 9 insufficient_privilege errors, rule_cnt=%)', v_errs, v_rule_cnt;
    END IF;
END;
$$;
RESET ROLE;

-- Test 8: Controlled write path
SELECT set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_outsider'), true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_main INT;
    v_outsider INT;
    v_thief INT;
    v_ev_id BIGINT;
    v_visible_cnt INT;
    v_caught BOOLEAN := FALSE;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v::int INTO v_outsider FROM ctx WHERE k = 'test_outsider';
    SELECT v::int INTO v_thief FROM ctx WHERE k = 'test_thief';

    BEGIN
        v_ev_id := apply_action(v_main, v_outsider, 'build', '{"what":"stall"}'::jsonb);
        SELECT count(*) INTO v_visible_cnt FROM event WHERE event_id = v_ev_id;

        BEGIN
            PERFORM apply_action(v_main, v_thief, 'build', '{"what":"stall"}'::jsonb);
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%not your character%' THEN
                v_caught := TRUE;
            ELSE
                RAISE EXCEPTION 'unexpected error message: %', SQLERRM;
            END IF;
        END;

        IF v_ev_id IS NULL OR v_visible_cnt <> 1 OR NOT v_caught THEN
            RAISE EXCEPTION 'failed checks: ev_id=%, visible=%, caught=%', v_ev_id, v_visible_cnt, v_caught;
        END IF;

        -- Roll back the action so event count remains identical to setup
        RAISE EXCEPTION 'subx_done';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'subx_done' THEN
            RAISE NOTICE 'PASS: controlled_write_path';
        ELSE
            RAISE;
        END IF;
    END;
END;
$$;
RESET ROLE;

-- Test 9: Staff-only functions
SELECT set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_outsider'), true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_main INT;
    v_steal BIGINT;
    v_errs INT := 0;
BEGIN
    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v INTO v_steal FROM ctx WHERE k = 'steal';

    -- advance_day
    BEGIN
        EXECUTE format('SELECT advance_day(%s)', v_main);
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- join_village
    BEGIN
        EXECUTE format('SELECT join_village(%s, %L)', v_main, 'test_x');
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- fork_branch
    BEGIN
        EXECUTE format('SELECT fork_branch(%s, %s, %L, %L)', v_main, v_steal, 'test_fork', 'replay');
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- create_snapshot
    BEGIN
        EXECUTE format('SELECT create_snapshot(%s)', v_main);
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- refresh_daily_views
    BEGIN
        EXECUTE 'SELECT refresh_daily_views()';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- verify_event_chain
    BEGIN
        EXECUTE 'SELECT verify_event_chain()';
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    -- branch_diff
    BEGIN
        EXECUTE format('SELECT * FROM branch_diff(%s, %s)', v_main, v_main);
    EXCEPTION WHEN insufficient_privilege THEN v_errs := v_errs + 1;
    END;

    IF v_errs = 7 THEN
        RAISE NOTICE 'PASS: staff_only_functions';
    ELSE
        RAISE EXCEPTION 'FAIL: staff_only_functions (caught % of 7 insufficient_privilege errors)', v_errs;
    END IF;
END;
$$;
RESET ROLE;

-- Test 10: Game master (no app.actor_id)
SELECT set_config('app.actor_id', '', true);
SET LOCAL ROLE game_master_role;
DO $$
DECLARE
    v_cnt BIGINT;
    v_expected BIGINT;
    v_main INT;
    v_new_tick INT;
    v_late_id INT;
    v_ins_failed BOOLEAN := FALSE;
BEGIN
    SELECT v INTO v_expected FROM ctx WHERE k = 'total_events';
    SELECT count(*) INTO v_cnt FROM event;
    IF v_cnt <> v_expected THEN
        RAISE EXCEPTION 'FAIL: game_master (expected event count %, got %)', v_expected, v_cnt;
    END IF;

    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';

    BEGIN
        v_new_tick := advance_day(v_main);
        IF v_new_tick <> 3 THEN
            RAISE EXCEPTION 'advance_day did not return 3 (got %)', v_new_tick;
        END IF;

        v_late_id := join_village(v_main, 'test_late');
        IF v_late_id IS NULL THEN
            RAISE EXCEPTION 'join_village failed';
        END IF;

        -- Roll back the mutations so subsequent tests see clean setup baseline
        RAISE EXCEPTION 'subx_done';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'subx_done' THEN
            RAISE EXCEPTION 'FAIL: game_master (error in advance_day/join_village: %)', SQLERRM;
        END IF;
    END;

    BEGIN
        EXECUTE 'INSERT INTO event (branch_id, tick, action_type, payload) VALUES (1, 1, ''arrive'', ''{}'')';
    EXCEPTION WHEN insufficient_privilege THEN
        v_ins_failed := TRUE;
    END;

    IF v_ins_failed THEN
        RAISE NOTICE 'PASS: game_master';
    ELSE
        RAISE EXCEPTION 'FAIL: game_master (INSERT INTO event did not raise insufficient_privilege)';
    END IF;
END;
$$;
RESET ROLE;

-- Test 11: Auditor
SELECT set_config('app.actor_id', '', true);
SET LOCAL ROLE auditor_role;
DO $$
DECLARE
    v_cnt BIGINT;
    v_expected BIGINT;
    v_chain_bad INT;
    v_causal_bad INT;
    v_act_failed BOOLEAN := FALSE;
    v_adv_failed BOOLEAN := FALSE;
    v_ins_failed BOOLEAN := FALSE;
    v_main INT;
    v_thief INT;
BEGIN
    SELECT v INTO v_expected FROM ctx WHERE k = 'total_events';
    SELECT count(*) INTO v_cnt FROM event;
    IF v_cnt <> v_expected THEN
        RAISE EXCEPTION 'FAIL: auditor (expected event count %, got %)', v_expected, v_cnt;
    END IF;

    SELECT count(*) INTO v_chain_bad FROM verify_event_chain();
    SELECT count(*) INTO v_causal_bad FROM verify_causal_structures();

    SELECT v::int INTO v_main FROM ctx WHERE k = 'main';
    SELECT v::int INTO v_thief FROM ctx WHERE k = 'test_thief';

    BEGIN
        EXECUTE format('SELECT apply_action(%s, %s, ''build'', ''{"what":"stall"}'')', v_main, v_thief);
    EXCEPTION WHEN insufficient_privilege THEN
        v_act_failed := TRUE;
    END;

    BEGIN
        EXECUTE format('SELECT advance_day(%s)', v_main);
    EXCEPTION WHEN insufficient_privilege THEN
        v_adv_failed := TRUE;
    END;

    BEGIN
        EXECUTE 'INSERT INTO event (branch_id, tick, action_type, payload) VALUES (1, 1, ''arrive'', ''{}'')';
    EXCEPTION WHEN insufficient_privilege THEN
        v_ins_failed := TRUE;
    END;

    IF v_chain_bad = 0 AND v_causal_bad = 0 AND v_act_failed AND v_adv_failed AND v_ins_failed THEN
        RAISE NOTICE 'PASS: auditor';
    ELSE
        RAISE EXCEPTION 'FAIL: auditor (chain_bad=%, causal_bad=%, act_failed=%, adv_failed=%, ins_failed=%)',
            v_chain_bad, v_causal_bad, v_act_failed, v_adv_failed, v_ins_failed;
    END IF;
END;
$$;
RESET ROLE;

-- Test 12: Detective Ask Why
SELECT set_config('app.actor_id', (SELECT v::text FROM ctx WHERE k = 'test_outsider'), true);
SET LOCAL ROLE player_role;
DO $$
DECLARE
    v_rumor BIGINT;
    v_steal BIGINT;
    v_state_change BIGINT;
    v_outsider_rows INT := 0;
    v_has_forbidden BOOLEAN := FALSE;
    v_has_non_null_narrative BOOLEAN := FALSE;
    r RECORD;
BEGIN
    SELECT v INTO v_rumor FROM ctx WHERE k = 'rumor';
    SELECT v INTO v_steal FROM ctx WHERE k = 'steal';
    SELECT v INTO v_state_change FROM ctx WHERE k = 'state_change';

    FOR r IN SELECT * FROM ask_why(v_rumor) LOOP
        v_outsider_rows := v_outsider_rows + 1;
        IF r.event_id IN (v_steal, v_state_change) THEN
            v_has_forbidden := TRUE;
        END IF;
        IF r.depth NOT IN (0, 2) THEN
            RAISE EXCEPTION 'outsider saw unexpected depth %', r.depth;
        END IF;
        IF r.narrative IS NOT NULL THEN
            v_has_non_null_narrative := TRUE;
        END IF;
    END LOOP;

    IF v_outsider_rows <> 2 OR v_has_forbidden OR v_has_non_null_narrative THEN
        RAISE EXCEPTION 'FAIL: detective_ask_why (outsider_rows=%, forbidden=%, non_null_narrative=%)',
            v_outsider_rows, v_has_forbidden, v_has_non_null_narrative;
    END IF;

    INSERT INTO ctx (k, v) VALUES ('outsider_askwhy_ok', 1);
END;
$$;
RESET ROLE;

SELECT set_config('app.actor_id', '', true);
SET LOCAL ROLE game_master_role;
DO $$
DECLARE
    v_rumor BIGINT;
    v_gm_rows INT := 0;
    v_gm_steps_narrative_ok BOOLEAN := TRUE;
    r RECORD;
BEGIN
    SELECT v INTO v_rumor FROM ctx WHERE k = 'rumor';

    FOR r IN SELECT * FROM ask_why(v_rumor) ORDER BY step LOOP
        v_gm_rows := v_gm_rows + 1;
        IF r.step IN (1, 2, 3) AND r.narrative IS NULL THEN
            v_gm_steps_narrative_ok := FALSE;
        END IF;
    END LOOP;

    IF v_gm_rows = 4 AND v_gm_steps_narrative_ok AND (SELECT v FROM ctx WHERE k = 'outsider_askwhy_ok') = 1 THEN
        RAISE NOTICE 'PASS: detective_ask_why';
    ELSE
        RAISE EXCEPTION 'FAIL: detective_ask_why (gm_rows=%, narrative_ok=%)',
            v_gm_rows, v_gm_steps_narrative_ok;
    END IF;
END;
$$;
RESET ROLE;

ROLLBACK;

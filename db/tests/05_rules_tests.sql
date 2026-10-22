BEGIN;

CREATE TEMP TABLE ctx (
    k TEXT PRIMARY KEY,
    v BIGINT
);

DO $$
DECLARE
    v_cond_failed BOOLEAN := FALSE;
    v_effect_failed BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO "rule" (trigger_action_type, condition, effect_template)
        VALUES ('gift', 'not json', '{"action":"gift"}');
    EXCEPTION
        WHEN OTHERS THEN
            v_cond_failed := TRUE;
    END;

    BEGIN
        INSERT INTO "rule" (trigger_action_type, effect_template)
        VALUES ('gift', '{"nope":1}');
    EXCEPTION
        WHEN check_violation THEN
            v_effect_failed := TRUE;
    END;

    IF v_cond_failed AND v_effect_failed THEN
        RAISE NOTICE 'PASS: rule integrity';
    ELSE
        RAISE EXCEPTION 'FAIL: rule integrity (cond_failed=%, effect_failed=%)', v_cond_failed, v_effect_failed;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_bakery_id INT;
    v_bread_id INT;
    v_steal_rule_id INT;
    v_events_before INT;
    v_causes_before INT;
    v_sched_before INT;
    v_steal_event_id BIGINT;
    v_steal_tick INT;
    v_events_after INT;
    v_causes_after INT;
    v_sched_after INT;
    v_new_sched scheduled_effect;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';
    SELECT rule_id INTO v_steal_rule_id FROM "rule" WHERE trigger_action_type = 'steal';

    v_thief_id := join_village(v_branch_id, 'test_thief');
    INSERT INTO ctx (k, v) VALUES ('thief_id', v_thief_id);

    SELECT count(*) INTO v_events_before FROM event WHERE branch_id = v_branch_id;
    SELECT count(*) INTO v_causes_before FROM event_cause;
    SELECT count(*) INTO v_sched_before FROM scheduled_effect WHERE branch_id = v_branch_id;

    v_steal_event_id := apply_action(
        v_branch_id,
        v_thief_id,
        'steal',
        jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 1)
    );
    INSERT INTO ctx (k, v) VALUES ('steal_event_id', v_steal_event_id);

    SELECT tick INTO v_steal_tick FROM event WHERE event_id = v_steal_event_id;

    SELECT count(*) INTO v_events_after FROM event WHERE branch_id = v_branch_id;
    SELECT count(*) INTO v_causes_after FROM event_cause;
    SELECT count(*) INTO v_sched_after FROM scheduled_effect WHERE branch_id = v_branch_id;

    SELECT * INTO v_new_sched
    FROM scheduled_effect
    WHERE branch_id = v_branch_id
    ORDER BY scheduled_id DESC
    LIMIT 1;

    IF v_events_after = v_events_before + 1
       AND v_causes_after = v_causes_before
       AND v_sched_after = v_sched_before + 1
       AND v_new_sched.due_tick = v_steal_tick + 1
       AND v_new_sched.processed = FALSE
       AND v_new_sched.rule_id = v_steal_rule_id
       AND v_new_sched.source_event_id = v_steal_event_id THEN
        RAISE NOTICE 'PASS: thief steals bread and schedules effect';
    ELSE
        RAISE EXCEPTION 'FAIL: thief steals bread and schedules effect (events_diff=%, causes_diff=%, sched_diff=%, due=%, proc=%, rule=%, src=%)',
            v_events_after - v_events_before, v_causes_after - v_causes_before, v_sched_after - v_sched_before,
            v_new_sched.due_tick, v_new_sched.processed, v_new_sched.rule_id, v_new_sched.source_event_id;
    END IF;
END
$$;

DO $$
DECLARE
    v_steal_event_id BIGINT;
    v_steal_event event;
    v_bakery_id INT;
    v_thief_id INT;
    v_template JSONB;
    v_result JSONB;
    v_expected JSONB;
BEGIN
    SELECT v INTO v_steal_event_id FROM ctx WHERE k = 'steal_event_id';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';

    SELECT * INTO v_steal_event FROM event WHERE event_id = v_steal_event_id;

    v_template := '{"p":"$payload.place_id","who":"$actor","t":"$tick","k":[1,"$payload.qty"],"lit":"x"}'::jsonb;
    v_result := resolve_template(v_template, v_steal_event);

    v_expected := jsonb_build_object(
        'p', v_bakery_id,
        'who', v_thief_id,
        't', 0,
        'k', jsonb_build_array(1, 1),
        'lit', 'x'
    );

    IF v_result = v_expected THEN
        RAISE NOTICE 'PASS: resolve template';
    ELSE
        RAISE EXCEPTION 'FAIL: resolve template (result=%, expected=%)', v_result, v_expected;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_steal_event_id BIGINT;
    v_steal_rule_id INT;
    v_set_price_rule_id INT;
    v_day INT;
    v_day_start_count INT;
    v_set_price_event event;
    v_cause_match INT;
    v_bread_price NUMERIC(10,2);
    v_bakery_id INT;
    v_bread_id INT;
    v_steal_sched_processed BOOLEAN;
    v_new_sched scheduled_effect;
    v_unprocessed_sched_count INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';
    SELECT v INTO v_steal_event_id FROM ctx WHERE k = 'steal_event_id';
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';
    SELECT rule_id INTO v_steal_rule_id FROM "rule" WHERE trigger_action_type = 'steal';
    SELECT rule_id INTO v_set_price_rule_id FROM "rule" WHERE trigger_action_type = 'set_price';

    v_day := advance_day(v_branch_id);

    SELECT count(*) INTO v_day_start_count
    FROM event
    WHERE branch_id = v_branch_id AND tick = 1 AND action_type = 'day_start';

    SELECT * INTO v_set_price_event
    FROM event
    WHERE branch_id = v_branch_id AND tick = 1 AND action_type = 'set_price';
    INSERT INTO ctx (k, v) VALUES ('set_price_event_id', v_set_price_event.event_id);

    SELECT count(*) INTO v_cause_match
    FROM event_cause
    WHERE effect_id = v_set_price_event.event_id
      AND cause_id = v_steal_event_id
      AND rule_id = v_steal_rule_id;

    SELECT price INTO v_bread_price
    FROM stock
    WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    SELECT processed INTO v_steal_sched_processed
    FROM scheduled_effect
    WHERE source_event_id = v_steal_event_id;

    SELECT count(*) INTO v_unprocessed_sched_count
    FROM scheduled_effect
    WHERE branch_id = v_branch_id AND NOT processed;

    SELECT * INTO v_new_sched
    FROM scheduled_effect
    WHERE branch_id = v_branch_id AND NOT processed
    LIMIT 1;

    IF v_day = 1
       AND v_day_start_count = 1
       AND v_set_price_event.event_id IS NOT NULL
       AND (v_set_price_event.payload->>'price_pct')::int = 25
       AND (v_set_price_event.payload->>'culprit')::int = v_thief_id
       AND v_cause_match = 1
       AND v_bread_price = 2.50
       AND v_steal_sched_processed = TRUE
       AND v_unprocessed_sched_count = 1
       AND v_new_sched.due_tick = 2
       AND v_new_sched.rule_id = v_set_price_rule_id THEN
        RAISE NOTICE 'PASS: advance day to day 1';
    ELSE
        RAISE EXCEPTION 'FAIL: advance day to day 1 (day=%, day_start=%, set_price=%, culprit=%, cause=%, price=%, steal_proc=%, unproc=%, new_due=%, new_rule=%)',
            v_day, v_day_start_count, v_set_price_event.event_id, v_set_price_event.payload->>'culprit',
            v_cause_match, v_bread_price, v_steal_sched_processed, v_unprocessed_sched_count,
            v_new_sched.due_tick, v_new_sched.rule_id;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_set_price_event_id BIGINT;
    v_day INT;
    v_sc_event event;
    v_sc_cause_match INT;
    v_thief_state JSONB;
    v_rumor_event event;
    v_rumor_cause_match INT;
    v_witness_count INT;
    v_actor_count INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';
    SELECT v INTO v_set_price_event_id FROM ctx WHERE k = 'set_price_event_id';

    v_day := advance_day(v_branch_id);

    SELECT * INTO v_sc_event
    FROM event
    WHERE branch_id = v_branch_id AND tick = 2 AND action_type = 'state_change';
    INSERT INTO ctx (k, v) VALUES ('sc_event_id', v_sc_event.event_id);

    SELECT count(*) INTO v_sc_cause_match
    FROM event_cause
    WHERE effect_id = v_sc_event.event_id
      AND cause_id = v_set_price_event_id;

    SELECT state INTO v_thief_state
    FROM entity_state
    WHERE entity_id = v_thief_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT * INTO v_rumor_event
    FROM event
    WHERE branch_id = v_branch_id AND tick = 2 AND action_type = 'rumor';
    INSERT INTO ctx (k, v) VALUES ('rumor_event_id', v_rumor_event.event_id);

    SELECT count(*) INTO v_rumor_cause_match
    FROM event_cause
    WHERE effect_id = v_rumor_event.event_id
      AND cause_id = v_sc_event.event_id;

    SELECT count(*) INTO v_witness_count
    FROM event_witness
    WHERE event_id = v_rumor_event.event_id;

    SELECT count(*) INTO v_actor_count FROM actor;

    IF v_day = 2
       AND v_sc_event.event_id IS NOT NULL
       AND v_sc_cause_match = 1
       AND (v_thief_state->>'trust')::int = 45
       AND v_thief_state->>'mood' = 'shunned'
       AND v_rumor_event.event_id IS NOT NULL
       AND v_rumor_cause_match = 1
       AND v_witness_count = v_actor_count THEN
        RAISE NOTICE 'PASS: advance day to day 2 and cascade';
    ELSE
        RAISE EXCEPTION 'FAIL: advance day to day 2 and cascade (day=%, sc=%, sc_cause=%, trust=%, mood=%, rumor=%, rumor_cause=%, witnesses=%, actors=%)',
            v_day, v_sc_event.event_id, v_sc_cause_match, v_thief_state->>'trust', v_thief_state->>'mood',
            v_rumor_event.event_id, v_rumor_cause_match, v_witness_count, v_actor_count;
    END IF;
END
$$;

DO $$
DECLARE
    v_rumor_id BIGINT;
    v_thief_id INT;
    v_steal_id BIGINT;
    v_why_count INT;
    v_max_depth INT;
    v_deepest_cause_id BIGINT;
    v_deepest_actor_id INT;
BEGIN
    SELECT v INTO v_rumor_id FROM ctx WHERE k = 'rumor_event_id';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';
    SELECT v INTO v_steal_id FROM ctx WHERE k = 'steal_event_id';

    WITH RECURSIVE why AS (
        SELECT
            cause_id,
            effect_id,
            rule_id,
            1 AS depth
        FROM event_cause
        WHERE effect_id = v_rumor_id

        UNION ALL

        SELECT
            ec.cause_id,
            ec.effect_id,
            ec.rule_id,
            w.depth + 1
        FROM event_cause ec
        JOIN why w ON ec.effect_id = w.cause_id
    )
    SELECT
        count(*),
        max(depth),
        (SELECT cause_id FROM why ORDER BY depth DESC LIMIT 1)
    INTO v_why_count, v_max_depth, v_deepest_cause_id
    FROM why;

    SELECT actor_id INTO v_deepest_actor_id FROM event WHERE event_id = v_deepest_cause_id;

    IF v_why_count = 3
       AND v_max_depth = 3
       AND v_deepest_cause_id = v_steal_id
       AND v_deepest_actor_id = v_thief_id THEN
        RAISE NOTICE 'PASS: ask why causal chain';
    ELSE
        RAISE EXCEPTION 'FAIL: ask why causal chain (count=%, max_depth=%, deepest_cause=%, expected_steal=%, actor=%, expected_thief=%)',
            v_why_count, v_max_depth, v_deepest_cause_id, v_steal_id, v_deepest_actor_id, v_thief_id;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_trust_0 INT;
    v_trust_1 INT;
    v_trust_2 INT;
    v_row_count INT;
    v_range_1 INT4RANGE;
    v_range_2 INT4RANGE;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';

    v_trust_0 := (entity_state_at(v_thief_id, v_branch_id, 0)->>'trust')::int;
    v_trust_1 := (entity_state_at(v_thief_id, v_branch_id, 1)->>'trust')::int;
    v_trust_2 := (entity_state_at(v_thief_id, v_branch_id, 2)->>'trust')::int;

    SELECT count(*) INTO v_row_count
    FROM entity_state
    WHERE entity_id = v_thief_id AND branch_id = v_branch_id;

    SELECT valid_ticks INTO v_range_1
    FROM entity_state
    WHERE entity_id = v_thief_id AND branch_id = v_branch_id AND NOT upper_inf(valid_ticks);

    SELECT valid_ticks INTO v_range_2
    FROM entity_state
    WHERE entity_id = v_thief_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    IF v_trust_0 = 50 AND v_trust_1 = 50 AND v_trust_2 = 45
       AND v_row_count = 2
       AND v_range_1 = '[0,2)'::int4range
       AND v_range_2 = '[2,)'::int4range THEN
        RAISE NOTICE 'PASS: time travel entity state history';
    ELSE
        RAISE EXCEPTION 'FAIL: time travel entity state history (t0=%, t1=%, t2=%, rows=%, r1=%, r2=%)',
            v_trust_0, v_trust_1, v_trust_2, v_row_count, v_range_1, v_range_2;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_bakery_id INT;
    v_bread_id INT;
    v_steal_rule_id INT;
    v_sched_count_before INT;
    v_sched_count_after INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';
    SELECT rule_id INTO v_steal_rule_id FROM "rule" WHERE trigger_action_type = 'steal';

    UPDATE "rule" SET is_active = FALSE WHERE rule_id = v_steal_rule_id;

    SELECT count(*) INTO v_sched_count_before
    FROM scheduled_effect
    WHERE branch_id = v_branch_id;

    PERFORM apply_action(
        v_branch_id,
        v_thief_id,
        'steal',
        jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 1)
    );

    SELECT count(*) INTO v_sched_count_after
    FROM scheduled_effect
    WHERE branch_id = v_branch_id;

    IF v_sched_count_after = v_sched_count_before THEN
        RAISE NOTICE 'PASS: disabled rule does not schedule effect';
    ELSE
        RAISE EXCEPTION 'FAIL: disabled rule does not schedule effect (before=%, after=%)',
            v_sched_count_before, v_sched_count_after;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_wick_id INT;
    v_bread_id INT;
    v_new_rule_id INT;
    v_coins_before INT;
    v_coins_after INT;
    v_gift_event_id BIGINT;
    v_cause_match INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';
    SELECT actor_id INTO v_wick_id FROM actor WHERE name = 'Old Wick';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';

    INSERT INTO "rule" (trigger_action_type, condition, delay_ticks, effect_template, narrative_template, is_active)
    VALUES (
        'gift',
        NULL,
        0,
        '{"action":"state_change","actor":null,"payload":{"entity_id":"$payload.target_actor","add":{"coins":1}},"visibility":"private"}',
        'A gift made a neighbor richer.',
        TRUE
    )
    RETURNING rule_id INTO v_new_rule_id;

    SELECT (state->>'coins')::int INTO v_coins_before
    FROM entity_state
    WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    v_gift_event_id := apply_action(
        v_branch_id,
        v_thief_id,
        'gift',
        jsonb_build_object('item_id', v_bread_id, 'qty', 1, 'target_actor', v_wick_id)
    );

    SELECT (state->>'coins')::int INTO v_coins_after
    FROM entity_state
    WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT count(*) INTO v_cause_match
    FROM event_cause
    WHERE cause_id = v_gift_event_id AND rule_id = v_new_rule_id;

    IF v_coins_after = v_coins_before + 1 AND v_cause_match = 1 THEN
        RAISE NOTICE 'PASS: dynamically added rule executes immediately';
    ELSE
        RAISE EXCEPTION 'FAIL: dynamically added rule executes immediately (before=%, after=%, cause_match=%)',
            v_coins_before, v_coins_after, v_cause_match;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_thief_id INT;
    v_feast_before INT;
    v_causes_before INT;
    v_feast_after INT;
    v_causes_after INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_thief_id FROM ctx WHERE k = 'thief_id';

    INSERT INTO "rule" (trigger_action_type, condition, delay_ticks, effect_template, is_active)
    VALUES ('feast', NULL, 0, '{"action":"feast","actor":null,"payload":{},"visibility":"private"}', TRUE);

    SELECT count(*) INTO v_feast_before FROM event WHERE branch_id = v_branch_id AND action_type = 'feast';
    SELECT count(*) INTO v_causes_before FROM event_cause;

    PERFORM apply_action(v_branch_id, v_thief_id, 'feast', '{}'::jsonb);

    SELECT count(*) INTO v_feast_after FROM event WHERE branch_id = v_branch_id AND action_type = 'feast';
    SELECT count(*) INTO v_causes_after FROM event_cause;

    IF v_feast_after = v_feast_before + 6 AND v_causes_after = v_causes_before + 5 THEN
        RAISE NOTICE 'PASS: cascade depth limit respected';
    ELSE
        RAISE EXCEPTION 'FAIL: cascade depth limit respected (feast_diff=%, causes_diff=%)',
            v_feast_after - v_feast_before, v_causes_after - v_causes_before;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_other_id INT;
    v_events_before INT;
    v_witness_before INT;
    v_events_after INT;
    v_witness_after INT;
    v_raised_state BOOLEAN := FALSE;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';

    v_other_id := join_village(v_branch_id, 'test_other');

    INSERT INTO "rule" (trigger_action_type, condition, delay_ticks, effect_template, is_active)
    VALUES ('hire', NULL, 0, '{"action":"state_change","actor":null,"payload":{"entity_id":999999,"set":{"mood":"x"}},"visibility":"private"}', TRUE);

    SELECT count(*) INTO v_events_before FROM event;
    SELECT count(*) INTO v_witness_before FROM event_witness;

    BEGIN
        PERFORM apply_action(v_branch_id, v_other_id, 'hire', '{}'::jsonb);
    EXCEPTION
        WHEN OTHERS THEN
            IF position('no current state' IN SQLERRM) > 0 THEN
                v_raised_state := TRUE;
            ELSE
                RAISE EXCEPTION 'FAIL: atomic rollback hire wrong error (%)', SQLERRM;
            END IF;
    END;

    SELECT count(*) INTO v_events_after FROM event;
    SELECT count(*) INTO v_witness_after FROM event_witness;

    IF v_raised_state AND v_events_after = v_events_before AND v_witness_after = v_witness_before THEN
        RAISE NOTICE 'PASS: atomic rollback on cascade error';
    ELSE
        RAISE EXCEPTION 'FAIL: atomic rollback on cascade error (raised=%, events_before=%, events_after=%, witness_before=%, witness_after=%)',
            v_raised_state, v_events_before, v_events_after, v_witness_before, v_witness_after;
    END IF;
END
$$;

DO $$
DECLARE
    v_chain_problems INT;
    v_null_rules INT;
    v_unmatched_causes INT;
BEGIN
    SELECT count(*) INTO v_chain_problems FROM verify_event_chain();

    SELECT count(*) INTO v_null_rules
    FROM event_cause
    WHERE rule_id IS NULL;

    SELECT count(*) INTO v_unmatched_causes
    FROM scheduled_effect s
    WHERE s.processed
      AND NOT EXISTS (
          SELECT 1
          FROM event_cause ec
          WHERE ec.cause_id = s.source_event_id
            AND ec.rule_id = s.rule_id
      );

    IF v_chain_problems = 0 AND v_null_rules = 0 AND v_unmatched_causes = 0 THEN
        RAISE NOTICE 'PASS: engine integrity and event chain verification';
    ELSE
        RAISE EXCEPTION 'FAIL: engine integrity and event chain verification (chain_problems=%, null_rules=%, unmatched_causes=%)',
            v_chain_problems, v_null_rules, v_unmatched_causes;
    END IF;
END
$$;

ROLLBACK;

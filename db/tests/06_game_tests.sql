BEGIN;

CREATE TEMP TABLE ctx (
    k TEXT PRIMARY KEY,
    v BIGINT
);

CREATE FUNCTION pg_temp.coin_total()
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM((es.state->>'coins')::numeric), 0)
    FROM entity_state es
    JOIN branch b ON b.branch_id = es.branch_id
    WHERE b.name = 'main'
      AND upper_inf(es.valid_ticks);
$$;

CREATE FUNCTION pg_temp.item_total(p_item TEXT)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    SELECT
        COALESCE((
            SELECT SUM(s.qty)
            FROM stock s
            JOIN item i ON i.item_id = s.item_id
            JOIN branch b ON b.branch_id = s.branch_id
            WHERE b.name = 'main' AND i.name = p_item
        ), 0)::BIGINT
        +
        COALESCE((
            SELECT SUM((es.state->'inv'->>p_item)::BIGINT)
            FROM entity_state es
            JOIN branch b ON b.branch_id = es.branch_id
            WHERE b.name = 'main'
              AND upper_inf(es.valid_ticks)
              AND es.state->'inv'->>p_item IS NOT NULL
        ), 0)::BIGINT;
$$;

-- Setup: look up IDs, register 5 players, record baseline coins
DO $$
DECLARE
    v_branch_id INT;
    v_buyer_id INT;
    v_helper_id INT;
    v_saboteur_id INT;
    v_boss_id INT;
    v_rumor_id INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;
    INSERT INTO ctx (k, v) VALUES ('branch_id', v_branch_id);

    INSERT INTO ctx (k, v)
    SELECT 'place_bakery', place_id FROM place WHERE name = 'Maren''s Bakery'
    UNION ALL
    SELECT 'place_mill', place_id FROM place WHERE name = 'Tobin''s Mill'
    UNION ALL
    SELECT 'place_farm', place_id FROM place WHERE name = 'Hartley Farm'
    UNION ALL
    SELECT 'place_market', place_id FROM place WHERE name = 'Market Square'
    UNION ALL
    SELECT 'item_bread', item_id FROM item WHERE name = 'bread'
    UNION ALL
    SELECT 'item_grain', item_id FROM item WHERE name = 'grain'
    UNION ALL
    SELECT 'item_flour', item_id FROM item WHERE name = 'flour'
    UNION ALL
    SELECT 'actor_wick', actor_id FROM actor WHERE name = 'Old Wick'
    UNION ALL
    SELECT 'actor_maren', actor_id FROM actor WHERE name = 'Maren';

    -- Setup: join_village for 5 players
    v_buyer_id := join_village(v_branch_id, 'test_buyer');
    v_helper_id := join_village(v_branch_id, 'test_helper');
    v_saboteur_id := join_village(v_branch_id, 'test_saboteur');
    v_boss_id := join_village(v_branch_id, 'test_boss');
    v_rumor_id := join_village(v_branch_id, 'test_rumor');

    INSERT INTO ctx (k, v) VALUES
        ('buyer_id', v_buyer_id),
        ('helper_id', v_helper_id),
        ('saboteur_id', v_saboteur_id),
        ('boss_id', v_boss_id),
        ('rumor_id', v_rumor_id);

    -- THEN record baseline coin_total in ctx
    INSERT INTO ctx (k, v) VALUES ('baseline_coins', pg_temp.coin_total()::BIGINT);
END
$$;

-- 1. trade: test_buyer buys 2 bread from Maren's Bakery
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_buyer_id INT := (SELECT v FROM ctx WHERE k = 'buyer_id');
    v_maren_id INT := (SELECT v FROM ctx WHERE k = 'actor_maren');
    v_bakery_id INT := (SELECT v FROM ctx WHERE k = 'place_bakery');
    v_bread_id INT := (SELECT v FROM ctx WHERE k = 'item_bread');
    v_baseline_coins NUMERIC := (SELECT v FROM ctx WHERE k = 'baseline_coins');
    v_bakery_bread_before INT;
    v_bakery_bread_after INT;
    v_maren_coins_before NUMERIC;
    v_maren_coins_after NUMERIC;
    v_buyer_coins NUMERIC;
    v_buyer_bread INT;
    v_bread_total_before BIGINT;
    v_bread_total_after BIGINT;
    v_event_id BIGINT;
    v_witness_count INT;
    v_coins_now NUMERIC;
BEGIN
    SELECT qty INTO v_bakery_bread_before
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    SELECT (state->>'coins')::numeric INTO v_maren_coins_before
    FROM entity_state WHERE entity_id = v_maren_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    v_bread_total_before := pg_temp.item_total('bread');

    v_event_id := apply_action(
        v_branch_id,
        v_buyer_id,
        'trade',
        jsonb_build_object(
            'place_id', v_bakery_id,
            'item_id', v_bread_id,
            'qty', 2,
            'target_actor', v_maren_id
        )
    );

    SELECT qty INTO v_bakery_bread_after
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    SELECT (state->>'coins')::numeric INTO v_buyer_coins
    FROM entity_state WHERE entity_id = v_buyer_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT (state->>'coins')::numeric INTO v_maren_coins_after
    FROM entity_state WHERE entity_id = v_maren_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT COALESCE((state->'inv'->>'bread')::int, 0) INTO v_buyer_bread
    FROM entity_state WHERE entity_id = v_buyer_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    v_bread_total_after := pg_temp.item_total('bread');
    v_coins_now := pg_temp.coin_total();

    SELECT count(*) INTO v_witness_count FROM event_witness WHERE event_id = v_event_id;

    IF v_bakery_bread_after = v_bakery_bread_before - 2
       AND v_buyer_coins = 1
       AND v_maren_coins_after = v_maren_coins_before + 4
       AND v_buyer_bread = 2
       AND v_coins_now = v_baseline_coins
       AND v_bread_total_after = v_bread_total_before
       AND v_witness_count = 2 THEN
        RAISE NOTICE 'PASS: trade';
    ELSE
        RAISE EXCEPTION 'FAIL: trade (bread_after=%, buyer_coins=%, maren_coins=%, buyer_bread=%, coins_now=%, bread_total=%, witnesses=%)',
            v_bakery_bread_after, v_buyer_coins, v_maren_coins_after, v_buyer_bread, v_coins_now, v_bread_total_after, v_witness_count;
    END IF;
END
$$;

-- 2. trade without enough coins: test_buyer buys 1 more bread -> raises 'not enough coins'
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_buyer_id INT := (SELECT v FROM ctx WHERE k = 'buyer_id');
    v_maren_id INT := (SELECT v FROM ctx WHERE k = 'actor_maren');
    v_bakery_id INT := (SELECT v FROM ctx WHERE k = 'place_bakery');
    v_bread_id INT := (SELECT v FROM ctx WHERE k = 'item_bread');
    v_events_before INT;
    v_events_after INT;
    v_bread_before INT;
    v_bread_after INT;
    v_raised BOOLEAN := FALSE;
    v_err TEXT := '';
BEGIN
    SELECT count(*) INTO v_events_before FROM event WHERE branch_id = v_branch_id;
    SELECT qty INTO v_bread_before FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_buyer_id,
            'trade',
            jsonb_build_object(
                'place_id', v_bakery_id,
                'item_id', v_bread_id,
                'qty', 1,
                'target_actor', v_maren_id
            )
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('not enough coins' IN SQLERRM) > 0 THEN
                v_raised := TRUE;
            ELSE
                v_err := SQLERRM;
            END IF;
    END;

    SELECT count(*) INTO v_events_after FROM event WHERE branch_id = v_branch_id;
    SELECT qty INTO v_bread_after FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    IF v_raised AND v_events_after = v_events_before AND v_bread_after = v_bread_before THEN
        RAISE NOTICE 'PASS: trade without enough coins';
    ELSE
        RAISE EXCEPTION 'FAIL: trade without enough coins (raised=%, err=%, events_diff=%, bread_diff=%)',
            v_raised, v_err, v_events_after - v_events_before, v_bread_after - v_bread_before;
    END IF;
END
$$;

-- 3. trade over stock: test_boss buys qty 999 bread -> raises (any error)
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_boss_id INT := (SELECT v FROM ctx WHERE k = 'boss_id');
    v_maren_id INT := (SELECT v FROM ctx WHERE k = 'actor_maren');
    v_bakery_id INT := (SELECT v FROM ctx WHERE k = 'place_bakery');
    v_bread_id INT := (SELECT v FROM ctx WHERE k = 'item_bread');
    v_events_before INT;
    v_events_after INT;
    v_bread_before INT;
    v_bread_after INT;
    v_raised BOOLEAN := FALSE;
BEGIN
    SELECT count(*) INTO v_events_before FROM event WHERE branch_id = v_branch_id;
    SELECT qty INTO v_bread_before FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_boss_id,
            'trade',
            jsonb_build_object(
                'place_id', v_bakery_id,
                'item_id', v_bread_id,
                'qty', 999,
                'target_actor', v_maren_id
            )
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_raised := TRUE;
    END;

    SELECT count(*) INTO v_events_after FROM event WHERE branch_id = v_branch_id;
    SELECT qty INTO v_bread_after FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    IF v_raised AND v_events_after = v_events_before AND v_bread_after = v_bread_before THEN
        RAISE NOTICE 'PASS: trade over stock';
    ELSE
        RAISE EXCEPTION 'FAIL: trade over stock (raised=%, events_diff=%, bread_diff=%)',
            v_raised, v_events_after - v_events_before, v_bread_after - v_bread_before;
    END IF;
END
$$;

-- 4. help_harvest: test_helper qty 5 at Hartley Farm
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_helper_id INT := (SELECT v FROM ctx WHERE k = 'helper_id');
    v_farm_id INT := (SELECT v FROM ctx WHERE k = 'place_farm');
    v_bakery_id INT := (SELECT v FROM ctx WHERE k = 'place_bakery');
    v_grain_id INT := (SELECT v FROM ctx WHERE k = 'item_grain');
    v_help_rule_id INT;
    v_farm_grain_before INT;
    v_farm_grain_after INT;
    v_event_id BIGINT;
    v_witness_count INT;
    v_sc_cause_count INT;
    v_helper_trust NUMERIC;
    v_raised_large BOOLEAN := FALSE;
    v_raised_nonfarm BOOLEAN := FALSE;
BEGIN
    SELECT rule_id INTO v_help_rule_id FROM "rule" WHERE trigger_action_type = 'help_harvest';

    SELECT qty INTO v_farm_grain_before
    FROM stock WHERE place_id = v_farm_id AND item_id = v_grain_id AND branch_id = v_branch_id;

    v_event_id := apply_action(
        v_branch_id,
        v_helper_id,
        'help_harvest',
        jsonb_build_object('place_id', v_farm_id, 'qty', 5)
    );

    SELECT qty INTO v_farm_grain_after
    FROM stock WHERE place_id = v_farm_id AND item_id = v_grain_id AND branch_id = v_branch_id;

    SELECT count(*) INTO v_witness_count FROM event_witness WHERE event_id = v_event_id;

    SELECT count(*) INTO v_sc_cause_count
    FROM event_cause ec
    JOIN event e ON e.event_id = ec.effect_id
    WHERE ec.cause_id = v_event_id
      AND ec.rule_id = v_help_rule_id
      AND e.action_type = 'state_change';

    SELECT (state->>'trust')::numeric INTO v_helper_trust
    FROM entity_state WHERE entity_id = v_helper_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    -- qty 11 raises 'qty too large'
    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_helper_id,
            'help_harvest',
            jsonb_build_object('place_id', v_farm_id, 'qty', 11)
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('qty too large' IN SQLERRM) > 0 THEN
                v_raised_large := TRUE;
            END IF;
    END;

    -- help_harvest at bakery raises 'not a farm'
    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_helper_id,
            'help_harvest',
            jsonb_build_object('place_id', v_bakery_id, 'qty', 5)
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('not a farm' IN SQLERRM) > 0 THEN
                v_raised_nonfarm := TRUE;
            END IF;
    END;

    IF v_farm_grain_after = v_farm_grain_before + 5
       AND v_witness_count = 1
       AND v_sc_cause_count = 1
       AND v_helper_trust = 52
       AND v_raised_large
       AND v_raised_nonfarm THEN
        RAISE NOTICE 'PASS: help_harvest';
    ELSE
        RAISE EXCEPTION 'FAIL: help_harvest (grain_after=%, witnesses=%, sc_causes=%, trust=%, raised_large=%, raised_nonfarm=%)',
            v_farm_grain_after, v_witness_count, v_sc_cause_count, v_helper_trust, v_raised_large, v_raised_nonfarm;
    END IF;
END
$$;

-- 5. gift rule: test_buyer gifts 1 bread to Old Wick
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_buyer_id INT := (SELECT v FROM ctx WHERE k = 'buyer_id');
    v_wick_id INT := (SELECT v FROM ctx WHERE k = 'actor_wick');
    v_bread_id INT := (SELECT v FROM ctx WHERE k = 'item_bread');
    v_gift_rule_id INT;
    v_event_id BIGINT;
    v_wick_mood TEXT;
    v_cause_count INT;
BEGIN
    SELECT rule_id INTO v_gift_rule_id FROM "rule" WHERE trigger_action_type = 'gift';

    v_event_id := apply_action(
        v_branch_id,
        v_buyer_id,
        'gift',
        jsonb_build_object(
            'item_id', v_bread_id,
            'qty', 1,
            'target_actor', v_wick_id
        )
    );

    SELECT state->>'mood' INTO v_wick_mood
    FROM entity_state WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT count(*) INTO v_cause_count
    FROM event_cause
    WHERE cause_id = v_event_id AND rule_id = v_gift_rule_id;

    IF v_wick_mood = 'grateful' AND v_cause_count = 1 THEN
        RAISE NOTICE 'PASS: gift rule';
    ELSE
        RAISE EXCEPTION 'FAIL: gift rule (mood=%, causes=%)', v_wick_mood, v_cause_count;
    END IF;
END
$$;

-- 6. sabotage: test_saboteur sabotages 5 bread at the bakery
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_saboteur_id INT := (SELECT v FROM ctx WHERE k = 'saboteur_id');
    v_bakery_id INT := (SELECT v FROM ctx WHERE k = 'place_bakery');
    v_bread_id INT := (SELECT v FROM ctx WHERE k = 'item_bread');
    v_sabotage_rule_id INT;
    v_bakery_bread_before INT;
    v_bakery_bread_after INT;
    v_bread_total_before BIGINT;
    v_bread_total_after BIGINT;
    v_event_id BIGINT;
    v_witness_count INT;
    v_sched_count INT;
    v_cur_tick INT;
BEGIN
    SELECT rule_id INTO v_sabotage_rule_id FROM "rule" WHERE trigger_action_type = 'sabotage';

    SELECT qty INTO v_bakery_bread_before
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    v_bread_total_before := pg_temp.item_total('bread');
    v_cur_tick := current_tick(v_branch_id);

    v_event_id := apply_action(
        v_branch_id,
        v_saboteur_id,
        'sabotage',
        jsonb_build_object(
            'place_id', v_bakery_id,
            'item_id', v_bread_id,
            'qty', 5
        )
    );

    SELECT qty INTO v_bakery_bread_after
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    v_bread_total_after := pg_temp.item_total('bread');

    SELECT count(*) INTO v_witness_count FROM event_witness WHERE event_id = v_event_id;

    SELECT count(*) INTO v_sched_count
    FROM scheduled_effect
    WHERE source_event_id = v_event_id
      AND rule_id = v_sabotage_rule_id
      AND due_tick = v_cur_tick + 1
      AND NOT processed;

    IF v_bakery_bread_after = v_bakery_bread_before - 5
       AND v_bread_total_after = v_bread_total_before - 5
       AND v_witness_count = 1
       AND v_sched_count = 1 THEN
        RAISE NOTICE 'PASS: sabotage';
    ELSE
        RAISE EXCEPTION 'FAIL: sabotage (bread_diff=%, total_diff=%, witnesses=%, sched_count=%)',
            v_bakery_bread_after - v_bakery_bread_before, v_bread_total_after - v_bread_total_before, v_witness_count, v_sched_count;
    END IF;
END
$$;

-- 7. rumors: slander, praise, weather
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_rumor_id INT := (SELECT v FROM ctx WHERE k = 'rumor_id');
    v_wick_id INT := (SELECT v FROM ctx WHERE k = 'actor_wick');
    v_trust1 NUMERIC;
    v_trust2 NUMERIC;
    v_trust3 NUMERIC;
    v_thief_count INT;
    v_events_before INT;
    v_events_after INT;
    v_total_actors INT;
BEGIN
    SELECT count(*) INTO v_total_actors FROM actor;

    -- Slander
    PERFORM apply_action(
        v_branch_id,
        v_rumor_id,
        'rumor',
        jsonb_build_object('about', v_wick_id, 'text', 'slander')
    );

    SELECT (state->>'trust')::numeric INTO v_trust1
    FROM entity_state WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT count(*) INTO v_thief_count
    FROM event e
    JOIN event_cause ec ON ec.effect_id = e.event_id
    JOIN event parent ON parent.event_id = ec.cause_id
    WHERE e.branch_id = v_branch_id
      AND e.action_type = 'rumor'
      AND (e.payload->>'about')::int = v_wick_id
      AND e.payload->>'text' = 'thief'
      AND parent.action_type = 'state_change'
      AND (SELECT count(*) FROM event_witness ew WHERE ew.event_id = e.event_id) = v_total_actors;

    -- Praise
    PERFORM apply_action(
        v_branch_id,
        v_rumor_id,
        'rumor',
        jsonb_build_object('about', v_wick_id, 'text', 'praise')
    );

    SELECT (state->>'trust')::numeric INTO v_trust2
    FROM entity_state WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    -- Weather
    SELECT count(*) INTO v_events_before FROM event WHERE branch_id = v_branch_id;

    PERFORM apply_action(
        v_branch_id,
        v_rumor_id,
        'rumor',
        jsonb_build_object('about', v_wick_id, 'text', 'weather')
    );

    SELECT count(*) INTO v_events_after FROM event WHERE branch_id = v_branch_id;

    SELECT (state->>'trust')::numeric INTO v_trust3
    FROM entity_state WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    IF v_trust1 = 47
       AND v_thief_count >= 1
       AND v_trust2 = 50
       AND (v_events_after - v_events_before) = 1
       AND v_trust3 = 50 THEN
        RAISE NOTICE 'PASS: rumors';
    ELSE
        RAISE EXCEPTION 'FAIL: rumors (trust1=%, thief_count=%, trust2=%, events_diff=%, trust3=%)',
            v_trust1, v_thief_count, v_trust2, v_events_after - v_events_before, v_trust3;
    END IF;
END
$$;

-- 8. hire: test_boss hires Old Wick with wage 3
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_boss_id INT := (SELECT v FROM ctx WHERE k = 'boss_id');
    v_wick_id INT := (SELECT v FROM ctx WHERE k = 'actor_wick');
    v_baseline_coins NUMERIC := (SELECT v FROM ctx WHERE k = 'baseline_coins');
    v_wick_coins_before NUMERIC;
    v_wick_coins_after NUMERIC;
    v_boss_coins NUMERIC;
    v_wick_employer INT;
    v_event_id BIGINT;
    v_witness_count INT;
    v_coins_now NUMERIC;
    v_raised_coins BOOLEAN := FALSE;
BEGIN
    SELECT (state->>'coins')::numeric INTO v_wick_coins_before
    FROM entity_state WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    v_event_id := apply_action(
        v_branch_id,
        v_boss_id,
        'hire',
        jsonb_build_object('target_actor', v_wick_id, 'wage', 3)
    );

    SELECT (state->>'coins')::numeric INTO v_boss_coins
    FROM entity_state WHERE entity_id = v_boss_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT (state->>'coins')::numeric INTO v_wick_coins_after
    FROM entity_state WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT (state->>'employer')::int INTO v_wick_employer
    FROM entity_state WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT count(*) INTO v_witness_count FROM event_witness WHERE event_id = v_event_id;
    v_coins_now := pg_temp.coin_total();

    -- Second hire with wage 3 raises 'not enough coins'
    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_boss_id,
            'hire',
            jsonb_build_object('target_actor', v_wick_id, 'wage', 3)
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('not enough coins' IN SQLERRM) > 0 THEN
                v_raised_coins := TRUE;
            END IF;
    END;

    IF v_boss_coins = 2
       AND v_wick_coins_after = v_wick_coins_before + 3
       AND v_wick_employer = v_boss_id
       AND v_witness_count = 2
       AND v_coins_now = v_baseline_coins
       AND v_raised_coins THEN
        RAISE NOTICE 'PASS: hire';
    ELSE
        RAISE EXCEPTION 'FAIL: hire (boss_coins=%, wick_coins_diff=%, employer=%, witnesses=%, coins_now=%, raised_coins=%)',
            v_boss_coins, v_wick_coins_after - v_wick_coins_before, v_wick_employer, v_witness_count, v_coins_now, v_raised_coins;
    END IF;
END
$$;

-- 9. recorded-only actions: build and feast
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_buyer_id INT := (SELECT v FROM ctx WHERE k = 'buyer_id');
    v_helper_id INT := (SELECT v FROM ctx WHERE k = 'helper_id');
    v_market_id INT := (SELECT v FROM ctx WHERE k = 'place_market');
    v_build_event_id BIGINT;
    v_feast_event_id BIGINT;
    v_build_witnesses INT;
    v_build_causes INT;
    v_feast_causes INT;
    v_total_actors INT;
BEGIN
    SELECT count(*) INTO v_total_actors FROM actor;

    v_build_event_id := apply_action(
        v_branch_id,
        v_buyer_id,
        'build',
        '{"what":"stall"}'::jsonb
    );

    SELECT count(*) INTO v_build_witnesses FROM event_witness WHERE event_id = v_build_event_id;
    SELECT count(*) INTO v_build_causes FROM event_cause WHERE cause_id = v_build_event_id;

    v_feast_event_id := apply_action(
        v_branch_id,
        v_helper_id,
        'feast',
        jsonb_build_object('place_id', v_market_id)
    );

    SELECT count(*) INTO v_feast_causes FROM event_cause WHERE cause_id = v_feast_event_id;

    IF v_build_witnesses = v_total_actors AND v_build_causes = 0 AND v_feast_causes = 0 THEN
        RAISE NOTICE 'PASS: recorded-only actions';
    ELSE
        RAISE EXCEPTION 'FAIL: recorded-only actions (build_witnesses=%, total_actors=%, build_causes=%, feast_causes=%)',
            v_build_witnesses, v_total_actors, v_build_causes, v_feast_causes;
    END IF;
END
$$;

-- 10. daily routines: advance_day
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_saboteur_id INT := (SELECT v FROM ctx WHERE k = 'saboteur_id');
    v_farm_id INT := (SELECT v FROM ctx WHERE k = 'place_farm');
    v_mill_id INT := (SELECT v FROM ctx WHERE k = 'place_mill');
    v_bakery_id INT := (SELECT v FROM ctx WHERE k = 'place_bakery');
    v_grain_id INT := (SELECT v FROM ctx WHERE k = 'item_grain');
    v_flour_id INT := (SELECT v FROM ctx WHERE k = 'item_flour');
    v_bread_id INT := (SELECT v FROM ctx WHERE k = 'item_bread');

    v_farm_grain_before INT;
    v_mill_grain_before INT;
    v_mill_flour_before INT;
    v_bakery_flour_before INT;
    v_bakery_bread_before INT;

    v_farm_grain_after INT;
    v_mill_grain_after INT;
    v_mill_flour_after INT;
    v_bakery_flour_after INT;
    v_bakery_bread_after INT;

    v_day INT;
    v_day_start_id BIGINT;
    v_produce_count INT;
    v_deliver_count INT;
    v_consume_count INT;
    v_caused_by_day_start INT;
    v_set_price_count INT;
BEGIN
    SELECT qty INTO v_farm_grain_before
    FROM stock WHERE place_id = v_farm_id AND item_id = v_grain_id AND branch_id = v_branch_id;

    SELECT qty INTO v_mill_grain_before
    FROM stock WHERE place_id = v_mill_id AND item_id = v_grain_id AND branch_id = v_branch_id;

    SELECT qty INTO v_mill_flour_before
    FROM stock WHERE place_id = v_mill_id AND item_id = v_flour_id AND branch_id = v_branch_id;

    SELECT qty INTO v_bakery_flour_before
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_flour_id AND branch_id = v_branch_id;

    SELECT qty INTO v_bakery_bread_before
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    v_day := advance_day(v_branch_id);

    SELECT event_id INTO v_day_start_id
    FROM event WHERE branch_id = v_branch_id AND tick = 1 AND action_type = 'day_start';

    SELECT count(*) INTO v_produce_count
    FROM event WHERE branch_id = v_branch_id AND tick = 1 AND action_type = 'produce';

    SELECT count(*) INTO v_deliver_count
    FROM event WHERE branch_id = v_branch_id AND tick = 1 AND action_type = 'deliver';

    SELECT count(*) INTO v_consume_count
    FROM event WHERE branch_id = v_branch_id AND tick = 1 AND action_type = 'consume';

    SELECT count(*) INTO v_caused_by_day_start
    FROM event_cause ec
    JOIN event e ON e.event_id = ec.effect_id
    WHERE e.branch_id = v_branch_id
      AND e.tick = 1
      AND e.action_type IN ('produce', 'deliver', 'consume')
      AND ec.cause_id = v_day_start_id;

    SELECT qty INTO v_farm_grain_after
    FROM stock WHERE place_id = v_farm_id AND item_id = v_grain_id AND branch_id = v_branch_id;

    SELECT qty INTO v_mill_grain_after
    FROM stock WHERE place_id = v_mill_id AND item_id = v_grain_id AND branch_id = v_branch_id;

    SELECT qty INTO v_mill_flour_after
    FROM stock WHERE place_id = v_mill_id AND item_id = v_flour_id AND branch_id = v_branch_id;

    SELECT qty INTO v_bakery_flour_after
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_flour_id AND branch_id = v_branch_id;

    SELECT qty INTO v_bakery_bread_after
    FROM stock WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

    SELECT count(*) INTO v_set_price_count
    FROM event
    WHERE branch_id = v_branch_id
      AND tick = 1
      AND action_type = 'set_price'
      AND (payload->>'culprit')::int = v_saboteur_id;

    IF v_day = 1
       AND v_produce_count = 3
       AND v_deliver_count = 2
       AND v_consume_count = 1
       AND v_caused_by_day_start = 6
       AND (v_farm_grain_after - v_farm_grain_before) = 5
       AND (v_mill_grain_after - v_mill_grain_before) = 0
       AND (v_mill_flour_after - v_mill_flour_before) = 10
       AND (v_bakery_flour_after - v_bakery_flour_before) = 0
       AND (v_bakery_bread_after - v_bakery_bread_before) = 5
       AND v_set_price_count = 1 THEN
        RAISE NOTICE 'PASS: daily routines';
    ELSE
        RAISE EXCEPTION 'FAIL: daily routines (day=%, produce=%, deliver=%, consume=%, causes=%, farm_g_diff=%, mill_g_diff=%, mill_f_diff=%, bak_f_diff=%, bak_b_diff=%, set_price=%)',
            v_day, v_produce_count, v_deliver_count, v_consume_count, v_caused_by_day_start,
            v_farm_grain_after - v_farm_grain_before,
            v_mill_grain_after - v_mill_grain_before,
            v_mill_flour_after - v_mill_flour_before,
            v_bakery_flour_after - v_bakery_flour_before,
            v_bakery_bread_after - v_bakery_bread_before,
            v_set_price_count;
    END IF;
END
$$;

-- 11. stock_at_least condition test
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_buyer_id INT := (SELECT v FROM ctx WHERE k = 'buyer_id');
    v_bakery_id INT := (SELECT v FROM ctx WHERE k = 'place_bakery');
    v_bread_id INT := (SELECT v FROM ctx WHERE k = 'item_bread');
    v_rule_high INT;
    v_rule_low INT;
    v_sc_before INT;
    v_sc_after INT;
    v_build_event_id BIGINT;
    v_low_cause INT;
    v_high_cause INT;
BEGIN
    INSERT INTO "rule" (trigger_action_type, condition, effect_template, delay_ticks, is_active)
    VALUES (
        'build',
        jsonb_build_object('stock_at_least', jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 99999))::text,
        '{"action":"state_change","actor":null,"payload":{"entity_id":"$actor","set":{"mood":"proud"}},"visibility":"private"}',
        0,
        TRUE
    ) RETURNING rule_id INTO v_rule_high;

    INSERT INTO "rule" (trigger_action_type, condition, effect_template, delay_ticks, is_active)
    VALUES (
        'build',
        jsonb_build_object('stock_at_least', jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 1))::text,
        '{"action":"state_change","actor":null,"payload":{"entity_id":"$actor","set":{"mood":"proud"}},"visibility":"private"}',
        0,
        TRUE
    ) RETURNING rule_id INTO v_rule_low;

    SELECT count(*) INTO v_sc_before FROM event WHERE action_type = 'state_change';

    v_build_event_id := apply_action(
        v_branch_id,
        v_buyer_id,
        'build',
        '{"what":"garden"}'::jsonb
    );

    SELECT count(*) INTO v_sc_after FROM event WHERE action_type = 'state_change';

    SELECT count(*) INTO v_low_cause
    FROM event_cause
    WHERE cause_id = v_build_event_id AND rule_id = v_rule_low;

    SELECT count(*) INTO v_high_cause
    FROM event_cause
    WHERE cause_id = v_build_event_id AND rule_id = v_rule_high;

    IF (v_sc_after - v_sc_before) = 1 AND v_low_cause = 1 AND v_high_cause = 0 THEN
        RAISE NOTICE 'PASS: stock_at_least';
    ELSE
        RAISE EXCEPTION 'FAIL: stock_at_least (sc_diff=%, low_cause=%, high_cause=%)',
            v_sc_after - v_sc_before, v_low_cause, v_high_cause;
    END IF;
END
$$;

-- 12. Integrity checks
DO $$
DECLARE
    v_branch_id INT := (SELECT v FROM ctx WHERE k = 'branch_id');
    v_baseline_coins NUMERIC := (SELECT v FROM ctx WHERE k = 'baseline_coins');
    v_chain_problems INT;
    v_coins_now NUMERIC;
    v_null_rule_causes INT;
    v_unmatched_sched INT;
BEGIN
    SELECT count(*) INTO v_chain_problems FROM verify_event_chain(v_branch_id);
    v_coins_now := pg_temp.coin_total();

    SELECT count(*) INTO v_null_rule_causes
    FROM event_cause
    WHERE rule_id IS NULL;

    SELECT count(*) INTO v_unmatched_sched
    FROM scheduled_effect s
    WHERE s.processed
      AND NOT EXISTS (
          SELECT 1
          FROM event_cause ec
          WHERE ec.cause_id = s.source_event_id
            AND ec.rule_id = s.rule_id
      );

    IF v_chain_problems = 0
       AND v_coins_now = v_baseline_coins
       AND v_null_rule_causes = 0
       AND v_unmatched_sched = 0 THEN
        RAISE NOTICE 'PASS: integrity';
    ELSE
        RAISE EXCEPTION 'FAIL: integrity (chain_problems=%, coins_now=%, baseline=%, null_rules=%, unmatched_sched=%)',
            v_chain_problems, v_coins_now, v_baseline_coins, v_null_rule_causes, v_unmatched_sched;
    END IF;
END
$$;

ROLLBACK;

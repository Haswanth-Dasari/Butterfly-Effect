BEGIN;

DO $$
DECLARE
    v_total INT;
    v_bakery INT;
    v_farm INT;
    v_home INT;
    v_inn INT;
    v_market INT;
    v_mill INT;
    v_well INT;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (WHERE kind = 'bakery'),
        count(*) FILTER (WHERE kind = 'farm'),
        count(*) FILTER (WHERE kind = 'home'),
        count(*) FILTER (WHERE kind = 'inn'),
        count(*) FILTER (WHERE kind = 'market'),
        count(*) FILTER (WHERE kind = 'mill'),
        count(*) FILTER (WHERE kind = 'well')
    INTO v_total, v_bakery, v_farm, v_home, v_inn, v_market, v_mill, v_well
    FROM place;

    IF v_total = 18 AND v_bakery = 1 AND v_farm = 3 AND v_home = 10
       AND v_inn = 1 AND v_market = 1 AND v_mill = 1 AND v_well = 1 THEN
        RAISE NOTICE 'PASS: place counts and kinds';
    ELSE
        RAISE EXCEPTION 'FAIL: place counts and kinds (total=%, bakery=%, farm=%, home=%, inn=%, market=%, mill=%, well=%)',
            v_total, v_bakery, v_farm, v_home, v_inn, v_market, v_mill, v_well;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_unoccupied INT;
BEGIN
    SELECT count(*) INTO v_total FROM home;

    SELECT count(*) INTO v_unoccupied
    FROM home AS h
    WHERE NOT EXISTS (
        SELECT 1 FROM actor AS a WHERE a.home_id = h.home_id
    );

    IF v_total = 10 AND v_unoccupied = 0 THEN
        RAISE NOTICE 'PASS: home counts and occupancy';
    ELSE
        RAISE EXCEPTION 'FAIL: home counts and occupancy (total=%, unoccupied=%)', v_total, v_unoccupied;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_valid INT;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (WHERE kind = 'villager' AND home_id IS NOT NULL)
    INTO v_total, v_valid
    FROM actor;

    IF v_total = 30 AND v_valid = 30 THEN
        RAISE NOTICE 'PASS: actor count and validity';
    ELSE
        RAISE EXCEPTION 'FAIL: actor count and validity (total=%, valid=%)', v_total, v_valid;
    END IF;
END
$$;

DO $$
DECLARE
    v_baker INT;
    v_miller INT;
    v_innkeeper INT;
    v_well_keeper INT;
    v_mill_helper INT;
BEGIN
    SELECT
        count(*) FILTER (WHERE job = 'baker'),
        count(*) FILTER (WHERE job = 'miller'),
        count(*) FILTER (WHERE job = 'innkeeper'),
        count(*) FILTER (WHERE job = 'well_keeper'),
        count(*) FILTER (WHERE job = 'mill_helper')
    INTO v_baker, v_miller, v_innkeeper, v_well_keeper, v_mill_helper
    FROM actor;

    IF v_baker = 1 AND v_miller = 1 AND v_innkeeper = 1 AND v_well_keeper = 1 AND v_mill_helper >= 1 THEN
        RAISE NOTICE 'PASS: job requirements';
    ELSE
        RAISE EXCEPTION 'FAIL: job requirements (baker=%, miller=%, innkeeper=%, well_keeper=%, mill_helper=%)',
            v_baker, v_miller, v_innkeeper, v_well_keeper, v_mill_helper;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_mill_helper INT;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (WHERE a.job = 'mill_helper')
    INTO v_total, v_mill_helper
    FROM actor AS a
    JOIN home AS h ON h.home_id = a.home_id
    WHERE h.family_name = 'Hollis';

    IF v_total = 4 AND v_mill_helper >= 1 THEN
        RAISE NOTICE 'PASS: Hollis household structure';
    ELSE
        RAISE EXCEPTION 'FAIL: Hollis household structure (total=%, mill_helper=%)', v_total, v_mill_helper;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_valid INT;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (WHERE name IN ('bread', 'grain', 'flour'))
    INTO v_total, v_valid
    FROM item;

    IF v_total = 3 AND v_valid = 3 THEN
        RAISE NOTICE 'PASS: item inventory';
    ELSE
        RAISE EXCEPTION 'FAIL: item inventory (total=%, valid=%)', v_total, v_valid;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_valid INT;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (WHERE branch_id = 1 AND qty > 0 AND price > 0)
    INTO v_total, v_valid
    FROM stock;

    IF v_total = 7 AND v_valid = 7 THEN
        RAISE NOTICE 'PASS: stock records';
    ELSE
        RAISE EXCEPTION 'FAIL: stock records (total=%, valid=%)', v_total, v_valid;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_player_actions INT;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (WHERE action_type IN (
            'gift', 'trade', 'steal', 'rumor', 'build',
            'hire', 'set_price', 'help_harvest', 'sabotage', 'feast'
        ))
    INTO v_total, v_player_actions
    FROM action_type;

    IF v_total = 22 AND v_player_actions = 10 THEN
        RAISE NOTICE 'PASS: action_type records';
    ELSE
        RAISE EXCEPTION 'FAIL: action_type records (total=%, player_actions=%)', v_total, v_player_actions;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_distinct_entities INT;
    v_valid_ticks INT;
    v_valid_keys INT;
BEGIN
    SELECT
        count(*),
        count(DISTINCT es.entity_id),
        count(*) FILTER (WHERE es.valid_ticks = '[0,)'::int4range),
        count(*) FILTER (WHERE es.state ? 'mood' AND es.state ? 'trust' AND es.state ? 'coins')
    INTO v_total, v_distinct_entities, v_valid_ticks, v_valid_keys
    FROM entity_state AS es
    JOIN actor AS a ON a.actor_id = es.entity_id;

    IF v_total = 30 AND v_distinct_entities = 30 AND v_valid_ticks = 30 AND v_valid_keys = 30 THEN
        RAISE NOTICE 'PASS: entity_state records';
    ELSE
        RAISE EXCEPTION 'FAIL: entity_state records (total=%, distinct=%, valid_ticks=%, valid_keys=%)',
            v_total, v_distinct_entities, v_valid_ticks, v_valid_keys;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_count INT;
    v_event_count INT;
    v_event_valid INT;
    v_chain_problems INT;
BEGIN
    SELECT count(*)
    INTO v_branch_count
    FROM branch
    WHERE name = 'main' AND parent_id IS NULL;

    SELECT
        count(*),
        count(*) FILTER (
            WHERE tick = 0
              AND action_type = 'world_start'
              AND actor_id IS NULL
              AND hash IS NOT NULL
              AND prev_hash IS NULL
        )
    INTO v_event_count, v_event_valid
    FROM event;

    SELECT count(*)
    INTO v_chain_problems
    FROM verify_event_chain();

    IF v_branch_count = 1 AND v_event_count = 1 AND v_event_valid = 1 AND v_chain_problems = 0 THEN
        RAISE NOTICE 'PASS: branch, genesis event, and event chain verification';
    ELSE
        RAISE EXCEPTION 'FAIL: branch, genesis event, and event chain verification (branch=%, event_count=%, event_valid=%, chain_problems=%)',
            v_branch_count, v_event_count, v_event_valid, v_chain_problems;
    END IF;
END
$$;

DO $$
DECLARE
    v_place_last BIGINT;
    v_home_last BIGINT;
    v_actor_last BIGINT;
    v_item_last BIGINT;
    v_branch_last BIGINT;
    v_place_max BIGINT;
    v_home_max BIGINT;
    v_actor_max BIGINT;
    v_item_max BIGINT;
    v_branch_max BIGINT;
BEGIN
    SELECT last_value INTO v_place_last FROM pg_sequences WHERE sequencename = 'place_place_id_seq';
    SELECT last_value INTO v_home_last FROM pg_sequences WHERE sequencename = 'home_home_id_seq';
    SELECT last_value INTO v_actor_last FROM pg_sequences WHERE sequencename = 'actor_actor_id_seq';
    SELECT last_value INTO v_item_last FROM pg_sequences WHERE sequencename = 'item_item_id_seq';
    SELECT last_value INTO v_branch_last FROM pg_sequences WHERE sequencename = 'branch_branch_id_seq';

    SELECT COALESCE(max(place_id), 0) INTO v_place_max FROM place;
    SELECT COALESCE(max(home_id), 0) INTO v_home_max FROM home;
    SELECT COALESCE(max(actor_id), 0) INTO v_actor_max FROM actor;
    SELECT COALESCE(max(item_id), 0) INTO v_item_max FROM item;
    SELECT COALESCE(max(branch_id), 0) INTO v_branch_max FROM branch;

    IF v_place_last IS NOT NULL AND v_place_last >= v_place_max
       AND v_home_last IS NOT NULL AND v_home_last >= v_home_max
       AND v_actor_last IS NOT NULL AND v_actor_last >= v_actor_max
       AND v_item_last IS NOT NULL AND v_item_last >= v_item_max
       AND v_branch_last IS NOT NULL AND v_branch_last >= v_branch_max THEN
        RAISE NOTICE 'PASS: sequences advanced';
    ELSE
        RAISE EXCEPTION 'FAIL: sequences advanced (place: last=% max=%, home: last=% max=%, actor: last=% max=%, item: last=% max=%, branch: last=% max=%)',
            v_place_last, v_place_max, v_home_last, v_home_max, v_actor_last, v_actor_max,
            v_item_last, v_item_max, v_branch_last, v_branch_max;
    END IF;
END
$$;

DO $$
DECLARE
    v_total INT;
    v_active INT;
    v_steal INT;
    v_set_price INT;
    v_state_change INT;
    v_day_start INT;
    v_sabotage INT;
    v_gift INT;
    v_help_harvest INT;
    v_rumor INT;
    v_trade INT;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (WHERE is_active),
        count(*) FILTER (WHERE trigger_action_type = 'steal'),
        count(*) FILTER (WHERE trigger_action_type = 'set_price'),
        count(*) FILTER (WHERE trigger_action_type = 'state_change'),
        count(*) FILTER (WHERE trigger_action_type = 'day_start'),
        count(*) FILTER (WHERE trigger_action_type = 'sabotage'),
        count(*) FILTER (WHERE trigger_action_type = 'gift'),
        count(*) FILTER (WHERE trigger_action_type = 'help_harvest'),
        count(*) FILTER (WHERE trigger_action_type = 'rumor'),
        count(*) FILTER (WHERE trigger_action_type = 'trade')
    INTO
        v_total, v_active, v_steal, v_set_price, v_state_change,
        v_day_start, v_sabotage, v_gift, v_help_harvest, v_rumor, v_trade
    FROM "rule";

    IF v_total = 15 AND v_active = 15
       AND v_steal = 1 AND v_set_price = 1 AND v_state_change = 1
       AND v_day_start = 6 AND v_sabotage = 1 AND v_gift = 1
       AND v_help_harvest = 1 AND v_rumor = 2 AND v_trade = 1 THEN
        RAISE NOTICE 'PASS: rules seeded';
    ELSE
        RAISE EXCEPTION 'FAIL: rules seeded (total=%, active=%, steal=%, set_price=%, state_change=%, day_start=%, sabotage=%, gift=%, help_harvest=%, rumor=%, trade=%)',
            v_total, v_active, v_steal, v_set_price, v_state_change,
            v_day_start, v_sabotage, v_gift, v_help_harvest, v_rumor, v_trade;
    END IF;
END
$$;

-- 13. Baseline snapshot
DO $$
DECLARE
    v_snap_count INT;
    v_snap snapshot;
    v_genesis_id BIGINT;
    v_main_id INT;
    v_stock_len INT;
    v_entities_len INT;
    v_pending_len INT;
BEGIN
    SELECT branch_id INTO v_main_id FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT event_id INTO v_genesis_id FROM event WHERE branch_id = v_main_id AND action_type = 'world_start' AND tick = 0;

    SELECT count(*) INTO v_snap_count FROM snapshot;
    SELECT * INTO v_snap FROM snapshot WHERE branch_id = v_main_id;

    v_stock_len := jsonb_array_length(v_snap.state->'stock');
    v_entities_len := jsonb_array_length(v_snap.state->'entities');
    v_pending_len := jsonb_array_length(v_snap.state->'pending');

    IF v_snap_count = 1
       AND v_snap.branch_id = v_main_id
       AND v_snap.tick = 0
       AND v_snap.last_event_id = v_genesis_id
       AND v_stock_len = 7
       AND v_entities_len = 30
       AND v_pending_len = 0 THEN
        RAISE NOTICE 'PASS: baseline snapshot';
    ELSE
        RAISE EXCEPTION 'FAIL: baseline snapshot (count=%, branch=%, tick=%, last_event=%, genesis=%, stock=%, entities=%, pending=%)',
            v_snap_count, v_snap.branch_id, v_snap.tick, v_snap.last_event_id, v_genesis_id, v_stock_len, v_entities_len, v_pending_len;
    END IF;
END
$$;

ROLLBACK;

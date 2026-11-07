BEGIN;

CREATE TEMP TABLE ctx (
    k TEXT PRIMARY KEY,
    v BIGINT
);

CREATE FUNCTION pg_temp.bread_total()
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    SELECT
        COALESCE((
            SELECT SUM(s.qty)
            FROM stock AS s
            JOIN item AS i ON i.item_id = s.item_id
            JOIN branch AS b ON b.branch_id = s.branch_id
            WHERE b.name = 'main' AND i.name = 'bread'
        ), 0)::BIGINT
        +
        COALESCE((
            SELECT SUM((es.state->'inv'->>'bread')::BIGINT)
            FROM entity_state AS es
            JOIN branch AS b ON b.branch_id = es.branch_id
            WHERE b.name = 'main'
              AND upper_inf(es.valid_ticks)
              AND es.state->'inv'->>'bread' IS NOT NULL
        ), 0)::BIGINT;
$$;

INSERT INTO ctx (k, v)
VALUES ('bread_total', pg_temp.bread_total());

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_actor_kind TEXT;
    v_state JSONB;
    v_arrive_count INT;
    v_witness_count INT;
    v_total_actors INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';

    v_alpha_id := join_village(v_branch_id, 'test_alpha');
    INSERT INTO ctx (k, v) VALUES ('alpha_id', v_alpha_id);

    SELECT kind INTO v_actor_kind FROM actor WHERE actor_id = v_alpha_id;

    SELECT state INTO v_state
    FROM entity_state
    WHERE entity_id = v_alpha_id
      AND branch_id = v_branch_id
      AND upper_inf(valid_ticks);

    SELECT count(*) INTO v_arrive_count
    FROM event
    WHERE branch_id = v_branch_id
      AND actor_id = v_alpha_id
      AND action_type = 'arrive';

    SELECT count(*) INTO v_witness_count
    FROM event_witness AS ew
    JOIN event AS e ON e.event_id = ew.event_id
    WHERE e.branch_id = v_branch_id
      AND e.actor_id = v_alpha_id
      AND e.action_type = 'arrive';

    SELECT count(*) INTO v_total_actors FROM actor;

    IF v_actor_kind = 'player'
       AND (v_state->>'coins')::int = 5
       AND (v_state->>'trust')::int = 50
       AND v_state->'inv' = '{}'::jsonb
       AND v_arrive_count = 1
       AND v_witness_count = v_total_actors THEN
        RAISE NOTICE 'PASS: join village alpha';
    ELSE
        RAISE EXCEPTION 'FAIL: join village alpha (kind=%, state=%, arrive=%, witnesses=%, total_actors=%)',
            v_actor_kind, v_state, v_arrive_count, v_witness_count, v_total_actors;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_tt_id INT;
    v_cur_tick INT;
    v_row_count_1 INT;
    v_coins_1 INT;
    v_row_count_2 INT;
    v_range_1 INT4RANGE;
    v_range_2 INT4RANGE;
    v_coins_at_0 INT;
    v_coins_at_5 INT;
    v_coins_at_7 INT;
    v_raised_before BOOLEAN := FALSE;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';

    v_tt_id := join_village(v_branch_id, 'test_timetravel');
    v_cur_tick := current_tick(v_branch_id);

    PERFORM patch_entity_state(v_tt_id, v_branch_id, v_cur_tick, '{"coins": 4}'::jsonb);

    SELECT count(*), max((state->>'coins')::int)
    INTO v_row_count_1, v_coins_1
    FROM entity_state
    WHERE entity_id = v_tt_id AND branch_id = v_branch_id;

    PERFORM patch_entity_state(v_tt_id, v_branch_id, 5, '{"coins": 3}'::jsonb);

    SELECT count(*) INTO v_row_count_2
    FROM entity_state
    WHERE entity_id = v_tt_id AND branch_id = v_branch_id;

    SELECT valid_ticks INTO v_range_1
    FROM entity_state
    WHERE entity_id = v_tt_id AND branch_id = v_branch_id AND NOT upper_inf(valid_ticks);

    SELECT valid_ticks INTO v_range_2
    FROM entity_state
    WHERE entity_id = v_tt_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    v_coins_at_0 := (entity_state_at(v_tt_id, v_branch_id, 0)->>'coins')::int;
    v_coins_at_5 := (entity_state_at(v_tt_id, v_branch_id, 5)->>'coins')::int;
    v_coins_at_7 := (entity_state_at(v_tt_id, v_branch_id, 7)->>'coins')::int;

    BEGIN
        PERFORM patch_entity_state(v_tt_id, v_branch_id, 2, '{"coins": 2}'::jsonb);
    EXCEPTION
        WHEN OTHERS THEN
            IF position('before the current state begins' IN SQLERRM) > 0 THEN
                v_raised_before := TRUE;
            ELSE
                RAISE EXCEPTION 'FAIL: time travel patch wrong error (%)', SQLERRM;
            END IF;
    END;

    IF v_row_count_1 = 1 AND v_coins_1 = 4
       AND v_row_count_2 = 2
       AND v_range_1 = '[0,5)'::int4range
       AND v_range_2 = '[5,)'::int4range
       AND v_coins_at_0 = 4 AND v_coins_at_5 = 3 AND v_coins_at_7 = 3
       AND v_raised_before THEN
        RAISE NOTICE 'PASS: time travel entity state';
    ELSE
        RAISE EXCEPTION 'FAIL: time travel entity state (rows1=%, coins1=%, rows2=%, r1=%, r2=%, c0=%, c5=%, c7=%, raised=%)',
            v_row_count_1, v_coins_1, v_row_count_2, v_range_1, v_range_2,
            v_coins_at_0, v_coins_at_5, v_coins_at_7, v_raised_before;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_place_id INT;
    v_item_id INT;
    v_bakery_qty_before INT;
    v_bakery_qty_after INT;
    v_event_id BIGINT;
    v_alpha_bread INT;
    v_hash_len INT;
    v_witness_count INT;
    v_witness_actor INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';
    SELECT place_id INTO v_place_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_item_id FROM item WHERE name = 'bread';

    SELECT qty INTO v_bakery_qty_before
    FROM stock
    WHERE place_id = v_place_id AND item_id = v_item_id AND branch_id = v_branch_id;

    v_event_id := apply_action(
        v_branch_id,
        v_alpha_id,
        'steal',
        jsonb_build_object('place_id', v_place_id, 'item_id', v_item_id, 'qty', 1)
    );

    SELECT qty INTO v_bakery_qty_after
    FROM stock
    WHERE place_id = v_place_id AND item_id = v_item_id AND branch_id = v_branch_id;

    SELECT (state->'inv'->>'bread')::int INTO v_alpha_bread
    FROM entity_state
    WHERE entity_id = v_alpha_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT octet_length(hash) INTO v_hash_len
    FROM event
    WHERE event_id = v_event_id;

    SELECT count(*), min(actor_id) INTO v_witness_count, v_witness_actor
    FROM event_witness
    WHERE event_id = v_event_id;

    IF v_bakery_qty_after = v_bakery_qty_before - 1
       AND v_alpha_bread = 1
       AND v_hash_len = 32
       AND v_witness_count = 1
       AND v_witness_actor = v_alpha_id THEN
        RAISE NOTICE 'PASS: alpha steals bread';
    ELSE
        RAISE EXCEPTION 'FAIL: alpha steals bread (before=%, after=%, inv=%, hash_len=%, witnesses=%, witness_actor=%)',
            v_bakery_qty_before, v_bakery_qty_after, v_alpha_bread, v_hash_len, v_witness_count, v_witness_actor;
    END IF;
END
$$;

DO $$
DECLARE
    v_current_total BIGINT;
    v_initial_total BIGINT;
BEGIN
    v_current_total := pg_temp.bread_total();
    SELECT v INTO v_initial_total FROM ctx WHERE k = 'bread_total';

    IF v_current_total = v_initial_total THEN
        RAISE NOTICE 'PASS: bread conservation after steal';
    ELSE
        RAISE EXCEPTION 'FAIL: bread conservation after steal (current=%, initial=%)',
            v_current_total, v_initial_total;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_wick_id INT;
    v_item_id INT;
    v_event_id BIGINT;
    v_alpha_bread INT;
    v_wick_bread INT;
    v_witness_count INT;
    v_current_total BIGINT;
    v_initial_total BIGINT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';
    SELECT actor_id INTO v_wick_id FROM actor WHERE name = 'Old Wick';
    SELECT item_id INTO v_item_id FROM item WHERE name = 'bread';
    SELECT v INTO v_initial_total FROM ctx WHERE k = 'bread_total';

    v_event_id := apply_action(
        v_branch_id,
        v_alpha_id,
        'gift',
        jsonb_build_object('item_id', v_item_id, 'qty', 1, 'target_actor', v_wick_id)
    );

    SELECT (state->'inv'->>'bread')::int INTO v_alpha_bread
    FROM entity_state
    WHERE entity_id = v_alpha_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT (state->'inv'->>'bread')::int INTO v_wick_bread
    FROM entity_state
    WHERE entity_id = v_wick_id AND branch_id = v_branch_id AND upper_inf(valid_ticks);

    SELECT count(*) INTO v_witness_count
    FROM event_witness
    WHERE event_id = v_event_id;

    v_current_total := pg_temp.bread_total();

    IF v_alpha_bread = 0
       AND v_wick_bread = 1
       AND v_witness_count = 2
       AND v_current_total = v_initial_total THEN
        RAISE NOTICE 'PASS: alpha gifts bread to Old Wick';
    ELSE
        RAISE EXCEPTION 'FAIL: alpha gifts bread to Old Wick (alpha_inv=%, wick_inv=%, witnesses=%, total=%, expected=%)',
            v_alpha_bread, v_wick_bread, v_witness_count, v_current_total, v_initial_total;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_wick_id INT;
    v_item_id INT;
    v_event_count_before INT;
    v_event_count_after INT;
    v_raised_insufficient BOOLEAN := FALSE;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';
    SELECT actor_id INTO v_wick_id FROM actor WHERE name = 'Old Wick';
    SELECT item_id INTO v_item_id FROM item WHERE name = 'bread';

    SELECT count(*) INTO v_event_count_before FROM event WHERE branch_id = v_branch_id;

    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_alpha_id,
            'gift',
            jsonb_build_object('item_id', v_item_id, 'qty', 1, 'target_actor', v_wick_id)
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('insufficient inventory' IN SQLERRM) > 0 THEN
                v_raised_insufficient := TRUE;
            ELSE
                RAISE EXCEPTION 'FAIL: alpha gifts 0 bread wrong error (%)', SQLERRM;
            END IF;
    END;

    SELECT count(*) INTO v_event_count_after FROM event WHERE branch_id = v_branch_id;

    IF v_raised_insufficient AND v_event_count_after = v_event_count_before THEN
        RAISE NOTICE 'PASS: gifting with insufficient inventory fails cleanly';
    ELSE
        RAISE EXCEPTION 'FAIL: gifting with insufficient inventory (raised=%, before=%, after=%)',
            v_raised_insufficient, v_event_count_before, v_event_count_after;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_place_id INT;
    v_item_id INT;
    v_stock_before INT;
    v_stock_after INT;
    v_event_count_before INT;
    v_event_count_after INT;
    v_raised_check BOOLEAN := FALSE;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';
    SELECT place_id INTO v_place_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_item_id FROM item WHERE name = 'bread';

    SELECT qty INTO v_stock_before
    FROM stock
    WHERE place_id = v_place_id AND item_id = v_item_id AND branch_id = v_branch_id;

    SELECT count(*) INTO v_event_count_before FROM event WHERE branch_id = v_branch_id;

    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_alpha_id,
            'steal',
            jsonb_build_object('place_id', v_place_id, 'item_id', v_item_id, 'qty', 999)
        );
    EXCEPTION
        WHEN check_violation THEN
            v_raised_check := TRUE;
    END;

    SELECT qty INTO v_stock_after
    FROM stock
    WHERE place_id = v_place_id AND item_id = v_item_id AND branch_id = v_branch_id;

    SELECT count(*) INTO v_event_count_after FROM event WHERE branch_id = v_branch_id;

    IF v_raised_check AND v_stock_after = v_stock_before AND v_event_count_after = v_event_count_before THEN
        RAISE NOTICE 'PASS: excessive steal fails check constraint';
    ELSE
        RAISE EXCEPTION 'FAIL: excessive steal fails check constraint (raised=%, stock_before=%, stock_after=%, events_before=%, events_after=%)',
            v_raised_check, v_stock_before, v_stock_after, v_event_count_before, v_event_count_after;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_place_id INT;
    v_item_id INT;
    v_event_id BIGINT;
    v_price NUMERIC(10,2);
    v_witness_count INT;
    v_total_actors INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';
    SELECT place_id INTO v_place_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_item_id FROM item WHERE name = 'bread';

    v_event_id := apply_action(
        v_branch_id,
        v_alpha_id,
        'set_price',
        jsonb_build_object('place_id', v_place_id, 'item_id', v_item_id, 'price', 2.50)
    );

    SELECT price INTO v_price
    FROM stock
    WHERE place_id = v_place_id AND item_id = v_item_id AND branch_id = v_branch_id;

    SELECT count(*) INTO v_witness_count
    FROM event_witness
    WHERE event_id = v_event_id;

    SELECT count(*) INTO v_total_actors FROM actor;

    IF v_price = 2.50 AND v_witness_count = v_total_actors THEN
        RAISE NOTICE 'PASS: alpha set price';
    ELSE
        RAISE EXCEPTION 'FAIL: alpha set price (price=%, witnesses=%, total_actors=%)',
            v_price, v_witness_count, v_total_actors;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_place_id INT;
    v_item_id INT;
    v_event_count_before INT;
    v_event_count_after INT;
    v_raised_limit BOOLEAN := FALSE;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';
    SELECT place_id INTO v_place_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_item_id FROM item WHERE name = 'bread';

    SELECT count(*) INTO v_event_count_before FROM event WHERE branch_id = v_branch_id;

    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_alpha_id,
            'set_price',
            jsonb_build_object('place_id', v_place_id, 'item_id', v_item_id, 'price', 3.00)
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('no actions left today' IN SQLERRM) > 0 THEN
                v_raised_limit := TRUE;
            ELSE
                RAISE EXCEPTION 'FAIL: fourth action wrong error (%)', SQLERRM;
            END IF;
    END;

    SELECT count(*) INTO v_event_count_after FROM event WHERE branch_id = v_branch_id;

    IF v_raised_limit AND v_event_count_after = v_event_count_before THEN
        RAISE NOTICE 'PASS: action limit reached';
    ELSE
        RAISE EXCEPTION 'FAIL: action limit reached (raised=%, before=%, after=%)',
            v_raised_limit, v_event_count_before, v_event_count_after;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_beta_id INT;
    v_place_id INT;
    v_item_id INT;
    v_raised_not_player BOOLEAN := FALSE;
    v_raised_unknown_actor BOOLEAN := FALSE;
    v_raised_qty_positive BOOLEAN := FALSE;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';
    SELECT place_id INTO v_place_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_item_id FROM item WHERE name = 'bread';

    BEGIN
        PERFORM apply_action(v_branch_id, v_alpha_id, 'drought', '{}'::jsonb);
    EXCEPTION
        WHEN OTHERS THEN
            IF position('not a player action' IN SQLERRM) > 0 THEN
                v_raised_not_player := TRUE;
            ELSE
                RAISE EXCEPTION 'FAIL: drought action wrong error (%)', SQLERRM;
            END IF;
    END;

    BEGIN
        PERFORM apply_action(
            v_branch_id,
            999999,
            'steal',
            jsonb_build_object('place_id', v_place_id, 'item_id', v_item_id, 'qty', 1)
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('unknown actor' IN SQLERRM) > 0 THEN
                v_raised_unknown_actor := TRUE;
            ELSE
                RAISE EXCEPTION 'FAIL: unknown actor wrong error (%)', SQLERRM;
            END IF;
    END;

    v_beta_id := join_village(v_branch_id, 'test_beta');
    BEGIN
        PERFORM apply_action(
            v_branch_id,
            v_beta_id,
            'steal',
            jsonb_build_object('place_id', v_place_id, 'item_id', v_item_id, 'qty', 0)
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF position('qty must be positive' IN SQLERRM) > 0 THEN
                v_raised_qty_positive := TRUE;
            ELSE
                RAISE EXCEPTION 'FAIL: qty 0 steal wrong error (%)', SQLERRM;
            END IF;
    END;

    IF v_raised_not_player AND v_raised_unknown_actor AND v_raised_qty_positive THEN
        RAISE NOTICE 'PASS: invalid calls rejected';
    ELSE
        RAISE EXCEPTION 'FAIL: invalid calls rejected (not_player=%, unknown_actor=%, qty_positive=%)',
            v_raised_not_player, v_raised_unknown_actor, v_raised_qty_positive;
    END IF;
END
$$;

DO $$
DECLARE
    v_branch_id INT;
    v_alpha_id INT;
    v_chain_problems INT;
    v_actions TEXT[];
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT v INTO v_alpha_id FROM ctx WHERE k = 'alpha_id';

    SELECT count(*) INTO v_chain_problems FROM verify_event_chain();

    SELECT array_agg(action_type ORDER BY event_id)
    INTO v_actions
    FROM event
    WHERE branch_id = v_branch_id
      AND actor_id = v_alpha_id
      AND action_type <> 'arrive';

    IF v_chain_problems = 0 AND v_actions = ARRAY['steal', 'gift', 'set_price'] THEN
        RAISE NOTICE 'PASS: event chain valid and alpha action history';
    ELSE
        RAISE EXCEPTION 'FAIL: event chain valid and alpha action history (chain_problems=%, actions=%)',
            v_chain_problems, v_actions;
    END IF;
END
$$;

ROLLBACK;

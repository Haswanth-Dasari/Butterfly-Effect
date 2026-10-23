BEGIN;

-- Test 1: reset_loaves(5) leaves shelf qty 5 and 0 sales.
DO $$
DECLARE
    v_qty INT;
    v_sales BIGINT;
BEGIN
    PERFORM lab.reset_loaves(5);
    SELECT qty INTO v_qty FROM lab.shelf WHERE item = 'bread';
    SELECT count(*) INTO v_sales FROM lab.sale;
    IF v_qty = 5 AND v_sales = 0 THEN
        RAISE NOTICE 'PASS: reset_loaves';
    ELSE
        RAISE EXCEPTION 'FAIL: reset_loaves (expected qty=5, sales=0; got qty=%, sales=%)', v_qty, v_sales;
    END IF;
END;
$$;

-- Test 2: buy_naive
DO $$
DECLARE
    v_res TEXT;
    v_qty INT;
    v_sales BIGINT;
BEGIN
    PERFORM lab.reset_loaves(5);
    FOR i IN 1..5 LOOP
        v_res := lab.buy_naive(i);
        IF v_res <> 'sold' THEN
            RAISE EXCEPTION 'FAIL: buy_naive (call % returned % instead of sold)', i, v_res;
        END IF;
    END LOOP;
    v_res := lab.buy_naive(6);
    IF v_res <> 'sold_out' THEN
        RAISE EXCEPTION 'FAIL: buy_naive (call 6 returned % instead of sold_out)', v_res;
    END IF;
    SELECT qty INTO v_qty FROM lab.shelf WHERE item = 'bread';
    SELECT count(*) INTO v_sales FROM lab.sale;
    IF v_qty = 0 AND v_sales = 5 THEN
        RAISE NOTICE 'PASS: buy_naive';
    ELSE
        RAISE EXCEPTION 'FAIL: buy_naive (expected qty=0, sales=5; got qty=%, sales=%)', v_qty, v_sales;
    END IF;
END;
$$;

-- Test 3: buy_for_update
DO $$
DECLARE
    v_res TEXT;
    v_qty INT;
    v_sales BIGINT;
BEGIN
    PERFORM lab.reset_loaves(5);
    FOR i IN 1..5 LOOP
        v_res := lab.buy_for_update(i);
        IF v_res <> 'sold' THEN
            RAISE EXCEPTION 'FAIL: buy_for_update (call % returned % instead of sold)', i, v_res;
        END IF;
    END LOOP;
    v_res := lab.buy_for_update(6);
    IF v_res <> 'sold_out' THEN
        RAISE EXCEPTION 'FAIL: buy_for_update (call 6 returned % instead of sold_out)', v_res;
    END IF;
    SELECT qty INTO v_qty FROM lab.shelf WHERE item = 'bread';
    SELECT count(*) INTO v_sales FROM lab.sale;
    IF v_qty = 0 AND v_sales = 5 THEN
        RAISE NOTICE 'PASS: buy_for_update';
    ELSE
        RAISE EXCEPTION 'FAIL: buy_for_update (expected qty=0, sales=5; got qty=%, sales=%)', v_qty, v_sales;
    END IF;
END;
$$;

-- Test 4: buy_atomic_check
DO $$
DECLARE
    v_res TEXT;
    v_qty INT;
    v_sales BIGINT;
BEGIN
    PERFORM lab.reset_loaves(5);
    FOR i IN 1..5 LOOP
        v_res := lab.buy_atomic_check(i);
        IF v_res <> 'sold' THEN
            RAISE EXCEPTION 'FAIL: buy_atomic_check (call % returned % instead of sold)', i, v_res;
        END IF;
    END LOOP;
    v_res := lab.buy_atomic_check(6);
    IF v_res <> 'sold_out' THEN
        RAISE EXCEPTION 'FAIL: buy_atomic_check (call 6 returned % instead of sold_out)', v_res;
    END IF;
    SELECT qty INTO v_qty FROM lab.shelf WHERE item = 'bread';
    SELECT count(*) INTO v_sales FROM lab.sale;
    IF v_qty = 0 AND v_sales = 5 THEN
        RAISE NOTICE 'PASS: buy_atomic_check';
    ELSE
        RAISE EXCEPTION 'FAIL: buy_atomic_check (expected qty=0, sales=5; got qty=%, sales=%)', v_qty, v_sales;
    END IF;
END;
$$;

-- Test 5: buy_optimistic
DO $$
DECLARE
    v_res TEXT;
    v_qty INT;
    v_sales BIGINT;
BEGIN
    PERFORM lab.reset_loaves(5);
    FOR i IN 1..5 LOOP
        v_res := lab.buy_optimistic(i);
        IF v_res <> 'sold' THEN
            RAISE EXCEPTION 'FAIL: buy_optimistic (call % returned % instead of sold)', i, v_res;
        END IF;
    END LOOP;
    v_res := lab.buy_optimistic(6);
    IF v_res <> 'sold_out' THEN
        RAISE EXCEPTION 'FAIL: buy_optimistic (call 6 returned % instead of sold_out)', v_res;
    END IF;
    SELECT qty INTO v_qty FROM lab.shelf WHERE item = 'bread';
    SELECT count(*) INTO v_sales FROM lab.sale;
    IF v_qty = 0 AND v_sales = 5 THEN
        RAISE NOTICE 'PASS: buy_optimistic';
    ELSE
        RAISE EXCEPTION 'FAIL: buy_optimistic (expected qty=0, sales=5; got qty=%, sales=%)', v_qty, v_sales;
    END IF;
END;
$$;

-- Test 6: reset_purses(); transfer_unordered('alice','bob',5) and transfer_ordered('bob','alice',7): total coins 200, alice 102, bob 98, and 2 rows in lab.transfer_log.
DO $$
DECLARE
    v_total_coins BIGINT;
    v_alice_coins INT;
    v_bob_coins INT;
    v_log_count BIGINT;
BEGIN
    PERFORM lab.reset_purses();
    PERFORM lab.transfer_unordered('alice', 'bob', 5);
    PERFORM lab.transfer_ordered('bob', 'alice', 7);
    SELECT SUM(coins),
           MAX(CASE WHEN owner = 'alice' THEN coins END),
           MAX(CASE WHEN owner = 'bob' THEN coins END)
    INTO v_total_coins, v_alice_coins, v_bob_coins
    FROM lab.purse;
    SELECT count(*) INTO v_log_count FROM lab.transfer_log;
    IF v_total_coins = 200 AND v_alice_coins = 102 AND v_bob_coins = 98 AND v_log_count = 2 THEN
        RAISE NOTICE 'PASS: transfer_purses';
    ELSE
        RAISE EXCEPTION 'FAIL: transfer_purses (expected total=200, alice=102, bob=98, log=2; got total=%, alice=%, bob=%, log=%)',
            v_total_coins, v_alice_coins, v_bob_coins, v_log_count;
    END IF;
END;
$$;

ROLLBACK;

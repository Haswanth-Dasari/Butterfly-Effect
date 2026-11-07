-- Schema and functions for concurrency experiments (isolated from game tables)
DROP SCHEMA IF EXISTS lab CASCADE;
CREATE SCHEMA lab;

-- Tables
CREATE TABLE lab.shelf (
    item TEXT PRIMARY KEY,
    qty INT NOT NULL CHECK (qty >= 0)
);

CREATE TABLE lab.sale (
    sale_id BIGSERIAL PRIMARY KEY,
    client INT NOT NULL,
    sold_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE lab.purse (
    owner TEXT PRIMARY KEY,
    coins INT NOT NULL CHECK (coins >= 0)
);

CREATE TABLE lab.transfer_log (
    log_id BIGSERIAL PRIMARY KEY,
    from_owner TEXT NOT NULL,
    to_owner TEXT NOT NULL,
    amt INT NOT NULL
);

-- Functions

-- Resets bread shelf inventory and clears the sales log.
CREATE OR REPLACE FUNCTION lab.reset_loaves(p_qty INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE lab.sale;
    INSERT INTO lab.shelf (item, qty)
    VALUES ('bread', p_qty)
    ON CONFLICT (item) DO UPDATE SET qty = EXCLUDED.qty;
END;
$$;

-- Demonstrates the lost update under READ COMMITTED.
CREATE OR REPLACE FUNCTION lab.buy_naive(p_client INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v INT;
BEGIN
    SELECT qty INTO v FROM lab.shelf WHERE item = 'bread';
    PERFORM pg_sleep(0.002);
    IF v > 0 THEN
        UPDATE lab.shelf SET qty = v - 1 WHERE item = 'bread';
        INSERT INTO lab.sale (client) VALUES (p_client);
        RETURN 'sold';
    ELSE
        RETURN 'sold_out';
    END IF;
END;
$$;

-- Locks the target row with SELECT FOR UPDATE to serialize concurrent updates.
CREATE OR REPLACE FUNCTION lab.buy_for_update(p_client INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v INT;
BEGIN
    SELECT qty INTO v FROM lab.shelf WHERE item = 'bread' FOR UPDATE;
    PERFORM pg_sleep(0.002);
    IF v > 0 THEN
        UPDATE lab.shelf SET qty = v - 1 WHERE item = 'bread';
        INSERT INTO lab.sale (client) VALUES (p_client);
        RETURN 'sold';
    ELSE
        RETURN 'sold_out';
    END IF;
END;
$$;

-- Same pattern as the game engine (relative update + CHECK).
CREATE OR REPLACE FUNCTION lab.buy_atomic_check(p_client INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_sleep(0.002);
    BEGIN
        UPDATE lab.shelf SET qty = qty - 1 WHERE item = 'bread';
        INSERT INTO lab.sale (client) VALUES (p_client);
        RETURN 'sold';
    EXCEPTION WHEN check_violation THEN
        RETURN 'sold_out';
    END;
END;
$$;

-- Compare-and-swap on the value.
CREATE OR REPLACE FUNCTION lab.buy_optimistic(p_client INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v INT;
BEGIN
    FOR attempt IN 1..10 LOOP
        SELECT qty INTO v FROM lab.shelf WHERE item = 'bread';
        IF v <= 0 THEN
            RETURN 'sold_out';
        END IF;
        PERFORM pg_sleep(0.002);
        UPDATE lab.shelf SET qty = qty - 1 WHERE item = 'bread' AND qty = v;
        IF FOUND THEN
            INSERT INTO lab.sale (client) VALUES (p_client);
            RETURN 'sold';
        END IF;
    END LOOP;
    RETURN 'gave_up';
END;
$$;

-- Resets purse balances to 100 each and clears the transfer log.
CREATE OR REPLACE FUNCTION lab.reset_purses()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE lab.transfer_log;
    DELETE FROM lab.purse;
    INSERT INTO lab.purse (owner, coins) VALUES ('alice', 100), ('bob', 100);
END;
$$;

-- Locks the sender first, so opposite transfers can deadlock.
CREATE OR REPLACE FUNCTION lab.transfer_unordered(p_from TEXT, p_to TEXT, p_amt INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE lab.purse SET coins = coins - p_amt WHERE owner = p_from;
    PERFORM pg_sleep(0.05);
    UPDATE lab.purse SET coins = coins + p_amt WHERE owner = p_to;
    INSERT INTO lab.transfer_log (from_owner, to_owner, amt) VALUES (p_from, p_to, p_amt);
END;
$$;

-- Consistent lock order prevents deadlock.
CREATE OR REPLACE FUNCTION lab.transfer_ordered(p_from TEXT, p_to TEXT, p_amt INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM 1 FROM lab.purse WHERE owner = LEAST(p_from, p_to) FOR UPDATE;
    PERFORM 1 FROM lab.purse WHERE owner = GREATEST(p_from, p_to) FOR UPDATE;
    UPDATE lab.purse SET coins = coins - p_amt WHERE owner = p_from;
    PERFORM pg_sleep(0.05);
    UPDATE lab.purse SET coins = coins + p_amt WHERE owner = p_to;
    INSERT INTO lab.transfer_log (from_owner, to_owner, amt) VALUES (p_from, p_to, p_amt);
END;
$$;

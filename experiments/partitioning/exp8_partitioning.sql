-- Experiment 8: table partitioning (project doc section 17.17)
--
-- Question: if the event table were partitioned by branch (one partition per
-- parallel village), does a query about one village scan only that village's
-- rows, and what does dropping an abandoned village cost?
--
-- Everything lives in the throw-away schema exp8; the game tables are never
-- touched. Run from the repo root:
--   psql -U postgres -d butterfly -v n=400000 -v out=experiments/results/exp8_partitioning.csv -f experiments/partitioning/exp8_partitioning.sql
--
-- Why this is an experiment and not a change to the real event table:
-- event_cause, event_witness, snapshot... all reference event(event_id) alone.
-- In PostgreSQL a unique key on a partitioned table must include the partition
-- key, so (event_id) cannot stay unique and those foreign keys could not exist.
-- Adopting partitioning for real means widening every reference to
-- (branch_id, event_id). The report discusses that trade-off; this experiment
-- measures the benefit it would buy.

\set ON_ERROR_STOP on
\if :{?n} \else \set n 400000 \endif
\if :{?out} \else \set out experiments/results/exp8_partitioning.csv \endif

DROP SCHEMA IF EXISTS exp8 CASCADE;
CREATE SCHEMA exp8;

-- 1. Baseline: one ordinary table, same shape as the real event table.
CREATE TABLE exp8.event_flat (
    event_id    BIGINT NOT NULL,
    branch_id   INT    NOT NULL,
    tick        INT    NOT NULL,
    actor_id    INT,
    action_type TEXT   NOT NULL,
    payload     JSONB  NOT NULL,
    PRIMARY KEY (branch_id, event_id)
);

-- 2. LIST partitioning by branch: one partition per parallel village.
CREATE TABLE exp8.event_by_branch (LIKE exp8.event_flat) PARTITION BY LIST (branch_id);
DO $$
BEGIN
    FOR b IN 1..8 LOOP
        EXECUTE format('CREATE TABLE exp8.event_by_branch_p%s PARTITION OF exp8.event_by_branch FOR VALUES IN (%s)', b, b);
    END LOOP;
END $$;
ALTER TABLE exp8.event_by_branch ADD PRIMARY KEY (branch_id, event_id);

-- 3. RANGE partitioning by tick: old history in its own partitions.
CREATE TABLE exp8.event_by_tick (LIKE exp8.event_flat) PARTITION BY RANGE (tick);
DO $$
BEGIN
    FOR t IN 0..9 LOOP
        EXECUTE format('CREATE TABLE exp8.event_by_tick_p%s PARTITION OF exp8.event_by_tick FOR VALUES FROM (%s) TO (%s)', t, t * 100, (t + 1) * 100);
    END LOOP;
END $$;
ALTER TABLE exp8.event_by_tick ADD PRIMARY KEY (tick, branch_id, event_id);

-- 4. Same synthetic history in all three: 8 branches, 1000 ticks.
INSERT INTO exp8.event_flat
SELECT g, 1 + (g % 8), (g / 8) % 1000, 1 + (g % 30),
       (ARRAY['gift','trade','steal','rumor','set_price','produce','deliver','consume'])[1 + (g % 8)],
       jsonb_build_object('n', g)
FROM generate_series(1, :n) g;
INSERT INTO exp8.event_by_branch SELECT * FROM exp8.event_flat;
INSERT INTO exp8.event_by_tick   SELECT * FROM exp8.event_flat;

-- The same secondary index the real event table has (branch_id, tick).
CREATE INDEX ON exp8.event_flat (branch_id, tick);
CREATE INDEX ON exp8.event_by_branch (branch_id, tick);
CREATE INDEX ON exp8.event_by_tick (branch_id, tick);
ANALYZE exp8.event_flat; ANALYZE exp8.event_by_branch; ANALYZE exp8.event_by_tick;

-- 5. Measure: run EXPLAIN (ANALYZE, FORMAT JSON), then read execution time and
--    count which physical tables the plan actually touched.
CREATE TABLE exp8.results (
    query_name TEXT, layout TEXT, rows_in_table BIGINT,
    exec_ms NUMERIC, relations_scanned INT, partitions_scanned INT
);

CREATE FUNCTION exp8.measure(p_name TEXT, p_layout TEXT, p_sql TEXT) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE j JSONB; ms NUMERIC; rels INT; parts INT; total BIGINT;
BEGIN
    EXECUTE 'SELECT count(*) FROM exp8.' || p_layout INTO total;
    -- warm once, then take the best of 5 (steady-state, cache-warm)
    EXECUTE p_sql;
    ms := NULL;
    FOR i IN 1..5 LOOP
        EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON, COSTS OFF) ' || p_sql INTO j;
        IF ms IS NULL OR (j->0->>'Execution Time')::numeric < ms THEN ms := (j->0->>'Execution Time')::numeric; END IF;
    END LOOP;
    SELECT count(DISTINCT v #>> '{}') INTO rels FROM jsonb_path_query(j, '$.**."Relation Name"') v;
    SELECT count(DISTINCT v #>> '{}') INTO parts FROM jsonb_path_query(j, '$.**."Relation Name"') v WHERE (v #>> '{}') ~ '_p[0-9]+$';
    INSERT INTO exp8.results VALUES (p_name, p_layout, total, round(ms, 3), rels, parts);
END $$;

DO $$
DECLARE l TEXT;
BEGIN
    FOREACH l IN ARRAY ARRAY['event_flat', 'event_by_branch', 'event_by_tick'] LOOP
        -- Q1: one village, one day range  (prunes by branch; by tick too)
        PERFORM exp8.measure('Q1 one branch, ticks 100-199', l, format('SELECT count(*) FROM exp8.%I WHERE branch_id = 3 AND tick BETWEEN 100 AND 199', l));
        -- Q2: one village, everything
        PERFORM exp8.measure('Q2 one branch, all history', l, format('SELECT count(*), max(tick) FROM exp8.%I WHERE branch_id = 3', l));
        -- Q3: all villages, recent days only (prunes by tick)
        PERFORM exp8.measure('Q3 all branches, ticks 900-999', l, format('SELECT branch_id, count(*) FROM exp8.%I WHERE tick >= 900 GROUP BY branch_id', l));
        -- Q4: a query that cannot prune (control)
        PERFORM exp8.measure('Q4 all branches, all history', l, format('SELECT count(*) FROM exp8.%I', l));
    END LOOP;
END $$;

-- 6. Retiring an abandoned village: DELETE vs DETACH/DROP PARTITION.
DO $$
DECLARE t0 TIMESTAMPTZ; d_ms NUMERIC; p_ms NUMERIC; n_del BIGINT;
BEGIN
    t0 := clock_timestamp();
    DELETE FROM exp8.event_flat WHERE branch_id = 7;
    GET DIAGNOSTICS n_del = ROW_COUNT;
    d_ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
    t0 := clock_timestamp();
    ALTER TABLE exp8.event_by_branch DETACH PARTITION exp8.event_by_branch_p7;
    DROP TABLE exp8.event_by_branch_p7;
    p_ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
    INSERT INTO exp8.results VALUES ('Q5 retire branch 7 (rows removed: ' || n_del || ')', 'event_flat', n_del, round(d_ms, 3), 1, 0);
    INSERT INTO exp8.results VALUES ('Q5 retire branch 7 (rows removed: ' || n_del || ')', 'event_by_branch', n_del, round(p_ms, 3), 0, 1);
END $$;

\echo
\echo ===== Experiment 8 results =====
SELECT query_name, layout, exec_ms, relations_scanned, partitions_scanned
FROM exp8.results ORDER BY query_name, layout;

-- A readable plan for the headline claim (partition pruning), straight from the planner.
\echo
\echo ===== Plan: one branch on the branch-partitioned table =====
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT count(*) FROM exp8.event_by_branch WHERE branch_id = 3 AND tick BETWEEN 100 AND 199;

-- (psql's \copy does not expand variables, so write the CSV with \o and csv output mode.)
\pset format csv
\o :out
SELECT query_name, layout, rows_in_table, exec_ms, relations_scanned, partitions_scanned FROM exp8.results ORDER BY query_name, layout;
\o
\pset format aligned
\echo Wrote :out
-- DROP SCHEMA exp8 CASCADE;   -- uncomment to clean up

-- Test Suite 11: Index definitions, partial predicates, query plan usage, and drop/recreate verification
BEGIN;

-- 1. All nine indexes exist in schema public, and scheduled_pending_idx and entity_state_open_idx
-- are partial (pg_index.indpred IS NOT NULL) while the other seven are not.
DO $$
DECLARE
    v_total_idx INT;
    v_partial_count INT;
    v_non_partial_count INT;
BEGIN
    SELECT count(*) INTO v_total_idx
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'i'
      AND c.relname IN (
          'event_branch_tick_idx',
          'event_branch_event_idx',
          'event_cause_cause_idx',
          'causal_closure_desc_idx',
          'causal_path_prefix_idx',
          'event_witness_actor_idx',
          'scheduled_pending_idx',
          'entity_state_open_idx',
          'snapshot_branch_event_idx'
      );

    IF v_total_idx <> 9 THEN
        RAISE EXCEPTION 'FAIL: expected 9 indexes in public schema, found %', v_total_idx;
    END IF;

    SELECT count(*) INTO v_partial_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_index i ON i.indexrelid = c.oid
    WHERE n.nspname = 'public'
      AND c.relkind = 'i'
      AND c.relname IN ('scheduled_pending_idx', 'entity_state_open_idx')
      AND i.indpred IS NOT NULL;

    IF v_partial_count <> 2 THEN
        RAISE EXCEPTION 'FAIL: scheduled_pending_idx and entity_state_open_idx must be partial (found %)', v_partial_count;
    END IF;

    SELECT count(*) INTO v_non_partial_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_index i ON i.indexrelid = c.oid
    WHERE n.nspname = 'public'
      AND c.relkind = 'i'
      AND c.relname IN (
          'event_branch_tick_idx',
          'event_branch_event_idx',
          'event_cause_cause_idx',
          'causal_closure_desc_idx',
          'causal_path_prefix_idx',
          'event_witness_actor_idx',
          'snapshot_branch_event_idx'
      )
      AND i.indpred IS NULL;

    IF v_non_partial_count <> 7 THEN
        RAISE EXCEPTION 'FAIL: the other seven indexes must not be partial (found % non-partial)', v_non_partial_count;
    END IF;

    RAISE NOTICE 'PASS: 9 indexes exist with correct partial predicates';
END $$;

-- 2. Plan for SELECT count(*) FROM event WHERE branch_id = 1 AND tick BETWEEN 0 AND 5 uses event_branch_tick_idx
DO $$
DECLARE
    r RECORD;
    v_plan TEXT := '';
BEGIN
    SET LOCAL enable_seqscan = off;
    FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT count(*) FROM event WHERE branch_id = 1 AND tick BETWEEN 0 AND 5' LOOP
        v_plan := v_plan || ' ' || r."QUERY PLAN";
    END LOOP;

    IF position('event_branch_tick_idx' IN v_plan) > 0 THEN
        RAISE NOTICE 'PASS: plan uses event_branch_tick_idx';
    ELSE
        RAISE EXCEPTION 'FAIL: plan does not use event_branch_tick_idx (plan: %)', v_plan;
    END IF;
END $$;

-- 3. Plan for SELECT effect_id FROM event_cause WHERE cause_id = 1 uses event_cause_cause_idx
DO $$
DECLARE
    r RECORD;
    v_plan TEXT := '';
BEGIN
    SET LOCAL enable_seqscan = off;
    FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT effect_id FROM event_cause WHERE cause_id = 1' LOOP
        v_plan := v_plan || ' ' || r."QUERY PLAN";
    END LOOP;

    IF position('event_cause_cause_idx' IN v_plan) > 0 THEN
        RAISE NOTICE 'PASS: plan uses event_cause_cause_idx';
    ELSE
        RAISE EXCEPTION 'FAIL: plan does not use event_cause_cause_idx (plan: %)', v_plan;
    END IF;
END $$;

-- 4. Plan for SELECT ancestor_id, depth FROM causal_closure WHERE descendant_id = 1 AND depth > 0 uses causal_closure_desc_idx
DO $$
DECLARE
    r RECORD;
    v_plan TEXT := '';
BEGIN
    SET LOCAL enable_seqscan = off;
    FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT ancestor_id, depth FROM causal_closure WHERE descendant_id = 1 AND depth > 0' LOOP
        v_plan := v_plan || ' ' || r."QUERY PLAN";
    END LOOP;

    IF position('causal_closure_desc_idx' IN v_plan) > 0 THEN
        RAISE NOTICE 'PASS: plan uses causal_closure_desc_idx';
    ELSE
        RAISE EXCEPTION 'FAIL: plan does not use causal_closure_desc_idx (plan: %)', v_plan;
    END IF;
END $$;

-- 5. Plan for SELECT count(*) FROM causal_path WHERE path LIKE '1/%' uses causal_path_prefix_idx
DO $$
DECLARE
    r RECORD;
    v_plan TEXT := '';
BEGIN
    SET LOCAL enable_seqscan = off;
    FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT count(*) FROM causal_path WHERE path LIKE ''1/%''' LOOP
        v_plan := v_plan || ' ' || r."QUERY PLAN";
    END LOOP;

    IF position('causal_path_prefix_idx' IN v_plan) > 0 THEN
        RAISE NOTICE 'PASS: plan uses causal_path_prefix_idx';
    ELSE
        RAISE EXCEPTION 'FAIL: plan does not use causal_path_prefix_idx (plan: %)', v_plan;
    END IF;
END $$;

-- 6. Plan for SELECT count(*) FROM event_witness WHERE actor_id = 1 uses event_witness_actor_idx
DO $$
DECLARE
    r RECORD;
    v_plan TEXT := '';
BEGIN
    SET LOCAL enable_seqscan = off;
    FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT count(*) FROM event_witness WHERE actor_id = 1' LOOP
        v_plan := v_plan || ' ' || r."QUERY PLAN";
    END LOOP;

    IF position('event_witness_actor_idx' IN v_plan) > 0 THEN
        RAISE NOTICE 'PASS: plan uses event_witness_actor_idx';
    ELSE
        RAISE EXCEPTION 'FAIL: plan does not use event_witness_actor_idx (plan: %)', v_plan;
    END IF;
END $$;

-- 7. Plan for SELECT scheduled_id FROM scheduled_effect WHERE branch_id = 1 AND NOT processed AND due_tick <= 5 ORDER BY due_tick, scheduled_id uses scheduled_pending_idx
DO $$
DECLARE
    r RECORD;
    v_plan TEXT := '';
BEGIN
    SET LOCAL enable_seqscan = off;
    FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT scheduled_id FROM scheduled_effect WHERE branch_id = 1 AND NOT processed AND due_tick <= 5 ORDER BY due_tick, scheduled_id' LOOP
        v_plan := v_plan || ' ' || r."QUERY PLAN";
    END LOOP;

    IF position('scheduled_pending_idx' IN v_plan) > 0 THEN
        RAISE NOTICE 'PASS: plan uses scheduled_pending_idx';
    ELSE
        RAISE EXCEPTION 'FAIL: plan does not use scheduled_pending_idx (plan: %)', v_plan;
    END IF;
END $$;

-- 8. Plan for SELECT snapshot_id FROM snapshot WHERE branch_id = 1 AND last_event_id <= 5 ORDER BY last_event_id DESC LIMIT 1 uses snapshot_branch_event_idx
DO $$
DECLARE
    r RECORD;
    v_plan TEXT := '';
BEGIN
    SET LOCAL enable_seqscan = off;
    FOR r IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT snapshot_id FROM snapshot WHERE branch_id = 1 AND last_event_id <= 5 ORDER BY last_event_id DESC LIMIT 1' LOOP
        v_plan := v_plan || ' ' || r."QUERY PLAN";
    END LOOP;

    IF position('snapshot_branch_event_idx' IN v_plan) > 0 THEN
        RAISE NOTICE 'PASS: plan uses snapshot_branch_event_idx';
    ELSE
        RAISE EXCEPTION 'FAIL: plan does not use snapshot_branch_event_idx (plan: %)', v_plan;
    END IF;
END $$;

-- 9. Drop script: count indexes in public, run drop script, ensure count drops by exactly 9 and all PK/unique constraint indexes remain
CREATE TEMP TABLE idx_test_ctx (
    k TEXT PRIMARY KEY,
    v INT
);

DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT count(*) INTO v_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'i';

    INSERT INTO idx_test_ctx (k, v) VALUES ('pre_drop_count', v_count);
END $$;

\ir ../schema/08_indexes_drop.sql

DO $$
DECLARE
    v_pre INT;
    v_post INT;
    v_missing_constraints INT;
BEGIN
    SELECT v INTO v_pre FROM idx_test_ctx WHERE k = 'pre_drop_count';

    SELECT count(*) INTO v_post
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'i';

    IF (v_pre - v_post) <> 9 THEN
        RAISE EXCEPTION 'FAIL: drop script index count difference is % (expected 9)', (v_pre - v_post);
    END IF;

    SELECT count(*) INTO v_missing_constraints
    FROM pg_constraint con
    JOIN pg_namespace n ON n.oid = con.connamespace
    WHERE n.nspname = 'public'
      AND con.contype IN ('p', 'u')
      AND NOT EXISTS (
          SELECT 1 FROM pg_class c WHERE c.oid = con.conindid
      );

    IF v_missing_constraints > 0 THEN
        RAISE EXCEPTION 'FAIL: % primary key or unique constraint index(es) missing after drop script', v_missing_constraints;
    END IF;

    RAISE NOTICE 'PASS: drop script removed exactly 9 indexes and preserved constraint indexes';
END $$;

-- 10. Recreate: run \ir ../schema/08_indexes.sql inside the same transaction; the nine indexes exist again
\ir ../schema/08_indexes.sql

DO $$
DECLARE
    v_recreated_count INT;
BEGIN
    SELECT count(*) INTO v_recreated_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'i'
      AND c.relname IN (
          'event_branch_tick_idx',
          'event_branch_event_idx',
          'event_cause_cause_idx',
          'causal_closure_desc_idx',
          'causal_path_prefix_idx',
          'event_witness_actor_idx',
          'scheduled_pending_idx',
          'entity_state_open_idx',
          'snapshot_branch_event_idx'
      );

    IF v_recreated_count = 9 THEN
        RAISE NOTICE 'PASS: recreate script restored all 9 indexes';
    ELSE
        RAISE EXCEPTION 'FAIL: recreate script only restored % of 9 indexes', v_recreated_count;
    END IF;
END $$;

ROLLBACK;

-- Test Suite 12: Look Back (lineage-aware as-of reads)

BEGIN;

-- Setup: build some history on main, then a child branch, to look back across.
DO $$
DECLARE
    v_main INT;
    v_child INT;
    v_demo INT;
    v_bakery INT;
    v_bread INT;
    v_fork_evt BIGINT;
    v_branch_count_before INT;
    v_event_count_before INT;
    v_branch_count_after INT;
    v_event_count_after INT;
    v_state_direct JSONB;
    v_state_lineage JSONB;
    v_stock_now JSONB;
    v_stock_past JSONB;
    v_stock_live JSONB;
    v_chain_errs INT;
    v_causal_errs INT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT place_id INTO v_bakery FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread FROM item WHERE name = 'bread';

    v_demo := join_village(v_main, 'lookback_demo');
    PERFORM apply_action(v_main, v_demo, 'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 1));
    PERFORM advance_day(v_main);
    PERFORM apply_action(v_main, v_demo, 'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 1));
    PERFORM advance_day(v_main);

    -- 1. entity_state_at_lineage agrees with entity_state_at on the same branch.
    v_state_direct := entity_state_at(v_demo, v_main, 1);
    v_state_lineage := entity_state_at_lineage(v_demo, v_main, 1);
    IF v_state_direct IS NOT DISTINCT FROM v_state_lineage THEN
        RAISE NOTICE 'PASS: entity_state_at_lineage matches entity_state_at (same branch)';
    ELSE
        RAISE EXCEPTION 'FAIL: entity_state_at_lineage same-branch mismatch (direct=%, lineage=%)',
            v_state_direct, v_state_lineage;
    END IF;

    -- 2. entity_state_at_lineage walks into the parent from a child branch.
    SELECT max(event_id) INTO v_fork_evt FROM event WHERE branch_id = v_main AND tick <= 2;
    v_child := fork_branch(v_main, v_fork_evt, 'lookback_test_child', 'snapshot_delta');
    v_state_lineage := entity_state_at_lineage(v_demo, v_child, 1);
    IF v_state_lineage IS NOT DISTINCT FROM v_state_direct THEN
        RAISE NOTICE 'PASS: entity_state_at_lineage walks into the parent branch';
    ELSE
        RAISE EXCEPTION 'FAIL: entity_state_at_lineage did not find parent state (got %)', v_state_lineage;
    END IF;

    -- 3. look_back at the current tick equals the live serialized state.
    v_stock_live := serialize_branch_state(v_main) -> 'stock';
    v_stock_now := look_back(v_main, current_tick(v_main)) -> 'stock';
    IF v_stock_now IS NOT DISTINCT FROM v_stock_live THEN
        RAISE NOTICE 'PASS: look_back at the present matches live state';
    ELSE
        RAISE EXCEPTION 'FAIL: look_back at the present diverged from live state';
    END IF;

    -- 4. look_back at tick 0 shows different (earlier) bread stock than now.
    v_stock_past := look_back(v_main, 0) -> 'stock';
    IF v_stock_past IS DISTINCT FROM v_stock_live THEN
        RAISE NOTICE 'PASS: look_back at tick 0 differs from the present';
    ELSE
        RAISE EXCEPTION 'FAIL: look_back at tick 0 did not differ from the present';
    END IF;

    -- 5. look_back is read-only: no scratch branches or events survive it.
    SELECT count(*) INTO v_branch_count_before FROM branch;
    SELECT count(*) INTO v_event_count_before FROM event;
    PERFORM look_back(v_main, 0);
    PERFORM look_back(v_main, 1);
    SELECT count(*) INTO v_branch_count_after FROM branch;
    SELECT count(*) INTO v_event_count_after FROM event;
    IF v_branch_count_after = v_branch_count_before AND v_event_count_after = v_event_count_before THEN
        RAISE NOTICE 'PASS: look_back leaves no scratch branches or events behind';
    ELSE
        RAISE EXCEPTION 'FAIL: look_back leaked state (branches %->%, events %->%)',
            v_branch_count_before, v_branch_count_after, v_event_count_before, v_event_count_after;
    END IF;

    -- 6. look_back's internal fork-and-discard does not corrupt the hash chain or causal structures.
    SELECT count(*) INTO v_chain_errs FROM verify_event_chain();
    SELECT count(*) INTO v_causal_errs FROM verify_causal_structures();
    IF v_chain_errs = 0 AND v_causal_errs = 0 THEN
        RAISE NOTICE 'PASS: integrity preserved after look_back';
    ELSE
        RAISE EXCEPTION 'FAIL: integrity broken after look_back (chain_errs=%, causal_errs=%)',
            v_chain_errs, v_causal_errs;
    END IF;
END;
$$;

ROLLBACK;

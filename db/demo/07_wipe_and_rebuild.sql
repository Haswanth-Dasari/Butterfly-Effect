-- Demo 07: Wipe and Rebuild (Application-Level Recovery)

BEGIN;

CREATE TEMP TABLE demo_ctx (
    main_id INT
);

CREATE TEMP TABLE demo_baseline (
    digest_before TEXT
);

DO $$
DECLARE
    v_main INT;
    v_demo INT;
    v_hartley INT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    IF v_main IS NULL THEN
        RAISE EXCEPTION 'main branch not found';
    END IF;
    INSERT INTO demo_ctx (main_id) VALUES (v_main);

    SELECT place_id INTO v_hartley FROM place WHERE name = 'Hartley Farm';

    v_demo := join_village(v_main, 'Demo');

    FOR i IN 1..5 LOOP
        PERFORM advance_day(v_main);
        PERFORM apply_action(
            v_main,
            v_demo,
            'help_harvest',
            jsonb_build_object('place_id', v_hartley, 'qty', 1)
        );
    END LOOP;
END;
$$;

-- (A) Record baseline projection counts and digest before wipe
INSERT INTO demo_baseline (digest_before)
SELECT branch_projection_digest((SELECT main_id FROM demo_ctx));

SELECT
    (SELECT count(*) FROM stock WHERE branch_id = (SELECT main_id FROM demo_ctx)) AS stock_rows,
    (SELECT count(*) FROM entity_state WHERE branch_id = (SELECT main_id FROM demo_ctx)) AS entity_rows,
    digest_before
FROM demo_baseline;

-- (B) TRUNCATE stock and entity_state, then verify zero counts
TRUNCATE stock, entity_state;

SELECT
    (SELECT count(*) FROM stock WHERE branch_id = (SELECT main_id FROM demo_ctx)) AS stock_rows,
    (SELECT count(*) FROM entity_state WHERE branch_id = (SELECT main_id FROM demo_ctx)) AS entity_rows;

-- (C) Rebuild all projections and verify restored counts
SELECT rebuild_all_projections() AS branches_rebuilt;

SELECT
    (SELECT count(*) FROM stock WHERE branch_id = (SELECT main_id FROM demo_ctx)) AS stock_rows,
    (SELECT count(*) FROM entity_state WHERE branch_id = (SELECT main_id FROM demo_ctx)) AS entity_rows;

-- (D) Prove recovered projection digest is identical to pre-wipe baseline
SELECT branch_projection_digest((SELECT main_id FROM demo_ctx)) = (SELECT digest_before FROM demo_baseline) AS identical;

-- (E) Verify event chain integrity across the entire village
SELECT * FROM verify_event_chain();

ROLLBACK;

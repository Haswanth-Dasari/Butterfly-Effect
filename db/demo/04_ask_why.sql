-- Demo 04: Ask Why Layer
-- Demonstrates the Chronicle provenance, implementation comparisons, action scores, and daily views.

BEGIN;

DO $$
DECLARE
    v_branch_id INT;
    v_demo_id INT;
    v_bakery_id INT;
    v_bread_id INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';

    v_demo_id := join_village(v_branch_id, 'Demo');

    PERFORM apply_action(
        v_branch_id,
        v_demo_id,
        'steal',
        jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 1)
    );
END;
$$;

SELECT advance_day((SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL)) AS day_advanced_to_1;
SELECT advance_day((SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL)) AS day_advanced_to_2;

-- (A) SELECT step, tick, action_type, actor_name, narrative FROM ask_why(<rumor event>) (the Chronicle)
SELECT step, tick, action_type, actor_name, narrative
FROM ask_why((
    SELECT max(e.event_id)
    FROM event e
    JOIN branch b ON b.branch_id = e.branch_id
    WHERE b.name = 'main' AND b.parent_id IS NULL AND e.action_type = 'rumor'
));

-- (B) one row per implementation: 'cte', 'closure', 'path' with count(*) of its why_ids_* rows
SELECT 'cte' AS implementation, count(*) AS ancestor_count
FROM why_ids_cte((
    SELECT max(e.event_id)
    FROM event e
    JOIN branch b ON b.branch_id = e.branch_id
    WHERE b.name = 'main' AND b.parent_id IS NULL AND e.action_type = 'rumor'
))
UNION ALL
SELECT 'closure' AS implementation, count(*) AS ancestor_count
FROM why_ids_closure((
    SELECT max(e.event_id)
    FROM event e
    JOIN branch b ON b.branch_id = e.branch_id
    WHERE b.name = 'main' AND b.parent_id IS NULL AND e.action_type = 'rumor'
))
UNION ALL
SELECT 'path' AS implementation, count(*) AS ancestor_count
FROM why_ids_path((
    SELECT max(e.event_id)
    FROM event e
    JOIN branch b ON b.branch_id = e.branch_id
    WHERE b.name = 'main' AND b.parent_id IS NULL AND e.action_type = 'rumor'
));

-- (C) SELECT * FROM v_action_scores WHERE branch_id = <main>
SELECT *
FROM v_action_scores
WHERE branch_id = (SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL);

-- (D) PERFORM/SELECT refresh_daily_views(); then SELECT * FROM mv_leaderboard WHERE branch_id = <main>
SELECT refresh_daily_views();

SELECT *
FROM mv_leaderboard
WHERE branch_id = (SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL);

-- (E) SELECT branch_id, tick, events_total, player_actions, cascade_events, top_score, events_cumulative FROM mv_evening_bell WHERE branch_id = <main> ORDER BY tick
SELECT branch_id, tick, events_total, player_actions, cascade_events, top_score, events_cumulative
FROM mv_evening_bell
WHERE branch_id = (SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL)
ORDER BY tick;

-- (F) SELECT * FROM verify_causal_structures(); and SELECT * FROM verify_event_chain();
SELECT * FROM verify_causal_structures();
SELECT * FROM verify_event_chain((SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL));

ROLLBACK;

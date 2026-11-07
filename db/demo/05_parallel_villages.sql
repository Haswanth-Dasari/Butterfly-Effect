-- Demo 05: Parallel Villages (Branching, Rewind, and Counterfactual Diffing)

BEGIN;

DO $$
DECLARE
    v_main INT;
    v_demo_id INT;
    v_a_ev BIGINT;
    v_bakery INT;
    v_bread INT;
    v_what_if INT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT place_id INTO v_bakery FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread FROM item WHERE name = 'bread';

    -- 1. Demo joins village on main; record arrival event id
    v_demo_id := join_village(v_main, 'Demo');
    SELECT event_id INTO v_a_ev FROM event WHERE branch_id = v_main AND actor_id = v_demo_id AND action_type = 'arrive';

    -- 2. Demo steals bread from bakery on main
    PERFORM apply_action(
        v_main,
        v_demo_id,
        'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 1)
    );

    -- 3. Advance day twice on main (triggers price hike, trust drop, rumor cascade)
    PERFORM advance_day(v_main);
    PERFORM advance_day(v_main);

    -- 4. Rewind: fork from arrival event A_ev before the theft occurred using replay
    v_what_if := fork_branch(v_main, v_a_ev, 'what_if', 'replay');

    -- 5. Advance day twice on the counterfactual branch (peaceful village with no theft)
    PERFORM advance_day(v_what_if);
    PERFORM advance_day(v_what_if);
END;
$$;

-- (A) SELECT branch_id, name, parent_id, fork_event FROM branch ORDER BY branch_id
SELECT branch_id, name, parent_id, fork_event
FROM branch
ORDER BY branch_id;

-- (B) SELECT current_tick(<main>) AS main_tick, current_tick(<what_if>) AS what_if_tick
SELECT
    current_tick((SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL)) AS main_tick,
    current_tick((SELECT branch_id FROM branch WHERE name = 'what_if')) AS what_if_tick;

-- (C) SELECT * FROM branch_diff(<main>, <what_if>)
SELECT *
FROM branch_diff(
    (SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL),
    (SELECT branch_id FROM branch WHERE name = 'what_if')
);

-- (D) SELECT branch_id, count(*) AS rumors FROM event WHERE action_type = 'rumor' AND branch_id IN (<main>, <what_if>) GROUP BY branch_id ORDER BY branch_id
SELECT branch_id, count(*) AS rumors
FROM event
WHERE action_type = 'rumor'
  AND branch_id IN (
      (SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL),
      (SELECT branch_id FROM branch WHERE name = 'what_if')
  )
GROUP BY branch_id
ORDER BY branch_id;

-- (E) SELECT * FROM verify_event_chain();
SELECT * FROM verify_event_chain();

ROLLBACK;

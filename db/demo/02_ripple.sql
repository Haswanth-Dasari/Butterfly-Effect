BEGIN;

DO $$
DECLARE
    v_branch_id INT;
    v_demo_id INT;
    v_bakery_id INT;
    v_bread_id INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';

    v_demo_id := join_village(v_branch_id, 'Demo');

    PERFORM apply_action(
        v_branch_id,
        v_demo_id,
        'steal',
        jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 1)
    );
END
$$;

-- (S) Scheduled effects after the theft
SELECT
    scheduled_id,
    due_tick,
    source_event_id,
    rule_id,
    payload,
    processed
FROM scheduled_effect
ORDER BY scheduled_id;

-- Advance day twice
SELECT advance_day((SELECT branch_id FROM branch WHERE name = 'main')) AS day_advanced_to_1;
SELECT advance_day((SELECT branch_id FROM branch WHERE name = 'main')) AS day_advanced_to_2;

-- (A) all events: event_id, tick, actor name or '-', action_type, ORDER BY event_id
SELECT
    e.event_id,
    e.tick,
    COALESCE(a.name, '-') AS actor_name,
    e.action_type
FROM event AS e
LEFT JOIN actor AS a ON a.actor_id = e.actor_id
JOIN branch AS b ON b.branch_id = e.branch_id
WHERE b.name = 'main'
ORDER BY e.event_id;

-- (B) Ask Why for the 'rumor' event: recursive CTE; one row per causal link: depth, cause action_type, effect action_type, the rule's narrative_template, ORDER BY depth
WITH RECURSIVE why AS (
    SELECT
        ec.cause_id,
        ec.effect_id,
        ec.rule_id,
        1 AS depth
    FROM event_cause ec
    JOIN event e ON e.event_id = ec.effect_id
    JOIN branch b ON b.branch_id = e.branch_id
    WHERE b.name = 'main' AND e.action_type = 'rumor'

    UNION ALL

    SELECT
        ec.cause_id,
        ec.effect_id,
        ec.rule_id,
        w.depth + 1
    FROM event_cause ec
    JOIN why w ON ec.effect_id = w.cause_id
)
SELECT
    w.depth,
    c.action_type AS cause_action,
    e.action_type AS effect_action,
    r.narrative_template
FROM why w
JOIN event c ON c.event_id = w.cause_id
JOIN event e ON e.event_id = w.effect_id
JOIN "rule" r ON r.rule_id = w.rule_id
ORDER BY w.depth;

-- (C) Demo's current mood and trust from the open state row
SELECT
    a.name AS actor_name,
    es.state->>'mood' AS mood,
    (es.state->>'trust')::numeric AS trust
FROM actor a
JOIN entity_state es ON es.entity_id = a.actor_id
JOIN branch b ON b.branch_id = es.branch_id
WHERE b.name = 'main'
  AND upper_inf(es.valid_ticks)
  AND a.name = 'Demo';

-- (D) Demo's trust at tick 0, 1 and 2 via entity_state_at
SELECT
    t.tick,
    (entity_state_at(a.actor_id, b.branch_id, t.tick)->>'trust')::numeric AS trust
FROM actor a
CROSS JOIN branch b
CROSS JOIN (VALUES (0), (1), (2)) AS t(tick)
WHERE b.name = 'main'
  AND a.name = 'Demo'
ORDER BY t.tick;

-- (E) SELECT * FROM verify_event_chain();
SELECT * FROM verify_event_chain();

ROLLBACK;

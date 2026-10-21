BEGIN;

DO $$
DECLARE
    v_branch_id INT;
    v_demo_id INT;
    v_wick_id INT;
    v_bakery_id INT;
    v_bread_id INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main';
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';
    SELECT actor_id INTO v_wick_id FROM actor WHERE name = 'Old Wick';

    v_demo_id := join_village(v_branch_id, 'Demo');

    PERFORM apply_action(
        v_branch_id,
        v_demo_id,
        'steal',
        jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'qty', 1)
    );

    PERFORM apply_action(
        v_branch_id,
        v_demo_id,
        'gift',
        jsonb_build_object('item_id', v_bread_id, 'qty', 1, 'target_actor', v_wick_id)
    );

    PERFORM apply_action(
        v_branch_id,
        v_demo_id,
        'set_price',
        jsonb_build_object('place_id', v_bakery_id, 'item_id', v_bread_id, 'price', 2.50)
    );
END
$$;

-- (A) events: event_id, tick, actor name (or '-'), action_type, witness count, ORDER BY event_id
SELECT
    e.event_id,
    e.tick,
    COALESCE(a.name, '-') AS actor_name,
    e.action_type,
    count(ew.actor_id) AS witness_count
FROM event AS e
LEFT JOIN actor AS a ON a.actor_id = e.actor_id
LEFT JOIN event_witness AS ew ON ew.event_id = e.event_id
JOIN branch AS b ON b.branch_id = e.branch_id
WHERE b.name = 'main'
GROUP BY e.event_id, e.tick, a.name, e.action_type
ORDER BY e.event_id;

-- (B) the bakery's bread qty and price
SELECT
    p.name AS place_name,
    i.name AS item_name,
    s.qty,
    s.price
FROM stock AS s
JOIN place AS p ON p.place_id = s.place_id
JOIN item AS i ON i.item_id = s.item_id
JOIN branch AS b ON b.branch_id = s.branch_id
WHERE b.name = 'main'
  AND p.name = 'Maren''s Bakery'
  AND i.name = 'bread';

-- (C) inventories of 'Old Wick' and 'Demo' (state->'inv')
SELECT
    a.name AS actor_name,
    es.state->'inv' AS inventory
FROM actor AS a
JOIN entity_state AS es ON es.entity_id = a.actor_id
JOIN branch AS b ON b.branch_id = es.branch_id
WHERE b.name = 'main'
  AND upper_inf(es.valid_ticks)
  AND a.name IN ('Old Wick', 'Demo')
ORDER BY a.name;

-- (D) SELECT * FROM verify_event_chain();
SELECT * FROM verify_event_chain();

ROLLBACK;

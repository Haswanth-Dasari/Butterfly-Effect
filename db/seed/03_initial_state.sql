-- Seed assumes an EMPTY schema.

INSERT INTO stock (place_id, item_id, branch_id, qty, price) VALUES
((SELECT place_id FROM place WHERE name = 'Maren''s Bakery'), (SELECT item_id FROM item WHERE name = 'bread'), 1, 40, 2.00),
((SELECT place_id FROM place WHERE name = 'Maren''s Bakery'), (SELECT item_id FROM item WHERE name = 'flour'), 1, 30, 1.50),
((SELECT place_id FROM place WHERE name = 'Tobin''s Mill'), (SELECT item_id FROM item WHERE name = 'grain'), 1, 60, 1.00),
((SELECT place_id FROM place WHERE name = 'Tobin''s Mill'), (SELECT item_id FROM item WHERE name = 'flour'), 1, 50, 1.50),
((SELECT place_id FROM place WHERE name = 'Hartley Farm'), (SELECT item_id FROM item WHERE name = 'grain'), 1, 40, 0.80),
((SELECT place_id FROM place WHERE name = 'Brook Farm'), (SELECT item_id FROM item WHERE name = 'grain'), 1, 40, 0.80),
((SELECT place_id FROM place WHERE name = 'Thorn Farm'), (SELECT item_id FROM item WHERE name = 'grain'), 1, 40, 0.80);

-- entity_id equals actor_id here because only actors carry state.
INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
SELECT
    actor_id,
    1,
    '[0,)'::int4range,
    jsonb_build_object(
        'mood', 'content',
        'trust', 50,
        'coins', CASE
            WHEN job IN ('baker', 'miller', 'innkeeper') THEN 30
            WHEN job = 'farmer' THEN 20
            ELSE 10
        END
    )
FROM actor
ORDER BY actor_id;

INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
VALUES (1, 0, NULL, 'world_start', '{"note":"Alderbrook begins"}'::jsonb);

-- Baseline for full replay (the baseline snapshot, tick 0).
SELECT create_snapshot((SELECT branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL));

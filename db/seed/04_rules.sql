-- Game content; rules are data.

INSERT INTO "rule" (rule_id, trigger_action_type, condition, effect_template, narrative_template, delay_ticks, is_active)
VALUES
(
    1,
    'steal',
    '{"stock_below":{"place_id":"$payload.place_id","item_id":"$payload.item_id","qty":40}}',
    '{"action":"set_price","actor":null,"payload":{"place_id":"$payload.place_id","item_id":"$payload.item_id","price_pct":25,"culprit":"$actor"},"visibility":"public"}',
    'The shelf ran short, so the baker raised the price.',
    1,
    TRUE
),
(
    2,
    'set_price',
    '{"payload_gte":{"price_pct":20}}',
    '{"action":"state_change","actor":null,"payload":{"entity_id":"$payload.culprit","set":{"mood":"shunned"},"add":{"trust":-5}},"visibility":"private"}',
    'Dearer bread set the neighbors whispering about a thief.',
    1,
    TRUE
),
(
    3,
    'state_change',
    '{"state_lt":{"entity_id":"$payload.entity_id","key":"trust","value":50}}',
    '{"action":"rumor","actor":null,"payload":{"about":"$payload.entity_id","text":"thief"},"visibility":"public"}',
    'Trust fell, and the whispers became a village rumor.',
    0,
    TRUE
),
(
    4,
    'day_start',
    NULL,
    jsonb_build_object(
        'action', 'produce',
        'actor', NULL,
        'payload', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Hartley Farm'),
            'output_item_id', (SELECT item_id FROM item WHERE name = 'grain'),
            'output_qty', 25
        ),
        'visibility', 'private'
    )::text,
    'Hartley Farm brought in the day''s harvest.',
    0,
    TRUE
),
(
    5,
    'day_start',
    jsonb_build_object(
        'stock_at_least', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Hartley Farm'),
            'item_id', (SELECT item_id FROM item WHERE name = 'grain'),
            'qty', 20
        )
    )::text,
    jsonb_build_object(
        'action', 'deliver',
        'actor', NULL,
        'payload', jsonb_build_object(
            'from_place', (SELECT place_id FROM place WHERE name = 'Hartley Farm'),
            'to_place', (SELECT place_id FROM place WHERE name = 'Tobin''s Mill'),
            'item_id', (SELECT item_id FROM item WHERE name = 'grain'),
            'qty', 20
        ),
        'visibility', 'private'
    )::text,
    'A cart of grain rolled from the farm to the mill.',
    0,
    TRUE
),
(
    6,
    'day_start',
    jsonb_build_object(
        'stock_at_least', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Tobin''s Mill'),
            'item_id', (SELECT item_id FROM item WHERE name = 'grain'),
            'qty', 20
        )
    )::text,
    jsonb_build_object(
        'action', 'produce',
        'actor', NULL,
        'payload', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Tobin''s Mill'),
            'input_item_id', (SELECT item_id FROM item WHERE name = 'grain'),
            'input_qty', 20,
            'output_item_id', (SELECT item_id FROM item WHERE name = 'flour'),
            'output_qty', 20
        ),
        'visibility', 'private'
    )::text,
    'Tobin ground the day''s grain into flour.',
    0,
    TRUE
),
(
    7,
    'day_start',
    jsonb_build_object(
        'stock_at_least', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Tobin''s Mill'),
            'item_id', (SELECT item_id FROM item WHERE name = 'flour'),
            'qty', 10
        )
    )::text,
    jsonb_build_object(
        'action', 'deliver',
        'actor', NULL,
        'payload', jsonb_build_object(
            'from_place', (SELECT place_id FROM place WHERE name = 'Tobin''s Mill'),
            'to_place', (SELECT place_id FROM place WHERE name = 'Maren''s Bakery'),
            'item_id', (SELECT item_id FROM item WHERE name = 'flour'),
            'qty', 10
        ),
        'visibility', 'private'
    )::text,
    'Flour was carried from the mill to the bakery.',
    0,
    TRUE
),
(
    8,
    'day_start',
    jsonb_build_object(
        'stock_at_least', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Maren''s Bakery'),
            'item_id', (SELECT item_id FROM item WHERE name = 'flour'),
            'qty', 10
        )
    )::text,
    jsonb_build_object(
        'action', 'produce',
        'actor', NULL,
        'payload', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Maren''s Bakery'),
            'input_item_id', (SELECT item_id FROM item WHERE name = 'flour'),
            'input_qty', 10,
            'output_item_id', (SELECT item_id FROM item WHERE name = 'bread'),
            'output_qty', 20
        ),
        'visibility', 'private'
    )::text,
    'Maren baked the morning bread.',
    0,
    TRUE
),
(
    9,
    'day_start',
    jsonb_build_object(
        'stock_at_least', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Maren''s Bakery'),
            'item_id', (SELECT item_id FROM item WHERE name = 'bread'),
            'qty', 15
        )
    )::text,
    jsonb_build_object(
        'action', 'consume',
        'actor', NULL,
        'payload', jsonb_build_object(
            'place_id', (SELECT place_id FROM place WHERE name = 'Maren''s Bakery'),
            'item_id', (SELECT item_id FROM item WHERE name = 'bread'),
            'qty', 15
        ),
        'visibility', 'private'
    )::text,
    'The village ate its daily bread.',
    0,
    TRUE
),
(
    10,
    'sabotage',
    '{"stock_below":{"place_id":"$payload.place_id","item_id":"$payload.item_id","qty":40}}',
    '{"action":"set_price","actor":null,"payload":{"place_id":"$payload.place_id","item_id":"$payload.item_id","price_pct":25,"culprit":"$actor"},"visibility":"public"}',
    'Damaged stock left the shelf short, so the price rose.',
    1,
    TRUE
),
(
    11,
    'gift',
    NULL,
    '{"action":"state_change","actor":null,"payload":{"entity_id":"$payload.target_actor","set":{"mood":"grateful"}},"visibility":"private"}',
    'A gift left a neighbor feeling grateful.',
    0,
    TRUE
),
(
    12,
    'help_harvest',
    NULL,
    '{"action":"state_change","actor":null,"payload":{"entity_id":"$actor","add":{"trust":2}},"visibility":"private"}',
    'Neighbors noticed the extra hands at harvest.',
    0,
    TRUE
),
(
    13,
    'rumor',
    '{"payload_eq":{"text":"slander"}}',
    '{"action":"state_change","actor":null,"payload":{"entity_id":"$payload.about","add":{"trust":-3}},"visibility":"private"}',
    'A nasty rumor chipped away at a good name.',
    0,
    TRUE
),
(
    14,
    'rumor',
    '{"payload_eq":{"text":"praise"}}',
    '{"action":"state_change","actor":null,"payload":{"entity_id":"$payload.about","add":{"trust":3}},"visibility":"private"}',
    'Kind words lifted a neighbor''s standing.',
    0,
    TRUE
),
(
    15,
    'trade',
    '{"stock_below":{"place_id":"$payload.place_id","item_id":"$payload.item_id","qty":10}}',
    '{"action":"set_price","actor":null,"payload":{"place_id":"$payload.place_id","item_id":"$payload.item_id","price_pct":10},"visibility":"public"}',
    'The shelf nearly emptied, so the price crept up.',
    1,
    TRUE
);

SELECT setval(pg_get_serial_sequence('rule', 'rule_id'), (SELECT max(rule_id) FROM "rule"));

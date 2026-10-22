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
);

SELECT setval(pg_get_serial_sequence('rule', 'rule_id'), (SELECT max(rule_id) FROM "rule"));

-- DEVELOPMENT ONLY. Destroys all data.
DROP FUNCTION IF EXISTS verify_event_chain(INT) CASCADE;
DROP FUNCTION IF EXISTS event_hash_chain() CASCADE;
DROP FUNCTION IF EXISTS event_hash(BYTEA, BIGINT, INT, INT, INT, TEXT, JSONB) CASCADE;
DROP FUNCTION IF EXISTS forbid_event_change() CASCADE;

DROP TABLE IF EXISTS
    scheduled_effect,
    snapshot,
    entity_state,
    stock,
    event_witness,
    event_cause,
    event,
    branch,
    rule,
    action_type,
    item,
    actor,
    home,
    place
CASCADE;

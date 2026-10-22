-- DEVELOPMENT ONLY. Destroys all data.
DROP FUNCTION IF EXISTS advance_day CASCADE;
DROP FUNCTION IF EXISTS process_event_rules CASCADE;
DROP FUNCTION IF EXISTS emit_effect CASCADE;
DROP FUNCTION IF EXISTS rule_matches CASCADE;
DROP FUNCTION IF EXISTS resolve_template CASCADE;
DROP FUNCTION IF EXISTS cascade_max_depth CASCADE;
DROP FUNCTION IF EXISTS apply_action CASCADE;
DROP FUNCTION IF EXISTS join_village CASCADE;
DROP FUNCTION IF EXISTS add_witnesses CASCADE;
DROP FUNCTION IF EXISTS default_visibility CASCADE;
DROP FUNCTION IF EXISTS current_tick CASCADE;
DROP FUNCTION IF EXISTS event_project_trg CASCADE;
DROP FUNCTION IF EXISTS project_event CASCADE;
DROP FUNCTION IF EXISTS adjust_inventory CASCADE;
DROP FUNCTION IF EXISTS patch_entity_state CASCADE;
DROP FUNCTION IF EXISTS entity_state_at CASCADE;
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

-- DEVELOPMENT ONLY. Destroys all data.
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

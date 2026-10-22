-- Derived from event_cause and maintained by a trigger.
-- Stored explicitly because event is immutable.
-- No secondary indexes on purpose (the benchmark checkpoint adds them).

CREATE TABLE causal_closure (
    ancestor_id BIGINT NOT NULL REFERENCES event,
    descendant_id BIGINT NOT NULL REFERENCES event,
    depth INT NOT NULL CHECK (depth >= 0),
    PRIMARY KEY (ancestor_id, descendant_id)
);

CREATE TABLE causal_path (
    event_id BIGINT PRIMARY KEY REFERENCES event,
    path TEXT NOT NULL
);

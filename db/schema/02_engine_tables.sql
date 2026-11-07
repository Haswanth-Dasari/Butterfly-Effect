CREATE TABLE action_type (
    action_type TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

CREATE TABLE rule (
    rule_id SERIAL PRIMARY KEY,
    trigger_action_type TEXT NOT NULL REFERENCES action_type,
    condition TEXT,
    effect_template TEXT NOT NULL,
    narrative_template TEXT,
    delay_ticks INT NOT NULL DEFAULT 0 CHECK (delay_ticks >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE branch (
    branch_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INT REFERENCES branch,
    fork_event BIGINT
);

CREATE TABLE event (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id INT NOT NULL REFERENCES branch,
    tick INT NOT NULL CHECK (tick >= 0),
    actor_id INT REFERENCES actor,
    action_type TEXT NOT NULL REFERENCES action_type,
    payload JSONB NOT NULL,
    prev_hash BYTEA,
    hash BYTEA NOT NULL
);

CREATE TABLE event_cause (
    effect_id BIGINT NOT NULL REFERENCES event,
    cause_id BIGINT NOT NULL REFERENCES event,
    rule_id INT REFERENCES rule,
    PRIMARY KEY (effect_id, cause_id),
    CHECK (cause_id < effect_id)
);

CREATE TABLE event_witness (
    event_id BIGINT NOT NULL REFERENCES event,
    actor_id INT NOT NULL REFERENCES actor,
    PRIMARY KEY (event_id, actor_id)
);

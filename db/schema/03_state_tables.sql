CREATE TABLE stock (
    place_id INT NOT NULL REFERENCES place,
    item_id INT NOT NULL REFERENCES item,
    branch_id INT NOT NULL REFERENCES branch,
    qty INT NOT NULL CHECK (qty >= 0),
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    PRIMARY KEY (place_id, item_id, branch_id)
);

CREATE TABLE entity_state (
    entity_id INT NOT NULL,
    branch_id INT NOT NULL REFERENCES branch,
    valid_ticks INT4RANGE NOT NULL,
    state JSONB NOT NULL,
    PRIMARY KEY (entity_id, branch_id, valid_ticks),
    EXCLUDE USING gist (entity_id WITH =, branch_id WITH =, valid_ticks WITH &&)
);

COMMENT ON COLUMN entity_state.entity_id IS 'Polymorphic entity identifier; intentionally has no foreign key.';

CREATE TABLE snapshot (
    snapshot_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL REFERENCES branch,
    tick INT NOT NULL CHECK (tick >= 0),
    last_event_id BIGINT NOT NULL REFERENCES event,
    state JSONB NOT NULL,
    UNIQUE (branch_id, tick)
);

CREATE TABLE scheduled_effect (
    scheduled_id SERIAL PRIMARY KEY,
    branch_id INT NOT NULL REFERENCES branch,
    due_tick INT NOT NULL CHECK (due_tick >= 0),
    source_event_id BIGINT NOT NULL REFERENCES event,
    rule_id INT NOT NULL REFERENCES rule,
    payload JSONB NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT FALSE
);

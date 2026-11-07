-- This function is the only place the event hash formula is defined.
CREATE FUNCTION event_hash(
    p_prev BYTEA,
    p_event_id BIGINT,
    p_branch_id INT,
    p_tick INT,
    p_actor_id INT,
    p_action_type TEXT,
    p_payload JSONB
)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT digest(
        coalesce(p_prev, ''::bytea)
        || convert_to(
            concat_ws(
                '|',
                p_event_id,
                p_branch_id,
                p_tick,
                coalesce(p_actor_id::text, ''),
                p_action_type,
                p_payload::text
            ),
            'UTF8'
        ),
        'sha256'
    );
$$;

-- The advisory transaction lock serializes inserts per branch, keeping each branch's hash chain ordered.
CREATE FUNCTION event_hash_chain()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(1001, NEW.branch_id);

    SELECT hash
    INTO NEW.prev_hash
    FROM event
    WHERE branch_id = NEW.branch_id
      AND hash IS NOT NULL
    ORDER BY event_id DESC
    LIMIT 1;

    NEW.hash := event_hash(
        NEW.prev_hash,
        NEW.event_id,
        NEW.branch_id,
        NEW.tick,
        NEW.actor_id,
        NEW.action_type,
        NEW.payload
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER event_hash_chain
BEFORE INSERT ON event
FOR EACH ROW
EXECUTE FUNCTION event_hash_chain();

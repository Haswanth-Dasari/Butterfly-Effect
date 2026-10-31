-- Look Back: lineage-aware as-of reads for the time slider.
-- entity_state_at only looks inside one branch; these walk the lineage
-- (parent branches up to their fork point), which a child branch needs.

-- 1. Entity state as of a tick, walking the lineage (nearest branch wins).
CREATE OR REPLACE FUNCTION entity_state_at_lineage(p_entity INT, p_branch INT, p_tick INT)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    SELECT es.state
    FROM lineage_branches(p_branch, (SELECT COALESCE(MAX(event_id), 9223372036854775807) FROM event WHERE branch_id = p_branch)) l
    JOIN entity_state es
      ON es.branch_id = l.branch_id
     AND es.entity_id = p_entity
     AND es.valid_ticks @> p_tick
    -- lineage_branches returns the branch itself first, then its ancestors;
    -- rely on that order (child branch state, if present, wins over parent).
    LIMIT 1;
$$;

-- 2. World state as of a tick (any branch, any point in its history), without
--    creating a lasting branch. Reuses the already-tested fork machinery
--    (fork_branch + serialize_branch_state) inside one transaction, then
--    deletes the scratch branch it created so the branch table stays clean.
--    Read-only from the caller's point of view: either everything is rolled
--    back together or nothing is.
CREATE OR REPLACE FUNCTION look_back(p_branch INT, p_tick INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fork_event BIGINT;
    v_scratch_branch INT;
    v_state JSONB;
BEGIN
    IF p_tick >= current_tick(p_branch) THEN
        -- Already at or past the present: no replay needed.
        RETURN serialize_branch_state(p_branch);
    END IF;

    SELECT MAX(event_id) INTO v_fork_event
    FROM lineage_events(p_branch, (SELECT MAX(event_id) FROM event WHERE branch_id = p_branch))
    WHERE tick <= p_tick;

    IF v_fork_event IS NULL THEN
        RAISE EXCEPTION 'look_back: no event at or before tick % on branch %', p_tick, p_branch;
    END IF;

    v_scratch_branch := fork_branch(p_branch, v_fork_event,
        'lookback_' || p_branch || '_' || p_tick || '_' || clock_timestamp()::text,
        'snapshot_delta');

    v_state := serialize_branch_state(v_scratch_branch);

    -- Clean up: this is a read, not a real fork. Remove everything the fork created.
    DELETE FROM scheduled_effect WHERE branch_id = v_scratch_branch;
    DELETE FROM snapshot WHERE branch_id = v_scratch_branch;
    DELETE FROM entity_state WHERE branch_id = v_scratch_branch;
    DELETE FROM stock WHERE branch_id = v_scratch_branch;
    DELETE FROM event_witness WHERE event_id IN (SELECT event_id FROM event WHERE branch_id = v_scratch_branch);
    DELETE FROM event_cause WHERE effect_id IN (SELECT event_id FROM event WHERE branch_id = v_scratch_branch);
    ALTER TABLE event DISABLE TRIGGER event_immutable;
    DELETE FROM event WHERE branch_id = v_scratch_branch;
    ALTER TABLE event ENABLE TRIGGER event_immutable;
    DELETE FROM branch WHERE branch_id = v_scratch_branch;

    RETURN v_state;
END;
$$;

-- Role grants live with the rest of the privilege grants in
-- db/security/03_privileges.sql (that file's step 3 already revokes EXECUTE
-- from PUBLIC on every function in this schema, this one included).

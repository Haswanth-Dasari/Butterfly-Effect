-- Application-level recovery: rebuild projections from the immutable event store.

-- Digest of branch projections (stock and open entities), deliberately excluding pending effects.
CREATE OR REPLACE FUNCTION branch_projection_digest(p_branch INT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    WITH s AS (
        SELECT serialize_branch_state(p_branch) AS s
    )
    SELECT encode(digest(jsonb_build_object('stock', s->'stock', 'entities', s->'entities')::text, 'sha256'), 'hex')
    FROM s;
$$;

-- Same replay machinery as fork_branch; scheduled_effect is queue state that cannot be derived from events and is protected by database-level recovery; one transaction, so a failure changes nothing.
CREATE OR REPLACE FUNCTION rebuild_projections(p_branch INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_head BIGINT;
    v_base snapshot;
    e event;
    v_ev_copy event;
BEGIN
    -- 1. If the branch does not exist or has no events: RAISE EXCEPTION 'unknown branch'.
    IF NOT EXISTS (SELECT 1 FROM branch WHERE branch_id = p_branch)
       OR NOT EXISTS (SELECT 1 FROM event WHERE branch_id = p_branch) THEN
        RAISE EXCEPTION 'unknown branch';
    END IF;

    -- 2. v_head := max(event_id) of the branch's own events.
    SELECT max(event_id) INTO v_head
    FROM event
    WHERE branch_id = p_branch;

    -- 3. Baseline: snapshot with SMALLEST last_event_id on lineage root
    SELECT s.*
    INTO v_base
    FROM snapshot s
    JOIN lineage_branches(p_branch, v_head) l
      ON s.branch_id = l.branch_id AND s.last_event_id <= l.upto
    JOIN branch b ON b.branch_id = s.branch_id AND b.parent_id IS NULL
    ORDER BY s.last_event_id ASC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no baseline snapshot';
    END IF;

    -- 4. Delete current projection rows (do NOT touch scheduled_effect)
    DELETE FROM stock WHERE branch_id = p_branch;
    DELETE FROM entity_state WHERE branch_id = p_branch;

    -- 5. Restore baseline state
    PERFORM restore_branch_state(p_branch, v_base.state, v_base.tick);

    -- 6. Replay lineage events occurring after the baseline snapshot
    FOR e IN
        SELECT *
        FROM lineage_events(p_branch, v_head)
        WHERE event_id > v_base.last_event_id
        ORDER BY event_id
    LOOP
        v_ev_copy := e;
        v_ev_copy.branch_id := p_branch;
        PERFORM project_event(v_ev_copy);
    END LOOP;
END;
$$;

-- Rebuilds projections for all branches in branch_id order and returns the count of branches rebuilt.
CREATE OR REPLACE FUNCTION rebuild_all_projections()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_count INT := 0;
BEGIN
    FOR r IN SELECT branch_id FROM branch ORDER BY branch_id LOOP
        PERFORM rebuild_projections(r.branch_id);
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;

-- Rebuilds projections for a branch, then recomputes causal structures and refreshes daily views.
CREATE OR REPLACE FUNCTION rebuild_world(p_branch INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM rebuild_projections(p_branch);
    PERFORM rebuild_causal_structures();
    PERFORM refresh_daily_views();
END;
$$;

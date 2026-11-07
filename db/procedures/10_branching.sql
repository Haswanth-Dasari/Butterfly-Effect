-- Branching (parallel villages): history inheritance, state serialization,
-- snapshots, copy-on-write / replay / snapshot-delta forking, and branch diffing.

-- 1. Returns all ancestor branches up the lineage tree, each bounded by the fork event of its child.
CREATE OR REPLACE FUNCTION lineage_branches(p_branch INT, p_upto BIGINT)
RETURNS TABLE (branch_id INT, upto BIGINT)
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE lin AS (
        SELECT p_branch AS branch_id, p_upto AS upto
        UNION ALL
        SELECT b.parent_id, b.fork_event
        FROM lin l
        JOIN branch b ON b.branch_id = l.branch_id
        WHERE b.parent_id IS NOT NULL
    )
    SELECT lin.branch_id, lin.upto FROM lin;
$$;

-- 2. Returns all events in the branch's inherited lineage up to p_upto.
CREATE OR REPLACE FUNCTION lineage_events(p_branch INT, p_upto BIGINT)
RETURNS SETOF event
LANGUAGE sql
STABLE
AS $$
    SELECT e.*
    FROM event e
    JOIN lineage_branches(p_branch, p_upto) l
      ON e.branch_id = l.branch_id
     AND e.event_id <= l.upto
    ORDER BY e.event_id;
$$;

-- 3. Canonical JSON serialization of current branch state (stock, open entities, unprocessed pending effects).
-- Row ranges, scheduled_id and processed flags are deliberately excluded to ensure deterministic digests.
CREATE OR REPLACE FUNCTION serialize_branch_state(p_branch INT)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object(
        'stock',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'place_id', place_id,
                        'item_id', item_id,
                        'qty', qty,
                        'price', price
                    )
                    ORDER BY place_id, item_id
                )
                FROM stock
                WHERE branch_id = p_branch
            ),
            '[]'::jsonb
        ),
        'entities',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'entity_id', entity_id,
                        'state', state
                    )
                    ORDER BY entity_id
                )
                FROM entity_state
                WHERE branch_id = p_branch
                  AND upper_inf(valid_ticks)
            ),
            '[]'::jsonb
        ),
        'pending',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'due_tick', due_tick,
                        'source_event_id', source_event_id,
                        'rule_id', rule_id,
                        'payload', payload
                    )
                    ORDER BY source_event_id, rule_id
                )
                FROM scheduled_effect
                WHERE branch_id = p_branch
                  AND NOT processed
            ),
            '[]'::jsonb
        )
    );
$$;

-- 4. SHA-256 hex digest of the branch's canonical state serialization.
CREATE OR REPLACE FUNCTION branch_state_digest(p_branch INT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT encode(digest(serialize_branch_state(p_branch)::text, 'sha256'), 'hex');
$$;

-- 5. Restores stock and entity_state from a serialized state.
-- Do NOT restore 'pending' here (it is derived separately).
CREATE OR REPLACE FUNCTION restore_branch_state(p_branch INT, p_state JSONB, p_tick INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM stock WHERE branch_id = p_branch)
       OR EXISTS (SELECT 1 FROM entity_state WHERE branch_id = p_branch) THEN
        RAISE EXCEPTION 'branch already has state';
    END IF;

    IF p_state ? 'stock' AND p_state->'stock' <> '[]'::jsonb THEN
        INSERT INTO stock (place_id, item_id, branch_id, qty, price)
        SELECT s.place_id, s.item_id, p_branch, s.qty, s.price
        FROM jsonb_to_recordset(p_state->'stock') AS s(place_id INT, item_id INT, qty INT, price NUMERIC);
    END IF;

    IF p_state ? 'entities' AND p_state->'entities' <> '[]'::jsonb THEN
        INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
        SELECT e.entity_id, p_branch, int4range(p_tick, NULL), e.state
        FROM jsonb_to_recordset(p_state->'entities') AS e(entity_id INT, state JSONB);
    END IF;
END;
$$;

-- 6. Creates an immutable snapshot of branch state at current_tick.
-- Intentionally has no ON CONFLICT: a second snapshot at the same tick must raise
-- a unique violation to ensure we never overwrite an established baseline.
CREATE OR REPLACE FUNCTION create_snapshot(p_branch INT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_snapshot_id BIGINT;
BEGIN
    INSERT INTO snapshot (branch_id, tick, last_event_id, state)
    VALUES (
        p_branch,
        current_tick(p_branch),
        (SELECT max(event_id) FROM event WHERE branch_id = p_branch),
        serialize_branch_state(p_branch)
    )
    RETURNING snapshot_id INTO v_snapshot_id;

    RETURN v_snapshot_id;
END;
$$;

-- 7. Forks a parent branch at p_fork_event into a new child branch.
--
-- Strategies:
--   'cow': Copy-on-write duplicates current tables directly. It is O(state size) and
--          fast, but strictly head-only (can only fork from the parent's latest event).
--   'replay': Full replay from the root branch baseline snapshot (smallest last_event_id).
--          Deterministic and can reconstruct any past event in the lineage.
--   'snapshot_delta': Replays from the latest usable snapshot whose last_event_id <= fork event.
--          O(events since snapshot), balancing speed and time-travel capability.
--
-- History is inherited: the child branch holds only its own new events starting with
-- a 'world_start' fork marker; previous history is queried through lineage_events.
CREATE OR REPLACE FUNCTION fork_branch(
    p_parent INT,
    p_fork_event BIGINT,
    p_name TEXT,
    p_strategy TEXT DEFAULT 'snapshot_delta'
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_fork_event event;
    v_child INT;
    v_base snapshot;
    v_replayed_count INT := 0;
    e event;
    v_ev_copy event;
BEGIN
    -- 1. Validate strategy
    IF p_strategy NOT IN ('replay', 'snapshot_delta', 'cow') THEN
        RAISE EXCEPTION 'unknown strategy %', p_strategy;
    END IF;

    -- 2. Load and validate fork event
    SELECT * INTO v_fork_event
    FROM event
    WHERE event_id = p_fork_event AND branch_id = p_parent;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'fork event must belong to the parent branch';
    END IF;

    -- 3. Create child branch
    INSERT INTO branch (name, parent_id, fork_event)
    VALUES (p_name, p_parent, p_fork_event)
    RETURNING branch_id INTO v_child;

    -- 4. Insert child's first event (world_start fork marker)
    INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
    VALUES (
        v_child,
        v_fork_event.tick,
        NULL,
        'world_start',
        jsonb_build_object(
            'fork_of', p_parent,
            'fork_event', p_fork_event,
            'strategy', p_strategy
        )
    );

    -- 5. Restore state by strategy
    IF p_strategy = 'cow' THEN
        IF p_fork_event <> (SELECT max(event_id) FROM event WHERE branch_id = p_parent) THEN
            RAISE EXCEPTION 'copy-on-write can only fork from the latest event of the parent';
        END IF;

        -- Copy stock
        INSERT INTO stock (place_id, item_id, branch_id, qty, price)
        SELECT place_id, item_id, v_child, qty, price
        FROM stock
        WHERE branch_id = p_parent;

        -- Copy open entity states
        INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
        SELECT entity_id, v_child, int4range(v_fork_event.tick, NULL), state
        FROM entity_state
        WHERE branch_id = p_parent
          AND upper_inf(valid_ticks);

        -- Copy unprocessed scheduled effects
        INSERT INTO scheduled_effect (branch_id, due_tick, source_event_id, rule_id, payload, processed)
        SELECT v_child, due_tick, source_event_id, rule_id, payload, false
        FROM scheduled_effect
        WHERE branch_id = p_parent
          AND NOT processed;

    ELSIF p_strategy = 'replay' THEN
        -- Smallest last_event_id snapshot on the root of the lineage within lineage_branches
        SELECT s.*
        INTO v_base
        FROM snapshot s
        JOIN lineage_branches(p_parent, p_fork_event) l
          ON s.branch_id = l.branch_id AND s.last_event_id <= l.upto
        JOIN branch b ON b.branch_id = s.branch_id AND b.parent_id IS NULL
        ORDER BY s.last_event_id ASC
        LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'no baseline snapshot';
        END IF;

        PERFORM restore_branch_state(v_child, v_base.state, v_base.tick);

        FOR e IN
            SELECT *
            FROM lineage_events(p_parent, p_fork_event)
            WHERE event_id > v_base.last_event_id
            ORDER BY event_id
        LOOP
            v_ev_copy := e;
            v_ev_copy.branch_id := v_child;
            PERFORM project_event(v_ev_copy);
            v_replayed_count := v_replayed_count + 1;
        END LOOP;

        RAISE NOTICE 'fork %: strategy %, replayed % events', v_child, p_strategy, v_replayed_count;

        INSERT INTO scheduled_effect (branch_id, due_tick, source_event_id, rule_id, payload, processed)
        SELECT v_child, s.due_tick, s.source_event_id, s.rule_id, s.payload, false
        FROM scheduled_effect s
        WHERE s.branch_id = p_parent
          AND s.source_event_id <= p_fork_event
          AND (
              NOT s.processed
              OR COALESCE((
                  SELECT min(ec.effect_id)
                  FROM event_cause ec
                  JOIN event ef ON ef.event_id = ec.effect_id
                  WHERE ec.cause_id = s.source_event_id
                    AND ec.rule_id = s.rule_id
                    AND ef.branch_id = s.branch_id
              ), 0) > p_fork_event
          );

    ELSIF p_strategy = 'snapshot_delta' THEN
        -- Largest last_event_id snapshot within lineage_branches
        SELECT s.*
        INTO v_base
        FROM snapshot s
        JOIN lineage_branches(p_parent, p_fork_event) l
          ON s.branch_id = l.branch_id AND s.last_event_id <= l.upto
        ORDER BY s.last_event_id DESC
        LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'no usable snapshot';
        END IF;

        PERFORM restore_branch_state(v_child, v_base.state, v_base.tick);

        FOR e IN
            SELECT *
            FROM lineage_events(p_parent, p_fork_event)
            WHERE event_id > v_base.last_event_id
            ORDER BY event_id
        LOOP
            v_ev_copy := e;
            v_ev_copy.branch_id := v_child;
            PERFORM project_event(v_ev_copy);
            v_replayed_count := v_replayed_count + 1;
        END LOOP;

        RAISE NOTICE 'fork %: strategy %, replayed % events', v_child, p_strategy, v_replayed_count;

        INSERT INTO scheduled_effect (branch_id, due_tick, source_event_id, rule_id, payload, processed)
        SELECT v_child, s.due_tick, s.source_event_id, s.rule_id, s.payload, false
        FROM scheduled_effect s
        WHERE s.branch_id = p_parent
          AND s.source_event_id <= p_fork_event
          AND (
              NOT s.processed
              OR COALESCE((
                  SELECT min(ec.effect_id)
                  FROM event_cause ec
                  JOIN event ef ON ef.event_id = ec.effect_id
                  WHERE ec.cause_id = s.source_event_id
                    AND ec.rule_id = s.rule_id
                    AND ef.branch_id = s.branch_id
              ), 0) > p_fork_event
          );
    END IF;

    -- 6. Return child branch id
    RETURN v_child;
END;
$$;

-- 8. Returns differences between current states of branch p_a and branch p_b.
CREATE OR REPLACE FUNCTION branch_diff(p_a INT, p_b INT)
RETURNS TABLE (kind TEXT, key TEXT, a_value TEXT, b_value TEXT)
LANGUAGE sql
STABLE
AS $$
    WITH stock_diff AS (
        SELECT
            'stock'::TEXT AS kind,
            COALESCE(p.name, p2.name) || ' / ' || COALESCE(i.name, i2.name) AS key,
            CASE WHEN a.place_id IS NOT NULL THEN 'qty=' || a.qty || ' price=' || a.price ELSE NULL END AS a_value,
            CASE WHEN b.place_id IS NOT NULL THEN 'qty=' || b.qty || ' price=' || b.price ELSE NULL END AS b_value
        FROM (SELECT * FROM stock WHERE branch_id = p_a) a
        FULL JOIN (SELECT * FROM stock WHERE branch_id = p_b) b
          ON a.place_id = b.place_id AND a.item_id = b.item_id
        LEFT JOIN place p ON p.place_id = a.place_id
        LEFT JOIN item i ON i.item_id = a.item_id
        LEFT JOIN place p2 ON p2.place_id = b.place_id
        LEFT JOIN item i2 ON i2.item_id = b.item_id
        WHERE a.qty IS DISTINCT FROM b.qty
           OR a.price IS DISTINCT FROM b.price
    ),
    entity_diff AS (
        SELECT
            'entity'::TEXT AS kind,
            COALESCE(act.name, COALESCE(a.entity_id, b.entity_id)::text) AS key,
            a.state::text AS a_value,
            b.state::text AS b_value
        FROM (SELECT * FROM entity_state WHERE branch_id = p_a AND upper_inf(valid_ticks)) a
        FULL JOIN (SELECT * FROM entity_state WHERE branch_id = p_b AND upper_inf(valid_ticks)) b
          ON a.entity_id = b.entity_id
        LEFT JOIN actor act ON act.actor_id = COALESCE(a.entity_id, b.entity_id)
        WHERE a.state IS DISTINCT FROM b.state
    )
    SELECT * FROM stock_diff
    UNION ALL
    SELECT * FROM entity_diff
    ORDER BY kind, key;
$$;

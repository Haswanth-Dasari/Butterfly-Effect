-- Follow prev_hash links rather than event_id order because event IDs do not define chain integrity.
CREATE FUNCTION verify_event_chain(p_branch_id INT DEFAULT NULL)
RETURNS TABLE (branch_id INT, event_id BIGINT, step INT, problem TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_branch_id INT;
    v_head_count BIGINT;
    v_head_event_id BIGINT;
    v_event_count BIGINT;
    v_current_event_id BIGINT;
    v_current_tick INT;
    v_current_actor_id INT;
    v_current_action_type TEXT;
    v_current_payload JSONB;
    v_current_prev_hash BYTEA;
    v_current_hash BYTEA;
    v_computed_hash BYTEA;
    v_next_count BIGINT;
    v_next_event_id BIGINT;
    v_steps INT;
    v_visited BIGINT[];
    v_unvisited_event_id BIGINT;
    v_problem_found BOOLEAN;
BEGIN
    FOR v_branch_id IN
        SELECT DISTINCT e.branch_id
        FROM event AS e
        WHERE p_branch_id IS NULL OR e.branch_id = p_branch_id
        ORDER BY e.branch_id
    LOOP
        SELECT count(*), min(e.event_id)
        INTO v_head_count, v_head_event_id
        FROM event AS e
        WHERE e.branch_id = v_branch_id
          AND e.prev_hash IS NULL;

        IF v_head_count <> 1 THEN
            branch_id := v_branch_id;
            event_id := v_head_event_id;
            step := 0;
            problem := format('expected exactly 1 chain head, found %s', v_head_count);
            RETURN NEXT;
            CONTINUE;
        END IF;

        SELECT count(*)
        INTO v_event_count
        FROM event AS e
        WHERE e.branch_id = v_branch_id;

        SELECT e.event_id, e.tick, e.actor_id, e.action_type, e.payload, e.prev_hash, e.hash
        INTO v_current_event_id, v_current_tick, v_current_actor_id, v_current_action_type,
             v_current_payload, v_current_prev_hash, v_current_hash
        FROM event AS e
        WHERE e.branch_id = v_branch_id
          AND e.event_id = v_head_event_id;

        v_steps := 0;
        v_visited := ARRAY[]::BIGINT[];
        v_problem_found := FALSE;

        LOOP
            v_steps := v_steps + 1;
            v_visited := array_append(v_visited, v_current_event_id);

            v_computed_hash := event_hash(
                v_current_prev_hash,
                v_current_event_id,
                v_branch_id,
                v_current_tick,
                v_current_actor_id,
                v_current_action_type,
                v_current_payload
            );

            IF v_computed_hash IS DISTINCT FROM v_current_hash THEN
                branch_id := v_branch_id;
                event_id := v_current_event_id;
                step := v_steps;
                problem := 'hash mismatch';
                RETURN NEXT;
                v_problem_found := TRUE;
                EXIT;
            END IF;

            SELECT count(*), min(e.event_id)
            INTO v_next_count, v_next_event_id
            FROM event AS e
            WHERE e.branch_id = v_branch_id
              AND e.prev_hash = v_current_hash;

            IF v_next_count > 1 THEN
                branch_id := v_branch_id;
                event_id := v_current_event_id;
                step := v_steps;
                problem := 'chain forks';
                RETURN NEXT;
                v_problem_found := TRUE;
                EXIT;
            ELSIF v_next_count = 0 THEN
                EXIT;
            END IF;

            SELECT e.tick, e.actor_id, e.action_type, e.payload, e.prev_hash, e.hash
            INTO v_current_tick, v_current_actor_id, v_current_action_type, v_current_payload,
                 v_current_prev_hash, v_current_hash
            FROM event AS e
            WHERE e.branch_id = v_branch_id
              AND e.event_id = v_next_event_id;

            v_current_event_id := v_next_event_id;
        END LOOP;

        IF NOT v_problem_found AND v_steps < v_event_count THEN
            SELECT min(e.event_id)
            INTO v_unvisited_event_id
            FROM event AS e
            WHERE e.branch_id = v_branch_id
              AND NOT (e.event_id = ANY(v_visited));

            branch_id := v_branch_id;
            event_id := v_unvisited_event_id;
            step := v_steps;
            problem := 'unreachable events (broken chain link)';
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;

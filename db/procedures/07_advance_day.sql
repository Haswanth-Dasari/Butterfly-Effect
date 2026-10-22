-- Advances a branch to the next day, processing scheduled effects and cascading rules.
CREATE FUNCTION advance_day(p_branch INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_new INT;
    v_day_event event;
    s scheduled_effect;
    v_source_event event;
    v_new_ev event;
BEGIN
    -- FOR UPDATE SKIP LOCKED lets parallel workers claim different jobs; the whole day is one transaction.

    -- 1. Branch must exist
    IF NOT EXISTS (SELECT 1 FROM branch WHERE branch_id = p_branch) THEN
        RAISE EXCEPTION 'unknown branch';
    END IF;

    -- 2. New tick
    v_new := current_tick(p_branch) + 1;

    -- 3. Day start event
    INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
    VALUES (p_branch, v_new, NULL, 'day_start', jsonb_build_object('day', v_new))
    RETURNING * INTO v_day_event;

    PERFORM process_event_rules(v_day_event, 0);

    -- 4. Process due scheduled effects
    FOR s IN
        SELECT *
        FROM scheduled_effect
        WHERE branch_id = p_branch
          AND NOT processed
          AND due_tick <= v_new
        ORDER BY due_tick, scheduled_id
        FOR UPDATE SKIP LOCKED
    LOOP
        SELECT * INTO v_source_event
        FROM event
        WHERE event_id = s.source_event_id;

        v_new_ev := emit_effect(v_source_event, s.rule_id, s.payload, v_new);

        UPDATE scheduled_effect
        SET processed = TRUE
        WHERE scheduled_id = s.scheduled_id;

        PERFORM process_event_rules(v_new_ev, 0);
    END LOOP;

    -- 5. Return new tick
    RETURN v_new;
END;
$$;

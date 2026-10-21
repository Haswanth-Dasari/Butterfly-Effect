-- One call = one transaction; any error undoes the event, witnesses and projections together.

-- Returns the current tick for a branch based on its latest event.
CREATE FUNCTION current_tick(p_branch INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    -- There is no clock table yet; the day-advance function comes later.
    SELECT COALESCE(MAX(tick), 0)
    FROM event
    WHERE branch_id = p_branch;
$$;

-- Returns the default visibility classification for an action type.
CREATE FUNCTION default_visibility(p_action TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_action IN ('steal', 'sabotage') THEN 'secret'
        WHEN p_action IN ('set_price', 'build', 'feast') THEN 'public'
        ELSE 'private'
    END;
$$;

-- Adds witnesses to an event based on visibility rules and returns the number of rows inserted.
CREATE FUNCTION add_witnesses(p_event BIGINT, p_visibility TEXT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_actor_id INT;
    v_payload JSONB;
    v_target_actor INT;
    v_inserted INT := 0;
BEGIN
    SELECT actor_id, payload
    INTO v_actor_id, v_payload
    FROM event
    WHERE event_id = p_event;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown event %', p_event;
    END IF;

    IF p_visibility = 'secret' THEN
        IF v_actor_id IS NOT NULL THEN
            INSERT INTO event_witness (event_id, actor_id)
            VALUES (p_event, v_actor_id)
            ON CONFLICT DO NOTHING;
            GET DIAGNOSTICS v_inserted = ROW_COUNT;
        END IF;
    ELSIF p_visibility = 'private' THEN
        v_target_actor := (v_payload->>'target_actor')::int;
        INSERT INTO event_witness (event_id, actor_id)
        SELECT p_event, a_id
        FROM (
            SELECT v_actor_id AS a_id
            UNION
            SELECT v_target_actor AS a_id
        ) s
        WHERE a_id IS NOT NULL
        ON CONFLICT DO NOTHING;
        GET DIAGNOSTICS v_inserted = ROW_COUNT;
    ELSIF p_visibility = 'public' THEN
        INSERT INTO event_witness (event_id, actor_id)
        SELECT p_event, actor_id
        FROM actor
        WHERE actor_id IS NOT NULL
        ON CONFLICT DO NOTHING;
        GET DIAGNOSTICS v_inserted = ROW_COUNT;
    ELSE
        RAISE EXCEPTION 'unknown visibility %', p_visibility;
    END IF;

    RETURN v_inserted;
END;
$$;

-- Registers a new player actor, logs their arrive event, and witnesses it publicly.
CREATE FUNCTION join_village(p_branch INT, p_name TEXT, p_coins INT DEFAULT 5)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_actor_id INT;
    v_event_id BIGINT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM branch WHERE branch_id = p_branch) THEN
        RAISE EXCEPTION 'unknown branch';
    END IF;

    INSERT INTO actor (name, kind)
    VALUES (p_name, 'player')
    RETURNING actor_id INTO v_actor_id;

    INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
    VALUES (p_branch, current_tick(p_branch), v_actor_id, 'arrive', jsonb_build_object('coins', p_coins))
    RETURNING event_id INTO v_event_id;

    PERFORM add_witnesses(v_event_id, 'public');

    RETURN v_actor_id;
END;
$$;

-- Validates and applies a player action, recording the event, witnesses, and projections.
CREATE FUNCTION apply_action(
    p_branch INT,
    p_actor INT,
    p_action TEXT,
    p_payload JSONB,
    p_visibility TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_actor_kind TEXT;
    v_tick INT;
    v_action_count INT;
    v_event_id BIGINT;
BEGIN
    -- 1. Branch must exist
    IF NOT EXISTS (SELECT 1 FROM branch WHERE branch_id = p_branch) THEN
        RAISE EXCEPTION 'unknown branch';
    END IF;

    -- 2. Actor must exist
    SELECT kind INTO v_actor_kind
    FROM actor
    WHERE actor_id = p_actor;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown actor';
    END IF;

    -- 3. p_action must be one of the 10 player actions; payload must not be NULL
    IF p_action NOT IN (
        'gift', 'trade', 'steal', 'rumor', 'build',
        'hire', 'set_price', 'help_harvest', 'sabotage', 'feast'
    ) THEN
        RAISE EXCEPTION 'not a player action: %', p_action;
    END IF;

    IF p_payload IS NULL THEN
        RAISE EXCEPTION 'payload must not be null';
    END IF;

    -- 4. Current tick
    v_tick := current_tick(p_branch);

    -- 5. Player action limit (3 actions per day)
    IF v_actor_kind = 'player' THEN
        SELECT count(*)
        INTO v_action_count
        FROM event
        WHERE branch_id = p_branch
          AND actor_id = p_actor
          AND tick = v_tick
          AND action_type IN (
              'gift', 'trade', 'steal', 'rumor', 'build',
              'hire', 'set_price', 'help_harvest', 'sabotage', 'feast'
          );

        -- 3 actions per day
        IF v_action_count >= 3 THEN
            RAISE EXCEPTION 'no actions left today';
        END IF;
    END IF;

    -- 6. Insert event (triggers compute hash/prev_hash and projection)
    INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
    VALUES (p_branch, v_tick, p_actor, p_action, p_payload)
    RETURNING event_id INTO v_event_id;

    -- 7. Add witnesses
    PERFORM add_witnesses(v_event_id, COALESCE(p_visibility, default_visibility(p_action)));

    -- 8. Return event_id
    RETURN v_event_id;
END;
$$;

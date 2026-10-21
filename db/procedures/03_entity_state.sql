-- Returns the entity state at a given tick in a branch, or NULL if none.
CREATE FUNCTION entity_state_at(p_entity INT, p_branch INT, p_tick INT)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    SELECT state
    FROM entity_state
    WHERE entity_id = p_entity
      AND branch_id = p_branch
      AND valid_ticks @> p_tick;
$$;

-- Patches an entity's open state row at a given tick, versioning if tick advances.
CREATE FUNCTION patch_entity_state(p_entity INT, p_branch INT, p_tick INT, p_patch JSONB)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_valid_ticks INT4RANGE;
    v_state JSONB;
BEGIN
    SELECT valid_ticks, state
    INTO v_valid_ticks, v_state
    FROM entity_state
    WHERE entity_id = p_entity
      AND branch_id = p_branch
      AND upper_inf(valid_ticks)
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no current state for entity %', p_entity;
    END IF;

    IF p_tick < lower(v_valid_ticks) THEN
        RAISE EXCEPTION 'tick is before the current state begins';
    END IF;

    IF p_tick = lower(v_valid_ticks) THEN
        UPDATE entity_state
        SET state = state || p_patch
        WHERE entity_id = p_entity
          AND branch_id = p_branch
          AND valid_ticks = v_valid_ticks;
    ELSE
        UPDATE entity_state
        SET valid_ticks = int4range(lower(v_valid_ticks), p_tick)
        WHERE entity_id = p_entity
          AND branch_id = p_branch
          AND valid_ticks = v_valid_ticks;

        INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
        VALUES (p_entity, p_branch, int4range(p_tick, NULL), v_state || p_patch);
    END IF;
END;
$$;

-- Adjusts an actor's inventory count for an item by delta at the given tick.
CREATE FUNCTION adjust_inventory(p_actor INT, p_branch INT, p_tick INT, p_item TEXT, p_delta INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_state JSONB;
    v_count INT;
BEGIN
    SELECT state
    INTO v_state
    FROM entity_state
    WHERE entity_id = p_actor
      AND branch_id = p_branch
      AND upper_inf(valid_ticks);

    IF NOT FOUND THEN
        PERFORM patch_entity_state(p_actor, p_branch, p_tick, '{}'::jsonb);
    END IF;

    v_count := COALESCE((v_state->'inv'->>p_item)::int, 0) + p_delta;

    IF v_count < 0 THEN
        RAISE EXCEPTION 'insufficient inventory of %', p_item;
    END IF;

    PERFORM patch_entity_state(
        p_actor,
        p_branch,
        p_tick,
        jsonb_build_object('inv', COALESCE(v_state->'inv', '{}'::jsonb) || jsonb_build_object(p_item, v_count))
    );
END;
$$;

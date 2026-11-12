-- Story engine functions. Writes go through the same event store, witness rows and rule cascade as every
-- other action, so story choices are causally linked, hash-chained and rewindable like everything else.

-- A player may only act as their own character (same rule as apply_action).
CREATE FUNCTION story_actor_claim(p_actor INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_claim TEXT;
BEGIN
    v_claim := NULLIF(current_setting('app.actor_id', true), '');
    IF v_claim IS NOT NULL AND v_claim::int <> p_actor THEN
        RAISE EXCEPTION 'not your character';
    END IF;
END;
$$;

-- Actions spent today: the ten village actions plus story choices that cost an action.
CREATE FUNCTION story_actions_used(p_branch INT, p_actor INT, p_tick INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT count(*)::int
    FROM event
    WHERE branch_id = p_branch
      AND actor_id = p_actor
      AND tick = p_tick
      AND (action_type IN ('gift', 'trade', 'steal', 'rumor', 'build', 'hire', 'set_price', 'help_harvest', 'sabotage', 'feast')
           OR (action_type = 'story_choice' AND payload @> '{"cost":1}'::jsonb));
$$;

-- Has the actor made this choice? p_spec is 'beat' (any option) or 'beat:option'.
CREATE FUNCTION story_chose(p_branch INT, p_actor INT, p_spec TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM event e
        WHERE e.branch_id = p_branch
          AND e.actor_id = p_actor
          AND e.action_type = 'story_choice'
          AND e.payload ->> 'beat' = split_part(p_spec, ':', 1)
          AND (position(':' IN p_spec) = 0 OR e.payload ->> 'option' = split_part(p_spec, ':', 2))
    );
$$;

-- Is this scene on offer right now?
CREATE FUNCTION story_beat_available(p_branch INT, p_actor INT, p_beat TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    b story_beat;
    v_picks INT;
    v_left INT;
    r TEXT;
BEGIN
    SELECT * INTO b FROM story_beat WHERE beat_key = p_beat;
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF b.day <> current_tick(p_branch) THEN
        RETURN FALSE;
    END IF;

    SELECT count(*) INTO v_picks
    FROM event
    WHERE branch_id = p_branch AND actor_id = p_actor
      AND action_type = 'story_choice' AND payload ->> 'beat' = p_beat;
    IF v_picks >= b.max_picks THEN
        RETURN FALSE;
    END IF;

    SELECT count(*) INTO v_left
    FROM story_option o
    WHERE o.beat_key = p_beat
      AND NOT story_chose(p_branch, p_actor, p_beat || ':' || o.option_key);
    IF v_left = 0 THEN
        RETURN FALSE;
    END IF;

    FOREACH r IN ARRAY b.requires_beats LOOP
        IF NOT story_chose(p_branch, p_actor, r) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    FOREACH r IN ARRAY b.forbids_beats LOOP
        IF story_chose(p_branch, p_actor, r) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$;

-- Make a story choice. The choice is an event; everything that follows (meters, clues, consequences)
-- comes out of rules, so it is all causally linked and Ask Why can walk it.
CREATE FUNCTION story_choose(p_branch INT, p_actor INT, p_beat TEXT, p_option TEXT)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    pt playthrough;
    b story_beat;
    o story_option;
    v_tick INT;
    v_ev event;
    v_dead NUMERIC;
BEGIN
    PERFORM story_actor_claim(p_actor);

    SELECT * INTO pt FROM playthrough WHERE branch_id = p_branch AND actor_id = p_actor;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no story in progress';
    END IF;

    SELECT COALESCE((state ->> 'dead')::numeric, 0) INTO v_dead
    FROM entity_state
    WHERE entity_id = p_actor AND branch_id = p_branch AND upper_inf(valid_ticks);
    IF COALESCE(v_dead, 0) >= 1 THEN
        RAISE EXCEPTION 'your story has ended';
    END IF;

    SELECT * INTO b FROM story_beat WHERE beat_key = p_beat AND scenario_key = pt.scenario_key;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown scene';
    END IF;

    IF NOT story_beat_available(p_branch, p_actor, p_beat) THEN
        RAISE EXCEPTION 'that moment has passed';
    END IF;

    SELECT * INTO o FROM story_option WHERE beat_key = p_beat AND option_key = p_option;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown choice';
    END IF;

    IF story_chose(p_branch, p_actor, p_beat || ':' || p_option) THEN
        RAISE EXCEPTION 'you already chose that';
    END IF;

    v_tick := current_tick(p_branch);
    IF b.costs_action AND story_actions_used(p_branch, p_actor, v_tick) >= 3 THEN
        RAISE EXCEPTION 'no actions left today';
    END IF;

    INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
    VALUES (
        p_branch, v_tick, p_actor, 'story_choice',
        jsonb_build_object('beat', p_beat, 'option', p_option, 'cost', CASE WHEN b.costs_action THEN 1 ELSE 0 END)
    )
    RETURNING * INTO v_ev;

    PERFORM add_witnesses(v_ev.event_id, 'private');
    PERFORM process_event_rules(v_ev, 0);

    RETURN jsonb_build_object('event_id', v_ev.event_id, 'beat', p_beat, 'option', p_option, 'result', o.result_text);
END;
$$;

-- Strength (0-3) of each link of the case at the end of a given tick.
CREATE FUNCTION story_link_strength(p_branch INT, p_actor INT, p_upto_tick INT)
RETURNS TABLE (link_key TEXT, strength INT)
LANGUAGE sql
STABLE
AS $$
    SELECT l.link_key,
           COALESCE((
               SELECT LEAST(3, SUM(cl.weight))::int
               FROM clue_link cl
               WHERE cl.link_key = l.link_key
                 AND cl.clue_key IN (
                     SELECT e.payload ->> 'clue'
                     FROM event e
                     WHERE e.branch_id = p_branch AND e.actor_id = p_actor
                       AND e.action_type = 'discover' AND e.tick <= p_upto_tick
                 )
           ), 0)
    FROM case_link l
    WHERE l.scenario_key = (SELECT scenario_key FROM playthrough WHERE branch_id = p_branch);
$$;

CREATE FUNCTION story_progress(p_branch INT, p_actor INT, p_upto_tick INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(strength), 0)::int FROM story_link_strength(p_branch, p_actor, p_upto_tick);
$$;

-- The player's own case board: the seven links with their strength, and every clue they have found.
CREATE FUNCTION story_board(p_branch INT, p_actor INT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tick INT;
    v_links JSONB;
    v_clues JSONB;
BEGIN
    PERFORM story_actor_claim(p_actor);
    v_tick := current_tick(p_branch);

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'key', l.link_key, 'title', l.title, 'question', l.question, 'strength', s.strength
           ) ORDER BY l.ord), '[]'::jsonb)
    INTO v_links
    FROM case_link l
    JOIN story_link_strength(p_branch, p_actor, v_tick) s ON s.link_key = l.link_key;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'key', c.clue_key, 'title', c.title, 'kind', c.kind, 'journal', c.journal, 'tick', d.tick,
               'links', COALESCE((SELECT jsonb_agg(jsonb_build_object('link', cl.link_key, 'weight', cl.weight))
                                  FROM clue_link cl WHERE cl.clue_key = c.clue_key), '[]'::jsonb)
           ) ORDER BY d.tick, c.clue_key), '[]'::jsonb)
    INTO v_clues
    FROM clue c
    JOIN (
        SELECT e.payload ->> 'clue' AS clue_key, min(e.tick) AS tick
        FROM event e
        WHERE e.branch_id = p_branch AND e.actor_id = p_actor AND e.action_type = 'discover'
        GROUP BY 1
    ) d ON d.clue_key = c.clue_key;

    RETURN jsonb_build_object('links', v_links, 'clues', v_clues, 'progress', story_progress(p_branch, p_actor, v_tick));
END;
$$;

-- The Compass (optional guidance). It reports how close the player's UNDERSTANDING is to the truth;
-- it names categories of the case, never a person, and never says what to do.
CREATE FUNCTION story_compass(p_branch INT, p_actor INT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    pt playthrough;
    v_tick INT;
    v_score INT;
    v_prev INT;
    v_mis NUMERIC;
    v_needle TEXT;
    v_gained TEXT;
    v_reason TEXT;
BEGIN
    PERFORM story_actor_claim(p_actor);
    SELECT * INTO pt FROM playthrough WHERE branch_id = p_branch AND actor_id = p_actor;
    IF NOT FOUND OR NOT pt.guided THEN
        RETURN jsonb_build_object('guided', false);
    END IF;

    v_tick := current_tick(p_branch);
    SELECT COALESCE((state ->> 'misdirect')::numeric, 0) INTO v_mis
    FROM entity_state WHERE entity_id = p_actor AND branch_id = p_branch AND upper_inf(valid_ticks);

    v_score := GREATEST(0, story_progress(p_branch, p_actor, v_tick) - COALESCE(v_mis, 0)::int);
    v_prev := GREATEST(0, story_progress(p_branch, p_actor, v_tick - 1) - COALESCE(v_mis, 0)::int);

    v_needle := CASE
        WHEN v_score < 4 THEN 'Lost'
        WHEN v_score < 9 THEN 'Cold'
        WHEN v_score < 13 THEN 'Cool'
        WHEN v_score < 17 THEN 'Warm'
        ELSE 'Hot'
    END;

    SELECT string_agg(l.title, ', ' ORDER BY l.ord) INTO v_gained
    FROM story_link_strength(p_branch, p_actor, v_tick) a
    JOIN story_link_strength(p_branch, p_actor, v_tick - 1) b ON b.link_key = a.link_key
    JOIN case_link l ON l.link_key = a.link_key
    WHERE a.strength > b.strength;

    v_reason := CASE
        WHEN v_gained IS NOT NULL THEN 'Warmer. You have learned something about ' || v_gained || '.'
        WHEN v_score < v_prev THEN 'Colder. Something you did has moved you away from the truth.'
        ELSE 'No change since yesterday.'
    END;

    RETURN jsonb_build_object('guided', true, 'score', v_score, 'prev_score', v_prev, 'max', 21,
                              'needle', v_needle, 'trend', v_score - v_prev, 'reason', v_reason);
END;
$$;

-- Everything the UI needs for one screen of the story.
CREATE FUNCTION story_scene(p_branch INT, p_actor INT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    pt playthrough;
    sc scenario;
    d story_day;
    v_tick INT;
    v_state JSONB;
    v_beats JSONB;
    v_done JSONB;
    v_ending JSONB;
BEGIN
    PERFORM story_actor_claim(p_actor);
    SELECT * INTO pt FROM playthrough WHERE branch_id = p_branch AND actor_id = p_actor;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    SELECT * INTO sc FROM scenario WHERE scenario_key = pt.scenario_key;
    v_tick := current_tick(p_branch);

    SELECT state INTO v_state
    FROM entity_state
    WHERE entity_id = p_actor AND branch_id = p_branch AND upper_inf(valid_ticks);
    v_state := COALESCE(v_state, '{}'::jsonb);

    SELECT * INTO d FROM story_day WHERE scenario_key = sc.scenario_key AND day = v_tick;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'beat_key', b.beat_key, 'title', b.title, 'body', b.body, 'phase', b.phase,
               'costs_action', b.costs_action,
               'picks_left', b.max_picks - (SELECT count(*) FROM event e
                                            WHERE e.branch_id = p_branch AND e.actor_id = p_actor
                                              AND e.action_type = 'story_choice' AND e.payload ->> 'beat' = b.beat_key),
               'options', (SELECT COALESCE(jsonb_agg(jsonb_build_object('key', o.option_key, 'label', o.label) ORDER BY o.ord), '[]'::jsonb)
                           FROM story_option o
                           WHERE o.beat_key = b.beat_key
                             AND NOT story_chose(p_branch, p_actor, b.beat_key || ':' || o.option_key))
           ) ORDER BY b.ord, b.beat_key), '[]'::jsonb)
    INTO v_beats
    FROM story_beat b
    WHERE b.scenario_key = sc.scenario_key
      AND story_beat_available(p_branch, p_actor, b.beat_key);

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'tick', e.tick, 'beat_key', b.beat_key, 'title', b.title, 'option_key', o.option_key,
               'label', o.label, 'result', o.result_text, 'costs_action', b.costs_action
           ) ORDER BY e.event_id), '[]'::jsonb)
    INTO v_done
    FROM event e
    JOIN story_beat b ON b.beat_key = e.payload ->> 'beat'
    JOIN story_option o ON o.beat_key = b.beat_key AND o.option_key = e.payload ->> 'option'
    WHERE e.branch_id = p_branch AND e.actor_id = p_actor AND e.action_type = 'story_choice';

    SELECT jsonb_build_object('key', se.ending_key, 'title', se.title, 'text', se.text)
    INTO v_ending
    FROM story_ending se
    WHERE se.scenario_key = sc.scenario_key
      AND COALESCE((v_state ->> se.flag)::numeric, 0) >= 1
    LIMIT 1;

    RETURN jsonb_build_object(
        'scenario', sc.scenario_key, 'title', sc.title, 'tagline', sc.tagline,
        'day', v_tick, 'day_title', d.title, 'intro', d.intro,
        'actions_left', GREATEST(0, 3 - story_actions_used(p_branch, p_actor, v_tick)),
        'meters', jsonb_build_object(
            'suspicion', COALESCE(v_state -> 'suspicion', '0'::jsonb),
            'danger', COALESCE(v_state -> 'danger', '0'::jsonb),
            'smoke', COALESCE(v_state -> 'smoke', '0'::jsonb),
            'coins', COALESCE(v_state -> 'coins', '0'::jsonb)),
        'trust', COALESCE((SELECT jsonb_object_agg(replace(key, 'trust_', ''), value)
                           FROM jsonb_each(v_state) WHERE key LIKE 'trust\_%'), '{}'::jsonb),
        'beats', v_beats, 'done', v_done, 'ending', v_ending,
        'slice_over', v_tick > sc.slice_end_day,
        'guided', pt.guided, 'trait', pt.trait, 'pronouns', pt.pronouns);
END;
$$;

-- Begin a story: fork a private village from the original world, then play the opening.
-- Each playthrough is its own branch, so players cannot affect each other, and Rewind still works.
CREATE FUNCTION start_playthrough(p_scenario TEXT, p_trait TEXT, p_guided BOOLEAN DEFAULT FALSE, p_pronouns TEXT DEFAULT 'they')
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    sc scenario;
    v_main INT;
    v_world BIGINT;
    v_branch INT;
    v_n INT;
    v_ev event;
BEGIN
    SELECT * INTO sc FROM scenario WHERE scenario_key = p_scenario;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown scenario';
    END IF;
    IF p_trait NOT IN ('kind', 'sharp', 'quiet') THEN
        RAISE EXCEPTION 'unknown trait';
    END IF;

    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT min(event_id) INTO v_world FROM event WHERE branch_id = v_main AND action_type = 'world_start';
    IF v_world IS NULL THEN
        RAISE EXCEPTION 'the world has not been seeded';
    END IF;

    SELECT count(*) INTO v_n FROM playthrough;
    v_branch := fork_branch(v_main, v_world, 'story: ' || sc.title || ' #' || (v_n + 1), 'replay');

    INSERT INTO playthrough (branch_id, scenario_key, actor_id, trait, guided, pronouns)
    VALUES (v_branch, p_scenario, sc.protagonist_id, p_trait, COALESCE(p_guided, FALSE), COALESCE(p_pronouns, 'they'));

    INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
    VALUES (v_branch, current_tick(v_branch), sc.protagonist_id, 'story_start',
            jsonb_build_object('scenario', p_scenario, 'trait', p_trait))
    RETURNING * INTO v_ev;
    PERFORM add_witnesses(v_ev.event_id, 'private');
    PERFORM process_event_rules(v_ev, 0);

    PERFORM advance_day(v_branch);   -- Day 1 begins

    RETURN jsonb_build_object('branch_id', v_branch, 'actor_id', sc.protagonist_id);
END;
$$;

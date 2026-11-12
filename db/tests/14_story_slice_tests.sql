-- Story slice (Who Burned the Mill? days 1-4) played through the real engine functions.
-- Applies the story seed itself, so run it on a freshly seeded database (scripts/run_tests.* does).
\set ON_ERROR_STOP on
\ir ../seed/_seed_story.sql

DO $$
DECLARE
    r JSONB; v_branch INT; v_actor INT; v_state JSONB; v_scene JSONB; v_board JSONB; v_comp JSONB;
    v_ev JSONB; v_n INT; v_threw BOOLEAN; v_main INT; v_choice BIGINT; v_branch2 INT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;

    -- ===== 1. Starting a playthrough forks a private village and plays the opening =====
    r := start_playthrough('mystery', 'kind', TRUE, 'they');
    v_branch := (r->>'branch_id')::int; v_actor := (r->>'actor_id')::int;
    IF v_actor <> 11 THEN RAISE EXCEPTION 'protagonist should be actor 11, got %', v_actor; END IF;
    IF current_tick(v_branch) <> 1 THEN RAISE EXCEPTION 'story should open on day 1, got %', current_tick(v_branch); END IF;
    IF NOT EXISTS (SELECT 1 FROM playthrough WHERE branch_id = v_branch AND trait = 'kind' AND guided) THEN
        RAISE EXCEPTION 'playthrough row missing';
    END IF;

    SELECT state INTO v_state FROM entity_state WHERE entity_id = 11 AND branch_id = v_branch AND upper_inf(valid_ticks);
    IF (v_state->>'coins')::numeric <> 6 OR (v_state->>'trust_wick')::numeric <> 40 OR (v_state->>'suspicion')::numeric <> 0 THEN
        RAISE EXCEPTION 'start state wrong (kind trait should add +10 trust): %', v_state;
    END IF;
    RAISE NOTICE 'PASS 1 playthrough starts on day 1 with the Kind bonus';

    -- ===== 2. New characters enter only inside the playthrough; the original world is untouched =====
    IF NOT EXISTS (SELECT 1 FROM entity_state WHERE entity_id = 31 AND branch_id = v_branch) THEN
        RAISE EXCEPTION 'the drover should have entered the village on day 1';
    END IF;
    IF EXISTS (SELECT 1 FROM entity_state WHERE entity_id = 31 AND branch_id = v_main) THEN
        RAISE EXCEPTION 'the drover must not exist in the original village';
    END IF;
    IF EXISTS (SELECT 1 FROM event WHERE branch_id = v_main AND action_type IN ('story_start', 'story_choice', 'story_event')) THEN
        RAISE EXCEPTION 'story events leaked into the original village';
    END IF;
    RAISE NOTICE 'PASS 2 story world is isolated from the main village';

    -- ===== 3. Fog of knowledge: the villain's private plan exists but the player never witnessed it =====
    IF NOT EXISTS (SELECT 1 FROM event WHERE branch_id = v_branch AND action_type = 'story_event' AND payload->>'kind' = 'wick_plan') THEN
        RAISE EXCEPTION 'wick_plan event should exist';
    END IF;
    IF EXISTS (SELECT 1 FROM event e JOIN event_witness w ON w.event_id = e.event_id
               WHERE e.branch_id = v_branch AND e.payload->>'kind' = 'wick_plan' AND w.actor_id = 11) THEN
        RAISE EXCEPTION 'the player must not witness the villain''s private plan';
    END IF;
    RAISE NOTICE 'PASS 3 hidden events stay hidden';

    -- ===== 4. The scene: five beats on day 1, three actions =====
    v_scene := story_scene(v_branch, 11);
    IF jsonb_array_length(v_scene->'beats') <> 5 OR (v_scene->>'actions_left')::int <> 3 THEN
        RAISE EXCEPTION 'day 1 should offer 5 scenes and 3 actions: %', v_scene->'beats';
    END IF;
    RAISE NOTICE 'PASS 4 day-1 scene offers 5 beats, 3 actions';

    -- ===== 5. A choice runs rules: meters, clues, and hidden consequences =====
    v_ev := story_choose(v_branch, 11, 'd1_well', 'share_loaf');
    v_choice := (v_ev->>'event_id')::bigint;
    SELECT state INTO v_state FROM entity_state WHERE entity_id = 11 AND branch_id = v_branch AND upper_inf(valid_ticks);
    IF (v_state->>'trust_wick')::numeric <> 50 OR (v_state->>'gave_loaf')::numeric <> 1 THEN
        RAISE EXCEPTION 'sharing the loaf should raise trust to 50 and set the flag: %', v_state;
    END IF;
    v_board := story_board(v_branch, 11);
    IF (SELECT (l->>'strength')::int FROM jsonb_array_elements(v_board->'links') l WHERE l->>'key' = 'mask') <> 1 THEN
        RAISE EXCEPTION 'C01 should give Mask strength 1: %', v_board;
    END IF;
    -- causal link: the discovery was caused by the choice (so Ask Why can walk it)
    IF NOT EXISTS (SELECT 1 FROM event_cause ec JOIN event d ON d.event_id = ec.effect_id
                   WHERE ec.cause_id = v_choice AND d.action_type = 'discover') THEN
        RAISE EXCEPTION 'the clue discovery should be causally linked to the choice';
    END IF;
    RAISE NOTICE 'PASS 5 a choice updates meters, finds a clue, and is causally linked';

    -- ===== 6. The villain plans for your cruelty: refuse Giles and Wick pays for the oil =====
    PERFORM story_choose(v_branch, 11, 'd1_giles', 'refuse');
    SELECT state INTO v_state FROM entity_state WHERE entity_id = 13 AND branch_id = v_branch AND upper_inf(valid_ticks);
    IF v_state->>'oil_source' <> 'wick' THEN RAISE EXCEPTION 'Giles should have got the oil from Wick: %', v_state; END IF;
    RAISE NOTICE 'PASS 6 the story adapts to refusal (Wick pays for the oil)';

    -- ===== 7. Three paid actions a day, and the budget also blocks village actions =====
    PERFORM story_choose(v_branch, 11, 'd1_packet', 'peek');
    v_threw := FALSE;
    BEGIN PERFORM story_choose(v_branch, 11, 'd1_inn', 'look_close');
    EXCEPTION WHEN OTHERS THEN v_threw := (SQLERRM = 'no actions left today'); END;
    IF NOT v_threw THEN RAISE EXCEPTION 'a 4th paid choice should be refused'; END IF;
    v_threw := FALSE;
    BEGIN PERFORM apply_action(v_branch, 11, 'steal', jsonb_build_object('place_id', 2, 'item_id', 1, 'qty', 1));
    EXCEPTION WHEN OTHERS THEN v_threw := (SQLERRM = 'no actions left today'); END;
    IF NOT v_threw THEN RAISE EXCEPTION 'story choices should count against the village action budget'; END IF;
    v_threw := FALSE;
    BEGIN PERFORM story_choose(v_branch, 11, 'd1_well', 'listen');
    EXCEPTION WHEN OTHERS THEN v_threw := TRUE; END;
    IF NOT v_threw THEN RAISE EXCEPTION 'the same scene cannot be played twice'; END IF;
    RAISE NOTICE 'PASS 7 action budget and one-shot scenes enforced';

    -- ===== 8. The Compass (Guided) =====
    v_comp := story_compass(v_branch, 11);
    IF NOT (v_comp->>'guided')::boolean OR v_comp->>'needle' <> 'Lost' OR (v_comp->>'score')::int <> 2 THEN
        RAISE EXCEPTION 'compass wrong (expected Lost, score 2 = mask 1 + means 1): %', v_comp;
    END IF;
    RAISE NOTICE 'PASS 8 the Compass reads Lost with score %', v_comp->>'score';

    -- ===== 9. Day 2: a public quarrel everyone witnessed; a private act only a child witnessed =====
    PERFORM advance_day(v_branch);
    SELECT state INTO v_state FROM entity_state WHERE entity_id = 11 AND branch_id = v_branch AND upper_inf(valid_ticks);
    IF (v_state->>'suspicion')::numeric <> 10 THEN RAISE EXCEPTION 'the quarrel should raise suspicion to 10: %', v_state; END IF;
    IF NOT EXISTS (SELECT 1 FROM event e JOIN event_witness w ON w.event_id = e.event_id
                   WHERE e.branch_id = v_branch AND e.payload->>'kind' = 'quarrel' AND w.actor_id = 11) THEN
        RAISE EXCEPTION 'the quarrel is public; the player should have witnessed it';
    END IF;
    IF EXISTS (SELECT 1 FROM event e JOIN event_witness w ON w.event_id = e.event_id
               WHERE e.branch_id = v_branch AND e.payload->>'kind' = 'pocket_key' AND w.actor_id = 11) THEN
        RAISE EXCEPTION 'the player must not have witnessed Wick pocketing the key';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM event e JOIN event_witness w ON w.event_id = e.event_id
                   WHERE e.branch_id = v_branch AND e.payload->>'kind' = 'pocket_key' AND w.actor_id = 10) THEN
        RAISE EXCEPTION 'Lily should have witnessed Wick pocketing the key';
    END IF;
    RAISE NOTICE 'PASS 9 public vs private witnesses (Lily saw the key taken, you did not)';

    -- ===== 10. Free scenes do not cost an action; trait changes consequences =====
    PERFORM story_choose(v_branch, 11, 'd2_quarrel', 'apologise');
    IF (story_scene(v_branch, 11)->>'actions_left')::int <> 3 THEN RAISE EXCEPTION 'the quarrel response should be free'; END IF;
    PERFORM story_choose(v_branch, 11, 'd2_night', 'watch_wellhouse');
    SELECT state INTO v_state FROM entity_state WHERE entity_id = 11 AND branch_id = v_branch AND upper_inf(valid_ticks);
    IF (v_state->>'danger')::numeric <> 15 THEN
        RAISE EXCEPTION 'danger should be 5 (peek) + 10 (not Quiet) = 15, got %', v_state->>'danger';
    END IF;
    RAISE NOTICE 'PASS 10 free scenes and trait-dependent danger';

    -- ===== 11. Day 3: scene dependencies (read the page later) =====
    PERFORM advance_day(v_branch);
    IF NOT EXISTS (SELECT 1 FROM event e WHERE e.branch_id = v_branch AND e.action_type = 'discover' AND e.payload->>'clue' = 'C25') THEN
        RAISE EXCEPTION 'Thorn''s public threat should be in the journal';
    END IF;
    PERFORM story_choose(v_branch, 11, 'd3_page', 'pocket');
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(story_scene(v_branch, 11)->'beats') b WHERE b->>'beat_key' = 'd3_read_later') THEN
        RAISE EXCEPTION 'pocketing the page should unlock reading it later';
    END IF;
    PERFORM story_choose(v_branch, 11, 'd3_read_later', 'read');
    PERFORM story_choose(v_branch, 11, 'd3_night', 'go_to_mill');
    SELECT state INTO v_state FROM entity_state WHERE entity_id = 11 AND branch_id = v_branch AND upper_inf(valid_ticks);
    IF (v_state->>'concussed')::numeric <> 1 OR (v_state->>'danger')::numeric <> 55 THEN
        RAISE EXCEPTION 'going to the mill should concuss you and raise danger to 55: %', v_state;
    END IF;
    RAISE NOTICE 'PASS 11 dependencies and the risky night-3 choice';

    -- ===== 12. Day 4: if you went to the mill you never see the fire; you wake in a ditch =====
    PERFORM advance_day(v_branch);
    v_scene := story_scene(v_branch, 11);
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_scene->'beats') b WHERE b->>'beat_key' = 'd4_fire') THEN
        RAISE EXCEPTION 'the fire scene must be unavailable if you were knocked out';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_scene->'beats') b WHERE b->>'beat_key' = 'd4_wake') THEN
        RAISE EXCEPTION 'the wake-in-a-ditch scene should be offered';
    END IF;
    RAISE NOTICE 'PASS 12 branching on a risky choice';

    -- ===== 13. Hash chain still intact after all of it =====
    SELECT count(*) INTO v_n FROM verify_event_chain(v_branch);
    IF v_n <> 0 THEN RAISE EXCEPTION 'hash chain broken (% problems)', v_n; END IF;
    RAISE NOTICE 'PASS 13 hash chain verifies';

    -- ===== 14. A second playthrough: the fire can kill you =====
    r := start_playthrough('mystery', 'quiet', FALSE, 'she');
    v_branch2 := (r->>'branch_id')::int;
    IF (story_compass(v_branch2, 11)->>'guided')::boolean THEN RAISE EXCEPTION 'Bold mode must not expose the compass'; END IF;
    IF (SELECT (state->>'stealth')::numeric FROM entity_state WHERE entity_id = 11 AND branch_id = v_branch2 AND upper_inf(valid_ticks)) <> 1 THEN
        RAISE EXCEPTION 'Quiet trait should set stealth 1';
    END IF;
    PERFORM advance_day(v_branch2); PERFORM advance_day(v_branch2); PERFORM advance_day(v_branch2);   -- days 2, 3, 4
    IF current_tick(v_branch2) <> 4 THEN RAISE EXCEPTION 'expected day 4'; END IF;
    PERFORM story_choose(v_branch2, 11, 'd4_fire', 'office');
    PERFORM story_choose(v_branch2, 11, 'd4_fire', 'body');
    IF story_scene(v_branch2, 11)->'ending' <> 'null'::jsonb THEN RAISE EXCEPTION 'two moves (smoke 5) should still be survivable'; END IF;
    PERFORM story_choose(v_branch2, 11, 'd4_fire', 'grain');
    v_scene := story_scene(v_branch2, 11);
    IF v_scene->'ending'->>'key' <> 'smoke' THEN RAISE EXCEPTION 'smoke 6 should end the story: %', v_scene->'ending'; END IF;
    v_threw := FALSE;
    BEGIN PERFORM story_choose(v_branch2, 11, 'd4_ruins', 'cellar');
    EXCEPTION WHEN OTHERS THEN v_threw := (SQLERRM = 'your story has ended'); END;
    IF NOT v_threw THEN RAISE EXCEPTION 'a dead protagonist cannot keep acting'; END IF;
    RAISE NOTICE 'PASS 14 the fire can kill you, and Bold mode shows no compass';

    -- ===== 15. Two playthroughs are independent worlds =====
    IF (SELECT count(*) FROM event WHERE branch_id = v_branch2 AND action_type = 'story_choice' AND payload->>'beat' = 'd1_well') <> 0 THEN
        RAISE EXCEPTION 'playthroughs must not share choices';
    END IF;
    RAISE NOTICE 'PASS 15 playthroughs are isolated';
END $$;

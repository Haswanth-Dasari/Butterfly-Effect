-- Wick's nightly agenda (days 5-8): who he acts on depends on what the PLAYER did and whom they protected.
-- The decision is one SQL function (wick_pick_target); what each outcome DOES is rules (data).
\set ON_ERROR_STOP on
\ir ../seed/_seed_story.sql

CREATE FUNCTION pg_temp.ff(p_branch INT, p_days INT) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN FOR i IN 1..p_days LOOP PERFORM advance_day(p_branch); END LOOP; END $$;
CREATE FUNCTION pg_temp.st(p_branch INT, p_actor INT DEFAULT 11) RETURNS JSONB LANGUAGE sql AS $$
    SELECT state FROM entity_state WHERE entity_id = p_actor AND branch_id = p_branch AND upper_inf(valid_ticks) $$;
CREATE FUNCTION pg_temp.victim(p_branch INT) RETURNS INT LANGUAGE sql AS $$
    SELECT (payload ->> 'victim')::int FROM event WHERE branch_id = p_branch AND action_type = 'story_event' AND payload ->> 'kind' = 'wick_night' $$;
CREATE FUNCTION pg_temp.avail(p_branch INT, p_beat TEXT) RETURNS BOOLEAN LANGUAGE sql AS $$
    SELECT story_beat_available(p_branch, 11, p_beat) $$;
CREATE FUNCTION pg_temp.new_story(p_trait TEXT DEFAULT 'kind') RETURNS INT LANGUAGE sql AS $$
    SELECT (start_playthrough('mystery', p_trait, FALSE, 'they') ->> 'branch_id')::int $$;

DO $$
DECLARE
    b INT; v_n INT; v_threw BOOLEAN; v_before NUMERIC;
BEGIN
    -- ===== 1. Day 5: the Sergeant arrives (characters enter, your key is produced) =====
    b := pg_temp.new_story();
    PERFORM pg_temp.ff(b, 4);
    IF current_tick(b) <> 5 THEN RAISE EXCEPTION 'expected day 5, got %', current_tick(b); END IF;
    IF NOT EXISTS (SELECT 1 FROM entity_state WHERE entity_id = 32 AND branch_id = b) OR NOT EXISTS (SELECT 1 FROM entity_state WHERE entity_id = 33 AND branch_id = b) THEN
        RAISE EXCEPTION 'Pike and Corwen should have entered the village on day 5';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(story_board(b, 11)->'clues') c WHERE c->>'key' = 'C12') THEN
        RAISE EXCEPTION 'your key in the ashes should be in the journal';
    END IF;
    IF (pg_temp.st(b)->>'suspicion')::numeric <> 25 THEN RAISE EXCEPTION 'suspicion should be 25 (quarrel 10 + key 15): %', pg_temp.st(b)->>'suspicion'; END IF;
    RAISE NOTICE 'PASS 1 day 5: Pike arrives and produces your key';

    -- ===== 2. Default night 7 (no contact, no protection): Ines is the most exposed witness =====
    PERFORM pg_temp.ff(b, 3);
    IF current_tick(b) <> 8 THEN RAISE EXCEPTION 'expected day 8'; END IF;
    IF pg_temp.victim(b) <> 8 THEN RAISE EXCEPTION 'Ines (actor 8) should be the default victim, got %', pg_temp.victim(b); END IF;
    IF (pg_temp.st(b, 8)->>'dead')::numeric <> 1 THEN RAISE EXCEPTION 'Ines should be dead'; END IF;
    IF (pg_temp.st(b)->>'suspicion')::numeric <> 10 THEN RAISE EXCEPTION 'the false confession should drop suspicion to 10'; END IF;
    IF NOT EXISTS (SELECT 1 FROM event e JOIN event_witness w ON w.event_id = e.event_id
                   WHERE e.branch_id = b AND e.payload ->> 'kind' = 'confession' AND w.actor_id = 11) THEN
        RAISE EXCEPTION 'the confession is public; the player should have witnessed it';
    END IF;
    IF EXISTS (SELECT 1 FROM event e JOIN event_witness w ON w.event_id = e.event_id
               WHERE e.branch_id = b AND e.payload ->> 'kind' = 'wick_night' AND w.actor_id = 11) THEN
        RAISE EXCEPTION 'the player must NOT witness the villain''s decision';
    END IF;
    IF NOT story_chose(b, 11, '_night7:ines') OR NOT pg_temp.avail(b, 'd8_scene_ines') OR pg_temp.avail(b, 'd8_scene_giles') OR pg_temp.avail(b, 'd8_letter') THEN
        RAISE EXCEPTION 'day 8 scenes should match the outcome (Ines)';
    END IF;
    IF (story_scene(b, 11)->>'actions_left')::int <> 3 THEN RAISE EXCEPTION 'no grief expected (trust in Ines is under 40)'; END IF;
    RAISE NOTICE 'PASS 2 night 7 default: Ines dies, a forged confession closes the case';

    -- ===== 3. The decision is causally linked (so the Reckoning can show it) =====
    IF NOT EXISTS (SELECT 1 FROM event_cause ec JOIN event w ON w.event_id = ec.cause_id AND w.payload ->> 'kind' = 'wick_night'
                   JOIN event c ON c.event_id = ec.effect_id AND c.payload ->> 'kind' = 'confession' WHERE w.branch_id = b) THEN
        RAISE EXCEPTION 'the confession should be caused by the hidden decision';
    END IF;
    RAISE NOTICE 'PASS 3 the confession is causally linked to the villain''s hidden decision';

    -- ===== 4. Finding Giles raises his threat above Ines: he becomes the victim =====
    b := pg_temp.new_story();
    PERFORM pg_temp.ff(b, 5);
    PERFORM story_choose(b, 11, 'd6_giles', 'gentle');
    PERFORM pg_temp.ff(b, 2);
    IF pg_temp.victim(b) <> 13 THEN RAISE EXCEPTION 'Giles should be the victim after you found him, got %', pg_temp.victim(b); END IF;
    IF (pg_temp.st(b)->>'trust_bethan')::numeric <> 10 THEN RAISE EXCEPTION 'Bethan''s trust should collapse (50-40=10): %', pg_temp.st(b)->>'trust_bethan'; END IF;
    IF (story_scene(b, 11)->>'actions_left')::int <> 2 THEN RAISE EXCEPTION 'grief should cost an action'; END IF;
    RAISE NOTICE 'PASS 4 finding Giles puts him on Wick''s list; grief costs an action';

    -- ===== 5. Protecting Giles redirects Wick to Ines =====
    b := pg_temp.new_story();
    PERFORM pg_temp.ff(b, 5);
    PERFORM story_choose(b, 11, 'd6_giles', 'gentle');
    PERFORM pg_temp.ff(b, 1);
    PERFORM story_choose(b, 11, 'd7_protect_giles', 'watch');
    PERFORM pg_temp.ff(b, 1);
    IF pg_temp.victim(b) <> 8 THEN RAISE EXCEPTION 'with Giles protected, Ines should be next, got %', pg_temp.victim(b); END IF;
    IF (pg_temp.st(b, 13)->>'dead') IS NOT NULL THEN RAISE EXCEPTION 'Giles must survive when protected'; END IF;
    RAISE NOTICE 'PASS 5 protection saves Giles; the cost is someone else';

    -- ===== 6. Protecting everyone worth killing: he turns on YOU instead =====
    b := pg_temp.new_story();
    PERFORM pg_temp.ff(b, 5);
    PERFORM story_choose(b, 11, 'd6_giles', 'gentle');
    PERFORM pg_temp.ff(b, 1);
    PERFORM story_choose(b, 11, 'd7_protect_giles', 'watch');
    PERFORM story_choose(b, 11, 'd7_protect_ines', 'watch');
    v_before := (pg_temp.st(b)->>'suspicion')::numeric;
    PERFORM pg_temp.ff(b, 1);
    IF pg_temp.victim(b) <> 0 THEN RAISE EXCEPTION 'nobody unprotected should be worth killing: victim %', pg_temp.victim(b); END IF;
    IF (pg_temp.st(b)->>'suspicion')::numeric <> v_before + 25 THEN RAISE EXCEPTION 'a planted statement should raise suspicion by 25'; END IF;
    IF NOT pg_temp.avail(b, 'd8_letter') OR pg_temp.avail(b, 'd8_purse') THEN RAISE EXCEPTION 'the letter scene replaces the purse'; END IF;
    RAISE NOTICE 'PASS 6 everyone protected: Wick frames you instead';

    -- ===== 7. Pressing Maren makes her the top target (and the actions are scarce) =====
    b := pg_temp.new_story();
    PERFORM pg_temp.ff(b, 5);
    PERFORM story_choose(b, 11, 'd6_giles', 'gentle');
    PERFORM pg_temp.ff(b, 1);
    PERFORM story_choose(b, 11, 'd7_maren', 'press');
    PERFORM story_choose(b, 11, 'd7_protect_giles', 'watch');
    PERFORM story_choose(b, 11, 'd7_protect_ines', 'watch');
    v_threw := FALSE;
    BEGIN PERFORM story_choose(b, 11, 'd7_protect_maren', 'watch');
    EXCEPTION WHEN OTHERS THEN v_threw := (SQLERRM = 'no actions left today'); END;
    IF NOT v_threw THEN RAISE EXCEPTION 'a 4th action should be refused: you cannot protect everyone'; END IF;
    PERFORM pg_temp.ff(b, 1);
    IF pg_temp.victim(b) <> 2 THEN RAISE EXCEPTION 'pressed and unprotected, Maren should die: victim %', pg_temp.victim(b); END IF;
    RAISE NOTICE 'PASS 7 pressing Maren without protecting her gets her killed';

    -- ===== 8. Custody protects Giles but costs trust; the protect beat is hidden =====
    b := pg_temp.new_story();
    PERFORM pg_temp.ff(b, 5);
    PERFORM story_choose(b, 11, 'd6_giles', 'pike');
    PERFORM pg_temp.ff(b, 1);
    IF pg_temp.avail(b, 'd7_protect_giles') THEN RAISE EXCEPTION 'a boy in custody needs no watching'; END IF;
    PERFORM pg_temp.ff(b, 1);
    IF pg_temp.victim(b) <> 8 THEN RAISE EXCEPTION 'Giles is in custody, so Ines is next: %', pg_temp.victim(b); END IF;
    RAISE NOTICE 'PASS 8 handing Giles to Pike protects him (and costs his trust)';

    -- ===== 9. The false peace is a real ending: take the purse and the story is over =====
    b := pg_temp.new_story();
    PERFORM pg_temp.ff(b, 7);
    PERFORM story_choose(b, 11, 'd8_purse', 'take');
    IF story_scene(b, 11)->'ending'->>'key' <> 'convenient_peace' THEN RAISE EXCEPTION 'taking the purse should end the story'; END IF;
    v_threw := FALSE;
    BEGIN PERFORM story_choose(b, 11, 'd8_pike_closes', 'accept');
    EXCEPTION WHEN OTHERS THEN v_threw := (SQLERRM = 'your story has ended'); END;
    IF NOT v_threw THEN RAISE EXCEPTION 'nothing can be chosen after an ending'; END IF;
    RAISE NOTICE 'PASS 9 Convenient Peace ends the story';

    -- ===== 10. The whole chain is still tamper-evident =====
    SELECT count(*) INTO v_n FROM verify_event_chain(b);
    IF v_n <> 0 THEN RAISE EXCEPTION 'hash chain broken (% problems)', v_n; END IF;
    RAISE NOTICE 'PASS 10 hash chain verifies after the nights';
END $$;

-- Story privileges. Writes run with the owner's rights (like apply_action); players get read access to
-- the story catalogue and execute rights on the story functions only.
ALTER FUNCTION story_choose(INT, INT, TEXT, TEXT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION start_playthrough(TEXT, TEXT, BOOLEAN, TEXT) SECURITY DEFINER SET search_path = public, pg_temp;
-- Readers must also see all of the player's own events, not only RLS-visible ones, to compute meters and strength.
ALTER FUNCTION story_scene(INT, INT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION story_board(INT, INT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION story_compass(INT, INT) SECURITY DEFINER SET search_path = public, pg_temp;

GRANT SELECT ON scenario, case_link, clue, clue_link, story_day, story_beat, story_option, story_ending, playthrough
    TO game_master_role, auditor_role;

GRANT EXECUTE ON FUNCTION
    story_choose, story_scene, story_board, story_compass, story_beat_available, story_chose,
    story_actions_used, story_link_strength, story_progress, story_actor_claim, current_tick
TO player_role;

GRANT EXECUTE ON FUNCTION start_playthrough TO game_master_role;
GRANT EXECUTE ON FUNCTION
    story_choose, story_scene, story_board, story_compass, story_beat_available, story_chose,
    story_actions_used, story_link_strength, story_progress, story_actor_claim
TO game_master_role, auditor_role;

-- The API lets a player switch the Compass on or off; that is the only column it may change.
GRANT UPDATE (guided) ON playthrough TO game_master_role;

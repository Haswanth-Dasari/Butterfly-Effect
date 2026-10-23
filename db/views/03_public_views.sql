-- Owned by the table owner, so it deliberately bypasses RLS to show only the public mood faces, never coins or trust.
CREATE VIEW v_village_mood AS
SELECT
    s.branch_id,
    s.entity_id AS actor_id,
    a.name AS actor_name,
    s.state ->> 'mood' AS mood
FROM entity_state s
JOIN actor a ON a.actor_id = s.entity_id
WHERE upper_inf(s.valid_ticks);

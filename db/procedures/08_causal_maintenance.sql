-- Maintained causal structures for fast provenance and path lookups.

-- Trigger function to maintain causal_closure and causal_path on event_cause inserts.
-- Closure insert: every ancestor of the cause x every descendant of the effect is connected,
-- setting the depth to the minimum (LEAST) of existing depth and new path depth.
-- Path rule: first-cause-wins via ON CONFLICT (event_id) DO NOTHING, keeping the primary causal chain.
CREATE OR REPLACE FUNCTION causal_maintain()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    c BIGINT := NEW.cause_id;
    e BIGINT := NEW.effect_id;
BEGIN
    -- 1. Ensure self-closure rows (depth 0) exist for both cause and effect
    INSERT INTO causal_closure (ancestor_id, descendant_id, depth)
    VALUES (c, c, 0), (e, e, 0)
    ON CONFLICT DO NOTHING;

    -- 2. Transitive closure insert:
    -- Every ancestor of cause 'c' is connected to every descendant of effect 'e'.
    -- The new path length is a.depth + 1 + d.depth. If a path already exists, keep the shortest.
    INSERT INTO causal_closure (ancestor_id, descendant_id, depth)
    SELECT a.ancestor_id, d.descendant_id, a.depth + 1 + d.depth
    FROM causal_closure a
    CROSS JOIN causal_closure d
    WHERE a.descendant_id = c AND d.ancestor_id = e
    ON CONFLICT (ancestor_id, descendant_id)
    DO UPDATE SET depth = LEAST(causal_closure.depth, EXCLUDED.depth);

    -- 3. Ensure base path exists for cause
    INSERT INTO causal_path (event_id, path)
    VALUES (c, c::text)
    ON CONFLICT DO NOTHING;

    -- 4. Materialize path for effect from cause's path:
    -- First cause wins (ON CONFLICT (event_id) DO NOTHING)
    INSERT INTO causal_path (event_id, path)
    SELECT e, p.path || '/' || e
    FROM causal_path p
    WHERE p.event_id = c
    ON CONFLICT (event_id) DO NOTHING;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS event_cause_derived ON event_cause;
CREATE TRIGGER event_cause_derived
AFTER INSERT ON event_cause
FOR EACH ROW
EXECUTE FUNCTION causal_maintain();

-- Rebuild causal structures from event_cause from scratch.
CREATE OR REPLACE FUNCTION rebuild_causal_structures()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE causal_closure, causal_path;

    -- Rebuild causal_closure:
    -- Base: self rows (depth 0) for all events appearing as cause or effect, plus direct edges (depth 1).
    -- Recursive step: join on descendant = next cause.
    -- Aggregate: MIN(depth) per (ancestor_id, descendant_id).
    WITH RECURSIVE tc AS (
        SELECT id AS ancestor_id, id AS descendant_id, 0 AS depth
        FROM (
            SELECT cause_id AS id FROM event_cause
            UNION
            SELECT effect_id AS id FROM event_cause
        ) s
        UNION ALL
        SELECT cause_id, effect_id, 1 FROM event_cause
        UNION ALL
        SELECT c.ancestor_id, ec.effect_id, c.depth + 1
        FROM tc c
        JOIN event_cause ec ON c.descendant_id = ec.cause_id
        WHERE c.depth > 0
    )
    INSERT INTO causal_closure (ancestor_id, descendant_id, depth)
    SELECT ancestor_id, descendant_id, MIN(depth)
    FROM tc
    GROUP BY ancestor_id, descendant_id;

    -- Rebuild causal_path:
    -- Base: root events (events that appear as a cause but never as an effect), path = event_id::text.
    -- Each child event takes as its primary parent the LOWEST cause_id among its causes.
    -- (Comment: only single-cause events are guaranteed to match what the trigger produced.)
    WITH RECURSIVE
    primary_edge AS (
        SELECT effect_id, MIN(cause_id) AS cause_id
        FROM event_cause
        GROUP BY effect_id
    ),
    paths AS (
        SELECT DISTINCT cause_id AS event_id, cause_id::text AS path
        FROM event_cause
        WHERE cause_id NOT IN (SELECT effect_id FROM event_cause)
        UNION ALL
        SELECT pe.effect_id, p.path || '/' || pe.effect_id
        FROM paths p
        JOIN primary_edge pe ON pe.cause_id = p.event_id
    )
    INSERT INTO causal_path (event_id, path)
    SELECT event_id, path FROM paths;
END;
$$;

-- Verify consistency of causal_closure and causal_path against recomputed recursive logic.
-- Events with 2+ causes are ignored for paths.
-- Returns zero rows when everything is consistent.
CREATE OR REPLACE FUNCTION verify_causal_structures()
RETURNS TABLE (kind TEXT, detail TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE expected_closure AS (
        SELECT id AS ancestor_id, id AS descendant_id, 0 AS depth
        FROM (
            SELECT cause_id AS id FROM event_cause
            UNION
            SELECT effect_id AS id FROM event_cause
        ) s
        UNION ALL
        SELECT cause_id, effect_id, 1 FROM event_cause
        UNION ALL
        SELECT c.ancestor_id, ec.effect_id, c.depth + 1
        FROM expected_closure c
        JOIN event_cause ec ON c.descendant_id = ec.cause_id
        WHERE c.depth > 0
    ),
    min_closure AS (
        SELECT ancestor_id, descendant_id, MIN(depth) AS depth
        FROM expected_closure
        GROUP BY ancestor_id, descendant_id
    )
    SELECT 'closure missing or wrong'::TEXT AS kind,
           format('ancestor=%s descendant=%s expected_depth=%s actual_depth=%s',
                  e.ancestor_id, e.descendant_id, e.depth, a.depth) AS detail
    FROM min_closure e
    LEFT JOIN causal_closure a ON e.ancestor_id = a.ancestor_id AND e.descendant_id = a.descendant_id
    WHERE a.depth IS NULL OR a.depth <> e.depth

    UNION ALL

    SELECT 'closure extra'::TEXT AS kind,
           format('ancestor=%s descendant=%s depth=%s',
                  a.ancestor_id, a.descendant_id, a.depth) AS detail
    FROM causal_closure a
    LEFT JOIN min_closure e ON a.ancestor_id = e.ancestor_id AND a.descendant_id = e.descendant_id
    WHERE e.ancestor_id IS NULL

    UNION ALL

    SELECT 'path wrong'::TEXT AS kind,
           format('event=%s expected=%s actual=%s',
                  sp.effect_id, parent_p.path || '/' || sp.effect_id, act.path) AS detail
    FROM (
        SELECT effect_id, MIN(cause_id) AS parent_id
        FROM event_cause
        GROUP BY effect_id
        HAVING COUNT(*) = 1
    ) sp
    LEFT JOIN causal_path parent_p ON parent_p.event_id = sp.parent_id
    LEFT JOIN causal_path act ON act.event_id = sp.effect_id
    WHERE act.path IS NULL OR act.path <> (parent_p.path || '/' || sp.effect_id);
END;
$$;

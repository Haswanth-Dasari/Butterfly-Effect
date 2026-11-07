-- The Ask Why provenance layer (Chronicle API, butterfly score, and causal traversals).
-- All functions are LANGUAGE sql, STABLE to avoid PL/pgSQL variable/column name conflicts.

-- 1. Recursive CTE walking event_cause upward from p_event.
CREATE OR REPLACE FUNCTION why_ids_cte(p_event BIGINT)
RETURNS TABLE (event_id BIGINT, depth INT)
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE up AS (
        SELECT ec.cause_id AS event_id, 1 AS depth
        FROM event_cause ec
        WHERE ec.effect_id = p_event
        UNION ALL
        SELECT ec.cause_id, up.depth + 1
        FROM up
        JOIN event_cause ec ON ec.effect_id = up.event_id
    )
    SELECT up.event_id, MIN(up.depth)::INT AS depth
    FROM up
    GROUP BY up.event_id
    ORDER BY depth, up.event_id;
$$;

-- 2. Transitive closure lookup of all ancestors with depth > 0.
CREATE OR REPLACE FUNCTION why_ids_closure(p_event BIGINT)
RETURNS TABLE (event_id BIGINT, depth INT)
LANGUAGE sql
STABLE
AS $$
    SELECT ancestor_id AS event_id, depth
    FROM causal_closure
    WHERE descendant_id = p_event AND depth > 0
    ORDER BY depth, ancestor_id;
$$;

-- 3. Materialized path lookup split on '/' with ordinality.
-- (Comment: follows the primary chain only.)
CREATE OR REPLACE FUNCTION why_ids_path(p_event BIGINT)
RETURNS TABLE (event_id BIGINT, depth INT)
LANGUAGE sql
STABLE
AS $$
    WITH elements AS (
        SELECT t.elem::BIGINT AS elem_id,
               t.ord::INT AS ord,
               count(*) OVER ()::INT AS total
        FROM causal_path cp,
             unnest(string_to_array(cp.path, '/')) WITH ORDINALITY AS t(elem, ord)
        WHERE cp.event_id = p_event
    )
    SELECT elem_id AS event_id, (total - ord)::INT AS depth
    FROM elements
    WHERE ord < total
    ORDER BY depth, event_id;
$$;

-- 4. The Chronicle: ask_why returns the full provenance story leading to p_event.
-- Target row (depth 0) has NULL rule_id and narrative. Root cause is step 1.
CREATE OR REPLACE FUNCTION ask_why(p_event BIGINT)
RETURNS TABLE (
    step INT,
    depth INT,
    event_id BIGINT,
    tick INT,
    action_type TEXT,
    actor_name TEXT,
    rule_id INT,
    narrative TEXT
)
LANGUAGE sql
STABLE
AS $$
    WITH anc AS (
        SELECT w.event_id, w.depth
        FROM why_ids_closure(p_event) w
        UNION ALL
        SELECT p_event AS event_id, 0 AS depth
    )
    SELECT
        (row_number() OVER (ORDER BY a.depth DESC, a.event_id))::INT AS step,
        a.depth::INT,
        a.event_id,
        e.tick,
        e.action_type,
        act.name AS actor_name,
        CASE WHEN a.depth > 0 THEN r_edge.rule_id ELSE NULL END AS rule_id,
        CASE WHEN a.depth > 0 THEN r.narrative_template ELSE NULL END AS narrative
    FROM anc a
    JOIN event e ON e.event_id = a.event_id
    LEFT JOIN actor act ON act.actor_id = e.actor_id
    LEFT JOIN LATERAL (
        SELECT ec.rule_id
        FROM event_cause ec
        JOIN anc child ON child.event_id = ec.effect_id AND child.depth = a.depth - 1
        WHERE a.depth > 0
          AND ec.cause_id = a.event_id
        ORDER BY ec.rule_id ASC NULLS LAST
        LIMIT 1
    ) r_edge ON a.depth > 0
    LEFT JOIN rule r ON r.rule_id = r_edge.rule_id
    ORDER BY a.depth DESC, a.event_id;
$$;

-- 5. Butterfly score: count of causal_closure rows with ancestor_id = p_event AND depth > 0
-- whose descendant event has the same branch_id as the ancestor event.
CREATE OR REPLACE FUNCTION butterfly_score(p_event BIGINT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT count(*)::INT
    FROM causal_closure cc
    JOIN event ea ON ea.event_id = cc.ancestor_id
    JOIN event ed ON ed.event_id = cc.descendant_id
    WHERE cc.ancestor_id = p_event
      AND cc.depth > 0
      AND ed.branch_id = ea.branch_id;
$$;

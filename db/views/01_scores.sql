-- Player action scores and butterfly metrics.

CREATE OR REPLACE VIEW v_action_scores AS
WITH action_counts AS (
    SELECT
        e.event_id,
        e.branch_id,
        e.tick,
        e.actor_id,
        a.name AS actor_name,
        e.action_type,
        COALESCE(cc.descendant_count, 0)::INT AS score
    FROM event e
    JOIN actor a ON a.actor_id = e.actor_id
    LEFT JOIN (
        SELECT cc.ancestor_id, count(*)::INT AS descendant_count
        FROM causal_closure cc
        JOIN event ea ON ea.event_id = cc.ancestor_id
        JOIN event ed ON ed.event_id = cc.descendant_id
        WHERE cc.depth > 0
          AND ed.branch_id = ea.branch_id
        GROUP BY cc.ancestor_id
    ) cc ON cc.ancestor_id = e.event_id
    WHERE e.action_type IN (
        'gift', 'trade', 'steal', 'rumor', 'build',
        'hire', 'set_price', 'help_harvest', 'sabotage', 'feast'
    )
      AND e.actor_id IS NOT NULL
)
SELECT
    event_id,
    branch_id,
    tick,
    actor_id,
    actor_name,
    action_type,
    score,
    RANK() OVER (PARTITION BY branch_id ORDER BY score DESC)::INT AS score_rank
FROM action_counts;

CREATE OR REPLACE VIEW v_player_butterfly AS
SELECT
    branch_id,
    actor_id,
    actor_name,
    count(*)::INT AS actions,
    sum(score)::INT AS total_score,
    max(score)::INT AS best_score,
    RANK() OVER (PARTITION BY branch_id ORDER BY sum(score) DESC)::INT AS player_rank
FROM v_action_scores
GROUP BY branch_id, actor_id, actor_name;

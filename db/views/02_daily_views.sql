-- Daily materialized views and refresh function.

CREATE MATERIALIZED VIEW mv_evening_bell AS
WITH per_event AS (
    SELECT
        e.branch_id,
        e.tick,
        e.event_id,
        CASE
            WHEN e.action_type IN (
                'gift', 'trade', 'steal', 'rumor', 'build',
                'hire', 'set_price', 'help_harvest', 'sabotage', 'feast'
            ) AND e.actor_id IS NOT NULL THEN 1
            ELSE 0
        END AS is_player_action,
        CASE
            WHEN EXISTS (SELECT 1 FROM event_cause ec WHERE ec.effect_id = e.event_id) THEN 1
            ELSE 0
        END AS is_cascade,
        COALESCE(cc.score, 0) AS score
    FROM event e
    LEFT JOIN (
        SELECT cc.ancestor_id, count(*)::INT AS score
        FROM causal_closure cc
        JOIN event ea ON ea.event_id = cc.ancestor_id
        JOIN event ed ON ed.event_id = cc.descendant_id
        WHERE cc.depth > 0
          AND ed.branch_id = ea.branch_id
        GROUP BY cc.ancestor_id
    ) cc ON cc.ancestor_id = e.event_id
),
per_tick AS (
    SELECT
        branch_id,
        tick,
        count(*)::INT AS events_total,
        sum(is_player_action)::INT AS player_actions,
        sum(is_cascade)::INT AS cascade_events,
        COALESCE(max(score) FILTER (WHERE is_player_action = 1), 0)::INT AS top_score
    FROM per_event
    GROUP BY branch_id, tick
)
SELECT
    branch_id,
    tick,
    events_total,
    player_actions,
    cascade_events,
    top_score,
    sum(events_total) OVER (PARTITION BY branch_id ORDER BY tick)::INT AS events_cumulative
FROM per_tick
WITH DATA;

CREATE UNIQUE INDEX mv_evening_bell_pk ON mv_evening_bell (branch_id, tick);

CREATE MATERIALIZED VIEW mv_leaderboard AS
SELECT
    branch_id,
    actor_id,
    actor_name,
    count(*)::INT AS actions,
    sum(score)::INT AS total_score,
    max(score)::INT AS best_score,
    RANK() OVER (PARTITION BY branch_id ORDER BY sum(score)::INT DESC)::INT AS leaderboard_rank
FROM v_action_scores
GROUP BY branch_id, actor_id, actor_name
WITH DATA;

CREATE UNIQUE INDEX mv_leaderboard_pk ON mv_leaderboard (branch_id, actor_id);

-- Called by the application right after advance_day(); CONCURRENTLY is an option later.
CREATE OR REPLACE FUNCTION refresh_daily_views()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_evening_bell;
    REFRESH MATERIALIZED VIEW mv_leaderboard;
END;
$$;

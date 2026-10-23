-- Security privileges: write hardening, deny-by-default execution, and least-privilege role grants.

-- 1. Harden the write entry points: these run with the owner's rights so no role needs write privileges on tables.
ALTER FUNCTION apply_action(INT, INT, TEXT, JSONB, TEXT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION join_village(INT, TEXT, INT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION advance_day(INT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION fork_branch(INT, BIGINT, TEXT, TEXT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION create_snapshot(INT) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION refresh_daily_views() SECURITY DEFINER SET search_path = public, pg_temp;

-- 2. Revoke table and sequence permissions from PUBLIC.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;

-- 3. Deny functions by default: a DO block that loops over every function in schema public that does NOT belong to an extension and revokes execute from PUBLIC.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS proc_name
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_proc'::regclass
                AND d.objid = p.oid
                AND d.deptype = 'e'
          )
    LOOP
        EXECUTE 'REVOKE ALL ON FUNCTION ' || r.proc_name || ' FROM PUBLIC';
    END LOOP;
END;
$$;

-- 4. Staff read access: grant select on all tables, views, and materialized views to game master and auditor.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO game_master_role, auditor_role;

-- 5. Player read access: specific public world tables, views, materialized views, and public columns of rule.
GRANT SELECT ON
    place,
    home,
    actor,
    item,
    action_type,
    stock,
    branch,
    event,
    event_witness,
    entity_state,
    event_cause,
    causal_closure,
    v_village_mood,
    mv_evening_bell,
    mv_leaderboard
TO player_role;

GRANT SELECT (rule_id, narrative_template) ON rule TO player_role;

-- 6. Function execution rights (name only, all overloads are single).
-- Player role execution rights
GRANT EXECUTE ON FUNCTION
    apply_action,
    ask_why,
    why_ids_cte,
    why_ids_closure,
    why_ids_path,
    butterfly_score,
    current_tick
TO player_role;

-- Game master role execution rights
GRANT EXECUTE ON FUNCTION
    apply_action,
    join_village,
    advance_day,
    fork_branch,
    create_snapshot,
    refresh_daily_views,
    current_tick,
    ask_why,
    why_ids_cte,
    why_ids_closure,
    why_ids_path,
    butterfly_score,
    entity_state_at,
    branch_diff,
    branch_state_digest,
    branch_projection_digest,
    serialize_branch_state,
    verify_event_chain,
    verify_causal_structures,
    event_hash
TO game_master_role;

-- Auditor role execution rights
GRANT EXECUTE ON FUNCTION
    current_tick,
    ask_why,
    why_ids_cte,
    why_ids_closure,
    why_ids_path,
    butterfly_score,
    entity_state_at,
    branch_diff,
    branch_state_digest,
    branch_projection_digest,
    serialize_branch_state,
    verify_event_chain,
    verify_causal_structures,
    event_hash
TO auditor_role;

-- Note: rebuild_projections, rebuild_all_projections, and rebuild_world are owner-only on purpose (no grants).


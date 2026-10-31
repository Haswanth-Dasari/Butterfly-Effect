-- Login roles for the backend (separate from the three NOLOGIN group roles
-- created in 01_roles.sql). The backend authenticates as one of these,
-- inherits the matching group role's privileges, and sets app.actor_id
-- per request with SET LOCAL so RLS (02_rls.sql) can do its job.
--
-- Passwords are placeholders: set real ones with ALTER ROLE ... PASSWORD
-- outside version control, or generate them in deployment scripts. Never
-- commit a real password here.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'butterfly_app') THEN
        CREATE ROLE butterfly_app LOGIN PASSWORD 'change_me' IN ROLE player_role;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'butterfly_gm') THEN
        CREATE ROLE butterfly_gm LOGIN PASSWORD 'change_me' IN ROLE game_master_role;
    END IF;
END;
$$;

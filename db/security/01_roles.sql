-- Group roles; the backend's login role joins one of them and sets app.actor_id per request (SET LOCAL).
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'player_role') THEN
        CREATE ROLE player_role NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'game_master_role') THEN
        CREATE ROLE game_master_role NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'auditor_role') THEN
        CREATE ROLE auditor_role NOLOGIN;
    END IF;
END;
$$;

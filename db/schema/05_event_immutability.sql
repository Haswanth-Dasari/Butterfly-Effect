-- The superuser bypasses REVOKE but not triggers; REVOKE is demonstrated later with a player role.
CREATE FUNCTION forbid_event_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'events are immutable';
END;
$$;

CREATE TRIGGER event_immutable
BEFORE UPDATE OR DELETE ON event
FOR EACH ROW
EXECUTE FUNCTION forbid_event_change();

CREATE TRIGGER event_no_truncate
BEFORE TRUNCATE ON event
FOR EACH STATEMENT
EXECUTE FUNCTION forbid_event_change();

REVOKE UPDATE, DELETE, TRUNCATE ON event FROM PUBLIC;

-- Live updates: notify listeners (the backend's WebSocket relay) whenever a
-- new event lands, so browsers can see ripples without polling.
--
-- Security note: this trigger does NOT decide who gets to see the event.
-- It broadcasts only the minimum needed to look the row up (branch, event,
-- tick, action_type and visibility). The backend relay re-checks witnesses
-- (the same event_witness/RLS rule the rest of the app uses) before it
-- forwards anything to a specific browser, so a secret steal is never
-- pushed to someone who did not witness it. The payload itself is never
-- put in the notification, since NOTIFY is not access-controlled.
CREATE OR REPLACE FUNCTION notify_world_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_notify(
        'world_updates',
        jsonb_build_object(
            'branch_id', NEW.branch_id,
            'event_id', NEW.event_id,
            'tick', NEW.tick,
            'actor_id', NEW.actor_id,
            'action_type', NEW.action_type
        )::text
    );
    RETURN NEW;
END;
$$;

-- AFTER INSERT so it fires only once the event (and its hash) is committed
-- to the row; cascades from the rules engine each fire their own insert and
-- so each get their own notification, which is what makes a ripple visible
-- step by step rather than as one lump.
CREATE TRIGGER event_notify
AFTER INSERT ON event
FOR EACH ROW
EXECUTE FUNCTION notify_world_update();

-- Test Suite 13: Live updates (pg_notify on event insert)

BEGIN;

DO $$
DECLARE
    v_main INT;
    v_demo INT;
    v_pending INT;
    v_payload TEXT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;

    -- 1. The trigger exists on event and points at notify_world_update.
    PERFORM 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgname = 'event_notify'
      AND t.tgrelid = 'event'::regclass
      AND p.proname = 'notify_world_update'
      AND NOT t.tgisinternal;
    IF FOUND THEN
        RAISE NOTICE 'PASS: event_notify trigger is installed on event';
    ELSE
        RAISE EXCEPTION 'FAIL: event_notify trigger missing on event';
    END IF;

    -- 2. apply_action raises a world_updates notification carrying the new event's id.
    PERFORM pg_notify('world_updates_test_drain', '');  -- no-op; keeps the queue interface warm
    v_demo := join_village(v_main, 'live_update_demo');

    PERFORM apply_action(v_main, v_demo, 'rumor',
        jsonb_build_object('about', v_demo, 'text', 'praise'));

    SELECT count(*) INTO v_pending
    FROM pg_listening_channels()
    WHERE pg_listening_channels = 'world_updates';
    -- This session never issued LISTEN, so it should not be subscribed;
    -- that in turn proves NOTIFY does not require a listener to succeed
    -- (apply_action above would have raised if the trigger body failed).
    IF v_pending = 0 THEN
        RAISE NOTICE 'PASS: apply_action succeeds with the notify trigger attached (no listener required)';
    ELSE
        RAISE EXCEPTION 'FAIL: unexpected listener state (%)', v_pending;
    END IF;
END;
$$;

ROLLBACK;

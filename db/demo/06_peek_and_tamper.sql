-- Demo 06: Peek and Tamper (Security, RLS Visibility, and Cryptographic Tamper Evidence)

BEGIN;

DO $$
DECLARE
    v_main INT;
    v_demo INT;
    v_spy INT;
    v_bakery INT;
    v_bread INT;
BEGIN
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT place_id INTO v_bakery FROM place WHERE name = 'Maren''s Bakery';
    SELECT item_id INTO v_bread FROM item WHERE name = 'bread';

    v_demo := join_village(v_main, 'Demo');
    v_spy := join_village(v_main, 'Spy');

    PERFORM apply_action(
        v_main,
        v_demo,
        'steal',
        jsonb_build_object('place_id', v_bakery, 'item_id', v_bread, 'qty', 1)
    );
END;
$$;

-- (A) as Spy: SELECT count(*) AS steals_visible_to_spy FROM event WHERE action_type = 'steal'
SELECT set_config('app.actor_id', (SELECT actor_id::text FROM actor WHERE name = 'Spy'), true);
SET LOCAL ROLE player_role;
SELECT count(*) AS steals_visible_to_spy FROM event WHERE action_type = 'steal';
RESET ROLE;

-- (B) as Demo: SELECT count(*) AS steals_visible_to_demo FROM event WHERE action_type = 'steal'
SELECT set_config('app.actor_id', (SELECT actor_id::text FROM actor WHERE name = 'Demo'), true);
SET LOCAL ROLE player_role;
SELECT count(*) AS steals_visible_to_demo FROM event WHERE action_type = 'steal';
RESET ROLE;

-- (C) as Spy, inside a DO block: try UPDATE event SET payload = '{}'::jsonb; catch insufficient_privilege
SELECT set_config('app.actor_id', (SELECT actor_id::text FROM actor WHERE name = 'Spy'), true);
SET LOCAL ROLE player_role;
DO $$
BEGIN
    UPDATE event SET payload = '{}'::jsonb;
    RAISE EXCEPTION 'direct UPDATE unexpectedly succeeded';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'direct UPDATE as player denied: %', SQLSTATE;
END;
$$;
RESET ROLE;

-- (D) as auditor_role: SELECT * FROM verify_event_chain();  (expect 0 rows)
SELECT set_config('app.actor_id', '', true);
SET LOCAL ROLE auditor_role;
SELECT * FROM verify_event_chain();
RESET ROLE;

-- (E) as superuser: bypass immutability trigger and tamper with the steal event payload
ALTER TABLE event DISABLE TRIGGER event_immutable;
UPDATE event SET payload = jsonb_build_object('tampered', true) WHERE action_type = 'steal';
ALTER TABLE event ENABLE TRIGGER event_immutable;

-- (F) as auditor_role: SELECT * FROM verify_event_chain();  (expect 1 row)
SET LOCAL ROLE auditor_role;
SELECT * FROM verify_event_chain();
RESET ROLE;

ROLLBACK;

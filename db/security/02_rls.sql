-- Row Level Security (RLS) policies for player privacy and role-based visibility.

-- 1. Table: event
ALTER TABLE event ENABLE ROW LEVEL SECURITY;

-- Staff members (game master, auditor) can see all events.
DROP POLICY IF EXISTS staff_all ON event;
CREATE POLICY staff_all ON event
    FOR SELECT
    TO game_master_role, auditor_role
    USING (true);

-- Players may only see events that they personally witnessed.
DROP POLICY IF EXISTS player_witnessed ON event;
CREATE POLICY player_witnessed ON event
    FOR SELECT
    TO player_role
    USING (
        EXISTS (
            SELECT 1
            FROM event_witness w
            WHERE w.event_id = event.event_id
              AND w.actor_id = NULLIF(current_setting('app.actor_id', true), '')::int
        )
    );

-- 2. Table: event_witness
ALTER TABLE event_witness ENABLE ROW LEVEL SECURITY;

-- Staff members can see all witness records.
DROP POLICY IF EXISTS staff_all ON event_witness;
CREATE POLICY staff_all ON event_witness
    FOR SELECT
    TO game_master_role, auditor_role
    USING (true);

-- Players may only see their own witness records.
DROP POLICY IF EXISTS player_own ON event_witness;
CREATE POLICY player_own ON event_witness
    FOR SELECT
    TO player_role
    USING (
        actor_id = NULLIF(current_setting('app.actor_id', true), '')::int
    );

-- 3. Table: entity_state
ALTER TABLE entity_state ENABLE ROW LEVEL SECURITY;

-- Staff members can see all entity states.
DROP POLICY IF EXISTS staff_all ON entity_state;
CREATE POLICY staff_all ON entity_state
    FOR SELECT
    TO game_master_role, auditor_role
    USING (true);

-- Players may only see their own entity state (private coins, trust, and inventory).
DROP POLICY IF EXISTS player_own ON entity_state;
CREATE POLICY player_own ON entity_state
    FOR SELECT
    TO player_role
    USING (
        entity_id = NULLIF(current_setting('app.actor_id', true), '')::int
    );

-- 4. Table: event_cause
ALTER TABLE event_cause ENABLE ROW LEVEL SECURITY;

-- Staff members can see all causal links.
DROP POLICY IF EXISTS staff_all ON event_cause;
CREATE POLICY staff_all ON event_cause
    FOR SELECT
    TO game_master_role, auditor_role
    USING (true);

-- Players may only see causal links leading to an effect event that is visible to them.
DROP POLICY IF EXISTS player_visible_effect ON event_cause;
CREATE POLICY player_visible_effect ON event_cause
    FOR SELECT
    TO player_role
    USING (
        EXISTS (
            SELECT 1
            FROM event e
            WHERE e.event_id = event_cause.effect_id
        )
    );

-- 5. Table: causal_closure
ALTER TABLE causal_closure ENABLE ROW LEVEL SECURITY;

-- Staff members can see the full causal closure graph.
DROP POLICY IF EXISTS staff_all ON causal_closure;
CREATE POLICY staff_all ON causal_closure
    FOR SELECT
    TO game_master_role, auditor_role
    USING (true);

-- Players may only see causal closure pairs where both the ancestor and descendant events are visible to them.
DROP POLICY IF EXISTS player_visible_pair ON causal_closure;
CREATE POLICY player_visible_pair ON causal_closure
    FOR SELECT
    TO player_role
    USING (
        EXISTS (
            SELECT 1
            FROM event e
            WHERE e.event_id = causal_closure.descendant_id
        )
        AND EXISTS (
            SELECT 1
            FROM event e
            WHERE e.event_id = causal_closure.ancestor_id
        )
    );

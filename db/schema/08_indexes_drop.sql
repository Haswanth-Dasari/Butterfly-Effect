-- 08_indexes_drop.sql - Used by the benchmark to recreate the 'before' state; never run in normal use.

DROP INDEX IF EXISTS event_branch_tick_idx;
DROP INDEX IF EXISTS event_branch_event_idx;
DROP INDEX IF EXISTS event_cause_cause_idx;
DROP INDEX IF EXISTS causal_closure_desc_idx;
DROP INDEX IF EXISTS causal_path_prefix_idx;
DROP INDEX IF EXISTS event_witness_actor_idx;
DROP INDEX IF EXISTS scheduled_pending_idx;
DROP INDEX IF EXISTS entity_state_open_idx;
DROP INDEX IF EXISTS snapshot_branch_event_idx;

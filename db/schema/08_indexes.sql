-- 08_indexes.sql - Secondary and partial indexes for read queries and fork lookups

CREATE INDEX event_branch_tick_idx ON event (branch_id, tick);  -- range reads, current_tick
CREATE INDEX event_branch_event_idx ON event (branch_id, event_id);  -- chain-prev lookup, lineage reads
CREATE INDEX event_cause_cause_idx ON event_cause (cause_id);  -- downward walk (the upward walk uses the primary key (effect_id, cause_id))
CREATE INDEX causal_closure_desc_idx ON causal_closure (descendant_id, depth);  -- Ask Why via the closure table
CREATE INDEX causal_path_prefix_idx ON causal_path (path text_pattern_ops);  -- descendants by path prefix
CREATE INDEX event_witness_actor_idx ON event_witness (actor_id, event_id);  -- what an actor witnessed
CREATE INDEX scheduled_pending_idx ON scheduled_effect (branch_id, due_tick, scheduled_id) WHERE NOT processed;  -- partial: claiming due effects
CREATE INDEX entity_state_open_idx ON entity_state (entity_id, branch_id) WHERE upper_inf(valid_ticks);  -- partial: the open (current) state row
CREATE INDEX snapshot_branch_event_idx ON snapshot (branch_id, last_event_id DESC);  -- best snapshot for a fork

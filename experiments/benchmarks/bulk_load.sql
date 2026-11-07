-- Synthetic data for benchmarks only.
-- The 4-event chains mimic the steal-price-state-rumor ripple across branches.
-- Closure and path rows are generated consistently with the causal edges.

CREATE OR REPLACE FUNCTION bench_bulk_load(p_events BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_base BIGINT;
    v_versions INT;
BEGIN
    -- bench_bulk_load must be run by a superuser.
    -- Disables triggers (including immutability and causal triggers) and foreign key checks
    -- for this transaction only to allow fast set-based bulk loading.
    PERFORM set_config('session_replication_role', 'replica', true);

    -- Base event_id from existing seed (the genesis event)
    SELECT COALESCE(MAX(event_id), 0) INTO v_base FROM event;

    -- 1. branch: insert branches 2..5 and advance branch sequence
    INSERT INTO branch (branch_id, name, parent_id, fork_event)
    SELECT b, 'bench_b' || b, NULL, NULL
    FROM generate_series(2, 5) b;

    PERFORM setval(pg_get_serial_sequence('branch', 'branch_id'), (SELECT MAX(branch_id) FROM branch));

    -- 2. event: insert synthetic event stream with OVERRIDING SYSTEM VALUE
    -- chain_idx = (g - 1) / 4; pos = (g - 1) % 4
    -- branch_id = 1 + (chain_idx % 5); tick = chain_idx / 50
    -- action_type by pos: 0 'steal', 1 'set_price', 2 'state_change', 3 'rumor'
    -- actor_id = 1 + (chain_idx % 30) when pos = 0, else NULL
    INSERT INTO event (event_id, branch_id, tick, actor_id, action_type, payload, prev_hash, hash)
    OVERRIDING SYSTEM VALUE
    SELECT
        v_base + g,
        1 + (((g - 1) / 4) % 5),
        ((g - 1) / 4) / 50,
        CASE WHEN ((g - 1) % 4) = 0 THEN 1 + (((g - 1) / 4) % 30) ELSE NULL END,
        CASE ((g - 1) % 4)
            WHEN 0 THEN 'steal'
            WHEN 1 THEN 'set_price'
            WHEN 2 THEN 'state_change'
            WHEN 3 THEN 'rumor'
        END,
        jsonb_build_object('n', g),
        NULL,
        digest(g::text, 'sha256')
    FROM generate_series(1, p_events) g;

    PERFORM setval(pg_get_serial_sequence('event', 'event_id'), (SELECT MAX(event_id) FROM event));

    -- 3. event_cause: for pos > 0: effect_id = event id, cause_id = event id - 1, rule_id = 1 + (pos % 3)
    INSERT INTO event_cause (effect_id, cause_id, rule_id)
    SELECT
        v_base + g,
        v_base + g - 1,
        1 + (((g - 1) % 4) % 3)
    FROM generate_series(1, p_events) g
    WHERE ((g - 1) % 4) > 0;

    -- 4. event_witness: two rows per event: actors 1 + (g % 30) and 1 + ((g+7) % 30)
    -- plus, for pos = 3 events, three more rows with actors 1 + ((g+11) % 30), 1 + ((g+13) % 30), 1 + ((g+17) % 30)
    INSERT INTO event_witness (event_id, actor_id)
    SELECT v_base + g, 1 + (g % 30)
    FROM generate_series(1, p_events) g
    UNION ALL
    SELECT v_base + g, 1 + ((g + 7) % 30)
    FROM generate_series(1, p_events) g;

    INSERT INTO event_witness (event_id, actor_id)
    SELECT v_base + g, 1 + ((g + 11) % 30)
    FROM generate_series(1, p_events) g
    WHERE ((g - 1) % 4) = 3
    UNION ALL
    SELECT v_base + g, 1 + ((g + 13) % 30)
    FROM generate_series(1, p_events) g
    WHERE ((g - 1) % 4) = 3
    UNION ALL
    SELECT v_base + g, 1 + ((g + 17) % 30)
    FROM generate_series(1, p_events) g
    WHERE ((g - 1) % 4) = 3;

    -- 5. causal_closure: self row (id, id, 0) for every event;
    -- for pos > 0 also (id - d, id, d) for d = 1..pos
    INSERT INTO causal_closure (ancestor_id, descendant_id, depth)
    SELECT v_base + g, v_base + g, 0
    FROM generate_series(1, p_events) g;

    INSERT INTO causal_closure (ancestor_id, descendant_id, depth)
    SELECT v_base + g - d, v_base + g, d
    FROM generate_series(1, p_events) g
    CROSS JOIN LATERAL generate_series(1, ((g - 1) % 4)) d
    WHERE ((g - 1) % 4) > 0;

    -- 6. causal_path: ids of the chain from head to itself joined by '/' using CASE on pos
    INSERT INTO causal_path (event_id, path)
    SELECT
        v_base + g,
        CASE ((g - 1) % 4)
            WHEN 0 THEN (v_base + g)::text
            WHEN 1 THEN (v_base + g - 1)::text || '/' || (v_base + g)::text
            WHEN 2 THEN (v_base + g - 2)::text || '/' || (v_base + g - 1)::text || '/' || (v_base + g)::text
            WHEN 3 THEN (v_base + g - 3)::text || '/' || (v_base + g - 2)::text || '/' || (v_base + g - 1)::text || '/' || (v_base + g)::text
        END
    FROM generate_series(1, p_events) g;

    -- 7. scheduled_effect: p_events / 20 rows
    -- The synthetic unprocessed effects live only on branches 2-5 so engine calls on main (branch 1) never claim them, and every payload is a valid effect anyway.
    -- branch_id = 2 + (k % 4), due_tick = k / 50, source_event_id = v_base + k, rule_id = 1 + (k % 15),
    -- payload = valid effect object, processed = (k % 100 <> 0)
    INSERT INTO scheduled_effect (branch_id, due_tick, source_event_id, rule_id, payload, processed)
    SELECT
        2 + (k % 4),
        k / 50,
        v_base + k,
        1 + (k % 15),
        jsonb_build_object('action', 'state_change', 'actor', NULL, 'payload', jsonb_build_object('entity_id', 1, 'set', jsonb_build_object('mood', 'content')), 'visibility', 'private'),
        (k % 100 <> 0)
    FROM generate_series(1, (p_events / 20)) k;

    PERFORM setval(pg_get_serial_sequence('scheduled_effect', 'scheduled_id'), (SELECT MAX(scheduled_id) FROM scheduled_effect));

    -- 8. entity_state: reset branch 1 and insert closed + open versions
    -- V = greatest(10, p_events / 1000)
    DELETE FROM entity_state WHERE branch_id = 1;

    v_versions := GREATEST(10, (p_events / 1000)::INT);

    INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
    SELECT
        e,
        1,
        int4range(v, v + 1),
        '{"mood":"content","trust":50,"coins":10}'::jsonb
    FROM generate_series(1, 30) e
    CROSS JOIN generate_series(0, v_versions - 1) v;

    INSERT INTO entity_state (entity_id, branch_id, valid_ticks, state)
    SELECT
        e,
        1,
        int4range(v_versions, NULL),
        '{"mood":"content","trust":50,"coins":10}'::jsonb
    FROM generate_series(1, 30) e;
END;
$$;

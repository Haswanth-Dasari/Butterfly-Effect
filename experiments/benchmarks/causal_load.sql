-- Synthetic causal lineage data generator and benchmark write-cost function.
-- Two functions created in the benchmark database only.

-- (a) bench_causal_load: set-based bulk loader for causal chains of arbitrary length/depth.
CREATE OR REPLACE FUNCTION bench_causal_load(p_events BIGINT, p_depth INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    L INT;
    v_chains BIGINT;
    v_base BIGINT;
BEGIN
    -- bench_causal_load must be run by a superuser.
    -- Disables triggers (including immutability and causal triggers) and foreign key checks
    -- for this transaction only to allow fast set-based bulk loading.
    PERFORM set_config('session_replication_role', 'replica', true);

    L := p_depth + 1;
    v_chains := p_events / L;

    -- Base event_id from existing seed (the genesis event)
    SELECT COALESCE(MAX(event_id), 0) INTO v_base FROM event;

    -- 1. Insert synthetic events
    -- chain_idx = (g - 1) / L; pos = (g - 1) % L
    -- branch_id = 1; tick = chain_idx / 50
    -- action_type: 'steal' when pos = 0 else 'state_change'
    -- actor_id: 1 + (chain_idx % 30) when pos = 0 else NULL
    INSERT INTO event (event_id, branch_id, tick, actor_id, action_type, payload, prev_hash, hash)
    OVERRIDING SYSTEM VALUE
    SELECT
        v_base + g,
        1,
        ((g - 1) / L) / 50,
        CASE WHEN ((g - 1) % L) = 0 THEN 1 + (((g - 1) / L) % 30) ELSE NULL END,
        CASE WHEN ((g - 1) % L) = 0 THEN 'steal' ELSE 'state_change' END,
        jsonb_build_object('n', g),
        NULL,
        digest(g::text, 'sha256')
    FROM generate_series(1, v_chains * L) g;

    PERFORM setval(pg_get_serial_sequence('event', 'event_id'), (SELECT MAX(event_id) FROM event));

    -- 2. Insert direct causal edges
    -- for pos > 0: effect_id = event id, cause_id = event id - 1, rule_id = 1
    INSERT INTO event_cause (effect_id, cause_id, rule_id)
    SELECT
        v_base + g,
        v_base + g - 1,
        1
    FROM generate_series(1, v_chains * L) g
    WHERE ((g - 1) % L) > 0;

    -- 3. Insert transitive causal closure rows
    -- for every event: (event id - d, event id, d) for d = 0..pos
    INSERT INTO causal_closure (ancestor_id, descendant_id, depth)
    SELECT
        v_base + g - d,
        v_base + g,
        d
    FROM generate_series(1, v_chains * L) g
    CROSS JOIN LATERAL generate_series(0, ((g - 1) % L)::INT) d;

    -- 4. Insert causal path rows
    -- for every event: array_to_string(ARRAY(SELECT generate_series(event id - pos, event id)), '/')
    INSERT INTO causal_path (event_id, path)
    SELECT
        v_base + g,
        array_to_string(ARRAY(SELECT generate_series(v_base + g - ((g - 1) % L), v_base + g)), '/')
    FROM generate_series(1, v_chains * L) g;
END;
$$;

-- (b) bench_causal_write: measures the write cost of one event plus its causal edge,
-- with and without the closure/path maintenance trigger.
CREATE OR REPLACE FUNCTION bench_causal_write(
    p_ops INT,
    p_first_chain BIGINT,
    p_depth INT,
    p_trigger BOOLEAN
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    L INT;
    v_base BIGINT;
    v_tail BIGINT;
    v_new BIGINT;
    t0 TIMESTAMPTZ;
    t1 TIMESTAMPTZ;
BEGIN
    L := p_depth + 1;

    SELECT min(event_id) - 1 INTO v_base
    FROM event
    WHERE action_type = 'steal';

    IF NOT p_trigger THEN
        ALTER TABLE event_cause DISABLE TRIGGER event_cause_derived;
    ELSE
        ALTER TABLE event_cause ENABLE TRIGGER event_cause_derived;
    END IF;

    t0 := clock_timestamp();
    BEGIN
        FOR i IN 0..(p_ops - 1) LOOP
            v_tail := v_base + (p_first_chain + i + 1) * L;

            INSERT INTO event (branch_id, tick, actor_id, action_type, payload)
            VALUES (1, 0, NULL, 'rumor', '{}'::jsonb)
            RETURNING event_id INTO v_new;

            INSERT INTO event_cause (effect_id, cause_id, rule_id)
            VALUES (v_new, v_tail, 1);
        END LOOP;
        t1 := clock_timestamp();

        -- Always enable the trigger again before returning
        ALTER TABLE event_cause ENABLE TRIGGER event_cause_derived;
    EXCEPTION WHEN OTHERS THEN
        ALTER TABLE event_cause ENABLE TRIGGER event_cause_derived;
        RAISE;
    END;

    RETURN ROUND(((EXTRACT(EPOCH FROM (t1 - t0)) * 1000.0) / p_ops)::NUMERIC, 3);
END;
$$;

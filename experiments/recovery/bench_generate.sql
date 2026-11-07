-- Synthetic history for benchmarks only; about 13 events per day.
CREATE OR REPLACE FUNCTION bench_generate(p_days INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_main INT;
    v_hartley INT;
    v_b1 INT;
    v_b2 INT;
    v_b3 INT;
    d INT;
BEGIN
    -- Look up the main branch id and the id of Hartley Farm
    SELECT branch_id INTO v_main FROM branch WHERE name = 'main' AND parent_id IS NULL;
    IF v_main IS NULL THEN
        RAISE EXCEPTION 'main branch not found';
    END IF;

    SELECT place_id INTO v_hartley FROM place WHERE name = 'Hartley Farm';
    IF v_hartley IS NULL THEN
        RAISE EXCEPTION 'Hartley Farm not found';
    END IF;

    -- Create players 'bench_1', 'bench_2', 'bench_3' with join_village if they do not exist yet (look up by name)
    SELECT actor_id INTO v_b1 FROM actor WHERE name = 'bench_1';
    IF NOT FOUND THEN
        v_b1 := join_village(v_main, 'bench_1');
    END IF;

    SELECT actor_id INTO v_b2 FROM actor WHERE name = 'bench_2';
    IF NOT FOUND THEN
        v_b2 := join_village(v_main, 'bench_2');
    END IF;

    SELECT actor_id INTO v_b3 FROM actor WHERE name = 'bench_3';
    IF NOT FOUND THEN
        v_b3 := join_village(v_main, 'bench_3');
    END IF;

    -- For each day 1..p_days: advance day and apply help_harvest for each player
    FOR d IN 1..p_days LOOP
        PERFORM advance_day(v_main);
        PERFORM apply_action(v_main, v_b1, 'help_harvest', jsonb_build_object('place_id', v_hartley, 'qty', 1));
        PERFORM apply_action(v_main, v_b2, 'help_harvest', jsonb_build_object('place_id', v_hartley, 'qty', 1));
        PERFORM apply_action(v_main, v_b3, 'help_harvest', jsonb_build_object('place_id', v_hartley, 'qty', 1));
    END LOOP;
END;
$$;

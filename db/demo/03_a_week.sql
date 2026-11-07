-- A village that lives without you.
BEGIN;

CREATE TEMP TABLE week (
    day INT,
    bread INT,
    bakery_flour INT,
    mill_grain INT,
    mill_flour INT,
    farm_grain INT,
    events INT
);

DO $$
DECLARE
    v_branch_id INT;
    v_bakery_id INT;
    v_mill_id INT;
    v_farm_id INT;
    v_bread_id INT;
    v_grain_id INT;
    v_flour_id INT;
    v_day INT;
    v_bread INT;
    v_bakery_flour INT;
    v_mill_grain INT;
    v_mill_flour INT;
    v_farm_grain INT;
    v_events INT;
    i INT;
BEGIN
    SELECT branch_id INTO v_branch_id FROM branch WHERE name = 'main' AND parent_id IS NULL;
    SELECT place_id INTO v_bakery_id FROM place WHERE name = 'Maren''s Bakery';
    SELECT place_id INTO v_mill_id FROM place WHERE name = 'Tobin''s Mill';
    SELECT place_id INTO v_farm_id FROM place WHERE name = 'Hartley Farm';
    SELECT item_id INTO v_bread_id FROM item WHERE name = 'bread';
    SELECT item_id INTO v_grain_id FROM item WHERE name = 'grain';
    SELECT item_id INTO v_flour_id FROM item WHERE name = 'flour';

    FOR i IN 1..5 LOOP
        v_day := advance_day(v_branch_id);

        SELECT qty INTO v_bread
        FROM stock
        WHERE place_id = v_bakery_id AND item_id = v_bread_id AND branch_id = v_branch_id;

        SELECT qty INTO v_bakery_flour
        FROM stock
        WHERE place_id = v_bakery_id AND item_id = v_flour_id AND branch_id = v_branch_id;

        SELECT qty INTO v_mill_grain
        FROM stock
        WHERE place_id = v_mill_id AND item_id = v_grain_id AND branch_id = v_branch_id;

        SELECT qty INTO v_mill_flour
        FROM stock
        WHERE place_id = v_mill_id AND item_id = v_flour_id AND branch_id = v_branch_id;

        SELECT qty INTO v_farm_grain
        FROM stock
        WHERE place_id = v_farm_id AND item_id = v_grain_id AND branch_id = v_branch_id;

        SELECT count(*) INTO v_events
        FROM event
        WHERE branch_id = v_branch_id AND tick = v_day;

        INSERT INTO week (day, bread, bakery_flour, mill_grain, mill_flour, farm_grain, events)
        VALUES (v_day, v_bread, v_bakery_flour, v_mill_grain, v_mill_flour, v_farm_grain, v_events);
    END LOOP;
END
$$;

SELECT * FROM week ORDER BY day;

SELECT * FROM verify_event_chain();

ROLLBACK;

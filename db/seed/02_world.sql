-- Seed assumes an EMPTY schema.

INSERT INTO place (place_id, name, kind, x, y) VALUES
(1, 'Market Square', 'market', 50.0, 50.0),
(2, 'Maren''s Bakery', 'bakery', 48.0, 52.0),
(3, 'Tobin''s Mill', 'mill', 35.0, 65.0),
(4, 'Ines''s Inn', 'inn', 52.0, 47.0),
(5, 'The Well', 'well', 50.0, 48.0),
(6, 'Hartley Farm', 'farm', 20.0, 25.0),
(7, 'Brook Farm', 'farm', 25.0, 75.0),
(8, 'Thorn Farm', 'farm', 75.0, 30.0),
(9, 'Home of Wick', 'home', 47.0, 45.0),
(10, 'Home of Baker-Dunn', 'home', 46.0, 54.0),
(11, 'Home of Miller', 'home', 33.0, 67.0),
(12, 'Home of Taverner', 'home', 55.0, 45.0),
(13, 'Home of Hollis', 'home', 40.0, 60.0),
(14, 'Home of Hartley', 'home', 18.0, 23.0),
(15, 'Home of Brook', 'home', 23.0, 77.0),
(16, 'Home of Thorn', 'home', 77.0, 28.0),
(17, 'Home of Carter', 'home', 60.0, 55.0),
(18, 'Home of Fenn', 'home', 65.0, 40.0);

INSERT INTO home (home_id, place_id, family_name) VALUES
(1, 9, 'Wick'),
(2, 10, 'Baker-Dunn'),
(3, 11, 'Miller'),
(4, 12, 'Taverner'),
(5, 13, 'Hollis'),
(6, 14, 'Hartley'),
(7, 15, 'Brook'),
(8, 16, 'Thorn'),
(9, 17, 'Carter'),
(10, 18, 'Fenn');

INSERT INTO actor (actor_id, name, kind, job, home_id) VALUES
(1, 'Old Wick', 'villager', 'well_keeper', 1),
(2, 'Maren', 'villager', 'baker', 2),
(3, 'Elspeth Dunn', 'villager', 'baker_helper', 2),
(4, 'Robin Dunn', 'villager', NULL, 2),
(5, 'Tobin', 'villager', 'miller', 3),
(6, 'Kendra Miller', 'villager', 'labourer', 3),
(7, 'Jonas Miller', 'villager', NULL, 3),
(8, 'Ines', 'villager', 'innkeeper', 4),
(9, 'Aldous Taverner', 'villager', 'labourer', 4),
(10, 'Lily Taverner', 'villager', NULL, 4),
(11, 'Rowan Hollis', 'villager', 'mill_helper', 5),
(12, 'Bethan Hollis', 'villager', 'labourer', 5),
(13, 'Giles Hollis', 'villager', NULL, 5),
(14, 'Milo Hollis', 'villager', NULL, 5),
(15, 'Hugh Hartley', 'villager', 'farmer', 6),
(16, 'Edith Hartley', 'villager', 'farmer', 6),
(17, 'Toby Hartley', 'villager', NULL, 6),
(18, 'Silas Brook', 'villager', 'farmer', 7),
(19, 'Martha Brook', 'villager', 'farmer', 7),
(20, 'Clara Brook', 'villager', NULL, 7),
(21, 'Garth Thorn', 'villager', 'farmer', 8),
(22, 'Agnes Thorn', 'villager', 'farmer', 8),
(23, 'Bram Thorn', 'villager', NULL, 8),
(24, 'Roger Carter', 'villager', 'labourer', 9),
(25, 'Alice Carter', 'villager', 'labourer', 9),
(26, 'Bess Carter', 'villager', NULL, 9),
(27, 'Ned Carter', 'villager', NULL, 9),
(28, 'Gilbert Fenn', 'villager', 'labourer', 10),
(29, 'Winnie Fenn', 'villager', 'labourer', 10),
(30, 'Jack Fenn', 'villager', NULL, 10);

SELECT setval(pg_get_serial_sequence('place', 'place_id'), (SELECT max(place_id) FROM place));
SELECT setval(pg_get_serial_sequence('home', 'home_id'), (SELECT max(home_id) FROM home));
SELECT setval(pg_get_serial_sequence('actor', 'actor_id'), (SELECT max(actor_id) FROM actor));
SELECT setval(pg_get_serial_sequence('item', 'item_id'), (SELECT max(item_id) FROM item));
SELECT setval(pg_get_serial_sequence('branch', 'branch_id'), (SELECT max(branch_id) FROM branch));

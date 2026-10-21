-- Seed assumes an EMPTY schema.

INSERT INTO action_type (action_type, description) VALUES
('gift', 'Gift an item or coins to another villager'),
('trade', 'Trade items or commodities with another villager'),
('steal', 'Steal items or coins from a villager or place'),
('rumor', 'Spread a rumor to influence village opinions'),
('build', 'Construct or upgrade a village structure or workshop'),
('hire', 'Hire a villager for labor, trade, or assistance'),
('set_price', 'Set or adjust the commodity price at a workplace'),
('help_harvest', 'Assist farm households with harvesting crops'),
('sabotage', 'Sabotage crops, structures, or goods in secret'),
('feast', 'Host or attend a community feast in the village'),
('drought', 'World event: severe lack of rainfall damaging seasonal crops'),
('flood', 'World event: river inundation damaging low-lying fields and structures'),
('festival', 'World event: annual village celebration bringing high spirits and trade'),
('traveling_merchant', 'World event: itinerant merchant visiting Alderbrook with exotic wares'),
('tax_collector', 'World event: royal tax collector arriving to levy dues on households'),
('world_start', 'System: marks the start of a branch'),
('arrive', 'System: a player arrives in the village');

INSERT INTO item (item_id, name) VALUES
(1, 'bread'),
(2, 'grain'),
(3, 'flour');

INSERT INTO branch (branch_id, name, parent_id, fork_event) VALUES
(1, 'main', NULL, NULL);

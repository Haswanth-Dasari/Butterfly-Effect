# Concept coverage matrix

Every database topic in the project documentation (section 17), mapped to the file that **implements** it, the test that **proves** it and the experiment that **measures** it. Every path below is checked by `scripts/check_docs.py`.

| # | Concept | Implemented in | Proven by (test) | Measured by (experiment) |
|---|---|---|---|---|
| 17.1 | Data modeling (ER → relational) | `db/schema/01_world_tables.sql`, `db/schema/02_engine_tables.sql`, `db/schema/03_state_tables.sql`, `docs/er/er-diagram.md` | `db/tests/03_seed_tests.sql` | — |
| 17.2 | Integrity constraints (PK/FK/CHECK/EXCLUDE) | `db/schema/03_state_tables.sql`, `db/schema/06_rule_checks.sql`, `db/schema/07_causal_structures.sql` | `db/tests/01_constraint_tests.sql` | — |
| 17.3 | Normalization (FDs, BCNF proof) | `docs/er/normalization.md` | — | — |
| 17.4 | Append-only storage (event sourcing) | `db/schema/05_event_immutability.sql` | `db/tests/02_event_store_tests.sql` | `experiments/results/exp7a_rebuild.csv` |
| 17.5 | Tamper evidence (hash chain) | `db/procedures/01_event_hash.sql`, `db/procedures/02_verify_chain.sql` | `db/tests/02_event_store_tests.sql`, `db/tests/10_recovery_tests.sql` | `experiments/results/exp7b_crash.csv` |
| 17.6 | Causal graph, recursive queries | `db/procedures/09_ask_why.sql`, `db/schema/07_causal_structures.sql` | `db/tests/07_askwhy_tests.sql` | Experiment 3: `experiments/results/exp3_askwhy.csv` |
| 17.7 | Triggers and stored procedures (rules engine) | `db/procedures/05_apply_action.sql`, `db/procedures/06_rules_engine.sql`, `db/procedures/07_advance_day.sql`, `db/seed/04_rules.sql` | `db/tests/04_engine_tests.sql`, `db/tests/05_rules_tests.sql`, `db/tests/06_game_tests.sql` | — |
| 17.8 | Transactions and ACID | `db/procedures/05_apply_action.sql` | `db/tests/04_engine_tests.sql` | Experiment 1: `experiments/results/exp1_last_loaf.csv` |
| 17.9 | Concurrency control, isolation, deadlock | `experiments/pgbench/loaf_naive.sql`, `experiments/lab/00_lab.sql` | `experiments/lab/selftest.sql` | Experiments 1 and 2: `experiments/results/exp1_last_loaf.csv`, `experiments/results/exp2_deadlock.csv` |
| 17.10 | Indexing and query optimization | `db/schema/08_indexes.sql`, `db/schema/08_indexes_drop.sql` | `db/tests/11_index_tests.sql` | Experiment 5: `experiments/results/exp5_index_summary.csv`, `experiments/results/exp5_index_queries.csv`, `experiments/results/exp5_plans_1000000.txt` |
| 17.11 | Views, materialized views, window functions | `db/views/01_scores.sql`, `db/views/02_daily_views.sql`, `db/views/03_public_views.sql` | `db/tests/06_game_tests.sql`, `db/tests/13_live_update_tests.sql` | — |
| 17.12 | Temporal data and time travel | `db/procedures/12_lookback.sql`, `db/procedures/03_entity_state.sql` | `db/tests/12_lookback_tests.sql` | — |
| 17.13 | Branching (parallel villages) | `db/procedures/10_branching.sql` | `db/tests/08_branching_tests.sql` | Experiment 4: `experiments/results/exp4_branching.csv`, `experiments/results/exp4_snapshots.csv` |
| 17.14 | Roles, privileges, row-level security | `db/security/03_privileges.sql`, `db/security/04_app_roles.sql` | `db/tests/09_security_tests.sql` | — |
| 17.15 | Durability, recovery, backup, PITR | `experiments/recovery/` | `db/tests/10_recovery_tests.sql` | Experiment 7: `experiments/results/exp7a_rebuild.csv`, `experiments/results/exp7b_crash.csv`, `experiments/results/exp7c_pitr.csv`, `experiments/results/exp7d_mvcc.csv` |
| 17.16 | Scheduled work, queues, LISTEN/NOTIFY | `db/procedures/07_advance_day.sql`, `db/procedures/13_live_updates.sql`, `backend/src/liveUpdates.js` | `db/tests/13_live_update_tests.sql` | — |
| 17.17 | Partitioning | `experiments/partitioning/exp8_partitioning.sql` | — | Experiment 8: `experiments/partitioning/run_experiment8.ps1` (writes `experiments/results/exp8_partitioning.csv` when run) |

## Story engine (scenario packs)

| Concept in the story | Implemented in | Proven by (test) |
|---|---|---|
| Stories as data (scenario, beats, options, clues, endings) | `db/scenarios/01_story_schema.sql`, `db/scenarios/mystery/slice.json`, `db/scenarios/build_seed.mjs`, `db/seed/05_story_mystery.sql` | `db/tests/14_story_slice_tests.sql` |
| Story effects as rules in the rules engine (meters, clues, hidden consequences) | `db/procedures/06_rules_engine.sql` (new conditions `state_gte`, `scenario`, `trait`), `db/seed/05_story_mystery.sql` | `db/tests/14_story_slice_tests.sql` |
| A playthrough is a branch (private world, rewind still works) | `db/scenarios/02_story_functions.sql` (`start_playthrough`) | `db/tests/14_story_slice_tests.sql` |
| Fog of knowledge in play (witnessed vs hidden events) | `db/procedures/05_apply_action.sql`, `db/scenarios/02_story_functions.sql` | `db/tests/14_story_slice_tests.sql` |
| Case Board and Compass computed in SQL | `db/scenarios/02_story_functions.sql` (`story_board`, `story_compass`) | `db/tests/14_story_slice_tests.sql` |
| API and UI | `backend/src/routes/story.js`, `frontend/js/story.js`, `frontend/js/storystart.js`, `frontend/js/almanac.js` | `scripts/ui_smoke_test.py` |

## Application layer (not a syllabus topic, but part of the system)

| Area | Files |
|---|---|
| REST + WebSocket API | `backend/src/server.js`, `backend/src/routes/actions.js`, `backend/src/routes/queries.js`, `backend/src/routes/world.js`, `backend/src/routes/join.js`, `backend/src/liveUpdates.js` |
| Parameterized queries, per-request RLS context | `backend/src/db.js`, `backend/src/auth.js` |
| Village map, ripples, day/night | `frontend/js/map.js`, `frontend/css/style.css` |
| Chronicle (Ask Why) | `frontend/js/chronicle.js` |
| Time slider (Look Back) | `frontend/js/timeline.js` |
| Parallel villages UI | `frontend/js/worlds.js` |
| Evening Bell, leaderboard | `frontend/js/main.js`, `frontend/js/village.js` |
| Database-free demo server | `backend/dev/mock-server.mjs` |

## Submission checklist (project doc §20.4)

| Item | Where |
|---|---|
| ER diagram and mapped relational schema | `docs/er/er-diagram.md`, `db/schema/` |
| Functional dependencies and normalization proof | `docs/er/normalization.md` |
| Full DDL, ≥5 triggers, ≥3 stored procedures, several views/MVs | `db/schema/`, `db/procedures/`, `db/views/` (6 triggers, 46 functions, 1 view + 2 materialized views) |
| Indexes with before/after benchmarks | `experiments/results/exp5_index_queries.csv` |
| Isolation, deadlock and tamper experiments | `experiments/results/exp1_last_loaf.csv`, `experiments/results/exp2_deadlock.csv`, `db/tests/02_event_store_tests.sql` |
| Roles and RLS demo | `db/tests/09_security_tests.sql`, `db/demo/` |
| Backup, point-in-time recovery and full rebuild demo | `experiments/recovery/`, `experiments/results/exp7c_pitr.csv`, `experiments/results/exp7a_rebuild.csv` |
| Concept-coverage matrix | this file |
| Report, slides, rehearsed demo script | `docs/report/Butterfly_Effect_Report.docx`, `docs/slides/Butterfly_Effect_Slides.pptx`, `docs/demo_script.md` |

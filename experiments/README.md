# Concurrency Experiments Lab

This directory contains concurrency benchmark experiments comparing transaction isolation levels, locking mechanisms, optimistic concurrency control, and deadlock prevention techniques in PostgreSQL 18.

> [!NOTE]
> **Schema Isolation**: All experiments run exclusively within the `lab` schema defined in `experiments/lab/00_lab.sql`. The experiments are completely isolated from and do not read or write any game data or tables in the `public` schema.

---

## Experiment 1: The Last Loaf (Lost Updates & Concurrency Control)

### Question Answered
How do different concurrency control patterns prevent lost updates, race conditions, and overselling when multiple concurrent clients compete for limited stock (the "last loaf" problem)?

### Concepts
- **Transaction Isolation Levels**: Behavior of `READ COMMITTED` vs `SERIALIZABLE` under high write contention.
- **Pessimistic Locking**: Explicit row-level locks via `SELECT ... FOR UPDATE`.
- **Atomic Operations & Constraints**: Relative in-place updates (`qty = qty - 1`) protected by relational `CHECK` constraints (matching the core engine design).
- **Optimistic Concurrency Control (OCC)**: Value-based Compare-And-Swap (CAS) retry loops without persistent read locks.

### Variant Summary
- **`naive`**: Demonstrates the classic lost update anomaly under default `READ COMMITTED` isolation, causing stale reads and severe overselling (phantom loaves).
- **`for_update`**: Uses pessimistic row locking (`SELECT ... FOR UPDATE`) before checking stock, guaranteeing zero overselling but introducing lock contention delays.
- **`atomic_check`**: Relies on a single atomic relative update (`SET qty = qty - 1`) validated by table `CHECK (qty >= 0)`, mirroring the game engine's design pattern.
- **`optimistic`**: Implements Compare-And-Swap (CAS) conditional updates (`WHERE qty = v`) inside a 10-attempt retry loop without acquiring pessimistic read locks.
- **`serializable`**: Executes naive purchase logic inside a `SERIALIZABLE` transaction, relying on PostgreSQL's SSI engine and pgbench retries (`--max-tries`) to resolve serialization failures.

### How to Run
Ensure `$env:PGPASSWORD` is set in your PowerShell session:
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/run_experiment1.ps1
```

Optional parameters:
- `-Database` (default: `butterfly`)
- `-User` (default: `postgres`)
- `-Loaves` (default: `100`)
- `-Clients` (default: `20`)
- `-TxPerClient` (default: `50`)
- `-MaxTries` (default: `50`)

### Results Output
CSV file: `experiments/results/exp1_last_loaf.csv`

### Results
| variant | mode | clients | tx_per_client | tps | failed | retried | serialization_failures | deadlock_failures | total_retries | sales | final_qty | removed | phantom | oversold | correct |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| naive | control | | | | | | | | | | | | | | |
| naive | contended | | | | | | | | | | | | | | |
| for_update | control | | | | | | | | | | | | | | |
| for_update | contended | | | | | | | | | | | | | | |
| atomic_check | control | | | | | | | | | | | | | | |
| atomic_check | contended | | | | | | | | | | | | | | |
| optimistic | control | | | | | | | | | | | | | | |
| optimistic | contended | | | | | | | | | | | | | | |
| serializable | control | | | | | | | | | | | | | | |
| serializable | contended | | | | | | | | | | | | | | |

---

## Experiment 2: The Deadlock Duel (Lock Ordering & Deadlock Avoidance)

### Question Answered
How does resource acquisition order impact concurrent transactions transferring balances between accounts, and how can deterministic lock ordering completely eliminate deadlocks?

### Concepts
- **Deadlock Cycles**: Cyclic wait-for graphs arising when concurrent transactions lock resources in opposing order (e.g., Alice->Bob concurrently with Bob->Alice).
- **Deadlock Detection**: Engine resolution via `deadlock_timeout` (configured to `100ms` during benchmark execution).
- **Canonical Lock Ordering**: Enforcing a deterministic acquisition order using SQL `LEAST()` and `GREATEST()` to eliminate circular wait conditions.

### Variant Summary
- **`unordered`**: Updates the sender's purse before the receiver's purse, creating lock inversion and frequent deadlock aborts when bidirectional transfers collide.
- **`ordered`**: Explicitly pre-locks both participants' purses in deterministic lexicographical order (`LEAST` followed by `GREATEST`) before modifying balances, completely preventing deadlocks.

### How to Run
Ensure `$env:PGPASSWORD` is set in your PowerShell session:
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/run_experiment2.ps1
```

Optional parameters:
- `-Database` (default: `butterfly`)
- `-User` (default: `postgres`)
- `-Clients` (default: `4`)
- `-TxPerClient` (default: `25`)

### Results Output
CSV file: `experiments/results/exp2_deadlock.csv`

### Results
| variant | clients | processed | failed | deadlock_failures | serialization_failures | tps | sum_coins | conserved | ledger_consistent |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| unordered | | | | | | | | | |
| ordered | | | | | | | | | |

---

## Experiment 5: Index Impact

### Question Answered
How do secondary and partial indexes impact read query execution latency, scan plans, and scaling behavior across event volumes from 10,000 to 1,000,000 events, and what is the trade-off in index build time, table storage overhead, and engine write throughput?

### Evaluated Queries and Indexes

| Query | Name | Target Query / Pattern | Index Needed |
| :--- | :--- | :--- | :--- |
| **Q1** | range | `SELECT count(*) FROM event WHERE branch_id = 2 AND tick BETWEEN MID AND MID+10;` | `event_branch_tick_idx` (`event(branch_id, tick)`) |
| **Q2** | current tick | `SELECT COALESCE(MAX(tick),0) FROM event WHERE branch_id = 3;` | `event_branch_tick_idx` (`event(branch_id, tick)`) |
| **Q3** | chain prev | `SELECT hash FROM event WHERE branch_id = 4 ORDER BY event_id DESC LIMIT 1;` | `event_branch_event_idx` (`event(branch_id, event_id)`) |
| **Q4** | ask why (recursive) | `WITH RECURSIVE up AS (...) SELECT event_id, MIN(depth) FROM up GROUP BY event_id;` | `PRIMARY KEY (effect_id, cause_id)` on `event_cause` |
| **Q5** | closure | `SELECT ancestor_id, depth FROM causal_closure WHERE descendant_id = DEEP AND depth > 0;` | `causal_closure_desc_idx` (`causal_closure(descendant_id, depth)`) |
| **Q6** | downward | `SELECT effect_id FROM event_cause WHERE cause_id = HEAD;` | `event_cause_cause_idx` (`event_cause(cause_id)`) |
| **Q7** | path prefix | `SELECT count(*) FROM causal_path WHERE path LIKE 'HEAD/%';` | `causal_path_prefix_idx` (`causal_path(path text_pattern_ops)`) |
| **Q8** | witness by actor | `SELECT count(*) FROM event_witness WHERE actor_id = 7;` | `event_witness_actor_idx` (`event_witness(actor_id, event_id)`) |
| **Q9** | player read under RLS | `BEGIN; SET LOCAL ROLE player_role; ... SELECT count(*) FROM event ...; ROLLBACK;` | `event_witness_actor_idx` & `event_branch_tick_idx` |
| **Q10** | pending claim | `SELECT scheduled_id FROM scheduled_effect WHERE branch_id = 2 AND NOT processed AND due_tick <= MID ORDER BY due_tick, scheduled_id LIMIT 10;` | `scheduled_pending_idx` (`scheduled_effect(branch_id, due_tick, scheduled_id) WHERE NOT processed`) |
| **Q11** | open row | `SELECT state FROM entity_state WHERE entity_id = 5 AND branch_id = 1 AND upper_inf(valid_ticks);` | `entity_state_open_idx` (`entity_state(entity_id, branch_id) WHERE upper_inf(valid_ticks)`) |

### How to Run
Ensure `$env:PGPASSWORD` is set in your PowerShell session:
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/benchmarks/run_experiment5.ps1
```

Optional parameters:
- `-Sizes` (default: `10000, 100000, 1000000`)
- `-Database` (default: `butterfly_bench`)
- `-User` (default: `postgres`)

### Output Files
- CSV file: `experiments/results/exp5_index_queries.csv` (per-query timing, scan type, speedup)
- CSV file: `experiments/results/exp5_index_summary.csv` (build times, storage sizes, engine write cost)
- Query plans: `experiments/results/exp5_plans_<N>.txt` (full EXPLAIN ANALYZE text for the largest dataset size)

### Results: Query Performance
| events | query | description | before_ms | after_ms | speedup | before_scan | after_scan |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 10000 | Q1 | range | | | | | |
| 10000 | Q2 | current_tick | | | | | |
| 10000 | Q3 | chain_prev | | | | | |
| 10000 | Q4 | ask_why_recursive | | | | | |
| 10000 | Q5 | closure | | | | | |
| 10000 | Q6 | downward | | | | | |
| 10000 | Q7 | path_prefix | | | | | |
| 10000 | Q8 | witness_by_actor | | | | | |
| 10000 | Q9 | player_rls | | | | | |
| 10000 | Q10 | pending_claim | | | | | |
| 10000 | Q11 | open_row | | | | | |
| 100000 | Q1 | range | | | | | |
| 100000 | Q2 | current_tick | | | | | |
| 100000 | Q3 | chain_prev | | | | | |
| 100000 | Q4 | ask_why_recursive | | | | | |
| 100000 | Q5 | closure | | | | | |
| 100000 | Q6 | downward | | | | | |
| 100000 | Q7 | path_prefix | | | | | |
| 100000 | Q8 | witness_by_actor | | | | | |
| 100000 | Q9 | player_rls | | | | | |
| 100000 | Q10 | pending_claim | | | | | |
| 100000 | Q11 | open_row | | | | | |
| 1000000 | Q1 | range | | | | | |
| 1000000 | Q2 | current_tick | | | | | |
| 1000000 | Q3 | chain_prev | | | | | |
| 1000000 | Q4 | ask_why_recursive | | | | | |
| 1000000 | Q5 | closure | | | | | |
| 1000000 | Q6 | downward | | | | | |
| 1000000 | Q7 | path_prefix | | | | | |
| 1000000 | Q8 | witness_by_actor | | | | | |
| 1000000 | Q9 | player_rls | | | | | |
| 1000000 | Q10 | pending_claim | | | | | |
| 1000000 | Q11 | open_row | | | | | |

### Results: Build Times & Write Overhead
| events | index_build_seconds | index_size_mb | table_size_mb | engine_write_before_ms | engine_write_after_ms |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 10000 | | | | | |
| 100000 | | | | | |
| 1000000 | | | | | |

### Measuring Rebuild Speed-Up in Experiment 7a
Now that secondary indexes are integrated into `db/schema/_all.sql`, Experiment 7a can be re-run to quantify how `event_branch_tick_idx` accelerates event store projection replays.

To measure the speed-up:
1. Preserve your baseline results from before indexes were added:
   ```powershell
   Copy-Item experiments/results/exp7a_rebuild.csv experiments/results/exp7a_rebuild_before_indexes.csv
   ```
2. Re-run Experiment 7a with indexes active:
   ```powershell
   powershell -ExecutionPolicy Bypass -File experiments/recovery/run_experiment7a.ps1
   ```
3. Compare `rebuild_projections_ms` and `rebuild_world_ms` between `exp7a_rebuild_before_indexes.csv` and `exp7a_rebuild.csv`.

---

## Experiment 7a: Rebuild from the Event Store (Application-Level Recovery)

### Question Answered
How does recovery replay time scale with event volume and history length, and does replaying lineage events from a baseline snapshot guarantee identical projection state digests across the world?

### How to Run
Ensure `$env:PGPASSWORD` is set in your PowerShell session:
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/recovery/run_experiment7a.ps1
```

Optional parameters:
- `-Days` (default: `50, 200, 800`)
- `-Database` (default: `butterfly_bench`)
- `-User` (default: `postgres`)

### Results Output
CSV file: `experiments/results/exp7a_rebuild.csv`

### Results
| days | events | entity_rows | closure_rows | rebuild_projections_ms | rebuild_world_ms | digest_equal |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 50 | | | | | | |
| 200 | | | | | | |
| 800 | | | | | | |

---

## Experiment 7b: Crash and Restart (Database-Level WAL Recovery)

### Question Answered
How does PostgreSQL's Write-Ahead Logging (WAL) and automatic redo recovery protect committed event store transactions and world state during an abrupt power loss or process kill (`SIGKILL`), and does recovery guarantee zero data loss, zero partial inflight writes, and unbroken event hash chains?

### What is Proven
- **Atomicity under Sudden Crash**: Inflight transactions active during a sudden kill (`taskkill /F /T`) leave zero partial writes or phantom records (`partial_players_found = 0`).
- **Durability of Acknowledged Commits**: All transactions acknowledged prior to the crash (`advance_day` 1..5) are fully preserved (`tick_ok = true`, `events_ok = true`).
- **Cryptographic Chain Integrity**: The cryptographic hash chain (`verify_event_chain()`) remains unbroken with 0 verification errors (`chain_problems = 0`).
- **State Projection Digest Invariance**: Canonical projection digest before and after crash recovery matches byte-for-byte (`digest_equal = true`).
- **Automatic Server Redo**: PostgreSQL automatically initiates redo replay upon restart without administrator intervention (`crash_recovery_logged = true`).

> [!NOTE]
> **Lab Cluster Isolation**: This experiment uses an isolated throwaway cluster on port **5544** under `C:\pg_lab`. It **never** connects to port 5432 or any development database. It uses local trust authentication (no passwords required) and **must be run from a non-administrator (standard user) PowerShell** session.

### How to Run
Run from a standard (non-elevated) PowerShell session:
```powershell
powershell -ExecutionPolicy Bypass -File experiments/recovery/run_experiment7b_crash.ps1
```

Optional parameters:
- `-InflightDays` (default: `3000`)
- `-Keep` (switch to preserve scratch cluster under `C:\pg_lab` for inspection)
- `-LabRoot` (default: `C:\pg_lab`)

### Results Output
- CSV file: `experiments/results/exp7b_crash.csv`
- Log file: `experiments/results/exp7b_recovery_log.txt`

### Results
| acked_ticks | tick_after | events_before | events_after | partial_players_found | chain_problems | digest_equal | crash_recovery_logged | inflight_at_kill | recovery_seconds |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| | | | | | | | | | |

---

## Experiment 7c: Point-in-Time Recovery (PITR)

### Question Answered
How does combining continuous WAL archiving with a physical base backup allow restoring the database to a named restore point created immediately prior to catastrophic human error or schema damage (such as an accidental `DROP TABLE` and `TRUNCATE`)?

### What is Proven
- **Point-in-Time Precision**: WAL replay stops exactly at the named restore point (`before_oops`), completely restoring the dropped `stock` table and truncated `entity_state`.
- **Identical State Reconstruction**: State reconstructed on the standby/restored cluster on port **5545** matches the exact pre-disaster projection digest (`digest_equal = true`, `events_equal = true`, `entity_equal = true`).
- **Event Store Hash Chain Continuity**: Restored event history maintains cryptographic chain integrity with 0 verification errors (`chain_problems = 0`).
- **Disaster Proof & Damage Containment**: While the damaged primary instance on port 5544 remains broken, the restored instance on port 5545 is promoted and fully operational.

> [!NOTE]
> **Lab Cluster Isolation**: This experiment uses isolated throwaway clusters on ports **5544** (primary) and **5545** (restored) under `C:\pg_lab`. It **never** connects to port 5432 or any development database. It uses local trust authentication (no passwords required) and **must be run from a non-administrator (standard user) PowerShell** session.

### How to Run
Run from a standard (non-elevated) PowerShell session:
```powershell
powershell -ExecutionPolicy Bypass -File experiments/recovery/run_experiment7c_pitr.ps1
```

Optional parameters:
- `-Days` (default: `100`)
- `-Keep` (switch to preserve scratch clusters under `C:\pg_lab` for inspection)
- `-LabRoot` (default: `C:\pg_lab`)

### Results Output
- CSV file: `experiments/results/exp7c_pitr.csv`
- Log file: `experiments/results/exp7c_restore_log.txt`

### Results
| base_backup_seconds | events_at_restore_point | events_restored | entity_rows_at_restore_point | entity_rows_restored | stock_present | digest_equal | chain_problems | disaster_confirmed | primary_still_damaged | restore_point_reached | archived_wal_files | restore_seconds |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| | | | | | | | | | | | | |

---

## Experiment 7d: Why the Rebuild is Super-Linear

### Question Answered
Does the super-linear increase in event replay and rebuild time arise from executing generation within a single long-running transaction that accumulates deep MVCC row-version dead-tuple chains?

### Hypothesis
If MVCC row version churn across thousands of consecutive actions inside a single transaction degrades state updates and index scans, splitting generation into multiple smaller transactions (`chunked_large`) will show significantly lower per-day generation overhead (`ms_per_day`) than one large single transaction (`single_large`). If the ratio of per-day cost (`single_large` / `chunked_large`) does not exceed 1.5, the super-linear rebuild cost is caused by other factors (such as recursive query graph traversal in causal closures).

### How to Run
Ensure `$env:PGPASSWORD` is set in your PowerShell session:
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/recovery/run_experiment7d_mvcc.ps1
```

Optional parameters:
- `-SmallDays` (default: `200`)
- `-Days` (default: `800`)
- `-Chunks` (default: `16`)
- `-Database` (default: `butterfly_bench`)
- `-User` (default: `postgres`)

### Results Output
CSV file: `experiments/results/exp7d_mvcc.csv`

### Results
| scenario | days | calls | events | generation_ms | ms_per_day | rebuild_projections_ms |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| single_small | | | | | | |
| single_large | | | | | | |
| chunked_large | | | | | | |

---

## Sanity Self-Test

To verify function logic without running full concurrent benchmarks, run the isolated self-test:
```sql
psql -U postgres -d butterfly -f experiments/lab/selftest.sql
```
This runs 6 validation tests inside a single session wrapped in `BEGIN ... ROLLBACK` without modifying database state.


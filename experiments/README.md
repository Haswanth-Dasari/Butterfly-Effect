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

## Experiment 3: Ask Why Strategies (Causal Lineage & Provenance)

### Question Answered
What is the optimal architectural pattern for causal lineage graph traversals (both upward provenance "Ask Why" and downward impact analysis "Ripple Effect") across varying chain depths and dataset scales, and what are the trade-offs in read latency, write-time trigger overhead, and table storage?

### The 3 Strategies x 2 Directions
1. **Recursive CTE on `event_cause`**: Graph traversal computed dynamically at query time using `WITH RECURSIVE`. Zero write maintenance and minimal storage, but execution time scales with depth.
2. **Transitive Closure Table (`causal_closure`)**: Pre-materialized ancestor-descendant pairs indexed by `(descendant_id, depth)` for upward lookups and `(ancestor_id, depth)` for downward lookups. Fast point/range lookups at the expense of $O(D^2)$ storage and trigger maintenance cost.
3. **Materialized Path Table (`causal_path`)**: Pre-materialized path string `'head/.../tail'` indexed using B-tree with `text_pattern_ops`. Downward impact analysis executes via index prefix scan (`LIKE 'HEAD/%'`), and upward provenance unrolls the delimited path with `unnest() WITH ORDINALITY`.

- **Upward Provenance**: Traverses from effect to cause (Ask Why): `up_cte`, `up_closure`, `up_path`.
- **Downward Impact**: Traverses from cause to effect (Ripple Effect): `down_cte`, `down_closure`, `down_path`.

### Depth Sweep and Size Sweep
- **Depth Sweep**: Evaluates $N = 100,000$ events with chain depths $D \in \{2, 4, 8, 16, 32, 64\}$ to observe latency scaling with graph depth.
- **Size Sweep**: Evaluates fixed depth $D = 8$ across dataset volumes $N \in \{10,000, 100,000, 1,000,000\}$ to observe index and cache behavior with database growth.
- The shared configuration $(100000, 8)$ is tagged `both`.

### Write Cost and Storage Overhead
- **Write Cost**: Evaluates per-operation insertion latency (`bench_causal_write`) with trigger `event_cause_derived` enabled (`write_closure_ms`) versus disabled (`write_base_ms`).
- **Storage**: Measures physical on-disk relation footprints in MB (`pg_total_relation_size`) for `event_cause`, `causal_closure`, and `causal_path`.

### How to Run
Ensure `$env:PGPASSWORD` is set in your PowerShell session:
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/benchmarks/run_experiment3.ps1
```

Optional parameters:
- `-Database` (default: `butterfly_bench`)
- `-User` (default: `postgres`)
- `-Quick` (switch: runs only $(10000, 2)$, $(10000, 8)$, and $(10000, 32)$ with 50 write operations)

### Results Output
CSV file: `experiments/results/exp3_askwhy.csv`

### Results: Upward Provenance Queries
| sweep | events | depth | closure_rows_ok | up_cte_ms | up_closure_ms | up_path_ms |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| depth | 100000 | 2 | | | | |
| depth | 100000 | 4 | | | | |
| both | 100000 | 8 | | | | |
| depth | 100000 | 16 | | | | |
| depth | 100000 | 32 | | | | |
| depth | 100000 | 64 | | | | |
| size | 10000 | 8 | | | | |
| size | 1000000 | 8 | | | | |

### Results: Downward Provenance Queries
| sweep | events | depth | down_cte_ms | down_closure_ms | down_path_ms |
| :--- | :--- | :--- | :--- | :--- | :--- |
| depth | 100000 | 2 | | | |
| depth | 100000 | 4 | | | |
| both | 100000 | 8 | | | |
| depth | 100000 | 16 | | | |
| depth | 100000 | 32 | | | |
| depth | 100000 | 64 | | | |
| size | 10000 | 8 | | | |
| size | 1000000 | 8 | | | |

### Results: Write Cost and Storage Overhead
| sweep | events | depth | write_base_ms | write_closure_ms | edges_mb | closure_mb | path_mb |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| depth | 100000 | 2 | | | | | |
| depth | 100000 | 4 | | | | | |
| both | 100000 | 8 | | | | | |
| depth | 100000 | 16 | | | | | |
| depth | 100000 | 32 | | | | | |
| depth | 100000 | 64 | | | | | |
| size | 10000 | 8 | | | | | |
| size | 1000000 | 8 | | | | | |

---

## Experiment 4: Branching Strategies (Parallel Worlds)

### Question Answered
How do different branch forking strategies scale in creation latency, replayed event volume, state duplication footprint, and subsequent read latency when branching from the head of time versus arbitrary past checkpoints?

### The Three Strategies and Two Scenarios
- **Strategies**:
  1. **`cow` (Copy-on-Write)**: Duplicates live tables directly (`stock`, `entity_state`, `scheduled_effect`). $O(\text{state size})$ creation time, zero events replayed, but restricted exclusively to head-of-time forks.
  2. **`replay` (Full Replay)**: Replays all lineage events from the root baseline snapshot up to the fork event. $O(\text{total lineage history})$ work; deterministic and can fork from any point in history.
  3. **`snapshot_delta` (Snapshot + Delta Replay)**: Restores from the latest snapshot preceding the fork point and replays only the delta events since that snapshot. $O(\text{events since snapshot})$ work, balancing fork speed and time-travel capability.
- **Scenarios**:
  1. **`head` (Latest Event)**: Forks at $H_{\text{HEAD}}$, evaluated across `replay`, `snapshot_delta`, and `cow`.
  2. **`past` (Mid-History Checkpoint)**: Forks at $H_{\text{PAST}}$, evaluated across `replay` and `snapshot_delta` (`cow` is not applicable to historical points).

### How to Run
Ensure `$env:PGPASSWORD` is set in your PowerShell session:
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/benchmarks/run_experiment4.ps1
```

Optional parameters:
- `-Sizes` (default: `100, 400, 1600, 3200` days)
- `-Database` (default: `butterfly_bench`)
- `-User` (default: `postgres`)
- `-Quick` (switch: runs only `-Sizes 100, 400`)

### Results Output
- Forking metrics: `experiments/results/exp4_branching.csv`
- Snapshot storage metrics: `experiments/results/exp4_snapshots.csv`

### Results: Branching Strategies
| days | events | scenario | strategy | fork_ms | replayed_events | digest_ok | child_entity_rows | child_stock_rows | child_state_kb | read_ms |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 100 | | head | replay | | | | | | | |
| 100 | | head | snapshot_delta | | | | | | | |
| 100 | | head | cow | | | | | | | |
| 100 | | past | replay | | | | | | | |
| 100 | | past | snapshot_delta | | | | | | | |
| 400 | | head | replay | | | | | | | |
| 400 | | head | snapshot_delta | | | | | | | |
| 400 | | head | cow | | | | | | | |
| 400 | | past | replay | | | | | | | |
| 400 | | past | snapshot_delta | | | | | | | |
| 1600 | | head | replay | | | | | | | |
| 1600 | | head | snapshot_delta | | | | | | | |
| 1600 | | head | cow | | | | | | | |
| 1600 | | past | replay | | | | | | | |
| 1600 | | past | snapshot_delta | | | | | | | |
| 3200 | | head | replay | | | | | | | |
| 3200 | | head | snapshot_delta | | | | | | | |
| 3200 | | head | cow | | | | | | | |
| 3200 | | past | replay | | | | | | | |
| 3200 | | past | snapshot_delta | | | | | | | |

### Results: Snapshot Storage Overhead
| days | events | snapshots | snapshot_kb | parent_entity_rows |
| :--- | :--- | :--- | :--- | :--- |
| 100 | | | | |
| 400 | | | | |
| 1600 | | | | |
| 3200 | | | | |

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



---

## Experiment 8: Partitioning (partition pruning and cheap retirement)

### Question Answered
If the `event` table were partitioned (by branch, or by tick range), would a query about one parallel village touch only that village's data, and what does it cost to retire an abandoned village?

### Concepts
- **Declarative partitioning** (`PARTITION BY LIST (branch_id)` and `PARTITION BY RANGE (tick)`).
- **Partition pruning**: the planner drops partitions that cannot match; we count the physical tables each plan touches from `EXPLAIN (ANALYZE, FORMAT JSON)`.
- **Maintenance**: `DETACH PARTITION` + `DROP TABLE` versus `DELETE ... WHERE branch_id = ...`.

### Design note (why this is a lab and not a schema change)
`event_cause`, `event_witness` and `snapshot` reference `event(event_id)`. A unique key on a partitioned table has to include the partition key, so `(event_id)` alone could not stay unique. Real adoption means widening those references to `(branch_id, event_id)`. The experiment measures what that change would buy, in the `exp8` schema, without touching game data.

### How to Run
```powershell
$env:PGPASSWORD = "your_db_password"
powershell -ExecutionPolicy Bypass -File experiments/partitioning/run_experiment8.ps1 -Events 400000
```
Linux/macOS: `PGPASSWORD=... ./experiments/partitioning/run_experiment8.sh 400000`

Output: a printed table, a pruning plan, and `experiments/results/exp8_partitioning.csv`.
Expected shape of the result: Q1/Q2 scan **1** partition on `event_by_branch` (vs 1 big table), Q3 scans only the last tick partition on `event_by_tick`, Q4 (no filter) scans all of them, and Q5 shows `DROP PARTITION` taking milliseconds where `DELETE` must visit and then vacuum every row.

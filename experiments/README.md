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

## Sanity Self-Test

To verify function logic without running full concurrent benchmarks, run the isolated self-test:
```sql
psql -U postgres -d butterfly -f experiments/lab/selftest.sql
```
This runs 6 validation tests inside a single session wrapped in `BEGIN ... ROLLBACK` without modifying database state.


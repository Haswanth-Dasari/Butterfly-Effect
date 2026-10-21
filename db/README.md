All SQL lives here. Files are numbered to run in order.

## Local database setup

1. Install PostgreSQL 16+ and ensure `psql` is on `PATH`.
2. Create the database: `psql -U postgres -c "CREATE DATABASE butterfly;"`
3. Apply extensions: `psql -U postgres -d butterfly -f db/schema/00_extensions.sql`
4. Copy `.env.example` to `.env` and fill in your password.

## Applying the schema

Run these commands from the repository root:

```sh
psql -U postgres -d butterfly -f db/schema/_all.sql
psql -U postgres -d butterfly -f db/tests/01_constraint_tests.sql
```

For a clean rebuild, run `db/schema/drop_all.sql` first, then `db/schema/_all.sql`.

## Event store and tamper evidence

For a clean rebuild, run `db/schema/drop_all.sql` first, then `db/schema/_all.sql`. Run both test files from the repository root:

```sh
psql -U postgres -d butterfly -f db/tests/01_constraint_tests.sql
psql -U postgres -d butterfly -f db/tests/02_event_store_tests.sql
```

- The immutability trigger rejects updates, deletes, and truncation of events; the table also revokes `UPDATE`, `DELETE`, and `TRUNCATE` from `PUBLIC`.
- `event_hash` defines the SHA-256 hash formula over the previous hash and canonical event fields.
- Each branch maintains its own chain; an advisory transaction lock serializes inserts within that branch.
- `verify_event_chain()` follows stored hash links and reports the first integrity problem it finds for each branch.

## Seed data

Run these commands from the repository root:

```sh
psql -U postgres -d butterfly -f db/schema/drop_all.sql
psql -U postgres -d butterfly -f db/schema/_all.sql
psql -U postgres -d butterfly -f db/seed/_seed_all.sql
psql -U postgres -d butterfly -f db/tests/01_constraint_tests.sql
psql -U postgres -d butterfly -f db/tests/02_event_store_tests.sql
psql -U postgres -d butterfly -f db/tests/03_seed_tests.sql
```

- Seed is the tick-0 baseline.
- `entity_state.entity_id = actor_id` for now.
- Test files use `test_` names.

## Engine: actions and projections

- `apply_action` records validated player decisions and executes world projections in a single atomic transaction.
- `join_village` registers player actors, records an arrive event, and seeds initial state via triggers.
- Visibility rules determine witness recording: secret (actor only), private (actor and target), or public (all actors).
- Players are constrained to 3 actions per day at the branch's current tick.
- The `event_project` AFTER INSERT trigger updates world stock and versions entity states via `entity_state_at` and `patch_entity_state`.
- Inventory adjustments preserve commodity conservation across stock and entity state rows.

Run tests and the demo from the repository root (note: tests 01, 02 and 04 burn sequence values, so run 03 first on a freshly seeded DB):

```sh
psql -U postgres -d butterfly -f db/tests/03_seed_tests.sql
psql -U postgres -d butterfly -f db/tests/04_engine_tests.sql
psql -U postgres -d butterfly -f db/demo/01_first_evening.sql
```

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

## Rules and cascades

- Rules as JSON: Conditions and effect templates are stored as validated JSON objects in relational text columns.
- Template references: Variable placeholders (`$actor`, `$tick`, `$branch`, `$event`, and `$payload.<key>`) resolve dynamically from triggering events.
- The 4 condition keys: `payload_eq`, `payload_gte`, `stock_below`, and `state_lt` evaluate event payloads and world state.
- Delay vs immediate: Immediate rules (`delay_ticks = 0`) cascade synchronously; delayed rules queue in `scheduled_effect`.
- Depth limit 5: Cascades terminate after 5 immediate hops via `cascade_max_depth()` to avoid infinite loops.
- `advance_day`: Advances branch tick, emits `day_start`, and processes due scheduled effects via `FOR UPDATE SKIP LOCKED`.
- Causal links carry `rule_id`: `event_cause` preserves parent events and rules for recursive "Ask Why" provenance queries.
- Determinism: Serialized event ordering per branch ensures repeatable simulation outcomes and unbroken hash chains.

Run test suites and demos from the repository root:

```sh
psql -U postgres -d butterfly -f db/tests/03_seed_tests.sql
psql -U postgres -d butterfly -f db/tests/04_engine_tests.sql
psql -U postgres -d butterfly -f db/tests/05_rules_tests.sql
psql -U postgres -d butterfly -f db/demo/01_first_evening.sql
psql -U postgres -d butterfly -f db/demo/02_ripple.sql
```

## Game content

### Player actions

The 10 player actions:

| Action | Description | Notes |
| --- | --- | --- |
| `gift` | Transfers an item from actor inventory to target actor's inventory. | Private visibility. Triggers rule 11. |
| `trade` | Buys goods from a place's stock, paying the target actor (seller) and receiving the goods into actor inventory. | Private visibility. Triggers rule 15 if stock falls low. |
| `steal` | Takes goods from a place's stock into actor inventory without paying. | Secret visibility. Triggers rule 1 if stock falls low. |
| `rumor` | Spreads a rumor (`slander`, `praise`, or other) about another actor. | Private visibility. Triggers rules 13 and 14. |
| `build` | Constructs or upgrades a village structure or workshop. | Public visibility. Recorded-only by design (effects come from rules). |
| `hire` | Hires another villager for a wage, setting their employer in entity state. | Private visibility. Deducts wage from actor and credits target actor. |
| `set_price` | Adjusts commodity price at a workplace by fixed amount or percentage. | Public visibility. Triggers rule 2 if price rises >= 20%. |
| `help_harvest` | Assists with harvesting grain at a farm (up to 10 units), increasing farm grain stock. | Private visibility. Triggers rule 12. |
| `sabotage` | Destroys goods directly from a place's stock in secret. | Secret visibility. Triggers rule 10 if stock falls low. (Sabotage destroys goods; steal conserves them.) |
| `feast` | Hosts or attends a community feast in the village. | Public visibility. Recorded-only by design (effects come from rules). |

*Note: `build` and `feast` are recorded-only by design; any gameplay effects arise exclusively through rule triggers.*

### Seed rules (1–15)

| Rule ID | Trigger | Delay | Meaning |
| --- | --- | --- | --- |
| 1 | `steal` | 1 | Low bread stock at bakery (< 40) after theft causes a 25% price increase next day. |
| 2 | `set_price` | 1 | Price increase of >= 20% shuns the culprit and reduces trust by 5 next day. |
| 3 | `state_change` | 0 | When an entity's trust drops below 50, a public 'thief' rumor is immediately sparked. |
| 4 | `day_start` | 0 | Hartley Farm brings in the daily harvest (+25 grain). |
| 5 | `day_start` | 0 | Hartley Farm delivers 20 grain to Tobin's Mill if farm grain stock is at least 20. |
| 6 | `day_start` | 0 | Tobin's Mill grinds 20 grain into 20 flour if mill grain stock is at least 20. |
| 7 | `day_start` | 0 | Tobin's Mill delivers 10 flour to Maren's Bakery if mill flour stock is at least 10. |
| 8 | `day_start` | 0 | Maren's Bakery bakes 10 flour into 20 bread if bakery flour stock is at least 10. |
| 9 | `day_start` | 0 | The village consumes 15 bread from Maren's Bakery if bakery bread stock is at least 15. |
| 10 | `sabotage` | 1 | Damaged stock (< 40) causes a 25% price increase next day. |
| 11 | `gift` | 0 | Receiving a gift leaves the recipient feeling grateful. |
| 12 | `help_harvest` | 0 | Helping harvest increases the helper's trust by 2. |
| 13 | `rumor` | 0 | Slander rumors reduce the subject's trust by 3. |
| 14 | `rumor` | 0 | Praise rumors increase the subject's trust by 3. |
| 15 | `trade` | 1 | Low stock (< 10) after trade causes a 10% price increase next day. |

### Rule engine conditions

In addition to `payload_eq`, `payload_gte`, `stock_below`, and `state_lt`, the engine supports:
- `stock_at_least`: Object `{place_id, item_id, qty}` verifying that the stock row for the specified place, item, and branch has `qty >= given qty`. Evaluates to `false` if no stock row exists.

### Running tests and demos

Run test suites and demos from the repository root:

```sh
psql -U postgres -d butterfly -f db/tests/03_seed_tests.sql
psql -U postgres -d butterfly -f db/tests/04_engine_tests.sql
psql -U postgres -d butterfly -f db/tests/05_rules_tests.sql
psql -U postgres -d butterfly -f db/tests/06_game_tests.sql
psql -U postgres -d butterfly -f db/demo/01_first_evening.sql
psql -U postgres -d butterfly -f db/demo/02_ripple.sql
psql -U postgres -d butterfly -f db/demo/03_a_week.sql
```

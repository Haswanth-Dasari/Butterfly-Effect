# Database Normalization

## Section 1: First draft (unnormalized)

`event_flat(event_id, branch_id, tick, actor_id, actor_name, actor_home, action_type, action_description, payload, prev_hash, hash)`

Candidate key: `event_id`

| Determinant | Attributes functionally determined |
|---|---|
| `event_id` | `branch_id, tick, actor_id, actor_name, actor_home, action_type, action_description, payload, prev_hash, hash` |
| `actor_id` | `actor_name, actor_home` |
| `action_type` | `action_description` |

## Section 2: Anomalies in `event_flat`

- **Update anomaly:** If Maren the baker changes her home, every `event_flat` row for an event performed by Maren must be updated. Missing one row leaves conflicting values for `actor_home`.
- **Insert anomaly:** Maren cannot be recorded as a baker with her home until an event involving her is also available, because actor details exist only in an event row.
- **Delete anomaly:** If the only event involving Maren the baker is deleted, the row containing her name and home is deleted too, losing those actor details.

## Section 3: Decomposition

### Step A: Check for partial dependencies

`event_flat` has a single-attribute candidate key, `event_id`, so there are no partial dependencies on part of a composite key. Therefore, 2NF holds.

### Step B: Identify transitive dependencies

`actor_id -> actor_name, actor_home` and `action_type -> action_description` are transitive dependencies through `event_id`: `event_id` determines both determinants, which in turn determine their descriptive attributes. These violate 3NF. In each case, the determinant is not a superkey of `event_flat`, so BCNF is also violated.

### Step C: Split the relations

Separate actor and action-type details from event rows:

| Relation | Attributes | Key |
|---|---|---|
| `actor` | `actor_id, name, kind, job, home_id` | `actor_id` |
| `action_type` | `action_type, description` | `action_type` |
| `event` | `event_id, branch_id, tick, actor_id, action_type, payload, prev_hash, hash` | `event_id` |

This uses the `actor`, `action_type`, and `event` relations and attributes shown in the ER diagram. The original actor and action-type details are stored with their respective determinants rather than repeated in event rows.

The decomposition is lossless-join: the shared `actor_id` is a key of `actor`, and the shared `action_type` is a key of `action_type`. It is dependency-preserving: the event, actor, and action-type dependencies can each be checked in the resulting relation that contains their attributes.

## Section 4: FD list for the final 14 relations

| Relation | Primary key | Non-trivial FDs | Is every determinant a superkey? |
|---|---|---|---|
| `place` | `place_id` | `place_id -> name, kind, x, y` | Yes |
| `home` | `home_id` | `home_id -> place_id, family_name` | Yes |
| `actor` | `actor_id` | `actor_id -> name, kind, job, home_id` | Yes |
| `item` | `item_id` | `item_id -> name` | Yes |
| `stock` | `(place_id, item_id, branch_id)` | `(place_id, item_id, branch_id) -> qty, price` | Yes |
| `action_type` | `action_type` | `action_type -> description` | Yes |
| `rule` | `rule_id` | `rule_id -> trigger_action_type, condition, effect_template, narrative_template, delay_ticks, is_active` | Yes |
| `branch` | `branch_id` | `branch_id -> name, parent_id, fork_event` | Yes |
| `event` | `event_id` | `event_id -> branch_id, tick, actor_id, action_type, payload, prev_hash, hash` | Yes |
| `event_cause` | `(effect_id, cause_id)` | `(effect_id, cause_id) -> rule_id` | Yes |
| `event_witness` | `(event_id, actor_id)` | No non-trivial FDs | Yes |
| `entity_state` | `(entity_id, branch_id, valid_ticks)` | `(entity_id, branch_id, valid_ticks) -> state` | Yes |
| `snapshot` | `snapshot_id` | `snapshot_id -> branch_id, tick, last_event_id, state` | Yes |
| `scheduled_effect` | `scheduled_id` | `scheduled_id -> branch_id, due_tick, source_event_id, rule_id, payload, processed` | Yes |

## Section 5: BCNF proof

- `place`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `home`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `actor`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `item`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `stock`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `action_type`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `rule`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `branch`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `event`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `event_cause`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `event_witness`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `entity_state`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `snapshot`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.
- `scheduled_effect`: Every non-trivial FD has a determinant that is a (super)key, therefore BCNF.

**Note:** `home.place_id` should also carry a `UNIQUE` constraint because the ER diagram says a place has at most one home; this makes `place_id` a second candidate key and BCNF still holds.

## Section 6: Deliberate trade-offs

| Item | What is redundant or flexible | Why we keep it |
|---|---|---|
| `event.payload` JSONB | Action-specific shape varies per action type | It accommodates each action type's shape without changing the event relation. |
| `entity_state.state` JSONB | Mood, trust and coins are different attributes per entity | It accommodates entity-specific state attributes. |
| `event.prev_hash` and `hash` | Derivable from other rows | Stored for tamper evidence |
| `snapshot.state` | A derived copy of world state | Stored to speed up branch reconstruction |
| `entity_state.entity_id` | Polymorphic, no FK | It can refer to different entity kinds. |

```mermaid
erDiagram
    place {
        int place_id PK
        string name
        string kind
        float x
        float y
    }
    home {
        int home_id PK
        int place_id FK
        string family_name
    }
    actor {
        int actor_id PK
        string name
        string kind
        string job
        int home_id FK
    }
    item {
        int item_id PK
        string name
    }
    stock {
        int place_id PK, FK
        int item_id PK, FK
        int branch_id PK, FK
        int qty
        decimal price
    }
    action_type {
        string action_type PK
        string description
    }
    rule {
        int rule_id PK
        string trigger_action_type FK
        string condition
        string effect_template
        string narrative_template
        int delay_ticks
        boolean is_active
    }
    branch {
        int branch_id PK
        string name
        int parent_id FK
        int fork_event FK
    }
    event {
        int event_id PK
        int branch_id FK
        int tick
        int actor_id FK
        string action_type FK
        jsonb payload
        string prev_hash
        string hash
    }
    event_cause {
        int effect_id PK, FK
        int cause_id PK, FK
        int rule_id FK
    }
    event_witness {
        int event_id PK, FK
        int actor_id PK, FK
    }
    entity_state {
        int entity_id PK
        int branch_id PK, FK
        string valid_ticks PK
        jsonb state
    }
    snapshot {
        int snapshot_id PK
        int branch_id FK
        int tick
        int last_event_id FK
        jsonb state
    }
    scheduled_effect {
        int scheduled_id PK
        int branch_id FK
        int due_tick
        int source_event_id FK
        int rule_id FK
        jsonb payload
        boolean processed
    }

    place ||--o| home : "has"
    home ||--o{ actor : "houses"
    place ||--o{ stock : "stores"
    item ||--o{ stock : "is stocked as"
    branch ||--o{ stock : "has stock"
    action_type ||--o{ rule : "triggers"
    action_type ||--o{ event : "types"
    branch ||--o{ event : "contains"
    branch o|--o{ branch : "parent of"
    event o|--o{ branch : "fork point for"
    actor o|--o{ event : "performs"
    event ||--o{ event_cause : "effect"
    event ||--o{ event_cause : "cause"
    rule o|--o{ event_cause : "explains"
    event ||--o{ event_witness : "has witness"
    actor ||--o{ event_witness : "witnesses"
    branch ||--o{ entity_state : "has state"
    branch ||--o{ snapshot : "has snapshot"
    event ||--o{ snapshot : "last event in"
    event ||--o{ scheduled_effect : "schedules"
    rule ||--o{ scheduled_effect : "defines"
    branch ||--o{ scheduled_effect : "has scheduled effect"
```

## Design decisions

| # | Decision | Reason |
|---|---|---|
| 1 | Changing values (mood, trust, coins held) live in entity_state, not in actor. | This keeps mutable values branch-specific and separate from an actor's identity. |
| 2 | event.payload is JSONB because each action type has a different shape. | JSONB accommodates action-specific fields without changing the event structure. |
| 3 | event_cause is the M:N link between events (causal graph). | It records multiple causes for effects and multiple effects for each cause. |
| 4 | event_witness is the M:N link between events and actors (who knew what). | It captures which actors witnessed each event and which events each actor witnessed. |
| 5 | branch references itself to form a tree of parallel villages. | A parent reference connects each child branch to its originating branch. |
| 6 | stock primary key includes branch_id so each branch has its own stock. | Including branch_id allows the same place and item to have distinct stock records in different branches. |
| 7 | entity_state.entity_id is polymorphic with no FK (it can refer to an actor, place or item). | A single entity identifier supports state for all three entity kinds without a foreign key to only one table. |
| 8 | action_type uses a text primary key because it is a small, stable, readable lookup. | Text keys keep action type references readable and directly tied to stable lookup values. |

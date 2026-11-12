# Who Burned the Mill? — the playable slice, as built

The slice covers **Days 1–4**: the three quiet days, the fire, and the first day of the investigation. It runs on the real database engine; nothing about the story lives in application code.

## What changed from the bible when it met the engine

| Bible | As built | Why |
|---|---|---|
| Rowan Ash, a stranger who arrived 3 months ago | **Rowan Hollis**, foster child of the Hollis family for ten years | The seed village already has a mill helper named Rowan Hollis (actor 11). The protagonist *is* that slot. It also gives Rowan a real motive (the Hollis debt) and makes Giles a foster-brother |
| Wick "placed" Rowan three months ago | Wick has quietly watched Rowan since childhood; the Hollis family was chosen because they were poor and in debt | Stronger and more plausible: a decade-long patient plan |
| E.W. on page 41 | **E.** only | Elspeth *Dunn* is the baker's helper in the seed. "E." can mean Elspeth, Edith or Edric |
| Aldous Thorn, headman | **Garth Thorn** (Thorn Farm) | Matches the seed |
| Maren, Ines, Lily, Giles, Tobin, Wick, Elspeth | Seed villagers (Maren Baker-Dunn, Ines of the inn, Lily Taverner, Giles Hollis, Tobin Marsh, Old Wick, Elspeth Dunn) | Same people, mapped to the existing 30 |
| New characters | Corbin Brand, Sergeant Pike, Corwen, Hesper Brook, Reeve Voss are added by the story seed only; they get a state row (`story_enter` event) only when the story brings them in | The core seed is exactly 30 villagers and its tests assert that |

## How it works

- **A story is data.** `db/scenarios/mystery/slice.json` is the single source: scenes (beats), choices, clues, days, endings, rules. `node db/scenarios/build_seed.mjs mystery` turns it into `db/seed/05_story_mystery.sql` (committed; CI fails if it is out of date).
- **Choices are events; consequences are rules.** `story_choose()` inserts a `story_choice` event; the existing rules engine runs rows like *"when story_choice d1_giles/refuse → set Giles's oil_source = 'wick'"*. Every effect is causally linked and hash-chained like any other event, so Ask Why and rewind work on the story.
- **Fog is real.** Meter changes and the villain's plans are hidden events (no witnesses). Public events (the quarrel, the fire) are witnessed by everyone. A private event (Wick pockets your key) is witnessed only by Wick and Lily, so you can only learn it by asking Lily.
- **A playthrough is a branch.** `start_playthrough()` forks a private village from the original world, so players cannot affect each other.
- **Three engine changes** (all tiny, all additive): `project_event` handles `story_enter`; `rule_matches` understands `state_gte`, `scenario` and `trait`; `apply_action` counts paid story choices against the three-actions-a-day budget.
- **Case Board and Compass are SQL**: `story_board()` and `story_compass()` compute link strength (0–3, `LEAST(3, SUM(weight))`) from the clues the player discovered.

## What is playable

20 scenes, 50 choices, 14 clues, 5 new characters, one death ending (the fire), the Case Board, the optional Compass, the Almanac, an Evening Bell that narrates what changed, and a "To be continued" card after day 4.

## Not built yet (next)

Days 5–12 (Pike, the cleanup nights, the confession, the well, the Moot), the Deduction Board's by-hand clue placement, the Reckoning screen, Second Chance as a story power, and the Drama and Survival stories.

## How to add or change a scene

1. Edit `db/scenarios/mystery/slice.json` (a beat has `options`, each with `effects`: `{entity, add/set}`, `{discover}`, `{event}`, `{enter}`).
2. `node db/scenarios/build_seed.mjs mystery`
3. `scripts/setup.ps1 -Reset` (or run the test suite). The demo server (`npm run mock`) reads the same JSON, so you can try a change without a database.

## Verification status (honest)

- The UI and the demo server were played end to end in a headless browser (start, all four days, the fire, the Case Board, the Compass, the Almanac).
- The **new PostgreSQL code (`db/scenarios/*.sql`, the three engine edits, `db/tests/14_story_slice_tests.sql`) was written but has not been run**: the authoring environment had no PostgreSQL. It was checked by reading it against the existing function signatures. **The first real run is your CI**: push, then open the Actions tab. If suite 14 fails, the log names the exact step; send it over and we fix it.

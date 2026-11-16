# Who Burned the Mill? — the playable slice, as built

The slice covers **Days 1–8**: the three quiet days, the fire, the arrival of the law, the first night the villain acts, and the false confession. It runs on the real database engine; nothing about the story lives in application code.

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

## Opening polish (v1.2)

Playtest feedback: the opening was fine but not gripping, and the rules were not clear without the Almanac. Changes, all data-driven:

- **Cold open:** a flash-forward to the Moot (rope, oak, "they are going to hang you") before day 1, so quiet choices carry dread. Stored in `scenario.cold_open`.
- **Always-visible goal and clock:** "Prove who burned the mill. The Reeve arrives in N days", plus a top-bar countdown and "Case: X of 7 questions have evidence". Stored in `scenario.goal` and `scenario.deadline_day`.
- **First-day coach:** a five-step spotlight (scenes, three actions, meters, end the day, the Almanac). The Almanac stays optional.
- **End-of-day hooks:** each day ends on a question (`story_day.outro`), shown by the Evening Bell.
- **Visible reactions:** the map camera glides to where a scene happens (`story_beat.focus`) and the affected villager speaks in a bubble (`story_option.react_actor`, `react_line`).

## Days 5 to 8 and Wick's nightly agenda

- **Day 5, the Sergeant:** Pike arrives (a day-start rule makes Pike and Corwen `enter` the village) and produces your key. Showing him page 41 gets Elspeth arrested ("E."); the tally book (clue C06) proves "E." was never her.
- **Day 6, the hayloft:** Giles confesses to lighting the shed but says Tobin was already cold, and that a dry voice smelling of walnut sent him. Finding Giles makes him *more dangerous to the villain*. The window Wick says was smashed from outside was smashed from inside.
- **Day 7, the good friend:** Wick visits you. Every honest answer raises Danger. This is the day to protect people, at one action each.
- **Night 7, Wick acts.** One SQL function, `wick_pick_target`, picks the highest-threat witness who is alive and not protected. Threat = a base value plus weights for things *you* did (`story_witness`, `story_witness_factor`). If everyone he would act on is protected he turns on you instead. A trigger on `day_start` calls it (`story_on_day_start`) and records a hidden `wick_night` event; **what each outcome does is ordinary rules**, so the villain's agenda is data and the outcome is causally linked.
- **Day 8, the confession:** a forged note closes the case. Suspicion falls and you are free, and Wick offers a purse. Taking it is the **Convenient Peace** ending; staying keeps you digging in a village that wants you to stop. Marker events (`_night7:ines` etc.) make the right scenes appear for whoever died.
- **Tests:** `db/tests/15_story_nights_tests.sql` proves the targeting rules (default victim, finding Giles redirects Wick, protection saves a life, protecting everyone frames you, pressing Maren without protecting her gets her killed, the hidden decision is hidden, the chain verifies).

## What is playable

41 scenes, 93 choices, 23 clues, 5 new characters, two endings (the fire, Convenient Peace), a villain who acts at night, the Case Board, the optional Compass, the Almanac, an Evening Bell that narrates what changed, and a "To be continued" card after day 4.

## Not built yet (next)

Days 9–12 (Maren's confession, the second cleanup night, the ambush, the well, Wick's offer, the Moot), the Deduction Board's by-hand clue placement, the Reckoning screen, Second Chance as a story power, and the Drama and Survival stories.

## How to add or change a scene

1. Edit `db/scenarios/mystery/slice.json` (a beat has `options`, each with `effects`: `{entity, add/set}`, `{discover}`, `{event}`, `{enter}`).
2. `node db/scenarios/build_seed.mjs mystery`
3. `scripts/setup.ps1 -Reset` (or run the test suite). The demo server (`npm run mock`) reads the same JSON, so you can try a change without a database.

## Verification status (honest)

- The UI and the demo server were played end to end in a headless browser (start, all four days, the fire, the Case Board, the Compass, the Almanac).
- The **new PostgreSQL code (`db/scenarios/*.sql`, the three engine edits, `db/tests/14_story_slice_tests.sql`) was written but has not been run**: the authoring environment had no PostgreSQL. It was checked by reading it against the existing function signatures. **The first real run is your CI**: push, then open the Actions tab. If suite 14 fails, the log names the exact step; send it over and we fix it.

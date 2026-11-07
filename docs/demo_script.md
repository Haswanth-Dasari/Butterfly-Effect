# Demo script (about 12 minutes, three presenters)

Rehearse once with the real database and once with `npm run mock` (the no-database fallback in case of a laptop or Postgres problem on the day).

**Before you start**

1. `scripts/setup.ps1 -Reset`, then `cd backend ; npm start`, open `http://localhost:4000`.
2. Open a second browser window (private mode) so you can play two villagers.
3. Have a `psql` window open on the `butterfly` database, and `docs/screenshots/` ready as a backup.

---

## Part 1 — The story (Person C, 4 min)

| Step | Say | Do |
|---|---|---|
| 1 | "Alderbrook is a village that never forgets. About thirty villagers live here whether or not we watch." | Show the map. Hover a few villagers; point at mood faces above homes. |
| 2 | "I arrive with five coins and take three actions a day." | Join as *Rin*. Point at the three action dots. |
| 3 | "I'll do one bad thing." | **Act → Steal**: Maren's Bakery, bread, 5. Watch the ripple. |
| 4 | "And one harmless thing." | **Rumor → praise Old Wick**. |
| 5 | "Now time moves on." | **End the day**. The map goes dark, the Evening Bell rings and narrates: price rise, whispers, mood shift. |
| 6 | "Notice: *Yesterday you set something in motion.* The village remembers." | Read the delayed-consequence line aloud. |

## Part 2 — The superpowers (Person C then B, 4 min)

| Step | Say | Do |
|---|---|---|
| 7 | "Why did the bread price rise?" | **Chronicle** → click the price rise. The timeline walks back to *your* theft. Point at the butterfly score. |
| 8 | "That is a recursive query over a causal graph." | Switch to `psql`: run `SELECT * FROM ask_why(<event id>);` (see `db/demo/04_ask_why.sql`). |
| 9 | "Look Back: what did the village look like on day 0?" | **Look back** → drag the slider. Prices and moods change on the map. |
| 10 | "What if I had not stolen?" | **Rewind & fork from here** → name it "What if I never stole" → Create. |
| 11 | "Two villages now exist side by side." | **Worlds** → compare. Gold rings mark differing shelves; the table lists them. |
| 12 | "Fog of knowledge." | In the second window, join as *Sam*, open **Chronicle**: Sam can see the price rise but asking why goes cold, because Sam did not witness the theft. |

## Part 3 — The database (Person A and B, 4 min)

| Step | Say | Do (in `psql`) |
|---|---|---|
| 13 | "History cannot be edited." | `UPDATE event SET payload = '{}' WHERE event_id = 1;` → *events are immutable* (see `db/demo/06_peek_and_tamper.sql`). |
| 14 | "Even a superuser who bypasses the trigger is caught." | Run the tamper step from the same demo file, then `SELECT * FROM verify_event_chain();` → first bad row reported. |
| 15 | "Two players, one last loaf." | Show `experiments/results/exp1_last_loaf.csv`: naive sells 900 loaves that do not exist; `FOR UPDATE` and atomic UPDATE are correct. |
| 16 | "Indexes." | Show slide 8: engine write path 146 s → 0.19 s at 1M events. |
| 17 | "Disaster." | `db/demo/07_wipe_and_rebuild.sql`: wipe every projection, rebuild from events, digest equal. |

## Likely questions

- **Why JSONB payload if you normalized?** Each action type has a different shape; it is a documented exception (report §3.3). The fields the engine depends on are validated.
- **Why is `event` not partitioned?** A unique key must include the partition key, so every table referencing `event(event_id)` would need `(branch_id, event_id)`. Experiment 8 measures the benefit separately (report §14).
- **How is fog enforced?** Row-level security on `event` and `entity_state`, plus redaction of the privileged `look_back` / `branch_diff` results in the API.
- **What if two players act on the same tick?** Row locks / atomic conditional updates; Experiment 1 compares the options.

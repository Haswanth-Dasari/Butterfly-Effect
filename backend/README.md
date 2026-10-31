# Butterfly Effect — backend

A thin API. Every write goes through a `SECURITY DEFINER` function already
in the database (`apply_action`, `join_village`, `advance_day`,
`fork_branch`, ...); this layer's only jobs are: authenticate the caller,
set `app.actor_id` with `SET LOCAL` so row-level security applies, and
relay `pg_notify` events to the right browsers over WebSocket. It does not
re-implement any game rule — those all live in `db/procedures`.

## Setup

```powershell
cd backend
npm install
copy .env.example .env
# edit .env: set PG_APP_PASSWORD and PG_GM_PASSWORD to match the roles
# created by db/security/04_app_roles.sql, and set a real SESSION_SECRET
# (openssl rand -hex 32, or any long random string)
```

Before first run, set real passwords on the two login roles (the schema
creates them with the placeholder `change_me`):

```sql
ALTER ROLE butterfly_app PASSWORD 'your_real_password';
ALTER ROLE butterfly_gm PASSWORD 'your_real_password';
```

Run it:

```powershell
npm start
# or: npm run dev   (restarts on file change)
```

## Endpoints

| Method | Path | Auth | Calls |
|---|---|---|---|
| POST | `/api/join` | none | `join_village` (as game master) |
| POST | `/api/actions` | bearer token | `apply_action` (as the player) |
| GET | `/api/ask-why/:eventId` | bearer token | `ask_why` |
| GET | `/api/score/:eventId` | bearer token | `butterfly_score` |
| GET | `/api/mood` | bearer token | `v_village_mood` |
| GET | `/api/evening-bell` | bearer token | `mv_evening_bell` |
| GET | `/api/leaderboard` | bearer token | `mv_leaderboard` |
| GET | `/api/current-tick` | bearer token | `current_tick` |
| GET | `/api/look-back/:tick` | bearer token | `look_back` |
| POST | `/api/advance-day` | *(see below)* | `advance_day` + `refresh_daily_views` (as game master) |
| POST | `/api/fork` | *(see below)* | `fork_branch` (as game master) |
| GET | `/api/branch-diff/:a/:b` | *(see below)* | `branch_diff` (as game master) |
| WS | `/ws?token=...` | bearer token (query param) | live ripple push |

The bearer token comes from `/api/join`'s response. It is a signed
`{actorId, branchId}` claim, not a real account system — the game has
neither passwords nor emails. `apply_action` still independently checks
"not your character" against whatever the token resolves to, so a forged
or guessed `actorId` in a request body is not enough on its own.

**The three game-master endpoints (`advance-day`, `fork`, `branch-diff`)
are not gated on a player's identity on purpose — they are not
per-player actions.** As shipped they are open to any caller, which is
fine for local development and a classroom demo, but not for a public
deployment: add an admin check (an allowlist, a shared admin token, a
real staff login) in front of them before exposing this past localhost.

## Live updates

`db/procedures/13_live_updates.sql`'s trigger calls
`pg_notify('world_updates', ...)` on every event insert, including each
step of a rule cascade. `src/liveUpdates.js` keeps one dedicated
(non-pooled — `LISTEN` is session-scoped) connection open as
`butterfly_gm`, and for each notification checks `event_witness` to decide
which connected browsers actually witnessed that event before pushing it.
A secret `steal` is still never pushed to someone who did not witness it;
the trigger itself never puts the payload in the notification, only
enough to look the row up.

## What this does not do yet

- No account system (see above) — fine for the project's scope, called
  out explicitly so it is not mistaken for an oversight.
- No rate limiting or request validation beyond what is listed above.
- The admin endpoints are open (see above).
- No UI yet — see the repository root for the remaining roadmap.

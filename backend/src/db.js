import pg from 'pg';
import 'dotenv/config';

const { Pool, Client } = pg;

const commonConfig = {
  host: process.env.PGHOST || 'localhost',
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || 'butterfly',
};

// Player-facing pool: logs in as butterfly_app (member of player_role).
// Every query that touches game state goes through one transaction that
// sets app.actor_id with SET LOCAL, so row-level security (db/security/02_rls.sql)
// and the "not your character" check in apply_action both apply.
export const appPool = new Pool({
  ...commonConfig,
  user: process.env.PG_APP_USER || 'butterfly_app',
  password: process.env.PG_APP_PASSWORD,
  max: 10,
});

// Game-master pool: logs in as butterfly_gm (member of game_master_role).
// Used only by the game's own admin/tick endpoints (join_village,
// advance_day, fork_branch, create_snapshot, refresh_daily_views) and by
// reads that are meant to be omniscient (the live-updates relay's witness
// check). Never call this with untrusted, per-player input.
export const gmPool = new Pool({
  ...commonConfig,
  user: process.env.PG_GM_USER || 'butterfly_gm',
  password: process.env.PG_GM_PASSWORD,
  max: 5,
});

/**
 * Run `fn(client)` inside one transaction as the given actor, with
 * app.actor_id set via SET LOCAL (so it is undone at COMMIT/ROLLBACK and
 * never leaks to the next query on a pooled connection).
 * set_config(..., true) is used instead of string-building "SET LOCAL
 * app.actor_id = $1" because SET does not accept bind parameters; this
 * form does, so there is no SQL injection surface even though actorId is
 * already validated as an integer by the route layer.
 */
export async function withAppActor(actorId, fn) {
  const client = await appPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.actor_id', $1, true)", [String(actorId)]);
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/** Run `fn(client)` inside one transaction on the game-master connection. */
export async function withGm(fn) {
  const client = await gmPool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/**
 * A dedicated, non-pooled connection for LISTEN world_updates. LISTEN is
 * session-scoped, so it cannot run through the Pool (a pooled connection
 * can be handed to another query mid-session). Logs in as the game master
 * so the relay can check witnesses for any event, for any player.
 */
export function createListenerClient() {
  return new Client({
    ...commonConfig,
    user: process.env.PG_GM_USER || 'butterfly_gm',
    password: process.env.PG_GM_PASSWORD,
  });
}

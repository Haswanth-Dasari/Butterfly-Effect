import { Router } from 'express';
import { withAppActor, withGm } from '../db.js';
import { requireAuth, issueToken } from '../auth.js';

const router = Router();

// GET /api/ask-why/:eventId — the Chronicle: root cause first, with each
// link's rule narrative. Runs as the player so RLS limits it to events
// they actually witnessed (ask_why itself walks causal_closure, which has
// the same RLS policy).
router.get('/ask-why/:eventId', requireAuth, async (req, res) => {
  const eventId = Number(req.params.eventId);
  if (!Number.isInteger(eventId)) return res.status(400).json({ error: 'eventId must be an integer' });
  try {
    const rows = await withAppActor(req.actor.actorId, async (client) => {
      const r = await client.query('SELECT * FROM ask_why($1)', [eventId]);
      return r.rows;
    });
    res.json(rows);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// GET /api/score/:eventId — the butterfly score (size of the causal subtree).
router.get('/score/:eventId', requireAuth, async (req, res) => {
  const eventId = Number(req.params.eventId);
  if (!Number.isInteger(eventId)) return res.status(400).json({ error: 'eventId must be an integer' });
  try {
    const score = await withAppActor(req.actor.actorId, async (client) => {
      const r = await client.query('SELECT butterfly_score($1) AS score', [eventId]);
      return r.rows[0].score;
    });
    res.json({ eventId, score });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// GET /api/mood — village mood faces. v_village_mood is a deliberate
// public view (section 5.7), so this one is not gated on witnessing, but
// it still runs as the authenticated player for consistency.
router.get('/mood', requireAuth, async (req, res) => {
  const rows = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query('SELECT * FROM v_village_mood WHERE branch_id = $1', [req.actor.branchId]);
    return r.rows;
  });
  res.json(rows);
});

// GET /api/evening-bell — the end-of-day summary (events per tick, player
// actions, cascade events, top score, running total).
router.get('/evening-bell', requireAuth, async (req, res) => {
  const rows = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query('SELECT * FROM mv_evening_bell WHERE branch_id = $1 ORDER BY tick', [req.actor.branchId]);
    return r.rows;
  });
  res.json(rows);
});

// GET /api/leaderboard — the butterfly-score ranking.
router.get('/leaderboard', requireAuth, async (req, res) => {
  const rows = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query(
      'SELECT * FROM mv_leaderboard WHERE branch_id = $1 ORDER BY leaderboard_rank, actor_id', [req.actor.branchId]);
    return r.rows;
  });
  res.json(rows);
});

// GET /api/current-tick
router.get('/current-tick', requireAuth, async (req, res) => {
  const tick = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query('SELECT current_tick($1) AS tick', [req.actor.branchId]);
    return r.rows[0].tick;
  });
  res.json({ branchId: req.actor.branchId, tick });
});

// GET /api/look-back/:tick — the time slider. Runs as the player: look_back
// forks and discards internally (db/procedures/12_lookback.sql), and the
// state it returns is whatever that player's own branch looked like, not a
// peek into anyone else's secrets.
router.get('/look-back/:tick', requireAuth, async (req, res) => {
  const tick = Number(req.params.tick);
  if (!Number.isInteger(tick) || tick < 0) return res.status(400).json({ error: 'tick must be a non-negative integer' });
  try {
    const state = await withAppActor(req.actor.actorId, async (client) => {
      const r = await client.query('SELECT look_back($1, $2) AS state', [req.actor.branchId, tick]);
      return r.rows[0].state;
    });
    res.json(redactWorld(state, req.actor.actorId));
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

/**
 * look_back and branch_diff are SECURITY DEFINER / game-master functions, so they
 * see everyone's private state. Fog of knowledge is enforced here for what leaves
 * the server: other villagers expose only their public mood; only your own coins,
 * trust and inventory are returned; pending (not-yet-happened) effects are hidden.
 */
function redactWorld(state, me) {
  if (!state) return state;
  return {
    stock: state.stock ?? [],
    entities: (state.entities ?? []).map((e) => ({
      entity_id: e.entity_id,
      state: e.entity_id === me ? e.state : { mood: e.state?.mood ?? null },
    })),
    pending: [],
  };
}

function redactDiffRow(row, me, names) {
  if (row.kind !== 'entity') return row;
  const strip = (txt) => {
    if (!txt) return txt;
    try { return JSON.stringify({ mood: JSON.parse(txt).mood ?? null }); } catch { return null; }
  };
  return names.get(row.key) === me ? row : { ...row, a_value: strip(row.a_value), b_value: strip(row.b_value) };
}

// --- Shared-village controls. These call game-master functions, but they are
// player-facing features in the story ("end the day", "rewind"), so they now
// require a valid session token. advance-day is limited to the caller's own
// branch. Set ADMIN_TOKEN in .env to additionally require `x-admin-token`
// on advance-day for a locked-down deployment (see backend/README.md).

function adminOk(req) {
  const need = process.env.ADMIN_TOKEN;
  return !need || req.headers['x-admin-token'] === need;
}

// POST /api/advance-day { branchId? }  (defaults to the caller's branch)
router.post('/advance-day', requireAuth, async (req, res) => {
  if (!adminOk(req)) return res.status(403).json({ error: 'admin token required' });
  const branchId = req.body?.branchId === undefined ? req.actor.branchId : Number(req.body.branchId);
  if (!Number.isInteger(branchId)) return res.status(400).json({ error: 'branchId must be an integer' });
  if (branchId !== req.actor.branchId) return res.status(403).json({ error: 'you can only end the day in your own village' });
  try {
    const tick = await withGm(async (client) => {
      const r = await client.query('SELECT advance_day($1) AS tick', [branchId]);
      await client.query('SELECT refresh_daily_views()');
      return r.rows[0].tick;
    });
    res.json({ branchId, tick });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// POST /api/fork { tick | forkEvent, name, strategy? }
// Rewind and Parallel Villages. The parent is the caller's own branch. Players
// think in days, not event ids, so `tick` is accepted and resolved to the last
// event of that day on the branch; `forkEvent` is still accepted for the API.
router.post('/fork', requireAuth, async (req, res) => {
  const { tick, forkEvent, name } = req.body || {};
  const strategy = req.body?.strategy || 'snapshot_delta';
  const parent = req.actor.branchId;
  if (typeof name !== 'string' || !name.trim()) return res.status(400).json({ error: 'name is required' });
  if (!['replay', 'snapshot_delta', 'cow'].includes(strategy)) return res.status(400).json({ error: 'unknown strategy' });
  if (!Number.isInteger(tick) && !Number.isInteger(forkEvent)) {
    return res.status(400).json({ error: 'tick or forkEvent is required' });
  }
  try {
    const out = await withGm(async (client) => {
      let ev = forkEvent;
      if (!Number.isInteger(ev)) {
        const r = await client.query(
          'SELECT max(event_id) AS id FROM event WHERE branch_id = $1 AND tick <= $2', [parent, tick]);
        ev = r.rows[0].id === null ? null : Number(r.rows[0].id);
      }
      if (ev === null || ev === undefined) throw new Error('nothing happened on or before that day in this village');
      const r = await client.query('SELECT fork_branch($1, $2, $3, $4) AS branch_id', [parent, ev, name.trim().slice(0, 60), strategy]);
      return { childBranchId: r.rows[0].branch_id, forkEvent: Number(ev) };
    });
    res.json(out);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// GET /api/branches — every village in this world, with its parent and fork point.
router.get('/branches', requireAuth, async (req, res) => {
  const rows = await withGm(async (client) => {
    const r = await client.query(`
      SELECT b.branch_id, b.name, b.parent_id, b.fork_event, current_tick(b.branch_id) AS tick,
             EXISTS (SELECT 1 FROM entity_state es
                     WHERE es.branch_id = b.branch_id AND es.entity_id = $1) AS you_live_here
      FROM branch b
      WHERE b.name NOT LIKE 'lookback\_%'
      ORDER BY b.branch_id`, [req.actor.actorId]);
    return r.rows;
  });
  res.json(rows);
});

// POST /api/switch-branch { branchId } — same villager, another village.
// A new token is issued only if the villager actually exists on that branch.
router.post('/switch-branch', requireAuth, async (req, res) => {
  const branchId = Number(req.body?.branchId);
  if (!Number.isInteger(branchId)) return res.status(400).json({ error: 'branchId must be an integer' });
  const ok = await withGm(async (client) => {
    const r = await client.query(
      'SELECT 1 FROM entity_state WHERE branch_id = $1 AND entity_id = $2 LIMIT 1', [branchId, req.actor.actorId]);
    return r.rowCount > 0;
  });
  if (!ok) return res.status(404).json({ error: 'you have not arrived in that village (it was forked before you came)' });
  res.json({ token: issueToken(req.actor.actorId, branchId), actorId: req.actor.actorId, branchId });
});

// GET /api/branch-diff/:a/:b — side-by-side comparison of two villages.
router.get('/branch-diff/:a/:b', requireAuth, async (req, res) => {
  const a = Number(req.params.a);
  const b = Number(req.params.b);
  if (!Number.isInteger(a) || !Number.isInteger(b)) return res.status(400).json({ error: 'a and b must be integers' });
  try {
    const diff = await withGm(async (client) => {
      const r = await client.query('SELECT * FROM branch_diff($1, $2)', [a, b]);
      const nm = await client.query('SELECT name, actor_id FROM actor');
      const names = new Map(nm.rows.map((x) => [x.name, x.actor_id]));
      return r.rows.map((row) => redactDiffRow(row, req.actor.actorId, names));
    });
    res.json(diff);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

export default router;

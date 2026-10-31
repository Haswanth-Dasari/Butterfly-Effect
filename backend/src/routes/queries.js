import { Router } from 'express';
import { withAppActor, withGm } from '../db.js';
import { requireAuth } from '../auth.js';

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
    const r = await client.query('SELECT * FROM v_village_mood');
    return r.rows;
  });
  res.json(rows);
});

// GET /api/evening-bell — the end-of-day summary (events per tick, player
// actions, cascade events, top score, running total).
router.get('/evening-bell', requireAuth, async (req, res) => {
  const rows = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query('SELECT * FROM mv_evening_bell ORDER BY tick');
    return r.rows;
  });
  res.json(rows);
});

// GET /api/leaderboard — the butterfly-score ranking.
router.get('/leaderboard', requireAuth, async (req, res) => {
  const rows = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query('SELECT * FROM mv_leaderboard ORDER BY rank');
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
    res.json(state);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// --- Game-master endpoints below: not gated on a specific player's
// identity, so they are left unauthenticated-by-actor on purpose, but a
// real deployment should put these behind a separate admin check (an
// allowlist, a shared admin token, etc.) before going live — they are not
// safe to expose to every visitor as-is.

// POST /api/advance-day { branchId }
router.post('/advance-day', async (req, res) => {
  const branchId = Number(req.body?.branchId);
  if (!Number.isInteger(branchId)) return res.status(400).json({ error: 'branchId must be an integer' });
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

// POST /api/fork { branchId, forkEvent, name, strategy }
router.post('/fork', async (req, res) => {
  const { branchId, forkEvent, name, strategy } = req.body || {};
  if (!Number.isInteger(branchId) || !Number.isInteger(forkEvent) || !name || !strategy) {
    return res.status(400).json({ error: 'branchId, forkEvent, name and strategy are required' });
  }
  try {
    const childBranchId = await withGm(async (client) => {
      const r = await client.query('SELECT fork_branch($1, $2, $3, $4) AS branch_id', [branchId, forkEvent, name, strategy]);
      return r.rows[0].branch_id;
    });
    res.json({ childBranchId });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// GET /api/branch-diff/:a/:b
router.get('/branch-diff/:a/:b', async (req, res) => {
  const a = Number(req.params.a);
  const b = Number(req.params.b);
  if (!Number.isInteger(a) || !Number.isInteger(b)) return res.status(400).json({ error: 'a and b must be integers' });
  try {
    const diff = await withGm(async (client) => {
      const r = await client.query('SELECT branch_diff($1, $2) AS diff', [a, b]);
      return r.rows[0].diff;
    });
    res.json(diff);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

export default router;

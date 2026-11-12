import { Router } from 'express';
import { withAppActor, withGm } from '../db.js';
import { requireAuth, issueToken } from '../auth.js';

const router = Router();

// Stories that exist now, and the ones that are planned (shown as locked cards in the UI).
const COMING_SOON = [
  { key: 'drama', title: 'The Newcomer\u2019s Inheritance', genre: 'Drama', tagline: 'A failing farm, a secret debt, and three families who each want something.', locked: true },
  { key: 'survival', title: 'The Long Winter', genre: 'Survival', tagline: 'The harvest failed. The granary will not last until spring. Someone has to decide who eats.', locked: true },
];

// GET /api/story/scenarios — public: the story shelf.
router.get('/story/scenarios', async (req, res) => {
  const rows = await withGm(async (client) => {
    const r = await client.query(
      `SELECT scenario_key AS key, title, genre, tagline, slice_end_day FROM scenario ORDER BY scenario_key`);
    return r.rows.map((s) => ({ ...s, locked: false }));
  });
  res.json([...rows, ...COMING_SOON]);
});

// POST /api/story/start { scenario, trait, guided, pronouns } — public: begins a private playthrough.
router.post('/story/start', async (req, res) => {
  const { scenario, trait, guided, pronouns } = req.body || {};
  if (typeof scenario !== 'string' || !['kind', 'sharp', 'quiet'].includes(trait)) {
    return res.status(400).json({ error: 'scenario and trait (kind|sharp|quiet) are required' });
  }
  const pr = ['she', 'he', 'they'].includes(pronouns) ? pronouns : 'they';
  try {
    const out = await withGm(async (client) => {
      const r = await client.query('SELECT start_playthrough($1, $2, $3, $4) AS r', [scenario, trait, !!guided, pr]);
      return r.rows[0].r;
    });
    res.json({ token: issueToken(out.actor_id, out.branch_id), actorId: out.actor_id, branchId: out.branch_id });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// GET /api/story/scene — everything for one screen of the story (scenes on offer, meters, history).
router.get('/story/scene', requireAuth, async (req, res) => {
  const { actorId, branchId } = req.actor;
  const scene = await withAppActor(actorId, async (client) => {
    const r = await client.query('SELECT story_scene($1, $2) AS s', [branchId, actorId]);
    return r.rows[0].s;
  });
  if (!scene) return res.status(404).json({ error: 'no story in progress' });
  res.json(scene);
});

// POST /api/story/choose { beat, option }
router.post('/story/choose', requireAuth, async (req, res) => {
  const { beat, option } = req.body || {};
  if (typeof beat !== 'string' || typeof option !== 'string') return res.status(400).json({ error: 'beat and option are required' });
  const { actorId, branchId } = req.actor;
  try {
    const out = await withAppActor(actorId, async (client) => {
      const r = await client.query('SELECT story_choose($1, $2, $3, $4) AS r', [branchId, actorId, beat, option]);
      return r.rows[0].r;
    });
    res.json(out);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// GET /api/story/board — the player's case board (seven links and the clues found).
router.get('/story/board', requireAuth, async (req, res) => {
  const { actorId, branchId } = req.actor;
  const board = await withAppActor(actorId, async (client) => (await client.query('SELECT story_board($1, $2) AS b', [branchId, actorId])).rows[0].b);
  res.json(board);
});

// GET /api/story/compass — guidance (only if the player turned it on).
router.get('/story/compass', requireAuth, async (req, res) => {
  const { actorId, branchId } = req.actor;
  const c = await withAppActor(actorId, async (client) => (await client.query('SELECT story_compass($1, $2) AS c', [branchId, actorId])).rows[0].c);
  res.json(c);
});

// POST /api/story/guidance { guided } — switch the Compass on or off at any time.
router.post('/story/guidance', requireAuth, async (req, res) => {
  const { actorId, branchId } = req.actor;
  const guided = !!req.body?.guided;
  await withGm(async (client) => {
    await client.query('UPDATE playthrough SET guided = $3 WHERE branch_id = $1 AND actor_id = $2', [branchId, actorId, guided]);
  });
  res.json({ guided });
});

export default router;

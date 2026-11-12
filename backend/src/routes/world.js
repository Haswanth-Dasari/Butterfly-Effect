import { Router } from 'express';
import { withAppActor } from '../db.js';
import { requireAuth } from '../auth.js';

const router = Router();

const PLAYER_ACTIONS = [
  'gift', 'trade', 'steal', 'rumor', 'build',
  'hire', 'set_price', 'help_harvest', 'sabotage', 'feast',
];

// Where a villager spends the day. Everything here is derived from rows the
// player role may already read (place, home, actor); nothing is hard-coded by id.
function workplaceFor(actor, home, places) {
  const byKind = (k) => places.find((p) => p.kind === k);
  switch (actor.job) {
    case 'baker':
    case 'baker_helper': return byKind('bakery');
    case 'miller':
    case 'mill_helper': return byKind('mill');
    case 'innkeeper':
    case 'drover': return byKind('inn');
    case 'well_keeper': return byKind('well');
    case 'farmer': {
      const fam = (home?.family_name || '').toLowerCase();
      return places.find((p) => p.kind === 'farm' && p.name.toLowerCase().startsWith(fam)) || null;
    }
    case 'labourer': return byKind('market');
    default: return null;
  }
}

// GET /api/places — every place on the map, with this branch's stock.
router.get('/places', requireAuth, async (req, res) => {
  const out = await withAppActor(req.actor.actorId, async (client) => {
    const p = await client.query('SELECT place_id, name, kind, x, y FROM place ORDER BY place_id');
    const s = await client.query(
      `SELECT s.place_id, s.item_id, i.name AS item_name, s.qty, s.price::float8 AS price
         FROM stock s JOIN item i USING (item_id)
        WHERE s.branch_id = $1 ORDER BY s.place_id, s.item_id`, [req.actor.branchId]);
    return p.rows.map((pl) => ({ ...pl, stock: s.rows.filter((r) => r.place_id === pl.place_id) }));
  });
  res.json(out);
});

// GET /api/actors — everyone in the village, their home, workplace and public mood.
// Coins/trust/inventory are private (RLS) and are deliberately NOT included.
router.get('/actors', requireAuth, async (req, res) => {
  const out = await withAppActor(req.actor.actorId, async (client) => {
    const places = (await client.query('SELECT place_id, name, kind, x, y FROM place ORDER BY place_id')).rows;
    const homes = (await client.query('SELECT home_id, place_id, family_name FROM home')).rows;
    const mood = (await client.query('SELECT actor_id, mood FROM v_village_mood WHERE branch_id = $1', [req.actor.branchId])).rows;
    const actors = (await client.query('SELECT actor_id, name, kind, job, home_id FROM actor ORDER BY actor_id')).rows;
    const moodOf = new Map(mood.map((m) => [m.actor_id, m.mood]));
    const market = places.find((p) => p.kind === 'market');
    return actors
      // a villager only exists in a village once it has a mood row there
      .filter((a) => moodOf.has(a.actor_id))
      .map((a) => {
        const home = homes.find((h) => h.home_id === a.home_id) || null;
        const homePlace = home ? places.find((p) => p.place_id === home.place_id) : market;
        const work = workplaceFor(a, home, places);
        return {
          actor_id: a.actor_id, name: a.name, kind: a.kind, job: a.job, home_id: a.home_id,
          family: home?.family_name || null,
          home_place_id: homePlace?.place_id ?? null,
          work_place_id: work?.place_id ?? null,
          place_id: (work || homePlace)?.place_id ?? null,
          x: (work || homePlace)?.x ?? 50, y: (work || homePlace)?.y ?? 50,
          home_x: homePlace?.x ?? 50, home_y: homePlace?.y ?? 50,
          mood: moodOf.get(a.actor_id) ?? null,
        };
      });
  });
  res.json(out);
});

// GET /api/me — your own private state and how many actions you have left today.
router.get('/me', requireAuth, async (req, res) => {
  const { actorId, branchId } = req.actor;
  const out = await withAppActor(actorId, async (client) => {
    const a = await client.query('SELECT name FROM actor WHERE actor_id = $1', [actorId]);
    if (a.rowCount === 0) return null;
    const st = await client.query(
      `SELECT state FROM entity_state
        WHERE entity_id = $1 AND branch_id = $2 AND upper_inf(valid_ticks)`, [actorId, branchId]);
    const tick = (await client.query('SELECT current_tick($1) AS t', [branchId])).rows[0].t;
    const used = await client.query(
      `SELECT count(*)::int AS n FROM event
        WHERE branch_id = $1 AND actor_id = $2 AND tick = $3
          AND (action_type = ANY($4::text[]) OR (action_type = 'story_choice' AND payload @> '{"cost":1}'::jsonb))`,
      [branchId, actorId, tick, PLAYER_ACTIONS]);
    const n = used.rows[0].n;
    return {
      actorId, branchId, name: a.rows[0].name, tick,
      state: st.rows[0]?.state ?? null,
      actionsUsedToday: n,
      actionsRemainingToday: Math.max(0, 3 - n),
    };
  });
  if (!out) return res.status(404).json({ error: 'unknown villager' });
  res.json(out);
});

// GET /api/items and /api/action-types — reference data for the forms.
router.get('/items', requireAuth, async (req, res) => {
  const rows = await withAppActor(req.actor.actorId, async (c) =>
    (await c.query('SELECT item_id, name FROM item ORDER BY item_id')).rows);
  res.json(rows);
});

router.get('/action-types', requireAuth, (req, res) => res.json(PLAYER_ACTIONS));

// GET /api/events?limit=40&since=<event_id> — events this villager witnessed (RLS
// does the filtering; there is no WHERE clause for visibility here on purpose),
// newest first, with payload so the client can narrate them.
router.get('/events', requireAuth, async (req, res) => {
  const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 40));
  const since = Number.isInteger(Number(req.query.since)) ? Number(req.query.since) : 0;
  const rows = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query(
      `SELECT e.event_id::text AS event_id, e.tick, e.actor_id, a.name AS actor_name,
              e.action_type, e.payload,
              EXISTS (SELECT 1 FROM event_cause ec WHERE ec.effect_id = e.event_id) AS is_cascade
         FROM event e LEFT JOIN actor a ON a.actor_id = e.actor_id
        WHERE e.branch_id = $1 AND e.event_id > $2
        ORDER BY e.event_id DESC LIMIT $3`, [req.actor.branchId, since, limit]);
    return r.rows;
  });
  res.json(rows);
});

// GET /api/event/:id — one witnessed event (payload included). 404 if not witnessed.
router.get('/event/:id', requireAuth, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'id must be an integer' });
  const rows = await withAppActor(req.actor.actorId, async (client) => {
    const r = await client.query(
      `SELECT e.event_id::text AS event_id, e.tick, e.branch_id, e.actor_id, a.name AS actor_name,
              e.action_type, e.payload
         FROM event e LEFT JOIN actor a ON a.actor_id = e.actor_id WHERE e.event_id = $1`, [id]);
    return r.rows;
  });
  if (rows.length === 0) return res.status(404).json({ error: 'nothing comes to mind' });
  res.json(rows[0]);
});

export default router;

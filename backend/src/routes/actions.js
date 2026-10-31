import { Router } from 'express';
import { withAppActor } from '../db.js';
import { requireAuth } from '../auth.js';

const router = Router();

const PLAYER_ACTIONS = new Set([
  'gift', 'trade', 'steal', 'rumor', 'build',
  'hire', 'set_price', 'help_harvest', 'sabotage', 'feast',
]);

// POST /api/actions { action, payload, visibility? }
// The one endpoint that writes to the world on a player's behalf. All the
// real validation (own actions only, 3-per-day, payload shape per action,
// conservation) lives in apply_action itself; this route's job is only to
// authenticate the caller and set app.actor_id, never to re-implement
// rules the database already enforces.
router.post('/actions', requireAuth, async (req, res) => {
  const { action, payload, visibility } = req.body || {};
  if (!PLAYER_ACTIONS.has(action)) {
    return res.status(400).json({ error: `not a player action: ${action}` });
  }
  if (!payload || typeof payload !== 'object') {
    return res.status(400).json({ error: 'payload must be an object' });
  }
  const { actorId, branchId } = req.actor;
  try {
    const eventId = await withAppActor(actorId, async (client) => {
      const { rows } = await client.query(
        'SELECT apply_action($1, $2, $3, $4::jsonb, $5) AS event_id',
        [branchId, actorId, action, JSON.stringify(payload), visibility || null]
      );
      return rows[0].event_id;
    });
    res.json({ eventId });
  } catch (err) {
    // apply_action's messages (e.g. "no actions left today", "not your
    // character", a rule or constraint violation) are written to be
    // read by a human; pass them through rather than wrapping them.
    res.status(400).json({ error: err.message });
  }
});

export default router;

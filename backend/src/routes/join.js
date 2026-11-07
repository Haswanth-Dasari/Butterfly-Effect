import { Router } from 'express';
import { withGm } from '../db.js';
import { issueToken } from '../auth.js';

const router = Router();

// POST /api/join { name, branchId? }
// Onboards a new player. join_village is a game-master-only function
// (table 1.3 / section 12.3 of the handoff), so this is the one place the
// backend uses the gm connection on behalf of an anonymous visitor rather
// than an authenticated one — there is no actor yet to authenticate as.
router.post('/join', async (req, res) => {
  const { name, branchId } = req.body || {};
  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    return res.status(400).json({ error: 'name is required' });
  }
  const branch = Number.isInteger(branchId) ? branchId : 1; // 1 = main, per the seed
  try {
    const { rows } = await withGm((client) =>
      client.query('SELECT join_village($1, $2) AS actor_id', [branch, name.trim()])
    );
    const actorId = rows[0].actor_id;
    const token = issueToken(actorId, branch);
    res.json({ token, actorId, branchId: branch });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

export default router;

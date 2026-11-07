import jwt from 'jsonwebtoken';
import 'dotenv/config';

const SECRET = process.env.SESSION_SECRET;

/**
 * A session token is just a signed claim of {actorId, branchId}. It is NOT
 * a substitute for a real account system (no password, no email) — the
 * game has no such concept yet (see the handoff doc, section 10: no
 * friendship graph, no identity beyond actor). It exists only so a browser
 * tab can reconnect as "the same villager" without the backend trusting a
 * client-supplied actorId outright: apply_action independently re-checks
 * "not your character" against whatever this token resolves to.
 */
export function issueToken(actorId, branchId) {
  return jwt.sign({ actorId, branchId }, SECRET, { expiresIn: '30d' });
}

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'missing bearer token' });
  try {
    const claim = jwt.verify(token, SECRET);
    req.actor = { actorId: claim.actorId, branchId: claim.branchId };
    next();
  } catch {
    return res.status(401).json({ error: 'invalid or expired token' });
  }
}

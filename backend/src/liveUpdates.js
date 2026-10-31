import { WebSocketServer } from 'ws';
import jwt from 'jsonwebtoken';
import 'dotenv/config';
import { createListenerClient, gmPool } from './db.js';

/**
 * Relays db/procedures/13_live_updates.sql's pg_notify('world_updates', ...)
 * to connected browsers over WebSocket — but only to a browser whose actor
 * actually witnessed that event. The trigger itself does not decide
 * visibility (see the comment in that file); this is where that decision
 * gets made, by checking event_witness directly on the game-master
 * connection (which can see every witness row, bypassing RLS, precisely
 * so it can decide who else gets to see it).
 */
export function attachLiveUpdates(httpServer) {
  const wss = new WebSocketServer({ server: httpServer, path: '/ws' });

  /** @type {Map<import('ws').WebSocket, {actorId: number, branchId: number}>} */
  const clients = new Map();

  wss.on('connection', (socket, req) => {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    try {
      const claim = jwt.verify(token, process.env.SESSION_SECRET);
      clients.set(socket, { actorId: claim.actorId, branchId: claim.branchId });
    } catch {
      socket.close(4001, 'invalid or missing token');
      return;
    }
    socket.on('close', () => clients.delete(socket));
  });

  const listener = createListenerClient();
  listener.connect().then(() => listener.query('LISTEN world_updates'));

  listener.on('notification', async (msg) => {
    let update;
    try {
      update = JSON.parse(msg.payload);
    } catch {
      return;
    }
    const { branch_id, event_id } = update;

    // Find which of the currently connected actors, on this branch,
    // witnessed this event. One query for every connected client avoids an
    // N+1 against the pool; it is still cheap because event_witness is
    // indexed on (actor_id, event_id) (db/security's RLS index).
    const candidateActorIds = [...clients.values()]
      .filter((c) => c.branchId === branch_id)
      .map((c) => c.actorId);
    if (candidateActorIds.length === 0) return;

    const { rows } = await gmPool.query(
      'SELECT actor_id FROM event_witness WHERE event_id = $1 AND actor_id = ANY($2::int[])',
      [event_id, candidateActorIds]
    );
    const witnessed = new Set(rows.map((r) => r.actor_id));
    if (witnessed.size === 0) return;

    const payload = JSON.stringify({ type: 'event', ...update });
    for (const [socket, claim] of clients) {
      if (claim.branchId === branch_id && witnessed.has(claim.actorId) && socket.readyState === socket.OPEN) {
        socket.send(payload);
      }
    }
  });

  listener.on('error', (err) => {
    // eslint-disable-next-line no-console
    console.error('live-updates listener error', err);
  });

  return wss;
}

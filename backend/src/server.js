import express from 'express';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import 'dotenv/config';

import joinRouter from './routes/join.js';
import actionsRouter from './routes/actions.js';
import queriesRouter from './routes/queries.js';
import worldRouter from './routes/world.js';
import { attachLiveUpdates } from './liveUpdates.js';
import { appPool } from './db.js';

if (!process.env.SESSION_SECRET || process.env.SESSION_SECRET.length < 8) {
  console.error('SESSION_SECRET is missing or too short. Set a long random value in backend/.env');
  process.exit(1);
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '32kb' }));

// Conservative security headers for a game that serves its own static UI.
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Content-Security-Policy',
    "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " +
    "script-src 'self'; connect-src 'self' ws: wss:; font-src 'self'; frame-ancestors 'none'");
  next();
});

// Tiny fixed-window rate limiter (per IP): enough to stop an accidental hot
// loop or a trivial flood without adding a dependency.
const WINDOW_MS = 10_000;
const MAX_REQ = Number(process.env.RATE_LIMIT_PER_10S || 200);
const hits = new Map();
app.use('/api', (req, res, next) => {
  const now = Date.now();
  const key = req.ip;
  const rec = hits.get(key);
  if (!rec || now - rec.start > WINDOW_MS) { hits.set(key, { start: now, n: 1 }); return next(); }
  rec.n += 1;
  if (rec.n > MAX_REQ) return res.status(429).json({ error: 'the village needs a moment — slow down' });
  next();
});
setInterval(() => { const t = Date.now(); for (const [k, v] of hits) if (t - v.start > WINDOW_MS) hits.delete(k); }, 30_000).unref();

app.get('/api/health', async (req, res) => {
  try { await appPool.query('SELECT 1'); res.json({ ok: true, db: true }); }
  catch { res.status(503).json({ ok: false, db: false }); }
});
app.use('/api', joinRouter);
app.use('/api', actionsRouter);
app.use('/api', queriesRouter);
app.use('/api', worldRouter);
app.use('/api', (req, res) => res.status(404).json({ error: 'no such endpoint' }));

// The UI is plain static files (no build step): npm start is the whole app.
const here = path.dirname(fileURLToPath(import.meta.url));
app.use(express.static(path.resolve(here, '../../frontend'), { extensions: ['html'] }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'internal error' });
});

const server = http.createServer(app);
attachLiveUpdates(server);

const port = Number(process.env.PORT || 4000);
server.listen(port, () => {
  console.log(`Butterfly Effect listening on http://localhost:${port}`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => { server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 2000).unref(); });
}

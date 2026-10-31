import express from 'express';
import http from 'node:http';
import 'dotenv/config';

import joinRouter from './routes/join.js';
import actionsRouter from './routes/actions.js';
import queriesRouter from './routes/queries.js';
import { attachLiveUpdates } from './liveUpdates.js';

const app = express();
app.use(express.json());

app.get('/api/health', (req, res) => res.json({ ok: true }));
app.use('/api', joinRouter);
app.use('/api', actionsRouter);
app.use('/api', queriesRouter);

// Centralized error handler: anything a route didn't catch becomes a 500
// with no internal detail leaked (the SQL error text from apply_action and
// friends is already handled per-route, since those are meant to reach
// the player).
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'internal error' });
});

const server = http.createServer(app);
attachLiveUpdates(server);

const port = Number(process.env.PORT || 4000);
server.listen(port, () => {
  console.log(`Butterfly Effect backend listening on :${port}`);
});

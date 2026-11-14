// Butterfly Effect — DEMO / UI-DEVELOPMENT SERVER (no database needed).
//
// This is NOT the real backend. It re-implements the same HTTP + WebSocket
// contract in memory (a simplified rules engine, fog of knowledge, forks,
// look-back) so the UI can be developed, demoed or screenshotted on a laptop
// without PostgreSQL. The seed data is parsed straight from db/seed/*.sql so
// the village matches the real one. The real game logic lives in db/procedures.
//
//   cd backend && npm install && npm run mock      ->  http://localhost:4100
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const require = createRequire(import.meta.url);
let WebSocketServer;
try { ({ WebSocketServer } = require('ws')); }
catch { ({ WebSocketServer } = require(path.join(root, 'backend/node_modules/ws'))); }

const PORT = Number(process.env.PORT || 4100);
const SECRET = 'mock-secret';

// ---------- seed (parsed from the real SQL so the village matches) ----------
const world = fs.readFileSync(path.join(root, 'db/seed/02_world.sql'), 'utf8');
const unq = (s) => s.replace(/''/g, "'");
const places = [...world.matchAll(/\((\d+), '((?:[^']|'')*)', '(\w+)', ([\d.]+), ([\d.]+)\)/g)]
  .map((m) => ({ place_id: +m[1], name: unq(m[2]), kind: m[3], x: +m[4], y: +m[5] }));
const homes = [...world.split('INSERT INTO home')[1].split('INSERT INTO actor')[0]
  .matchAll(/\((\d+), (\d+), '([^']+)'\)/g)].map((m) => ({ home_id: +m[1], place_id: +m[2], family_name: m[3] }));
const baseActors = [...world.split('INSERT INTO actor')[1]
  .matchAll(/\((\d+), '((?:[^']|'')*)', 'villager', (NULL|'\w+'), (\d+)\)/g)]
  .map((m) => ({ actor_id: +m[1], name: unq(m[2]), kind: 'villager', job: m[3] === 'NULL' ? null : m[3].slice(1, -1), home_id: +m[4] }));
const items = [{ item_id: 1, name: 'bread' }, { item_id: 2, name: 'grain' }, { item_id: 3, name: 'flour' }];
const pid = (n) => places.find((p) => p.name === n).place_id;
const ACTIONS = ['gift', 'trade', 'steal', 'rumor', 'build', 'hire', 'set_price', 'help_harvest', 'sabotage', 'feast'];

const actors = new Map(baseActors.map((a) => [a.actor_id, { ...a }]));
let nextActor = 31;
let nextEvent = 1;
let nextBranch = 1;
const events = new Map();        // id -> event
const branches = new Map();      // id -> branch

const clone = (o) => JSON.parse(JSON.stringify(o));
function freshState() {
  const stock = {};
  const put = (pl, it, qty, price) => { stock[`${pid(pl)}:${it}`] = { qty, price }; };
  put("Maren's Bakery", 1, 40, 2); put("Maren's Bakery", 3, 30, 1.5);
  put("Tobin's Mill", 2, 60, 1); put("Tobin's Mill", 3, 50, 1.5);
  put('Hartley Farm', 2, 40, .8); put('Brook Farm', 2, 40, .8); put('Thorn Farm', 2, 40, .8);
  const ent = {};
  for (const a of baseActors) {
    ent[a.actor_id] = { mood: 'content', trust: 50, inv: {},
      coins: ['baker', 'miller', 'innkeeper'].includes(a.job) ? 30 : a.job === 'farmer' ? 20 : 10 };
  }
  return { stock, ent };
}
function newBranch(name, parent, forkEvent, state, tick) {
  const b = { branch_id: nextBranch++, name, parent_id: parent, fork_event: forkEvent, tick, ...state, pending: [], history: {} };
  branches.set(b.branch_id, b);
  return b;
}
const main = newBranch('main', null, null, freshState(), 0);
function addEvent(b, actor_id, action_type, payload, witnesses, causes = []) {
  const e = { event_id: nextEvent++, branch_id: b.branch_id, tick: b.tick, actor_id, action_type, payload, witnesses: new Set(witnesses), causes };
  events.set(e.event_id, e);
  broadcast(e);
  return e;
}
const allActorIds = (b) => Object.keys(b.ent).map(Number);
addEvent(main, null, 'world_start', { note: 'Alderbrook begins' }, []);
snap(main);
function snap(b) { b.history[b.tick] = clone({ stock: b.stock, ent: b.ent, pending: b.pending }); }

// ---------- rules engine (simplified mirror of db/seed/04_rules.sql) ----------
const fx = (b, e, rule, eff, delay, narrative) => ({ b, e, rule, eff, delay, narrative });
function rulesFor(b, e) {
  const out = []; const p = e.payload;
  const stk = (pl, it) => b.stock[`${pl}:${it}`];
  if (e.action_type === 'steal' && stk(p.place_id, p.item_id)?.qty < 40)
    out.push(fx(b, e, 1, { action: 'set_price', actor: null, payload: { place_id: p.place_id, item_id: p.item_id, price_pct: 25, culprit: e.actor_id }, vis: 'public' }, 1, 'The shelf ran short, so the baker raised the price.'));
  if (e.action_type === 'sabotage' && stk(p.place_id, p.item_id)?.qty < 40)
    out.push(fx(b, e, 10, { action: 'set_price', actor: null, payload: { place_id: p.place_id, item_id: p.item_id, price_pct: 25, culprit: e.actor_id }, vis: 'public' }, 1, 'Damaged stock left the shelf short, so the price rose.'));
  if (e.action_type === 'trade' && stk(p.place_id, p.item_id)?.qty < 10)
    out.push(fx(b, e, 15, { action: 'set_price', actor: null, payload: { place_id: p.place_id, item_id: p.item_id, price_pct: 10 }, vis: 'public' }, 1, 'The shelf nearly emptied, so the price crept up.'));
  if (e.action_type === 'set_price' && p.price_pct >= 20 && p.culprit)
    out.push(fx(b, e, 2, { action: 'state_change', actor: null, payload: { entity_id: p.culprit, set: { mood: 'shunned' }, add: { trust: -5 } }, vis: 'culprit' }, 1, 'Dearer bread set the neighbors whispering about a thief.'));
  if (e.action_type === 'state_change' && (b.ent[e.payload.entity_id]?.trust ?? 50) < 50 && e.payload.add?.trust)
    out.push(fx(b, e, 3, { action: 'rumor', actor: null, payload: { about: e.payload.entity_id, text: 'thief' }, vis: 'public' }, 0, 'Trust fell, and the whispers became a village rumor.'));
  if (e.action_type === 'gift')
    out.push(fx(b, e, 11, { action: 'state_change', actor: null, payload: { entity_id: p.target_actor, set: { mood: 'grateful' } }, vis: 'private' }, 0, 'A gift left a neighbor feeling grateful.'));
  if (e.action_type === 'help_harvest')
    out.push(fx(b, e, 12, { action: 'state_change', actor: null, payload: { entity_id: e.actor_id, add: { trust: 2 } }, vis: 'private' }, 0, 'Neighbors noticed the extra hands at harvest.'));
  if (e.action_type === 'rumor' && p.text === 'slander')
    out.push(fx(b, e, 13, { action: 'state_change', actor: null, payload: { entity_id: p.about, add: { trust: -3 } }, vis: 'private' }, 0, 'A nasty rumor chipped away at a good name.'));
  if (e.action_type === 'rumor' && p.text === 'praise')
    out.push(fx(b, e, 14, { action: 'state_change', actor: null, payload: { entity_id: p.about, add: { trust: 3 } }, vis: 'private' }, 0, 'Kind words lifted a neighbor\'s standing.'));
  return out;
}
const RULE_TEXT = {};
function project(b, e) {
  const p = e.payload; const st = (pl, it) => b.stock[`${pl}:${it}`];
  const ent = (id) => b.ent[id];
  const nm = (id) => items.find((i) => i.item_id === id).name;
  const need = (c, m) => { if (!c) throw new Error(m); };
  switch (e.action_type) {
    case 'arrive': b.ent[e.actor_id] = { mood: 'curious', trust: 50, coins: p.coins ?? 5, inv: {} }; break;
    case 'steal': { need(p.qty > 0, 'qty must be positive'); const s = st(p.place_id, p.item_id); need(s, 'no such stock');
      need(s.qty - p.qty >= 0, 'new row for relation "stock" violates check constraint "stock_qty_check"'); s.qty -= p.qty;
      ent(e.actor_id).inv[nm(p.item_id)] = (ent(e.actor_id).inv[nm(p.item_id)] || 0) + p.qty; break; }
    case 'gift': { need(p.qty > 0, 'qty must be positive'); const me = ent(e.actor_id);
      need((me.inv[nm(p.item_id)] || 0) >= p.qty, 'insufficient inventory of ' + nm(p.item_id)); need(ent(p.target_actor), 'unknown actor');
      me.inv[nm(p.item_id)] -= p.qty; const t = ent(p.target_actor); t.inv[nm(p.item_id)] = (t.inv[nm(p.item_id)] || 0) + p.qty; break; }
    case 'set_price': { const s = st(p.place_id, p.item_id); need(s, 'no such stock');
      s.price = p.price !== undefined ? +p.price : Math.round(s.price * (100 + p.price_pct)) / 100; break; }
    case 'trade': { need(p.qty > 0, 'qty must be positive'); const s = st(p.place_id, p.item_id); need(s, 'no such stock');
      need(s.qty >= p.qty, 'new row for relation "stock" violates check constraint "stock_qty_check"');
      const total = s.price * p.qty; const me = ent(e.actor_id);
      need(me.coins >= total, 'not enough coins'); need(ent(p.target_actor), 'unknown actor');
      s.qty -= p.qty; me.coins -= total; ent(p.target_actor).coins += total;
      me.inv[nm(p.item_id)] = (me.inv[nm(p.item_id)] || 0) + p.qty; break; }
    case 'hire': { need(p.wage > 0, 'wage must be positive'); const me = ent(e.actor_id);
      need(me.coins >= p.wage, 'not enough coins'); need(ent(p.target_actor), 'unknown actor');
      me.coins -= p.wage; ent(p.target_actor).coins += p.wage; ent(p.target_actor).employer = e.actor_id; break; }
    case 'help_harvest': { need(p.qty > 0, 'qty must be positive'); need(p.qty <= 10, 'qty too large');
      need(places.find((x) => x.place_id === p.place_id)?.kind === 'farm', 'not a farm'); const s = st(p.place_id, 2); need(s, 'no such stock'); s.qty += p.qty; break; }
    case 'sabotage': { need(p.qty > 0, 'qty must be positive'); const s = st(p.place_id, p.item_id); need(s, 'no such stock');
      need(s.qty - p.qty >= 0, 'new row for relation "stock" violates check constraint "stock_qty_check"'); s.qty -= p.qty; break; }
    case 'state_change': { const t = ent(p.entity_id); if (!t) break; if (p.set) Object.assign(t, p.set);
      if (p.add) for (const [k, v] of Object.entries(p.add)) t[k] = (t[k] ?? 0) + v; break; }
    case 'produce': { if (p.input_item_id) st(p.place_id, p.input_item_id).qty -= p.input_qty; st(p.place_id, p.output_item_id).qty += p.output_qty; break; }
    case 'deliver': { st(p.from_place, p.item_id).qty -= p.qty;
      const k = `${p.to_place}:${p.item_id}`; (b.stock[k] ||= { qty: 0, price: 1.5 }).qty += p.qty; break; }
    case 'consume': st(p.place_id, p.item_id).qty -= p.qty; break;
    default: break;
  }
}
function witnessesFor(b, e, vis) {
  vis = vis || (['steal', 'sabotage'].includes(e.action_type) ? 'secret' : ['set_price', 'build', 'feast'].includes(e.action_type) ? 'public' : 'private');
  if (vis === 'public') return allActorIds(b);
  if (vis === 'secret') return e.actor_id ? [e.actor_id] : [];
  if (vis === 'culprit') return [e.payload.entity_id].filter(Boolean);       // mock-only nicety
  return [e.actor_id, e.payload?.target_actor].filter(Boolean);
}
function emit(b, cause, rule, eff, tick) {
  const ev = { event_id: nextEvent++, branch_id: b.branch_id, tick, actor_id: eff.actor, action_type: eff.action, payload: eff.payload, witnesses: new Set(), causes: [{ cause: cause.event_id, rule }] };
  project(b, ev);
  events.set(ev.event_id, ev); ev.witnesses = new Set(witnessesFor(b, ev, eff.vis)); broadcast(ev); return ev;
}
function cascade(b, e, depth = 0) {
  if (depth >= 5) return;
  for (const r of rulesFor(b, e)) {
    RULE_TEXT[r.rule] = r.narrative;
    if (r.delay === 0) cascade(b, emit(b, e, r.rule, r.eff, e.tick), depth + 1);
    else b.pending.push({ due: e.tick + r.delay, source: e.event_id, rule: r.rule, eff: r.eff });
  }
}
const DAILY = [
  [4, { action: 'produce', actor: null, payload: { place_id: pid('Hartley Farm'), output_item_id: 2, output_qty: 25 }, vis: 'private' }, () => true, 'Hartley Farm brought in the day\'s harvest.'],
  [5, { action: 'deliver', actor: null, payload: { from_place: pid('Hartley Farm'), to_place: pid("Tobin's Mill"), item_id: 2, qty: 20 }, vis: 'private' }, (b) => b.stock[`${pid('Hartley Farm')}:2`].qty >= 20, 'A cart of grain rolled from the farm to the mill.'],
  [6, { action: 'produce', actor: null, payload: { place_id: pid("Tobin's Mill"), input_item_id: 2, input_qty: 20, output_item_id: 3, output_qty: 20 }, vis: 'private' }, (b) => b.stock[`${pid("Tobin's Mill")}:2`].qty >= 20, 'Tobin ground the day\'s grain into flour.'],
  [7, { action: 'deliver', actor: null, payload: { from_place: pid("Tobin's Mill"), to_place: pid("Maren's Bakery"), item_id: 3, qty: 10 }, vis: 'private' }, (b) => b.stock[`${pid("Tobin's Mill")}:3`].qty >= 10, 'Flour was carried from the mill to the bakery.'],
  [8, { action: 'produce', actor: null, payload: { place_id: pid("Maren's Bakery"), input_item_id: 3, input_qty: 10, output_item_id: 1, output_qty: 20 }, vis: 'private' }, (b) => b.stock[`${pid("Maren's Bakery")}:3`].qty >= 10, 'Maren baked the morning bread.'],
  [9, { action: 'consume', actor: null, payload: { place_id: pid("Maren's Bakery"), item_id: 1, qty: 15 }, vis: 'private' }, (b) => b.stock[`${pid("Maren's Bakery")}:1`].qty >= 15, 'The village ate its daily bread.'],
];
function advanceDay(b) {
  b.tick += 1;
  const day = addEvent(b, null, 'day_start', { day: b.tick }, []);
  const sp = plays.get(b.branch_id); if (sp) storyDay(b, sp, b.tick);
  for (const [rule, eff, cond, text] of DAILY) {
    RULE_TEXT[rule] = text;
    if (cond(b)) { const ev = emit(b, day, rule, JSON.parse(JSON.stringify(eff)), b.tick); cascade(b, ev, 1); }
  }
  const due = b.pending.filter((p) => p.due <= b.tick); b.pending = b.pending.filter((p) => p.due > b.tick);
  for (const p of due) { const src = events.get(p.source); const ev = emit(b, src, p.rule, JSON.parse(JSON.stringify(p.eff)), b.tick); cascade(b, ev, 0); }
  snap(b);
  return b.tick;
}
function actionsUsed(b, actor) {
  const sp = plays.get(b.branch_id);
  return [...events.values()].filter((e) => e.branch_id === b.branch_id && e.actor_id === actor && e.tick === b.tick && ACTIONS.includes(e.action_type)).length + (sp && actor === PROT ? sp.choices.filter((c) => c.tick === b.tick && c.cost).length : 0);
}
function applyAction(b, actor, action, payload) {
  if (!ACTIONS.includes(action)) throw new Error(`not a player action: ${action}`);
  if (!b.ent[actor]) throw new Error('unknown actor');
  if (actionsUsed(b, actor) >= 3) throw new Error('no actions left today');
  const backup = clone({ stock: b.stock, ent: b.ent, pending: b.pending });
  const evBackup = nextEvent; const evKeys = new Set(events.keys());
  try {
    const e = { event_id: nextEvent++, branch_id: b.branch_id, tick: b.tick, actor_id: actor, action_type: action, payload, witnesses: new Set(), causes: [] };
    project(b, e); events.set(e.event_id, e); e.witnesses = new Set(witnessesFor(b, e)); broadcast(e);
    cascade(b, e); return e.event_id;
  } catch (err) {                                    // atomic: nothing half-applied, like the real transaction
    b.stock = backup.stock; b.ent = backup.ent; b.pending = backup.pending;
    for (const k of [...events.keys()]) if (!evKeys.has(k)) events.delete(k);
    nextEvent = evBackup; throw err;
  }
}
// ---------- causal helpers ----------
function ancestors(id) {                              // [{id, depth}]
  const out = new Map(); const q = [[id, 0]];
  while (q.length) { const [cur, d] = q.shift(); for (const c of events.get(cur)?.causes || []) { if (!out.has(c.cause) || out.get(c.cause) > d + 1) { out.set(c.cause, d + 1); q.push([c.cause, d + 1]); } } }
  return [...out].map(([i, depth]) => ({ id: i, depth }));
}
const descendants = (id) => { let n = 0; const seen = new Set(); const q = [id];
  while (q.length) { const cur = q.shift(); for (const e of events.values()) if (e.causes.some((c) => c.cause === cur) && !seen.has(e.event_id)) { seen.add(e.event_id); n++; q.push(e.event_id); } } return n; };

// ---------- STORY MODE (mirrors db/scenarios + db/seed/05_story_*.sql; content comes from the same slice.json) ----------
const SLICE = JSON.parse(fs.readFileSync(path.join(root, 'db/scenarios/mystery/slice.json'), 'utf8'));
const PROT = SLICE.scenario.protagonist_id;
for (const a of SLICE.actors) actors.set(a.id, { actor_id: a.id, name: a.name, kind: 'villager', job: a.job, home_id: null });
const plays = new Map();   // branchId -> {trait, guided, pronouns, found: Map(clue->tick), choices: []}
const witnessSet = (b, vis, actor, target) => (vis === 'public' ? allActorIds(b) : [actor, target].filter(Boolean));
function runOps(b, p, ops) {
  for (const op of ops || []) {
    const st = b.ent[PROT];
    if (op.when) {
      const w = op.when;
      if (w.state_lt && !(st[w.state_lt.key] !== undefined && st[w.state_lt.key] < w.state_lt.value)) continue;
      if (w.state_gte && !(st[w.state_gte.key] !== undefined && st[w.state_gte.key] >= w.state_gte.value)) continue;
    }
    if (op.discover) { if (!p.found.has(op.discover)) p.found.set(op.discover, b.tick); addEvent(b, PROT, 'discover', { clue: op.discover }, [PROT]); }
    else if (op.enter) { const a = SLICE.actors.find((x) => x.id === op.enter); if (!b.ent[a.id]) b.ent[a.id] = clone(a.state); }
    else if (op.event) { const e = op.event; addEvent(b, e.actor ?? null, 'story_event', { kind: e.kind, text: e.text, ...(e.target ? { target_actor: e.target } : {}) }, witnessSet(b, e.visibility, e.actor, e.target)); }
    else { const t = b.ent[op.entity === 'player' ? PROT : op.entity]; if (t) { Object.assign(t, op.set || {}); for (const [k, v] of Object.entries(op.add || {})) t[k] = (t[k] ?? 0) + v; } }
  }
}
function storyDay(b, p, day) {
  for (const de of SLICE.day_events.filter((x) => x.day === day)) {
    if (de.text) addEvent(b, null, 'story_event', { kind: de.kind, text: de.text }, de.visibility === 'public' ? allActorIds(b) : []);
    runOps(b, p, de.effects);
  }
}
const chose = (p, spec) => { const [bk, ok] = spec.split(':'); return p.choices.some((c) => c.beat === bk && (!ok || c.option === ok)); };
function beatAvailable(b, p, beat) {
  if (beat.day !== b.tick) return false;
  const picks = p.choices.filter((c) => c.beat === beat.key).length;
  if (picks >= beat.max_picks) return false;
  if (!beat.options.some((o) => !chose(p, `${beat.key}:${o.key}`))) return false;
  return beat.requires.every((r) => chose(p, r)) && !beat.forbids.some((r) => chose(p, r));
}
const paidUsed = (b, p) => p.choices.filter((c) => c.tick === b.tick && c.cost).length;
function linkStrength(p, upto) {
  return SLICE.links.map((l) => ({ ...l, strength: Math.min(3, SLICE.clues.filter((c) => c.links[l.key] && p.found.has(c.key) && p.found.get(c.key) <= upto).reduce((n, c) => n + c.links[l.key], 0)) }));
}
const progress = (p, upto) => linkStrength(p, upto).reduce((n, l) => n + l.strength, 0);
function startStory(trait, guided, pronouns) {
  const b = newBranch(`story: ${SLICE.scenario.title} #${plays.size + 1}`, 1, null, freshState(), 0);
  const p = { trait, guided: !!guided, pronouns, found: new Map(), choices: [] }; plays.set(b.branch_id, p);
  addEvent(b, null, 'world_start', { note: 'story begins' }, []);
  Object.assign(b.ent[PROT], SLICE.scenario.start_state);
  for (const r of SLICE.start_rules) if (r.when.trait === trait) runOps(b, p, r.effects);
  advanceDay(b);
  return b;
}
function storyScene(b, p) {
  const st = b.ent[PROT]; const sc = SLICE.scenario; const day = SLICE.days.find((d) => d.day === b.tick) || {};
  const beats = SLICE.beats.filter((x) => beatAvailable(b, p, x)).map((x) => ({ beat_key: x.key, title: x.title, body: x.body, phase: x.phase, costs_action: x.cost, focus: x.focus ?? null,
    picks_left: x.max_picks - p.choices.filter((c) => c.beat === x.key).length, options: x.options.filter((o) => !chose(p, `${x.key}:${o.key}`)).map((o) => ({ key: o.key, label: o.label })) }));
  const done = p.choices.map((c) => { const bt = SLICE.beats.find((x) => x.key === c.beat); const o = bt.options.find((y) => y.key === c.option); return { tick: c.tick, beat_key: c.beat, title: bt.title, option_key: c.option, label: o.label, result: o.result, costs_action: bt.cost }; });
  const ending = SLICE.endings.find((e) => (st[e.flag] ?? 0) >= 1);
  return { scenario: sc.key, title: sc.title, tagline: sc.tagline, day: b.tick, day_title: day.title, intro: day.intro, goal: sc.goal, deadline_day: sc.deadline_day, cold_open: sc.cold_open,
    outros: Object.fromEntries(SLICE.days.filter((d) => d.day < b.tick && d.outro).map((d) => [String(d.day), d.outro])), actions_left: Math.max(0, 3 - paidUsed(b, p) - [...events.values()].filter((e) => e.branch_id === b.branch_id && e.actor_id === PROT && e.tick === b.tick && ACTIONS.includes(e.action_type)).length),
    meters: { suspicion: st.suspicion ?? 0, danger: st.danger ?? 0, smoke: st.smoke ?? 0, coins: st.coins ?? 0 },
    trust: Object.fromEntries(Object.entries(st).filter(([k]) => k.startsWith('trust_')).map(([k, v]) => [k.slice(6), v])),
    beats, done, ending: ending ? { key: ending.key, title: ending.title, text: ending.text } : null, slice_over: b.tick > sc.slice_end_day, guided: p.guided, trait: p.trait, pronouns: p.pronouns };
}
function storyChoose(b, p, beatKey, optKey) {
  const st = b.ent[PROT]; if ((st.dead ?? 0) >= 1) throw new Error('your story has ended');
  const beat = SLICE.beats.find((x) => x.key === beatKey); if (!beat) throw new Error('unknown scene');
  if (!beatAvailable(b, p, beat)) throw new Error('that moment has passed');
  const opt = beat.options.find((o) => o.key === optKey); if (!opt) throw new Error('unknown choice');
  if (chose(p, `${beatKey}:${optKey}`)) throw new Error('you already chose that');
  if (beat.cost && paidUsed(b, p) + [...events.values()].filter((e) => e.branch_id === b.branch_id && e.actor_id === PROT && e.tick === b.tick && ACTIONS.includes(e.action_type)).length >= 3) throw new Error('no actions left today');
  p.choices.push({ beat: beatKey, option: optKey, tick: b.tick, cost: beat.cost ? 1 : 0 });
  runOps(b, p, opt.effects);
  for (const r of SLICE.rules) { const w = r.when; if (w.payload_eq.beat === beatKey && (st[w.state_gte.key] ?? 0) >= w.state_gte.value) runOps(b, p, r.effects); }
  return { event_id: nextEvent, beat: beatKey, option: optKey, result: opt.result, react_actor: opt.react_actor ?? null, react_line: opt.react_line ?? null };
}
function storyCompass(b, p) {
  if (!p.guided) return { guided: false };
  const mis = b.ent[PROT].misdirect ?? 0; const score = Math.max(0, progress(p, b.tick) - mis); const prev = Math.max(0, progress(p, b.tick - 1) - mis);
  const now = linkStrength(p, b.tick); const before = linkStrength(p, b.tick - 1);
  const gained = now.filter((l, i) => l.strength > before[i].strength).map((l) => l.title).join(', ');
  return { guided: true, score, prev_score: prev, max: 21, needle: score < 4 ? 'Lost' : score < 9 ? 'Cold' : score < 13 ? 'Cool' : score < 17 ? 'Warm' : 'Hot', trend: score - prev,
    reason: gained ? `Warmer. You have learned something about ${gained}.` : score < prev ? 'Colder. Something you did has moved you away from the truth.' : 'No change since yesterday.' };
}

// ---------- tokens ----------
const sign = (o) => { const b = Buffer.from(JSON.stringify(o)).toString('base64url'); return `mock.${b}.${crypto.createHmac('sha256', SECRET).update(b).digest('base64url')}`; };
const verify = (t) => { const [m, b, s] = (t || '').split('.'); if (m !== 'mock' || s !== crypto.createHmac('sha256', SECRET).update(b).digest('base64url')) return null; return JSON.parse(Buffer.from(b, 'base64url')); };

// ---------- websocket ----------
const wss = new WebSocketServer({ noServer: true });
const sockets = new Map();
function broadcast(e) {
  const msg = JSON.stringify({ type: 'event', branch_id: e.branch_id, event_id: String(e.event_id), tick: e.tick, actor_id: e.actor_id, action_type: e.action_type });
  setTimeout(() => { for (const [ws, c] of sockets) if (c.branchId === e.branch_id && e.witnesses.has(c.actorId) && ws.readyState === 1) ws.send(msg); }, 0);
}

// ---------- http ----------
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json', '.png': 'image/png', '.ico': 'image/x-icon' };
const readBody = (req) => new Promise((ok) => { let s = ''; req.on('data', (c) => (s += c)); req.on('end', () => { try { ok(s ? JSON.parse(s) : {}); } catch { ok({}); } }); });
const send = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x'); const p = url.pathname;
  if (!p.startsWith('/api/')) {
    const f = path.join(root, 'frontend', p === '/' ? 'index.html' : p);
    if (!f.startsWith(path.join(root, 'frontend')) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': mime[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' }); return fs.createReadStream(f).pipe(res);
  }
  const body = req.method === 'POST' ? await readBody(req) : {};
  const route = `${req.method} ${p}`;
  try {
    if (route === 'GET /api/health') return send(res, 200, { ok: true, db: 'mock' });
    if (route === 'GET /api/story/scenarios') return send(res, 200, [{ key: SLICE.scenario.key, title: SLICE.scenario.title, genre: SLICE.scenario.genre, tagline: SLICE.scenario.tagline, locked: false, slice_end_day: SLICE.scenario.slice_end_day },
      { key: 'drama', title: 'The Newcomer\u2019s Inheritance', genre: 'Drama', tagline: 'A failing farm, a secret debt, and three families who each want something.', locked: true },
      { key: 'survival', title: 'The Long Winter', genre: 'Survival', tagline: 'The harvest failed. The granary will not last until spring. Someone has to decide who eats.', locked: true }]);
    if (route === 'POST /api/story/start') {
      if (!['kind', 'sharp', 'quiet'].includes(body.trait)) return send(res, 400, { error: 'scenario and trait (kind|sharp|quiet) are required' });
      const sb = startStory(body.trait, body.guided, ['she', 'he', 'they'].includes(body.pronouns) ? body.pronouns : 'they');
      return send(res, 200, { token: sign({ actorId: PROT, branchId: sb.branch_id }), actorId: PROT, branchId: sb.branch_id });
    }
    if (route === 'POST /api/join') {
      const name = (body.name || '').trim(); if (!name) return send(res, 400, { error: 'name is required' });
      const b = branches.get(Number.isInteger(body.branchId) ? body.branchId : 1); if (!b) return send(res, 400, { error: 'unknown branch' });
      const id = nextActor++; actors.set(id, { actor_id: id, name, kind: 'player', job: null, home_id: null });
      const e = { event_id: nextEvent++, branch_id: b.branch_id, tick: b.tick, actor_id: id, action_type: 'arrive', payload: { coins: 5 }, witnesses: new Set(), causes: [] };
      project(b, e); events.set(e.event_id, e); e.witnesses = new Set([...allActorIds(b)]); broadcast(e);
      return send(res, 200, { token: sign({ actorId: id, branchId: b.branch_id }), actorId: id, branchId: b.branch_id });
    }
    const claim = verify((req.headers.authorization || '').replace('Bearer ', ''));
    if (!claim) return send(res, 401, { error: 'invalid or expired token' });
    const b = branches.get(claim.branchId); const me = claim.actorId;
    const visible = (e) => e.witnesses.has(me);
    const sp = plays.get(claim.branchId);
    if (route === 'GET /api/story/scene') return sp ? send(res, 200, storyScene(b, sp)) : send(res, 404, { error: 'no story in progress' });
    if (route === 'POST /api/story/choose') return send(res, 200, storyChoose(b, sp, body.beat, body.option));
    if (route === 'GET /api/story/board') {
      const found = [...sp.found].map(([k, t]) => ({ c: SLICE.clues.find((x) => x.key === k), t })).sort((x, y) => x.t - y.t);
      return send(res, 200, { links: linkStrength(sp, b.tick).map((l) => ({ key: l.key, title: l.title, question: l.question, strength: l.strength })), progress: progress(sp, b.tick),
        clues: found.map(({ c, t }) => ({ key: c.key, title: c.title, kind: c.kind, journal: c.journal, tick: t, links: Object.entries(c.links).map(([link, weight]) => ({ link, weight })) })) });
    }
    if (route === 'GET /api/story/compass') return send(res, 200, storyCompass(b, sp));
    if (route === 'POST /api/story/guidance') { sp.guided = !!body.guided; return send(res, 200, { guided: sp.guided }); }
    if (route === 'GET /api/places') return send(res, 200, places.map((pl) => ({ ...pl, stock: Object.entries(b.stock).filter(([k]) => +k.split(':')[0] === pl.place_id).map(([k, v]) => ({ place_id: pl.place_id, item_id: +k.split(':')[1], item_name: items.find((i) => i.item_id === +k.split(':')[1]).name, qty: v.qty, price: v.price })) })));
    if (route === 'GET /api/actors') {
      const market = places.find((x) => x.kind === 'market');
      return send(res, 200, allActorIds(b).map((id) => { const a = actors.get(id); const home = homes.find((h) => h.home_id === a.home_id);
        const hp = home ? places.find((x) => x.place_id === home.place_id) : market;
        const byKind = (k) => places.find((x) => x.kind === k);
        const work = { baker: byKind('bakery'), baker_helper: byKind('bakery'), miller: byKind('mill'), mill_helper: byKind('mill'), innkeeper: byKind('inn'), well_keeper: byKind('well'), labourer: market,
          farmer: places.find((x) => x.kind === 'farm' && home && x.name.toLowerCase().startsWith(home.family_name.toLowerCase())) }[a.job] || null;
        const at = work || hp;
        return { actor_id: id, name: a.name, kind: a.kind, job: a.job, home_id: a.home_id, family: home?.family_name || null, home_place_id: hp.place_id, work_place_id: work?.place_id ?? null, place_id: at.place_id, x: at.x, y: at.y, home_x: hp.x, home_y: hp.y, mood: b.ent[id].mood }; }));
    }
    if (route === 'GET /api/me') { const s = b.ent[me]; const n = actionsUsed(b, me);
      return send(res, 200, { actorId: me, branchId: b.branch_id, name: actors.get(me).name, tick: b.tick, state: { coins: Math.round(s.coins * 100) / 100, mood: s.mood, trust: s.trust, inv: s.inv }, actionsUsedToday: n, actionsRemainingToday: Math.max(0, 3 - n) }); }
    if (route === 'GET /api/items') return send(res, 200, items);
    if (route === 'GET /api/action-types') return send(res, 200, ACTIONS);
    if (route === 'GET /api/current-tick') return send(res, 200, { branchId: b.branch_id, tick: b.tick });
    if (route === 'GET /api/mood') return send(res, 200, allActorIds(b).map((id) => ({ branch_id: b.branch_id, actor_id: id, actor_name: actors.get(id).name, mood: b.ent[id].mood })));
    if (route === 'GET /api/events') {
      const lim = Math.min(200, +url.searchParams.get('limit') || 40); const since = +url.searchParams.get('since') || 0;
      return send(res, 200, [...events.values()].filter((e) => e.branch_id === b.branch_id && e.event_id > since && visible(e)).sort((x, y) => y.event_id - x.event_id).slice(0, lim)
        .map((e) => ({ event_id: String(e.event_id), tick: e.tick, actor_id: e.actor_id, actor_name: e.actor_id ? actors.get(e.actor_id)?.name : null, action_type: e.action_type, payload: e.payload, is_cascade: e.causes.length > 0 })));
    }
    if (route === 'POST /api/actions') {
      if (!ACTIONS.includes(body.action)) return send(res, 400, { error: `not a player action: ${body.action}` });
      return send(res, 200, { eventId: String(applyAction(b, me, body.action, body.payload || {})) });
    }
    let m;
    if ((m = p.match(/^\/api\/event\/(\d+)$/)) && req.method === 'GET') { const e = events.get(+m[1]); if (!e || !visible(e)) return send(res, 404, { error: 'nothing comes to mind' });
      return send(res, 200, { event_id: String(e.event_id), tick: e.tick, branch_id: e.branch_id, actor_id: e.actor_id, actor_name: e.actor_id ? actors.get(e.actor_id).name : null, action_type: e.action_type, payload: e.payload }); }
    if ((m = p.match(/^\/api\/ask-why\/(\d+)$/)) && req.method === 'GET') {
      const t = events.get(+m[1]); if (!t || !visible(t)) return send(res, 200, []);
      const anc = ancestors(t.event_id).filter((a) => visible(events.get(a.id)) && visible(events.get(a.id)));
      const rows = [...anc, { id: t.event_id, depth: 0 }].sort((x, y) => y.depth - x.depth || x.id - y.id);
      return send(res, 200, rows.map((r, i) => { const e = events.get(r.id);
        const child = r.depth > 0 ? [...events.values()].find((c) => c.causes.some((k) => k.cause === r.id) && (c.event_id === t.event_id || anc.some((a) => a.id === c.event_id))) : null;
        const rule = child ? child.causes.find((k) => k.cause === r.id)?.rule : null;
        return { step: i + 1, depth: r.depth, event_id: String(e.event_id), tick: e.tick, action_type: e.action_type, actor_name: e.actor_id ? actors.get(e.actor_id).name : null, rule_id: rule ?? null, narrative: rule ? RULE_TEXT[rule] || null : null }; }));
    }
    if ((m = p.match(/^\/api\/score\/(\d+)$/)) && req.method === 'GET') { const e = events.get(+m[1]); return send(res, 200, { eventId: +m[1], score: e && visible(e) ? descendants(+m[1]) : 0 }); }
    if (route === 'GET /api/evening-bell') {
      const per = {}; for (const e of events.values()) if (e.branch_id === b.branch_id) { const r = (per[e.tick] ||= { branch_id: b.branch_id, tick: e.tick, events_total: 0, player_actions: 0, cascade_events: 0, top_score: 0 });
        r.events_total++; if (ACTIONS.includes(e.action_type) && e.actor_id) { r.player_actions++; r.top_score = Math.max(r.top_score, descendants(e.event_id)); } if (e.causes.length) r.cascade_events++; }
      let cum = 0; return send(res, 200, Object.values(per).sort((x, y) => x.tick - y.tick).map((r) => ({ ...r, events_cumulative: (cum += r.events_total) })));
    }
    if (route === 'GET /api/leaderboard') {
      const per = new Map(); for (const e of events.values()) if (e.branch_id === b.branch_id && e.actor_id && ACTIONS.includes(e.action_type)) { const r = per.get(e.actor_id) || { actions: 0, total_score: 0, best_score: 0 };
        const s = descendants(e.event_id); r.actions++; r.total_score += s; r.best_score = Math.max(r.best_score, s); per.set(e.actor_id, r); }
      const rows = [...per].map(([id, r]) => ({ branch_id: b.branch_id, actor_id: id, actor_name: actors.get(id).name, ...r })).sort((x, y) => y.total_score - x.total_score);
      return send(res, 200, rows.map((r, i) => ({ ...r, leaderboard_rank: i > 0 && rows[i - 1].total_score === r.total_score ? rows.findIndex((q) => q.total_score === r.total_score) + 1 : i + 1 })));
    }
    if ((m = p.match(/^\/api\/look-back\/(\d+)$/)) && req.method === 'GET') {
      await new Promise((r) => setTimeout(r, 250));                         // the real one replays: simulate the wait
      const t = Math.min(+m[1], b.tick); const h = clone(b.history[t] || { stock: b.stock, ent: b.ent, pending: [] }); const src = t >= b.tick ? clone({ stock: b.stock, ent: b.ent, pending: b.pending }) : h;
      return send(res, 200, { stock: Object.entries(src.stock).map(([k, v]) => ({ place_id: +k.split(':')[0], item_id: +k.split(':')[1], qty: v.qty, price: v.price })),
        entities: Object.entries(src.ent).map(([id, s]) => ({ entity_id: +id, state: +id === me ? s : { mood: s.mood } })), pending: [] });
    }
    if (route === 'POST /api/advance-day') return send(res, 200, { branchId: b.branch_id, tick: advanceDay(b) });
    if (route === 'POST /api/fork') {
      const strategy = body.strategy || 'snapshot_delta'; if (!body.name) return send(res, 400, { error: 'name is required' });
      const tk = Number.isInteger(body.tick) ? body.tick : events.get(body.forkEvent)?.tick;
      if (!Number.isInteger(tk) || !b.history[tk]) return send(res, 400, { error: 'nothing happened on or before that day in this village' });
      const evs = [...events.values()].filter((e) => e.branch_id === b.branch_id && e.tick <= tk); const fe = evs.sort((x, y) => y.event_id - x.event_id)[0];
      const child = newBranch(String(body.name).slice(0, 60), b.branch_id, fe.event_id, clone({ stock: b.history[tk].stock, ent: b.history[tk].ent }), tk); child.pending = clone(b.history[tk].pending || []);
      for (const e of evs) { const c = { ...e, event_id: nextEvent++, branch_id: child.branch_id, witnesses: new Set(e.witnesses), causes: [] }; events.set(c.event_id, c); }   // inherited history (the real DB shares it through lineage)
      child.fork_event = fe.event_id; snap(child);
      return send(res, 200, { childBranchId: child.branch_id, forkEvent: fe.event_id });
    }
    if (route === 'GET /api/branches') return send(res, 200, [...branches.values()].map((x) => ({ branch_id: x.branch_id, name: x.name, parent_id: x.parent_id, fork_event: x.fork_event === null ? null : String(x.fork_event), tick: x.tick, you_live_here: !!x.ent[me] })));
    if (route === 'POST /api/switch-branch') { const t = branches.get(+body.branchId); if (!t || !t.ent[me]) return send(res, 404, { error: 'you have not arrived in that village (it was forked before you came)' });
      return send(res, 200, { token: sign({ actorId: me, branchId: t.branch_id }), actorId: me, branchId: t.branch_id }); }
    if ((m = p.match(/^\/api\/branch-diff\/(\d+)\/(\d+)$/)) && req.method === 'GET') {
      const A = branches.get(+m[1]); const B = branches.get(+m[2]); if (!A || !B) return send(res, 400, { error: 'unknown branch' }); const rows = [];
      for (const k of new Set([...Object.keys(A.stock), ...Object.keys(B.stock)])) { const a = A.stock[k]; const bb = B.stock[k];
        if (!a || !bb || a.qty !== bb.qty || a.price !== bb.price) { const [pl, it] = k.split(':').map(Number);
          rows.push({ kind: 'stock', key: `${places.find((x) => x.place_id === pl).name} / ${items.find((x) => x.item_id === it).name}`, a_value: a ? `qty=${a.qty} price=${a.price}` : null, b_value: bb ? `qty=${bb.qty} price=${bb.price}` : null }); } }
      for (const id of new Set([...Object.keys(A.ent), ...Object.keys(B.ent)])) { const a = A.ent[id]; const bb = B.ent[id];
        if (JSON.stringify(a) !== JSON.stringify(bb)) rows.push({ kind: 'entity', key: actors.get(+id)?.name || id, a_value: a ? JSON.stringify(+id === me ? a : { mood: a.mood }) : null, b_value: bb ? JSON.stringify(+id === me ? bb : { mood: bb.mood }) : null }); }
      return send(res, 200, rows);
    }
    return send(res, 404, { error: 'no such endpoint' });
  } catch (err) { return send(res, 400, { error: err.message }); }
});
server.on('upgrade', (req, socket, head) => {
  const u = new URL(req.url, 'http://x'); const claim = verify(u.searchParams.get('token'));
  if (u.pathname !== '/ws' || !claim) { socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, (ws) => { sockets.set(ws, claim); ws.on('close', () => sockets.delete(ws)); });
});
server.listen(PORT, () => console.log(`Butterfly Effect DEMO server (in-memory, no database) on http://localhost:${PORT}`));

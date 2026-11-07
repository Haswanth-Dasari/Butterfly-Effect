// Butterfly Effect UI — orchestration. Every panel gets the same `ctx`.
import { $, $$, h, s, svgFromString, store, bus, indexWorld, money, moodInfo, plural, sleep, debounce } from './util.js';
import { api, session, connectLive, flavor } from './api.js';
import { createMap } from './map.js';
import { describe, eventPlaceId, eventTargets, ACTION_META, iconSvg } from './narrate.js';
import { toast, modal, moodPill, coinText } from './ui.js';
import { sound } from './sound.js';
import { createActionsPanel } from './actions.js';
import { createChroniclePanel } from './chronicle.js';
import { createTimePanel } from './timeline.js';
import { createWorldsPanel } from './worlds.js';
import { createVillagePanel } from './village.js';
import { startTour } from './tour.js';

const BUTTERFLY = `<g class="bf"><path d="M32 30 C14 8 2 16 8 30 C10 40 22 42 32 34z" fill="#f2b84b" stroke="#7a4a10" stroke-width="1.4"/>
<path d="M32 34 C20 40 14 54 24 56 C30 57 33 46 32 34z" fill="#ff7a3d" stroke="#7a4a10" stroke-width="1.4"/>
<path d="M32 30 C50 8 62 16 56 30 C54 40 42 42 32 34z" fill="#f2b84b" stroke="#7a4a10" stroke-width="1.4"/>
<path d="M32 34 C44 40 50 54 40 56 C34 57 31 46 32 34z" fill="#ff7a3d" stroke="#7a4a10" stroke-width="1.4"/>
<circle cx="18" cy="24" r="3" fill="#fff3c9"/><circle cx="46" cy="24" r="3" fill="#fff3c9"/>
<path d="M32 22 V44" stroke="#3a2410" stroke-width="2.500" stroke-linecap="round"/><path d="M32 22 C30 14 26 12 24 10M32 22 C34 14 38 12 40 10" stroke="#3a2410" fill="none" stroke-width="1.300" stroke-linecap="round"/></g>`;

const TABS = [
  { id: 'act', label: 'Act', icon: 'feast' }, { id: 'why', label: 'Chronicle', icon: 'ask' }, { id: 'time', label: 'Look back', icon: 'time' },
  { id: 'worlds', label: 'Worlds', icon: 'worlds' }, { id: 'village', label: 'Village', icon: 'village' },
];

let map; let panels = {}; let live = null; let poll = null; let current = 'act';
let seenEvents = new Set(); let lastWs = 0; let hop = 0; let ghostTick = null; let ending = false;

// ---------- boot ----------
function heroArt() {
  $('#hero-art').replaceChildren(...svgFromString(`<svg viewBox="0 0 400 400" xmlns="http://www.w3.org/2000/svg"></svg>`).map((n) => n));
  const svg = s('svg', { viewBox: '0 0 400 400' });
  svg.append(...svgFromString(`<defs><radialGradient id="hg"><stop offset="0" stop-color="#f2b84b" stop-opacity=".35"/><stop offset="1" stop-color="#f2b84b" stop-opacity="0"/></radialGradient></defs>
    <circle cx="200" cy="200" r="190" fill="url(#hg)"/>
    <g class="hero-rings" fill="none" stroke="#f2b84b" stroke-width="2"><circle cx="200" cy="215" r="30" class="rr r1"/><circle cx="200" cy="215" r="30" class="rr r2"/><circle cx="200" cy="215" r="30" class="rr r3"/></g>
    <g transform="translate(88 70) scale(3.6)">${BUTTERFLY}</g>`));
  $('#hero-art').replaceChildren(svg);
  const st = document.createElement('style');
  st.textContent = '.rr{transform-box:fill-box;transform-origin:center;animation:hr 4.5s ease-out infinite;opacity:0}.r2{animation-delay:1.5s}.r3{animation-delay:3s}@keyframes hr{0%{transform:scale(.4);opacity:.9}100%{transform:scale(5.2);opacity:0}}.bf{transform-origin:32px 34px;animation:flap 1.3s ease-in-out infinite}@keyframes flap{50%{transform:scaleX(.72)}}';
  document.head.append(st);
}

function init() {
  heroArt();
  $('#pw1').replaceChildren(iconSvg('ask', 18), 'Ask Why'); $('#pw2').replaceChildren(iconSvg('worlds', 18), 'Parallel villages'); $('#pw3').replaceChildren(iconSvg('time', 18), 'Look Back');
  const saved = session.load();
  if (saved?.token) {
    const b = $('#resume-btn'); b.classList.remove('hidden'); b.textContent = `Continue as ${saved.name}`;
    b.onclick = async () => { store.session = saved; try { await enterGame(); } catch (e) { session.clear(); $('#join-err').textContent = flavor(e); b.classList.add('hidden'); } };
    $('#join-note').textContent = 'Your villager is remembered in this browser.';
  }
  $('#join-form').addEventListener('submit', async (e) => {
    e.preventDefault(); const name = $('#name').value.trim(); if (!name) return;
    $('#join-btn').disabled = true; $('#join-err').textContent = '';
    try {
      const r = await api.join(name);
      store.session = { token: r.token, actorId: r.actorId, branchId: r.branchId, name }; session.save(store.session);
      await enterGame();
    } catch (err) { $('#join-err').textContent = flavor(err); } finally { $('#join-btn').disabled = false; }
  });
  bus.on('auth-lost', () => { if (!$('#game').classList.contains('hidden')) { toast('Your session ended. Please arrive again.', 'bad'); leave(); } });
}

async function enterGame() {
  $('#join').classList.add('hidden'); $('#game').classList.remove('hidden');
  buildChrome();
  await loadWorld();
  bus.emit('branch');
  map.setPhase('morning'); sound.play('morning'); setTimeout(() => map.setPhase(phaseFromActions()), 2600);
  live?.close(); live = connectLive(onLive, (st) => $('#live').classList.toggle('live', st === 'live'));
  clearInterval(poll); poll = setInterval(() => { if (!document.hidden && !ending) refreshAll().catch(() => {}); }, 10000);
  if (!localStorage.getItem('butterfly.toured')) setTimeout(() => startTour(), 900);
  panels.village.update();
}

function leave() {
  live?.close(); clearInterval(poll); session.clear(); store.session = null;
  $('#game').classList.add('hidden'); $('#join').classList.remove('hidden'); location.reload();
}

// ---------- chrome ----------
function buildChrome() {
  $('#brand').replaceChildren(s('svg', { viewBox: '0 0 64 64' }, ...svgFromString(BUTTERFLY)), h('span', 'Butterfly Effect'));
  $('#btn-sound').replaceChildren(iconSvg(sound.enabled ? 'sound' : 'mute', 20)); $('#btn-help').replaceChildren(iconSvg('help', 20));
  $('#btn-sound').onclick = () => { const on = sound.toggle(); $('#btn-sound').replaceChildren(iconSvg(on ? 'sound' : 'mute', 20)); toast(on ? 'Sound on' : 'Sound off'); };
  $('#btn-help').onclick = () => startTour();
  $('#btn-leave').onclick = () => { if (confirm('Leave Alderbrook? Your villager stays in the village, but this browser will forget you.')) leave(); };
  $('#end-day-top').onclick = () => endDay();
  $('#st-branch').onclick = () => selectTab('worlds');
  document.addEventListener('pointerdown', () => sound.resume(), { once: true });

  map = createMap($('#map'), {
    onHover: (h2, ev) => tooltip(h2, ev), onSelectActor: showVillager, onSelectPlace: showPlace,
    onPickMode: (p) => { $('#pickbar')?.remove(); if (p) $('#mapwrap').append(h('div.overlay#pickbar', h('span', p.hint || 'Choose on the map'), h('button.btn.sm', { onclick: () => map.setPick(null) }, 'Cancel'))); },
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { if (map.picking) map.setPick(null); $('#villager-card').classList.add('hidden'); } });
  $('#mapwrap').addEventListener('click', () => $('#villager-card').classList.add('hidden'));

  const ctx = {
    map, afterAction, endDay, pickOnMap: (p) => { map.setPick(p); }, switchBranch, openFork, setGhost,
    toast, refresh: refreshAll, forkDay: null,
  };
  panels = { act: createActionsPanel(ctx), why: createChroniclePanel(ctx), time: createTimePanel(ctx), worlds: createWorldsPanel(ctx), village: createVillagePanel(ctx) };
  $('#tabs').replaceChildren(...TABS.map((t) => h('button.tab', { role: 'tab', 'data-tab': t.id, 'aria-selected': t.id === current, onclick: () => selectTab(t.id) }, iconSvg(t.icon, 20), t.label)));
  $('#panels').replaceChildren(...TABS.map((t) => h('section.panel', { id: `p-${t.id}`, class: t.id === current ? 'active' : '', role: 'tabpanel' }, panels[t.id].el)));
  $('#legend').replaceChildren(...['content', 'happy', 'curious', 'sad', 'angry', 'shunned'].map((m) => h('span', h('i', { style: { background: moodInfo(m).color } }), m)));
}

function selectTab(id) {
  if (current === 'time' && id !== 'time') panels.time.leave();
  current = id; sound.play('tab');
  $$('.tab').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.tab === id)));
  $$('.panel').forEach((p) => p.classList.toggle('active', p.id === `p-${id}`));
  panels[id].update?.();
}

function phaseFromActions() { return (store.me?.actionsRemainingToday ?? 3) <= 0 ? 'evening' : 'day'; }

function updateTop() {
  const me = store.me; if (!me) return;
  $('#st-day').replaceChildren(iconSvg(map?.phase === 'night' ? 'moon' : 'sun', 16), ` Day ${store.tick}`);
  const b = store.branches.find((x) => x.branch_id === store.session.branchId);
  const main = !b || !b.parent_id;
  $('#st-branch').className = `chip-stat branch ${main ? '' : 'alt'}`; $('#st-branch').replaceChildren(iconSvg('worlds', 15), main ? 'Main village' : b.name);
  $('#st-coins').replaceChildren(iconSvg('coin', 16), money(me.state?.coins ?? 0)); $('#st-trust').replaceChildren(iconSvg('heart', 16), `${me.state?.trust ?? '–'}`);
  $('#st-mood').replaceChildren(moodPill(me.state?.mood));
  const left = me.actionsRemainingToday ?? 3;
  $('#pips').replaceChildren(...[0, 1, 2].map((i) => h('i.pip', { class: i < left ? 'full' : '' })));
  $('#pips').title = `${left} of 3 actions left today`;
  $('#end-day-top').textContent = left > 0 ? 'End day' : 'End day ›';
  $('#phase-badge').replaceChildren(iconSvg(map.phase === 'night' ? 'moon' : 'sun', 18), `Day ${store.tick} · ${ { morning: 'morning', day: 'daytime', evening: 'evening', night: 'night' }[map.phase] }`);
}

// ---------- data ----------
async function loadWorld() {
  const [items, me] = await Promise.all([api.items(), api.me()]);
  store.items = items; store.me = me; store.tick = me.tick;
  await refreshAll(true);
}

async function refreshAll() {
  const [me, places, actors, events] = await Promise.all([api.me(), api.places(), api.actors(), api.events(60)]);
  const tickChanged = me.tick !== store.tick;
  store.me = me; store.places = places; store.actors = actors; store.events = events; store.tick = me.tick; indexWorld();
  if (ghostTick === null) map.setWorld({ places, actors });
  updateTop();
  bus.emit('me'); bus.emit('events'); if (tickChanged) bus.emit('tick');
  panels.act?.update(); panels.time?.update();
}
const refreshSoon = debounce(() => refreshAll().catch(() => {}), 450);

function setGhost(t) {
  ghostTick = t;
  $('#ghostbar')?.remove();
  if (t !== null) $('#mapwrap').append(h('div.overlay#ghostbar', `Looking back: day ${t}`));
}

// ---------- tooltip / villager card ----------
function tooltip(info, ev) {
  const tip = $('#tooltip'); if (!info) { tip.classList.add('hidden'); return; }
  tip.classList.remove('hidden');
  if (info.type === 'actor') {
    const a = info.actor; const m = moodInfo(a.mood);
    tip.replaceChildren(h('b', a.name), h('span.m', h('i.dot', { style: { background: m.color } }), `${m.label}${a.job ? ' · ' + a.job.replace('_', ' ') : a.kind === 'player' ? ' · newcomer' : ''}`));
  } else {
    const p = info.place;
    tip.replaceChildren(h('b', p.name), ...(p.stock?.length ? p.stock.map((r) => h('div', `${r.item_name}: ${r.qty} @ ${money(r.price)}c`)) : [h('span.m', p.kind === 'home' ? 'A home' : 'No shelves here')]));
  }
  tip.style.left = `${Math.min(innerWidth - 250, ev.clientX + 14)}px`; tip.style.top = `${Math.min(innerHeight - 90, ev.clientY + 14)}px`;
}

function showVillager(a) {
  const card = $('#villager-card'); card.classList.remove('hidden');
  const home = store.places.find((p) => p.place_id === a.home_place_id);
  const isMe = a.actor_id === store.me?.actorId;
  card.replaceChildren(h('button.btn.icon.ghost.x', { 'aria-label': 'Close', onclick: (e) => { e.stopPropagation(); card.classList.add('hidden'); } }, '×'),
    h('h3', isMe ? `${a.name} (you)` : a.name), h('div.meta', `${a.job ? a.job.replace('_', ' ') : a.kind === 'player' ? 'newcomer' : 'villager'}${home ? ` · ${home.name}` : ''}`),
    h('div', { style: { marginBottom: '10px' } }, moodPill(a.mood)),
    isMe ? null : h('div.row', ['gift', 'rumor', 'hire'].map((act) => h('button.btn.sm', { onclick: () => { selectTab('act'); panels.act.openFor(act, { target: a.actor_id }); card.classList.add('hidden'); } }, ACTION_META[act].label))));
  card.onclick = (e) => e.stopPropagation();
}
function showPlace(p) {
  const card = $('#villager-card'); card.classList.remove('hidden');
  card.replaceChildren(h('button.btn.icon.ghost.x', { 'aria-label': 'Close', onclick: (e) => { e.stopPropagation(); card.classList.add('hidden'); } }, '×'), h('h3', p.name), h('div.meta', p.kind),
    p.stock?.length ? h('div', p.stock.map((r) => h('div', `${r.item_name}: ${r.qty} on the shelf at ${money(r.price)}c`))) : h('div', { style: { color: 'var(--muted)' } }, 'No shelves here.'),
    p.stock?.length ? h('div.row', { style: { marginTop: '10px' } }, ['trade', 'steal'].map((act) => h('button.btn.sm', { onclick: () => { selectTab('act'); panels.act.openFor(act, { place: p.place_id }); card.classList.add('hidden'); } }, ACTION_META[act].label))) : null);
  card.onclick = (e) => e.stopPropagation();
}

// ---------- ticker + live ripples ----------
function news(text, cascade, eventId, tick) {
  const t = $('#ticker'); const el = h('div.news', { class: cascade ? 'cascade' : '', onclick: () => { if (eventId) { selectTab('why'); panels.why.ask(eventId); } }, title: 'Click to ask why' }, h('span.d', `Day ${tick}`), h('span', text));
  t.append(el); while (t.children.length > 4) t.firstChild.remove();
  setTimeout(() => el.classList.add('out'), 9000); setTimeout(() => el.remove(), 9700);
}

async function onLive(d) {
  const id = String(d.event_id); if (seenEvents.has(id)) return; seenEvents.add(id);
  if (['day_start'].includes(d.action_type)) { refreshSoon(); return; }
  let e; try { e = await api.event(id); } catch { refreshSoon(); return; }
  const now = Date.now(); hop = now - lastWs > 1800 ? 0 : Math.min(hop + 1, 5); lastWs = now;
  const cascade = !(e.action_type in ACTION_META) || !e.actor_id;
  news(describe(e), cascade, id, e.tick);
  const from = eventPlaceId(e); const color = ACTION_META[e.action_type]?.hue || '#ff7a3d';
  const targets = eventTargets(e).map((x) => ({ id: x }));
  if (e.actor_id && from && store.actorById.get(e.actor_id)?.place_id !== from) targets.unshift({ id: e.actor_id });
  if (e.action_type === 'deliver') targets.push({ id: e.payload.to_place, place: true });
  if (ghostTick === null) { map.ripple({ fromPlace: from, fromActor: e.actor_id, targets, color, hop }); if (from) map.pulsePlace(from, color); }
  if (!(e.actor_id === store.me?.actorId)) sound.play('ripple');
  refreshSoon();
}

function afterAction(act, eventId) {
  toast({ gift: 'Your gift is on its way.', trade: 'A fair deal.', steal: 'Nobody saw… you hope.', rumor: 'The whisper is out.', build: 'Work begins.', hire: 'Hands for hire.', set_price: 'The new price is chalked up.', help_harvest: 'Many hands, light work.', sabotage: 'Sparks and silence.', feast: 'Let the feast begin!' }[act] || 'Done.', 'good');
  const pip = $$('.pip.full').pop(); pip?.classList.add('pop');
  seenEvents.add(String(eventId));
  if (!$('#live').classList.contains('live')) onLive({ event_id: eventId, action_type: act });
  seenEvents.delete(String(eventId));
  refreshAll().then(() => { if (phaseFromActions() === 'evening') { map.setPhase('evening'); toast('The sun sinks. End the day when you are ready.'); } });
}

// ---------- the day cycle & Evening Bell ----------
function stockSnapshot() {
  const m = new Map(); for (const p of store.places) for (const r of p.stock || []) m.set(`${p.place_id}:${r.item_id}`, { qty: r.qty, price: r.price, place: p.name, item: r.item_name });
  return m;
}
async function endDay() {
  if (ending) return; ending = true; $('#end-day-top').disabled = true;
  if (ghostTick !== null) { panels.time.leave(); }
  const before = { tick: store.tick, stock: stockSnapshot(), moods: new Map(store.actors.map((a) => [a.actor_id, a.mood])), events: new Set(store.events.map((e) => e.event_id)), me: structuredClone(store.me.state) };
  try {
    map.setPhase('evening'); await sleep(900); map.setPhase('night'); sound.play('night'); updateTop();
    const r = await api.advanceDay(); await sleep(600);
    await refreshAll(); map.setPhase('night');
    const story = await buildStory(before, r.tick);
    sound.play('bell'); map.setPhase('morning');
    showBell(story, r.tick);
  } catch (err) { toast(flavor(err), 'bad'); map.setPhase(phaseFromActions()); } finally { ending = false; $('#end-day-top').disabled = false; }
}

async function buildStory(before, newTick) {
  const paras = []; const fresh = store.events.filter((e) => !before.events.has(e.event_id)).sort((a, b) => Number(a.event_id) - Number(b.event_id));
  const cascades = fresh.filter((e) => e.is_cascade);
  // delayed consequences: effects whose root is days old (and ideally yours)
  const delayed = [];
  for (const e of cascades.slice(-3)) {
    try {
      const rows = await api.askWhy(e.event_id); if (rows.length < 2) continue;
      const root = await api.event(rows[0].event_id).catch(() => null); if (!root) continue;
      const ago = e.tick - root.tick; if (ago < 1) continue;
      const mine = root.actor_id === store.me.actorId;
      delayed.push({ e, root, ago, mine, why: rows[rows.length - 2]?.narrative });
    } catch { /* hidden trail */ }
  }
  for (const d of delayed) paras.push(`<em>${d.ago === 1 ? 'Yesterday' : `${d.ago} days ago`}</em>, ${d.mine ? 'you' : 'someone'} set something in motion: ${stripDot(describe(d.root)).replace(/^You /, 'you ')}. Today: ${describe(d.e)}${d.why ? ` ${d.why}` : ''}`);
  const nowStock = stockSnapshot();
  for (const [k, now] of nowStock) { const was = before.stock.get(k); if (!was) continue;
    const bits = []; if (was.qty !== now.qty) bits.push(`${was.qty} → ${now.qty} on the shelf`); if (Number(was.price) !== Number(now.price)) bits.push(`price ${money(was.price)}c → ${money(now.price)}c`);
    if (bits.length) paras.push(`<em>${now.place.replace(/^(\w+)'s /, '$1’s ')}</em> ${now.item}: ${bits.join(', ')}.`); }
  const moodChanged = store.actors.filter((a) => before.moods.has(a.actor_id) && before.moods.get(a.actor_id) !== a.mood);
  if (moodChanged.length) paras.push(`${moodChanged.slice(0, 3).map((a) => `<em>${a.name}</em> now feels ${a.mood}`).join('; ')}${moodChanged.length > 3 ? `, and ${moodChanged.length - 3} more shifted too` : ''}.`);
  const own = fresh.filter((e) => !e.is_cascade && e.actor_id && e.actor_id !== store.me.actorId && e.action_type in ACTION_META);
  for (const e of own.slice(0, 3)) paras.push(describe(e));
  if (!paras.length) paras.push('A quiet night. Nothing you can see has changed. Somewhere, a small chain may still be waiting to arrive.');
  let stats = null; try { const bell = await api.bell(); const row = bell.find((r) => r.tick === newTick) || bell[bell.length - 1]; stats = { ...row, top_score: Math.max(0, ...bell.map((r) => r.top_score)) }; } catch { /* ignore */ }
  const topCascade = cascades[cascades.length - 1] || fresh[fresh.length - 1];
  return { paras, stats, topCascade, newTick };
}
const stripDot = (t) => t.replace(/\.$/, '');

function showBell(story, tick) {
  const body = h('div.bell-story');
  story.paras.forEach((p, i) => { const el = document.createElement('p'); el.innerHTML = p.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])).replace(/&lt;em&gt;/g, '<em>').replace(/&lt;\/em&gt;/g, '</em>'); el.style.animationDelay = `${0.35 + i * 0.5}s`; body.append(el); });
  const st = story.stats;
  const close = modal([
    h('div.bell-hdr', s('svg', { class: 'bell-icon', viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', 'stroke-width': 1.6, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, ...svgFromString('<path d="M6 17V11a6 6 0 0 1 12 0v6l2 2H4z"/><path d="M10 21a2 2 0 0 0 4 0"/>')),
      h('div', h('h2', 'The Evening Bell'), h('div.sub', `Day ${tick - 1} is over. Day ${tick} begins.`))),
    body,
    st ? h('div.stat3', h('div', h('b', st.events_total), h('span', 'things happened')), h('div', h('b', st.cascade_events), h('span', 'were ripples')), h('div', h('b', st.top_score), h('span', 'biggest ripple so far'))) : null,
    h('div.modal-actions', story.topCascade ? h('button.btn', { onclick: () => { close(); selectTab('why'); panels.why.ask(story.topCascade.event_id); } }, iconSvg('ask', 16), 'Ask why') : null,
      h('button.btn.primary', { onclick: () => close() }, `Begin day ${tick}`)),
  ], { onClose: () => { map.setPhase('day'); sound.play('morning'); updateTop(); selectTab('act'); panels.village.update(); } });
}

// ---------- worlds ----------
async function switchBranch(branchId) {
  try {
    const r = await api.switchBranch(branchId);
    store.session = { ...store.session, token: r.token, branchId: r.branchId }; session.save(store.session);
    ghostTick = null; map.setView(null); setGhost(null);
    live?.close(); live = connectLive(onLive, (st) => $('#live').classList.toggle('live', st === 'live'));
    seenEvents = new Set(); store.branches = await api.branches(); await refreshAll();
    bus.emit('branch'); bus.emit('tick'); toast('You step into another version of Alderbrook.', 'good'); map.setPhase(phaseFromActions());
  } catch (err) { toast(flavor(err), 'bad'); }
}
function openFork(day) { selectTab('worlds'); panels.worlds.setForkDay(day ?? store.tick); }

init();

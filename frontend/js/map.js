// The living village map. One SVG, drawn by code from the places and actors
// the API returns (never hard-coded ids). Villagers are mood-faced markers that
// walk between home and work as the day turns; ripples travel along threads
// from the place where something happened to every villager it touches.
import { s, h, svgFromString, seeded, clamp, money, moodInfo, store } from './util.js';

const W = 1000; const H = 680; const CX = 500; const CY = 340;
const ITEM_COLOR = { bread: '#e8a94a', grain: '#d8c46a', flour: '#efe6d2' };

/** The village green is magnified: distance from the centre is compressed (power 0.42)
 *  so the crowded square stays readable while the far farms still fit. */
export function project(x, y) {
  const dx = x - 50; const dy = y - 50; const d = Math.hypot(dx, dy);
  if (d < 1e-6) return { x: CX, y: CY };
  const r = 10.1 * Math.pow(d, 0.42);
  return { x: CX + (dx / d) * r * 10.4, y: CY + (dy / d) * r * 6.9 };
}

const GLYPH = {
  market: `<g class="glyph"><rect class="g-wall" x="-22" y="-2" width="44" height="14" rx="1.5"/>
    <path class="g-awn a" d="M-25 -3 L-14 -3 L-16 -16 L-25 -3z"/><path class="g-awn b" d="M-14 -3 L-3 -3 L-3 -16 L-16 -16z"/>
    <path class="g-awn a" d="M-3 -3 L8 -3 L8 -16 L-3 -16z"/><path class="g-awn b" d="M8 -3 L19 -3 L16 -16 L8 -16z"/><path class="g-awn a" d="M19 -3 L25 -3 L25 -3 L16 -16z"/>
    <rect class="g-crate" x="-16" y="3" width="9" height="8"/><rect class="g-crate" x="-4" y="5" width="8" height="6"/><circle class="g-fruit" cx="12" cy="8" r="3.5"/></g>`,
  bakery: `<g class="glyph"><rect class="g-chim" x="7" y="-27" width="7" height="14"/><rect class="g-wall" x="-18" y="-7" width="36" height="22" rx="1"/>
    <path class="g-roof" d="M-23 -6 L0 -26 L23 -6z"/><rect class="g-door" x="-4" y="3" width="8" height="12"/><rect class="g-win lit" x="-14" y="0" width="6" height="6"/><rect class="g-win lit" x="8" y="0" width="6" height="6"/>
    <circle class="smoke s1" cx="10" cy="-30" r="3"/><circle class="smoke s2" cx="10" cy="-30" r="3"/><circle class="smoke s3" cx="10" cy="-30" r="3"/></g>`,
  mill: `<g class="glyph"><path class="g-wall" d="M-12 16 L-8 -10 L8 -10 L12 16z"/><path class="g-roof" d="M-11 -9 L0 -22 L11 -9z"/><rect class="g-door" x="-3" y="6" width="6" height="10"/>
    <g class="blades"><rect class="g-blade" x="-1.5" y="-34" width="3" height="24"/><rect class="g-blade" x="-1.5" y="-10" width="3" height="24" transform="translate(0 0)"/><rect class="g-blade" x="-26" y="-11.5" width="24" height="3"/><rect class="g-blade" x="2" y="-11.5" width="24" height="3"/></g><circle class="g-hub" cx="0" cy="-10" r="2.6"/></g>`,
  inn: `<g class="glyph"><rect class="g-wall" x="-22" y="-8" width="44" height="24" rx="1"/><path class="g-roof" d="M-27 -7 L-12 -24 L12 -24 L27 -7z"/>
    <rect class="g-door" x="-4" y="5" width="8" height="11"/><rect class="g-win lit" x="-17" y="-2" width="7" height="7"/><rect class="g-win lit" x="10" y="-2" width="7" height="7"/>
    <path class="g-chain" d="M24 -6 V-1"/><rect class="g-sign sway" x="19" y="-1" width="11" height="8" rx="1"/></g>`,
  well: `<g class="glyph"><ellipse class="g-stone" cx="0" cy="8" rx="13" ry="6"/><ellipse class="g-water" cx="0" cy="7" rx="8.500" ry="3.500"/>
    <rect class="g-post" x="-12" y="-12" width="3" height="20"/><rect class="g-post" x="9" y="-12" width="3" height="20"/><path class="g-roof" d="M-16 -11 L0 -22 L16 -11z"/><path class="g-chain" d="M0 -12 V2"/><rect class="g-crate" x="-2.500" y="2" width="5" height="4"/></g>`,
  farm: `<g class="glyph"><path class="g-field" d="M-30 -2 L26 -2 L32 18 L-24 18z"/><path class="g-furrow" d="M-27 4 L29 4M-25.500 9 L30 9M-24 14 L31 14"/>
    <rect class="g-wall barn" x="-28" y="-18" width="18" height="14"/><path class="g-roof" d="M-31 -17 L-19 -28 L-7 -17z"/><rect class="g-door" x="-22" y="-12" width="6" height="8"/>
    <path class="g-sheaf" d="M10 -2 l2 -9 l2 9 M18 -2 l2 -8 l2 8"/></g>`,
  home: `<g class="glyph" transform="scale(.82)"><rect class="g-wall" x="-13" y="-4" width="26" height="18" rx="1"/><path class="g-roof" d="M-17 -3 L0 -19 L17 -3z"/>
    <rect class="g-door" x="-3" y="5" width="6" height="9"/><rect class="g-win lit" x="5" y="1" width="5" height="5"/><rect class="g-chim" x="6" y="-17" width="5" height="9"/></g>`,
};

function faceNodes(mood, r = 9) {
  const m = moodInfo(mood); const k = r / 9;
  const eyes = {
    dot: '<circle cx="-3.200" cy="-2" r="1.200"/><circle cx="3.200" cy="-2" r="1.200"/>',
    wide: '<circle cx="-3.300" cy="-2" r="1.800" fill="#fff"/><circle cx="3.300" cy="-2" r="1.800" fill="#fff"/><circle cx="-3.300" cy="-2" r=".9"/><circle cx="3.300" cy="-2" r=".9"/>',
    angry: '<circle cx="-3.200" cy="-1.500" r="1.100"/><circle cx="3.200" cy="-1.500" r="1.100"/><path class="st" d="M-5.500 -5 L-1.500 -3.500M5.500 -5 L1.500 -3.500"/>',
    happy: '<path class="st" d="M-5.200 -1.200 q1.800 -2.600 3.600 0M1.600 -1.200 q1.800 -2.600 3.600 0"/>',
    down: '<path class="st" d="M-5 -2 h3.200M1.800 -2 h3.200"/>',
  }[m.eyes];
  const mouth = {
    smile: '<path class="st" d="M-3.500 2.600 Q0 6.200 3.500 2.600"/>',
    grin: '<path d="M-4 2.200 Q0 8.200 4 2.200z"/>',
    flat: '<path class="st" d="M-3 4.200 H3"/>',
    frown: '<path class="st" d="M-3.500 5.800 Q0 2.200 3.500 5.800"/>',
    wobble: '<path class="st" d="M-4 4.800 q1.300 -1.600 2.600 0 t2.600 0 t2.600 0"/>',
  }[m.mouth];
  return `<g transform="scale(${k})"><circle class="face-bg" r="9" fill="${m.color}"/>
    <g class="face-feat">${eyes}${mouth}</g></g>`;
}

function slotsAround(n, R) {
  // Upper arc only, so labels and shelf chips below the building stay readable.
  const out = []; const perRing = 6;
  for (let i = 0; i < n; i++) {
    const ring = Math.floor(i / perRing); const idx = i % perRing; const cnt = Math.min(perRing, n - ring * perRing);
    const a0 = (-195 * Math.PI) / 180; const a1 = (15 * Math.PI) / 180;
    const a = cnt === 1 ? -Math.PI * 0.62 : a0 + ((a1 - a0) * idx) / (cnt - 1);
    const r = R + ring * 17;
    out.push({ dx: Math.cos(a) * r * 1.2, dy: Math.sin(a) * r * 0.8 - 4 });
  }
  return out;
}

/** Nudge overlapping places apart (homes may sit closer than working buildings). */
function relaxPositions(places, centres) {
  const list = places.map((p) => ({ id: p.place_id, home: p.kind === 'home', c: centres.get(p.place_id) }));
  for (let it = 0; it < 80; it++) {
    for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) {
      const a = list[i]; const b = list[j]; const minX = a.home && b.home ? 62 : 92; const minY = a.home && b.home ? 50 : 70;
      const dx = b.c.x - a.c.x; const dy = b.c.y - a.c.y;
      const ox = minX - Math.abs(dx); const oy = minY - Math.abs(dy);
      if (ox > 0 && oy > 0) {
        if (ox / minX < oy / minY) { const m = ox / 2 * (dx >= 0 ? 1 : -1); a.c.x -= m; b.c.x += m; } else { const m = oy / 2 * (dy >= 0 ? 1 : -1); a.c.y -= m; b.c.y += m; }
      }
    }
    for (const a of list) { a.c.x = clamp(a.c.x, 60, W - 60); a.c.y = clamp(a.c.y, 56, H - 90); }
  }
}

export function createMap(svg, hooks = {}) {
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
  svg.replaceChildren();

  const defs = s('defs');
  defs.append(...svgFromString(`
    <radialGradient id="grass" cx="50%" cy="48%" r="75%"><stop offset="0" stop-color="var(--grass-1)"/><stop offset="1" stop-color="var(--grass-2)"/></radialGradient>
    <radialGradient id="lantern"><stop offset="0" stop-color="#ffcf7a" stop-opacity=".75"/><stop offset="1" stop-color="#ffcf7a" stop-opacity="0"/></radialGradient>
    <radialGradient id="vignette" cx="50%" cy="50%" r="72%"><stop offset=".6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".55"/></radialGradient>
    <filter id="soft"><feGaussianBlur stdDeviation="2.200"/></filter>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`));
  svg.append(defs);

  const gGround = s('g', { class: 'layer-ground' });
  const gScenery = s('g', { class: 'layer-scenery' });
  const gPlaces = s('g', { class: 'layer-places' });
  const gHomeMood = s('g', { class: 'layer-homemood' });
  const gMarkers = s('g', { class: 'layer-markers' });
  const gFx = s('g', { class: 'layer-fx' });
  const gSky = s('g', { class: 'layer-sky' });
  svg.append(gGround, gScenery, gPlaces, gHomeMood, gMarkers, gFx, gSky);

  // ---------- state ----------
  let places = []; let actors = []; let phase = 'day'; let view = null; let pick = null;
  const placeNodes = new Map(); const markerNodes = new Map(); const homeFaces = new Map();
  const centres = new Map();       // place_id -> {x,y}
  let prevStock = new Map();       // "p:i" -> qty (for floating deltas)
  let sceneryKey = '';

  const stockOf = () => {
    if (view) return view.stock;
    const m = new Map();
    for (const p of places) for (const r of p.stock || []) m.set(`${p.place_id}:${r.item_id}`, { qty: r.qty, price: r.price, name: r.item_name });
    return m;
  };
  const moodOf = (a) => (view?.mood?.has(a.actor_id) ? view.mood.get(a.actor_id) : a.mood);

  // ---------- static scene ----------
  function buildGround() {
    gGround.replaceChildren(
      s('rect', { x: -600, y: -400, width: W + 1200, height: H + 800, fill: 'url(#grass)' }),
      s('g', { class: 'grass-tufts' }),
    );
    const rnd = seeded(7); const tufts = gGround.querySelector('.grass-tufts');
    for (let i = 0; i < 170; i++) {
      const x = rnd() * W; const y = rnd() * H; const hh = 3 + rnd() * 5;
      tufts.append(s('path', { d: `M${x} ${y} l-1.500 -${hh} M${x} ${y} l.5 -${hh + 1} M${x} ${y} l2 -${hh - 1}`, class: 'tuft' }));
    }
  }

  function buildScenery() {
    gScenery.replaceChildren();
    // river
    gScenery.append(
      s('path', { class: 'river-bank', d: 'M-700 650 L-20 640 C180 606 360 672 540 632 S860 596 1020 650 L1700 660' }),
      s('path', { class: 'river', d: 'M-700 650 L-20 640 C180 606 360 672 540 632 S860 596 1020 650 L1700 660' }),
      s('path', { class: 'river-shimmer', d: 'M-700 650 L-20 640 C180 606 360 672 540 632 S860 596 1020 650 L1700 660' }),
    );
    // roads: every non-market place to the market, homes to the nearest working place
    const market = places.find((p) => p.kind === 'market') || places[0];
    const roads = s('g', { class: 'roads' });
    for (const p of places) {
      if (p === market) continue;
      let to = market;
      if (p.kind === 'home') {
        const works = places.filter((q) => q.kind !== 'home');
        to = works.reduce((best, q) => (Math.hypot(q.x - p.x, q.y - p.y) < Math.hypot(best.x - p.x, best.y - p.y) ? q : best), works[0]);
      }
      const a = centres.get(p.place_id); const b = centres.get(to.place_id); if (!a || !b) continue;
      const mx = (a.x + b.x) / 2; const my = (a.y + b.y) / 2; const nx = -(b.y - a.y); const ny = b.x - a.x; const len = Math.hypot(nx, ny) || 1;
      const bend = (p.place_id % 2 ? 1 : -1) * Math.min(30, len * 0.12);
      roads.append(s('path', { class: p.kind === 'home' ? 'road small' : 'road', d: `M${a.x} ${a.y} Q${mx + (nx / len) * bend} ${my + (ny / len) * bend} ${b.x} ${b.y}` }));
    }
    gScenery.append(roads);
    // trees (deterministic, kept off places and the river)
    const rnd = seeded(42); const trees = s('g', { class: 'trees' });
    let tries = 0; let n = 0;
    while (n < 30 && tries++ < 600) {
      const x = 20 + rnd() * (W - 40); const y = 24 + rnd() * (H - 60);
      if ([...centres.values()].some((c) => Math.hypot(c.x - x, (c.y - y) * 1.15) < 96)) continue;
      const rv = 640 - 6 * Math.sin(x / 140) - 10; if (Math.abs(y - rv) < 46) continue;
      const k = 0.7 + rnd() * 0.7; const pine = rnd() > 0.5;
      trees.append(s('g', { class: `tree ${pine ? 'pine' : 'oak'}`, transform: `translate(${x.toFixed(1)} ${y.toFixed(1)}) scale(${k.toFixed(2)})`, style: `animation-delay:${(rnd() * -6).toFixed(1)}s` },
        s('rect', { class: 't-trunk', x: -2, y: 0, width: 4, height: 9 }),
        pine ? s('path', { class: 't-leaf', d: 'M0 -22 L9 -4 L-9 -4z M0 -14 L11 3 L-11 3z' }) : s('circle', { class: 't-leaf', cx: 0, cy: -6, r: 10 })));
    }
    gScenery.append(trees);
    // clouds + fireflies + stars live in the sky layer
    gSky.replaceChildren();
    const clouds = s('g', { class: 'clouds' });
    for (let i = 0; i < 4; i++) {
      const y = 50 + i * 120 + (i % 2) * 30;
      clouds.append(s('g', { class: 'cloud', style: `animation-duration:${90 + i * 25}s;animation-delay:${-i * 30}s`, transform: `translate(0 ${y})` },
        s('ellipse', { cx: 0, cy: 0, rx: 70, ry: 16 }), s('ellipse', { cx: 40, cy: -8, rx: 40, ry: 14 }), s('ellipse', { cx: -36, cy: -6, rx: 34, ry: 12 })));
    }
    const tint = s('rect', { class: 'sky-tint', x: -600, y: -400, width: W + 1200, height: H + 800 });
    const vig = s('rect', { class: 'vignette', x: -600, y: -400, width: W + 1200, height: H + 800, fill: 'url(#vignette)' });
    const stars = s('g', { class: 'stars' }); const rs = seeded(9);
    for (let i = 0; i < 60; i++) stars.append(s('circle', { cx: rs() * W, cy: rs() * H * 0.9, r: 0.6 + rs() * 1.2, style: `animation-delay:${(rs() * -5).toFixed(1)}s` }));
    const flies = s('g', { class: 'fireflies' });
    for (let i = 0; i < 18; i++) flies.append(s('circle', { class: 'firefly', cx: 40 + rs() * (W - 80), cy: 60 + rs() * (H - 140), r: 2, style: `animation-delay:${(rs() * -8).toFixed(1)}s;animation-duration:${6 + rs() * 6}s` }));
    gSky.append(clouds, tint, stars, flies, vig);
  }

  function buildPlaces() {
    gPlaces.replaceChildren(); placeNodes.clear(); homeFaces.clear(); gHomeMood.replaceChildren();
    // draw back-to-front so nearer (lower) places overlap farther ones
    for (const p of [...places].sort((a, b) => centres.get(a.place_id).y - centres.get(b.place_id).y)) {
      const c = centres.get(p.place_id);
      const g = s('g', { class: `place kind-${p.kind}`, 'data-place': p.place_id, transform: `translate(${c.x} ${c.y})`, tabindex: 0, role: 'button', 'aria-label': p.name });
      const lantern = s('circle', { class: 'lantern', r: p.kind === 'home' ? 34 : 54, fill: 'url(#lantern)' });
      const glyph = svgFromString(GLYPH[p.kind] || GLYPH.home);
      const short = p.kind === 'home' ? p.name.replace(/^Home of /, '') : p.name;
      const label = s('text', { class: `plabel ${p.kind === 'home' ? 'small' : ''}`, y: p.kind === 'home' ? 25 : 31, 'text-anchor': 'middle' }, short);
      const ring = s('circle', { class: 'pick-ring', r: p.kind === 'home' ? 30 : 38 });
      const chips = s('g', { class: 'chips', transform: `translate(0 ${p.kind === 'home' ? 30 : 38})` });
      g.append(lantern, ring, ...glyph, label, chips);
      g.addEventListener('click', (ev) => { ev.stopPropagation(); onPlaceClick(p); });
      g.addEventListener('keydown', (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); onPlaceClick(p); } });
      g.addEventListener('pointerenter', (ev) => hooks.onHover?.({ type: 'place', place: p }, ev));
      g.addEventListener('pointermove', (ev) => hooks.onHover?.({ type: 'place', place: p }, ev));
      g.addEventListener('pointerleave', () => hooks.onHover?.(null));
      gPlaces.append(g); placeNodes.set(p.place_id, { g, chips });
      if (p.kind === 'home') {
        const f = s('g', { class: 'homeface', transform: `translate(${c.x} ${c.y - 34})` }, s('g', { class: 'bob' }));
        gHomeMood.append(f); homeFaces.set(p.place_id, f.firstChild);
      }
    }
  }

  function renderChips(animate) {
    const st = stockOf();
    for (const p of places) {
      const node = placeNodes.get(p.place_id); if (!node) continue;
      const rows = [...st.entries()].filter(([k]) => Number(k.split(':')[0]) === p.place_id).map(([k, v]) => ({ item: Number(k.split(':')[1]), ...v }));
      node.chips.replaceChildren();
      const widths = rows.map((r) => 58 + String(r.qty).length * 3 + String(money(r.price)).length * 4);
      const total = widths.reduce((a, b) => a + b + 4, -4); let x = -total / 2;
      rows.forEach((r, i) => {
        const nm = r.name || store.itemById.get(r.item)?.name || '?';
        const key = `${p.place_id}:${r.item}`; const was = prevStock.get(key);
        const chip = s('g', { class: `chip ${r.qty === 0 ? 'empty' : r.qty < 10 ? 'low' : ''}`, transform: `translate(${x} 0)` },
          s('rect', { width: widths[i], height: 15, rx: 7.500 }),
          s('circle', { cx: 8, cy: 7.500, r: 3.500, fill: ITEM_COLOR[nm] || '#ccc' }),
          s('text', { x: 15, y: 11 }, `${r.qty}`),
          s('text', { class: 'pr', x: widths[i] - 5, y: 11, 'text-anchor': 'end' }, `${money(r.price)}c`));
        chip.append(s('title', {}, `${nm}: ${r.qty} on the shelf at ${money(r.price)} coins each`));
        node.chips.append(chip);
        if (animate && !view && was !== undefined && was !== r.qty) floatText(p.place_id, `${r.qty - was > 0 ? '+' : '−'}${Math.abs(r.qty - was)} ${nm}`, r.qty - was > 0 ? '#8fcf8a' : '#ff8a6a');
        x += widths[i] + 4;
      });
      if (!view) for (const r of rows) prevStock.set(`${p.place_id}:${r.item}`, r.qty);
    }
  }

  function floatText(placeId, text, color) {
    const c = centres.get(placeId); if (!c) return;
    const t = s('text', { class: 'floattext', x: c.x, y: c.y - 30, 'text-anchor': 'middle', fill: color }, text);
    gFx.append(t); setTimeout(() => t.remove(), 2400);
  }

  // ---------- villagers ----------
  function targetPlaceFor(a) {
    const night = phase === 'night' || phase === 'evening';
    if (a.kind === 'player') return night ? (nearestKind('inn') ?? a.place_id) : a.place_id;
    return night ? (a.home_place_id ?? a.place_id) : (a.work_place_id ?? a.home_place_id ?? a.place_id);
  }
  function nearestKind(kind) { return places.find((p) => p.kind === kind)?.place_id ?? null; }

  function buildMarkers() {
    gMarkers.replaceChildren(); markerNodes.clear();
    for (const a of actors) {
      const isMe = store.me && a.actor_id === store.me.actorId;
      const g = s('g', { class: `villager ${a.kind} ${isMe ? 'me' : ''}`, 'data-actor': a.actor_id, tabindex: 0, role: 'button', 'aria-label': a.name });
      const halo = s('circle', { class: 'halo', r: 15 });
      const body = s('g', { class: 'body' });
      const tag = isMe ? s('text', { class: 'youtag', y: -15, 'text-anchor': 'middle' }, 'you') : null;
      g.append(halo, body, tag);
      g.addEventListener('click', (ev) => { ev.stopPropagation(); onActorClick(a); });
      g.addEventListener('keydown', (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); onActorClick(a); } });
      g.addEventListener('pointerenter', (ev) => hooks.onHover?.({ type: 'actor', actor: a }, ev));
      g.addEventListener('pointermove', (ev) => hooks.onHover?.({ type: 'actor', actor: a }, ev));
      g.addEventListener('pointerleave', () => hooks.onHover?.(null));
      gMarkers.append(g); markerNodes.set(a.actor_id, { g, body, mood: null });
    }
    layoutMarkers(false);
  }

  function layoutMarkers(smooth = true) {
    const groups = new Map();
    for (const a of actors) { const pid = targetPlaceFor(a); if (!groups.has(pid)) groups.set(pid, []); groups.get(pid).push(a); }
    for (const [pid, list] of groups) {
      const c = centres.get(pid) || { x: CX, y: CY };
      const p = placeNodes.get(pid) ? places.find((q) => q.place_id === pid) : null;
      const R = (p?.kind === 'home' ? 26 : 36) + Math.max(0, list.length - 4) * 3;
      list.sort((x, y) => x.actor_id - y.actor_id);
      const slots = slotsAround(list.length, R);
      list.forEach((a, i) => {
        const n = markerNodes.get(a.actor_id); if (!n) return;
        const tx = c.x + slots[i].dx; const ty = c.y + slots[i].dy;
        n.pos = { x: tx, y: ty, place: pid };
        if (!smooth) n.g.classList.add('nosmooth');
        n.g.style.transform = `translate(${tx.toFixed(1)}px, ${ty.toFixed(1)}px)`;
        if (!smooth) requestAnimationFrame(() => requestAnimationFrame(() => n.g.classList.remove('nosmooth')));
      });
    }
    renderMoods();
  }

  function renderMoods() {
    for (const a of actors) {
      const n = markerNodes.get(a.actor_id); if (!n) continue;
      const m = moodOf(a);
      if (n.mood !== m) { n.mood = m; n.body.replaceChildren(...svgFromString(faceNodes(m, a.kind === 'player' ? 10 : 9))); n.g.dataset.mood = m || ''; }
    }
    // faces above homes: the most common mood among the residents
    for (const [pid, holder] of homeFaces) {
      const res = actors.filter((a) => a.home_place_id === pid && a.kind !== 'player');
      if (!res.length) { holder.replaceChildren(); continue; }
      const count = new Map(); for (const a of res) count.set(moodOf(a), (count.get(moodOf(a)) || 0) + 1);
      const top = [...count.entries()].sort((x, y) => y[1] - x[1])[0][0];
      if (holder.dataset.mood !== String(top)) { holder.dataset.mood = String(top); holder.replaceChildren(...svgFromString(faceNodes(top, 6.500))); }
    }
  }

  // ---------- interaction ----------
  function onPlaceClick(p) {
    if (pick?.type === 'place' && (!pick.ids || pick.ids.has(p.place_id))) { const cb = pick.onPick; setPick(null); cb(p.place_id); return; }
    if (pick) return;
    hooks.onSelectPlace?.(p);
  }
  function onActorClick(a) {
    if (pick?.type === 'actor' && (!pick.ids || pick.ids.has(a.actor_id))) { const cb = pick.onPick; setPick(null); cb(a.actor_id); return; }
    if (pick) return;
    hooks.onSelectActor?.(a);
  }
  function setPick(p) {
    pick = p; svg.classList.toggle('picking', !!p);
    for (const [id, n] of placeNodes) n.g.classList.toggle('pickable', !!p && p.type === 'place' && (!p.ids || p.ids.has(id)));
    for (const [id, n] of markerNodes) n.g.classList.toggle('pickable', !!p && p.type === 'actor' && (!p.ids || p.ids.has(id)));
    hooks.onPickMode?.(p);
  }

  // ---------- effects ----------
  const posOfActor = (id) => markerNodes.get(Number(id))?.pos || null;
  const posOfPlace = (id) => centres.get(Number(id)) || null;
  function ring(at, color, delay = 0, max = 90) {
    const c = s('circle', { class: 'ripple-ring', cx: at.x, cy: at.y, r: 8, stroke: color, style: `animation-delay:${delay}ms;--max:${max}` });
    gFx.append(c); setTimeout(() => c.remove(), 1800 + delay);
  }
  /** A ripple: rings at the origin, then a glowing thread to each affected villager. */
  function ripple({ fromPlace, fromActor, targets = [], color = '#f2b84b', hop = 0 }) {
    const from = (fromPlace && posOfPlace(fromPlace)) || (fromActor && posOfActor(fromActor)) || { x: CX, y: CY };
    const base = hop * 900;
    ring(from, color, base, 70); ring(from, color, base + 220, 110);
    targets.slice(0, 8).forEach((t, i) => {
      const to = t.place ? posOfPlace(t.id) : posOfActor(t.id); if (!to) return;
      const d = base + 260 + i * 90;
      const mx = (from.x + to.x) / 2; const my = (from.y + to.y) / 2 - Math.min(50, Math.hypot(to.x - from.x, to.y - from.y) * 0.25);
      const path = `M${from.x} ${from.y} Q${mx} ${my} ${to.x} ${to.y}`;
      const thread = s('path', { class: 'thread', d: path, stroke: color, style: `animation-delay:${d}ms` });
      const spark = s('circle', { class: 'spark', r: 3.200, fill: color, style: `animation-delay:${d}ms` },
        s('animateMotion', { dur: '0.9s', begin: `${d}ms`, path, fill: 'freeze', calcMode: 'spline', keySplines: '.3 .1 .3 1', keyTimes: '0;1' }));
      gFx.append(thread, spark);
      setTimeout(() => { ring(to, color, 0, 36); markerNodes.get(Number(t.id))?.g.classList.add('bump'); setTimeout(() => markerNodes.get(Number(t.id))?.g.classList.remove('bump'), 700); }, d + 800);
      setTimeout(() => { thread.remove(); spark.remove(); }, d + 1900);
    });
  }
  function pulsePlace(id, color = '#f2b84b') { const p = posOfPlace(id); if (p) { ring(p, color, 0, 60); placeNodes.get(Number(id))?.g.classList.add('flash'); setTimeout(() => placeNodes.get(Number(id))?.g.classList.remove('flash'), 900); } }
  function focus({ places: pl = [], actors: ac = [] } = {}, ms = 2200) {
    const els = [...pl.map((i) => placeNodes.get(Number(i))?.g), ...ac.map((i) => markerNodes.get(Number(i))?.g)].filter(Boolean);
    els.forEach((e) => e.classList.add('focus')); setTimeout(() => els.forEach((e) => e.classList.remove('focus')), ms);
  }

  // ---------- camera and speech ----------
  let vb = { x: 0, y: 0, w: W, h: H }; let raf = 0;
  const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  function moveCamera(t, ms = 750) {
    cancelAnimationFrame(raf);
    if (reduce) { vb = { ...t }; svg.setAttribute('viewBox', `${vb.x} ${vb.y} ${vb.w} ${vb.h}`); return; }
    const from = { ...vb }; const t0 = performance.now();
    const step = (now) => {
      const k = Math.min(1, (now - t0) / ms); const e = 1 - Math.pow(1 - k, 3);
      vb = { x: from.x + (t.x - from.x) * e, y: from.y + (t.y - from.y) * e, w: from.w + (t.w - from.w) * e, h: from.h + (t.h - from.h) * e };
      svg.setAttribute('viewBox', `${vb.x.toFixed(1)} ${vb.y.toFixed(1)} ${vb.w.toFixed(1)} ${vb.h.toFixed(1)}`);
      if (k < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
  }
  /** Glide the camera in on a place while a scene set there is on screen. */
  function focusPlace(id) {
    const c = centres.get(Number(id)); if (!c) return;
    const w = 520; const h2 = (w * H) / W;
    moveCamera({ x: clamp(c.x - w / 2, 0, W - w), y: clamp(c.y - h2 / 2 - 10, 0, H - h2), w, h: h2 });
    pulsePlace(id, '#ffd98a');
  }
  const unfocus = () => moveCamera({ x: 0, y: 0, w: W, h: H });
  /** A short speech bubble above a villager. */
  function say(actorId, text) {
    const n = markerNodes.get(Number(actorId)); if (!n?.pos || !text) return;
    const words = text.split(' '); const lines = []; let cur = '';
    for (const wd of words) { if ((cur + ' ' + wd).trim().length > 24) { lines.push(cur); cur = wd; } else cur = (cur + ' ' + wd).trim(); }
    if (cur) lines.push(cur);
    const wpx = Math.max(...lines.map((l) => l.length)) * 5.6 + 16; const hpx = lines.length * 13 + 10;
    const g = s('g', { class: 'bubble', transform: `translate(${n.pos.x} ${n.pos.y - 26})` },
      s('path', { d: `M${-wpx / 2} ${-hpx} h${wpx} a6 6 0 0 1 6 6 v${hpx - 12} a6 6 0 0 1 -6 6 h${-wpx / 2 + 8} l-5 7 l-1 -7 h${-wpx / 2 + 1} a6 6 0 0 1 -6 -6 v${-(hpx - 12)} a6 6 0 0 1 6 -6 z`, class: 'bubble-bg' }),
      ...lines.map((l, i) => s('text', { x: 0, y: -hpx + 15 + i * 13, 'text-anchor': 'middle', class: 'bubble-t' }, l)));
    gFx.append(g); setTimeout(() => g.remove(), 5600);
  }

  // ---------- public api ----------
  function setWorld(world) {
    places = world.places; actors = world.actors;
    const key = places.map((p) => `${p.place_id}:${p.x}:${p.y}`).join('|');
    if (key !== sceneryKey) {
      sceneryKey = key; centres.clear();
      for (const p of places) centres.set(p.place_id, project(p.x, p.y));
      relaxPositions(places, centres);
      buildGround(); buildPlaces(); buildScenery(); prevStock = new Map();
    }
    renderChips(true);
    const ids = actors.map((a) => a.actor_id).join(',');
    if (svg.dataset.actors !== ids || !!store.me !== (svg.dataset.hasMe === '1')) { svg.dataset.actors = ids; svg.dataset.hasMe = store.me ? '1' : '0'; buildMarkers(); } else layoutMarkers(true);
  }
  function setPhase(p) {
    phase = p; svg.dataset.phase = p;
    ['morning', 'day', 'evening', 'night'].forEach((x) => svg.classList.toggle(`phase-${x}`, x === p));
    layoutMarkers(true);
  }
  function setView(v) { view = v; svg.classList.toggle('ghost', !!v); renderChips(false); renderMoods(); }
  const markerRect = (id) => markerNodes.get(Number(id))?.g.getBoundingClientRect() || null;
  const placeRect = (id) => placeNodes.get(Number(id))?.g.getBoundingClientRect() || null;
  return { setWorld, setPhase, setView, ripple, pulsePlace, focus, setPick, focusPlace, unfocus, say, floatText, markerRect, placeRect, get phase() { return phase; }, get picking() { return pick; } };
}

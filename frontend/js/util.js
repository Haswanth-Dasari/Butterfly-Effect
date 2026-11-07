// Small shared helpers: DOM, formatting, a tiny event bus and the shared world store.
// Make replaceChildren/append ignore null/undefined/false (so `cond ? node : null` is safe everywhere).
for (const m of ['replaceChildren', 'append', 'prepend']) {
  const orig = Element.prototype[m];
  Element.prototype[m] = function patched(...kids) { return orig.apply(this, kids.flat(Infinity).filter((k) => k !== null && k !== undefined && k !== false)); };
}

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

/** Hyperscript: h('div.card#id', {onclick}, child, 'text', ...) */
export function h(tag, attrs, ...kids) {
  const m = tag.match(/^([a-z0-9]+)?((?:[.#][\w-]+)*)$/i);
  const el = document.createElement(m[1] || 'div');
  for (const part of (m[2].match(/[.#][\w-]+/g) || [])) {
    if (part[0] === '.') el.classList.add(part.slice(1)); else el.id = part.slice(1);
  }
  if (attrs !== null && attrs !== undefined && attrs !== false && (typeof attrs !== 'object' || attrs instanceof Node || Array.isArray(attrs))) { kids.unshift(attrs); attrs = null; }
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.classList.add(...String(v).split(' ').filter(Boolean));
    else if (k === 'dataset') Object.assign(el.dataset, v);
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (v === true) el.setAttribute(k, '');
    else el.setAttribute(k, v);
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid === null || kid === undefined || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

const SVGNS = 'http://www.w3.org/2000/svg';
/** SVG hyperscript. */
export function s(tag, attrs, ...kids) {
  const el = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs || {})) { if (v !== null && v !== undefined && v !== false) el.setAttribute(k, v); }
  for (const kid of kids.flat(Infinity)) { if (kid !== null && kid !== undefined && kid !== false) el.append(kid instanceof Node ? kid : document.createTextNode(String(kid))); }
  return el;
}
/** Parse trusted, static SVG markup (our own icon strings) into nodes. */
export const svgFromString = (str) => {
  const d = new DOMParser().parseFromString(`<svg xmlns="${SVGNS}">${str}</svg>`, 'image/svg+xml');
  return [...d.documentElement.childNodes].map((n) => document.importNode(n, true));
};

export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const money = (n) => (Math.round(Number(n) * 100) / 100).toFixed(2).replace(/\.00$/, '');
export const cap = (str) => (str ? str[0].toUpperCase() + str.slice(1) : str);
export const plural = (n, one, many) => `${n} ${n === 1 ? one : many || one + 's'}`;
export function debounce(fn, ms) {
  let t; const d = (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
  d.cancel = () => clearTimeout(t); return d;
}
/** Deterministic PRNG so the scenery (trees, clouds) is the same every visit. */
export function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export class Bus {
  constructor() { this.m = new Map(); }
  on(ev, fn) { (this.m.get(ev) || this.m.set(ev, new Set()).get(ev)).add(fn); return () => this.m.get(ev).delete(fn); }
  emit(ev, ...a) { for (const fn of [...(this.m.get(ev) || [])]) { try { fn(...a); } catch (e) { console.error(`[bus:${ev}]`, e); } } }
}
export const bus = new Bus();

/** The one shared world model. Panels read it and listen on the bus. */
export const store = {
  session: null,            // {token, actorId, branchId, name}
  tick: 0, me: null, places: [], actors: [], items: [], events: [], branches: [],
  placeById: new Map(), actorById: new Map(), itemById: new Map(),
};
export function indexWorld() {
  store.placeById = new Map(store.places.map((p) => [p.place_id, p]));
  store.actorById = new Map(store.actors.map((a) => [a.actor_id, a]));
  store.itemById = new Map(store.items.map((i) => [i.item_id, i]));
}

export const MOODS = {
  content:  { color: '#8fcf8a', mouth: 'smile',  eyes: 'dot' },
  happy:    { color: '#ffd166', mouth: 'grin',   eyes: 'dot' },
  grateful: { color: '#ff9ecb', mouth: 'grin',   eyes: 'happy' },
  curious:  { color: '#5fd8cc', mouth: 'flat',   eyes: 'wide' },
  sad:      { color: '#7a96ff', mouth: 'frown',  eyes: 'dot' },
  angry:    { color: '#ff6a5d', mouth: 'frown',  eyes: 'angry' },
  afraid:   { color: '#b794f4', mouth: 'wobble', eyes: 'wide' },
  shunned:  { color: '#9aa1ae', mouth: 'frown',  eyes: 'down' },
};
export const moodInfo = (m) => ({ label: m || 'unknown', ...(MOODS[m] || { color: '#c9c3b2', mouth: 'flat', eyes: 'dot' }) });

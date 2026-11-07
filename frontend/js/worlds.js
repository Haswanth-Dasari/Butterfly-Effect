// Rewind & Parallel Villages: fork from any day, hop between villages, and
// compare two of them. The original village is never touched.
import { h, store, bus, money, moodInfo } from './util.js';
import { api, flavor, session } from './api.js';
import { project } from './map.js';
import { s } from './util.js';
import { moodPill, toast, modal } from './ui.js';
import { iconSvg } from './narrate.js';

const parseKV = (v) => { if (!v) return null; const o = {}; for (const m of String(v).matchAll(/(\w+)=([\d.]+)/g)) o[m[1]] = Number(m[2]); return o; };
const parseJ = (v) => { try { return v ? JSON.parse(v) : null; } catch { return null; } };

export function createWorldsPanel(ctx) {
  const root = h('div'); const tree = h('div.btree'); const cmpOut = h('div'); let other = '';
  const forkBox = h('div');

  async function reload() {
    try { store.branches = await api.branches(); } catch (err) { tree.replaceChildren(h('div.cold', flavor(err))); return; }
    drawTree(); drawFork(); drawCmpSelect();
  }
  function node(b) {
    const kids = store.branches.filter((x) => x.parent_id === b.branch_id);
    const cur = b.branch_id === store.session.branchId;
    return h('div.bnode', { class: cur ? 'cur' : '' },
      h('div', h('b', b.name), h('small', `${b.parent_id ? 'a parallel village' : 'the original village'} · now day ${b.tick}`)),
      cur ? h('span', { style: { color: 'var(--teal)', fontSize: '13px' } }, 'you are here')
        : b.you_live_here ? h('button.btn.sm', { onclick: () => ctx.switchBranch(b.branch_id) }, 'Go there') : h('span', { style: { color: 'var(--faint)', fontSize: '12px' }, title: 'This village split off before you arrived' }, 'you were not here'),
      kids.length ? h('div.kids', kids.map(node)) : null);
  }
  function drawTree() { const roots = store.branches.filter((b) => !b.parent_id); tree.replaceChildren(...(roots.length ? roots.map(node) : [h('div.empty', 'No villages yet.')])); }

  function drawFork() {
    const max = store.tick; const day = h('input', { type: 'number', min: 0, max, value: ctx.forkDay ?? max, 'aria-label': 'Day to rewind to' });
    const name = h('input', { type: 'text', maxlength: 40, placeholder: 'What if I had… (name this village)', 'aria-label': 'Name of the new village' });
    const strat = h('select', { 'aria-label': 'Strategy' }, [['snapshot_delta', 'Snapshot + replay (balanced)'], ['replay', 'Full replay (slowest, always works)'], ['cow', 'Copy-on-write (instant, only from today)']].map(([v, l]) => h('option', { value: v }, l)));
    forkBox.replaceChildren(
      h('div.sect', 'Rewind & fork'), h('p.sub', { style: { marginTop: '-4px' } }, 'Go back to any day and take a different path. A second village grows beside the first; the original stays exactly as it was.'),
      h('div.field', h('label', 'Back to day'), day), h('div.field', h('label', 'Name'), name), h('div.field', h('label', 'How the database rebuilds the past'), strat),
      h('button.btn.primary', { onclick: async (e) => {
        const t = Number(day.value); if (!Number.isInteger(t) || t < 0 || t > max) return toast('Choose a day between 0 and today.', 'bad');
        e.target.disabled = true;
        try { const r = await api.fork(t, name.value.trim() || `What if (day ${t})`, strat.value); toast('A parallel village begins…', 'good'); ctx.forkDay = null; await reload(); if (store.branches.find((b) => b.branch_id === r.childBranchId)?.you_live_here) ctx.switchBranch(r.childBranchId); }
        catch (err) { toast(flavor(err), 'bad'); } finally { e.target.disabled = false; }
      } }, iconSvg('worlds', 18), 'Create parallel village'));
  }

  function drawCmpSelect() {
    const others = store.branches.filter((b) => b.branch_id !== store.session.branchId);
    if (!others.length) { cmpOut.replaceChildren(h('div.empty', 'Fork a village, then compare the two here.')); return; }
    if (!others.some((b) => String(b.branch_id) === other)) other = String(others[0].branch_id);
    const sel = h('select', { onchange: (e) => { other = e.target.value; compare(); } }, others.map((b) => h('option', { value: b.branch_id, selected: String(b.branch_id) === other }, b.name)));
    cmpOut.replaceChildren(h('div.sect', 'Compare villages'), h('div.field', h('label', `This village vs`), sel), h('div#cmp-body'));
    compare();
  }

  async function compare() {
    const body = cmpOut.querySelector('#cmp-body'); if (!body) return;
    body.replaceChildren(h('div.skeleton'), h('div.skeleton', { style: { width: '70%' } }));
    const a = store.session.branchId; const b = Number(other); const bn = store.branches.find((x) => x.branch_id === b)?.name || 'Other';
    let rows; try { rows = await api.diff(a, b); } catch (err) { body.replaceChildren(h('div.cold', flavor(err))); return; }
    const stock = rows.filter((r) => r.kind === 'stock'); const ent = rows.filter((r) => r.kind === 'entity');
    const stockPlaces = new Set(stock.map((r) => r.key.split(' / ')[0]));
    const moodA = new Map(); const moodB = new Map();
    for (const r of ent) { const actor = store.actors.find((x) => x.name === r.key); const A = parseJ(r.a_value); const B = parseJ(r.b_value); if (actor) { moodA.set(actor.actor_id, A?.mood); moodB.set(actor.actor_id, B?.mood); } }
    const mini = (title, moods, side) => h('figure', miniMap(moods, stockPlaces), h('figcaption', title));
    body.replaceChildren(
      h('div.cmpmaps', mini('This village', moodA, 'a'), mini(bn, moodB, 'b')),
      h('p.sub', { style: { marginTop: '8px' } }, rows.length ? `${stock.length} shelf difference${stock.length === 1 ? '' : 's'}, ${ent.length} villager difference${ent.length === 1 ? '' : 's'}. Gold rings mark shelves that differ.` : 'These two villages are still identical.'),
      stock.length ? h('table.cmp', h('thead', h('tr', h('th', 'Shelf'), h('th', 'Here'), h('th', bn))), h('tbody', stock.map((r) => { const A = parseKV(r.a_value); const B = parseKV(r.b_value);
        return h('tr', h('td', r.key.replace("'s ", ' ')), h('td.num', A ? `${A.qty} @ ${money(A.price)}c` : '—'), h('td.num', B ? `${B.qty} @ ${money(B.price)}c` : '—')); }))) : null,
      ent.length ? h('table.cmp', { style: { marginTop: '10px' } }, h('thead', h('tr', h('th', 'Villager'), h('th', 'Here'), h('th', bn))), h('tbody', ent.map((r) => { const A = parseJ(r.a_value); const B = parseJ(r.b_value);
        return h('tr', h('td', r.key), h('td', A?.mood ? moodPill(A.mood) : '—'), h('td', B?.mood ? moodPill(B.mood) : '—')); }))) : null);
  }

  function miniMap(moods, hotPlaces) {
    const W = 280; const H = 200; const svg = s('svg', { viewBox: `0 0 ${W} ${H}` });
    svg.append(s('rect', { width: W, height: H, fill: '#16301f' }));
    const sx = W / 1000; const sy = H / 680;
    for (const p of store.places) {
      const c = project(p.x, p.y); const hot = [...hotPlaces].some((n) => p.name.startsWith(n));
      svg.append(s('circle', { cx: c.x * sx, cy: c.y * sy, r: p.kind === 'home' ? 6 : 10, fill: p.kind === 'home' ? '#a07a58' : '#d8c3a0', stroke: hot ? '#ffd98a' : '#00000066', 'stroke-width': hot ? 2.5 : 1 }));
    }
    for (const a of store.actors) {
      const m = moods.has(a.actor_id) ? moods.get(a.actor_id) : a.mood; const c = project(a.x, a.y);
      svg.append(s('circle', { cx: c.x * sx + 6, cy: c.y * sy + 5, r: moods.has(a.actor_id) ? 5 : 3, fill: moodInfo(m).color, stroke: moods.has(a.actor_id) ? '#fff' : 'none', 'stroke-width': .8 }));
    }
    return svg;
  }

  root.append(h('h2', 'Parallel villages'), h('p.sub', 'What if you had done something different? Branch the timeline and see.'), tree, forkBox, cmpOut);
  bus.on('branch', reload); bus.on('tick', () => { if (root.closest('.panel.active')) reload(); });
  return { el: root, update: reload, setForkDay(t) { ctx.forkDay = t; drawFork(); } };
}

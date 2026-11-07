// Look Back: drag through time and see the village on any past day, beside today.
import { h, store, debounce, money, moodInfo, bus } from './util.js';
import { api, flavor } from './api.js';
import { moodPill, toast } from './ui.js';
import { iconSvg } from './narrate.js';

export function createTimePanel(ctx) {
  const root = h('div'); const cache = new Map(); let tickSel = null; let busy = 0;
  const label = h('b'); const sub = h('span', { style: { color: 'var(--muted)', fontSize: '13px' } });
  const slider = h('input', { type: 'range', min: 0, max: 0, step: 1, value: 0, 'aria-label': 'Day to look back to' });
  const ticks = h('div.ticks'); const out = h('div');
  const forkBtn = h('button.btn.sm', { onclick: () => ctx.openFork(tickSel) }, iconSvg('worlds', 16), 'Rewind & fork from here');
  const nowBtn = h('button.btn.sm.ghost', { onclick: () => { slider.value = slider.max; slider.dispatchEvent(new Event('input')); } }, 'Back to today');
  root.append(h('h2', 'Look back'), h('p.sub', 'Slide through time. The map shows prices and moods exactly as they were.'),
    h('div.slider-wrap', h('div.slider-top', label, sub), slider, ticks, h('div', { style: { display: 'flex', gap: '8px', marginTop: '10px' } }, nowBtn, forkBtn)), out);

  const load = debounce(async (t) => {
    const key = `${store.session.branchId}:${t}`; const my = ++busy;
    let data = cache.get(key);
    if (!data) {
      out.replaceChildren(h('div.skeleton'), h('div.skeleton', { style: { width: '80%' } }), h('div.skeleton', { style: { width: '60%' } }));
      try { data = await api.lookBack(t); if (t < store.tick) cache.set(key, data); } catch (err) { if (my === busy) out.replaceChildren(h('div.cold', flavor(err))); return; }
    }
    if (my !== busy) return; show(t, data);
  }, 280);

  function show(t, data) {
    const stockMap = new Map(data.stock.map((r) => [`${r.place_id}:${r.item_id}`, { qty: r.qty, price: Number(r.price), name: store.itemById.get(r.item_id)?.name }]));
    const moodMap = new Map(data.entities.map((e) => [e.entity_id, e.state?.mood]));
    ctx.map.setView(t >= store.tick ? null : { tick: t, stock: stockMap, mood: moodMap });
    ctx.setGhost(t >= store.tick ? null : t);
    // stock: then vs now
    const rows = [];
    for (const p of store.places) for (const r of p.stock || []) {
      const th = stockMap.get(`${p.place_id}:${r.item_id}`); if (!th) continue;
      rows.push({ p, item: r.item_name, thenQ: th.qty, nowQ: r.qty, thenP: th.price, nowP: Number(r.price) });
    }
    const dir = (a, b) => (b > a ? 'up' : b < a ? 'down' : 'same');
    const stockTbl = rows.length ? h('table.cmp', h('thead', h('tr', h('th', 'Shelf'), h('th.num', { style: { textAlign: 'right' } }, 'Then'), h('th', { style: { textAlign: 'right' } }, 'Today'))),
      h('tbody', rows.map((r) => h('tr', h('td', `${r.p.name.replace(/'s .*/, '')} · ${r.item}`),
        h('td.num', `${r.thenQ} @ ${money(r.thenP)}c`),
        h('td.num', { class: dir(r.thenQ + r.thenP, r.nowQ + r.nowP) }, `${r.nowQ} @ ${money(r.nowP)}c`))))) : h('div.empty', 'No shelves.');
    // moods that differ
    const diffs = store.actors.filter((a) => moodMap.has(a.actor_id) && moodMap.get(a.actor_id) !== a.mood);
    const mine = data.entities.find((e) => e.entity_id === store.me?.actorId)?.state;
    out.replaceChildren(
      h('div.sect', t >= store.tick ? 'Today' : `Day ${t} — then and now`), stockTbl,
      mine && store.me?.state ? h('div', h('div.sect', 'You'), h('table.cmp', h('tbody',
        h('tr', h('td', 'Coins'), h('td.num', money(mine.coins ?? 0)), h('td.num', { class: dir(mine.coins, store.me.state.coins) }, money(store.me.state.coins))),
        h('tr', h('td', 'Trust'), h('td.num', mine.trust ?? '–'), h('td.num', { class: dir(mine.trust, store.me.state.trust) }, store.me.state.trust))))) : null,
      h('div.sect', `Moods that have changed (${diffs.length})`),
      diffs.length ? h('table.cmp', h('tbody', diffs.map((a) => h('tr', h('td', a.name), h('td', moodPill(moodMap.get(a.actor_id))), h('td', '→'), h('td', moodPill(a.mood)))))) : h('div.empty', 'Everyone feels the same as they did.'));
  }

  function sync() {
    const max = store.tick; slider.max = max; if (tickSel === null || tickSel > max) tickSel = max; slider.value = tickSel;
    slider.style.setProperty('--p', max ? `${(tickSel / max) * 100}%` : '100%');
    label.textContent = tickSel >= max ? `Day ${max} — today` : `Day ${tickSel}`; sub.textContent = tickSel >= max ? '' : `${max - tickSel} day${max - tickSel === 1 ? '' : 's'} ago`;
    ticks.replaceChildren(h('span', 'Day 0'), h('span', `Day ${max}`)); forkBtn.disabled = tickSel === null;
  }
  slider.addEventListener('input', () => { tickSel = Number(slider.value); sync(); if (tickSel >= store.tick) { ctx.map.setView(null); ctx.setGhost(null); out.replaceChildren(h('div.empty', 'This is today.')); } else load(tickSel); });
  bus.on('tick', () => { cache.clear(); const was = tickSel >= Number(slider.max); tickSel = was ? store.tick : tickSel; sync(); });
  sync(); out.append(h('div.empty', 'Drag the slider back to see the past.'));
  return { el: root, update: sync, leave() { ctx.map.setView(null); ctx.setGhost(null); tickSel = store.tick; sync(); out.replaceChildren(h('div.empty', 'Drag the slider back to see the past.')); }, get tick() { return tickSel; } };
}

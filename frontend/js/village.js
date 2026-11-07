// The Village panel: the Evening Bell history (materialized view) and the Butterfly leaderboard.
import { h, store, bus } from './util.js';
import { api, flavor } from './api.js';
import { iconSvg } from './narrate.js';

export function createVillagePanel(ctx) {
  const root = h('div'); const bars = h('div'); const board = h('div'); const tbl = h('div');
  async function update() {
    try {
      const [bell, lb] = await Promise.all([api.bell(), api.leaderboard()]);
      const max = Math.max(1, ...bell.map((r) => r.events_total));
      bars.replaceChildren(bell.length ? h('div.bars', bell.map((r) => {
        const other = Math.max(0, r.events_total - r.player_actions - r.cascade_events);
        return h('div.bar', { style: { height: `${Math.max(6, (r.events_total / max) * 100)}%` }, title: `Day ${r.tick}: ${r.events_total} events, ${r.player_actions} by players, ${r.cascade_events} cascaded, top ripple ${r.top_score}` },
          h('i.a', { style: { flex: r.player_actions } }), h('i.c', { style: { flex: r.cascade_events } }), h('i.o', { style: { flex: other } })); }))
        : h('div.empty', 'The bell has not rung yet.'),
        h('div', { style: { display: 'flex', gap: '12px', fontSize: '11.5px', color: 'var(--muted)', margin: '6px 0 0' } }, h('span', { style: { color: 'var(--gold)' } }, '■ your actions'), h('span', { style: { color: 'var(--ember)' } }, '■ ripples'), h('span', '■ village life')));
      tbl.replaceChildren(bell.length ? h('table.cmp', h('thead', h('tr', h('th', 'Day'), h('th.num', { style: { textAlign: 'right' } }, 'Events'), h('th', { style: { textAlign: 'right' } }, 'Ripples'), h('th', { style: { textAlign: 'right' } }, 'Top score'))),
        h('tbody', [...bell].reverse().map((r) => h('tr', h('td', `Day ${r.tick}`), h('td.num', r.events_total), h('td.num', r.cascade_events), h('td.num', r.top_score))))) : null);
      const best = Math.max(1, ...lb.map((r) => r.total_score));
      board.replaceChildren(...(lb.length ? lb.map((r) => h('div.rank', { class: `${r.leaderboard_rank === 1 ? 'r1' : ''} ${r.actor_id === store.me?.actorId ? 'me' : ''}` },
        h('div.n', r.leaderboard_rank), h('div', h('b.serif', { style: { fontSize: '16px' } }, r.actor_name + (r.actor_id === store.me?.actorId ? ' (you)' : '')),
          h('small', { style: { color: 'var(--muted)' } }, `${r.actions} action${r.actions === 1 ? '' : 's'} · best single ripple ${r.best_score}`), h('div.meter', h('i', { style: { width: `${(r.total_score / best) * 100}%` } }))),
        h('div.sc', r.total_score))) : [h('div.empty', 'No ripples yet. End a day, then check back: scores refresh when the bell rings.')]));
    } catch (err) { board.replaceChildren(h('div.cold', flavor(err))); }
  }
  root.append(h('h2', 'The village'), h('p.sub', 'The Evening Bell record, and who has caused the biggest ripples.'),
    h('div.sect', { style: { marginTop: 0 } }, 'Butterfly leaderboard'), board, h('div.sect', 'Evening Bell, day by day'), bars, tbl);
  bus.on('tick', update);
  return { el: root, update };
}

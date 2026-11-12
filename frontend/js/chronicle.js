// Ask Why: the Chronicle. A recent-events feed to point at, and a vertical
// timeline that walks back from the thing you asked about to its root cause.
import { h, store, bus } from './util.js';
import { api, flavor } from './api.js';
import { describe, ACTION_META, iconSvg, eventPlaceId, eventTargets } from './narrate.js';
import { toast } from './ui.js';
import { sound } from './sound.js';

export function createChroniclePanel(ctx) {
  const root = h('div'); const out = h('div'); let selected = null; let seen = new Set();

  async function ask(id) {
    selected = String(id); drawFeed(); sound.play('tab');
    out.replaceChildren(h('div.skeleton'), h('div.skeleton', { style: { width: '70%' } }), h('div.skeleton', { style: { width: '85%' } }));
    try {
      const [rows, score] = await Promise.all([api.askWhy(id), api.score(id).catch(() => ({ score: 0 }))]);
      if (selected !== String(id)) return;
      if (!rows.length) { out.replaceChildren(h('div.cold', 'Nothing comes to mind.', h('br'), 'You did not see that happen, so the village will not tell you why.')); return; }
      const details = await Promise.all(rows.map((r) => api.event(r.event_id).catch(() => null)));
      render(rows, details, score.score);
      const t = details[details.length - 1]; if (t) { ctx.map.focus({ places: [eventPlaceId(t)].filter(Boolean), actors: [t.actor_id].filter(Boolean) }); }
    } catch (err) { out.replaceChildren(h('div.cold', flavor(err))); }
  }

  function render(rows, details, score) {
    const me = store.me?.actorId; const last = rows.length - 1;
    const cards = rows.map((r, i) => {
      const e = details[i] || { action_type: r.action_type, actor_name: r.actor_name, payload: {}, tick: r.tick };
      const mine = e.actor_id === me && me !== undefined;
      const isRoot = i === 0 && rows.length > 1; const isTarget = i === last;
      return h('div.link', { class: `${isRoot ? 'root' : ''} ${isTarget ? 'target' : ''} ${mine ? 'you' : ''}`, style: { animationDelay: `${i * 140}ms` } },
        h('div.day', `Day ${r.tick}`, isRoot ? h('span.tag.root', 'root cause') : null, isTarget ? h('span.tag.target', rows.length > 1 ? 'what you asked about' : 'this event') : null, mine ? h('span.tag.you', 'you') : null),
        h('div.body', describe({ ...e, actor_name: e.actor_name || r.actor_name })),
        r.narrative && i < last ? h('div.why', r.narrative) : null);
    });
    const root = details[0]; const rootMine = rows.length > 1 && root?.actor_id === me;
    const verdict = rows.length > 1
      ? h('div.verdict', h('h3', rootMine ? 'It started with you.' : 'The trail leads back to a single moment.'),
          h('p', { style: { margin: '0 0 8px', fontFamily: 'var(--serif)' } }, rootMine
            ? `${rows.length - 1} step${rows.length === 2 ? '' : 's'} of cause and effect separate your ${ACTION_META[root.action_type]?.label.toLowerCase() || 'action'} from this.`
            : `${rows.length - 1} step${rows.length === 2 ? '' : 's'} of cause and effect lead here.`))
      : h('div.cold', 'You can see that this happened, but the village does not show you any cause you witnessed. Some trails are hidden on purpose.');
    if (rows.length > 1 && score !== undefined) verdict.append(h('div.score-big', h('b', ''), h('span', { style: { color: 'var(--muted)' } }, 'ripples caused by the first link, its butterfly score')));
    if (rows.length > 1) { verdict.querySelector('.score-big b').textContent = ''; api.score(rows[0].event_id).then((s) => { const b = verdict.querySelector('.score-big b'); if (b) b.textContent = s.score; }).catch(() => {}); }
    out.replaceChildren(h('div.chronicle', cards), verdict);
  }

  function drawFeed() {
    const evs = store.events.filter((e) => !['story_choice', 'story_start', 'story_enter'].includes(e.action_type)).slice(0, 40);
    feed.replaceChildren(...(evs.length ? evs.map((e) => {
      const meta = ACTION_META[e.action_type];
      return h('button.fev', { class: `${selected === String(e.event_id) ? 'sel' : ''} ${e.is_cascade ? 'cascade' : ''} ${seen.has(e.event_id) ? '' : 'new'}`, style: { '--hue': meta?.hue }, onclick: () => ask(e.event_id), title: 'Ask why' },
        h('span.ico', iconSvg(e.action_type in ACTION_META ? e.action_type : 'village', 17)),
        h('span.t', describe(e)), h('span.w', `d${e.tick}`));
    }) : [h('div.empty', 'Nothing has happened that you witnessed. Do something.')]));
    seen = new Set(store.events.map((e) => e.event_id));
  }
  const input = h('input', { type: 'number', min: 1, placeholder: 'Event number', 'aria-label': 'Event number' });
  const feed = h('div.feed');
  root.append(h('h2', 'Ask the village why'), h('p.sub', 'Point at anything you saw. The village walks you back to the first cause. You only know what you witnessed.'),
    h('div.sect', { style: { marginTop: 0 } }, 'Things you saw'), feed,
    h('div.askrow', input, h('button.btn.sm', { onclick: () => { if (input.value) ask(input.value); } }, 'Ask why')),
    h('div.sect', 'The Chronicle'), out);
  out.append(h('div.empty', 'Choose an event above.'));
  drawFeed();
  bus.on('events', drawFeed);
  return { el: root, ask, update: drawFeed };
}

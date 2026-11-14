// Story mode panels: the Story tab (today's scenes, meters, compass) and the Case Board.
import { h, s, store, bus, cap } from './util.js';
import { api, flavor } from './api.js';
import { iconSvg } from './narrate.js';
import { toast } from './ui.js';
import { sound } from './sound.js';
import { openAlmanac } from './almanac.js';

const bar = (label, v, max, cls, hint) => h('div.meter-row', { title: hint },
  h('div.meter-l', label, h('b', Math.round(v))), h('div.meter-bar', h('i', { class: cls, style: { width: `${Math.min(100, (v / max) * 100)}%` } })));

function compassSvg(c) {
  const ang = -80 + (Math.min(21, c.score) / 21) * 160;
  const zones = [['#6b7aa8', 0, 4], ['#6fa0c8', 4, 9], ['#7fc4a8', 9, 13], ['#e0b84e', 13, 17], ['#ff7a3d', 17, 21]];
  const arc = (a0, a1, r = 44) => { const p = (a) => [60 + r * Math.cos(((a - 180) * Math.PI) / 180), 62 + r * Math.sin(((a - 180) * Math.PI) / 180)]; const [x0, y0] = p(a0); const [x1, y1] = p(a1); return `M${x0.toFixed(1)} ${y0.toFixed(1)} A${r} ${r} 0 0 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`; };
  const svg = s('svg', { viewBox: '0 0 120 76', width: 150, class: 'compass-svg', 'aria-hidden': 'true' });
  for (const [col, a, b2] of zones) svg.append(s('path', { d: arc((a / 21) * 160 + 10, (b2 / 21) * 160 + 10), stroke: col, 'stroke-width': 8, fill: 'none', 'stroke-linecap': 'butt' }));
  svg.append(s('g', { class: 'needle', style: `transform: rotate(${ang}deg); transform-origin: 60px 62px` }, s('path', { d: 'M60 62 L58 24 L60 18 L62 24 Z', fill: '#f2f2f2' })), s('circle', { cx: 60, cy: 62, r: 4.5, fill: '#f2b84b' }));
  return svg;
}

const placeFor = (focus) => (focus ? store.places.find((p) => p.kind === focus || p.name.toLowerCase().includes(String(focus).toLowerCase()))?.place_id : null);

export function createStoryPanel(ctx) {
  const root = h('div'); let scene = null; let compass = null; let last = null; let busy = false; let board = null; let unfocusT = 0; let lockUntil = 0;
  // After a choice the camera stays on that scene's place for a moment, even though the cards re-render under the pointer.
  const look = (focus, force) => { if (!force && Date.now() < lockUntil) return; clearTimeout(unfocusT); const id = placeFor(focus); if (id) ctx.map.focusPlace(id); };
  const unlook = (ms = 400) => { clearTimeout(unfocusT); unfocusT = setTimeout(() => ctx.map.unfocus(), Math.max(ms, lockUntil - Date.now())); };

  async function pick(beat, option) {
    if (busy) return; busy = true;
    try {
      const r = await api.storyChoose(beat, option);
      const focus = scene.beats.find((b) => b.beat_key === beat)?.focus;
      last = { title: scene.beats.find((b) => b.beat_key === beat)?.title, text: r.result };
      lockUntil = Date.now() + 3800; look(focus, true); if (r.react_line) setTimeout(() => ctx.map.say(r.react_actor, r.react_line), 800); unlook(3800);
      sound.play('tab');
      await ctx.refresh(); await update();
      root.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (err) { toast(flavor(err), 'bad'); } finally { busy = false; }
  }

  function sceneCard(b) {
    const locked = b.costs_action && scene.actions_left <= 0;
    return h('div.scene', { class: b.costs_action ? '' : 'free', dataset: { phase: b.phase }, onpointerenter: () => look(b.focus), onpointerleave: () => unlook(), onfocusin: () => look(b.focus), onfocusout: () => unlook() },
      h('div.scene-tag', b.costs_action ? `${cap(b.phase)} · uses 1 action` : 'Free · happens to you', b.picks_left > 1 ? ` · ${b.picks_left} moves left` : ''),
      h('h3', b.title), h('p.scene-body', b.body),
      h('div.opts', b.options.map((o) => h('button.opt', { disabled: locked, title: locked ? 'No actions left today. End the day.' : '', onclick: () => pick(b.beat_key, o.key) }, o.label))));
  }

  function render() {
    const sc = scene; const m = sc.meters;
    const kids = [];
    if (sc.ending) {
      kids.push(h('div.ending', h('div.ending-k', 'The end'), h('h2', sc.ending.title), h('p', sc.ending.text),
        h('div.modal-actions', h('button.btn.primary', { onclick: () => { ctx.leave(); } }, 'Begin a new story'))));
    }
    const left = Math.max(0, (sc.deadline_day || 12) - sc.day); const withEv = board ? board.links.filter((l) => l.strength > 0).length : 0;
    kids.push(h('div.goalbar', { class: left <= 3 ? 'urgent' : '' }, h('div.goal-clock', iconSvg('time', 18), h('b', `${left} day${left === 1 ? '' : 's'}`), h('span', 'until the Reeve arrives')),
      h('div.goal-text', sc.goal || ''), board ? h('div.goal-case', `Case: ${withEv} of ${board.links.length} questions have evidence`) : null));
    kids.push(h('div.day-head', h('div.day-k', sc.title), h('h2', sc.day_title || `Day ${sc.day}`), h('p.intro', sc.intro || '')));
    kids.push(h('div.meters', bar('Suspicion', m.suspicion, 100, m.suspicion >= 70 ? 'bad' : m.suspicion >= 40 ? 'warn' : 'ok', 'How strongly the village believes you did it. 70 = arrest, 100 = the mob.'),
      bar('Danger', m.danger, 60, m.danger >= 45 ? 'bad' : m.danger >= 25 ? 'warn' : 'ok', 'How closely the killer is watching you. 60 = an "accident".'),
      m.smoke > 0 ? bar('Smoke', m.smoke, 6, m.smoke >= 4 ? 'bad' : 'warn', 'Breath lost in the fire. At 6 you do not get out.') : null));
    const tr = Object.entries(sc.trust || {}).filter(([, v]) => v !== 0);
    if (tr.length) kids.push(h('details.trust', h('summary', 'Who trusts you'), h('div.trust-grid', tr.sort((a, b2) => b2[1] - a[1]).map(([k, v]) => h('div.trust-p', { class: v >= 60 ? 'hi' : v < 20 ? 'lo' : '' }, h('span', cap(k)), h('b', Math.round(v)))))));
    if (sc.guided && compass?.guided) {
      kids.push(h('div.compass', compassSvg(compass), h('div.compass-t', h('div.compass-n', compass.needle, h('span.trend', { class: compass.trend > 0 ? 'up' : compass.trend < 0 ? 'down' : '' }, compass.trend > 0 ? ` ▲ +${compass.trend}` : compass.trend < 0 ? ` ▼ ${compass.trend}` : ' ▬')),
        h('div.compass-r', compass.reason), h('button.btn.sm.ghost', { onclick: async () => { await api.storyGuidance(false); await update(); } }, 'Turn guidance off'))));
    } else if (!sc.guided) {
      kids.push(h('div.bold-note', h('span', 'Playing Bold: no guidance.'), h('button.btn.sm.ghost', { onclick: async () => { await api.storyGuidance(true); await update(); } }, 'Turn the Compass on')));
    }
    if (last) kids.push(h('div.result', h('div.result-k', last.title), h('p', last.text)));
    if (sc.slice_over) {
      kids.push(h('div.tbc', h('div.tbc-k', 'End of the opening chapters'), h('h3', 'To be continued'),
        h('p', 'Day 5 is when Sergeant Pike rides in and the investigation tightens. This is where the opening ends. Everything you did is recorded, and will matter.'),
        h('div.modal-actions', h('button.btn', { onclick: () => ctx.selectTab('board') }, 'Review your case'))));
    } else if (!sc.ending) {
      kids.push(h('div.actions-left', `${sc.actions_left} of 3 actions left today`));
      if (sc.beats.length) kids.push(h('div.scenes', sc.beats.map(sceneCard)));
      else kids.push(h('div.empty', 'Nothing more to do today. End the day.'));
      kids.push(h('div.endday', h('button.btn.night', { onclick: () => ctx.endDay() }, sc.actions_left > 0 ? `End the day (${sc.actions_left} unused)` : 'End the day, the village answers'),
        h('p', 'Time moves on. Consequences set in motion days ago finally arrive.')));
    }
    const hist = sc.done.filter((d) => d.tick === sc.day);
    if (hist.length) kids.push(h('details.history', h('summary', `Earlier today (${hist.length})`), hist.map((d) => h('div.hist', h('b', d.title), h('span', ' ' + d.label)))));
    kids.push(h('div.alm-link', h('button.btn.sm.ghost', { onclick: () => openAlmanac('scenes') }, iconSvg('book', 16), 'How does this work? Open the Almanac')));
    root.replaceChildren(...kids);
  }

  async function update() {
    try { scene = await api.storyScene(); try { board = await api.storyBoard(); } catch { /* optional */ } compass = scene.guided ? await api.storyCompass() : null; render(); ctx.onStory?.(scene, compass); }
    catch (err) { root.replaceChildren(h('div.cold', flavor(err))); }
  }
  bus.on('branch', () => { last = null; });
  return { el: root, update, get scene() { return scene; } };
}

const STRENGTH = ['Nothing', 'Heard', 'Evidence', 'Proven'];
export function createBoardPanel(ctx) {
  const root = h('div'); let board = null;
  async function update() {
    try { board = await api.storyBoard(); store.clueTitles = new Map(board.clues.map((c) => [c.key, c.title])); render(); }
    catch (err) { root.replaceChildren(h('div.cold', flavor(err))); }
  }
  function render() {
    const byLink = (k) => board.clues.filter((c) => c.links.some((l) => l.link === k));
    root.replaceChildren(h('h2', 'The Case'), h('p.sub', 'Seven questions every case must answer. A link is Proven when two independent clues agree.'),
      ...board.links.map((l) => h('div.link-card', { class: `st${l.strength}` },
        h('div.link-top', h('div', h('b.link-t', l.title), h('div.link-q', l.question)), h('div.pips3', [1, 2, 3].map((i) => h('i', { class: i <= l.strength ? 'on' : '' })), h('span', STRENGTH[l.strength]))),
        byLink(l.key).length ? h('div.link-clues', byLink(l.key).map((c) => h('details.clue', h('summary', h('span.ck', { class: c.kind }, c.kind), ' ', c.title), h('p', c.journal)))) : h('div.link-none', 'Nothing yet.'))),
      board.clues.some((c) => !c.links.length) ? h('div.sect', 'Noted, but it points nowhere (yet)') : null,
      ...board.clues.filter((c) => !c.links.length).map((c) => h('details.clue', h('summary', h('span.ck', { class: c.kind }, c.kind), ' ', c.title), h('p', c.journal))),
      !board.clues.length ? h('div.empty', 'Your journal is empty. Go and look at things.') : null);
  }
  return { el: root, update };
}

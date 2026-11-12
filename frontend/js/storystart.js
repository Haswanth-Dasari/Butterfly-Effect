// The story shelf on the arrival screen: choose a story, a temperament and whether you want guidance.
import { h, $ } from './util.js';
import { api, session, flavor } from './api.js';
import { store } from './util.js';

const TRAITS = [
  ['kind', 'Kind', 'People open up to you. +10 trust with everyone you know. Gentle questions work better.'],
  ['sharp', 'Sharp', 'You notice what others miss and can press a witness harder, but pressure can make them clam up.'],
  ['quiet', 'Quiet', 'You move unnoticed. Night actions are less likely to draw the killer\u2019s eye.'],
];

export async function buildStoryShelf(onStart) {
  const host = $('#story-shelf'); if (!host) return;
  let list = [];
  try { list = await api.scenarios(); } catch { host.replaceChildren(h('p.err', 'The story shelf is unreachable. Is the server running?')); return; }
  const pick = { scenario: list.find((s) => !s.locked)?.key, trait: 'kind', guided: false, pronouns: 'they' };
  const err = h('div.err'); const btn = h('button.btn.primary', { onclick: begin }, 'Begin the story');

  async function begin() {
    btn.disabled = true; err.textContent = '';
    try {
      const r = await api.storyStart(pick);
      store.session = { token: r.token, actorId: r.actorId, branchId: r.branchId, name: 'Rowan', story: true }; session.save(store.session);
      await onStart();
    } catch (e) { err.textContent = flavor(e); } finally { btn.disabled = false; }
  }
  const seg = (label, items, key) => h('div.shelf-block', h('div.shelf-k', label), h('div.seg-cards', items.map(([v, t, d]) =>
    h('button.seg-card', { type: 'button', 'aria-pressed': pick[key] === v, onclick: (ev) => { pick[key] = v; ev.currentTarget.parentElement.querySelectorAll('.seg-card').forEach((b) => b.setAttribute('aria-pressed', b === ev.currentTarget)); } }, h('b', t), h('span', d)))));
  host.replaceChildren(
    h('div.shelf-k', 'Choose your story'),
    h('div.story-cards', list.map((s) => h('button.story-card', { type: 'button', disabled: s.locked, 'aria-pressed': pick.scenario === s.key, onclick: (ev) => { if (s.locked) return; pick.scenario = s.key; ev.currentTarget.parentElement.querySelectorAll('.story-card').forEach((b) => b.setAttribute('aria-pressed', b === ev.currentTarget)); } },
      h('span.genre', s.genre), h('b', s.title), h('span.tag', s.tagline), s.locked ? h('span.soon', 'Coming soon') : null))),
    seg('Your temperament', TRAITS, 'trait'),
    seg('How much guidance?', [['false', 'Bold', 'No hints. Only the Case Board and the Almanac. Earns the Unaided badge.'], ['true', 'Guided', 'The Compass shows whether each choice moved you closer or farther, never naming a culprit.']].map(([v, t, d]) => [v === 'true', t, d]), 'guided'),
    seg('Pronouns', [['they', 'They', ''], ['she', 'She', ''], ['he', 'He', '']], 'pronouns'),
    err, h('div.join-row', btn));
  // normalise: the guided seg uses booleans
  host.querySelectorAll('.shelf-block')[1]?.querySelectorAll('.seg-card').forEach((b, i) => b.setAttribute('aria-pressed', String(i === 0)));
}

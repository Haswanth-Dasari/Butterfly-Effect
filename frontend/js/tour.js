// A short interactive tour that spotlights the real controls.
import { h, $ } from './util.js';

const STEPS = [
  { sel: '#mapwrap', title: 'Welcome to Alderbrook', text: 'About thirty villagers live here, and they keep living whether or not you watch. The faces show how they feel. Hover or click anyone.' },
  { sel: '#pips', title: 'Three actions a day', text: 'Each day you may take three actions: gift, trade, steal, spread a rumor and more. When you are done, end the day.' },
  { sel: '[data-tab=act]', title: 'Do something small', text: 'Pick an action. The form only offers choices the rules will accept, such as shelves that really stock the item.' },
  { sel: '#end-day-top', title: 'End the day', text: 'Time moves on. The Evening Bell tells you what changed, and consequences set in motion days ago finally arrive.' },
  { sel: '[data-tab=why]', title: 'Superpower 1: Ask Why', text: 'Point at anything you saw and the village walks you back, step by step, to the first cause. Sometimes the root is you.' },
  { sel: '[data-tab=time]', title: 'Superpower 3: Look Back', text: 'Drag through time and the map shows prices and moods exactly as they were on that day.' },
  { sel: '[data-tab=worlds]', title: 'Superpower 2: Parallel villages', text: 'Rewind to any day and take a different path. A second village grows beside the first. Then compare them.' },
];

export const STORY_STEPS = [
  { sel: '#panels', title: 'Scenes', text: 'Each card is something happening today. Read it, then choose how to respond. A choice costs one action, unless the card says Free.' },
  { sel: '#pips', title: 'Three actions a day', text: 'That is all you get. A day you waste is gone, and you cannot see everything. Choose where to look.' },
  { sel: '#panels .meters', title: 'Two meters to watch', text: 'Suspicion is what the village believes about you: at 70 you are arrested. Danger is how closely a killer is watching you. They pull against each other.' },
  { sel: '#end-day-top', title: 'End the day', text: 'When you are done, end the day. Time moves on and consequences arrive. The Reeve is coming, and the clock never stops.' },
  { sel: '#btn-almanac', title: 'Stuck on a rule?', text: 'The Almanac explains everything, and it is spoiler-free. Press H at any time.' },
];

export function startTour(onDone, steps = STEPS) {
  const STEPS_ = steps;
  const root = $('#tour'); root.classList.remove('hidden'); let i = 0;
  const done = () => { root.classList.add('hidden'); root.replaceChildren(); window.removeEventListener('resize', place); if (steps === STEPS) { try { localStorage.setItem('butterfly.toured', '1'); } catch { /* ignore */ } } onDone?.(); };
  const hole = h('div.hole'); const pop = h('div.pop'); root.replaceChildren(hole, pop);
  function place() {
    const st = STEPS_[i]; const el = $(st.sel); const r = el ? el.getBoundingClientRect() : { left: innerWidth / 2 - 50, top: innerHeight / 2 - 50, width: 100, height: 100 };
    const pad = 6; Object.assign(hole.style, { left: `${r.left - pad}px`, top: `${r.top - pad}px`, width: `${r.width + pad * 2}px`, height: `${r.height + pad * 2}px` });
    pop.replaceChildren(h('h3', st.title), h('p', st.text),
      h('div.row', h('div.dots', STEPS_.map((_, k) => h('i', { class: k === i ? 'on' : '' }))),
        h('div', { style: { display: 'flex', gap: '6px' } }, h('button.btn.sm.ghost', { onclick: done }, 'Skip'), h('button.btn.sm.primary', { onclick: () => { if (++i >= STEPS_.length) done(); else place(); } }, i === STEPS_.length - 1 ? 'Begin' : 'Next'))));
    const pw = Math.min(340, innerWidth * 0.92); let left = r.left + r.width / 2 - pw / 2; let top = r.top + r.height + 16;
    if (top + 190 > innerHeight) top = Math.max(12, r.top - 200);
    if (r.width > innerWidth * 0.5) { left = r.left + 24; top = r.top + 70; }
    pop.style.left = `${Math.max(10, Math.min(innerWidth - pw - 10, left))}px`; pop.style.top = `${Math.max(10, top)}px`;
  }
  window.addEventListener('resize', place); place();
}

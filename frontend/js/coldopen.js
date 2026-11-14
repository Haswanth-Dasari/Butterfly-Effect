// The cold open: a flash-forward to the Moot, shown once before day 1, so that every quiet choice carries dread.
import { h, $, sleep } from './util.js';
import { sound } from './sound.js';

export function coldOpen(text, title, onDone) {
  const lines = String(text || '').split('\n').filter(Boolean);
  if (!lines.length) { onDone(); return; }
  let skipped = false;
  const box = h('div.coldopen'); const skip = h('button.btn.sm.ghost.coldskip', { onclick: () => { skipped = true; finish(); } }, 'Skip');
  const root = h('div#coldopen', { role: 'dialog', 'aria-label': 'Prologue' }, box, skip);
  document.body.append(root);
  let done = false;
  function finish() { if (done) return; done = true; root.classList.add('out'); setTimeout(() => { root.remove(); onDone(); }, 700); }
  (async () => {
    sound.play('night');
    await sleep(600);
    for (let k = 0; k < lines.length && !skipped; k++) {
      const last = k === lines.length - 1;
      const el = h('p', { class: last ? 'cold-last' : '' }, lines[k]); box.append(el);
      requestAnimationFrame(() => el.classList.add('in'));
      await sleep(last ? 3000 : 2300);
    }
    if (!skipped) { box.append(h('div.cold-title', title)); requestAnimationFrame(() => box.lastChild.classList.add('in')); await sleep(2600); finish(); }
  })();
}

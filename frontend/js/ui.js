// Toasts, modals and small widgets shared by every panel.
import { h, $, moodInfo, money } from './util.js';
import { sound } from './sound.js';

export function toast(msg, kind = '') {
  const t = h('div.toast', { class: kind, role: 'status' }, msg);
  $('#toasts').append(t);
  if (kind === 'bad') sound.play('error');
  setTimeout(() => { t.style.transition = 'opacity .5s'; t.style.opacity = 0; setTimeout(() => t.remove(), 500); }, kind === 'bad' ? 4200 : 3000);
}

export function modal(content, { onClose, dismissible = true } = {}) {
  const root = $('#modal-root');
  const close = () => { scrim.remove(); document.removeEventListener('keydown', esc); onClose?.(); };
  const esc = (e) => { if (e.key === 'Escape' && dismissible) close(); };
  const scrim = h('div.scrim', { onclick: (e) => { if (e.target === scrim && dismissible) close(); } }, h('div.modal', { role: 'dialog', 'aria-modal': 'true' }, content));
  document.addEventListener('keydown', esc);
  root.append(scrim);
  scrim.querySelector('button, input')?.focus?.();
  return close;
}

export const moodPill = (m) => { const i = moodInfo(m); return h('span.pillmood', h('i', { style: { background: i.color } }), i.label); };

const ITEM_COLOR = { bread: '#e8a94a', grain: '#d8c46a', flour: '#efe6d2' };
export const itemColor = (n) => ITEM_COLOR[n] || '#ccc';
export function invPills(inv) {
  const rows = Object.entries(inv || {}).filter(([, n]) => n > 0);
  if (!rows.length) return h('span', { style: { color: 'var(--muted)', fontStyle: 'italic' } }, 'Your pockets are empty.');
  return h('div.invrow', rows.map(([k, n]) => h('span.invpill', h('i', { style: { background: itemColor(k) } }), `${n} ${k}`)));
}
export const coinText = (n) => `${money(n)} coin${Number(n) === 1 ? '' : 's'}`;

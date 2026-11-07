// The Act panel: ten action cards, each with a form that only offers choices the
// rules will accept (places that really stock the item, items you really carry...).
import { h, store, money, bus } from './util.js';
import { api, flavor } from './api.js';
import { ACTION_META, iconSvg, describe, eventPlaceId } from './narrate.js';
import { toast, invPills } from './ui.js';
import { sound } from './sound.js';

const NEEDS = {
  gift: ['target', 'item_inv', 'qty'], trade: ['item', 'place_for_item', 'qty', 'payee'], steal: ['item', 'place_for_item', 'qty'],
  sabotage: ['item', 'place_for_item', 'qty'], rumor: ['about', 'text'], build: ['what'], hire: ['target', 'wage'],
  set_price: ['item', 'place_for_item', 'price'], help_harvest: ['farm', 'qty'], feast: ['place'],
};

export function createActionsPanel(ctx) {
  const root = h('div');
  let chosen = null; let f = {};

  const others = () => store.actors.filter((a) => a.actor_id !== store.me?.actorId);
  const stockRows = (itemId) => store.places.flatMap((p) => (p.stock || []).filter((r) => r.item_id === itemId).map((r) => ({ place: p, ...r })));
  const owner = (placeId) => store.actors.find((a) => a.work_place_id === placeId && ['baker', 'miller', 'innkeeper', 'farmer'].includes(a.job)) || store.actors.find((a) => a.work_place_id === placeId);
  const inv = () => store.me?.state?.inv || {};
  const invItems = () => store.items.filter((i) => (inv()[i.name] || 0) > 0);

  function defaults(act) {
    const first = store.items[0]?.item_id;
    f = { qty: 1, wage: 1, text: 'praise', what: '', price: '' };
    if (NEEDS[act].includes('item_inv')) f.item = invItems()[0]?.item_id;
    if (NEEDS[act].includes('item')) {
      const withStock = store.items.find((i) => stockRows(i.item_id).length) || { item_id: first };
      f.item = (act === 'trade' ? store.items.find((i) => i.name === 'bread') : withStock)?.item_id ?? first;
    }
    if (NEEDS[act].includes('place_for_item')) fixPlace();
    if (NEEDS[act].includes('farm')) f.place = store.places.find((p) => p.kind === 'farm')?.place_id;
    if (NEEDS[act].includes('place')) f.place = (store.places.find((p) => p.kind === 'market') || store.places[0])?.place_id;
    if (NEEDS[act].includes('target') || NEEDS[act].includes('about')) f.target = others()[0]?.actor_id;
    if (act === 'rumor') f.target = others()[0]?.actor_id;
    f.payee = owner(f.place)?.actor_id;
  }
  function fixPlace() {
    const rows = stockRows(Number(f.item));
    if (!rows.some((r) => r.place.place_id === Number(f.place))) f.place = rows[0]?.place.place_id;
    f.payee = owner(Number(f.place))?.actor_id;
  }

  function payload(act) {
    const n = NEEDS[act]; const p = {};
    if (n.includes('target')) p.target_actor = Number(f.target);
    if (n.includes('about')) p.about = Number(f.target);
    if (n.includes('item') || n.includes('item_inv')) p.item_id = Number(f.item);
    if (n.includes('place_for_item') || n.includes('place') || n.includes('farm')) p.place_id = Number(f.place);
    if (n.includes('qty')) p.qty = Number(f.qty);
    if (n.includes('payee')) p.target_actor = Number(f.payee);
    if (n.includes('text')) p.text = f.text;
    if (n.includes('what')) p.what = f.what.trim();
    if (n.includes('wage')) p.wage = Number(f.wage);
    if (n.includes('price')) p.price = Number(f.price);
    return p;
  }

  function problem(act) {
    const p = payload(act); const me = store.me; if (!me) return 'You have not arrived yet.';
    if ((me.actionsRemainingToday ?? 3) <= 0) return 'No actions left today — end the day to let the village respond.';
    const need = NEEDS[act];
    if (need.includes('qty') && !(p.qty >= 1 && Number.isInteger(p.qty))) return 'Pick a whole number, at least 1.';
    if ((need.includes('target') || need.includes('about')) && !f.target) return 'Choose a villager.';
    if (need.includes('payee') && !f.payee) return 'Choose who gets paid.';
    if (need.includes('item_inv')) { if (!p.item_id) return 'You have nothing to give.'; const nm = store.itemById.get(p.item_id)?.name; if ((inv()[nm] || 0) < p.qty) return `You only carry ${inv()[nm] || 0} ${nm}.`; }
    if (need.includes('place_for_item')) {
      if (!p.place_id) return 'No shelf stocks that.';
      const r = stockRows(p.item_id).find((x) => x.place.place_id === p.place_id);
      if (need.includes('qty') && r && p.qty > r.qty) return `Only ${r.qty} on that shelf.`;
      if (act === 'trade' && r && r.price * p.qty > (me.state?.coins ?? 0)) return `That costs ${money(r.price * p.qty)} coins; you have ${money(me.state?.coins ?? 0)}.`;
    }
    if (act === 'help_harvest' && p.qty > 10) return 'At most ten sheaves at a time.';
    if (act === 'hire' && (!(p.wage > 0) || p.wage > (me.state?.coins ?? 0))) return !(p.wage > 0) ? 'Offer a wage above zero.' : 'You cannot afford that wage.';
    if (act === 'set_price' && !(p.price >= 0 && f.price !== '')) return 'Enter a price.';
    if (act === 'build' && !p.what) return 'Say what you would like to build.';
    return '';
  }

  const sel = (key, opts, { onChange } = {}) => h('select', { onchange: (e) => { f[key] = e.target.value; onChange?.(); draw(); } },
    opts.map((o) => h('option', { value: o.value, selected: String(o.value) === String(f[key]) }, o.label)));
  const field = (label, ...kids) => h('div.field', h('label', label), ...kids);

  function submitForm(act) {
    const meta = ACTION_META[act]; const p = payload(act); const bad = problem(act);
    const fake = { action_type: act, actor_id: store.me?.actorId, actor_name: store.me?.name, payload: p };
    const warn = h('div.warn', bad);
    const btn = h('button.btn.primary', { type: 'submit', disabled: !!bad }, `${meta.label}`);
    return h('form.form', { onsubmit: async (e) => {
      e.preventDefault(); if (problem(act)) return; btn.disabled = true;
      try {
        const res = await api.act(act, payload(act));
        sound.play(act); ctx.afterAction(act, res.eventId, payload(act));
        chosen = null; draw();
      } catch (err) { toast(flavor(err), 'bad'); btn.disabled = false; }
    } },
      h('h3', iconSvg(act, 22), meta.label), h('p.hint', meta.blurb),
      ...fieldsFor(act),
      h('div.preview', describe(fake)), warn,
      h('div', { style: { display: 'flex', gap: '8px', marginTop: '8px' } }, btn, h('button.btn.ghost', { type: 'button', onclick: () => { chosen = null; draw(); } }, 'Cancel')));
  }

  function actorField(label, key) {
    return field(label, h('div.pickrow',
      sel(key, others().map((a) => ({ value: a.actor_id, label: `${a.name}${a.job ? ` · ${a.job.replace('_', ' ')}` : a.kind === 'player' ? ' · newcomer' : ''}` }))),
      h('button.btn.sm', { type: 'button', title: 'Choose on the map', onclick: () => ctx.pickOnMap({ type: 'actor', ids: new Set(others().map((a) => a.actor_id)), hint: 'Click a villager on the map', onPick: (id) => { f[key] = id; draw(); } }) }, 'Pick on map')));
  }
  function placeField(label, ids, { forItem } = {}) {
    const list = ids || store.places.map((p) => p.place_id);
    const opts = list.map((id) => { const p = store.placeById.get(id); const r = forItem ? stockRows(Number(f.item)).find((x) => x.place.place_id === id) : null; return { value: id, label: r ? `${p.name} — ${r.qty} @ ${money(r.price)}c` : p.name }; });
    return field(label, h('div.pickrow',
      sel('place', opts, { onChange: () => { f.payee = owner(Number(f.place))?.actor_id; } }),
      h('button.btn.sm', { type: 'button', onclick: () => ctx.pickOnMap({ type: 'place', ids: new Set(list), hint: 'Click a place on the map', onPick: (id) => { f.place = id; f.payee = owner(id)?.actor_id; draw(); } }) }, 'Pick on map')));
  }

  function fieldsFor(act) {
    const n = NEEDS[act]; const out = [];
    if (n.includes('target')) out.push(actorField(act === 'gift' ? 'Give to' : 'Hire', 'target'));
    if (n.includes('about')) out.push(actorField('About', 'target'));
    if (n.includes('item_inv')) {
      const items = invItems();
      out.push(items.length ? field('What', sel('item', items.map((i) => ({ value: i.item_id, label: `${i.name} (you carry ${inv()[i.name]})` })))) : h('p.warn', 'You carry nothing to give. Trade for something, first.'));
    }
    if (n.includes('item')) out.push(field('Item', sel('item', store.items.map((i) => ({ value: i.item_id, label: i.name })), { onChange: fixPlace })));
    if (n.includes('place_for_item')) out.push(placeField(act === 'steal' ? 'From' : act === 'trade' ? 'Buy at' : 'At', stockRows(Number(f.item)).map((r) => r.place.place_id), { forItem: true }));
    if (n.includes('farm')) out.push(placeField('Farm', store.places.filter((p) => p.kind === 'farm').map((p) => p.place_id)));
    if (n.includes('place')) out.push(placeField('Where', null));
    if (n.includes('payee')) out.push(field('Pay', sel('payee', store.actors.map((a) => ({ value: a.actor_id, label: a.name })).filter((o) => o.value !== store.me?.actorId))));
    if (n.includes('text')) out.push(field('Say', h('div.seg', [['praise', 'Praise them'], ['slander', 'Slander them'], ['weather', 'Idle gossip']].map(([v, l]) => h('button', { type: 'button', 'aria-pressed': f.text === v, onclick: () => { f.text = v; draw(); } }, l)))));
    if (n.includes('what')) out.push(field('What', h('input', { type: 'text', maxlength: 40, placeholder: 'a new oven, a bridge, a bench…', value: f.what, oninput: (e) => { f.what = e.target.value; refreshBits(); } })));
    if (n.includes('qty')) out.push(field('How many', h('input', { type: 'number', min: 1, max: act === 'help_harvest' ? 10 : 99, step: 1, value: f.qty, oninput: (e) => { f.qty = e.target.value; refreshBits(); } })));
    if (n.includes('wage')) out.push(field('Wage (coins)', h('input', { type: 'number', min: 1, step: 1, value: f.wage, oninput: (e) => { f.wage = e.target.value; refreshBits(); } })));
    if (n.includes('price')) {
      const r = stockRows(Number(f.item)).find((x) => x.place.place_id === Number(f.place));
      out.push(field(`New price${r ? ` (now ${money(r.price)})` : ''}`, h('input', { type: 'number', min: 0, step: '0.25', value: f.price, placeholder: r ? money(r.price) : '', oninput: (e) => { f.price = e.target.value; refreshBits(); } })));
    }
    return out;
  }
  function refreshBits() { // typed inputs: update preview/warning without losing focus
    const form = root.querySelector('form.form'); if (!form || !chosen) return;
    const bad = problem(chosen);
    form.querySelector('.warn').textContent = bad; form.querySelector('button[type=submit]').disabled = !!bad;
    form.querySelector('.preview').textContent = describe({ action_type: chosen, actor_id: store.me?.actorId, actor_name: store.me?.name, payload: payload(chosen) });
  }

  function draw() {
    const left = store.me?.actionsRemainingToday ?? 3;
    root.replaceChildren(...[
      h('h2', 'What will you do?'), h('p.sub', 'Three actions a day. Small things travel far.'),
      h('div.card', h('div.sect', { style: { margin: '0 0 6px' } }, 'In your pockets'), invPills(inv())),
      h('div.sect', 'Choose an action'),
      h('div.actions-grid', Object.keys(ACTION_META).map((a) => h('button.act-card', { style: { '--hue': ACTION_META[a].hue }, 'aria-pressed': chosen === a, disabled: left <= 0, onclick: () => { chosen = chosen === a ? null : a; if (chosen) defaults(a); sound.play('tab'); draw(); } },
        h('span.ico', iconSvg(a, 20)), h('span', h('b', ACTION_META[a].label), h('small', ACTION_META[a].blurb))))),
      chosen ? submitForm(chosen) : null,
      h('div.endday',
        h('button.btn.night', { onclick: () => ctx.endDay() }, left > 0 ? `End the day (${left} action${left === 1 ? '' : 's'} unused)` : 'End the day — the village answers'),
        h('p', 'When the day ends, time moves on and consequences set in motion days ago finally arrive.'))].filter(Boolean));
  }
  draw();
  bus.on('me', () => { if (!chosen) draw(); else { fixPlaceSafe(); } });
  function fixPlaceSafe() { /* keep the open form stable while data refreshes in the background */ }
  return { el: root, update: () => { if (!chosen) draw(); }, openFor(act, preset = {}) { chosen = act; defaults(act); Object.assign(f, preset); draw(); } };
}

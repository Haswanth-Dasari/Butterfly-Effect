// Turns raw event rows into short, readable village prose. Pure functions:
// every id is resolved through the store, nothing is hard-coded.
import { store, money, cap } from './util.js';

const who = (id, fallback = 'Someone') => {
  if (id === null || id === undefined) return fallback;
  if (store.me && Number(id) === store.me.actorId) return 'You';
  return store.actorById.get(Number(id))?.name || `Villager #${id}`;
};
const place = (id) => store.placeById.get(Number(id))?.name || 'somewhere';
const item = (id) => store.itemById.get(Number(id))?.name || 'goods';
const qty = (n, it) => `${n} ${item(it)}`;

/** Which place a raw event "happens at" (for ripples and map pulses), or null. */
export function eventPlaceId(e) {
  const p = e.payload || {};
  if (p.place_id) return Number(p.place_id);
  if (p.from_place) return Number(p.from_place);
  const a = store.actorById.get(Number(e.actor_id));
  return a?.place_id ?? null;
}
/** Villagers an event touches (targets of the ripple). */
export function eventTargets(e) {
  const p = e.payload || {};
  const ids = [p.target_actor, p.about, p.entity_id, p.culprit].filter((x) => x !== undefined && x !== null && x !== '');
  return [...new Set(ids.map(Number))].filter((id) => id !== Number(e.actor_id));
}

export function icon(action) { return ICONS[action] ? action : 'default'; }

/** One sentence describing an event, from the viewer's point of view. */
export function describe(e) {
  const p = e.payload || {};
  const A = e.actor_name || who(e.actor_id, '');
  const you = store.me && Number(e.actor_id) === store.me.actorId;
  const subj = you ? 'You' : (A || 'Someone');
  const v = (you, third) => (you ? you : third); // verb agreement helper
  switch (e.action_type) {
    case 'world_start': return p.fork_of ? 'A new thread of the village begins here.' : 'Alderbrook begins.';
    case 'arrive': return `${subj} ${v('arrive', 'arrives')} in Alderbrook${p.coins ? ` with ${p.coins} coins` : ''}.`;
    case 'day_start': return `Day ${p.day ?? e.tick} dawns over Alderbrook.`;
    case 'gift': return `${subj} ${v('give', 'gives')} ${qty(p.qty, p.item_id)} to ${who(p.target_actor)}.`;
    case 'trade': return `${subj} ${v('buy', 'buys')} ${qty(p.qty, p.item_id)} at ${place(p.place_id)}, paying ${who(p.target_actor).toLowerCase() === 'you' ? 'yourself' : who(p.target_actor)}.`;
    case 'steal': return `${subj} ${v('slip', 'slips')} ${qty(p.qty, p.item_id)} off the shelf at ${place(p.place_id)}.`;
    case 'sabotage': return `${subj} ${v('spoil', 'spoils')} ${qty(p.qty, p.item_id)} at ${place(p.place_id)}.`;
    case 'rumor': return `${subj} ${v('spread', 'spreads')} ${p.text === 'praise' ? 'kind words' : p.text === 'slander' ? 'a nasty rumor' : p.text === 'thief' ? 'a whisper of theft' : `talk (“${p.text}”)`} about ${who(p.about)}.`;
    case 'build': return `${subj} ${v('start', 'starts')} building: ${p.what || 'something new'}.`;
    case 'hire': return `${subj} ${v('hire', 'hires')} ${who(p.target_actor)} for ${money(p.wage)} coins.`;
    case 'set_price': {
      const base = p.price !== undefined ? `to ${money(p.price)}` : p.price_pct >= 0 ? `up ${p.price_pct}%` : `down ${Math.abs(p.price_pct)}%`;
      return `${p.actor_id || e.actor_id ? subj : 'The shopkeeper'} ${e.actor_id ? v('set', 'sets') : 'sets'} the price of ${item(p.item_id)} at ${place(p.place_id)} ${base}.`;
    }
    case 'help_harvest': return `${subj} ${v('help', 'helps')} bring in ${p.qty} sheaves at ${place(p.place_id)}.`;
    case 'feast': return `${subj} ${v('throw', 'throws')} a feast at ${place(p.place_id)}.`;
    case 'produce': return p.input_item_id
      ? `${place(p.place_id)} turned ${qty(p.input_qty, p.input_item_id)} into ${qty(p.output_qty, p.output_item_id)}.`
      : `${place(p.place_id)} brought in ${qty(p.output_qty, p.output_item_id)}.`;
    case 'deliver': return `A cart carried ${qty(p.qty, p.item_id)} from ${place(p.from_place)} to ${place(p.to_place)}.`;
    case 'consume': return `The village ate ${qty(p.qty, p.item_id)} from ${place(p.place_id)}.`;
    case 'state_change': {
      const bits = [];
      if (p.set?.mood) bits.push(`feels ${p.set.mood}`);
      for (const [k, d] of Object.entries(p.add || {})) bits.push(`${k} ${d >= 0 ? 'rises' : 'falls'} by ${Math.abs(d)}`);
      const target = who(p.entity_id);
      return `${target}’${target === 'You' ? 's' : 's'} standing shifts${bits.length ? ': ' + bits.join(', ') : ''}.`.replace('You’s', 'Your');
    }
    case 'drought': return 'A drought parches the fields.';
    case 'flood': return 'The river floods the low fields.';
    case 'festival': return 'Alderbrook celebrates a festival.';
    case 'traveling_merchant': return 'A traveling merchant sets up in the square.';
    case 'tax_collector': return 'The tax collector knocks on every door.';
    default: return `${cap(String(e.action_type).replace(/_/g, ' '))}.`;
  }
}

/** Plain-English headline for an action type (button labels etc.). */
export const ACTION_META = {
  gift:         { label: 'Gift',          blurb: 'Give goods to a neighbor.',                 hue: '#ff9ecb' },
  trade:        { label: 'Trade',         blurb: 'Buy goods from a shelf.',                   hue: '#f2b84b' },
  steal:        { label: 'Steal',         blurb: 'Take goods. Quietly.',                      hue: '#9aa1ae' },
  rumor:        { label: 'Rumor',         blurb: 'Say something about someone.',              hue: '#b794f4' },
  build:        { label: 'Build',         blurb: 'Raise something new in the village.',       hue: '#d9a066' },
  hire:         { label: 'Hire',          blurb: 'Pay a villager to work for you.',           hue: '#5fd8cc' },
  set_price:    { label: 'Set price',     blurb: 'Change what a shelf charges.',              hue: '#ffd166' },
  help_harvest: { label: 'Help harvest',  blurb: 'Lend a hand at a farm.',                    hue: '#8fcf8a' },
  sabotage:     { label: 'Sabotage',      blurb: 'Spoil goods in secret.',                    hue: '#ff6a5d' },
  feast:        { label: 'Feast',         blurb: 'Gather everyone for a feast.',              hue: '#ff7a3d' },
};

// 24×24 stroke glyphs, drawn for this project (no emoji dependency, same look everywhere).
export const ICONS = {
  gift: '<rect x="4" y="9" width="16" height="11" rx="1.5"/><path d="M12 9v11M3 9h18M12 9C9 9 7 7.5 8 6s4 .5 4 3c0-2.5 3-4.5 4-3s-1 3-4 3"/>',
  trade: '<path d="M4 8h13l-3-3M20 16H7l3 3"/>',
  steal: '<path d="M4 14c2-6 6-8 8-8s6 2 8 8M3 14h18M8 14v3M16 14v3"/><circle cx="9" cy="11" r=".8"/><circle cx="15" cy="11" r=".8"/>',
  rumor: '<path d="M4 6h16v9H11l-4 4v-4H4z"/><path d="M8 10h8"/>',
  build: '<path d="M4 20l9-9M14 6l4 4M11 9l4-4 4 4-4 4z"/>',
  hire: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20c0-4 3-6 7-6s7 2 7 6"/>',
  set_price: '<path d="M3 12l9-9h8v8l-9 9z"/><circle cx="15.5" cy="8.5" r="1.3"/>',
  help_harvest: '<path d="M12 21V8M12 8c-3 0-4-2-4-4 3 0 4 2 4 4zM12 8c3 0 4-2 4-4-3 0-4 2-4 4zM12 14c-3 0-4-2-4-4 3 0 4 2 4 4zM12 14c3 0 4-2 4-4-3 0-4 2-4 4z"/>',
  sabotage: '<path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 2 1 1 0-3 1-5 2-7z"/>',
  feast: '<path d="M5 20V9l7-5 7 5v11M9 20v-6h6v6M3 20h18"/>',
  ask: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7M12 17v.2"/>',
  time: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  worlds: '<path d="M5 4v6c0 3 3 4 7 4s7 1 7 4M5 4v16M19 18v2M5 4h.01M19 20h.01"/><circle cx="5" cy="4" r="1.5"/><circle cx="5" cy="20" r="1.5"/><circle cx="19" cy="20" r="1.5"/>',
  village: '<path d="M3 20h18M5 20V10l4-3 4 3v10M13 20v-6h6v6M16 14l3-2"/>',
  coin: '<circle cx="12" cy="12" r="8"/><path d="M9.5 12h5M12 9v6" opacity=".5"/>',
  heart: '<path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 5.500-7 10-7 10z"/>',
  sound: '<path d="M4 9v6h4l5 4V5L8 9zM16 9c1.500 1.500 1.500 4.500 0 6M18.500 6.500c3 3 3 8 0 11"/>',
  mute: '<path d="M4 9v6h4l5 4V5L8 9zM17 9l5 6M22 9l-5 6"/>',
  help: '<circle cx="12" cy="12" r="9"/><path d="M9.500 9.500a2.500 2.500 0 1 1 3.500 2.300c-.7.400-1 .900-1 1.700M12 17v.2"/>',
  moon: '<path d="M20 14A8 8 0 1 1 10 4a6.500 6.500 0 0 0 10 10z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>',
  default: '<circle cx="12" cy="12" r="4"/>',
};
export function iconSvg(name, size = 20) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('width', size); svg.setAttribute('height', size);
  svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '1.7');
  svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round'); svg.setAttribute('aria-hidden', 'true');
  const doc = new DOMParser().parseFromString(`<svg xmlns="${ns}">${ICONS[name] || ICONS.default}</svg>`, 'image/svg+xml');
  for (const n of doc.documentElement.childNodes) svg.append(document.importNode(n, true));
  return svg;
}

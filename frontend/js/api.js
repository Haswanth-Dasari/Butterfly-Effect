// The only module that talks to the server. Every other module imports `api`.
import { bus, store } from './util.js';

const KEY = 'butterfly.session.v1';
export const session = {
  load() { try { return JSON.parse(localStorage.getItem(KEY)); } catch { return null; } },
  save(v) { try { localStorage.setItem(KEY, JSON.stringify(v)); } catch { /* private mode */ } },
  clear() { try { localStorage.removeItem(KEY); } catch { /* ignore */ } },
};

export class ApiError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}

async function req(method, path, body) {
  const headers = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (store.session?.token) headers.Authorization = `Bearer ${store.session.token}`;
  let res;
  try {
    res = await fetch(`/api${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError('The road to the village is blocked (is the server running?)', 0);
  }
  let data = null;
  try { data = await res.json(); } catch { /* empty body */ }
  if (!res.ok) {
    if (res.status === 401) bus.emit('auth-lost');
    throw new ApiError(data?.error || `${res.status} ${res.statusText}`, res.status);
  }
  return data;
}

export const api = {
  join: (name, branchId) => req('POST', '/join', branchId ? { name, branchId } : { name }),
  me: () => req('GET', '/me'),
  places: () => req('GET', '/places'),
  actors: () => req('GET', '/actors'),
  items: () => req('GET', '/items'),
  events: (limit = 60, since = 0) => req('GET', `/events?limit=${limit}&since=${since}`),
  event: (id) => req('GET', `/event/${id}`),
  askWhy: (id) => req('GET', `/ask-why/${id}`),
  score: (id) => req('GET', `/score/${id}`),
  bell: () => req('GET', '/evening-bell'),
  leaderboard: () => req('GET', '/leaderboard'),
  lookBack: (tick) => req('GET', `/look-back/${tick}`),
  act: (action, payload) => req('POST', '/actions', { action, payload }),
  advanceDay: () => req('POST', '/advance-day', {}),
  fork: (tick, name, strategy = 'snapshot_delta') => req('POST', '/fork', { tick, name, strategy }),
  branches: () => req('GET', '/branches'),
  switchBranch: (branchId) => req('POST', '/switch-branch', { branchId }),
  diff: (a, b) => req('GET', `/branch-diff/${a}/${b}`),
};

/** Turn the database's blunt error text into something a villager would say. */
export function flavor(err) {
  const m = String(err?.message || err || '');
  const rules = [
    [/no actions left/i, 'You have done all you can today. Let the village sleep — end the day.'],
    [/not your character/i, 'That is not your story to tell.'],
    [/insufficient inventory of (\w+)/i, (x) => `You are not carrying enough ${x[1]}.`],
    [/insufficient inventory/i, 'You are not carrying enough of that.'],
    [/not enough coins/i, 'Your purse is too light for that.'],
    [/no such stock/i, 'There is none of that to be had there.'],
    [/stock_qty_check|violates check constraint "stock/i, 'The shelf does not hold that much.'],
    [/qty too large/i, 'Even a strong back can only bring in ten sheaves at a time.'],
    [/not a farm/i, 'Harvest help is only wanted on a farm.'],
    [/qty must be positive/i, 'It has to be at least one.'],
    [/wage must be positive/i, 'Nobody works for nothing — offer a wage.'],
    [/unknown actor/i, 'There is nobody by that name here.'],
    [/nothing happened on or before/i, 'Nothing had happened yet on that day, so there is nothing to rewind to.'],
    [/fork event must belong/i, 'That moment belongs to another village.'],
    [/you have not arrived/i, 'You had not arrived in Alderbrook yet when that village split off.'],
    [/slow down|429/i, 'The village needs a moment — slow down.'],
    [/road to the village/i, m],
  ];
  for (const [re, out] of rules) { const x = m.match(re); if (x) return typeof out === 'function' ? out(x) : out; }
  return m || 'Something went wrong in the village.';
}

/** Live ripples. Reconnects with back-off; the token decides which branch we hear. */
export function connectLive(onEvent, onStatus) {
  let ws; let stopped = false; let tries = 0; let timer;
  const open = () => {
    if (stopped || !store.session?.token) return;
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    ws = new WebSocket(`${proto}://${location.host}/ws?token=${encodeURIComponent(store.session.token)}`);
    ws.onopen = () => { tries = 0; onStatus?.('live'); };
    ws.onmessage = (m) => { try { const d = JSON.parse(m.data); if (d.type === 'event') onEvent(d); } catch { /* ignore */ } };
    ws.onclose = () => {
      onStatus?.('offline');
      if (stopped) return;
      timer = setTimeout(open, Math.min(8000, 600 * 2 ** tries++));
    };
    ws.onerror = () => ws.close();
  };
  open();
  return { close() { stopped = true; clearTimeout(timer); ws?.close(); } };
}

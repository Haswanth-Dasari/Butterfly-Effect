// The Almanac: the in-game manual. Spoiler-free: it explains the rules and the shape of a case,
// never the answer. Open it any time (book icon, or the H key).
import { h, $ } from './util.js';
import { modal } from './ui.js';

export const CHAPTERS = [
  { id: 'case', title: 'Your case', body: [
    'You are Rowan Hollis, mill helper at Tobin\u2019s Mill, foster child of the Hollis family. On the night of the third day the mill burns and Tobin is found dead. Every sign points at you. The Reeve arrives on the twelfth day to judge, and unless you find the truth, you are the verdict.',
    'You win by understanding what really happened and proving it. There is no combat and no timer except the calendar: every day the village moves on, whether or not you do.',
    'The game you are playing now is the opening chapter: the three quiet days before the fire, the fire itself, and the first day of the investigation.'] },
  { id: 'day', title: 'How a day works', body: [
    'Each day has a morning, a daytime and a night. You have THREE actions a day, spent on scenes (see \u201cScenes and choices\u201d). When you are done, press End day. Time moves on: prices drift, moods change, and consequences set in motion days ago finally arrive. The Evening Bell tells you what changed.',
    'You cannot save actions for tomorrow. A day you spend badly is gone.'] },
  { id: 'scenes', title: 'Scenes and choices', body: [
    'The Story tab shows what is happening today as scenes. Each scene has a few choices. Choosing one spends an action, unless the scene says \u201cfree\u201d (important moments that happen to you whether you like it or not).',
    'A scene is usually a one-time chance. Some scenes only appear because of an earlier choice. Some choices close other doors. Nothing is marked \u201cright\u201d.',
    'You can also use the village actions in the Act tab (gift, trade, steal, rumour and so on). They use the same three actions.'] },
  { id: 'meters', title: 'The meters', body: [
    'SUSPICION is how strongly the village believes you did it. Public quarrels, running, lying and being found near the scene raise it. At 70 you will be arrested. At 100 a mob comes for you.',
    'DANGER is how closely the killer is watching you. Asking the wrong questions, being seen where you should not be, and getting close to the truth raise it. If suspicion falls, danger often rises: being safe from the mob is not the same as being safe.',
    'TRUST is how much each person will risk for you. Kindness, kept promises and protecting someone\u2019s secret raise it. Below 20 a person will not talk to you. Above 60 they may lie for you.',
    'SMOKE appears only during the fire. Every move in the burning mill costs you breath. At 6 you will not get out.'] },
  { id: 'fog', title: 'Witnesses and fog', body: [
    'You only know what you saw or were told. A secret act stays secret until somebody talks. Villagers only react to what has reached their ears.',
    'This is the heart of the game: other people saw things you did not. A child on a wall, a woman at her window, a man in a ditch. Asking them is how you learn. But some of them will not talk to you if they do not trust you.',
    'Some things that happen are hidden from you completely. That is not a bug: it is what an investigation is.'] },
  { id: 'clues', title: 'Clues and the Case Board', body: [
    'A case has seven questions: Motive (why), Means (who had the hand), Meeting (who met Tobin), Murder (how he died), Match (who lit the fire), Mask (who built the frame around you) and Master (who is behind it all).',
    'Everything you find is a clue, kept in your journal. A clue bears on one or more questions. Each question has a strength from 0 to 3: Nothing, Heard (a rumour), Testimony or Evidence, and Proven. Two independent clues are what make a proof; one alone is only a suspicion.',
    'Some clues are red herrings: they look like answers and are not. Each can be disproved by a specific fact somewhere in the village.',
    'You cannot see everything: the days are short. Choose where to look.'] },
  { id: 'why', title: 'Ask Why', body: [
    'Anything you witnessed can be questioned in the Chronicle tab: \u201cWhy did this happen?\u201d The village walks the chain of causes back to the first one. Sometimes the first cause is you.',
    'You can only trace what you saw. If you did not witness the earlier step, the trail goes cold. Collect testimony from people who did, and the trail extends.'] },
  { id: 'compass', title: 'The Compass (optional guidance)', body: [
    'You chose at the start whether to play Bold (no guidance) or Guided. You can change your mind at any time from the Story tab.',
    'The Compass is a needle: Lost, Cold, Cool, Warm, Hot. It shows how close your understanding is to the truth, and after each day tells you which question you advanced (for example \u201cYou have learned something about Means\u201d), or that you moved away.',
    'It never names the culprit and never tells you what to do. It measures what you know, not what will happen. A \u201cHot\u201d reading does not mean you are safe.'] },
  { id: 'time', title: 'Look Back and parallel villages', body: [
    'The Look back tab lets you slide through time and see the village on any past day: prices, moods, who was where.',
    'The Worlds tab lets you go back to any day and take a different path. A second village grows beside the first; the original stays exactly as it was. In a story this is a limited second chance, and the village may sense it.'] },
  { id: 'death', title: 'Danger and death', body: [
    'Death is permanent. People can die in this story, and so can you. Evidence you collected from someone survives them; evidence you did not collect does not.',
    'No child is ever harmed. Wrong accusations, though, have consequences: if you name the wrong person and the village believes you, you will live with it.'] },
  { id: 'endings', title: 'Endings', body: [
    'There are many endings and none is a \u201cgame over\u201d. What you did, who you saved and what you proved decide how it ends. After every ending the game shows The Reckoning, the full chain of cause and effect, including the parts you never saw.'] },
  { id: 'tips', title: 'Tips from the village', body: [
    'Write down who was where. Ask the child. Look at the hands. Not everyone who is kind is honest, and not everyone who is rude is guilty.',
    'If you are stuck, open the Case tab and look at which question is still at Nothing.',
    'Go slowly in the first three days. Small things you do now will matter later, and you will not know which.'] },
  { id: 'faq', title: 'Questions you may have', body: [
    'Why can\u2019t I do everything? Because you have three actions a day. It is meant to hurt.',
    'Can I fail? You can lose, and you can die. You cannot get stuck: every important clue can be found two ways.',
    'What does the hand on the top bar do? It opens this Almanac. Press H at any time.'] },
];

export function openAlmanac(startId) {
  let cur = startId || 'case';
  const nav = h('div.alm-nav'); const body = h('div.alm-body'); const q = h('input', { type: 'search', placeholder: 'Search the Almanac…', 'aria-label': 'Search the Almanac' });
  const draw = () => {
    const term = q.value.trim().toLowerCase();
    const list = CHAPTERS.filter((c) => !term || (c.title + ' ' + c.body.join(' ')).toLowerCase().includes(term));
    nav.replaceChildren(...list.map((c) => h('button.alm-link', { 'aria-current': c.id === cur, onclick: () => { cur = c.id; draw(); } }, c.title)), !list.length && h('div.empty', 'Nothing found.'));
    const c = CHAPTERS.find((x) => x.id === cur) || list[0];
    body.replaceChildren(...(c ? [h('h2', c.title), ...c.body.map((t) => h('p', t))] : []));
  };
  q.addEventListener('input', () => { if (q.value) { const hit = CHAPTERS.find((c) => (c.title + ' ' + c.body.join(' ')).toLowerCase().includes(q.value.trim().toLowerCase())); if (hit) cur = hit.id; } draw(); });
  draw();
  const close = modal(h('div.alm', h('div.alm-top', h('h2', 'The Almanac'), h('button.btn.sm', { onclick: () => close() }, 'Close')), q, h('div.alm-cols', nav, body)));
  return close;
}
document.addEventListener('keydown', (e) => { if (e.key === 'h' && !/input|textarea|select/i.test(e.target.tagName) && !$('.alm')) $('#btn-almanac')?.click(); });

// Synthesized sound: every cue is generated with the Web Audio API, so there
// are no audio files to ship. Off by default; the toggle remembers its state.
let ctx = null;
let on = (() => { try { return localStorage.getItem('butterfly.sound') === '1'; } catch { return false; } })();
let ambient = null;

const AC = window.AudioContext || window.webkitAudioContext;
function ac() { if (!ctx && AC) ctx = new AC(); if (ctx?.state === 'suspended') ctx.resume(); return ctx; }

function tone({ f = 440, type = 'sine', t = 0, d = 0.25, v = 0.12, slide = 0 }) {
  const c = ac(); if (!c || !on) return;
  const o = c.createOscillator(); const g = c.createGain();
  const t0 = c.currentTime + t;
  o.type = type; o.frequency.setValueAtTime(f, t0);
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, f + slide), t0 + d);
  g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(v, t0 + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t0 + d);
  o.connect(g).connect(c.destination); o.start(t0); o.stop(t0 + d + 0.05);
}
function noise({ t = 0, d = 0.2, v = 0.05, hp = 800 }) {
  const c = ac(); if (!c || !on) return;
  const buf = c.createBuffer(1, Math.floor(c.sampleRate * d), c.sampleRate);
  const data = buf.getChannelData(0); for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / data.length);
  const src = c.createBufferSource(); src.buffer = buf;
  const f = c.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = hp;
  const g = c.createGain(); g.gain.value = v;
  src.connect(f).connect(g).connect(c.destination); src.start(c.currentTime + t);
}

const CUES = {
  gift:         () => { tone({ f: 660, d: .18 }); tone({ f: 990, t: .1, d: .3 }); },
  trade:        () => { tone({ f: 1320, type: 'triangle', d: .12, v: .09 }); tone({ f: 1760, type: 'triangle', t: .09, d: .2, v: .09 }); },
  steal:        () => { noise({ d: .25, v: .06, hp: 2500 }); tone({ f: 180, type: 'sawtooth', d: .3, v: .05, slide: -60 }); },
  rumor:        () => { tone({ f: 330, type: 'triangle', d: .18, v: .08 }); tone({ f: 392, type: 'triangle', t: .12, d: .18, v: .08 }); tone({ f: 311, type: 'triangle', t: .24, d: .3, v: .08 }); },
  build:        () => { noise({ d: .08, v: .12, hp: 400 }); noise({ t: .18, d: .08, v: .12, hp: 400 }); tone({ f: 220, t: .3, d: .25, type: 'square', v: .04 }); },
  hire:         () => { tone({ f: 523, d: .15 }); tone({ f: 659, t: .12, d: .15 }); tone({ f: 784, t: .24, d: .25 }); },
  set_price:    () => { tone({ f: 880, type: 'square', d: .08, v: .05 }); tone({ f: 1175, type: 'square', t: .08, d: .12, v: .05 }); },
  help_harvest: () => { noise({ d: .3, v: .05, hp: 1200 }); tone({ f: 392, d: .3, v: .06 }); },
  sabotage:     () => { noise({ d: .5, v: .1, hp: 200 }); tone({ f: 120, type: 'sawtooth', d: .5, v: .08, slide: -70 }); },
  feast:        () => { [523, 659, 784, 1047].forEach((f, i) => tone({ f, t: i * .09, d: .35, v: .08, type: 'triangle' })); },
  error:        () => tone({ f: 160, type: 'square', d: .2, v: .06, slide: -40 }),
  ripple:       () => tone({ f: 740, d: .5, v: .05, slide: -300 }),
  bell: () => { [392, 523, 392].forEach((f, i) => { tone({ f, t: i * .55, d: 1.4, v: .1 }); tone({ f: f * 2.01, t: i * .55, d: .9, v: .04 }); }); },
  night: () => { tone({ f: 262, d: 1.2, v: .05, type: 'triangle' }); tone({ f: 196, t: .4, d: 1.4, v: .05, type: 'triangle' }); },
  morning: () => { [392, 494, 587, 784].forEach((f, i) => tone({ f, t: i * .13, d: .5, v: .07, type: 'triangle' })); },
  tab: () => tone({ f: 600, d: .05, v: .03 }),
};

export const sound = {
  get enabled() { return on; },
  play(name) { CUES[name]?.(); },
  toggle() {
    on = !on;
    try { localStorage.setItem('butterfly.sound', on ? '1' : '0'); } catch { /* ignore */ }
    if (on) { ac(); this.startAmbient(); CUES.tab(); } else this.stopAmbient();
    return on;
  },
  /** A soft evolving drone with a slow wobble: "a village at dusk". */
  startAmbient() {
    const c = ac(); if (!c || !on || ambient) return;
    const master = c.createGain(); master.gain.value = 0.018; master.connect(c.destination);
    const oscs = [110, 164.81, 220].map((f, i) => {
      const o = c.createOscillator(); o.type = 'sine'; o.frequency.value = f;
      const lfo = c.createOscillator(); lfo.frequency.value = 0.07 + i * 0.03;
      const lg = c.createGain(); lg.gain.value = 1.2; lfo.connect(lg).connect(o.frequency);
      o.connect(master); o.start(); lfo.start(); return [o, lfo];
    });
    ambient = { master, oscs };
  },
  stopAmbient() { if (!ambient) return; for (const [o, l] of ambient.oscs) { try { o.stop(); l.stop(); } catch { /* ignore */ } } ambient.master.disconnect(); ambient = null; },
  resume() { if (on) { ac(); this.startAmbient(); } },
};

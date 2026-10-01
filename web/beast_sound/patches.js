// Instrument patches for the Beast Sound simulator (WebAudio, no samples).
//
// Each patch is { id, name, family, gain, play(kit, dest, t, dur, freq, vel) } where `kit` holds the
// AudioContext plus shared resources (noise buffer, periodic waves, Karplus-Strong string cache).
// play() schedules one note at time t for dur seconds into `dest` and returns nothing. Patches keep
// node counts small (1-4 oscillators) because ornamented scores can hold 2,000+ notes.

export const PATCH_FAMILIES = { acoustic: 'Acoustic', keys: 'Keys & mallets', synth: 'Synthetic' };

// ── shared resources ──────────────────────────────────────────────
export function createKit(ac) {
  const sr = ac.sampleRate;
  const noise = ac.createBuffer(1, sr, sr);
  const nd = noise.getChannelData(0);
  for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
  const wave = (real, imag) => ac.createPeriodicWave(Float32Array.from(real), Float32Array.from(imag), { disableNormalization: false });
  const harmonics = (amps) => wave([0, ...amps.map(() => 0)], [0, ...amps]);
  const pulse = (duty, n = 32) => harmonics(Array.from({ length: n }, (_, k) => (2 / ((k + 1) * Math.PI)) * Math.sin((k + 1) * Math.PI * duty)));
  return {
    ac,
    noise,
    waves: {
      organ: harmonics([1, 0.7, 0.45, 0.35, 0, 0.2, 0, 0.18]),
      clarinet: harmonics([1, 0, 0.55, 0, 0.32, 0, 0.18, 0, 0.1, 0, 0.06]),
      pulse25: pulse(0.25),
      pulse12: pulse(0.125),
    },
    strings: new Map(),
  };
}

// Karplus-Strong plucked string, rendered once per (style, frequency) and cached.
function ksBuffer(kit, key, freq, { decay, brightness, seconds }) {
  const k = `${key}:${freq.toFixed(2)}`;
  if (kit.strings.has(k)) return kit.strings.get(k);
  const sr = kit.ac.sampleRate, n = Math.max(2, Math.round(sr / freq)), len = Math.floor(sr * seconds);
  const buf = kit.ac.createBuffer(1, len, sr), y = buf.getChannelData(0);
  for (let i = 0; i < n; i++) y[i] = Math.random() * 2 - 1;
  // brightness 1 = plain two-point average (dark), 0 = no averaging (very bright)
  for (let i = n; i < len; i++) y[i] = decay * ((1 - brightness / 2) * y[i - n] + (brightness / 2) * y[i - n - 1 < 0 ? 0 : i - n - 1]);
  kit.strings.set(k, buf);
  return buf;
}

// ── building blocks ───────────────────────────────────────────────
// Automation uses only setValueAtTime and linear/exponential ramps (no target-approach curves), so
// every Web Audio engine renders the same envelope.
function env(ac, dest, t, { a = 0.01, peak = 1, d = 0.1, s = 0.7, end, r = 0.15 }) {
  const g = ac.createGain(), p = g.gain;
  const atk = Math.max(0.002, Math.min(a, (end - t) * 0.5));
  const decEnd = t + atk + d;
  p.setValueAtTime(0, t);
  p.linearRampToValueAtTime(peak, t + atk);
  // level reached when the note releases (interpolated if it ends inside the decay)
  const rel = Math.max(end, t + atk);
  if (rel >= decEnd) { p.linearRampToValueAtTime(peak * s, decEnd); p.setValueAtTime(peak * s, rel); }
  else p.linearRampToValueAtTime(peak + (peak * s - peak) * ((rel - t - atk) / d), rel);
  p.linearRampToValueAtTime(0, rel + Math.max(r, 0.01));
  g.connect(dest);
  return g;
}
// Exponential sweep for filter cutoffs (values must stay > 0).
function sweep(param, t, from, to, time) {
  param.setValueAtTime(from, t);
  param.exponentialRampToValueAtTime(Math.max(to, 1), t + Math.max(time * 3, 0.005));
}
function osc(ac, type, freq, dest, t, stop, { detune = 0, wave } = {}) {
  const o = ac.createOscillator();
  if (wave) o.setPeriodicWave(wave); else o.type = type;
  o.frequency.value = freq;
  o.detune.value = detune;
  o.connect(dest);
  o.start(t);
  o.stop(stop);
  return o;
}
function lowpass(ac, dest, freq, q = 0.7) {
  const f = ac.createBiquadFilter();
  f.type = 'lowpass'; f.frequency.value = freq; f.Q.value = q;
  f.connect(dest);
  return f;
}
function vibrato(ac, oscs, t, { rate = 5, cents = 8, delay = 0.15, stop }) {
  const lfo = ac.createOscillator(), depth = ac.createGain();
  lfo.frequency.value = rate;
  depth.gain.setValueAtTime(0, t);
  depth.gain.linearRampToValueAtTime(cents, t + delay + 0.1);
  lfo.connect(depth);
  oscs.forEach((o) => depth.connect(o.detune));
  lfo.start(t); lfo.stop(stop);
}
function noiseBurst(kit, dest, t, dur, { freq, q = 1, gain }) {
  const src = kit.ac.createBufferSource(), bp = kit.ac.createBiquadFilter(), g = kit.ac.createGain();
  src.buffer = kit.noise; src.loop = true;
  bp.type = 'bandpass'; bp.frequency.value = freq; bp.Q.value = q;
  g.gain.setValueAtTime(gain, t); g.gain.linearRampToValueAtTime(gain * 0.25, t + Math.min(0.12, dur)); g.gain.linearRampToValueAtTime(0, t + dur + 0.08);
  src.connect(bp); bp.connect(g); g.connect(dest);
  src.start(t, Math.random() * 0.5); src.stop(t + dur + 0.2);
}
function fm(kit, dest, t, dur, freq, { ratio, index, indexEnd, indexTime, type = 'sine' }, stop) {
  const ac = kit.ac, car = ac.createOscillator(), mod = ac.createOscillator(), mg = ac.createGain();
  car.type = type; car.frequency.value = freq;
  mod.frequency.value = freq * ratio;
  mg.gain.setValueAtTime(freq * index, t);
  mg.gain.linearRampToValueAtTime(freq * indexEnd, t + Math.max(indexTime * 3, 0.005));
  mod.connect(mg); mg.connect(car.frequency); car.connect(dest);
  car.start(t); mod.start(t); car.stop(stop); mod.stop(stop);
}
function plucked(kit, key, dest, t, dur, freq, vel, { decay, brightness, seconds, ring, filter }) {
  const ac = kit.ac, src = ac.createBufferSource(), g = ac.createGain();
  src.buffer = ksBuffer(kit, key, freq, { decay, brightness, seconds });
  const end = Math.min(t + dur + ring, t + seconds);
  g.gain.setValueAtTime(vel, t);
  g.gain.setValueAtTime(vel, end);
  g.gain.linearRampToValueAtTime(0, end + 0.12);
  src.connect(g);
  g.connect(filter ? lowpass(ac, dest, filter) : dest);
  src.start(t); src.stop(end + 0.3);
}

// ── the patches ───────────────────────────────────────────────────
export const PATCHES = [
  {
    id: 'flute', name: 'Flute', family: 'acoustic', gain: 0.9,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.4;
      const g = env(ac, dest, t, { a: 0.045, peak: vel, d: 0.08, s: 0.85, end: t + dur, r: 0.12 });
      const o1 = osc(ac, 'sine', f, g, t, stop), o2 = osc(ac, 'triangle', f * 2, lowpass(ac, g, f * 3), t, stop);
      o2.detune.value = 3;
      vibrato(ac, [o1, o2], t, { rate: 5.2, cents: 9, delay: 0.18, stop });
      noiseBurst(kit, dest, t, dur, { freq: f * 2.2, q: 2, gain: vel * 0.08 });
    },
  },
  {
    id: 'nylon', name: 'Nylon Guitar', family: 'acoustic', gain: 1.1,
    play(kit, dest, t, dur, f, vel) { plucked(kit, 'nylon', dest, t, dur, f, vel, { decay: 0.996, brightness: 1, seconds: 2.5, ring: 0.6, filter: 2600 }); },
  },
  {
    id: 'steel', name: 'Steel Guitar', family: 'acoustic', gain: 0.9,
    play(kit, dest, t, dur, f, vel) { plucked(kit, 'steel', dest, t, dur, f, vel, { decay: 0.998, brightness: 0.55, seconds: 3, ring: 0.9 }); },
  },
  {
    id: 'harp', name: 'Harp', family: 'acoustic', gain: 1.0,
    play(kit, dest, t, dur, f, vel) { plucked(kit, 'harp', dest, t, dur, f, vel, { decay: 0.9985, brightness: 0.9, seconds: 3.5, ring: 1.8, filter: 3400 }); },
  },
  {
    id: 'cello', name: 'Cello Ensemble', family: 'acoustic', gain: 0.55,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.6;
      const g = env(ac, dest, t, { a: Math.min(0.09, dur * 0.4), peak: vel, d: 0.2, s: 0.8, end: t + dur, r: 0.3 });
      const lp = lowpass(ac, g, 1700, 0.9);
      const a = osc(ac, 'sawtooth', f, lp, t, stop, { detune: -7 }), b = osc(ac, 'sawtooth', f, lp, t, stop, { detune: 7 });
      vibrato(ac, [a, b], t, { rate: 5.6, cents: 7, delay: 0.2, stop });
    },
  },
  {
    id: 'choir', name: 'Choir “Oh”', family: 'acoustic', gain: 1.6,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.6;
      const g = env(ac, dest, t, { a: Math.min(0.12, dur * 0.5), peak: vel, d: 0.2, s: 0.9, end: t + dur, r: 0.35 });
      const src = ac.createGain();
      [[450, 6, 1], [800, 7, 0.55], [2830, 9, 0.25]].forEach(([ff, q, amp]) => {
        const bp = ac.createBiquadFilter(), ga = ac.createGain();
        bp.type = 'bandpass'; bp.frequency.value = ff; bp.Q.value = q; ga.gain.value = amp;
        src.connect(bp); bp.connect(ga); ga.connect(g);
      });
      const a = osc(ac, 'sawtooth', f, src, t, stop, { detune: -5 }), b = osc(ac, 'sawtooth', f, src, t, stop, { detune: 6 });
      vibrato(ac, [a, b], t, { rate: 4.8, cents: 10, delay: 0.25, stop });
    },
  },
  {
    id: 'clarinet', name: 'Clarinet', family: 'acoustic', gain: 0.7,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.3;
      const g = env(ac, dest, t, { a: 0.03, peak: vel, d: 0.1, s: 0.85, end: t + dur, r: 0.1 });
      const o = osc(ac, null, f, lowpass(ac, g, f * 6, 0.5), t, stop, { wave: kit.waves.clarinet });
      vibrato(ac, [o], t, { rate: 4.5, cents: 4, delay: 0.3, stop });
    },
  },
  {
    id: 'harpsichord', name: 'Harpsichord', family: 'keys', gain: 0.8,
    play(kit, dest, t, dur, f, vel) {
      const hp = kit.ac.createBiquadFilter();
      hp.type = 'highpass'; hp.frequency.value = 180; hp.connect(dest);
      plucked(kit, 'harpsi', hp, t, dur, f, vel, { decay: 0.997, brightness: 0.15, seconds: 2, ring: 0.25 });
    },
  },
  {
    id: 'epiano', name: 'Electric Piano', family: 'keys', gain: 0.75,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 1.2;
      const g = env(ac, dest, t, { a: 0.004, peak: vel, d: 1.1, s: 0.25, end: t + dur, r: 0.35 });
      fm(kit, g, t, dur, f, { ratio: 1, index: 2.4, indexEnd: 0.35, indexTime: 0.12 }, stop);
      fm(kit, g, t, dur, f * 2, { ratio: 7, index: 0.6, indexEnd: 0, indexTime: 0.02 }, Math.min(stop, t + 0.25));
    },
  },
  {
    id: 'organ', name: 'Church Organ', family: 'keys', gain: 0.45,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.4;
      const g = env(ac, dest, t, { a: 0.03, peak: vel, d: 0.05, s: 1, end: t + dur, r: 0.18 });
      osc(ac, null, f, g, t, stop, { wave: kit.waves.organ });
      osc(ac, 'sine', f / 2, g, t, stop).detune.value = 2;
    },
  },
  {
    id: 'musicbox', name: 'Music Box', family: 'keys', gain: 0.8,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + 1.6;
      const g1 = env(ac, dest, t, { a: 0.002, peak: vel, d: 1.2, s: 0, end: t + 1.4, r: 0.2 });
      const g2 = env(ac, dest, t, { a: 0.002, peak: vel * 0.35, d: 0.25, s: 0, end: t + 0.4, r: 0.1 });
      osc(ac, 'sine', f * 2, g1, t, stop);
      osc(ac, 'sine', f * 2 * 3.98, g2, t, t + 0.6);
    },
  },
  {
    id: 'marimba', name: 'Marimba', family: 'keys', gain: 1.0,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac;
      const g1 = env(ac, dest, t, { a: 0.003, peak: vel, d: 0.5, s: 0, end: t + Math.max(dur, 0.5), r: 0.15 });
      const g2 = env(ac, dest, t, { a: 0.002, peak: vel * 0.4, d: 0.07, s: 0, end: t + 0.12, r: 0.05 });
      osc(ac, 'sine', f, g1, t, t + 1);
      osc(ac, 'sine', f * 3.93, g2, t, t + 0.25);
      noiseBurst(kit, dest, t, 0.015, { freq: f * 6, q: 1.5, gain: vel * 0.12 });
    },
  },
  {
    id: 'bells', name: 'Tubular Bells', family: 'keys', gain: 0.55,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + 3.2;
      const g = env(ac, dest, t, { a: 0.003, peak: vel, d: 2.6, s: 0, end: t + 3, r: 0.2 });
      fm(kit, g, t, dur, f, { ratio: 3.5, index: 3, indexEnd: 0.4, indexTime: 0.7 }, stop);
    },
  },
  {
    id: 'supersaw', name: 'Supersaw Lead', family: 'synth', gain: 0.35,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.4;
      const g = env(ac, dest, t, { a: 0.01, peak: vel, d: 0.15, s: 0.75, end: t + dur, r: 0.2 });
      const lp = lowpass(ac, g, 1200, 1.2);
      sweep(lp.frequency, t, 5200, 1600, 0.18);
      [-14, 0, 13].forEach((c) => osc(ac, 'sawtooth', f, lp, t, stop, { detune: c }));
    },
  },
  {
    id: 'chiptune', name: 'Chiptune', family: 'synth', gain: 1.0,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, g = ac.createGain();
      g.gain.setValueAtTime(vel, t); g.gain.setValueAtTime(vel * 0.7, t + Math.min(dur, 0.05)); g.gain.setValueAtTime(0, t + dur);
      g.connect(dest);
      osc(ac, null, f, g, t, t + dur + 0.02, { wave: f > 400 ? kit.waves.pulse12 : kit.waves.pulse25 });
    },
  },
  {
    id: 'brass', name: 'FM Brass', family: 'synth', gain: 0.55,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.4;
      const g = env(ac, dest, t, { a: Math.min(0.05, dur * 0.5), peak: vel, d: 0.15, s: 0.8, end: t + dur, r: 0.15 });
      fm(kit, g, t, dur, f, { ratio: 1, index: 0.5, indexEnd: 3, indexTime: 0.06 }, stop);
    },
  },
  {
    id: 'acid', name: 'Acid Bass', family: 'synth', gain: 0.45,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.25;
      const g = env(ac, dest, t, { a: 0.004, peak: vel, d: 0.2, s: 0.6, end: t + dur, r: 0.06 });
      const lp = lowpass(ac, g, 300, 14);
      sweep(lp.frequency, t, Math.min(4200, f * 14), f * 1.5 + 120, 0.07);
      osc(ac, 'sawtooth', f / 2, lp, t, stop);
    },
  },
  {
    id: 'glasspad', name: 'Glass Pad', family: 'synth', gain: 0.6,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 1.2;
      const g = env(ac, dest, t, { a: Math.min(0.15, dur * 0.6), peak: vel, d: 0.3, s: 0.85, end: t + dur, r: 0.9 });
      osc(ac, 'triangle', f, g, t, stop, { detune: -8 });
      osc(ac, 'triangle', f, g, t, stop, { detune: 8 });
      const sh = ac.createGain(); sh.gain.value = 0.18; sh.connect(g);
      osc(ac, 'sine', f * 4, sh, t, stop, { detune: 3 });
    },
  },
  {
    id: 'wobble', name: 'Sub Wobble', family: 'synth', gain: 0.55,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + dur + 0.3;
      const g = env(ac, dest, t, { a: 0.01, peak: vel, d: 0.1, s: 0.9, end: t + dur, r: 0.1 });
      const lp = lowpass(ac, g, 600, 8);
      const lfo = ac.createOscillator(), depth = ac.createGain();
      lfo.frequency.value = 3; depth.gain.value = 500;
      lfo.connect(depth); depth.connect(lp.frequency); lfo.start(t); lfo.stop(stop);
      osc(ac, 'sawtooth', f, lp, t, stop);
      const sub = ac.createGain(); sub.gain.value = 0.7; sub.connect(g);
      osc(ac, 'sine', f / 2, sub, t, stop);
    },
  },
  {
    id: 'pluck', name: 'Synth Pluck', family: 'synth', gain: 0.6,
    play(kit, dest, t, dur, f, vel) {
      const ac = kit.ac, stop = t + Math.max(dur, 0.35) + 0.2;
      const g = env(ac, dest, t, { a: 0.002, peak: vel, d: 0.35, s: 0, end: t + Math.max(dur, 0.35), r: 0.1 });
      const lp = lowpass(ac, g, 600, 4);
      sweep(lp.frequency, t, Math.min(8000, f * 16), f * 1.2 + 200, 0.06);
      osc(ac, 'sawtooth', f, lp, t, stop, { detune: -5 });
      osc(ac, 'square', f, lp, t, stop, { detune: 5 });
    },
  },
];

export const PATCH_BY_ID = Object.fromEntries(PATCHES.map((p) => [p.id, p]));

/** Ensembles: one patch per role (leader, followers, countersubject). */
export const ENSEMBLES = [
  { id: 'consort', name: 'Renaissance consort', leader: 'flute', followers: 'harp', countersubject: 'cello' },
  { id: 'chamber', name: 'Chamber trio', leader: 'clarinet', followers: 'cello', countersubject: 'nylon' },
  { id: 'cathedral', name: 'Cathedral', leader: 'choir', followers: 'organ', countersubject: 'bells' },
  { id: 'dungeon8', name: '8-bit dungeon', leader: 'chiptune', followers: 'pluck', countersubject: 'acid' },
  { id: 'nightclub', name: 'Night synth', leader: 'supersaw', followers: 'glasspad', countersubject: 'wobble' },
  { id: 'mallets', name: 'Mallets', leader: 'marimba', followers: 'musicbox', countersubject: 'epiano' },
];

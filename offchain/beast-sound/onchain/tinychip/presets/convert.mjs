// The TinyChip bank as onchain-midi-player TinySynthSettings timbres: every preset (with its loudness
// gain and mix trim folded in), the Beast drum kit and the sampled chip waves they use. The same
// conversion as ../synth_settings.mjs for the launch 20 (build.mjs checks it), extended to the other
// 80 presets and to AM modulators. Shared by build.mjs (the audition page) and pack.mjs (the
// optional preset pack).
import { loadBank, ESSENTIALS } from '../essentials.mjs';
import { STEPS, INTERIM, BUILTIN_GAIN, TIMBRE_TRIM, chipTables, BEAST_DRUMS } from '../synth_settings.mjs';

const bank = loadBank();
const DEFAULTS = { g: 0, w: 'sine', t: 1, f: 0, v: 0.5, a: 0, h: 0.01, d: 0.01, s: 0, r: 0.05, p: 1, q: 1, k: 0 };
const BUILTIN = { sine: 'Sine', square: 'Square', sawtooth: 'Sawtooth', triangle: 'Triangle' };
const SCALE = 10000, fx = (x) => Math.round(x * SCALE);

// Loudness gain (x mix trim) folded into outputs and AM modulators, as TinyChipBank.install does.
export const presetOps = (id) => {
  const pr = bank.PRESETS[id], k = (bank.LOUDNESS[id] ?? 1) * ((bank.MIX_TRIM || {})[id] ?? 1);
  return pr.p.map((o) => { const op = { ...DEFAULTS, ...o }; if (op.g === 0 || op.g > 10) op.v *= k; return op; });
};
const drumOps = (key) => bank.DRUMS[key][1].map((o) => ({ ...DEFAULTS, ...o }));

const allLists = [...bank.PRESETS.map((p) => presetOps(p.program)), ...BEAST_DRUMS.map(drumOps)];
const used = new Set(allLists.flat().map((o) => o.w));
export const WAVES = Object.keys(STEPS).filter((w) => used.has(w));
const tables = chipTables(WAVES);

function operator(o, route, wave, mul = 1, gain = 1) {
  return {
    route, wave, volume: fx(o.v * gain), ratio: fx(o.t * mul), offset_hz: fx(o.f * mul),
    attack: fx(o.a), hold: fx(o.h), decay: fx(o.d), sustain: fx(o.s), release: fx(o.r),
    pitch_ratio: fx(o.p), pitch_time: fx(o.q), key_scale: fx(o.k), filter: null,
  };
}
// synth_settings.mjs timbreOperators, plus AM modulators (g > 10 -> route 10 + target).
function timbreOperators(ops, trim = 1) {
  const out = [], parts = [];
  for (const o of ops) {
    const split = o.w in STEPS ? [[{ Custom: WAVES.indexOf(o.w) }, 1, 1]] : INTERIM[o.w] || [[BUILTIN[o.w] || (() => { throw new Error('wave ' + o.w); })(), 1, 1]];
    if (o.g === 0) {
      parts.push(split.map(([w, mul, gain]) => (out.push(operator(o, 0, w, mul, gain * trim * (typeof w === 'string' ? BUILTIN_GAIN[w] ?? 1 : 1))), out.length)));
    } else {
      if (split.length > 1) throw new Error('split modulator');
      const [w] = split[0], am = o.g > 10, target = parts[(am ? o.g - 10 : o.g) - 1];
      // an AM depth is relative to the output level, so it takes the output's trim too
      const op = am ? { ...o, v: o.v * trim } : o;
      parts.push(target.map((t) => (out.push(operator(op, am ? 10 + t : t, w)), out.length)));
    }
  }
  if (out.length > 8) throw new Error(`${out.length} operators`);
  return out;
}

export const presets = bank.PRESETS.map((p) => ({
  program: p.program, name: p.name, category: p.category, inspired: p.inspired || null,
  inSet: ESSENTIALS.includes(p.program),
  operators: timbreOperators(presetOps(p.program), TIMBRE_TRIM[p.program] ?? 1),
}));
export const drums = BEAST_DRUMS.map((key) => ({ key, name: bank.DRUMS[key][0], operators: timbreOperators(drumOps(key)) }));
export const waves = WAVES.map((w) => ({ name: w, Samples: tables[w] }));

// Every timbre in one settings value (the launch defaults: quality 1, reverb 30, volume 40, 64 voices).
export const SETTINGS_BASE = { quality: 1, reverb: 30, master_vol: 40, voices: 64 };
export const full = {
  quality: 1, reverb: 30, master_vol: 40, voices: 64, waves: waves.map((w) => ({ Samples: w.Samples })),
  timbres: [...presets.map((p) => ({ drum: false, slot: p.program, operators: p.operators })), ...drums.map((d) => ({ drum: true, slot: d.key, operators: d.operators }))],
};

// The optional preset pack (chosen 2026-10-20): 25 of the 80 presets outside the launch set, to ship
// pre-encoded (gzip + base64) alongside onchain-midi-player. Bank program numbers, which are also
// the timbre slots; none collides with the launch 20.
export const OPTIONAL_PACK = [10, 21, 26, 28, 29, 31, 33, 39, 42, 44, 51, 58, 59, 60, 61, 62, 64, 68, 69, 71, 85, 86, 89, 95, 96];

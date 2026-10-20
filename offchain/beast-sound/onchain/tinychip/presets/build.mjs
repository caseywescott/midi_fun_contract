// Builds public/onchain/presets.html: all 100 TinyChip presets as onchain-midi-player TinySynthSettings timbres
// (the same conversion as onchain/tinychip/synth_settings.mjs, extended to the 80 presets outside
// the launch set and to AM modulators), played through the pinned TinySynth engine the way the
// onchain player installs settings.
//
//   node onchain/tinychip/presets/build.mjs <webaudio-tinysynth-4bf9829.min.js>   writes public/onchain/presets.html
//   OMP=<onchain-midi-player checkout> ...                                  also validates every timbre with its player/validate.js
import { readFileSync, writeFileSync } from 'node:fs';
import { loadBank } from '../essentials.mjs';
import { ESSENTIALS } from '../essentials.mjs';
import { STEPS, INTERIM, BUILTIN_GAIN, TIMBRE_TRIM, chipTables, BEAST_DRUMS } from '../synth_settings.mjs';
import { pathToFileURL } from 'node:url';

const here = new URL('.', import.meta.url);
const bank = loadBank();
const DEFAULTS = { g: 0, w: 'sine', t: 1, f: 0, v: 0.5, a: 0, h: 0.01, d: 0.01, s: 0, r: 0.05, p: 1, q: 1, k: 0 };
const BUILTIN = { sine: 'Sine', square: 'Square', sawtooth: 'Sawtooth', triangle: 'Triangle' };
const SCALE = 10000, fx = (x) => Math.round(x * SCALE);

// Loudness gain (x mix trim) folded into outputs and AM modulators, as TinyChipBank.install does.
const presetOps = (id) => {
  const pr = bank.PRESETS[id], k = (bank.LOUDNESS[id] ?? 1) * ((bank.MIX_TRIM || {})[id] ?? 1);
  return pr.p.map((o) => { const op = { ...DEFAULTS, ...o }; if (op.g === 0 || op.g > 10) op.v *= k; return op; });
};
const drumOps = (key) => bank.DRUMS[key][1].map((o) => ({ ...DEFAULTS, ...o }));

const allLists = [...bank.PRESETS.map((p) => presetOps(p.program)), ...BEAST_DRUMS.map(drumOps)];
const used = new Set(allLists.flat().map((o) => o.w));
const WAVES = Object.keys(STEPS).filter((w) => used.has(w));
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

const presets = bank.PRESETS.map((p) => ({
  program: p.program, name: p.name, category: p.category, inspired: p.inspired || null,
  inSet: ESSENTIALS.includes(p.program),
  operators: timbreOperators(presetOps(p.program), TIMBRE_TRIM[p.program] ?? 1),
}));
const drums = BEAST_DRUMS.map((key) => ({ key, name: bank.DRUMS[key][0], operators: timbreOperators(drumOps(key)) }));
const waves = WAVES.map((w) => ({ name: w, Samples: tables[w] }));

// Every timbre must pass onchain-midi-player's Cairo checks (JS reference) and encode.
const full = {
  quality: 1, reverb: 30, master_vol: 40, voices: 64, waves: waves.map((w) => ({ Samples: w.Samples })),
  timbres: [...presets.map((p) => ({ drum: false, slot: p.program, operators: p.operators })), ...drums.map((d) => ({ drum: true, slot: d.key, operators: d.operators }))],
};
if (process.env.OMP) {
  const { validateSettings } = await import(pathToFileURL(process.env.OMP + '/player/validate.js'));
  const { encodeSettings } = await import(pathToFileURL(process.env.OMP + '/player/encode.js'));
  validateSettings(full);
  console.log(`${presets.length} presets, ${drums.length} drums, ${waves.length} waves; full SETTINGS ${encodeSettings(full).length} bytes; valid`);
} else console.log('OMP not set: skipping onchain-midi-player validation');

// The launch set's settings must match synth_settings.mjs's own (same conversion for the 20).
const { beastSynthSettings } = await import('../synth_settings.mjs');
const ref = beastSynthSettings(undefined, ESSENTIALS, []);
const named = (ops, names) => ops.map((o) => ({ ...o, wave: typeof o.wave === 'object' ? names[o.wave.Custom] : o.wave }));
const refNames = Object.keys(STEPS).filter((w) => new Set(ESSENTIALS.flatMap((id) => presetOps(id).map((o) => o.w))).has(w));
for (const t of ref.timbres) {
  if (JSON.stringify(named(presets[t.slot].operators, WAVES)) !== JSON.stringify(named(t.operators, refNames))) throw new Error('launch preset ' + t.slot + ' differs from synth_settings.mjs');
}
console.log('launch set matches synth_settings.mjs');

const data = { waves, presets, drums, settingsBase: { quality: 1, reverb: 30, master_vol: 40, voices: 64 } };
if (!process.argv[2]) throw new Error('usage: node onchain/tinychip/presets/build.mjs <webaudio-tinysynth-4bf9829.min.js>');
const engine = readFileSync(process.argv[2], 'utf8');
const page = readFileSync(new URL('page.src.html', here), 'utf8')
  .replace('/*ENGINE*/', () => engine.replace(/<\/script/gi, '<\\/script'))
  .replace('/*DATA*/null', () => JSON.stringify(data));
writeFileSync(new URL('../../../public/onchain/presets.html', here), page);
console.log('presets.html', page.length, 'bytes');

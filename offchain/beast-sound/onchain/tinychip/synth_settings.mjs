// TinyChip as onchain-midi-player TinySynthSettings: the presets the self-contained Beast MIDI selects
// (BEAST_PROGRAMS, any of the 20 essentials) as custom timbres in their own program slots (bank
// numbers) and the chip drum kit on channel 10's notes. One source of truth: everything comes from bankData(),
// the same data the TinyChip runtime is built from.
//
// Sampled waves. Every pitched chip wave a selected preset or drum uses (the pulses, the NES 4-bit
// triangle, the 4-bit saw, the Game Boy, VRC6, FDS, N163, SID, TIA and PC Engine shapes, the
// short-LFSR tone; STEPS below) is sent as a custom wave (`TinySynthSettings.waves`,
// `WaveDef::Samples`): one cycle of tinysynth-chip.js's own waveform, read from its registerWaves,
// one sample per step as i8 (clamp(round(x * 128), -128, 127)). onchain-midi-player's player
// registers each with the engine's setSampleWave, which plays it sample-and-hold at the note's pitch
// like TinyChip's own looped buffer, so its operators keep their level (no gain) and their one wave,
// `Custom(index)`. `waves` holds only the waves the selection uses, in STEPS order, so a preset
// added later gets its exact wave with nothing else to change.
//
// The 50% pulse is a table too: TinySynth's square is band-limited, a duller wave than TinyChip's
// (Square Lead brightness 0.87x against 0.96x as two samples).
//
// Built-in waves. The LFSR noises stay TinySynth's own, at the same level:
//
//   nNOI  white noise x 0.866                     same RMS as the +-0.5 LFSR noise
//   nMET  metallic noise                          TinySynth's n1 already sits at 0.5 RMS (a 93-step
//                                                 table would carry the LFSR's DC offset)
//
// A vibrato modulator on a split carrier is repeated for each part (FM depth follows the target's
// frequency, so every part bends by the same ratio). A sampled wave is never split.
//
//   node onchain/tinychip/synth_settings.mjs              the six settings as JSON, settings/<family>[_mega].json (onchain-midi-player's
//                                                         scripts/preview.mjs --settings)
//   node onchain/tinychip/synth_settings.mjs --cairo      regenerates beasts/beast_contracts/src/synth_settings.cairo
import { mkdirSync, writeFileSync } from 'node:fs';
import { poseidonHashMany } from '../../src/index.js';
import { FAMILIES } from '../../src/full_midi.js';
import { EDITION_DRUMS, STYLES } from '../../src/editions_lite.js';
import { fileURLToPath } from 'node:url';
import { bankData, ESSENTIALS, loadBank } from './essentials.mjs';

const SCALE = 10000;
const DEFAULTS = { g: 0, w: 'sine', t: 1, f: 0, v: 0.5, a: 0, h: 0.01, d: 0.01, s: 0, r: 0.05, p: 1, q: 1, k: 0 };
const BUILTIN = { sine: 'Sine', square: 'Square', sawtooth: 'Sawtooth', triangle: 'Triangle' };

/** TinyChip wave -> [[built-in wave, frequency multiple, level multiple], ...] */
export const INTERIM = {
  nNOI: [['WhiteNoise', 1, 0.866]],
  nMET: [['MetallicNoise', 1, 1]],
};

// Web Audio's built-in oscillators are normalized to their band-limited peak (Gibbs overshoot), so
// their plateau sits below +-1; these gains bring each to the level of the ideal wave the table
// above assumes (measured: K-weighted loudness of every timbre against TinyChip's own, in Chrome
// through the pinned engine; onchain/tinychip/interim_check.mjs).
export const BUILTIN_GAIN = { Square: 1.174, Sawtooth: 1.24, Triangle: 1.063, MetallicNoise: 0.79 };

// Per-preset level trims: the plucks are balanced to one attack level. Measured on the same notes in
// Chrome through the pinned engine, their attacks peaked from -1.2 to +8.5 dB against the median of the 20
// presets (Muted Pluck +8.5, Pulse 25% +3.3, Chip Harp +3.1, Square +3.1, 4-bit Saw +2.2, Triangle +2.1,
// Pulse 12.5% +5.5 before its first trim), so each is cut to the median (Chip Piano, below it, stays). The
// leads are untouched. (Hero Fanfare (53) once had 0.933 while its pulses were square stacks; its exact
// pulse tables match TinyChip without it.)
export const TIMBRE_TRIM = { 12: 0.68, 13: 0.51, 14: 0.7, 15: 0.78, 16: 0.78, 17: 0.7, 19: 0.39 };

const fx = (x) => Math.round(x * SCALE);

/**
 * The pitched chip waves sent as samples, in tinysynth-chip.js's WAVES order (the order of
 * `TinySynthSettings.waves`), each with its steps per cycle: its waveform is constant on each step, so
 * one sample per step is the exact wave (chipTables checks it).
 */
export const STEPS = {
  nP06: 16, nP12: 8, nP25: 4, nP37: 8, nP50: 2, nTRI: 32, nSAW: 16, nVRS: 7, nWV1: 32, nWV2: 32,
  nFDS: 64, nN16: 32, nSID: 510, nTI4: 15, nTI5: 31, nTIB: 31, nPC1: 32, nPC2: 32, nMTP: 93,
};

const q8 = (x) => Math.max(-128, Math.min(127, Math.round(x * 128)));

/**
 * One cycle of each named wave as i8 samples, from tinysynth-chip.js's own registerWaves: run with a
 * sample rate of 440 x steps x 4, its 440-cycles-per-second buffer holds the cycle at four points
 * per step. Each step's sample is the middle one; throws if the other points differ (not a step
 * wave).
 */
export function chipTables(names) {
  const bank = loadBank(), out = {}, K = 4;
  for (const n of new Set(names.map((w) => STEPS[w]))) {
    const sr = 440 * n * K, buffers = {};
    const context = { sampleRate: sr, createBuffer: (_, len) => { const d = new Float64Array(len); return { getChannelData: () => d }; } };
    bank.install({ noiseBuf: buffers, program: Array.from({ length: 128 }, () => ({})), setTimbre() {}, getAudioContext: () => context }, { drums: false });
    for (const w of names.filter((x) => STEPS[x] === n)) {
      const d = buffers[w].getChannelData(0);
      out[w] = Array.from({ length: n }, (_, i) => {
        const v = d[i * K + 2];
        if (d[i * K + 1] !== v || d[i * K + 3] !== v) throw new Error(`${w}: not ${n} steps per cycle`);
        return q8(v);
      });
    }
  }
  return out;
}

/** The pitched chip waves these TinyChip operator lists use, as `TinySynthSettings.waves` names in order. */
export function sampledWaves(opLists) {
  const used = new Set(opLists.flat().map((o) => o.w));
  return Object.keys(STEPS).filter((w) => used.has(w));
}

/** One TinySynth operator (float fields) -> a TinySynthSettings Operator (fixed point). */
function operator(o, route, wave, mul = 1, gain = 1) {
  return {
    route, wave,
    volume: fx(o.v * gain), ratio: fx(o.t * mul), offset_hz: fx(o.f * mul),
    attack: fx(o.a), hold: fx(o.h), decay: fx(o.d), sustain: fx(o.s), release: fx(o.r),
    pitch_ratio: fx(o.p), pitch_time: fx(o.q), key_scale: fx(o.k), filter: null,
  };
}

/**
 * A TinyChip preset or drum (operator list) -> TinySynthSettings operators, built-in waves expanded and
 * pitched chip waves as `Custom(i)`, `i` their index in `waves` (sampledWaves).
 */
export function timbreOperators(ops, trim = 1, waves = []) {
  const out = [], parts = []; // parts[i]: 1-based indices in `out` of original operator i
  for (const raw of ops) {
    const o = { ...DEFAULTS, ...raw };
    const custom = (w) => (waves.includes(w) ? { Custom: waves.indexOf(w) } : (() => { throw new Error(`wave ${w} not in waves`); })());
    const split = o.w in STEPS ? [[custom(o.w), 1, 1]]
      : INTERIM[o.w] || [[BUILTIN[o.w] || (() => { throw new Error('wave ' + o.w); })(), 1, 1]];
    if (o.g === 0) {
      parts.push(split.map(([w, mul, gain]) => (out.push(operator(o, 0, w, mul, gain * trim * (typeof w === 'string' ? BUILTIN_GAIN[w] ?? 1 : 1))), out.length)));
    } else {
      // FM (g 1..=10) or AM (g 11..: the volume of operator g - 10) of an earlier operator, repeated
      // for each part of a split target; route is the part's 1-based index (AM: plus 10)
      if (split.length > 1) throw new Error('split modulator');
      const [w] = split[0];
      const am = o.g > 10;
      parts.push(parts[o.g - (am ? 11 : 1)].map((target) => (out.push(operator(o, target + (am ? 10 : 0), w)), out.length)));
    }
  }
  if (out.length > 8) throw new Error(`${out.length} operators`);
  return out;
}

/** The mega leads: a mega (shiny) Beast's lead and its octave double play Robot Hero Lead (50) and N163 Brass Wave (65). */
export const MEGA_LEAD_PROGRAMS = [50, 65];

/**
 * The programs a Beast's settings carry: its type's family (src/full_midi.js FAMILIES: three leads,
 * then three plucks; the MIDI picks among them by role, species and name), plus the mega leads when
 * it is mega. The settings depend only on the type and the shiny flag (both in the token ID), so
 * get_settings needs no composition.
 */
export const beastPrograms = (beastType, mega) => [...FAMILIES[beastType].leads, ...FAMILIES[beastType].plucks, ...(mega ? MEGA_LEAD_PROGRAMS : [])];

/** The drum notes the self-contained Beast MIDI plays (src/full_midi.js: groove and fills A-D). */
export const BEAST_DRUMS = [36, 38, 41, 42, 43, 45, 46, 47, 48, 49, 50];

/** The operator lists of the selected programs, then drums. */
const selection = (data, programs, drums) => [...programs.map((id) => data.presets[id]), ...drums.map((key) => data.drums[key])];

/** The `TinySynthSettings.waves` names of the selection, in order. */
export const beastWaves = (data = bankData(), programs = beastPrograms(0, false), drums = BEAST_DRUMS) => sampledWaves(selection(data, programs, drums));

/**
 * The settings: quality 1, the class's default reverb (30) and volume. Only the programs and drum
 * notes Beast MIDI plays (every timbre costs gas in each token_uri), and only the waves they use.
 * `programs` can be any of the 20 essentials (interim_check.mjs passes all of them).
 */
export function beastSynthSettings(data = bankData(), programs = beastPrograms(0, false), drums = BEAST_DRUMS) {
  const waves = beastWaves(data, programs, drums), tables = chipTables(waves);
  const timbres = [
    ...programs.map((id) => ({ drum: false, slot: id, operators: timbreOperators(data.presets[id], TIMBRE_TRIM[id] ?? 1, waves) })),
    ...drums.map((key) => ({ drum: true, slot: key, operators: timbreOperators(data.drums[key], 1, waves) })),
  ];
  return { quality: 1, reverb: 30, master_vol: 40, voices: 64, waves: waves.map((w) => ({ Samples: tables[w] })), timbres };
}

const WAVE_TAGS = ['Sine', 'Square', 'Sawtooth', 'Triangle', 'WhiteNoise', 'MetallicNoise'];
const OP_FIELDS = ['volume', 'ratio', 'offset_hz', 'attack', 'hold', 'decay', 'sustain', 'release', 'pitch_ratio', 'pitch_time', 'key_scale'];
const P = 2n ** 251n + 17n * 2n ** 192n + 1n;

/** Cairo Serde of a TinySynthSettings (as onchain-midi-player's scripts/gen_settings_fixtures.mjs serde()), as BigInts. */
export function serializeSettings(s) {
  const f = [s.quality, s.reverb, s.master_vol, s.voices, s.waves.length];
  for (const w of s.waves) {
    if (!w.Samples) throw new Error('Harmonics waves are not serialized here');
    f.push(1, w.Samples.length, ...w.Samples); // WaveDef::Samples is variant 1
  }
  f.push(s.timbres.length);
  for (const t of s.timbres) {
    f.push(t.drum ? 1 : 0, t.slot, t.operators.length);
    for (const o of t.operators) {
      if (o.filter !== null) throw new Error('filters are not serialized here');
      const wave = typeof o.wave === 'string' ? [WAVE_TAGS.indexOf(o.wave)] : [6, o.wave.Custom]; // Waveform::Custom is variant 6
      f.push(o.route, ...wave, ...OP_FIELDS.map((k) => o[k]), 1); // Option::None is variant 1
    }
  }
  return f.map((x) => ((BigInt(x) % P) + P) % P);
}

/** The Cairo source of beasts/beast_contracts/src/synth_settings.cairo. */
/** A doc comment wrapped as scarb fmt wraps it (greedy, 100 columns). */
const wrapDoc = (text, prefix = '///', width = 100) => {
  const lines = []; let line = prefix;
  for (const w of text.split(/\s+/).filter(Boolean)) {
    if (line !== prefix && line.length + 1 + w.length > width) { lines.push(line); line = prefix; }
    line += ' ' + w;
  }
  return [...lines, line].join('\n');
};

// Shared data: every wave's samples go once into SAMPLES and every distinct operator list once into
// OPERATORS (`const` fixed-size arrays, stored in the class's constant segment); a settings function
// is two tables of slices into them, which `settings_from` turns into the TinySynthSettings. Data in
// constants costs the contract a felt per value; the same values built in code (`array![...]` of
// struct literals in every settings function) cost about 10x that in CASM.
const SAMPLES = []; const SAMPLES_AT = new Map(); // samples key -> start
const OPERATORS = []; const OPERATORS_AT = new Map(); // operator list key -> start
const samplesAt = (samples) => {
  const key = samples.join(',');
  if (!SAMPLES_AT.has(key)) { SAMPLES_AT.set(key, SAMPLES.length); SAMPLES.push(...samples); }
  return SAMPLES_AT.get(key);
};
const operatorsAt = (ops) => {
  const key = ops.join('\n');
  if (!OPERATORS_AT.has(key)) { OPERATORS_AT.set(key, OPERATORS.length); OPERATORS.push(...ops); }
  return OPERATORS_AT.get(key);
};
const check = (ok, what) => { if (!ok) throw new Error(`settings table: ${what} out of range`); };

/** One generated settings function: its Serde hash constant, the function, then its two tables. */
function settingsFn(s, waveNames, fnName, hashName, doc) {
  const hash = poseidonHashMany(serializeSettings(s));
  const wave = (w) => (typeof w === 'string' ? w : `Custom(${w.Custom})`);
  // a wave: start * 0x100 + length, into SAMPLES
  const waves = s.waves.map((w) => {
    const start = samplesAt(w.Samples); const len = w.Samples.length;
    check(len < 0x100 && start < 0x1000000, 'wave');
    return start * 0x100 + len;
  });
  // a timbre: ((first * 0x100 + count) * 2 + drum) * 0x100 + slot, its operators from OPERATORS
  const timbres = s.timbres.map((t) => {
    const ops = t.operators.map((o) => `    Operator { route: ${o.route}, wave: Waveform::${wave(o.wave)}, ${OP_FIELDS.map((k) => `${k}: ${o[k]}`).join(', ')}, filter: Option::None },`);
    const first = operatorsAt(ops); const count = ops.length;
    check(count < 0x100 && first < 0x10000 && t.slot < 0x100, 'timbre');
    return ((first * 0x100 + count) * 2 + (t.drum ? 1 : 0)) * 0x100 + t.slot;
  });
  const up = fnName.replace('beast_synth_settings_', '').toUpperCase();
  return `${wrapDoc(`Poseidon hash of \`${fnName}\`'s Serde, as the generator computes it (tests check Cairo agrees).`)}
pub const ${hashName}: felt252 =
    0x${hash.toString(16)};
/// ${doc} Quality ${s.quality}, reverb ${s.reverb}, volume ${s.master_vol}, ${s.voices} voices; waves: ${waveNames.join(', ') || 'none'}; ${s.timbres.length} timbres.
#[cairofmt::skip]
pub fn ${fnName}() -> TinySynthSettings {
    settings_from(${s.quality}, ${s.reverb}, ${s.master_vol}, ${s.voices}, WAVES_${up}.span(), TIMBRES_${up}.span())
}
#[cairofmt::skip]
const WAVES_${up}: [u32; ${waves.length}] = [${waves.join(', ')}];
#[cairofmt::skip]
const TIMBRES_${up}: [u32; ${timbres.length}] = [${timbres.join(', ')}];
`;
}

/**
 * The Monthly Track Editions' settings (editions_lite.js, edition 1 and later): for each style and
 * Beast type, the presets its lead, accompaniment, bass and pad play (palette rows 0, 2, 3, 4; row 1
 * plays the lead's preset), untrimmed as the editions page plays them, the mega leads when mega,
 * and the chip drums the percussion figures play. Every edition settings value carries the same waves (all the editions' presets use), so a
 * preset's operators (its waves as \`Custom(i)\`) are the same in each and stored once.
 */
export const editionPrograms = (style, type, mega) => [...new Set([0, 2, 3, 4].map((row) => STYLES[style].palette[row][type])), ...(mega ? MEGA_LEAD_PROGRAMS : [])];
export const EDITION_PROGRAMS = [...new Set(STYLES.flatMap((_, s) => [0, 1, 2].flatMap((t) => editionPrograms(s, t, true))))];
export const editionData = () => bankData(undefined, [...new Set([...ESSENTIALS, ...EDITION_PROGRAMS])]);
export const editionWaves = (data = editionData()) => sampledWaves([...EDITION_PROGRAMS.map((id) => data.presets[id]), ...EDITION_DRUMS.map((key) => data.drums[key])]);
export function editionSynthSettings(style, type, mega, data = editionData()) {
  const waves = editionWaves(data), tables = chipTables(waves);
  const timbres = [
    ...editionPrograms(style, type, mega).map((id) => ({ drum: false, slot: id, operators: timbreOperators(data.presets[id], 1, waves) })),
    ...EDITION_DRUMS.map((key) => ({ drum: true, slot: key, operators: timbreOperators(data.drums[key], 1, waves) })),
  ];
  return { quality: 1, reverb: 30, master_vol: 40, voices: 64, waves: waves.map((w) => ({ Samples: tables[w] })), timbres };
}

/** The editions' Cairo: one wave list, one timbre per preset, and each style and type's presets. */
function editionsCairo() {
  const data = editionData(), waves = editionWaves(data);
  const s = editionSynthSettings(0, 0, false, data);
  const waveCodes = s.waves.map((w) => { const start = samplesAt(w.Samples); check(w.Samples.length < 0x100, 'wave'); return start * 0x100 + w.Samples.length; });
  const wave = (w) => (typeof w === 'string' ? w : `Custom(${w.Custom})`);
  const timbreCode = (id, drum = false) => {
    const ops = timbreOperators(drum ? data.drums[id] : data.presets[id], 1, waves).map((o) => `    Operator { route: ${o.route}, wave: Waveform::${wave(o.wave)}, ${OP_FIELDS.map((k) => `${k}: ${o[k]}`).join(', ')}, filter: Option::None },`);
    const first = operatorsAt(ops);
    check(ops.length < 0x100 && first < 0x10000, 'timbre');
    return ((first * 0x100 + ops.length) * 2 + (drum ? 1 : 0)) * 0x100 + id;
  };
  const codes = EDITION_PROGRAMS.map((id) => timbreCode(id));
  const drumCodes = EDITION_DRUMS.map((key) => timbreCode(key, true));
  const at = (id) => EDITION_PROGRAMS.indexOf(id);
  // a palette: its count * 2^20 + its timbres' indices into EDITION_TIMBRES, 5 bits each
  const palettes = STYLES.flatMap((_, st) => [0, 1, 2].map((t) => {
    const progs = editionPrograms(st, t, false);
    check(progs.length <= 4 && EDITION_PROGRAMS.length <= 32, 'palette');
    return progs.length * 2 ** 20 + progs.reduce((acc, id, i) => acc + at(id) * 32 ** i, 0);
  }));
  const hashes = STYLES.flatMap((_, st) => [0, 1, 2].flatMap((t) => [false, true].map((mega) => '0x' + poseidonHashMany(serializeSettings(editionSynthSettings(st, t, mega, data))).toString(16))));
  return `
/// The settings a Monthly Track Edition's file selects (editions_lite.js, edition 1 and later): style
/// \`style\` (0 waltz, 1 chorale, 2 lullaby, 3 dirge, 4 boss battle, 5 sea shanty, 6 march, 7 dungeon
/// crawl, 8 tango) for a Beast of \`beast_type\`, its lead,
/// accompaniment, bass and pad presets as the editions page plays them (untrimmed), the mega leads
/// when mega, and the drums ${EDITION_DRUMS.join(', ')} (the percussion figures). Every edition value carries the editions' ${waves.length} waves: ${waves.join(', ')}.
pub fn edition_synth_settings(style: u32, beast_type: u32, mega: bool) -> TinySynthSettings {
    let palette = *EDITION_PALETTES.span().at(style * 3 + beast_type);
    let timbres = EDITION_TIMBRES.span();
    let mut picked: Array<u32> = array![];
    let mut at = palette % 0x100000;
    let mut n = palette / 0x100000;
    while n > 0 {
        picked.append(*timbres.at(at % 32));
        at /= 32;
        n -= 1;
    }
    if mega {
        picked.append(*timbres.at(${at(MEGA_LEAD_PROGRAMS[0])}));
        picked.append(*timbres.at(${at(MEGA_LEAD_PROGRAMS[1])}));
    }
    for d in EDITION_DRUM_TIMBRES.span() {
        picked.append(*d);
    }
    settings_from(1, 30, 40, 64, EDITION_WAVES.span(), picked.span())
}
#[cairofmt::skip]
const EDITION_WAVES: [u32; ${waveCodes.length}] = [${waveCodes.join(', ')}];
/// One timbre per editions preset, programs ${EDITION_PROGRAMS.join(', ')}.
#[cairofmt::skip]
const EDITION_TIMBRES: [u32; ${codes.length}] = [${codes.join(', ')}];
/// The chip drums ${EDITION_DRUMS.join(', ')}.
#[cairofmt::skip]
const EDITION_DRUM_TIMBRES: [u32; ${drumCodes.length}] = [${drumCodes.join(', ')}];
/// Each style and type's presets (index style * 3 + type): count * 2^20 + indices into
/// EDITION_TIMBRES, 5 bits each.
#[cairofmt::skip]
const EDITION_PALETTES: [u32; ${palettes.length}] = [${palettes.join(', ')}];
/// The Poseidon hash of each \`edition_synth_settings(style, beast_type, mega)\`'s Serde, as the
/// generator computes it, at (style * 3 + beast_type) * 2 + mega (tests check Cairo agrees).
#[cfg(test)]
#[cairofmt::skip]
pub const EDITION_SERDE_HASHES: [felt252; ${hashes.length}] = [${hashes.join(', ')}];
`;
}

/** The six settings the provider serves: each type's family, normal and mega. */
export const SETTINGS_VARIANTS = FAMILIES.flatMap((f, t) => [false, true].map((mega) => ({ type: t, mega, name: f.name.toLowerCase() + (mega ? '_mega' : '') })));
/** The Yeti (species 68, a Brute): the Brute family plus Pulse 12.5% Pluck (13), its avalanche's preset. */
export const YETI_AVALANCHE_PROGRAM = 13;
export const YETI_VARIANTS = [false, true].map((mega) => ({ type: 2, mega, yeti: true, name: 'yeti' + (mega ? '_mega' : '') }));
export const variantPrograms = (v) => [...beastPrograms(v.type, v.mega), ...(v.yeti ? [YETI_AVALANCHE_PROGRAM] : [])];

/** beasts/beast_contracts/src/synth_settings.cairo: the six settings and the lookups by type and mega. */
export function settingsCairo() {
  const fns = [...SETTINGS_VARIANTS, ...YETI_VARIANTS].map((v) => settingsFn(beastSynthSettings(undefined, variantPrograms(v)), beastWaves(undefined, variantPrograms(v)),
    `beast_synth_settings_${v.name}`, `SERDE_HASH_${v.name.toUpperCase()}`,
    `${v.yeti ? 'The Yeti (a Brute): also Pulse 12.5% Pluck (13), its avalanche' : FAMILIES[v.type].name + ' Beasts'}${v.mega ? ' that are mega (shiny): also the mega leads, Robot Hero Lead (50) and N163 Brass Wave (65)' : ''}.`));
  const arm = (fn) => SETTINGS_VARIANTS.map((v) => `        (${v.type}, ${v.mega}) => ${fn(v)},`).join('\n');
  return `//! The Beast sound settings for onchain-midi-player: for each Beast type, its family of TinyChip
//! presets (the programs Beast MIDI selects, in their own program slots) and the chip drum kit,
//! with each pitched chip wave they use as a sampled custom wave; a mega (shiny) Beast's also carry
//! the mega leads. Generated by offchain/beast-sound/onchain/tinychip/synth_settings.mjs --cairo
//! from the TinyChip bank; do not edit by hand.
use midi::types::{Operator, Timbre, TinySynthSettings, WaveDef, Waveform};

/// The settings for a Beast of \`beast_type\` (0 Magic, 1 Hunter, 2 Brute), mega or not: everything
/// its MIDI can select.
pub fn beast_synth_settings(beast_type: u8, mega: bool) -> TinySynthSettings {
    match (beast_type, mega) {
${arm((v) => `beast_synth_settings_${v.name}()`)}
        _ => panic!("invalid type"),
    }
}

/// The Poseidon hash of \`beast_synth_settings(beast_type, mega)\`'s Serde, as the generator computes
/// it (tests check Cairo agrees).
pub fn beast_synth_settings_serde_hash(beast_type: u8, mega: bool) -> felt252 {
    match (beast_type, mega) {
${arm((v) => `SERDE_HASH_${v.name.toUpperCase()}`)}
        _ => panic!("invalid type"),
    }
}

/// The Yeti's settings (species 68): the Brute family and its avalanche's Pulse 12.5% Pluck (13).
pub fn yeti_synth_settings(mega: bool) -> TinySynthSettings {
    if mega {
        beast_synth_settings_yeti_mega()
    } else {
        beast_synth_settings_yeti()
    }
}

/// The Poseidon hash of \`yeti_synth_settings(mega)\`'s Serde.
pub fn yeti_synth_settings_serde_hash(mega: bool) -> felt252 {
    if mega {
        SERDE_HASH_YETI_MEGA
    } else {
        SERDE_HASH_YETI
    }
}

${fns.join('\n')}${editionsCairo()}/// Every wave's samples, each once (\`WAVES_*\`: start * 0x100 + length).
#[cairofmt::skip]
const SAMPLES: [i8; ${SAMPLES.length}] = [${SAMPLES.join(', ')}];
/// Every distinct operator list, each once (\`TIMBRES_*\`: ((first * 0x100 + count) * 2 + drum) *
/// 0x100 + slot); no filters.
#[cairofmt::skip]
const OPERATORS: [Operator; ${OPERATORS.length}] = [
${OPERATORS.join('\n')}
];

/// A settings value from its tables: each wave a slice of SAMPLES, each timbre a slice of
/// OPERATORS.
// Out of line on purpose: inlined, this body is copied into each of the eight settings functions.
#[inline(never)]
fn settings_from(
    quality: u8, reverb: u8, master_vol: u8, voices: u8, waves: Span<u32>, timbres: Span<u32>,
) -> TinySynthSettings {
    let samples = SAMPLES.span();
    let operators = OPERATORS.span();
    let mut wave_defs: Array<WaveDef> = array![];
    for w in waves {
        wave_defs.append(WaveDef::Samples(samples.slice(*w / 0x100, *w % 0x100)));
    }
    let mut timbre_defs: Array<Timbre> = array![];
    for t in timbres {
        let ops = *t / 0x200;
        timbre_defs
            .append(
                Timbre {
                    drum: (*t / 0x100) % 2 == 1,
                    slot: (*t % 0x100).try_into().unwrap(),
                    operators: operators.slice(ops / 0x100, ops % 0x100),
                },
            );
    }
    TinySynthSettings {
        quality, reverb, master_vol, voices, waves: wave_defs.span(), timbres: timbre_defs.span(),
    }
}
`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === '--cairo') {
    const out = fileURLToPath(new URL('../../../../beasts/beast_contracts/src/synth_settings.cairo', import.meta.url));
    writeFileSync(out, settingsCairo());
    console.log(`${out}: ${[...SETTINGS_VARIANTS, ...YETI_VARIANTS].map((v) => v.name).join(', ')}`);
    process.exit(0);
  }
  // the six settings as JSON (onchain-midi-player's scripts/preview.mjs --settings)
  const dir = fileURLToPath(new URL('./settings/', import.meta.url));
  mkdirSync(dir, { recursive: true });
  for (const v of [...SETTINGS_VARIANTS, ...YETI_VARIANTS]) {
    const st = beastSynthSettings(undefined, variantPrograms(v));
    writeFileSync(dir + v.name + '.json', JSON.stringify(st, null, 1) + '\n');
    console.log(`settings/${v.name}.json: ${st.timbres.length} timbres, ${st.waves.length} waves`);
  }
}

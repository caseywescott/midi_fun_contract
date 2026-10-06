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
//   node onchain/tinychip/synth_settings.mjs --cairo      regenerates contracts/beast_sound/src/synth_settings.cairo
import { mkdirSync, writeFileSync } from 'node:fs';
import { poseidonHashMany } from '../../src/index.js';
import { FAMILIES } from '../../src/full_midi.js';
import { fileURLToPath } from 'node:url';
import { bankData, loadBank } from './essentials.mjs';

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

// Per-preset level trims. Pulse 12.5% Pluck (13) is cut to 0.55 (-5.2 dB): its attack peaked 5.5 dB
// over the median of the 20 presets (the same note, in Chrome through the pinned engine) and its narrow
// pulse is the brightest wave in the set, so it read as too loud wherever it played (a Magic pluck, the
// Yeti's avalanche). (Hero Fanfare (53) once had 0.933 while its pulses were square stacks; its exact
// pulse tables match TinyChip without it.)
export const TIMBRE_TRIM = { 13: 0.55 };

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
    if (o.g > 10) throw new Error('AM modulators are not mapped');
    const custom = (w) => (waves.includes(w) ? { Custom: waves.indexOf(w) } : (() => { throw new Error(`wave ${w} not in waves`); })());
    const split = o.w in STEPS ? [[custom(o.w), 1, 1]]
      : INTERIM[o.w] || [[BUILTIN[o.w] || (() => { throw new Error('wave ' + o.w); })(), 1, 1]];
    if (o.g === 0) {
      parts.push(split.map(([w, mul, gain]) => (out.push(operator(o, 0, w, mul, gain * trim * (typeof w === 'string' ? BUILTIN_GAIN[w] ?? 1 : 1))), out.length)));
    } else {
      if (split.length > 1) throw new Error('split modulator');
      const [w] = split[0];
      parts.push(parts[o.g - 1].map((target) => (out.push(operator(o, target, w)), out.length)));
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

/** The Cairo source of contracts/beast_sound/src/synth_settings.cairo. */
/** A doc comment wrapped as scarb fmt wraps it (greedy, 100 columns). */
const wrapDoc = (text, prefix = '///', width = 100) => {
  const lines = []; let line = prefix;
  for (const w of text.split(/\s+/).filter(Boolean)) {
    if (line !== prefix && line.length + 1 + w.length > width) { lines.push(line); line = prefix; }
    line += ' ' + w;
  }
  return [...lines, line].join('\n');
};

/** One generated settings function: its Serde hash constant, then the function itself. */
function settingsFn(s, waveNames, fnName, hashName, doc) {
  const hash = poseidonHashMany(serializeSettings(s));
  const timbres = s.timbres.map((t) => {
    const wave = (w) => (typeof w === 'string' ? w : `Custom(${w.Custom})`);
    const ops = t.operators.map((o) => `            op(${o.route}, Waveform::${wave(o.wave)}, ${OP_FIELDS.map((k) => o[k]).join(', ')}),`);
    return `        Timbre {\n            drum: ${t.drum}, slot: ${t.slot}, operators: array![\n    ${ops.join('\n    ')}\n            ]\n                .span(),\n        },`;
  });
  const waves = s.waves.map((w) => `        WaveDef::Samples(array![${w.Samples.join(', ')}].span()),`);
  return `${wrapDoc(`Poseidon hash of \`${fnName}\`'s Serde, as the generator computes it (tests check Cairo agrees).`)}
pub const ${hashName}: felt252 =
    0x${hash.toString(16)};
/// ${doc} Quality ${s.quality}, reverb ${s.reverb}, volume ${s.master_vol}, ${s.voices} voices; waves: ${waveNames.join(', ') || 'none'}; ${s.timbres.length} timbres, one operator per line.
#[cairofmt::skip]
pub fn ${fnName}() -> TinySynthSettings {
    let waves = array![
${waves.join('\n')}
    ];
    let timbres = array![
${timbres.join('\n')}
    ];
    TinySynthSettings {
        quality: ${s.quality},
        reverb: ${s.reverb},
        master_vol: ${s.master_vol},
        voices: ${s.voices},
        waves: waves.span(),
        timbres: timbres.span(),
    }
}
`;
}

/** The six settings the provider serves: each type's family, normal and mega. */
export const SETTINGS_VARIANTS = FAMILIES.flatMap((f, t) => [false, true].map((mega) => ({ type: t, mega, name: f.name.toLowerCase() + (mega ? '_mega' : '') })));

/** contracts/beast_sound/src/synth_settings.cairo: the six settings and the lookups by type and mega. */
export function settingsCairo() {
  const fns = SETTINGS_VARIANTS.map((v) => settingsFn(beastSynthSettings(undefined, beastPrograms(v.type, v.mega)), beastWaves(undefined, beastPrograms(v.type, v.mega)),
    `beast_synth_settings_${v.name}`, `SERDE_HASH_${v.name.toUpperCase()}`,
    `${FAMILIES[v.type].name} Beasts${v.mega ? ' that are mega (shiny): also the mega leads, Robot Hero Lead (50) and N163 Brass Wave (65)' : ''}.`));
  const arm = (fn) => SETTINGS_VARIANTS.map((v) => `        (${v.type}, ${v.mega}) => ${fn(v)},`).join('\n');
  return `//! The Beast sound settings for onchain-midi-player: for each Beast type, its family of TinyChip
//! presets (the programs Beast MIDI selects, in their own program slots) and the chip drum kit,
//! with each pitched chip wave they use as a sampled custom wave; a mega (shiny) Beast's also carry
//! the mega leads. Generated by offchain/beast-sound/onchain/tinychip/synth_settings.mjs --cairo
//! from the TinyChip bank; do not edit by hand.
use midi_provider::synth::{Operator, Timbre, TinySynthSettings, WaveDef, Waveform};

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

${fns.join('\n')}
/// route, wave, then volume, ratio, offset_hz, attack, hold, decay, sustain, release, pitch_ratio,
/// pitch_time, key_scale (fixed point); no filter.
fn op(
    route: u8,
    wave: Waveform,
    volume: u32,
    ratio: u32,
    offset_hz: i32,
    attack: u32,
    hold: u32,
    decay: u32,
    sustain: u32,
    release: u32,
    pitch_ratio: u32,
    pitch_time: u32,
    key_scale: i32,
) -> Operator {
    Operator {
        route,
        wave,
        volume,
        ratio,
        offset_hz,
        attack,
        hold,
        decay,
        sustain,
        release,
        pitch_ratio,
        pitch_time,
        key_scale,
        filter: Option::None,
    }
}
`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === '--cairo') {
    const out = fileURLToPath(new URL('../../../../contracts/beast_sound/src/synth_settings.cairo', import.meta.url));
    writeFileSync(out, settingsCairo());
    console.log(`${out}: ${SETTINGS_VARIANTS.map((v) => v.name).join(', ')}`);
    process.exit(0);
  }
  // the six settings as JSON (onchain-midi-player's scripts/preview.mjs --settings)
  const dir = fileURLToPath(new URL('./settings/', import.meta.url));
  mkdirSync(dir, { recursive: true });
  for (const v of SETTINGS_VARIANTS) {
    const st = beastSynthSettings(undefined, beastPrograms(v.type, v.mega));
    writeFileSync(dir + v.name + '.json', JSON.stringify(st, null, 1) + '\n');
    console.log(`settings/${v.name}.json: ${st.timbres.length} timbres, ${st.waves.length} waves`);
  }
}

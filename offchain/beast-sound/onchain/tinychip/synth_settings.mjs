// TinyChip as onchain-tinysynth SynthSettings: the presets the self-contained Beast MIDI selects
// (BEAST_PROGRAMS, any of the 20 essentials) as custom timbres in their own program slots (bank
// numbers) and the chip drum kit on channel 10's notes. One source of truth: everything comes from bankData(),
// the same data the TinyChip runtime is built from.
//
// Interim waves. TinyChip's sampled chip waves (12.5/25/50% pulse, the NES 4-bit triangle, a 4-bit
// saw, the two LFSR noises) are custom waves to onchain-tinysynth, which rejects them until its
// issue #2 lands. Until then each is built from TinySynth's own waves at the same level:
//
//   nP50  square                                  (TinyChip pulses swing +-0.5: half a unit square)
//   nP25  square(f) x 0.707 + square(2f) x 0.5    the 25% pulse's exact magnitude spectrum: its odd
//                                                 harmonics are a square's x sin(pi/4), its even ones
//                                                 (2, 6, 10, ...) a square an octave up x 1/2
//   nP12  square(f) x 0.53 + square(2f) x 0.354 + square(4f) x 0.25
//                                                 even harmonics exact; the odd ones alternate
//                                                 sin(pi/8) and sin(3pi/8), so the fundamental square
//                                                 takes the level that matches their energy
//   nTRI  triangle x 0.6 + sawtooth(32f) x 0.04  the NES triangle is a 16-level staircase: a smooth
//                                                 triangle at its peak plus its step error, a saw 32
//                                                 times faster (+-half a step) that keeps the buzz;
//                                                 pitched operators only (on kicks and toms it
//                                                 brightens far past the original)
//   nSAW  sawtooth x 0.45                         the 4-bit saw's peak (smooth, without the steps)
//   nNOI  white noise x 0.866                     same RMS as the +-0.5 LFSR noise
//   nMET  metallic noise                          TinySynth's n1 already sits at 0.5 RMS
//
// A vibrato modulator on a split carrier is repeated for each part (FM depth follows the target's
// frequency, so every part bends by the same ratio). Once issue #2 lands, WAVES below become
// `SynthSettings.waves` (Samples) and every operator keeps its one wave.
//
//   node onchain/tinychip/synth_settings.mjs [out.json]   the settings as JSON (onchain-tinysynth's
//                                                         scripts/preview.mjs --settings)
//   node onchain/tinychip/synth_settings.mjs --cairo      regenerates contracts/beast_sound/src/synth_settings.cairo
import { writeFileSync } from 'node:fs';
import { poseidonHashMany } from '../../src/index.js';
import { fileURLToPath } from 'node:url';
import { bankData } from './essentials.mjs';

const SCALE = 10000;
const DEFAULTS = { g: 0, w: 'sine', t: 1, f: 0, v: 0.5, a: 0, h: 0.01, d: 0.01, s: 0, r: 0.05, p: 1, q: 1, k: 0 };
const BUILTIN = { sine: 'Sine', square: 'Square', sawtooth: 'Sawtooth', triangle: 'Triangle' };

/** TinyChip wave -> [[built-in wave, frequency multiple, level multiple], ...] */
export const INTERIM = {
  nP50: [['Square', 1, 0.5]],
  nP25: [['Square', 1, 0.5 * Math.SQRT1_2], ['Square', 2, 0.25]],
  nP12: [['Square', 1, 0.5 * 0.53], ['Square', 2, 0.5 * 0.3536], ['Square', 4, 0.125]],
  nTRI: [['Triangle', 1, 0.6], ['Sawtooth', 32, 0.04]],
  nSAW: [['Sawtooth', 1, 0.45]],
  nNOI: [['WhiteNoise', 1, 0.866]],
  nMET: [['MetallicNoise', 1, 1]],
};

// Web Audio's built-in oscillators are normalized to their band-limited peak (Gibbs overshoot), so
// their plateau sits below +-1; these gains bring each to the level of the ideal wave the table
// above assumes (measured: K-weighted loudness of every timbre against TinyChip's own, in Chrome
// through the pinned engine; onchain/tinychip/interim_check.mjs).
export const BUILTIN_GAIN = { Square: 1.174, Sawtooth: 1.24, Triangle: 1.063, MetallicNoise: 0.79 };

// Hero Fanfare layers a 12.5% pulse over a 25% pulse an octave down: their shared harmonics add up
// with the square parts' phases, not the pulses', 0.6 dB louder; its output levels come down by that.
export const TIMBRE_TRIM = { 53: 0.933 };

const fx = (x) => Math.round(x * SCALE);

/** One TinySynth operator (float fields) -> a SynthSettings Operator (fixed point). */
function operator(o, route, wave, mul = 1, gain = 1) {
  return {
    route, wave,
    volume: fx(o.v * gain), ratio: fx(o.t * mul), offset_hz: fx(o.f * mul),
    attack: fx(o.a), hold: fx(o.h), decay: fx(o.d), sustain: fx(o.s), release: fx(o.r),
    pitch_ratio: fx(o.p), pitch_time: fx(o.q), key_scale: fx(o.k), filter: null,
  };
}

/** A TinyChip preset or drum (operator list) -> SynthSettings operators, interim waves expanded. */
export function timbreOperators(ops, trim = 1) {
  const out = [], parts = []; // parts[i]: 1-based indices in `out` of original operator i
  for (const raw of ops) {
    const o = { ...DEFAULTS, ...raw };
    if (o.g > 10) throw new Error('AM modulators are not mapped');
    const split = INTERIM[o.w] || [[BUILTIN[o.w] || (() => { throw new Error('wave ' + o.w); })(), 1, 1]];
    if (o.g === 0) {
      const used = o.t === 0 ? split.filter(([, mul]) => mul < 32) : split; // fixed-pitch: no step layer
      parts.push(used.map(([w, mul, gain]) => (out.push(operator(o, 0, w, mul, gain * trim * (BUILTIN_GAIN[w] ?? 1))), out.length)));
    } else {
      if (split.length > 1) throw new Error('split modulator');
      const [w] = split[0];
      parts.push(parts[o.g - 1].map((target) => (out.push(operator(o, target, w)), out.length)));
    }
  }
  if (out.length > 8) throw new Error(`${out.length} operators`);
  return out;
}

/**
 * The programs the self-contained Beast MIDI selects (src/full_midi.js VOICE_PROGRAM): the Triangle
 * Lead only for now, until the preset set is chosen. Any of the 20 essentials can be listed.
 */
export const BEAST_PROGRAMS = [0];

/** The drum notes the self-contained Beast MIDI plays (src/full_midi.js: groove and fills A-D). */
export const BEAST_DRUMS = [36, 38, 41, 42, 43, 45, 46, 47, 48, 49, 50];

/**
 * The settings: quality 1, the class's default reverb (30) and volume. Only the programs and drum
 * notes Beast MIDI plays: every timbre costs gas in each token_uri.
 */
export function beastSynthSettings(data = bankData()) {
  const timbres = [];
  for (const id of BEAST_PROGRAMS) timbres.push({ drum: false, slot: id, operators: timbreOperators(data.presets[id], TIMBRE_TRIM[id] ?? 1) });
  for (const key of BEAST_DRUMS) {
    timbres.push({ drum: true, slot: key, operators: timbreOperators(data.drums[key]) });
  }
  return { quality: 1, reverb: 30, master_vol: 40, voices: 64, waves: [], timbres };
}

const WAVE_TAGS = ['Sine', 'Square', 'Sawtooth', 'Triangle', 'WhiteNoise', 'MetallicNoise'];
const OP_FIELDS = ['volume', 'ratio', 'offset_hz', 'attack', 'hold', 'decay', 'sustain', 'release', 'pitch_ratio', 'pitch_time', 'key_scale'];
const P = 2n ** 251n + 17n * 2n ** 192n + 1n;

/** Cairo Serde of a SynthSettings (as onchain-tinysynth's scripts/gen_settings_fixtures.mjs serde()), as BigInts. */
export function serializeSettings(s) {
  if (s.waves.length) throw new Error('custom waves are not serialized here');
  const f = [s.quality, s.reverb, s.master_vol, s.voices, 0, s.timbres.length];
  for (const t of s.timbres) {
    f.push(t.drum ? 1 : 0, t.slot, t.operators.length);
    for (const o of t.operators) {
      if (o.filter !== null || typeof o.wave !== 'string') throw new Error('filters and custom waves are not serialized here');
      f.push(o.route, WAVE_TAGS.indexOf(o.wave), ...OP_FIELDS.map((k) => o[k]), 1); // Option::None is variant 1
    }
  }
  return f.map((x) => ((BigInt(x) % P) + P) % P);
}

/** The Cairo source of contracts/beast_sound/src/synth_settings.cairo. */
export function settingsCairo(s) {
  const hash = poseidonHashMany(serializeSettings(s));
  const timbres = s.timbres.map((t) => {
    const ops = t.operators.map((o) => `            op(${o.route}, Waveform::${o.wave}, ${OP_FIELDS.map((k) => o[k]).join(', ')}),`);
    return `        Timbre {\n            drum: ${t.drum}, slot: ${t.slot}, operators: array![\n    ${ops.join('\n    ')}\n            ]\n                .span(),\n        },`;
  });
  return `//! The Beast sound settings for onchain-tinysynth: the TinyChip presets Beast MIDI selects, in
//! their own program slots, and its chip drum kit, with interim built-in waves until the class
//! supports custom waves (issue #2). Generated by
//! offchain/beast-sound/onchain/tinychip/synth_settings.mjs --cairo from the TinyChip bank; do not
//! edit by hand.
use midi_provider::synth::{Operator, SynthSettings, Timbre, Waveform};

/// Poseidon hash of the settings' Serde, as the generator computes it (tests check Cairo agrees).
pub const BEAST_SYNTH_SETTINGS_SERDE_HASH: felt252 =
    0x${hash.toString(16)};
/// Quality ${s.quality}, reverb ${s.reverb}, volume ${s.master_vol}, ${s.voices} voices; ${s.timbres.length} timbres, one operator per line.
#[cairofmt::skip]
pub fn beast_synth_settings() -> SynthSettings {
    let timbres = array![
${timbres.join('\n')}
    ];
    SynthSettings {
        quality: ${s.quality},
        reverb: ${s.reverb},
        master_vol: ${s.master_vol},
        voices: ${s.voices},
        waves: [].span(),
        timbres: timbres.span(),
    }
}

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
  const s = beastSynthSettings();
  if (process.argv[2] === '--cairo') {
    const out = fileURLToPath(new URL('../../../../contracts/beast_sound/src/synth_settings.cairo', import.meta.url));
    writeFileSync(out, settingsCairo(s));
    console.log(`${out}: Serde hash 0x${poseidonHashMany(serializeSettings(s)).toString(16)}`);
    process.exit(0);
  }
  const out = process.argv[2] || 'beast_synth_settings.json';
  writeFileSync(out, JSON.stringify(s, null, 1) + '\n');
  const ops = s.timbres.reduce((n, t) => n + t.operators.length, 0);
  console.log(`${out}: ${s.timbres.length} timbres (${BEAST_PROGRAMS.length} programs, ${s.timbres.length - BEAST_PROGRAMS.length} drums), ${ops} operators`);
}

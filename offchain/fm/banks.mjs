// Build four whole-bank variants for listening, each a script the lab loads like bank.min.js:
//   resynth   every instrument described from a recording and rebuilt by additive synthesis
//   hybrid    the same, with each recording's own attack (BRR) joined on
//   physical  plucked-string, bar/drum-mode, clarinet, flute and bowed-string models (no recordings)
//   fm        FM patches (no recordings)
// The violin and flute are Casey's recordings; the other eight are measured from the VSCO sources in
// samples/.source-cache (stand-ins until there are recordings of them).
//   node onchain/snes/resynth/banks.mjs <violin notes recording> <notes in it> <out dir>
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { build } from 'esbuild';
import { readChannels, steady, fundamental, findLoop } from '../samples/loot/notes.mjs';
import { readWav, prepare } from '../prepare.mjs';
import { encodeBRR, decodeBRR } from '../brr.js';
import { toBase91 } from '../pack.js';
import { safeJson } from '../build.mjs';
import { fft, RATE, N, EDGES, ALPHA } from './synth.js';
import { zone } from './engines.js';

const here = dirname(fileURLToPath(import.meta.url)), snes = resolve(here, '..'), [violinFile, violinCount, outDir] = process.argv.slice(2);
const hz = (m) => 440 * 2 ** ((m - 69) / 12), q = (v, max) => ALPHA[Math.max(0, Math.min(max, Math.round(v)))];
const wavOf = (f) => readWav(readFileSync(resolve(snes, f)));

/** A sustained note as [midi, pitch wander in cents, harmonic levels, noise per band] (see synth.js). */
function sustained(x, r0) {
  const st = steady(x, r0), f0 = [0.25, 0.5, 0.75].map((f) => fundamental(x, r0, st.from + f * (st.to - st.from))).sort((a, b) => a - b)[1], midi = Math.round(69 + 12 * Math.log2(f0 / 440));
  const M = Math.min(65536, 2 ** Math.floor(Math.log2(x.length))), win = Float64Array.from({ length: M }, (_, i) => { const t = 2 * Math.PI * i / (M - 1); return 0.35875 - 0.48829 * Math.cos(t) + 0.14128 * Math.cos(2 * t) - 0.01168 * Math.cos(3 * t); });
  const P = new Float64Array(M / 2), room = Math.max(0, Math.floor(st.to * r0) - Math.floor(st.from * r0) - M), frames = Math.max(1, Math.round(room / (M / 2)) + 1);
  for (let f = 0; f < frames; f++) { const s = Math.max(0, Math.min(x.length - M, Math.floor(st.from * r0) + (frames > 1 ? Math.round(f * room / (frames - 1)) : 0))), re = new Float64Array(M), im = new Float64Array(M); for (let i = 0; i < M; i++) re[i] = x[s + i] * win[i]; fft(re, im); for (let k = 0; k < M / 2; k++) P[k] += (re[k] ** 2 + im[k] ** 2) / frames; }
  const bin = r0 / M, H = Math.min(96, Math.floor(Math.min(14500, r0 / 2 - 500) / f0)), half = (f) => Math.max(6, Math.min(0.35 * f0, 0.008 * f) / bin), isH = new Uint8Array(M / 2), E = [], widths = [];
  for (let h = 1; h <= H; h++) { const c = h * f0 / bin, w = half(h * f0); let e = 0, m1 = 0; for (let k = Math.ceil(c - w); k <= c + w; k++) { e += P[k]; m1 += P[k] * k; isH[k] = 1; } m1 /= e; let m2 = 0; for (let k = Math.ceil(c - w); k <= c + w; k++) m2 += P[k] * (k - m1) ** 2; E.push(e); widths.push([e, 1200 * Math.log2(1 + Math.sqrt(Math.max(0, m2 / e - 1.1)) * bin / (h * f0))]); }
  const top = Math.max(...E), total = E.reduce((a, b) => a + b, 0), strong = widths.filter(([e], h) => e > top * 1e-3 && (h + 1) * f0 > 1000).map(([, c]) => c).sort((a, b) => a - b);
  const noise = EDGES.slice(0, -1).map((lo, b) => { let s = 0, c = 0, all = 0; for (let k = Math.ceil(lo / bin); k < EDGES[b + 1] / bin && k < M / 2; k++) { all++; if (!isH[k] && k * bin > 40) { s += P[k]; c++; } } return c ? s / c * all / total : 1e-9; });
  return [midi, +Math.min(4, Math.max(0.5, strong[strong.length >> 1] ?? 1.5)).toFixed(2), E.map((e) => q(-10 * Math.log10(e / top), 80)).join('').replace(new RegExp(`\\${ALPHA[80]}+$`), ''), noise.map((v) => q(-10 * Math.log10(v), 90)).join('')];
}

/** A struck or plucked note as partials [ratio to its fundamental, dB, decay in dB per second], and where it starts. */
function decaying(x, r, root) {
  let pk = 0; for (const v of x) pk = Math.max(pk, Math.abs(v));
  const onset = x.findIndex((v) => Math.abs(v) > 0.1 * pk), f0 = hz(root), W = Math.max(2048, Math.min(8192, 2 ** Math.ceil(Math.log2(14 * r / f0)))), hop = W / 4, frames = [];
  for (let j = 0; ; j++) { const s = onset + Math.round(0.005 * r) + j * hop; if (s + W > x.length || j * hop / r > 1.6) break; const re = new Float64Array(W), im = new Float64Array(W); for (let i = 0; i < W; i++) re[i] = x[s + i] * (0.5 - 0.5 * Math.cos(2 * Math.PI * i / (W - 1))); fft(re, im); frames.push(Float64Array.from({ length: W / 2 }, (_, k) => 10 * Math.log10(re[k] ** 2 + im[k] ** 2 + 1e-20))); }
  const A = frames[0], max = Math.max(...A), bin = r / W, tc = (j) => 0.005 + W / 2 / r + j * hop / r, peaks = [];
  for (let k = 2; k < W / 2 - 2; k++) if (A[k] > max - 50 && A[k] >= A[k - 1] && A[k] > A[k + 1] && A[k] > A[k - 2] && A[k] > A[k + 2] && k * bin > Math.min(40, f0 * 0.6) && k * bin < 14000) peaks.push([k, A[k]]);
  peaks.sort((a, b) => b[1] - a[1]); peaks.length = Math.min(peaks.length, 24);
  const out = peaks.map(([k, a0]) => {
    const off = 0.5 * (A[k - 1] - A[k + 1]) / (A[k - 1] - 2 * A[k] + A[k + 1]), pts = [];
    for (let j = 0; j < frames.length; j++) { const v = Math.max(frames[j][k - 1], frames[j][k], frames[j][k + 1]); if (v < a0 - 40 || (j && v > pts.at(-1)[1] + 3)) break; pts.push([tc(j), v]); }
    let slope = 60, at0 = a0;
    if (pts.length > 1) { const n = pts.length, mx = pts.reduce((s, p) => s + p[0], 0) / n, my = pts.reduce((s, p) => s + p[1], 0) / n, b = pts.reduce((s, p) => s + (p[0] - mx) * (p[1] - my), 0) / pts.reduce((s, p) => s + (p[0] - mx) ** 2, 0); slope = Math.max(2, Math.min(400, -b)); at0 = Math.min(a0 + 12, my + slope * mx); }
    return { f: (k + off) * bin, db: at0, slope };
  });
  const fund = out.filter((p) => Math.abs(1200 * Math.log2(p.f / f0)) < 120).sort((a, b) => b.db - a.db)[0]?.f ?? f0, top = Math.max(...out.map((p) => p.db));
  return { onset, parts: out.filter((p) => p.f > 0.3 * fund).sort((a, b) => a.f - b.f).map((p) => [+(p.f / fund).toFixed(3), +(p.db - top).toFixed(1), Math.round(p.slope)]) };
}

/** A recording's attack as [root, rate, samples, BRR base91], `seconds` from 2 ms before `onset`. */
function attack(x, r, onset, seconds, root, rate = 24000) {
  const from = Math.max(0, onset / r - 0.002); let pk = 0; for (let i = Math.floor(from * r); i < (from + seconds) * r; i++) pk = Math.max(pk, Math.abs(x[i]));
  const p = prepare({ pcm: x, rate: r }, { sampleRate: rate, trimStart: from, trimEnd: from + seconds, fadeIn: 0.001, gain: Math.min(8, 0.7 / pk) }), bytes = encodeBRR(p.pcm, null);
  return { atk: [root, rate, p.pcm.length, toBase91(bytes)], bytes: bytes.length };
}
/** Pitch near an expected frequency: the autocorrelation peak within 12% of its period, refined over
 *  about 30 ms of periods; `r` the match there, `high` the best match at a half, third or two thirds of
 *  the period (near 1 when the tone really sounds in a higher register). */
function pitchNear(x, rate, at, f) {
  const P = rate / f, W = Math.round(Math.max(0.05 * rate, 6 * P)), s = Math.round(at * rate);
  const ac = (L) => { let a = 0, b = 0, c = 0; for (let i = 0; i < W; i++) { const u = x[s + i], v = x[s + i + L] ?? 0; a += u * v; b += u * u; c += v * v; } return a / Math.sqrt(b * c + 1e-30); };
  const peak = (lo, hi) => { let L = lo, best = -2; for (let l = lo; l <= hi; l++) { const v = ac(l); if (v > best) { best = v; L = l; } } const a = ac(L - 1), b = ac(L), c = ac(L + 1), d = a - 2 * b + c; return [L + (d ? Math.max(-1, Math.min(1, 0.5 * (a - c) / d)) : 0), best]; };
  const [T1, r] = peak(Math.max(2, Math.floor(P * 0.89)), Math.ceil(P * 1.12)), K = Math.max(1, Math.round(0.03 * rate / T1)), w = Math.max(1, Math.floor(T1 * 0.4));
  const [TK] = K > 1 ? peak(Math.round(K * T1) - w, Math.round(K * T1) + w) : [T1];
  return { f: rate * K / TK, r, high: Math.max(...[1 / 2, 1 / 3, 2 / 3].map((k) => (T1 * k >= 3 ? ac(Math.round(T1 * k)) : -1))) };
}
/** Mean pitch and worst match over three vibrato cycles from `at` (a single reading follows the vibrato). */
function pitchOver(x, rate, at, f) { const ps = []; for (let j = 0; j < 12; j++) ps.push(pitchNear(x, rate, at + j * 0.545 / 12, f)); return { f: 2 ** (ps.reduce((s, p) => s + Math.log2(p.f), 0) / 12), r: Math.min(...ps.map((p) => p.r)), high: Math.max(...ps.map((p) => p.high)) }; }
const onsetOf = (x) => { let pk = 0; for (const v of x) pk = Math.max(pk, Math.abs(v)); return x.findIndex((v) => Math.abs(v) > 0.05 * pk); };

// ---- the bank's instruments: program, range, level and envelope from the sampled bank
const manifest = JSON.parse(readFileSync(resolve(snes, 'manifest.json'), 'utf8')), firstOf = (program) => manifest.instruments.find((i) => i.program === program);
// a sustained sample's level is its loop's or, when its attack is louder (the cello, which the bass plays far below its root, so the attack lasts), the whole sample's
const refLevel = (inst, loop) => { const p = prepare(wavOf(inst.file), inst), d = decodeBRR(encodeBRR(p.pcm, p.loopStart), p.loopStart), rms = (a, b) => { let s = 0; for (let i = a; i < b; i++) s += d[i] * d[i]; return Math.sqrt(s / (b - a)); }; return loop ? Math.max(rms(p.loopStart, d.length), rms(0, d.length)) : rms(0, Math.min(d.length, Math.round(0.1 * p.rate))); };
const INST = [ // id, program, lowest and highest zone root, sustained
  ['piano', 0, 48, 80, 0], ['glockenspiel', 9, 52, 88, 0], ['marimba', 12, 44, 80, 0], ['cello', 42, 28, 64, 1], ['pizzicato', 45, 36, 76, 0],
  ['harp', 46, 48, 80, 0], ['timpani', 47, 36, 56, 0], ['violin', 48, 40, 80, 1], ['clarinet', 71, 34, 78, 1], ['flute', 73, 48, 84, 1],
].map(([id, program, lo, hi, sus]) => { const ref = firstOf(program); return { id, program, lo, hi, sus, lvl: Math.round(refLevel(ref, sus)), volume: ref.volume, env: sus ? ref.envelope : { attack: ref.envelope.attack, decay: 0, sustain: 1, release: ref.envelope.release } }; });

// ---- measure the recordings
const vsco = (id) => { const w = wavOf(`samples/.source-cache/${id}.wav`); return [w.pcm, w.rate]; };
const src = readChannels(violinFile), slice = Math.floor(src.L.length / +violinCount), violinNotes = [], described = {}, attacks = {}, roots = { harp: 62, marimba: 72, glockenspiel: 84, pizzicato: 72, timpani: 42, piano: 65 };
for (let n = 0; n < +violinCount; n++) violinNotes.push(sustained(src.L.subarray(n * slice, (n + 1) * slice), src.rate));
described.violin = { t: 'a', notes: violinNotes, voices: 3 }; // a section: three detuned players
{ const n = violinNotes.findIndex((z) => z[0] === 60), x = src.L.subarray(n * slice, (n + 1) * slice); attacks.violin = attack(x, src.rate, onsetOf(x), 0.12, 60); }
{ const notes = []; for (const [name, root] of [['C4', 60], ['C5', 72]]) { const w = wavOf(`samples/loot/flute_${name}_src.wav`); notes.push(sustained(w.pcm, w.rate)); if (root === 72) attacks.flute = attack(w.pcm, w.rate, onsetOf(w.pcm), 0.1, notes.at(-1)[0]); } described.flute = { t: 'a', notes, vib: [13, 13, 0.2], chiff: [0.06, -9] }; } // the recording's vibrato (6.2 Hz, about 14 cents either way, 5 dB of level) and a breath at the start
// the cello is a section of three, each wandering less than the section's measured spread
for (const id of ['cello', 'clarinet']) { const [x, r] = vsco(id), z = sustained(x, r); described[id] = id === 'cello' ? { t: 'a', notes: [[z[0], Math.min(z[1], 2), z[2], z[3]]], voices: 3 } : { t: 'a', notes: [z] }; attacks[id] = attack(x, r, onsetOf(x), 0.1, z[0]); }
// the glockenspiel is darker than recorded (tilt), by request
for (const [id, root] of Object.entries(roots)) { const [x, r] = vsco(id), d = decaying(x, r, root); described[id] = { t: 'm', root, parts: d.parts, dk: 0.5, ...(id === 'glockenspiel' ? { tilt: 7 } : {}) }; attacks[id] = attack(x, r, d.onset, 0.06, root); }
for (const [id, d] of Object.entries(described)) console.error(id, d.t === 'a' ? d.notes.map((z) => `MIDI ${z[0]}: ${z[2].length} harmonics, wander ${z[1]} c`).join('; ') : `${d.parts.length} partials: ` + d.parts.slice(0, 8).map((p) => p.join('/')).join(' '));

// ---- the models and patches that use no recording
const PHYSICAL = {
  piano: { t: 'k', t60: 3.2, dk: 0.6, damp: 0.3, bright: 0.25, pick: 0.12, strings: [-1.5, 1.5] },
  glockenspiel: { t: 'm', root: 84, dk: 0.3, parts: [[1, 0, 9], [2.756, -15, 20], [5.404, -27, 38], [8.933, -38, 60]], strike: [-24, 2, 0.3] },
  marimba: { t: 'm', root: 60, dk: 0.6, parts: [[1, 0, 28], [3.93, -15, 60], [9.24, -27, 120]], strike: [-12, 4, 0.5] },
  cello: { t: 'b', v: 0.15, slope: 1.5, beta: 0.127236, vib: 9, noise: 0.06, duo: 1 },
  pizzicato: { t: 'k', t60: 0.5, dk: 0.3, damp: 0.5, bright: 0.3, pick: 0.2 },
  harp: { t: 'k', t60: 2.6, dk: 0.6, damp: 0.2, bright: 0.5, pick: 0.3 },
  timpani: { t: 'm', root: 42, dk: 0.3, parts: [[1, 0, 9], [1.504, -4, 13], [1.99, -9, 18], [2.44, -13, 24], [2.89, -17, 32]], strike: [-8, 14, 0.12] },
  violin: { t: 'b', v: 0.15, slope: 1.5, beta: 0.127236, vib: 11, noise: 0.06, duo: 1 },
  clarinet: { t: 'c', p: 0.8, noise: 0.1 },
  flute: { t: 'u', p: 1.2, noise: 0.12, lo: 52 }, // the model overblows below E3; the lowest zone plays those notes
};
const FM = {
  piano: { t: 'f', ops: [[1, 1, 2.2, 0.4, 0.25, 1, 18], [1, 14, 1.1, 0, 0.08, 0.3, 30]] },
  glockenspiel: { t: 'f', dk: 0.3, ops: [[1, 3.5, 1.1, 0.12, 0.2, 1, 13, 0, [5.404, 0.7]], [1, 7.1, 0.5, 0, 0.04, 0.12, 50]] },
  marimba: { t: 'f', dk: 0.5, ops: [[1, 4, 1.8, 0, 0.05, 1, 34], [1, 1, 0.3, 0, 0.1, 0.5, 30]] },
  cello: { t: 'f', sus: 1, pre: 6400, vib: [9, 11], ops: [[1, 1, 2.6, 1.8, 0.08, 1, 1, 1.1], [1, 1, 2.4, 1.7, 0.08, 0.9, -1, 1.1], [2, 1, 1.4, 1.0, 0.06, 0.2, 0], [1, 2, 1.3, 0.9, 0.08, 0.4, 2], [3, 1, 0.9, 0.7, 0.06, 0.12, -2], [1, 3, 0.8, 0.5, 0.1, 0.3, -3]] },
  pizzicato: { t: 'f', dk: 0.3, ops: [[1, 1, 2.6, 0.2, 0.05, 1, 60]] },
  harp: { t: 'f', dk: 0.5, ops: [[1, 1, 3.0, 0.3, 0.12, 1, 20], [1, 3, 1.0, 0, 0.05, 0.3, 35]] },
  timpani: { t: 'f', dk: 0.3, ops: [[1, 1.5, 2.2, 0.4, 0.2, 1, 20], [1.5, 1, 1.0, 0.2, 0.1, 0.4, 30]] },
  violin: { t: 'f', sus: 1, pre: 6400, vib: [11, 11], ops: [[1, 1, 2.4, 1.7, 0.08, 1, 1, 1.0], [1, 1, 2.2, 1.6, 0.08, 0.9, -1, 1.0], [2, 1, 1.5, 1.2, 0.06, 0.25, 0], [1, 2, 1.3, 0.9, 0.08, 0.4, 3], [3, 1, 0.9, 0.7, 0.06, 0.14, -2], [1, 3, 0.8, 0.5, 0.1, 0.3, -4]] },
  clarinet: { t: 'f', sus: 1, pre: 4800, vib: [3, 10], ops: [[1, 2, 2.4, 1.6, 0.06, 1, 0], [3, 2, 0.8, 0.5, 0.05, 0.15, 0]] },
  flute: { t: 'f', sus: 1, pre: 4800, vib: [13, 13], ops: [[1, 1, 1.3, 0.55, 0.05, 1, 0, 0, [2, 0.6]], [2, 1, 0.6, 0.2, 0.04, 0.12, 1], [3, 1, 0.5, 0.1, 0.03, 0.05, 0]] },
};
// The violin as first converted from the fmViolin patch, kept to go back to (not in the bank).
const VIOLIN_AS_CONVERTED = () => ({ ...{ t: 'f', sus: 1, takes: 2, human: 1, var: { index: 0.06, vibRate: 1, vibDepth: 0.15, vibDelay: 0.2, air: 2 }, pre: 23040, vib: [14, 11, 0.28, 0.38], vibAmp: 0.08, vibIdx: 0.1, drift: 1.2, lp: 7055, env: [0.08, 0, 1, 0.28],
    eq: [['p', 275, 1.11, 1.95], ['p', 460, 1.54, 2.35], ['p', 1050, 1.25, -2.2], ['p', 2400, 0.91, 3.2], ['s', 5500, 1, -3.5]],
    air: { pre: 1, bands: [[0, 3.5, 0.65, 1, 900, 6500, 1], [2800, 0, 1, 0.16, 0, 14000, 2]], gain: 0.066, vib: 0.15, puff: [0, 0.65, 0.037, 3.5] },
    ops: [[1, 1, 0.51, 1.79, 0.07, 0.56, 0], [2, 1, 0.316, 1.11, 0.07, 0.23, 0], [3, 2, 0.163, 0.574, 0.07, 0.11, 0], [1, 1, 0, 0, 0.1, 0.16, 0],
      [1, 1, 0.51, 1.79, 0.09, 0.224, 1], [2, 1, 0.316, 1.11, 0.09, 0.092, 2], [3, 2, 0.163, 0.574, 0.09, 0.044, 3], [1, 1, 0, 0, 0.1, 0.064, 1]] } });
// The Kankyo FM demo's patches (SuperCollider_Ideas/Kankyo_FM_Demo_UI.scd) and the Mild und Leise chord
// patch, as recipes for this engine: phase-modulation indices carried over as written (a frequency-
// modulated carrier's index is its depth over the modulator ratio), SinOscFB as feedback, each patch's
// lowpass as `lp`, detuned stacks as carrier ratios. Left out: slow LFO drifts, comb echoes, stereo
// spread and, for the acid bass, the moving resonant filter (a fixed key-tracked lowpass stands in).
// `env` is the playing envelope [attack, decay, sustain, release], shortened where Casey asked.
const cents = (c) => +(2 ** (c / 1200)).toFixed(5);
// The bowed-string voice (see the note at `violin` below): the strings as built, or the softer, quieter lead.
const stringVoice = (lead) => ({ t: 'f', sus: 1, align: 1, ...(lead ? { trim: -11.04 } : {}), takes: 3, human: 1, var: { index: 0.06, vibRate: 1, vibDepth: 0.15, vibDelay: 0.2, air: 2 }, pre: 23040, vib: [14, 11, 0.28, 0.38], vibWob: 0.15, vibAmp: 0.06, vibIdx: 0.08, drift: 1.2, scoop: [6, 0.03], lp: lead ? 6500 : 9000, env: [0.08, 0, 1, 0.28],
  eq: [['p', 275, 4, 3.5], ['p', 460, 5, 4], ['p', 550, 5, 3.5], ['p', 700, 2, -2.5], ['p', 1000, 3, 2.5], ['p', 1300, 3, 1.5], ['p', 1700, 2, -3], ...(lead ? [['p', 2500, 1.5, 2.5], ['p', 3300, 3, 0.5], ['s', 4500, 1, -9]] : [['p', 2500, 1.5, 5], ['p', 3300, 3, 2.5], ['s', 5000, 1, -7]])],
  air: { pre: 1, bands: [[0, 3.5, 0.65, 1, 900, 6500, 1], [2800, 0, 1, 0.16, 0, 14000, 2]], gain: 0.066, vib: 0.15, puff: [0, 0.65, 0.05, 3.5] },
  zones: (lead ? [40, 44, 48, 52, 56, 60, 64, 68, 72, 76, 80, 84] : [40, 44, 48, 52, 56, 60, 64, 68, 72, 76, 80]).map((m) => stringAt(m, lead ? 2600 : 4000)) });
// The harp's four FM pairs at a note, from the patch's formulas at its defaults (brightness 0.55, hardness
// 0.48, velocity 0.7, bloom 0.3, finger 0.25, pluck position 0.36): the main string (1:1, index falling fast
// then slowly), a shorter bright octave body, the quiet lingering bloom (2:1, a fraction of a cent sharp,
// arriving a few hundredths of a second late) and the finger-release click (3x carrier, 2.027x modulator),
// which skips the pluck-position comb. Ring time follows the patch: 10.5 s at C1 down to 1.6 s at G7.
// Brighter and louder than the patch, by ear (Casey): the main string's index is twice the patch's and falls
// more slowly (0.07 s, was 0.048), the octave body's index and level are 1.5 times, it is plucked nearer the
// end (0.22 of the string, was 0.36, which had notched out the third harmonic), the lowpass is 8 kHz + 1.2x
// the note (was 5.1 kHz), and the level is +4 dB.
function harpAt(m) {
  const B = 2, f = 440 * 2 ** ((m - 69) / 12), r = (v) => +v.toFixed(4), c01 = (v) => Math.max(0, Math.min(1, v)), reg = c01((m - 24) / 79), bass = c01((60 - m) / 24);
  const tr = f < 700 ? 1 : Math.max(0.16, 0.16 ** (Math.log(f / 700) / Math.log(3135.9635 / 700))), t60 = 10.5 * (1.6 / 10.5) ** (Math.log(f / 32.7032) / Math.log(3135.9635 / 32.7032)), rise = 0.00282 * (1.12 - 0.4 * reg);
  return { ops: [
    [1, 1, r(B * 0.749 * tr), r(B * 0.211 * tr), 0.07, 1, r(60 / t60), 0, null, null, 0, [r(B * 0.0497 * tr), r(t60 * 0.09)], r(rise)],
    [2, 1, r(1.5 * 0.5425 * tr), r(1.5 * 0.0434 * tr), 0.026, r(1.5 * 0.196), r(60 / (0.43 * t60)), 0, null, null, 0, [0, r(t60 * 0.05)], r(rise * 0.75)],
    [r(2 ** (0.55 * (0.35 + 0.25 * reg) / 1200)), 2, r(0.018 + 0.15 * tr), r(0.018 + 0.036 * tr), 0.048, 0.156, r(40 / t60), 0, null, null, 0, [r(0.018 + 0.0018 * tr), r(t60 * 0.09)], r(0.018 + 0.018 * bass)],
    [3, 2.027, r(0.724 * tr), 0, 0.005, r(0.0196 * (1 - 0.55 * reg)), 2500, 0, null, null, 0, null, 0.0007, 1]] };
}
// A bowed string's operators at a note: a plain fundamental and carriers at 1 to 5 times the note, all driven
// by one feedback modulator, with levels and indices found by a seeded search so that the harmonics fall as a
// bowed string's do (1/n, easing off above `corner`) as far up as fits under 10.5 kHz; then the second player,
// a fifth as loud and a beat or so away. The fit assumes every operator starts in step (the patch's `align`):
// a carrier's own phase changes how its folded sidebands add. The index opens from 0.28 of its value, as the patch's does.
function stringAt(m, corner = 4000) {
  const f = 440 * 2 ** ((m - 69) / 12), P = Math.round(RATE / f), ease = Math.min(1, Math.sqrt(523 / f)), H = Math.max(3, Math.min(16, Math.floor(10500 / f), (P >> 1) - 2)), top = Math.min((P >> 1) - 1, H + 4);
  const target = (h) => -20 * Math.log10(h) - 10 * Math.log10(1 + (h * f / corner) ** 2), n = P * 4, cs = [], sn = [];
  for (let h = 1; h <= top; h++) { cs.push(Float64Array.from({ length: 2 * P }, (_, i) => Math.cos(2 * Math.PI * h * i / P))); sn.push(Float64Array.from({ length: 2 * P }, (_, i) => Math.sin(2 * Math.PI * h * i / P))); }
  const cost = (p) => {
    const x = new Float64Array(2 * P); let m1 = 0, m2 = 0;
    for (let i = 0; i < n; i++) { const th = 2 * Math.PI * i / P, md = Math.sin(th + p[0] * ease * 0.5 * (m1 + m2)); m2 = m1; m1 = md; if (i < 2 * P) continue; let v = p[1] * Math.sin(th); for (let c = 1; c <= 5; c++) v += p[2 * c] * Math.sin(c * th + p[2 * c + 1] * md); x[i - 2 * P] = v; }
    const db = []; for (let h = 0; h < top; h++) { let re = 0, im = 0; for (let i = 0; i < 2 * P; i++) { re += x[i] * cs[h][i]; im += x[i] * sn[h][i]; } db.push(10 * Math.log10(re * re + im * im + 1e-9)); }
    let e = 0; for (let h = 2; h <= top; h++) { const d = db[h - 1] - db[0] - target(h); e += h <= H ? d * d : Math.max(0, d) ** 2; }
    return e / (top - 1);
  };
  let seed = m * 7919 + 1; const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff) * 2 - 1;
  let best = [0.9, 0.16, 0.56, 1.8, 0.23, 1.1, 0.11, 0.6, 0.08, 0.8, 0.05, 0.8], bc = cost(best);
  for (let it = 0; it < 2500; it++) { const q = best.map((v, i) => { const lim = i === 0 ? 1.3 : i === 1 ? 0.5 : i % 2 ? 2.6 : 1; return Math.max(0, Math.min(lim, v + rnd() * (it < 1500 ? 0.15 : 0.04) * lim * (rnd() > 0 ? 1 : 0))); }), c = cost(q); if (c < bc) { best = q; bc = c; } }
  const r = (v) => +v.toFixed(3), fb = r(best[0]), ops = [[1, 1, 0, 0, 0.1, r(best[1]), 0]];
  for (let c = 1; c <= 5; c++) if (best[2 * c] > 0.004 && c * f < 12000) ops.push([c, 1, r(0.28 * best[2 * c + 1]), r(best[2 * c + 1]), 0.07, r(best[2 * c]), 0, fb]);
  stringAt.fit = (stringAt.fit ?? []).concat((corner < 4000 ? 'lead ' : '') + m + ': ' + Math.sqrt(bc).toFixed(1) + ' dB over ' + H);
  return { ops: [...ops, ...ops.map((o, j) => { const q = [...o]; q[5] = r(o[5] * 0.2); q[6] = o[0]; q[4] = j ? 0.09 : 0.1; return q; })] };
}
// The clarinet's register-dependent settings at a sounding note, from the patch's own formulas: a 1:2 pair
// for the odd harmonics with small 4x and 1x modulators beside it, and a second carrier an octave up whose
// level grows from the throat notes (around G4) into the clarion register (A4 up); the 1150 Hz dip fades
// out there. Breath is two broad bands and three narrow ones on the note's 1st, 3rd and 5th harmonics.
// Raised here: breath 10 dB and the tongued "spit" 6 dB (as written the breath sits some 50 dB under the tone).
function clarinetAt(m) {
  const c01 = (v) => Math.max(0, Math.min(1, v)), r = (v) => +v.toFixed(4), throat = (1 - c01(Math.abs(m - 67) / 3.5)) ** 2, clarion = c01((m - 67) / 6), alt = c01((m - 85) / 9);
  const k = (1 - 0.17 * throat) * (1 - 0.32 * alt), odd = 0.883 * k, start = 0.364 * k, evenLevel = (0.018 + 0.075 * throat + 0.22 * clarion + 0.055 * alt) * 0.66, norm = 1 / (1 + 0.4 * evenLevel);
  return { ops: [[1, 2, r(start), r(odd), 0.038, r(norm), 0, 0, null, [[4, r(0.0368 * (1 - 0.65 * alt))], [1, r((0.008 + 0.045 * throat + 0.075 * clarion) * 0.683)]]], [2, 2, r(0.32 * start), r(0.32 * odd), 0.038, r(evenLevel * norm), 0]],
    eq: [['p', 1150, 1.25, r(-1.8 * (1 - clarion))], ['p', 2957, 1.43, 0.5]],
    airGain: r(0.046 * (1 + 0.25 * throat)) };
}
// The fmClarinet voice as converted (the Kankyo clarinet until 2026-11-16), kept to go back to (not in the bank).
// The fmClarinet voice (FM CLARINET, Casey's SuperCollider patch) with the slurred example's settings
// (velocity 0.7, vibrato 4 cents after 0.3 s, pressure 0.65, the middle of that phrase): see clarinetAt.
const CLARINET_AS_CONVERTED = { t: 'f', sus: 1, slur: 1, takes: 2, human: 1, var: { index: 0.05, vibDepth: 0.25, vibDelay: 0.2, air: 2 }, pre: 30720, vib: [4, 11, 0.3, 0.6], vibAmp: 0.03, vibIdx: 0.05, drift: 0.52, scoop: [2.34, 0.03], lpk: 1.6, lpo: 4569, env: [0.033, 0, 1, 0.12],
    air: { bands: [[2095, 0, 0.8, 0.65], [4800, 0, 0.65, 0.25], [0, 1, 0.1, 0.77, 100, 12800], [0, 3, 0.075, 0.42, 100, 12800], [0, 5, 0.06, 0.21, 100, 12800]], gain: 0.046, vib: 0.05, puff: [3100, 0.75, 0.036, 0, 0.008] },
    zones: [34, 38, 42, 46, 50, 54, 58, 62, 66, 70, 74, 78].map(clarinetAt) };
const KANKYO = {
  // The electric piano: the DX7's E.PIANO 1 (ROM1A 11), algorithm 5, as three carrier-modulator pairs: the
  // tine (carrier 1, modulator 14, fast-decaying), and two 1:1 bodies, the second detuned -7/+7 with feedback 6
  // on its modulator. Operator values are the published preset's as I know them (levels 99/58, 99/89, 99/79),
  // not read from a patch file; output levels become indices by the usual DX7 law (pi * 2^(33/16 - (99-level)/8)),
  // set back about 7 steps for a medium-hard key (the modulators are velocity-sensitive, and a note here has
  // one velocity). Envelope rates 20-50 become decays of 3-100 dB/s. Replaces Yabuki Velvet.
  // Then made less glassy, by ear (Casey: "less cheesy"): the tine quieter, shorter and half as deep; the
  // bodies' indices about 0.6 of the preset's (less bark) and settling to a little brightness, not none; the
  // second body's detune and feedback halved (less shimmer); a lowpass at 3.2 kHz or 4x the note; a faster
  // decay. As converted from the preset the three pairs were [.., 14, 0.3, 0.04, 0.087, 0.33, 5.6],
  // [1, 1, 2.0, 1.4, 0.15, 0.33, 3.1] and [-3 c, +3 c, 0.9, 0.63, 0.15, 0.33, 3.1, feedback 0.8], unfiltered.
  piano: { t: 'f', dk: 0.3, len: 3.5, lp: 3200, lpk: 4, env: [0.002, 0, 1, 0.25], ops: [
    [cents(0.8), 14, 0.16, 0.02, 0.05, 0.16, 9, 0, null, null, 0, [0, 0.3]],
    [1, 1, 1.15, 0.75, 0.12, 0.45, 4.5, 0, null, null, 0, [0.15, 2]],
    [cents(-1.5), cents(1.5), 0.55, 0.38, 0.12, 0.39, 4.5, 0.4, null, null, 0, [0.1, 2]]] },
  // Mist Choir, short attack and release, played as percussion: six detuned near-sines
  glockenspiel: { t: 'f', sus: 1, pre: 1600, vib: [0, 11], lp: 2800, lpk: 2.5, trim: -6, align: 1, env: [0.006, 0.3, 0.3, 0.14], ops: [-14, -7, -2, 3, 8, 15].map((c) => [cents(c), cents(c), 0.018, 0.018, 0.1, 1 / 6, 0]) },
  // Kokubo Plonk: index 2 at the strike, gone in 0.35 s; a 4.04x click
  marimba: { t: 'f', dk: 0.2, lp: 2600, lpk: 2.5, ops: [[1, 2, 2.0, 0, 0.035, 1, 26], [4.04, 1, 0, 0, 0.1, 0.15, 450]] },
  // 303 Soft Square as the bass: a feedback saw over a half-speed feedback pulse, lowpassed at 3.4x the note
  // (its attack is 10 ms, not the patch's 2: at 2 a low note's first cycle arrives as a step, a click on every note)
  cello: { t: 'f', sus: 1, pre: 1600, vib: [0, 11], lpk: 3.4, env: [0.01, 0, 1, 0.08], ops: [[1, 1, 1.6, 1.6, 0.1, 0.55, 0, 1.0], [0.5, 0.5, 1.4, 1.4, 0.1, 0.35, 0, 0.9]] },
  // Rain Pluck
  pizzicato: { t: 'f', dk: 0.2, lp: 5000, ops: [[1, 2, 1.8, 0, 0.04, 1, 80]] },
  // The fmHarp voice (FM HARP, Casey's SuperCollider patch) at its defaults: see harpAt. At full level again
  // (the Shadowfax harp it replaces had been turned down 30%). Notes ring past their note-off (release 1.2 s),
  // as the patch's do; up to 3.2 s of each is kept.
  harp: { t: 'f', takes: 3, human: 0.6, var: { comb: 0.025, index: 0.07 }, dk: 0, len: 3.2, comb: 0.22, trim: 4, lpk: 1.2, lpo: 8000, eq: [['l', 220, 1, 0.9], ['p', 850, 1.43, 0.63], ['p', 2800, 1.25, -0.675]], env: [0.001, 0, 1, 1.2],
    zones: [48, 52, 56, 60, 64, 68, 72, 76, 80].map(harpAt) },
  timpani: FM.timpani,
  // The fmViolin voice (FM VIOLIN, Casey's SuperCollider patch) at its defaults (pressure and brightness 0.55,
  // expression 0.85, body 0.8, humanize 0.55): carriers at 1, 2 and 3 times the note, each with its own
  // modulator, over a plain fundamental; the index opens behind the level (a bowed onset); vibrato 14 cents
  // after 0.28 s; pink bow friction with a scrape at the start; the five fixed body bands at the strength
  // body 0.8 gives them; lowpass 7055 Hz. Added here: a second, quieter player half a hertz away; vibrato
  // that also moves level, brightness and friction; friction and scrape 12 dB up (as written they sit
  // some 50 dB under the string). Replaces AFX Strings 5.
  // Then rebuilt for a fuller string (Casey: make it sound better, it may be bigger). As converted, the three
  // pairs gave five harmonics and almost nothing above (the sixth 40 dB down); a bowed string has fifteen or
  // more, falling about 6 dB an octave. Now: per register, five carriers on one feedback modulator, their
  // levels and indices fitted to that string spectrum (stringAt); ten fixed body bands after the violin's
  // own resonances (the air mode near 275 Hz, the two body modes near 460 and 550, the bridge hill around
  // 2.5 kHz), moderate in sharpness, where the patch has five broad ones; a vibrato whose depth swells and
  // eases; a small scoop into the note; three takes. Kept from the patch: its vibrato, bow friction and
  // scrape, the index opening behind the level, the second, quieter player. The converted patch is VIOLIN_AS_CONVERTED.
  // By ear (Casey): as built it is right for pads but way too loud and a bit shrill on a lead. So there are
  // two of it (stringVoice): the strings (program 48, pads and inner parts) as built, and a lead violin
  // (program 40) 11 dB down (6, then 30% and 20% more by ear) with less on top: its spectrum eases off from 2.6 kHz (4 for the strings), the
  // bridge hill is +2.5 dB (+5), the 3.3 kHz band +0.5 (+2.5), the shelf -9 dB from 4.5 kHz (-7 from 5), the
  // lowpass 6.5 kHz (9).
  // Replaced (2026-11-16, Casey's pick after an A/B): the strings are now Bill Schottstaedt's fm-violin (CCRMA, CLM),
  // its carrier and 1x, 3x and 4x modulators with indices following his formulas in pitch (engines.js `fmv`, fm-index
  // 1.8, twice as bright at the start), played by six players a few cents apart, each with their own vibrato (12-16
  // cents, 4.4-6.3 Hz), a slow jitter and a fast random-sounding vibrato (his random vibrato, near 16 Hz); the body
  // bands and bow friction of the voice above. Measured (loop, H1..H8 dB): G3 -14 -6 0 -12 -6 -11 -15 -15. The fitted
  // voice described above is stringVoice, kept to go back to (3.2 KB, and the bank build's 40 s fit).
  violin: { t: 'f', sus: 1, pre: 16000, fmv: [1.8, 2, 0.12], fmvFb: 0.3, vib: [0, 11, 0.15, 0.3], scoop: [5, 0.03], lp: 9000, env: [0.09, 0, 1, 0.3],
      section: [[0, 1, 13, 11, 0, 5, 3], [-7, 0.9, 15, 10, 1.9, 6, 4], [8, 0.9, 12, 12, 3.7, 5, 2], [-3, 0.85, 14, 9, 5.1, 6, 5], [5, 0.8, 16, 13, 0.7, 4, 3], [-10, 0.75, 12, 11, 2.6, 5, 4]],
      rvib: [3, [29, 37, 43]], eq: [['p', 275, 4, 3.5], ['p', 460, 5, 4], ['p', 550, 5, 3.5], ['p', 700, 2, -2.5], ['p', 1000, 3, 2.5], ['p', 1300, 3, 1.5], ['p', 1700, 2, -3], ['p', 2500, 1.5, 5], ['p', 3300, 3, 2.5], ['s', 5000, 1, -7]],
      air: { pre: 1, bands: [[0, 3.5, 0.65, 1, 900, 6500, 1], [2800, 0, 1, 0.16, 0, 14000, 2]], gain: 0.05, vib: 0.15, puff: [0, 0.65, 0.05, 3.5] } },
  // Replaced (2026-11-16, Casey's pick after an A/B): Chowning's FM clarinet: carrier 1, modulator 2 (odd harmonics
  // only), a small 1x modulator for the weak even ones, the index rising with the attack (brightness follows loudness);
  // slurs. Measured (loop, H1..H8 dB): D3 0 -23 -11 -27 -11 -44 -27 -47. 283 B against the converted voice's 2.6 KB
  // (CLARINET_AS_CONVERTED, kept to go back to).
  clarinet: { t: 'f', sus: 1, slur: 1, pre: 9600, vib: [3, 10, 0.1, 0.15], drift: 0.8, lpk: 5, lpo: 1500, env: [0.03, 0, 1, 0.1],
      ops: [[1, 2, 0.4, 1.6, 0.05, 1, 0, 0, null, [1, 0.15], 0.3]], air: { bands: [[1800, 0, 0.8, 0.5]], gain: 0.012, puff: [1500, 0.9, 0.03, 0, 0.01] } },
  // The fmFlute voice (FM FLUTE, Casey's SuperCollider patch) at its audition settings (pressure and velocity
  // 0.72, brightness 0.8, breath 0.28, tongue 0.75): one carrier with a 1:1 and a quieter 2:1 modulator,
  // indices easing up the register, a tongued start (brighter, 7 cents under, a puff of air), vibrato after
  // 0.32 s, three bands of breath outside the FM, lowpass at 5.6x the note + 900 Hz. Added here: the
  // vibrato also moves level, brightness and breath (Casey's recorded flute swings 5 dB with its vibrato).
  // Breath in the tone (2026-11-16, Casey: the A/B version, a bit less breathy): slow noise moves the index (engines.js
  // `nmod`, 15% at up to 120 Hz), so the breath rides in sidebands on each harmonic and moves with the tone, and the
  // breath beside it is 5 dB down (gain 0.045, was 0.08). At G4 the noise on the harmonics is 2 dB over the voice without.
  // 3 dB up (Casey: quieter than the clarinet; measured K-weighted, it sat 3 dB under it at every register).
  flute: { t: 'f', sus: 1, trim: 3, nmod: [0.15, 120], airGain: 0.045, takes: 2, human: 1, var: { index: 0.08, vibRate: 1, vibDepth: 0.15, vibDelay: 0.2, air: 2 }, pre: 30400, vib: [13, 11, 0.32, 0.55], vibAmp: 0.16, vibIdx: 0.15, drift: 1.8, scoop: [6.75, 0.025], lp: 2000, lpk: 8, lpo: 1500, env: [0.039, 0, 1, 0.18],
    air: { reg: 0.4, bands: [[950, 0.65, 0.8, 0.65, 700, 4500], [4200, 0, 0.65, 0.32], [0, 2, 0.12, 0.22, 500, 8000]], gain: 0.08, vib: 0.2, puff: [2600, 0.9, 0.06] }, // breath and puff 4 dB and 3 dB above the patch (0.0506, 0.044)
    // a lot brighter than the patch, by ear (Casey): its indices were 0.61 falling to 0.44 and 0.067, its lowpass 5.6x the note + 900 Hz
    ops: [[1, 1, 1.25, 0.95, 0.09, 1, 0, 0, null, [2, 0.2, 0.35], 0.28]] },
  // Takes: the voices converted from full SuperCollider patches (flute, violin, clarinet, harp) and their kin
  // render each zone two or three times with `var` moving a few settings a little, as the patches' own
  // per-note randomness does, and the sampler alternates them; `human` adds up to a cent and 5% of level.
  // Options, for the parts that ask for them (the lab's roles name them per style; other banks play strings):
  // Mild und Leise pad (program 89): the mildFM pair as two voices a few cents apart (the chord patch detunes
  // each chord tone), modulator near 2:1, index 2.7 in its terms (depth over ratio = 1.34 here) swelling ahead
  // of the level and settling at 0.55 of it, its bandpass at 1.6x the note with 0.15 dry, lowpass 4200 Hz.
  // The 2 s swell is 0.35 s so it follows chord changes.
  // Organ (program 19): yoshiSoftKey as played in the organ example (idxA 0.85, idxB 0.5, attack 0.12): a
  // feedback 1:1 stack and a brighter 2:1 stack at 2.003x, 4.9 Hz vibrato, lowpass 6x the note + 1200 Hz.
  // Its 1.6 s release is 0.8 s; the example's G2 choir bed is a separate held drone, not part of the voice.
  // The four pad instruments (pad, organ, drawbar, horn) are 25% louder than first set, by ear (Casey).
  _extra: [{ id: 'pad', program: 89, lo: 40, hi: 80, like: 'violin', gain: 1, def: { t: 'f', sus: 1, pre: 19200, vib: [0, 11], lp: 4200, eq: [['b', 1.6, 1.11, 0.15, 1]], env: [0.35, 0.4, 0.85, 0.8], ops: [[cents(-5), 2.01, 1.34, 0.74, 0.35, 1, 0], [cents(4), 2.0, 1.2, 0.68, 0.35, 0.8, 0]] } },
    // Vibraphone (program 11): the classic FM vibes, a 1:4 pair whose index dies in the first tenth of a second,
    // a soft 1:1 body, the bar's 4x and 10x modes as a mallet click, the motor's tremolo, a long ring. The
    // tremolo is 45% deep at 5.6 Hz (Casey asked for some; at the first 18% and 5.2 Hz it did not read).
    // It also takes the plucked accompaniments the guitar had (Casey: it sounds like one, at a twentieth of the
    // size; the fmAcousticGuitar conversion was removed), so its range reaches down to E2.
    { id: 'vibraphone', program: 11, lo: 40, hi: 84, like: 'harp', gain: 0.9, def: { t: 'f', dk: 0.4, len: 3.5, lp: 6000, trem: [0.45, 5.6], env: [0.001, 0, 1, 0.5],
      ops: [[1, 4, 1.1, 0.12, 0.06, 1, 9], [1, 1, 0.3, 0, 0.05, 0.4, 13], [4, 1, 0.5, 0, 0.03, 0.12, 40], [10, 1, 0, 0, 0.1, 0.04, 70]] } },
    // Guitar (program 25): the vibraphone's recipe with the motor off, stored as a reference to it (`base`) and
    // the one setting that differs, not as a second copy.
    { id: 'guitar', program: 25, lo: 40, hi: 84, like: 'harp', gain: 0.9, def: { base: 'vibraphone', trem: 0 } },
    // Upright bass, plucked (program 32), built in the manner of the harp: the main string (1:1, its index bright
    // at the pluck, falling fast and then slowly), a shorter octave body, a quiet 2:1 layer for the hollow growl
    // of a low string, and a plain fundamental for weight; all through a pluck-position comb (0.16 of the
    // string); then, outside the comb, the finger's thump (a fixed low FM burst) and the string's click on the
    // fingerboard. Five fixed body bands (the air and top-plate modes at 65 and 115 Hz, a box resonance at
    // 240, a dip at 800, a little presence at 2.2 kHz) and a lowpass that follows the note. Low notes ring
    // longer than high ones; a note is damped when it is let go (release 0.12 s). Three takes, the pluck
    // position and brightness a little different in each. One recipe for every register.
    { id: 'upright', program: 32, lo: 28, hi: 60, like: 'cello', gain: 1, def: { t: 'f', takes: 3, human: 0.6, var: { comb: 0.02, index: 0.08 }, dk: 0.4, len: 2.5, comb: 0.16, lp: 2200, lpk: 6,
      eq: [['p', 65, 2, 2.5], ['p', 115, 2, 3], ['p', 240, 1.5, 2], ['p', 800, 1, -3], ['p', 2200, 1.5, 1.5]], env: [0.002, 0, 1, 0.12],
      ops: [[1, 1, 2.8, 1.0, 0.06, 1, 31, 0, null, null, 0, [0.3, 0.7], 0.003], [2, 1, 1.6, 0.3, 0.05, 0.3, 55, 0, null, null, 0, [0.05, 0.3], 0.002], [1, 2, 0.6, 0.4, 0.1, 0.2, 22, 0, null, null, 0, [0.15, 1], 0.012],
        [1, 1, 0, 0, 0.1, 0.35, 24], [-180, -95, 2, 0, 0.012, 0.25, 900, 0, null, null, 0, null, 0.001, 1], [-1800, -2630, 1.5, 0, 0.004, 0.05, 3000, 0, null, null, 0, null, 0.0005, 1]] } },
    // Lately Bass (program 38): sqpLatelyBass from the Kankyo demo (TX81Z): a feedback modulator an octave below
    // driving the note and, more lightly, its octave; index 3.2 gone in a few hundredths of a second; lowpass
    // 2800 Hz. Its envelope drops to a tenth; here it settles at 0.3, and the level is raised 9 dB, so a held bass note
    // carries as the other bass does. No clip stage.
    // Its attack is 12 ms, not 1, and the index falls in 25 ms, not 12: as written every note began with a spike
    // 2-6 ms in, a click on each one at speed (Casey heard it in Punk Run); the bite now outlasts the attack.
    { id: 'latelybass', program: 38, lo: 28, hi: 64, like: 'cello', gain: 1, def: { t: 'f', sus: 1, pre: 3200, vib: [0, 11], lp: 2800, trim: 9, env: [0.012, 0.12, 0.3, 0.22], ops: [[1, 0.5, 3.2, 0, 0.025, 1, 0, 0.7], [2, 0.5, 0.96, 0, 0.025, 0.2, 0, 0.7]] } },
    // (3 dB up, 2026-11-16, Casey: level with the flute, which it sat 3 dB under, K-weighted.)
    // Ocarina (program 79): the flute's machinery with less in it: nearly a sine, hollow, a narrow band of air
    // on the octave. (A recorder and a whistle were built the same way, programs 74 and 78; of the three this is
    // the smallest, and Casey kept one: the whistle sounded like the flute.)
    { id: 'ocarina', program: 79, lo: 52, hi: 88, like: 'flute', gain: 1, def: { t: 'f', sus: 1, trim: 3, takes: 2, human: 1, var: { index: 0.06, vibDepth: 0.2, vibDelay: 0.2, air: 2 }, pre: 23360, vib: [10, 10, 0.25, 0.4], vibAmp: 0.08, drift: 2, scoop: [5, 0.03], lpk: 8, lpo: 2000, env: [0.04, 0, 1, 0.14],
      air: { bands: [[0, 2, 0.1, 0.8, 500, 8000], [1500, 0, 0.9, 0.3]], gain: 0.05, vib: 0.15, puff: [1800, 0.9, 0.015, 0, 0.04] }, ops: [[1, 1, 0.55, 0.5, 0.08, 1, 0, 0, null, [2, 0.12, 0.3], 0.2]] } }, // brighter, by ear (Casey): the indices were 0.15 and 0.03, the lowpass 5x the note + 1200 Hz
    // Drawbar organ (program 16): pure sines at the 16', 5 1/3', 8', 4' and 2 2/3' footages (the 88 8000 000 jazz
    // setting with a little above it), a key click, and a fast rotary speaker as vibrato that also moves the level.
    { id: 'drawbar', program: 16, lo: 36, hi: 84, like: 'violin', gain: 1, def: { t: 'f', sus: 1, pre: 1600, vib: [6, 13], vibAmp: 0.08, lp: 5000, env: [0.005, 0, 1, 0.06],
      air: { bands: [[3000, 0, 1, 0.001]], gain: 0, puff: [2500, 1.2, 0.05, 0, 0.004] }, ops: [[0.5, 1, 0.04, 0.04, 0.1, 0.9, 0], [1.5, 1, 0, 0, 0.1, 0.7, 0], [1, 1, 0.04, 0.04, 0.1, 1, 0], [2, 1, 0, 0, 0.1, 0.35, 0], [3, 1, 0, 0, 0.1, 0.15, 0]] } },
    // French horn (program 60): two players a few cents apart; the index opens with the note as brass does
    // (0.5 rising to 1.7), a little feedback, a dark lowpass that follows the note, a body peak at 450 Hz.
    { id: 'horn', program: 60, lo: 40, hi: 76, like: 'violin', gain: 1.125, def: { t: 'f', sus: 1, pre: 22400, vib: [3, 10, 0.4, 0.3], vibAmp: 0.03, vibIdx: 0.05, drift: 1, lpk: 2.5, lpo: 800, eq: [['p', 450, 1.5, 3]], env: [0.06, 0, 1, 0.2],
      ops: [[1, 1, 0.5, 1.7, 0.06, 1, 0, 0.3], [cents(2.5), 1, 0.4, 1.4, 0.07, 0.3, 0, 0.3]] } },
    // The lead violin (program 40): the same fm-violin as one player (17 cents of vibrato) and a quiet second, the
    // softer top and level the lead had (11 dB under the strings), stored as a reference to the strings.
    { id: 'violin-lead', program: 40, lo: 40, hi: 84, like: 'violin', gain: 1, def: { base: 'violin', trim: -11.04, fmv: [1.7, 2.2, 0.1], pre: 19200, vib: [0, 11, 0.25, 0.3], section: [[0, 1, 17, 11, 0, 5, 3], [4, 0.18, 12, 10, 2.5, 4, 4]], rvib: [4, [29, 37, 43]], lp: 6500,
      eq: [['p', 275, 4, 3.5], ['p', 460, 5, 4], ['p', 550, 5, 3.5], ['p', 700, 2, -2.5], ['p', 1000, 3, 2.5], ['p', 1300, 3, 1.5], ['p', 1700, 2, -3], ['p', 2500, 1.5, 2.5], ['p', 3300, 3, 0.5], ['s', 4500, 1, -9]] } },
    { id: 'organ', program: 19, lo: 36, hi: 84, like: 'violin', gain: 1, def: { t: 'f', sus: 1, pre: 3200, vib: [7, 10], lpk: 6, lpo: 1200, env: [0.12, 0.4, 0.55, 0.8], ops: [[1, 1, 0.85, 0.85, 0.1, 0.7, 0, 0.15], [2.003, 2, 0.5, 0.5, 0.1, 0.35, 0]] } },
    // Oboe (program 68): a 1:1 FM reed (feedback for the buzz, a 2:1 parallel modulator for the even harmonics)
    // through the oboe's fixed formants: a weak fundamental in the low register (low shelf), the nasal formant
    // near 1.1 kHz, a second near 2.9 kHz, a dark top. Tongued: brighter for the first 40 ms, a puff and a small
    // scoop; vibrato after 0.25 s that also moves level and brightness (an oboe's vibrato is mostly level); slurs.
    // Measured (loop, H1..H8 dB): Bb3 -14 -6 -1 0 0 -7 -12 -16; G4 -12 -10 0 -7 -12 -15 -17 -21; E6 near a sine.
    // 4.5 dB down (Casey: way too loud, so reedy it should sit under the flute): 3 dB under the flute, K-weighted.
    { id: 'oboe', program: 68, lo: 56, hi: 88, like: 'clarinet', gain: 1, def: { t: 'f', sus: 1, slur: 1, trim: -4.5, takes: 2, human: 1, var: { index: 0.06, vibDepth: 0.2, vibDelay: 0.2, air: 2 }, pre: 19200,
      vib: [12, 10, 0.25, 0.35], vibAmp: 0.1, vibIdx: 0.08, drift: 1.2, scoop: [10, 0.02], lpk: 7, lpo: 2200, eq: [['l', 300, 1, -8], ['p', 1150, 1.8, 8], ['p', 2900, 2.2, 4], ['s', 5200, 1, -9]], env: [0.022, 0, 1, 0.1],
      air: { bands: [[2700, 0, 0.6, 0.5], [0, 3, 0.15, 0.25, 600, 9000]], gain: 0.018, vib: 0.1, puff: [1900, 0.9, 0.04, 0, 0.012] },
      ops: [[1, 1, 3.0, 2.2, 0.04, 1, 0, 0.9, null, [2, 0.35, 0.4], 0.15]] } },
    // Bassoon (program 70): the oboe's reed as a reference to it (`base`), darker: formants near 480 Hz and 1.2 kHz,
    // a weak fundamental at the bottom, little above 3 kHz; slower, narrower vibrato (its delay and fade inside the
    // attack, or the attack would not meet the loop). Measured (loop, H1..H8 dB): Bb1 -19 -8 -2 -1 -1 -1 0 0;
    // D3 -18 -8 0 -4 -8 -12 -14 -17; C5 0 -8 -8 -17 -22 -25 -29 -34.
    { id: 'bassoon', program: 70, lo: 34, hi: 72, like: 'clarinet', gain: 1, def: { base: 'oboe', trim: 0, vib: [8, 9, 0.25, 0.35], vibAmp: 0.07, vibIdx: 0.06, drift: 1, scoop: [8, 0.025], lpk: 6, lpo: 1100,
      eq: [['l', 140, 1, -7], ['p', 480, 1.4, 8], ['p', 1200, 2, 4], ['s', 3000, 1, -10]], env: [0.03, 0, 1, 0.12],
      air: { bands: [[1400, 0, 0.6, 0.5], [0, 3, 0.15, 0.2, 300, 6000]], gain: 0.016, vib: 0.08, puff: [1200, 0.9, 0.035, 0, 0.014] } } },
    // Trumpet (program 56): Dexter Morrill's FM trumpet (1977): the index rises with the attack (brightness follows
    // loudness, Risset's rule for brass), formant carriers near 1.4 and 2.6 kHz, a start 45 cents flat that slides up,
    // vibrato after 0.25 s, a fast random-sounding vibrato. Index and feedback found by a search against a trumpet's
    // spectrum at G3 and C5. Measured (loop, H1..H8 dB): G3 -1 -10 -8 -6 -7 0 -4 -5; C5 -4 0 -12 -11 -16 -16 -21 -26.
    // 20% down (-1.94 dB; Casey, by ear). The trombones, a reference to it, state trim 0 to keep their level.
    { id: 'trumpet', program: 56, lo: 52, hi: 84, like: 'flute', gain: 1, def: { t: 'f', sus: 1, trim: -1.94, pre: 16000, vib: [11, 14, 0.25, 0.2], vibAmp: 0.04, drift: 1, scoop: [45, 0.03], lpk: 9, lpo: 2000, env: [0.035, 0, 1, 0.12],
      section: [[0, 1, 0, 1, 0, 4, 3]], rvib: [2, [31, 41]], ops: [[1, 1, 0.5, 2.6, 0.06, 1, 0, 0.8]], form: { f: [1400, 2600], db: [-4, -14], idx: [1.8, 1.8], rise: 0.25, tau: 0.06 },
      eq: [['p', 1300, 1.2, 3], ['s', 4500, 1, -6]], air: { bands: [[1500, 0, 0.8, 0.3]], gain: 0.005, puff: [1500, 0.8, 0.05, 0, 0.01] } } },
    // Trombone section (program 57): the trumpet as a reference (`base`), three players, formants near 580 Hz and 1.2 kHz,
    // a darker lowpass, less vibrato, a slower slide in. Measured (loop, H1..H8 dB): C3 -6 -9 -1 0 -4 -8 -13 -13.
    { id: 'trombone', program: 57, lo: 40, hi: 72, like: 'violin', gain: 1, def: { base: 'trumpet', trim: 0, vib: [6, 11, 0.3, 0.2], scoop: [35, 0.04], lpk: 7, lpo: 900,
      section: [[0, 1, 6, 11, 0, 4, 3], [-6, 0.85, 7, 12, 2.2, 4, 4], [5, 0.8, 5, 10, 4.1, 5, 2]], form: { f: [580, 1200], db: [-3, -10], idx: [1.6, 1.6], rise: 0.25, tau: 0.07 }, eq: [['p', 550, 1.2, 3], ['s', 3000, 1, -8]] } },
    // Bowed cello (program 43): feedback FM (the modulator on itself, towards a sawtooth: a bowed string's -6 dB an
    // octave), index opening with the bow, a quiet second player, bow friction, the cello's body (air near 100 Hz,
    // wood near 210 and 420, a hollow near 650, a bridge hill near 2.2 kHz). Measured (loop, H1..H8 dB): C2 0 -3 -5
    // -10 -12 -13 -15 -19.
    { id: 'bowed-cello', program: 43, lo: 36, hi: 72, like: 'violin', gain: 1, def: { t: 'f', sus: 1, trim: -4, pre: 19200, vib: [16, 11, 0.25, 0.35], vibAmp: 0.07, vibIdx: 0.08, drift: 1.2, scoop: [6, 0.03], lp: 6000, env: [0.09, 0, 1, 0.3],
      section: [[0, 1, 0, 11, 0, 3, 3], [4, 0.22, 6, 10, 1.7, 3, 4]], ops: [[1, 1, 0.6, 1.6, 0.08, 1, 0, 1.1, null, null, 0.2]],
      eq: [['p', 100, 2, 3], ['p', 210, 3, 4], ['p', 420, 3, 3], ['p', 650, 2, -2], ['p', 1200, 2, 1.5], ['p', 2200, 1.5, 2], ['s', 3500, 1, -9]],
      air: { pre: 1, bands: [[0, 3.5, 0.65, 1, 400, 4000, 1], [2000, 0, 1, 0.16, 0, 14000, 2]], gain: 0.05, vib: 0.15, puff: [0, 0.65, 0.05, 3.5] } } },
    // Koto (program 107): plucked near the bridge with an ivory pick (bright, a pick click outside the comb), a slide
    // up into the note (engines.js `bend`, 35 cents in 40 ms), a falling index, a paulownia box (260 Hz, 900 Hz, 2.6 kHz).
    { id: 'koto', program: 107, lo: 48, hi: 84, like: 'harp', gain: 0.9, def: { t: 'f', takes: 3, human: 0.6, var: { comb: 0.02, index: 0.08 }, dk: 0.45, len: 2.6, comb: 0.12, bend: [35, 0.04], lpk: 2, lpo: 6000, env: [0.001, 0, 1, 0.35],
      eq: [['p', 260, 1.5, 3], ['p', 900, 1.4, 2], ['p', 2600, 1.5, 3]],
      ops: [[1, 1, 2.6, 0.5, 0.03, 1, 8, 0.25, null, null, 0, [0.25, 0.6], 0.0015], [2, 1, 1.2, 0.15, 0.02, 0.3, 14, 0, null, null, 0, null, 0.001],
        [-2600, -1700, 1.5, 0, 0.004, 0.06, 2500, 0, null, null, 0, null, 0.0004, 1]] } },
    // Kalimba (program 108): a clamped tine, its modes at 1, 6.27 and 17.55 times the note (the upper two gone in
    // a moment), a brief FM flick at the strike, a second tine 4 cents off for the warble, a thumb thud (fixed
    // frequency, outside the note), a wooden box body. Lighter than the vibraphone for arpeggios.
    { id: 'kalimba', program: 108, lo: 48, hi: 88, like: 'harp', gain: 0.9, def: { t: 'f', takes: 3, human: 0.6, var: { index: 0.1 }, dk: 0.35, len: 3.2, lp: 9000, env: [0.001, 0, 1, 0.5],
      eq: [['p', 330, 1.6, 3], ['p', 2400, 1.4, 1.5]],
      ops: [[1, 1, 0.9, 0.04, 0.012, 1, 9, 0, null, null, 0, null, 0.0008], [cents(4), 1, 0.3, 0, 0.01, 0.22, 12, 0, null, null, 0, null, 0.0008],
        [6.27, 1, 0, 0, 0.1, 0.16, 48, 0, null, null, 0, null, 0.0005], [17.55, 1, 0, 0, 0.1, 0.05, 140, 0, null, null, 0, null, 0.0003],
        [-150, -105, 1.2, 0, 0.01, 0.1, 520, 0, null, null, 0, null, 0.002, 1]] } },
    // Choir "aah" (program 52): Chowning's FM soprano (1980) as a choir of four (engines.js choirOps): per singer
    // a glottal source (1:1 FM, feedback, purer up the register, plus a plain fundamental) and carriers at the
    // harmonics either side of each formant (F1 600-800, F2 1040-1150, F3 2400-2900 Hz, lower voices to sopranos;
    // F1 rides above the note); each singer detuned a few cents with their own vibrato (16-22 cents, 4.4-5.9 Hz)
    // and a slow random wander, so the section moves instead of beating as one. Aspiration in the formants.
    { id: 'choir', program: 52, lo: 43, hi: 79, like: 'violin', gain: 1, def: { t: 'f', sus: 1, pre: 9600, vib: [0, 11, 0.06, 0.2], lp: 6500, env: [0.13, 0, 1, 0.45],
      eq: [['p', 2800, 1.5, 2], ['s', 4200, 1, -6]], air: { bands: [[750, 0, 0.5, 0.6], [1150, 0, 0.4, 0.4], [2800, 0, 0.3, 0.3]], gain: 0.012 },
      ops: [[1, 1, 0.8, 2.1, 0.12, 0.7, 0, 0.75, null, null, 0.4], [1, 1, 0, 0, 0.1, 0.22, 0]],
      choir: { range: [45, 79], f: [[600, 1040, 2400], [800, 1150, 2900]], db: [4, -2, -13], idx: [0.6, 0.75, 0.9],
        singers: [[0, 1, 20, 11, 0, 6, 3], [-8, 0.85, 18, 10, 2.1, 7, 4], [9, 0.8, 22, 12, 4.4, 5, 2], [3, 0.7, 16, 9, 1.3, 8, 5]] } } }],
  // Dry 808 Hat (closed and, longer, open) and Bright Snare, with the demo's preset values worked out (the
  // snare 30% and then 10% quieter than first set, by ear)
  _drums: [['hat', 42, 0.22, { t: 'hh', len: 0.12, hp: 7888, metal: [4760, 5412, 6064, 6716, 7368], atk: 0.0006, tau: 0.0128, peak: 16000 }],
    ['open-hat', 46, 0.2, { t: 'hh', len: 0.5, hp: 7888, metal: [4760, 5412, 6064, 6716, 7368], atk: 0.0006, tau: 0.09, peak: 16000 }],
    ['snare', 38, 0.214, { t: 'sn', len: 0.42, body: 180, band: 1852, rq: 0.131, noise: 3, rattle: 116, snap: 0.033, atk: 0.0039, tau: 0.054, peak: 20000 }],
    // Kick: danceKick from the Kankyo demo at its defaults (a 55 Hz sine dropping from 13 times that in a few
    // milliseconds, a sub an octave down, a knock and a click). Toms: the same body, tuned per key from the
    // low floor tom to the high tom, with a gentler drop and a longer ring. The crash stays on the chip kit.
    ['kick', 36, 0.4, { t: 'kd', f: 55, sweep: 12, st: 0.004, tau: 0.056, sub: 0.24, knock: [330, 0.35, 0.34], click: [5057, 0.11], len: 0.5, peak: 24000 }],
    ...[[41, 82], [43, 98], [45, 123], [47, 147], [48, 165], [50, 196]].map(([key, f]) => ['tom-' + key, key, 0.36, { t: 'kd', f, sweep: 0.8, st: 0.03, tau: 0.13, knock: [f * 3, 0.5, 0.2], click: [3000, 0.04], len: 0.6, peak: 20000 }])],
};
// a sustained stack's operators start out of step; pick the spread whose level is steadiest over a note's
// first 0.7 s (in the middle of its range), so no note starts in a beat's trough
if (stringAt.fit) console.error('string fit, rms error per zone: ' + stringAt.fit.join('; '));
for (const [id, d] of [...Object.entries(KANKYO).filter(([k]) => k[0] !== '_'), ...KANKYO._extra.map((x) => [x.id, x.def])]) if (d.sus && !d.align && (d.ops ?? d.zones?.[0].ops ?? []).length > 1) {
  let best = null;
  for (let ps = 0; ps < 24; ps++) { const y = zone({ ...d, ps, lvl: 3000 }, 60, d.zones ? d.zones.length >> 1 : 0).make(), e = []; for (let t = 0; t < 14; t++) { let q = 0; for (let i = 0; i < 1600; i++) q += y[d.pre + t * 1600 + i] ** 2; e.push(10 * Math.log10(q + 1e-9)); } const swing = Math.max(...e) - Math.min(...e); if (!best || swing < best[1]) best = [ps, swing]; }
  d.ps = best[0]; console.error(id, 'operator spread', best[0], 'level swing over 0.7 s', best[1].toFixed(1), 'dB');
}
const BANKS = {
  resynth: Object.fromEntries(INST.map((i) => [i.id, described[i.id]])),
  hybrid: Object.fromEntries(INST.map((i) => [i.id, { t: 'h', atk: attacks[i.id].atk, in: { ...described[i.id], chiff: null }, ...(i.id === 'glockenspiel' ? { soft: 0.25 } : {}) }])),
  physical: PHYSICAL, fm: FM, kankyo: KANKYO,
};

// ---- zones every four semitones; the models' tuning and loops are found here by running them
const roots4 = (i, lo = i.lo) => { const r = []; for (let m = lo; m <= i.hi; m += 4) r.push(m); return r; };
const report = {};
mkdirSync(outDir, { recursive: true });
const empty = (await build({ stdin: { contents: `import {attach,createSampler} from '../runtime.js';window.SnesBank={attach,createSampler};`, resolveDir: here, loader: 'js' }, bundle: true, minify: true, format: 'iife', target: 'es2020', write: false })).outputFiles[0].text.length;
const workerText = (await build({ stdin: { contents: `import {zone} from './engines.js';self.onmessage=(e)=>{const [d,m,k,t]=e.data,y=zone(d,m,k,t<0?undefined:t).make();self.postMessage(y,[y.buffer])}`, resolveDir: here, loader: 'js' }, bundle: true, minify: true, format: 'iife', target: 'es2020', write: false })).outputFiles[0].text.trim();
for (const [name, defs] of Object.entries(BANKS)) {
  const data = [], checks = [];
  const extra = (defs._extra ?? []).map((x) => { const like = INST.find((i) => i.id === x.like); return { ...like, id: x.id, program: x.program, lo: x.lo, hi: x.hi, volume: +(like.volume * x.gain).toFixed(3), def: x.def }; });
  // a definition's `trim` is dB against the sampled instrument's level
  // a definition may be another's with a few settings changed: `base` names it, and it is stored as only the
  // changes (the page fills in the rest), so a variant costs a few dozen bytes
  for (const i of [...INST, ...extra]) {
    const raw = i.def ?? defs[i.id], def0 = raw.base ? { ...(defs[raw.base] ?? defs._extra.find((x) => x.id === raw.base).def), ...raw } : raw, d = { ...def0, lvl: Math.round(i.lvl * 10 ** ((def0.trim ?? 0) / 20)) }, inner = d.t === 'h' ? (d.in = { ...d.in, lvl: d.lvl }) : d, lo = d.lo ?? i.lo, ms = roots4(i, lo);
    if (inner.t === 'k') inner.tune = ms.map((m) => +(1200 * Math.log2(hz(m) / pitchNear(zone({ ...inner, tune: null }, m, 0).make(), RATE, 0.08, hz(m)).f)).toFixed(1));
    if ('cub'.includes(inner.t)) {
      inner.loops = []; inner.tune = [];
      if (inner.t === 'u') inner.zp = ms.map((m) => [inner.p, 1.0, 0.9, 1.35, 0.8, 1.5, 0.7].find((p) => { const c = pitchOver(zone({ ...inner, zp: null, p }, m, 0).raw(Math.round(2.3 * RATE)), RATE, 1.0, hz(m)); return c.r > 0.9 && c.high < 0.8; }) ?? inner.p);
      ms.forEach((m, k) => { const raw = Float64Array.from(zone(inner, m, k).raw(Math.round(2.3 * RATE))); let pk = 0; for (const v of raw) pk = Math.max(pk, Math.abs(v)); const x = raw.map((v) => v / (pk || 1));
        const L = findLoop(x, RATE, 0.9, 2.28, 1.1, 0.03), f = pitchOver(x, RATE, 1.0, hz(m)).f; inner.loops.push([L.start, L.end]); inner.tune.push(+(1200 * Math.log2(hz(m) / f)).toFixed(1)); });
    }
    ms.forEach((m, k) => { const z = zone(d, m, k), y = z.make(); let s = 0, bad = 0; const a = z.loopStart ?? 0, b = z.loopStart === null ? Math.min(y.length, 3200) : y.length; for (let j = a; j < b; j++) { s += y[j] * y[j]; if (!Number.isFinite(y[j])) bad++; }
      const pt = z.loopStart === null ? (inner.t === 'k' ? pitchNear(y, RATE, 0.08, hz(m) * 2 ** (-z.tune / 1200)) : null) : pitchOver(Float32Array.from({ length: z.loopStart + 2 * RATE }, (_, j) => y[j < y.length ? j : z.loopStart + (j - y.length) % (y.length - z.loopStart)]), RATE, z.loopStart / RATE + 0.1, hz(m) * 2 ** (-z.tune / 1200)), f = pt?.f;
      checks.push({ id: i.id, m, rms: Math.round(Math.sqrt(s / (b - a))), lvl: i.lvl, bad, cents: f ? +(1200 * Math.log2(f / hz(m)) + z.tune).toFixed(1) : null, r: pt ? +pt.r.toFixed(2) : null, high: pt ? +pt.high.toFixed(2) : null, tune: +z.tune.toFixed(1), seconds: +(y.length / RATE).toFixed(2) }); });
    data.push([i.id, i.program, lo, i.hi, i.volume, d.env ?? [i.env.attack, i.env.decay, i.env.sustain, i.env.release], raw.base ? { ...raw, lvl: d.lvl } : { ...d, env: undefined }]);
  }
  // The page renders zones in background workers (the engine again, as a worker script), a few at once and
  // off the main thread: first the zones a track is about to play (`need`, which resolves when they are
  // ready), then the rest of the first takes; a zone's other takes wait until its first note. A zone asked
  // for before it is ready is rendered on the spot. Without workers the same queue runs on a timer.
  const contents = `import {attach,createSampler} from '../runtime.js'; import {zone,RATE} from './engines.js';
const bank={format:'BSBRR1',name:${JSON.stringify(name)},samples:[],instruments:[]},jobs=[],W=${JSON.stringify(workerText)};
const finish=(j,y)=>{if(j.state===2)return;j.state=2;if(y){j.s.pcm=y}j.s.ready=true;j.wait.splice(0).forEach((f)=>f())};
const add=(prog,lo,hi,take,z,d,m,k,pri)=>{const s={rate:RATE,loopStart:z.loopStart,smoothing:false,...(take>0?{ready:false}:{}),render:()=>{if(!s.pcm){s.pcm=z.make();finish(j)}const p=s.pcm;s.pcm=null;if(take<=0)for(const o of jobs)if(o.prog===prog&&o.lo===lo&&o.take>0&&o.state===0&&o.pri<2){o.pri=2}pump();return p}},j={s,a:[d,m,k,take],prog,lo,hi,take,pri,state:0,wait:[]};jobs.push(j);return bank.samples.push(s)-1};
const rows=${safeJson(data)},byId=Object.fromEntries(rows.map((r)=>[r[0],r[6]]));
rows.forEach(([id,program,lo,hi,volume,[attack,decay,sustain,release],d])=>{if(d.base)d={...byId[d.base],...d};for(let m=lo,k=0;m<=hi;m+=4,k++){const T=d.takes||1,idx=[],keys=[k?m-1:0,m+4>hi?127:m+2];let first;
for(let t=0;t<T;t++){const z=zone(d,m,k,T>1?t:undefined);first??=z;idx.push(add(program,keys[0],keys[1],T>1?t:-1,z,d,m,k,t?-1:1))}
bank.instruments.push({id:id+'-'+m,program,sample:idx[0],...(T>1?{takes:idx}:{}),...(d.human?{human:d.human}:{}),rootNote:m,tuneCents:first.tune,volume,envelope:{attack,decay,sustain,release},keys,...(d.slur?{slur:1}:{}),credit:{author:'-',license:'-',source:'-'}})}});
${safeJson(defs._drums ?? [])}.forEach(([id,key,volume,d])=>{const z=zone(d,60,0);bank.instruments.push({id,drum:key,sample:add(-1,key,key,-1,z,d,60,0,6),rootNote:key,tuneCents:0,volume,envelope:{attack:0,decay:0,sustain:1,release:0.3},credit:{author:'-',license:'-',source:'-'}})});
let pool=[],timer=0;
try{const url=URL.createObjectURL(new Blob([W],{type:'text/javascript'}));for(let i=Math.max(1,Math.min(6,(navigator.hardwareConcurrency||4)-1));i--;){const w=new Worker(url);w.onmessage=(e)=>{const j=w.job;w.job=null;finish(j,j.state===2?null:e.data);pump()};w.onerror=()=>{const j=w.job;w.job=null;pool=pool.filter((x)=>x!==w);if(j&&j.state===1)j.state=0;pump()};pool.push(w)}}catch(e){pool=[]}
function next(){let b=null;for(const j of jobs)if(j.state===0&&j.pri>0&&(!b||j.pri>b.pri))b=j;return b}
function pump(){if(pool.length){for(const w of pool){if(w.job)continue;const j=next();if(!j)return;j.state=1;w.job=j;w.postMessage(j.a)}}else if(!timer){timer=setTimeout(()=>{timer=0;const j=next();if(j){j.s.pcm=zone(j.a[0],j.a[1],j.a[2],j.a[3]<0?undefined:j.a[3]).make();finish(j);pump()}},20)}}
const need=(list)=>{const ps=[];for(const [prog,note] of list)for(const j of jobs)if(j.prog===prog&&j.take<=0&&note>=j.lo&&note<=j.hi&&j.state!==2){if(j.state===0)j.pri=5;ps.push(new Promise((f)=>j.wait.push(f)))}pump();const p=Promise.all(ps);p.pending=ps.length>0;return p};
setTimeout(pump,0);
window.SnesBank={bank,need,attach:(s,o)=>attach(s,bank,o),createSampler:(a,o)=>createSampler(a,bank,o)};`;
  const text = (await build({ stdin: { contents, resolveDir: here, loader: 'js' }, bundle: true, minify: true, format: 'iife', target: 'es2020', write: false })).outputFiles[0].text.trim();
  writeFileSync(resolve(outDir, `${name}.min.js`), text + '\n'); writeFileSync(resolve(outDir, `${name}.checks.json`), JSON.stringify(checks));
  const bad = checks.filter((c) => c.bad || !c.rms || (c.cents !== null && (Math.abs(c.cents) > 5 || c.r < 0.7 || c.high > 0.93)));
  const perInstrument = Object.fromEntries([...data.map((row) => [row[0], { bytes: Buffer.byteLength(safeJson(row)), zones: Math.floor((row[3] - row[2]) / 4) + 1, takes: row[6].takes ?? 1 }]), ...(defs._drums ?? []).map((row) => [row[0], { bytes: Buffer.byteLength(safeJson(row)), zones: 1, takes: 1 }])]);
  report[name] = { perInstrument, workerBytes: workerText.length, samplerOnlyBytes: empty, scriptBytes: text.length, zones: checks.length, descriptionBytes: Buffer.byteLength(safeJson(data)), scriptBytesBeyondSampler: text.length - empty, attackBrrBytes: name === 'hybrid' ? Object.values(attacks).reduce((s, a) => s + a.bytes, 0) : 0, offPitchOrSilent: bad.map((c) => `${c.id}-${c.m}: ${c.cents} c, match ${c.r}, higher register ${c.high}, tuned ${c.tune} c`) };
}
console.log(JSON.stringify(report, null, 1));

// One recording of an instrument's notes, played one after another at equal spacing, split into key
// zones for the sample bank. Each note is measured at the pitch it sounds (file and note names are
// not trusted: Logic calls middle C "C3", an octave below the MIDI name), tuned, and cut to a loop in
// its steady tone. The channel is chosen once for the file: the mono sum when left and right agree,
// otherwise the louder side (a widened stereo patch cancels part of its tone when summed).
//
//   node onchain/snes/samples/loot/notes.mjs <recording.aif|wav> --id violin --replace strings --count 7
//        [--zones 60,67,72,79] [--loop 0.4,0.3,0.3,0.25] [--rates 16000,24000,...] [--trim-db 0.7] [--dry]
//
// --count   notes in the recording (equal slices)          --zones  sounding MIDI roots to keep (default all)
// --loop    loop seconds per kept zone (default 0.3)       --rates  sample rate per kept zone (default: the
// --replace the bank instrument (or zone family) replaced           lowest of 16/20/24/28/32 kHz that keeps the
//           in manifest.json and manifest-12k.json                  A-weighted loss under -40 dB)
// --manifest  other manifests (in onchain/snes, comma-separated) to write the zones into, to try a variant
// Writes <id>_<note>_src.wav (the excerpt used, 24-bit mono), <id>.json (the zones) and replaced-<name>.json.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readWav, prepare } from '../../prepare.mjs';
import { encodeBRR, decodeBRR } from '../../brr.js';

const here = new URL('.', import.meta.url), snes = new URL('../../', here);
const NAMES = ['C', 'Cs', 'D', 'Ds', 'E', 'F', 'Fs', 'G', 'Gs', 'A', 'As', 'B'];
export const noteName = (m) => NAMES[m % 12] + (Math.floor(m / 12) - 1);
const db = (v) => 20 * Math.log10(Math.max(v, 1e-12));
const rms = (x, a = 0, b = x.length) => { let s = 0; for (let i = a; i < b; i++) s += x[i] * x[i]; return Math.sqrt(s / Math.max(1, b - a)); };

/** Left, right and their mean as Float64Arrays at the file's rate (ffmpeg reads AIFF, WAV, 24-bit). */
export function readChannels(file) {
  const dir = mkdtempSync(join(tmpdir(), 'notes-'));
  try {
    const out = {};
    for (const [k, pan] of [['L', 'pan=mono|c0=c0'], ['R', 'pan=mono|c0=c1'], ['M', 'pan=mono|c0=0.5*c0+0.5*c1']]) {
      const f = join(dir, k + '.wav');
      try { execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', file, '-af', pan, '-c:a', 'pcm_f32le', f]); } catch (e) { if (k === 'L') throw e; continue; } // a mono file has no c1
      out[k] = readWav(readFileSync(f));
    }
    return { rate: out.L.rate, L: out.L.pcm, R: out.R?.pcm ?? out.L.pcm, M: out.M?.pcm ?? out.L.pcm, mono: !out.R };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

/** The fundamental in Hz of a steady tone: the shortest lag whose autocorrelation is within 10% of the
 *  best (so an octave-high patch reads at the pitch it sounds), refined over about 25 ms of periods. */
export function fundamental(x, rate, at) {
  const N = Math.round(0.06 * rate), s = Math.round(at * rate), lo = Math.floor(rate / 4500), hi = Math.ceil(rate / 55);
  const ac = (L) => { let a = 0, b = 0, c = 0; for (let i = 0; i < N; i++) { a += x[s + i] * x[s + i + L]; b += x[s + i] ** 2; c += x[s + i + L] ** 2; } return a / Math.sqrt(b * c + 1e-30); };
  const r = []; let best = -1;
  for (let L = lo; L <= hi; L++) { r.push(ac(L)); best = Math.max(best, r.at(-1)); }
  let k = r.findIndex((v, i) => v >= 0.9 * best && v >= (r[i - 1] ?? -1) && v >= (r[i + 1] ?? -1));
  const peak = (L) => { const a = ac(L - 1), b = ac(L), c = ac(L + 1), d = a - 2 * b + c; return L + (d ? 0.5 * (a - c) / d : 0); };
  let T = peak(lo + k);
  const K = Math.max(1, Math.round(0.025 * rate / T)); let Lk = Math.round(K * T), bv = -2;
  for (let L = Math.round(K * T) - 2; L <= Math.round(K * T) + 2; L++) { const v = ac(L); if (v > bv) { bv = v; Lk = L; } }
  T = peak(Lk) / K;
  return rate / T;
}

/** Energy above `rate`'s passband, A-weighted, in dB against the whole (what that rate would discard). */
export function lossDb(x, rate, a, b, bankRate) {
  // Goertzel-free: a plain DFT at 1/24-octave spaced bins would miss partials, so sum an FFT-size-free
  // periodogram by decimated autocorrelation is overkill; use a straight radix-2 FFT on 2^16 samples.
  const n = 65536, re = new Float64Array(n), im = new Float64Array(n), s = Math.max(a, Math.min(b - n, a));
  for (let i = 0; i < n; i++) re[i] = (x[s + i] ?? 0) * (0.5 - 0.5 * Math.cos(2 * Math.PI * i / (n - 1)));
  for (let i = 1, j = 0; i < n; i++) { let bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { const t = re[i]; re[i] = re[j]; re[j] = t; } }
  for (let len = 2; len <= n; len <<= 1) { const ang = -2 * Math.PI / len; for (let i = 0; i < n; i += len) for (let k = 0; k < len / 2; k++) { const wr = Math.cos(ang * k), wi = Math.sin(ang * k), p = i + k, q = p + len / 2, xr = re[q] * wr - im[q] * wi, xi = re[q] * wi + im[q] * wr; re[q] = re[p] - xr; im[q] = im[p] - xi; re[p] += xr; im[p] += xi; } }
  let total = 0, lost = 0;
  for (let k = 1; k < n / 2; k++) { const f = k * rate / n, f2 = f * f, w = (12194 ** 2 * f2 * f2) / ((f2 + 20.6 ** 2) * Math.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2)), e = (re[k] ** 2 + im[k] ** 2) * w * w; total += e; if (f > 0.45 * bankRate) lost += e; }
  return 10 * Math.log10(lost / total + 1e-12);
}

/** The steady part of a note, in seconds from the slice start: the longest run of 50 ms frames within
 *  4 dB of the sustained level, pulled in 0.1 s from each end. */
export function steady(x, rate) {
  const h = Math.round(0.05 * rate), e = []; for (let i = 0; i + h <= x.length; i += h) e.push(db(rms(x, i, i + h)));
  const top = [...e].sort((a, b) => b - a), level = top[Math.floor(top.length * 0.35)];
  let best = [0, 0], run = null;
  e.forEach((v, i) => { if (Math.abs(v - level) <= 4) { run ??= i; if (i + 1 - run > best[1] - best[0]) best = [run, i + 1]; } else run = null; });
  return { from: best[0] * 0.05 + 0.1, to: best[1] * 0.05 - 0.1, level };
}

/** A loop of about `seconds` in the steady part of `x` (already at the bank rate): block-aligned ends
 *  whose approach matches in waveform over the crossfade and in level, in the evenest stretch. */
export function findLoop(x, rate, from, to, seconds, crossfade) {
  const cf = Math.round(crossfade * rate), frame = Math.round(0.02 * rate), fe = []; for (let i = 0; i + frame <= x.length; i += frame) fe.push(db(rms(x, i, i + frame)));
  const spread = (a, b) => { let lo = Infinity, hi = -Infinity; for (let i = Math.floor(a / frame); i < Math.floor(b / frame); i++) { lo = Math.min(lo, fe[i]); hi = Math.max(hi, fe[i]); } return hi - lo; };
  const pre = 16 * Math.ceil((cf + 0.002 * rate) / 16), target = seconds * rate; let best = null;
  for (let start = 16 * Math.ceil(Math.max(pre, from * rate) / 16); start + target * 1.12 < to * rate; start += 32)
    for (let len = 16 * Math.ceil(target * 0.88 / 16); len <= target * 1.12; len += 16) {
      const end = start + len; let err = 0, en = 0;
      for (let i = 1; i <= cf; i += 2) { err += (x[start - i] - x[end - i]) ** 2; en += x[start - i] ** 2 + x[end - i] ** 2; }
      const match = err / Math.max(en, 1e-30); if (best && match > best.score) continue;
      const lv = Math.abs(db(rms(x, start - cf, start)) - db(rms(x, end - cf, end)));
      const score = match + lv / 20 + spread(start, end) / 60;
      if (!best || score < best.score) best = { start, end, pre, score, match, levelGap: lv, spread: spread(start, end) };
    }
  if (!best) throw new Error('No room for a loop of that length in the steady part');
  return best;
}

function wav24(pcm, rate) {
  const b = Buffer.alloc(44 + pcm.length * 3);
  b.write('RIFF', 0); b.writeUInt32LE(36 + pcm.length * 3, 4); b.write('WAVEfmt ', 8); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 3, 28); b.writeUInt16LE(3, 32); b.writeUInt16LE(24, 34); b.write('data', 36); b.writeUInt32LE(pcm.length * 3, 40);
  pcm.forEach((v, i) => b.writeIntLE(Math.max(-8388608, Math.min(8388607, Math.round(v * 8388608))), 44 + i * 3, 3));
  return b;
}

/** A zone's level as the player sounds it at its root: one second of the loop after the pre-roll. */
export function zoneLevel(file, opt) {
  const p = prepare(readWav(readFileSync(new URL(file, snes))), opt), d = decodeBRR(encodeBRR(p.pcm, p.loopStart), p.loopStart);
  let s = 0, n = 0; const from = p.loopStart ?? Math.round(0.2 * p.rate);
  for (let i = from; i < from + p.rate && (p.loopStart !== null || i < d.length); i++, n++) { const v = d[i < d.length ? i : p.loopStart + ((i - d.length) % (d.length - p.loopStart))] / 32768; s += v * v; }
  return 10 * Math.log10(s / n);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const args = process.argv.slice(2), file = args.shift(), opt = {};
  for (let i = 0; i < args.length; i++) if (args[i] === '--dry') opt.dry = true; else opt[args[i].replace(/^--/, '')] = args[++i];
  const list = (v) => (v === undefined ? null : String(v).split(',').map(Number));
  if (!file || !opt.id || !opt.replace || !opt.count) { console.error('usage: notes.mjs <recording> --id <name> --replace <bank instrument> --count <notes> [--zones ..] [--loop ..] [--rates ..] [--trim-db ..] [--dry]'); process.exit(2); }
  const src = readChannels(file), count = +opt.count, slice = Math.floor(src.L.length / count), r0 = src.rate;
  // the channel: summing must not cost more than 1.5 dB against the louder side on any note
  const seg = (ch, n) => src[ch].subarray(n * slice, (n + 1) * slice);
  let cancel = 0, louder = 0;
  for (let n = 0; n < count; n++) { const a = Math.round(0.25 * slice), b = Math.round(0.75 * slice), l = db(rms(seg('L', n), a, b)), r = db(rms(seg('R', n), a, b)); cancel = Math.max(cancel, Math.max(l, r) - db(rms(seg('M', n), a, b))); louder += l - r; }
  const channel = opt.channel ?? (src.mono || cancel <= 1.5 ? 'M' : louder >= 0 ? 'L' : 'R');
  console.error(`${basename(file)}: ${count} notes of ${(slice / r0).toFixed(2)} s, ${r0} Hz; channel ${channel} (the mono sum loses up to ${cancel.toFixed(1)} dB)`);
  const notes = [];
  for (let n = 0; n < count; n++) {
    const x = seg(channel, n), st = steady(x, r0), hz = [0.25, 0.5, 0.75].map((f) => fundamental(x, r0, st.from + f * (st.to - st.from))).sort((a, b) => a - b)[1];
    const midi = Math.round(69 + 12 * Math.log2(hz / 440)), cents = 1200 * Math.log2(hz / (440 * 2 ** ((midi - 69) / 12)));
    const a = Math.round(st.from * r0), b = Math.round(st.to * r0), loss = [16000, 20000, 24000, 28000, 32000].map((r) => [r, lossDb(x, r0, a, b, r)]);
    notes.push({ n, x, st, hz, midi, cents, rate: (loss.find(([, l]) => l <= -40) ?? loss.at(-1))[0], loss });
    console.error(`  note ${n + 1}: sounds ${noteName(midi)} (MIDI ${midi}) ${cents >= 0 ? '+' : ''}${cents.toFixed(1)} cents, steady ${st.from.toFixed(2)}-${st.to.toFixed(2)} s at ${st.level.toFixed(1)} dB; lost above the passband: ${loss.map(([r, l]) => `${r / 1000}k ${l.toFixed(0)}`).join(', ')} dB`);
  }
  const keep = (list(opt.zones) ?? notes.map((z) => z.midi)).map((m) => { const z = notes.find((q) => q.midi === m); if (!z) throw new Error(`No note sounds MIDI ${m}`); return z; }).sort((a, b) => a.midi - b.midi);
  const loops = list(opt.loop) ?? [], rates = list(opt.rates) ?? [], CROSSFADE = 0.03;
  const read = (f) => JSON.parse(readFileSync(new URL(f, snes)));
  const family = (i) => i.id === opt.replace || i.id.startsWith(opt.replace + '-') || i.id === opt.id || i.id.startsWith(opt.id + '-');
  const saved = new URL(`replaced-${opt.replace}.json`, here);
  const old = read('manifest.json').instruments.find((i) => i.id === opt.replace && !i.keys) ?? (existsSync(saved) ? JSON.parse(readFileSync(saved)) : null);
  if (!old) throw new Error(`No instrument ${opt.replace} to replace`);
  const ref = zoneLevel(old.file, old), TRIM_DB = +(opt['trim-db'] ?? 0.7), zones = [];
  keep.forEach((z, k) => {
    const rate = rates[k] ?? z.rate, seconds = loops[k] ?? loops.at(-1) ?? 0.3;
    const y = prepare({ pcm: z.x, rate: r0 }, { sampleRate: rate, trimEnd: Math.min(4, z.x.length / r0), gain: 1 });
    const f = Float64Array.from(y.pcm, (v) => v / 32767), L = findLoop(f, rate, z.st.from, z.st.to, seconds, CROSSFADE);
    // the excerpt: 50 ms either side of what the zone plays, starting on a source sample
    const t0 = (L.start - L.pre) / rate, t1 = L.end / rate, a0 = Math.max(0, Math.floor((t0 - 0.05) * r0)), a1 = Math.min(z.x.length, Math.ceil((t1 + 0.05) * r0)), ex = z.x.subarray(a0, a1);
    let pk = 0; for (const v of ex) pk = Math.max(pk, Math.abs(v));
    const name = noteName(z.midi), wavFile = `samples/loot/${opt.id}_${name}_src.wav`, norm = 0.708 / pk;
    if (!opt.dry) writeFileSync(new URL(wavFile, snes), wav24(Float64Array.from(ex, (v) => v * norm), r0));
    const lo = k ? Math.floor((keep[k - 1].midi + z.midi) / 2) + 1 : 0, hi = k < keep.length - 1 ? Math.floor((z.midi + keep[k + 1].midi) / 2) : 127;
    const o = { sampleRate: rate, gain: 1, trimStart: +(t0 - a0 / r0).toFixed(7), trimEnd: +(t1 - a0 / r0).toFixed(7), loopStart: +(L.pre / rate).toFixed(7), loopCrossfade: CROSSFADE, fadeIn: 0.002 };
    const zone = { id: `${opt.id}-${name}`, file: wavFile, program: old.program, keys: [lo, hi], rootNote: z.midi, ...o, smoothing: false, tuneCents: +(-z.cents).toFixed(1), volume: 0, envelope: old.envelope,
      credit: { author: 'Casey Wescott', license: 'Own work', source: `LootSampleBank/${basename(file)}` } };
    if (!opt.dry) zone.volume = +Math.min(1, old.volume * 10 ** ((ref - zoneLevel(wavFile, o) - TRIM_DB) / 20)).toFixed(3);
    zones.push(zone);
    console.error(`  ${zone.id}: keys ${lo}-${hi}, ${rate} Hz, loop ${(L.start / rate).toFixed(3)}-${(L.end / rate).toFixed(3)} s of the note (${((L.end - L.start) / rate).toFixed(3)} s), mismatch ${(10 * Math.log10(L.match + 1e-12)).toFixed(0)} dB, level gap ${L.levelGap.toFixed(2)} dB, level spread in the loop ${L.spread.toFixed(1)} dB, ${(L.end - L.start + L.pre) / 16 * 9} bytes`);
  });
  if (!opt.dry) {
    writeFileSync(saved, JSON.stringify(old, null, 2) + '\n');
    writeFileSync(new URL(`${opt.id}.json`, here), JSON.stringify(zones, null, 2) + '\n');
    for (const f of opt.manifest ? opt.manifest.split(',') : ['manifest.json', 'manifest-12k.json']) {
      const m = read(f), at = m.instruments.findIndex(family); if (at < 0) throw new Error(`${f} has no ${opt.replace}`);
      m.instruments = m.instruments.filter((i) => !family(i)); m.instruments.splice(at, 0, ...zones);
      writeFileSync(new URL(f, snes), JSON.stringify(m, null, 2) + '\n');
    }
  }
  console.log(JSON.stringify(zones.map((z) => ({ id: z.id, keys: z.keys, rootNote: z.rootNote, rate: z.sampleRate, tuneCents: z.tuneCents, volume: z.volume })), null, 1));
}

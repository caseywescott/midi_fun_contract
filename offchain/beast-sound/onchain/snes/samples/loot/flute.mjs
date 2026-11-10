// Casey's flute (new_samples_loot_survivor/Classic Electric Pianoflute_c4/c5.aif, as 16-bit WAV): two key
// zones, each its attack and a loop in the steady part at 16 kHz. The notes carry a ~7 Hz vibrato, so a
// loop is a whole number of vibrato cycles with the same pitch and direction at both ends, as well as
// matching waveform and level.
import { readFileSync } from 'node:fs';
import { readWav, prepare } from '../../prepare.mjs';
const here = new URL('.', import.meta.url);
/** Pitch in cents from `hz0` every 5 ms (autocorrelation with parabolic refinement). */
function pitchTrack(x, r, hz0) {
  const T0 = r / hz0, N = Math.round(3 * T0), out = [];
  for (let s = 0; s + N + T0 * 1.2 < x.length; s += Math.round(0.005 * r)) {
    const lo = Math.floor(T0 * 0.85), cs = [];
    for (let L = lo; L <= Math.ceil(T0 * 1.15); L++) { let a = 0, b = 0, c = 0; for (let i = 0; i < N; i++) { a += x[s + i] * x[s + i + L]; b += x[s + i] ** 2; c += x[s + i + L] ** 2; } cs.push(a / Math.sqrt(b * c + 1e-12)); }
    const k = cs.indexOf(Math.max(...cs)), off = k > 0 && k < cs.length - 1 ? 0.5 * (cs[k - 1] - cs[k + 1]) / (cs[k - 1] - 2 * cs[k] + cs[k + 1]) : 0;
    out.push(1200 * Math.log2(r / (lo + k + off) / hz0));
  }
  return out;
}
export function findLoop(file, gain, hz0, vibratoHz) {
  const w = readWav(readFileSync(new URL(file, here))), rate = 16000, P = pitchTrack(w.pcm, w.rate, hz0);
  const pitch = (t) => P[Math.min(P.length - 1, Math.round(t / 0.005))], slope = (t) => pitch(t + 0.01) - pitch(t - 0.01);
  const x = prepare(w, { sampleRate: rate, trimEnd: 0.9, gain }).pcm, env = (i, n = 160) => { let s = 0; for (let j = i - n; j < i; j++) s += x[j] * x[j]; return Math.sqrt(s / n); };
  const cycle = rate / vibratoHz;
  let best = null;
  for (let start = 16 * Math.round(0.25 * rate / 16); start <= 0.45 * rate; start += 16)
    for (const k of [1, 2]) for (let end = start + 16 * Math.floor((k * cycle - 0.012 * rate) / 16); end <= start + k * cycle + 0.012 * rate && end <= x.length - 16; end += 16) {
      let err = 0, en = 0; for (let i = 1; i <= 96; i++) { err += (x[start - i] - x[end - i]) ** 2; en += x[start - i] ** 2 + x[end - i] ** 2; }
      const ts = start / rate, te = end / rate, lv = Math.abs(env(start) - env(end)) / Math.max(env(start), 1);
      const dp = Math.abs(pitch(ts) - pitch(te)), ds = Math.sign(slope(ts)) === Math.sign(slope(te)) ? 0 : 1;
      const score = err / Math.max(en, 1) + 2 * lv + dp / 20 + 0.5 * ds;
      if (!best || score < best.score) best = { start, end, score, dp, ds, k };
    }
  return { loopStart: best.start / rate, trimEnd: best.end / rate, score: best.score, pitchGap: best.dp, cycles: best.k };
}

// node onchain/snes/samples/loot/flute.mjs: write flute.json (the two zones, volume matched to the
// flute it replaces) and put them in place of `flute` in manifest.json and manifest-12k.json
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  const { writeFileSync } = await import('node:fs');
  const { encodeBRR, decodeBRR } = await import('../../brr.js');
  const snes = new URL('../../', here), read = (f) => JSON.parse(readFileSync(new URL(f, snes)));
  const old = read('manifest.json').instruments.find((i) => i.id === 'flute' && !i.keys) ?? JSON.parse(readFileSync(new URL('replaced-flute.json', here)));
  writeFileSync(new URL('replaced-flute.json', here), JSON.stringify(old, null, 2) + '\n');
  // a 1.2 s note at its root as the player plays it (attack, then the loop): its level after the attack
  const level = (file, opt) => { const p = prepare(readWav(readFileSync(new URL(file, snes))), opt), d = decodeBRR(encodeBRR(p.pcm, p.loopStart), p.loopStart);
    let s = 0, n = 0; for (let i = Math.round(0.2 * p.rate); i < 1.2 * p.rate; i++, n++) { const v = d[i < d.length ? i : p.loopStart + ((i - d.length) % (d.length - p.loopStart))] / 32768; s += v * v; } return 10 * Math.log10(s / n); };
  // measured in the Loot lab against the TinyChip stems: the level match leaves it 0.7 dB loud
  const TRIM_DB = 0.7, ref = level(old.file, old), zones = [];
  for (const [name, root, keys, hz, vib] of [['C4', 60, [0, 66], 261.6256, 6.9], ['C5', 72, [67, 127], 523.2511, 7.5]]) {
    const file = `samples/loot/flute_${name}_src.wav`, x = readWav(readFileSync(new URL(file, snes))).pcm; let pk = 0; for (const v of x) pk = Math.max(pk, Math.abs(v));
    const gain = +(0.708 / pk).toFixed(3), L = findLoop(`flute_${name}_src.wav`, gain, hz, vib);
    const opt = { sampleRate: 16000, gain, loopStart: +L.loopStart.toFixed(4), trimEnd: +L.trimEnd.toFixed(4), loopCrossfade: 0.02 };
    zones.push({ id: `flute-${name}`, file, program: old.program, keys, rootNote: root, ...opt, tuneCents: 0, volume: +(old.volume * 10 ** ((ref - level(file, opt) - TRIM_DB) / 20)).toFixed(3),
      envelope: old.envelope, credit: { author: 'Casey Wescott', license: 'Own work', source: `new_samples_loot_survivor/Classic Electric Pianoflute_${name.toLowerCase()}.aif` } });
  }
  writeFileSync(new URL('flute.json', here), JSON.stringify(zones, null, 2) + '\n');
  for (const f of ['manifest.json', 'manifest-12k.json']) {
    const m = read(f); m.instruments = m.instruments.flatMap((i) => (i.id === 'flute' || i.id.startsWith('flute-') ? (i.id === 'flute' || i.id === 'flute-C4' ? zones : []) : [i]));
    writeFileSync(new URL(f, snes), JSON.stringify(m, null, 2) + '\n');
  }
  console.log(JSON.stringify(zones.map((z) => ({ id: z.id, keys: z.keys, loop: [z.loopStart, z.trimEnd], gain: z.gain, volume: z.volume })), null, 1));
}

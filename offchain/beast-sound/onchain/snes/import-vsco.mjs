// Recreate the compact CC0 source subset from revision/hash-pinned originals.
// node onchain/snes/import-vsco.mjs [--download]
// Full recordings stay in the ignored source cache; only short mono WAVs enter Git.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readWav, prepare } from './prepare.mjs';
const here = dirname(fileURLToPath(import.meta.url));
const sources = JSON.parse(readFileSync(resolve(here, 'vsco-sources.json'), 'utf8'));
const sha = (b) => createHash('sha256').update(b).digest('hex');
const settings = {
  harp: { program: 46, rootNote: 62, start: 0.020, length: 0.34, loopMin: 0.18, volume: 0.48, envelope: { attack: 0.002, decay: 0.65, sustain: 0.08, release: 0.24 } },
  marimba: { program: 12, rootNote: 72, start: 0, length: 0.36, volume: 0.6, envelope: { attack: 0.001, decay: 0.5, sustain: 0.2, release: 0.12 } },
  glockenspiel: { program: 9, rootNote: 84, start: 0, length: 0.26, loopMin: 0.12, volume: 0.48, envelope: { attack: 0.001, decay: 0.8, sustain: 0.1, release: 0.35 } },
  strings: { program: 48, rootNote: 72, start: 0.012, length: 0.45, loopMin: 0.20, volume: 0.42, envelope: { attack: 0.025, decay: 0.2, sustain: 0.85, release: 0.22 } },
  cello: { program: 42, rootNote: 60, start: 0, length: 0.44, loopMin: 0.23, volume: 0.48, envelope: { attack: 0.012, decay: 0.24, sustain: 0.8, release: 0.2 } },
  flute: { program: 73, rootNote: 72, start: 0.008, length: 0.36, loopMin: 0.15, volume: 0.40, envelope: { attack: 0.008, decay: 0.12, sustain: 0.8, release: 0.15 } },
};
function wav16(pcm, rate) {
  const b = Buffer.alloc(44 + pcm.length * 2);
  b.write('RIFF'); b.writeUInt32LE(b.length - 8, 4); b.write('WAVEfmt ', 8); b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 2, 28);
  b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(pcm.length * 2, 40);
  pcm.forEach((v, i) => b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), 44 + i * 2));
  return b;
}
// Windowed spectral peak around the known sounding root; no octave guessing.
// This also handles the glockenspiel's inharmonic overtones (which confuse autocorrelation).
function tuning(pcm, rate, root) {
  const nominal = 440 * 2 ** ((root - 69) / 12), low = nominal * 0.96, step = nominal * 0.08 / 128;
  const window = pcm.slice(Math.floor(rate * 0.08));
  for (let i = 0; i < window.length; i++) window[i] *= 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (window.length - 1));
  const values = [];
  for (let bin = 0; bin <= 128; bin++) {
    const angle = 2 * Math.PI * (low + bin * step) / rate, dc = Math.cos(angle), ds = Math.sin(angle);
    let c = 1, s = 0, re = 0, im = 0;
    for (const v of window) { re += v * c; im += v * s; const next = c * dc - s * ds; s = s * dc + c * ds; c = next; }
    values.push(re * re + im * im);
  }
  const index = values.indexOf(Math.max(...values));
  if (index === 0 || index === values.length - 1) throw new Error('Root pitch outside tuning search');
  const [a, b, c] = values.slice(index - 1, index + 2), offset = 0.5 * (a - c) / (a - 2 * b + c);
  const hz = low + (index + offset) * step;
  return { measuredHz: +hz.toFixed(3), tuneCents: +(-1200 * Math.log2(hz / nominal)).toFixed(2) };
}
function loop(pcm, minSeconds, rate) {
  let best;
  // Match a 4 ms waveform window before both boundaries; permit up to 40 ms shorter tail.
  const width = 64, maxEnd = Math.floor(pcm.length / 16) * 16;
  for (let end = maxEnd - 640; end <= maxEnd; end += 16) {
    for (let start = Math.ceil(minSeconds * rate / 16) * 16; start <= end - 1280; start += 16) {
      let error = 0, energy = 0;
      for (let i = 1; i <= width; i++) { error += (pcm[start - i] - pcm[end - i]) ** 2; energy += pcm[start - i] ** 2 + pcm[end - i] ** 2; }
      const score = error / Math.max(energy, 1);
      if (!best || score < best.score) best = { start, end, score };
    }
  }
  if (!best) throw new Error('No valid loop candidates');
  return best;
}
mkdirSync(resolve(here, 'samples/.source-cache'), { recursive: true });
mkdirSync(resolve(here, 'samples/vsco'), { recursive: true });
const instruments = [], processing = [];
for (const source of sources.samples) {
  const cached = resolve(here, `samples/.source-cache/${source.id}.wav`);
  if (!existsSync(cached)) {
    if (!process.argv.includes('--download')) throw new Error(`Missing ${source.id}: run with --download to fetch pinned originals`);
    execFileSync('curl', ['-L', '--fail', '--silent', '--show-error', source.url, '-o', cached]);
  }
  const original = readFileSync(cached);
  if (sha(original) !== source.sha256) throw new Error(`Source checksum mismatch: ${source.id}`);
  const input = readWav(original), s = settings[source.id];
  const crop = input.pcm.slice(Math.round(s.start * input.rate), Math.round((s.start + s.length) * input.rate));
  const mean = crop.reduce((a, b) => a + b, 0) / crop.length;
  let peak = 0; for (const x of crop) peak = Math.max(peak, Math.abs(x - mean));
  const gain = 0.72 / peak;
  const file = `samples/vsco/${source.id}.wav`, bytes = wav16(crop.map((v) => (v - mean) * gain), input.rate);
  writeFileSync(resolve(here, file), bytes);
  // Keep original sample rate in these small source clips. The bank build resamples only once.
  const prepared = prepare(readWav(bytes), { sampleRate: 16000 });
  const points = s.loopMin ? loop(prepared.pcm, s.loopMin, 16000) : null;
  const pitch = tuning(crop, input.rate, s.rootNote);
  instruments.push({ id: source.id, file, program: s.program, rootNote: s.rootNote, sampleRate: 16000,
    ...(points ? { trimEnd: points.end / 16000, loopStart: points.start / 16000, loopCrossfade: 0.012 } : { fadeOut: 0.035 }),
    fadeIn: 0.001, tuneCents: pitch.tuneCents, volume: s.volume, envelope: s.envelope,
    credit: { author: 'Versilian Studios / Sam Gossner & Simon Dalzell', license: 'CC0-1.0', source: sources.homepage } });
  processing.push({ id: source.id, inputRate: input.rate, cropStart: s.start, cropSeconds: crop.length / input.rate, monoNormalizationGain: +gain.toFixed(6), dcRemoved: +mean.toFixed(8), preparedSha256: sha(bytes), preparedBytes: bytes.length, ...pitch, ...(points ? { loopStart: points.start, loopEnd: points.end, boundaryError: +points.score.toFixed(6) } : {}) });
}
// Bare Beast scores use program 0: reuse the harp payload rather than storing another sample.
instruments.push({ ...instruments[0], id: 'default-harp', program: 0 });
writeFileSync(resolve(here, 'manifest.json'), JSON.stringify({ format: 'BSBRR1', name: 'VSCO pocket orchestra', maxBrrBytes: 20480, instruments }, null, 2) + '\n');
writeFileSync(resolve(here, 'vsco-processing.json'), JSON.stringify({ rate: 16000, samples: processing }, null, 2) + '\n');
console.log(JSON.stringify(processing, null, 2));

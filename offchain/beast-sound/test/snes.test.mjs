import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import { encodeBRR, decodeBRR, validateBRR } from '../onchain/snes/brr.js';
import { readWav, prepare } from '../onchain/snes/prepare.mjs';
import { validateBank } from '../onchain/snes/bank.js';
import { buildBank, bundleBank, buildArtifacts, cairoData } from '../onchain/snes/build.mjs';
import { toBase91, fromBase91 } from '../onchain/snes/pack.js';

function wav(pcm, rate = 32000) {
  const b = Buffer.alloc(44 + pcm.length * 2);
  b.write('RIFF'); b.writeUInt32LE(b.length - 8, 4); b.write('WAVEfmt ', 8); b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 2, 28);
  b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(pcm.length * 2, 40);
  pcm.forEach((s, i) => b.writeInt16LE(s, 44 + i * 2)); return b;
}
const tone = (length = 4096, period = 64) => Int16Array.from({ length }, (_, i) => Math.round(14000 * Math.sin(i * 2 * Math.PI / period)));
const example = () => ({ format: 'BSBRR1', instruments: [{ id: 'test', file: 'tone.wav', program: 0, rootNote: 60, loopStart: 0.032, credit: { author: 'Test', license: 'Test only', source: 'Generated sine' } }] });
function fixture(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'snes-bank-'));
  try { writeFileSync(join(dir, 'tone.wav'), wav(tone())); return fn(dir); }
  finally { rmSync(dir, { recursive: true, force: true }); }
}

test('BRR known filter-0 vector: sign, high nibble, range and final flag', () => {
  const bytes = Uint8Array.from([0x11, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef]);
  assert.deepEqual([...decodeBRR(bytes)], [0, 2, 4, 6, 8, 10, 12, 14, -16, -14, -12, -10, -8, -6, -4, -2]);
  assert.deepEqual([...decodeBRR(Uint8Array.from([0xd1, ...Array(8).fill(0x7f)]))], Array.from({ length: 16 }, (_, i) => i % 2 ? -4096 : 0));
});
test('BRR filter-1 history vector and malformed stream rejection', () => {
  assert.deepEqual([...decodeBRR(Uint8Array.from([0x15, 0x70, 0, 0, 0, 0, 0, 0, 0]))], [14, 12, 10, 8, 6, 4, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  assert.throws(() => decodeBRR(new Uint8Array(8)), /9-byte/);
  assert.throws(() => decodeBRR(new Uint8Array(9)), /end flag/);
  assert.throws(() => decodeBRR(Uint8Array.from([1, ...Array(17).fill(0)])), /end flag/);
  assert.throws(() => validateBRR(Uint8Array.from([3, ...Array(8).fill(0)])), /disagree/);
});
test('predictive encoding preserves a tone and resets prediction at loop entry', () => {
  const pcm = tone(), brr = encodeBRR(pcm, 64), decoded = decodeBRR(brr, 64);
  assert.equal(brr.length, pcm.length / 16 * 9);
  assert.equal(brr[0] & 12, 0); assert.equal(brr[64 / 16 * 9] & 12, 0); assert.equal(brr.at(-9) & 3, 3);
  assert.deepEqual(decodeBRR(brr.slice(64 / 16 * 9), 0), decoded.slice(64));
  let error = 0, signal = 0;
  for (let i = 0; i < pcm.length; i++) { error += (pcm[i] - decoded[i]) ** 2; signal += pcm[i] ** 2; }
  assert.ok(10 * Math.log10(signal / error) > 30);
  assert.throws(() => encodeBRR(pcm, 17), /loop/);
});
test('WAV preparation aligns loops, preserves one-shot padding and rejects bad metadata', () => {
  const input = readWav(wav(tone(4100)));
  const one = prepare(input), loop = prepare(input, { loopStart: 0.032 });
  assert.equal(one.pcm.length, 2064); assert.equal(loop.pcm.length, 2048); assert.equal(loop.loopStart, 512);
  assert.equal(prepare(input, { sampleRate: 12000 }).rate, 12000);
  assert.equal(one.pcm.at(-1), 0);
  assert.throws(() => prepare(input, { sampleRate: 11999 }), /12000/);
  assert.throws(() => prepare(input, { trimEnd: 10 }), /Trim/);
  assert.throws(() => prepare(input, { loopStart: NaN }), /loopStart/);
  assert.throws(() => readWav(wav(tone()).subarray(0, 100)), /Truncated/);
});
test('resampling attenuates frequencies above the new Nyquist frequency', () => {
  const rms = (p) => Math.sqrt(p.slice(100, -100).reduce((s, v) => s + v * v, 0) / (p.length - 200));
  const low = prepare(readWav(wav(tone(4096, 32)))).pcm;
  const high = prepare(readWav(wav(tone(4096, 8 / 3)))).pcm;
  assert.ok(rms(high) / rms(low) < 0.01);
});
test('loop crossfade joins pre-loop history and one-shots fade to zero', () => {
  const input = readWav(wav(tone(4096))), loopStart = 0.04;
  const plain = prepare(input, { loopStart });
  const smoothed = prepare(input, { loopStart, loopCrossfade: 0.01, fadeIn: 0.001 });
  assert.equal(smoothed.pcm.at(-1), plain.pcm[smoothed.loopStart - 1]);
  assert.equal(smoothed.pcm[0], 0);
  assert.equal(prepare(input, { fadeOut: 0.02 }).pcm.at(-1), 0);
  assert.throws(() => prepare(input, { loopCrossfade: 0.01 }), /pre-loop/);
  assert.throws(() => prepare(input, { loopStart: 0.001, loopCrossfade: 0.01 }), /pre-loop/);
  assert.throws(() => prepare(input, { loopStart, fadeOut: 0.01 }), /instead/);
});
test('bank compilation is deterministic, deduplicated, budgeted and validates mappings', () => fixture((dir) => {
  const path = join(dir, 'manifest.json'), m = example();
  m.instruments.push({ ...m.instruments[0], id: 'second', program: 1 });
  writeFileSync(path, JSON.stringify(m));
  const result = buildBank(path); assert.equal(result.bank.samples.length, 1); assert.equal(result.bank.instruments.length, 2);
  assert.deepEqual(buildBank(path), result);
  assert.equal(result.report.brrBytes, 1152);
  m.maxBrrBytes = 100; writeFileSync(path, JSON.stringify(m)); assert.throws(() => buildBank(path), /budget/);
  delete m.maxBrrBytes; m.instruments[1].program = 0; writeFileSync(path, JSON.stringify(m)); assert.throws(() => buildBank(path), /Duplicate/);
  const bad = structuredClone(result.bank); bad.samples[0].data = 'not base64'; assert.throws(() => validateBank(bad), /base64/);
}));
test('empty bank bundles safely, Cairo data is aligned, and encoder stays out of browser code', async () => {
  const bank = { format: 'BSBRR1', name: '</script><img>', samples: [], instruments: [] };
  const script = await bundleBank(bank);
  assert.ok(!script.includes('</script>')); assert.ok(!script.includes('PCM length must'));
  const unnamed = { format: 'BSBRR1', samples: [], instruments: [] };
  const context = { window: {} }; runInNewContext(await bundleBank(unnamed), context);
  assert.deepEqual(JSON.parse(JSON.stringify(context.window.SnesBank.bank)), unnamed);
  assert.throws(() => cairoData('AA=='), /aligned/);
  const dir = mkdtempSync(join(tmpdir(), 'snes-artifacts-'));
  try {
    const path = join(dir, 'manifest.json'); writeFileSync(path, JSON.stringify({ ...bank, maxBrrBytes: 20480 }));
    const report = await buildArtifacts(path, join(dir, 'out'));
    const stored = readFileSync(join(dir, 'out/stored.b64'), 'utf8');
    assert.equal(stored.length % 372, 0); assert.equal(report.pageDataWords, stored.length / 31);
    assert.ok(readFileSync(join(dir, 'out/page_data.cairo'), 'utf8').includes(`"${stored}"`));
    assert.ok(Buffer.from(stored, 'base64').toString().includes('snes-brr-1'));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('base91 page text round-trips every length and byte, with no quote, backslash or <', () => {
  let seed = 7;
  const random = () => (seed = (seed * 1103515245 + 12345) >>> 0) >>> 24;
  for (let len = 0; len < 300; len++) {
    for (const fill of [random, () => 0, () => 255]) {
      const bytes = Array.from({ length: len }, fill), text = toBase91(bytes);
      assert.deepEqual(fromBase91(text), bytes);
      assert.ok(!/["\\<]/.test(text));
    }
  }
});

test('curated VSCO bank is reproducible, ten payloads cover ten MIDI programs below 32 KiB', async () => {
  const root = new URL('../onchain/snes/', import.meta.url);
  const processing = JSON.parse(readFileSync(new URL('vsco-processing.json', root)));
  for (const s of processing.samples) {
    const bytes = readFileSync(new URL(`samples/vsco/${s.id}.wav`, root));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), s.preparedSha256);
    assert.ok(bytes.length < 45000);
  }
  const { bank, report } = buildBank(new URL('manifest.json', root));
  assert.equal(bank.samples.length, 10); assert.equal(bank.instruments.length, 10);
  assert.ok(report.brrBytes < 32768); assert.equal(report.sharedSampleReferences, 0);
  assert.deepEqual([0, 45, 47, 71].map((program) => bank.instruments.find((i) => i.program === program)?.id), ['piano', 'pizzicato', 'timpani', 'clarinet']);
  assert.notEqual(bank.instruments.find((i) => i.program === 0).sample, bank.instruments.find((i) => i.program === 46).sample);
  assert.ok(report.instruments.every((i) => i.snrDb > 20));
  const context = { window: {} }; runInNewContext(await bundleBank(bank), context);
  assert.deepEqual(JSON.parse(JSON.stringify(context.window.SnesBank.bank)), bank);
  assert.equal(context.window.SnesBank.bank.instruments[0].credit, context.window.SnesBank.bank.instruments[1].credit);
  const economical = buildBank(new URL('manifest-12k.json', root));
  assert.ok(economical.report.brrBytes < 28672);
  assert.ok(report.brrBytes - economical.report.brrBytes > 4000);
  const reduced = new Set(['marimba', 'strings', 'cello', 'clarinet', 'timpani']);
  economical.bank.instruments.forEach((i) => assert.equal(economical.bank.samples[i.sample].rate, reduced.has(i.id) ? 12000 : 16000));
  const badRate = structuredClone(economical.bank); badRate.samples[0].rate = 11999;
  assert.throws(() => validateBank(badRate), /sample rate/);
});

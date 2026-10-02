// The optional TinyChip pack (onchain/tinychip) against a stand-in tinysynth: where presets land,
// and what the player hook does for bare Beast scores and for MIDI that selects the chip bank.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const plain = (x) => JSON.parse(JSON.stringify(x)); // values made inside the sandbox realm

function loadPack() {
  const ctx = {};
  vm.runInNewContext(readFileSync(new URL('../onchain/tinychip/tinysynth-chip.js', import.meta.url), 'utf8'), ctx);
  return ctx.TinyChip;
}
function fakeSynth() {
  const ac = { sampleRate: 8000, createBuffer: (ch, len) => { const d = new Float32Array(len); return { getChannelData: () => d }; } };
  const s = {
    program: Array.from({ length: 128 }, (_, i) => ({ name: 'GM ' + i, p: [{ w: 'sine' }] })),
    drummap: Array.from({ length: 47 }, (_, i) => ({ name: 'GM drum ' + (35 + i), p: [{ w: 'n0' }] })),
    noiseBuf: { n0: {}, n1: {} }, pg: new Array(16).fill(0), calls: [],
    getAudioContext: () => ac,
    setTimbre(m, n, p) { if (m === 0) this.program[n] = { ...this.program[n], p }; else this.drummap[n - 35] = { ...this.drummap[n - 35], p }; },
    setProgram(ch, v) { this.pg[ch] = v; this.calls.push([ch, v]); },
  };
  return s;
}

test('install above General MIDI keeps the GM set and fills tinysynth defaults', () => {
  const T = loadPack(), s = fakeSynth();
  T.install(s, { programBase: T.PROGRAM_BASE, drums: false });
  assert.equal(T.PRESETS.length, 100);
  assert.equal(s.program[0].name, 'GM 0');
  assert.equal(s.program[T.PROGRAM_BASE].name, 'Triangle Lead (vibrato)');
  assert.equal(s.program[T.PROGRAM_BASE + 99].name, T.PRESETS[99].name);
  for (const k of ['g', 'w', 't', 'f', 'v', 'a', 'h', 'd', 's', 'r', 'p', 'q', 'k']) assert.ok(k in s.program[T.PROGRAM_BASE].p[0], k);
  assert.equal(s.drummap[1].name, 'GM drum 36'); // drums untouched
  assert.ok(T.WAVES.every((w) => s.noiseBuf[w]), 'chip waveforms registered');
});

test('bare Beast score: every note channel gets the chip lead and the chip drum kit', () => {
  const T = loadPack(), s = fakeSynth();
  const r = T.attach(s, { bare: true, channels: [0, 1, 4], events: [{ t: 0, m: [0x90, 60, 90] }] });
  assert.deepEqual(plain(r), { orchestration: 'tinychip-1', presets: 100, chipChannels: [0, 1, 4], chipDrums: true });
  assert.deepEqual([0, 1, 4].map((c) => s.pg[c]), [T.PROGRAM_BASE, T.PROGRAM_BASE, T.PROGRAM_BASE]);
  assert.equal(s.drummap[1].name, 'Kick');
});

test('MIDI with Bank Select 1 on a channel gets chip presets there; other channels stay General MIDI', () => {
  const T = loadPack(), s = fakeSynth();
  const events = [
    { t: 0, m: [0xb2, 0, 1] }, { t: 0, m: [0xc2, 50] },   // channel 3: chip bank, preset 50 (Robot Hero Lead)
    { t: 0, m: [0xc0, 80] },                              // channel 1: GM square lead, untouched
    { t: 480, m: [0xc2, 93] },                            // later change on the chip channel
  ];
  const r = T.attach(s, { bare: false, channels: [0, 2], events });
  assert.deepEqual(plain(r.chipChannels), [2]);
  assert.equal(r.chipDrums, false);
  assert.deepEqual(plain(events.map((e) => e.m)), [[0xb2, 0, 1], [0xc2, T.PROGRAM_BASE + 50], [0xc0, 80], [0xc2, T.PROGRAM_BASE + 93]]);
  assert.equal(s.drummap[1].name, 'GM drum 36');
});

test('MIDI that never selects the chip bank is left exactly as written', () => {
  const T = loadPack(), s = fakeSynth();
  const events = [{ t: 0, m: [0xc0, 33] }, { t: 0, m: [0x99, 36, 100] }];
  const before = JSON.stringify(events);
  const r = T.attach(s, { bare: false, channels: [0, 9], events });
  assert.equal(JSON.stringify(events), before);
  assert.equal(r, null);
  assert.equal(s.calls.length, 0);
  assert.equal(s.program[T.PROGRAM_BASE], undefined, 'nothing installed');
});

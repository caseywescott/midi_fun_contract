// The optional TinyChip module (onchain/tinychip) against a stand-in tinysynth: the 20-preset onchain
// runtime matches the full bank, the orchestration it gives bare Beast scores, and the Bank Select 1
// path for other MIDI, with and without the client-side full bank.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { engine } from '../src/index.js';
import { ESSENTIALS, tinychipSource } from '../onchain/tinychip/essentials.mjs';

const plain = (x) => JSON.parse(JSON.stringify(x)); // values made inside the sandbox realm
const bankSrc = readFileSync(new URL('../onchain/tinychip/tinysynth-chip.js', import.meta.url), 'utf8');
function load({ bank = false } = {}) {
  const ctx = {};
  if (bank) vm.runInNewContext(bankSrc, ctx);
  vm.runInNewContext(tinychipSource(), ctx);
  return ctx;
}
function fakeSynth() {
  const ac = { sampleRate: 8000, createBuffer: (ch, len) => { const d = new Float32Array(len); return { getChannelData: () => d }; } };
  return {
    program: Array.from({ length: 128 }, (_, i) => ({ name: 'GM ' + i, p: [{ w: 'sine' }] })),
    drummap: Array.from({ length: 47 }, (_, i) => ({ name: 'GM drum ' + (35 + i), p: [{ w: 'n0' }] })),
    noiseBuf: { n0: {}, n1: {} }, pg: new Array(16).fill(0), calls: [], song: { timebase: 1920 },
    getAudioContext: () => ac,
    setTimbre(m, n, p) { if (m === 0) this.program[n] = { ...this.program[n], p }; else this.drummap[n - 35] = { ...this.drummap[n - 35], p }; },
    setProgram(ch, v) { this.pg[ch] = v; this.calls.push([ch, v]); },
  };
}
// a Beast score as tinysynth song events: tempo at tick 0, then note-ons (channel = voice)
function beastEvents(beast, live) {
  const r = engine.render(beast, { summit_held_seconds: 0, ...live });
  const ev = [{ t: 0, m: [0xff51, 60e6 / r.params.tempo_us] }];
  for (const e of r.form.events) ev.push({ t: e.time, m: [0x90 | e.voice_id, e.pitch, e.velocity] }, { t: e.time + e.duration, m: [0x80 | e.voice_id, e.pitch, 64] });
  return { events: ev.sort((a, b) => a.t - b.t), channels: [...new Set(r.form.events.map((e) => e.voice_id))].sort((a, b) => a - b), r };
}
const close = (a, b) => (typeof a === 'number' ? Math.abs(a - b) <= 1e-5 * Math.max(1, Math.abs(b)) : a === b);

test('the onchain runtime holds the 20 essentials, and the orchestration pools use all of them', () => {
  const { TinyChip: T } = load();
  assert.deepEqual(plain(T.PRESET_IDS).sort((a, b) => a - b), [...ESSENTIALS].sort((a, b) => a - b));
  const pooled = Object.values(plain(T.POOLS)).flat().sort((a, b) => a - b);
  assert.deepEqual(pooled, [...ESSENTIALS].sort((a, b) => a - b));
});

test('its presets, drum kit and waveforms match the full bank (loudness gains folded in)', () => {
  const { TinyChip: T, TinyChipBank: B } = load({ bank: true });
  const a = fakeSynth(), b = fakeSynth();
  T.attach(a, { bare: true, channels: [0], events: [{ t: 0, m: [0x90, 60, 90] }] });
  B.install(b, { programBase: T.PROGRAM_BASE, drums: true });
  for (const id of ESSENTIALS) {
    const x = a.program[T.PROGRAM_BASE + id].p, y = b.program[T.PROGRAM_BASE + id].p;
    assert.equal(x.length, y.length, `preset ${id}`);
    x.forEach((op, i) => { for (const k in y[i]) assert.ok(close(op[k], y[i][k]), `preset ${id} op ${i} ${k}: ${op[k]} vs ${y[i][k]}`); });
  }
  for (let key = 35; key <= 59; key++) assert.deepEqual(plain(a.drummap[key - 35].p), plain(b.drummap[key - 35].p), `drum ${key}`);
  for (const w of ['nP12', 'nP25', 'nP50', 'nTRI', 'nSAW', 'nN16', 'nNOI', 'nMET']) assert.deepEqual(a.noiseBuf[w].getChannelData(), b.noiseBuf[w].getChannelData(), w);
});

test('orchestration: deterministic, register roles, tempo picks the leads, no preset twice in a score', () => {
  const { TinyChip: T } = load();
  const P = plain(T.POOLS);
  const cache = JSON.parse(readFileSync(new URL('../onchain/.gallery-cache.json', import.meta.url), 'utf8'));
  const gallery = JSON.parse(readFileSync(new URL('../public/onchain/gallery.json', import.meta.url), 'utf8'));
  const sets = new Set(), used = new Set();
  for (const { token } of gallery) {
    const { beast, live } = cache[token];
    const { events, channels, r } = beastEvents(beast, live);
    const roles = plain(T.orchestrate(events, channels, 1920));
    assert.deepEqual(plain(T.orchestrate(events, channels, 1920)), roles, 'same score, same orchestration');
    const ids = Object.values(roles);
    assert.equal(ids.length, channels.length);
    assert.equal(new Set(ids).size, ids.length, `token ${token}: a preset used twice`);
    const mean = (ch) => { const ps = r.form.events.filter((e) => e.voice_id === ch).map((e) => e.pitch); return ps.reduce((x, y) => x + y, 0) / ps.length; };
    const byPitch = [...channels].sort((x, y) => mean(x) - mean(y));
    const top = roles[byPitch[byPitch.length - 1]];
    assert.ok((r.params.tempo_us < 500000 ? P.bright : P.lead).includes(top), `token ${token}: lead ${top}`);
    if (byPitch.length > 1) assert.ok([...P.bass, ...P.keys].includes(roles[byPitch[0]]), `token ${token}: bottom voice`);
    sets.add(JSON.stringify(roles)); ids.forEach((id) => used.add(id));
  }
  console.log(`orchestrations: ${sets.size} distinct across ${gallery.length} Beasts, ${used.size} of 20 presets used`);
  assert.ok(sets.size >= 40, `only ${sets.size} distinct orchestrations across ${gallery.length} Beasts`);
  assert.ok(used.size >= 16, `only ${used.size} of 20 presets used`);
});

test('bare Beast score: orchestrated presets on the note channels and the chip drum kit', () => {
  const { TinyChip: T } = load(), s = fakeSynth();
  const { events, channels } = beastEvents({ id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 }, { adventurers_killed: 500, scars: 20, rank: 1, species_count: 40 });
  const r = plain(T.attach(s, { bare: true, channels, events }));
  assert.equal(r.orchestration, 'tinychip-2');
  assert.equal(r.chipDrums, true);
  for (const ch of channels) assert.equal(s.pg[ch], T.PROGRAM_BASE + r.presets[ch]);
  assert.equal(s.program[0].name, 'GM 0', 'General MIDI untouched');
  assert.equal(s.drummap[1].p[0].w, 'nTRI', 'chip kick on key 36');
});

test('Bank Select 1: the 20 by bank number, the Triangle Lead for the rest; all 100 with the client bank', () => {
  const events = () => [
    { t: 0, m: [0xb2, 0, 1] }, { t: 0, m: [0xc2, 50] },   // channel 3: chip bank, preset 50 (an essential)
    { t: 0, m: [0xc0, 80] },                              // channel 1: GM square lead, untouched
    { t: 480, m: [0xc2, 93] },                            // later change to a preset outside the 20
  ];
  const { TinyChip: T } = load(), s = fakeSynth(), ev = events();
  const r = plain(T.attach(s, { bare: false, channels: [0, 2], events: ev }));
  assert.deepEqual(r.chipChannels, [2]);
  assert.equal(r.fullBank, false);
  assert.deepEqual(plain(ev.map((e) => e.m)), [[0xb2, 0, 1], [0xc2, 129 + 50], [0xc0, 80], [0xc2, 129 + 0]]);
  assert.equal(s.drummap[1].name, 'GM drum 36');

  const withBank = load({ bank: true }), s2 = fakeSynth(), ev2 = events();
  const r2 = plain(withBank.TinyChip.attach(s2, { bare: false, channels: [0, 2], events: ev2 }));
  assert.equal(r2.fullBank, true);
  assert.deepEqual(plain(ev2.map((e) => e.m)).at(-1), [0xc2, 129 + 93]);
  assert.ok(s2.program[129 + 93].p.length > 0, 'full bank installed');
});

test('MIDI that never selects the chip bank is left exactly as written', () => {
  const { TinyChip: T } = load(), s = fakeSynth();
  const events = [{ t: 0, m: [0xc0, 33] }, { t: 0, m: [0x99, 36, 100] }];
  const before = JSON.stringify(events);
  assert.equal(T.attach(s, { bare: false, channels: [0, 9], events }), null);
  assert.equal(JSON.stringify(events), before);
  assert.equal(s.calls.length, 0);
  assert.equal(s.program[T.PROGRAM_BASE], undefined, 'nothing installed');
});

test('orchestration ignores the order of notes on the same tick', () => {
  const { TinyChip: T } = load();
  const { events, channels } = beastEvents({ id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 }, { adventurers_killed: 500, scars: 20, rank: 1, species_count: 40 });
  const shuffled = [...events].sort((a, b) => a.t - b.t || (b.m[0] & 15) - (a.m[0] & 15)); // reverse channel order within each tick
  assert.notDeepEqual(shuffled.map((e) => e.m[0]), events.map((e) => e.m[0]));
  assert.deepEqual(plain(T.orchestrate(shuffled, channels, 1920)), plain(T.orchestrate(events, channels, 1920)));
});

// The TinySynth page player: orchestration rules, and the shipped (patched) TinySynth playing Beast
// MIDI with sample-exact timing, driven offline against a mock WebAudio clock.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import vm from 'node:vm';
import { encodeTokenId, engine } from '../src/index.js';
import { drumPass as schedulerDrumPass } from '../server/scheduler.js';
import {
  DRUM_KEYS, LEAD, LEAD_PROGRAM, decodeMidi, drumEvents, drumPass, drumVelocity, isBareScore, loopEndTicks, noteChannels, panValue,
} from '../onchain/player-core.js';

const dir = new URL('../onchain/', import.meta.url);
const shipped = new URL('dist/tinysynth.min.js', dir);

const seeded = (seed) => () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
const beastMidi = (b, live) => Uint8Array.from(engine.toMidiFile(engine.render(b, { summit_held_seconds: 0, ...live })));
// Tier 1 Brute with an animated+shiny tempo (455,000 us = 131.87 BPM) and five voices.
const HEAVY = { id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 };
const HEAVY_LIVE = { adventurers_killed: 200, scars: 63, rank: 1, species_count: 1243 };

test('drum pass matches the previous page scheduler at 480 PPQN', () => {
  for (const loop of [1920, 7680, 19200]) assert.deepEqual(drumPass(loop, 480, seeded(7)), schedulerDrumPass(loop, seeded(7)));
  const ev = drumEvents(3840, 480, seeded(3));
  assert.ok(ev.every((e) => e.m[0] === 0x99 && Object.values(DRUM_KEYS).includes(e.m[1]) && e.m[2] >= 1 && e.m[2] <= 127));
  assert.deepEqual(ev.filter((e) => e.m[1] === DRUM_KEYS.kick).map((e) => e.t), [0, 1920]);
  assert.deepEqual(ev.filter((e) => e.m[1] === DRUM_KEYS.snare).map((e) => e.t), [960, 2880]);
  assert.equal(drumVelocity(0.32), 127);
  assert.equal(drumVelocity(0.16), 90);
});

test('bare scores get the page orchestration; scores with programs or percussion do not', () => {
  const bare = [{ t: 0, m: [0xff51, 120] }, { t: 0, m: [0x90, 60, 100] }, { t: 0, m: [0x93, 64, 100] }, { t: 480, m: [0x80, 60, 64] }];
  assert.ok(isBareScore(bare));
  assert.deepEqual(noteChannels(bare), [0, 3]);
  assert.ok(!isBareScore([...bare, { t: 0, m: [0xc1, 12] }]));
  assert.ok(!isBareScore([...bare, { t: 0, m: [0x99, 42, 70] }]));
  assert.ok(isBareScore([...bare, { t: 0, m: [0xf0, 0x7e, 0xf7] }]));
  assert.equal(loopEndTicks(1, 1920), 1920);
  assert.equal(loopEndTicks(1920, 1920), 1920);
  assert.equal(loopEndTicks(7681, 1920), 9600);
  assert.equal(panValue(0, 1), 64);
  assert.equal(panValue(0, 3), 64 - 0.85 * 64);
  assert.equal(panValue(2, 3), 64 + 0.85 * 64);
  assert.equal(LEAD.length, 2);
  assert.equal(LEAD_PROGRAM, 128);
});

test('MIDI text decodes with whitespace and rejects non-MIDI', () => {
  const midi = beastMidi(HEAVY, HEAVY_LIVE);
  const text = '   ' + Buffer.from(midi).toString('base64') + '      ';
  assert.deepEqual(decodeMidi(text), midi);
  assert.equal(decodeMidi('not base64!'), null);
  assert.equal(decodeMidi(Buffer.from('RIFF0000WAVEfmt ').toString('base64')), null);
  assert.equal(decodeMidi(''), null);
});

// ── TinySynth offline ─────────────────────────────────────────────

function mockAudio() {
  const param = (value = 0) => ({ value, setValueAtTime() {}, linearRampToValueAtTime() {}, exponentialRampToValueAtTime() {}, setTargetAtTime() {}, cancelScheduledValues() {} });
  const node = (extra = {}) => ({ connect() {}, disconnect() {}, ...extra });
  const ac = {
    currentTime: 0, sampleRate: 8000, state: 'running', destination: node(), resume: async () => {},
    createGain: () => node({ gain: param(1) }),
    createDynamicsCompressor: () => node(),
    createStereoPanner: () => node({ pan: param(0) }),
    createConvolver: () => node(),
    createBuffer: (ch, len) => ({ getChannelData: () => new Float32Array(len) }),
    createPeriodicWave: () => ({}),
    createOscillator: () => node({ frequency: param(440), detune: param(0), start() {}, stop() {}, setPeriodicWave() {} }),
    createBufferSource: () => node({ playbackRate: param(1), detune: param(0), start() {}, stop() {} }),
  };
  return ac;
}

/** Loads TinySynth source as the page does (a classic script on `window`), with a fake clock. */
function loadSynth(source) {
  const timers = [];
  const ac = mockAudio();
  const ctx = vm.createContext({
    setInterval: (fn) => timers.push(fn), clearInterval() {}, performance: { now: () => ac.currentTime * 1000 }, console,
    AudioContext: function AudioContext() { return ac; }, Math, Float32Array, Uint8Array, String, Array, Object, Promise,
  });
  vm.runInContext(source, ctx);
  const synth = new ctx.WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 64 });
  const notes = [];
  const note = synth._note;
  synth._note = (t, ch, n, v, p) => { notes.push({ t, ch, n, v, p }); return note(t, ch, n, v, p); };
  const run = (until, step = 0.05) => {
    for (; ac.currentTime < until; ac.currentTime = +(ac.currentTime + step).toFixed(6)) timers.forEach((fn) => fn());
  };
  return { synth, notes, run, ac };
}

/** Expected note-on times: TinySynth starts playing 0.1 s after playMIDI. */
function expectedTimes(midi, start, passes, loopTicks) {
  const r = engine.render(engine.decodeTokenId(encodeTokenId(HEAVY)), { summit_held_seconds: 0, ...HEAVY_LIVE });
  const tick = r.params.tempo_us / 1e6 / 480;
  const times = [];
  for (let p = 0; p < passes; p++) for (const e of r.form.events) times.push(start + (p * loopTicks + e.time) * tick);
  return times.sort((a, b) => a - b);
}

test('patched TinySynth plays Beast MIDI at the fractional tempo, looping in whole bars', { skip: !existsSync(shipped) && 'run node onchain/build.mjs' }, () => {
  const midi = beastMidi(HEAVY, HEAVY_LIVE);
  const { synth, notes, run, ac } = loadSynth(readFileSync(shipped, 'utf8'));
  synth.loadMIDI(midi.slice().buffer);
  assert.ok(isBareScore(synth.song.ev));
  const loopTicks = loopEndTicks(synth.maxTick, synth.song.timebase);
  assert.ok(loopTicks > synth.maxTick, 'this score ends mid-bar, so the loop end matters');
  synth.loopEnd = loopTicks;
  synth.setLoop(1);
  synth.program[LEAD_PROGRAM] = { name: 'Chip lead', p: LEAD };
  for (const ch of noteChannels(synth.song.ev)) synth.setProgram(ch, LEAD_PROGRAM);
  ac.currentTime = 1;
  synth.playMIDI();
  const start = 1.1;
  const tick = 455000 / 1e6 / 480;
  run(start + 2 * loopTicks * tick + 0.5);
  const got = notes.filter((n) => n.ch !== 9).map((n) => n.t);
  const want = expectedTimes(midi, start, 2, loopTicks).filter((t) => t <= ac.currentTime + 0.2);
  assert.ok(want.length > 400, `${want.length} notes over two passes`);
  assert.equal(got.length >= want.length, true);
  for (let i = 0; i < want.length; i++) assert.ok(Math.abs(got[i] - want[i]) < 1e-9, `note ${i}: ${got[i]} vs ${want[i]}`);
  // Every melodic note used the page lead; the MIDI's channels are the voices.
  assert.ok(notes.filter((n) => n.ch !== 9).every((n) => n.p === LEAD));
});

// BSI1 (62-bit instructions, 4 per felt): exact round trip, and detection against BSN1.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { composeBeast, encodeBsi, decodeBsi, isBsi, genesisBeast } from '../src/index.js';

const golden = JSON.parse(readFileSync(new URL('./golden.json', import.meta.url), 'utf8'));
const song = (s) => ({ notes: s.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice]), tempo_us: s.params.tempo_us, length_ticks: s.lengthTicks });

test('BSI1 round-trips Beast scores exactly and packs 4 instructions per felt', () => {
  const cases = golden.cases.map((c) => composeBeast(c.beast, c.live));
  for (let id = 1; id <= 75; id += 7) cases.push(composeBeast(genesisBeast({ id, prefix: 1 + (id % 69), suffix: 1 + (id % 18), level: 3 * id, health: 10 * id }), { adventurers_killed: id * 5, scars: id % 9, summit_held_seconds: id * 3600, rank: 1 + id, species_count: 1243 }));
  for (const s of cases) {
    const felts = encodeBsi(song(s));
    assert.equal(felts.length, Math.ceil((s.events.length + 2) / 4));
    assert.ok(felts.every((f) => f < 2n ** 248n));
    assert.ok(isBsi(felts));
    assert.ok(!isBsi(s.bsnFelts));
    assert.deepEqual(decodeBsi(felts), song(s));
  }
});

test('BSI1 carries arbitrary music: off-grid times, mixed durations, any voice', () => {
  const s = { notes: [[0, 1, 0, 1, 0], [7, 333, 127, 127, 15], [1048575, 1048575, 64, 64, 3]], tempo_us: 16777215 };
  assert.deepEqual(decodeBsi(encodeBsi(s)), s);
  assert.throws(() => encodeBsi({ notes: [[1 << 20, 1, 60, 90, 0]], tempo_us: 500000 }), /time/);
  assert.throws(() => encodeBsi({ notes: [[0, 1, 60, 90, 16]], tempo_us: 500000 }), /voice/);
});

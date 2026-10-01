// Golden tests: the offchain engine must reproduce the Cairo reference exactly.
// Fixtures come from Cairo output via scripts/beast_v3_parity.mjs --write; no Scarb needed here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { poseidonHashMany } from '@scure/starknet';
import {
  engine, composeBeast, decodeBsn, bsnToMidi, decodeTokenId, encodeTokenId, genesisTokenId,
  genesisBeast, beastName, hasSound, dropSaltFromBlockHash,
} from '../src/index.js';

const golden = JSON.parse(readFileSync(new URL('./golden.json', import.meta.url)));

for (const [i, c] of golden.cases.entries()) {
  test(`case ${i}: ${beastName(c.beast)} matches Cairo`, () => {
    const r = engine.render(c.beast, c.live);
    const midi = engine.bytesToFelts(engine.toMidiFile(r));
    const bsn = engine.bytesToFelts(engine.encodeBsn(r));
    const got = {
      seed: r.seed.toString(), params: r.params_hash.toString(), score: r.form.score_hash.toString(),
      state: r.state_hash.toString(), events: String(r.form.events.length),
      checksum: engine.eventChecksum(r.form.events).toString(),
      midi_len: String(midi[0]), midi_hash: poseidonHashMany(midi).toString(),
      bsn_len: String(bsn[0]), bsn_hash: poseidonHashMany(bsn).toString(),
    };
    assert.deepEqual(got, c.expected);
  });

  test(`case ${i}: BSN1 decodes back to the canonical notes and MIDI`, () => {
    const song = composeBeast(c.beast, c.live);
    const decoded = decodeBsn(song.bsnFelts);
    assert.equal(decoded.tempo_us, song.params.tempo_us);
    assert.deepEqual(
      decoded.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]),
      song.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice]),
    );
    assert.deepEqual(bsnToMidi(song.bsnFelts), song.midi);
  });
}

test('token IDs match the Beasts V3 Sepolia deployment', () => {
  assert.equal(genesisTokenId(1, 1, 0), 0x7006400010000000000000000001n); // Warlock Genesis
  const gloomfang = { id: 76, prefix: 1, suffix: 1, level: 10, health: 100, shiny: 0, animated: 1, tier: 3, beast_type: 1 };
  assert.equal(encodeTokenId(gloomfang), 0x2e0064000a081000000000000004cn); // "Agony Bane Gloomfang"
  assert.deepEqual(decodeTokenId(0x2e0064000a081000000000000004cn), gloomfang);
  assert.throws(() => decodeTokenId(encodeTokenId({ ...gloomfang, suffix: 0 })), /affix/);
});

test('same Beast keeps its motif while history changes the score', () => {
  const warlock = genesisBeast({ id: 1, prefix: 57, suffix: 15, level: 126, health: 229 });
  const calm = composeBeast(warlock, { adventurers_killed: 0, species_count: 954, rank: 500 });
  const veteran = composeBeast(warlock, { adventurers_killed: 64, scars: 9, summit_held_seconds: 72000, species_count: 954, rank: 1 });
  assert.equal(calm.motifHash, veteran.motifHash);
  assert.notEqual(calm.scoreHash, veteran.scoreHash);
  assert.ok(veteran.params.section_count > calm.params.section_count);
});

test('sound drop is a pure function of the salt and the Beast', () => {
  const salt = dropSaltFromBlockHash('0x1234');
  const b = genesisBeast({ id: 29, prefix: 20, suffix: 5, level: 50, health: 300 });
  assert.equal(hasSound(b, { salt }), hasSound(b, { salt }));
  assert.equal(hasSound(b, { salt, bps: 10000 }), true);
  assert.equal(hasSound(b, { salt, bps: 0 }), false);
  assert.equal(hasSound(genesisBeast({ id: 29 }), { salt, bps: 0 }), true); // Genesis always sings
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { encodeInputs, decodeInputs, encodeGenerationInputs, decodeGenerationInputs,
  applyPerformance, FIELD_P } from '../src/inputs.js';

// Literal field-order oracle also checked independently by Cairo inputs/src/tests.cairo.
const songWire = [4,1,11,2,1,4,60,3,2,4,3,2,1,1,3,5,109,500000,13,1,1,2,0,1,2,0,0,1,37,4,1,17,1,9,1,0,1].map(BigInt);
const checkWire = [4n,0n,18446744073709551615n,1242n,26n,103n,2n,1048575n,127n,3n];
const song = {
  theme: { motif_seed: 11n, tier: 2, register_band: 1 },
  score: { mode_id: 4, tonic_keynum: 60, tier: 3, weakness: 2, voice_count: 4,
    section_count: 3, stretto_lag: 2, use_inversion: true, use_countersubject: true,
    ornament_density: 3, articulation_profile: 5, velocity_ceiling: 109, tempo_us: 500000 },
  treatment: { rhythm_seed: 13n, flip_side: true, development: 1, direction: 2,
    spacing: 0, trill: true, prominence: 2, section_rhythm: false },
  arrangement: { family: 0, identity: { source_species_id: 1n, name_variant_id: 37 },
    channel_count: 4, channel_policy: { kind: 'Seeded', seed: 17n },
    special: { kind: 'Yeti', name_variant_id: 9 }, top_lead: true, balanced: false, weak_ties: true },
};
const recipe = () => structuredClone({ kind: 'Song', song });
test('Song and u64-max Sound Check match literal Cairo wire vectors exactly', () => {
  assert.deepEqual(encodeInputs(recipe()), songWire);
  assert.deepEqual(decodeInputs(songWire), recipe());
  assert.deepEqual(encodeInputs(decodeInputs(checkWire)), checkWire);
  assert.equal(decodeInputs(checkWire).check.identity.source_species_id, (1n << 64n) - 1n);
});
test('generation has its own version and no recipe discriminator', () => {
  const expected = [2n, ...songWire.slice(2)];
  assert.deepEqual(encodeGenerationInputs({ base_song: song }), expected);
  assert.deepEqual(decodeGenerationInputs(expected), { base_song: song });
});
test('all false/true combinations, modes, articulations, enum payloads and zero seeds roundtrip', () => {
  for (let bits = 0; bits < 256; bits++) {
    const x = recipe();
    [x.song.score.use_inversion, x.song.score.use_countersubject, x.song.treatment.flip_side,
      x.song.treatment.trill, x.song.arrangement.top_lead, x.song.arrangement.balanced,
      x.song.arrangement.weak_ties, x.song.treatment.section_rhythm] = Array.from({length:8}, (_,i) => !!(bits & 1 << i));
    x.song.theme.motif_seed = 0n; x.song.treatment.rhythm_seed = FIELD_P - 1n;
    x.song.arrangement.channel_policy = bits % 2 ? { kind: 'Genesis' } : { kind: 'Seeded', seed: 0n };
    x.song.arrangement.special = bits % 2 ? { kind: 'None' } : { kind: 'Yeti', name_variant_id: 1242 };
    assert.deepEqual(decodeInputs(encodeInputs(x)), x);
  }
  for (const mode of [4,5,6,7,8,26]) for (const profile of [0,1,2,3,5]) {
    const x = recipe(); x.song.score.mode_id = mode; x.song.score.articulation_profile = profile;
    assert.deepEqual(decodeInputs(encodeInputs(x)), x);
  }
});
test('rejects wire ambiguity, unsafe numbers, unknown fields, versions, tags and trailing data', () => {
  for (const wire of [[], [2n], [3n], [4n,2n], songWire.slice(0,-1), [...songWire,0n],
    songWire.with(12,2n), songWire.with(2,FIELD_P), songWire.with(25,2n), songWire.with(27,1n << 64n), songWire.with(30,2n)]) {
    assert.throws(() => decodeInputs(wire));
  }
  const x = recipe(); x.song.score.use_inversion = 1; assert.throws(() => encodeInputs(x));
  const y = recipe(); y.song.arrangement.identity.source_species_id = Number.MAX_SAFE_INTEGER + 1;
  assert.throws(() => encodeInputs(y));
  const z = recipe(); z.song.score.shiny = true; assert.throws(() => encodeInputs(z));
});
test('rejects every semantic constraint covered by canonical Cairo validation', () => {
  const mutations = [
    x => x.song.arrangement.identity.source_species_id = 0n,
    x => x.song.arrangement.identity.name_variant_id = 1243,
    x => x.song.score.mode_id = 0, x => x.song.theme.tier = 0, x => x.song.theme.register_band = 3,
    x => x.song.score.tier = 6, x => x.song.score.tonic_keynum = 97,
    x => x.song.score.weakness = 3, x => x.song.score.voice_count = 0,
    x => x.song.score.section_count = 6, x => x.song.score.stretto_lag = 0,
    x => x.song.score.ornament_density = 8, x => x.song.score.articulation_profile = 4,
    x => x.song.score.velocity_ceiling = 0, x => x.song.score.tempo_us = 1048576,
    x => x.song.treatment.development = 3, x => x.song.treatment.direction = 3,
    x => x.song.treatment.spacing = 3, x => x.song.treatment.prominence = 4,
    x => x.song.arrangement.family = 3, x => x.song.arrangement.channel_count = 7,
    x => x.song.arrangement.special.name_variant_id = 1243,
  ];
  for (const mutate of mutations) { const x = recipe(); mutate(x); assert.throws(() => encodeInputs(x)); }
  const check = decodeInputs(checkWire); check.check.tonic_keynum = 104;
  assert.throws(() => encodeInputs(check));
});
test('performance codes0–3 have exact order, units, saturation and immutable originals', () => {
  const x = recipe(); const original = encodeInputs(x);
  for (const [code,tempo,velocity,profile] of [[0,500000,109,5],[1,475000,121,2],
    [2,470000,117,5],[3,455000,124,3]]) {
    const p = applyPerformance(x,code).song.score;
    assert.deepEqual([p.tempo_us,p.velocity_ceiling,p.articulation_profile], [tempo,velocity,profile]);
    assert.deepEqual(encodeInputs(x), original);
  }
  for (const code of [1,2,3]) {
    const check = decodeInputs(checkWire); check.check.tempo_us = 1;
    const p = applyPerformance(check,code).check;
    assert.equal(p.tempo_us,1); assert.equal(p.velocity_ceiling,127);
  }
  assert.throws(() => applyPerformance(x,4)); assert.throws(() => applyPerformance(x,1.5));
});

test('generation codec rejects the previous version1 explicitly', () => {
  assert.throws(() => decodeGenerationInputs([1n]), /unknown generation version/);
});

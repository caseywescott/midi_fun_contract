import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';
import * as ED from '../src/loot_editions.js';
import * as RD from '../src/loot_rounds.js';
import * as CK from '../src/loot_checks.js';
import { O } from '../onchain/orchestra_ref.mjs';

// Source engines and the older published HTML bundle are separately frozen.
// These expectations came only from source at 965a782, never this candidate.
const baseline = JSON.parse(readFileSync(new URL('./fixtures/source-soundtrack-965a782.json', import.meta.url), 'utf8'));
test('all 30 source-engine soundtracks retain their MIDI and bands after the ID shift', () => {
  assert.equal(baseline.sourceCommit, '965a7824f7b8385a9f0829df49451911640bdd1b');
  assert.equal(baseline.cases.length, 360);
  for (const c of baseline.cases) {
    const sp = SPECIES[c.b], seed = BigInt(c.seed);
    const drift = c.drift && { ...c.drift, rhythm: c.drift.rhythm === null ? null : BigInt(c.drift.rhythm), rotate: c.drift.rotate === null ? null : BigInt(c.drift.rotate) };
    let sound, band;
    if (c.kind === 'check') {
      sound = CK.soundCheckMidi(sp, c.mega, seed);
      band = O.choose(O.ORCH.roundPools[sp.type], O.ORCH.roundKinds, sp.id, 2, null);
    } else if (c.kind === 'round') {
      sound = RD.roundMidi(sp, c.mega, seed, drift);
      band = O.choose(O.ORCH.roundPools[sp.type], O.ORCH.roundKinds, sp.id, 2, drift);
    } else {
      sound = ED.editionMidi(sp, c.mega, c.e, seed, drift);
      band = O.band(STYLES[(c.e - 1) % STYLES.length].key, sp.id, c.e, c.p, drift);
    }
    const label = `${sp.id}: ${JSON.stringify(c)}`;
    assert.equal(sound.midi.length, c.midiBytes, label);
    assert.equal(createHash('sha256').update(sound.midi).digest('hex'), c.midiSha256, label);
    assert.deepEqual(Array.from(band), c.instruments, label);
  }
});

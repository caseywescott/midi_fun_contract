import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { loadLab } from './lab-track.mjs';

// Frozen from the published lab at 965a782, BEFORE the ID correction. Never bless
// these expectations from the candidate: they protect the original soundtrack.
const baseline = JSON.parse(readFileSync(new URL('./fixtures/soundtrack-965a782.json', import.meta.url), 'utf8'));
const lab = loadLab(readFileSync(new URL('../public/loot-lab.html', import.meta.url), 'utf8'));
const sha256 = (data) => createHash('sha256').update(data).digest('hex');

test('public IDs 78-107 preserve the original 600 MIDI, band and settings cases', () => {
  assert.equal(baseline.sourceCommit, '965a7824f7b8385a9f0829df49451911640bdd1b');
  assert.equal(baseline.cases.length, 600);
  assert.deepEqual(lab.data.beasts.map((b) => b.id), Array.from({ length: 30 }, (_, i) => 78 + i));
  for (const { state, midiBytes, midiSha256, instruments, settingsSha256 } of baseline.cases) {
    const actual = lab.track(state);
    const label = `${lab.data.beasts[state.b].name}: ${JSON.stringify(state)}`;
    assert.equal(actual.midi.length, midiBytes, label);
    assert.equal(sha256(actual.midi), midiSha256, label);
    assert.deepEqual(Array.from(actual.orch), instruments, label);
    assert.equal(sha256(JSON.stringify(actual.settings)), settingsSha256, label);
  }
});

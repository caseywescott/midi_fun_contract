import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { cyclopsSoundCheckMidi } from '../src/cyclops_sound_check.js';
import { cyclopsSoundCheckSynthSettings, serializeSettings } from '../onchain/tinychip/synth_settings.mjs';

const reference = JSON.parse(readFileSync(new URL('./fixtures/cyclops-504.json', import.meta.url)));

test('Cyclops preserves the complete original 504 MIDI, not a single preset', () => {
  const { midi, info } = cyclopsSoundCheckMidi();
  assert.equal(Buffer.from(midi).toString('hex'), reference.midi_hex);
  assert.equal(createHash('sha256').update(midi).digest('hex'), reference.midi_sha256);
  assert.deepEqual(info.presets, [34, 35, 36, 37, 38, 39, 40, 41]);
  assert.equal(info.tempo, 175);
  assert.equal(info.authored, true);
});

test('Cyclops carries exactly the original eight timbres and three waves', () => {
  const settings = cyclopsSoundCheckSynthSettings();
  // SETTINGS version1 is the same structure as Cairo Serde except its leading version;
  // enum/option encodings differ, so use an independently extracted normalized reference.
  assert.deepEqual(settings, reference.settings);
  assert.equal(settings.waves.length, 3);
  assert.deepEqual(settings.timbres.map((t) => t.slot), [34, 35, 36, 37, 38, 39, 40, 41]);
  assert.equal(settings.timbres.some((t) => t.drum), false);
  assert.ok(serializeSettings(settings).length > 0);
});

test('legacy lab uses the same complete sequence for every named and shiny Cyclops', async () => {
  const { soundCheckMidi } = await import('../src/lab.js');
  for (const prefix of [0, 1, 69]) for (const shiny of [0, 1]) {
    const result = soundCheckMidi({ id: 64, prefix, suffix: prefix ? 18 : 0, shiny });
    assert.equal(Buffer.from(result.midi).toString('hex'), reference.midi_hex);
    assert.equal(result.settingsKey, 'cyclops-check');
  }
});

const effects = JSON.parse(readFileSync(new URL('./fixtures/cyclops-four-effects.json', import.meta.url)));
test('Cyclops follows all four standard Check performances without replacing the eight sounds', () => {
  const seen = new Set();
  for (const expected of effects) {
    const {midi, info} = cyclopsSoundCheckMidi(expected.fx);
    assert.equal(Buffer.from(midi).toString('hex'), expected.midiHex);
    const hash = createHash('sha256').update(midi).digest('hex');
    assert.equal(hash, expected.hash);
    assert.equal(info.tempo_us, 342857 - [0,25000,30000,45000][expected.fx]);
    assert.deepEqual(info.presets, [34,35,36,37,38,39,40,41]);
    seen.add(hash);
  }
  assert.equal(seen.size, 4);
});

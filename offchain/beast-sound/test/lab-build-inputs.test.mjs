import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { labBuildInputs, PLAYER_REVISION } from '../onchain/lab-build-inputs.mjs';

test('lab builds require the engine and upstream checkout inputs', () => {
  assert.throws(() => labBuildInputs(), /usage: <engine/);
  assert.throws(() => labBuildInputs('engine.js'), /onchain-midi-player checkout/);
});

test('lab builds reject upstream source drift before generating a page', () => {
  const root = mkdtempSync(join(tmpdir(), 'beast-lab-build-inputs-'));
  try {
    mkdirSync(join(root, 'player'));
    writeFileSync(join(root, 'player/notes.js'), 'export function mount() {}');
    assert.throws(() => labBuildInputs('engine.js', root), (error) =>
      error.message.includes('notes.js does not match') && error.message.includes(PLAYER_REVISION));
  } finally { rmSync(root, { recursive: true, force: true }); }
});

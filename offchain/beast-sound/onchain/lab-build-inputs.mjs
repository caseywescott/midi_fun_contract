import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';

export const PLAYER_REVISION = 'e3ad210fbf2caf4cd7940b2dee91375d073b65ac';
const SOURCES = {
  'notes.js': '2023822239385a869737552295c751f6e6f34d152909e2b12148433aa6fac3e0',
  'settings.js': '95541554ff0340347776696dd641d8b911a7acf28ed42770352922dc970b77fb',
};

// Keep Casey's existing engine-file + upstream-checkout build inputs. Only generated HTML
// contains the bundled upstream code; this repository does not maintain another source copy.
export function labBuildInputs(engineFile, playerCheckout) {
  if (!engineFile || !playerCheckout) throw new Error('usage: <engine .min.js> <onchain-midi-player checkout>');
  const paths = {};
  for (const [name, expected] of Object.entries(SOURCES)) {
    const path = resolve(playerCheckout, 'player', name);
    const actual = createHash('sha256').update(readFileSync(path)).digest('hex');
    if (actual !== expected) throw new Error(`${name} does not match onchain-midi-player ${PLAYER_REVISION}; use that revision to reproduce these labs`);
    paths[name] = path;
  }
  // The repository already carries this identical Apache-2.0 text for TinySynth. Include it
  // with the renderer's attribution so a downloaded standalone page retains the same notices.
  const license = readFileSync(new URL('./vendor/webaudio-tinysynth/LICENSE', import.meta.url), 'utf8');
  const notice = `<!--\nonchain-midi-player notes and settings\nCopyright 2026 Provable Games\nSource: https://github.com/Provable-Games/onchain-midi-player/tree/${PLAYER_REVISION}/player\nLicensed under Apache-2.0:\n${license}\n-->`;
  return { tiny: readFileSync(resolve(engineFile), 'utf8'), notesPath: paths['notes.js'], settingsPath: paths['settings.js'], notice };
}

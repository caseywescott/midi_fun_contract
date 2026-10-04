// Parity: the self-contained Beast MIDI (programs, pan, drums), JS (offchain/beast-sound/src/full_midi.js)
// against Cairo (contracts/beast_music: full_midi_parity_fixture).
//   (cd contracts/beast_music && scarb test -- --include-ignored --filter full_midi_parity_fixture | grep FULL > /tmp/full.txt)
//   node scripts/full_midi_parity.mjs /tmp/full.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { beastFullMidi } from '../offchain/beast-sound/src/full_midi.js';

// Must match full_midi_parity_fixture in contracts/beast_music/src/tests.cairo.
const W = { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 };
export const CASES = [
  [W, { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954 }],
  [W, { adventurers_killed: 40, scars: 9, summit_held_seconds: 90000, rank: 1, species_count: 954 }],
  [{ id: 6, prefix: 10, suffix: 3, level: 40, health: 300, shiny: 0, animated: 0, tier: 2, beast_type: 0 }, { adventurers_killed: 20, scars: 2, summit_held_seconds: 0, rank: 4, species_count: 300 }],
  [{ id: 11, prefix: 30, suffix: 9, level: 70, health: 120, shiny: 1, animated: 0, tier: 3, beast_type: 0 }, { adventurers_killed: 5, scars: 9, summit_held_seconds: 0, rank: 50, species_count: 900 }],
  [{ id: 16, prefix: 44, suffix: 12, level: 12, health: 80, shiny: 0, animated: 1, tier: 4, beast_type: 0 }, { adventurers_killed: 1, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 0 }],
  [{ id: 21, prefix: 0, suffix: 0, level: 3, health: 40, shiny: 0, animated: 0, tier: 5, beast_type: 0 }, { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 0 }],
  [{ id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 }, { adventurers_killed: 500, scars: 63, summit_held_seconds: 0, rank: 1, species_count: 1243 }],
];
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.includes('FULL'));
if (lines.length !== CASES.length) throw new Error(`expected ${CASES.length} FULL lines, got ${lines.length}`);
let failures = 0;
CASES.forEach(([b, live], i) => {
  const r = E.render(b, live), midi = E.bytesToFelts(beastFullMidi(r, E.formLength));
  const js = { len: String(midi[0]), hash: poseidonHashMany(midi).toString() };
  const cairo = Object.fromEntries(lines[i].trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  for (const k of ['len', 'hash']) if (js[k] !== cairo[k]) { failures++; console.log(`case ${i} ${k} FAIL js=${js[k]} cairo=${cairo[k]}`); }
  console.log(`case ${i}: tier ${r.params.tier}, ${r.params.voice_count} voices, ${js.len} bytes`);
});
console.log(failures === 0 ? `FULL MIDI PARITY: all ${CASES.length} cases match Cairo` : `FULL MIDI PARITY: ${failures} mismatches`);
process.exit(failures ? 1 : 0);

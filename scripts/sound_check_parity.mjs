// Parity: the Sound Check (track 0) of every species, no special name normal and shiny, and one named
// Beast each: the lab's `soundCheckMidi` against Cairo (sound_check.cairo via tracks.cairo).
//   cd contracts/beast_music && for i in 0 1 2; do scarb test -- --include-ignored --filter sound_check_parity_fixture_$i; done | grep '^SC' > /tmp/sc.txt
//   node scripts/sound_check_parity.mjs /tmp/sc.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { nameFromVariant, soundCheckMidi, speciesTier, speciesType } from '../offchain/beast-sound/src/lab.js';

const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('SC '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const id = Number(c.case), shiny = Number(c.shiny);
  const b = { id, ...nameFromVariant(Number(c.name)), level: 1, health: 100, shiny, animated: 0, tier: speciesTier(id), beast_type: speciesType(id) };
  const midi = E.bytesToFelts(soundCheckMidi(b, E).midi);
  if (String(midi[0]) !== c.midi_len || poseidonHashMany(midi).toString() !== c.midi) { failures++; console.log(`case ${id} name ${c.name} shiny ${shiny}: js ${midi[0]} cairo ${c.midi_len}`); }
}
const ok = failures === 0 && lines.length === 225;
console.log(`SOUND CHECK PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(ok ? 0 : 1);

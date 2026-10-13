// Parity: bought tracks (a seed on the Beast's key and the species' theme), two per species (no
// special name, and named + shiny), the lab's `sampleTrackMidi` with that seed against Cairo
// (genesis.cairo seeded_track_smf_bytes via tracks.cairo track 3).
//   FIXTURE=seeded_parity_fixture_ sh scripts/genesis_parity_cairo.sh /tmp/seed.txt && node scripts/seeded_parity.mjs /tmp/seed.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { GENESIS_DEFAULTS, sampleTrackMidi, speciesTier, speciesType } from '../offchain/beast-sound/src/lab.js';

const v11 = createEngineV11(E);
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('SEED '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const id = Number(c.case), name = Number(c.name), shiny = Number(c.shiny), seed = BigInt(c.seed);
  const b = { id, prefix: 0, suffix: 0, level: 1, health: 100, shiny, animated: 0, tier: speciesTier(id), beast_type: speciesType(id) };
  const midi = E.bytesToFelts(sampleTrackMidi(b, { species_count: 1 }, { ...GENESIS_DEFAULTS, name, seed }, E, v11).midi);
  if (String(midi[0]) !== c.midi_len || poseidonHashMany(midi).toString() !== c.midi) { failures++; console.log(`case ${id} name ${name} shiny ${shiny} seed ${seed}: js ${midi[0]} cairo ${c.midi_len}`); }
}
const ok = failures === 0 && lines.length === 150;
console.log(`SEEDED PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(ok ? 0 : 1);

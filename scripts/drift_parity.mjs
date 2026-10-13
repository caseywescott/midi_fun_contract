// Parity: the layered drift with block hashes (lab stand-in hashes) on the Species Song and on a named,
// shiny bought track, the lab's `sampleTrackMidi` (driftMode v2, blockHashes) against Cairo
// (drift.cairo through tracks.cairo).
//   FIXTURE=drift_parity_fixture_ sh scripts/genesis_parity_cairo.sh /tmp/drift.txt && node scripts/drift_parity.mjs /tmp/drift.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { GENESIS_DEFAULTS, genesisMidi, sampleTrackMidi, speciesTier, speciesType } from '../offchain/beast-sound/src/lab.js';

const v11 = createEngineV11(E);
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('DRIFT '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const id = Number(c.case), name = Number(c.name), shiny = Number(c.shiny), seed = BigInt(c.seed), day = Number(c.day);
  const drift = { epoch: day, driftMode: 'v2', blockHashes: true };
  const b = { id, prefix: 0, suffix: 0, level: 1, health: 100, shiny, animated: 0, tier: speciesTier(id), beast_type: speciesType(id) };
  const bytes = seed === 0n ? genesisMidi(id, shiny, E, v11, drift).midi : sampleTrackMidi(b, { species_count: 1 }, { ...GENESIS_DEFAULTS, name, seed, ...drift }, E, v11).midi;
  const midi = E.bytesToFelts(bytes);
  if (String(midi[0]) !== c.midi_len || poseidonHashMany(midi).toString() !== c.midi) { failures++; console.log(`case ${id} name ${name} seed ${seed} day ${day}: js ${midi[0]} cairo ${c.midi_len}`); }
}
const ok = failures === 0 && lines.length === 150;
console.log(`DRIFT PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(ok ? 0 : 1);

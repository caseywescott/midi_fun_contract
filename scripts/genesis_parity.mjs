// Parity: the Genesis Track of every species, normal and shiny, as the Beast Sound lab plays it
// (`genesisMidi`, offchain/beast-sound/src/lab.js: spread keys, chosen themes, default swaps, Genesis
// channels, weak-beat ties, no pluck on top, balanced mix) against Cairo
// (contracts/beast_music/src/composition/genesis.cairo, via genesis_tests.cairo).
//   sh scripts/genesis_parity_cairo.sh /tmp/gen.txt && node scripts/genesis_parity.mjs /tmp/gen.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { genesisMidi } from '../offchain/beast-sound/src/lab.js';

const v11 = createEngineV11(E);
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('GEN '));
if (lines.length !== 150) console.log(`warning: expected 150 GEN lines, got ${lines.length}`);
let failures = 0;
for (const line of lines) {
  const cairo = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const { midi: bytes } = genesisMidi(Number(cairo.case), cairo.shiny === '1', E, v11);
  const midi = E.bytesToFelts(bytes);
  const js = { midi_len: String(midi[0]), midi: poseidonHashMany(midi).toString() };
  for (const k of Object.keys(js)) if (js[k] !== cairo[k]) { failures++; console.log(`case ${cairo.case} shiny ${cairo.shiny} ${k}: js ${js[k]} cairo ${cairo[k]}`); }
}
console.log(failures === 0 && lines.length === 150 ? `GENESIS PARITY: all ${lines.length} tracks match Cairo` : `GENESIS PARITY: ${failures} mismatches over ${lines.length} tracks`);
process.exit(failures === 0 && lines.length === 150 ? 0 : 1);

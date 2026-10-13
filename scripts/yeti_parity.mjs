// Parity: the Yeti special (ornaments by profile, avalanche, rock groove) on Yeti name tracks covering
// every ornament placement, the lab (`sampleTrackMidi`) against Cairo (yeti.cairo via tracks.cairo).
//   cd contracts/beast_music && for i in 0 1; do scarb test -- --include-ignored --filter yeti_parity_fixture_$i; done | grep '^YETI' > /tmp/yeti.txt
//   node scripts/yeti_parity.mjs /tmp/yeti.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { GENESIS_DEFAULTS, sampleTrackMidi, speciesTier, speciesType, yetiOrnamentProfile, nameFromVariant } from '../offchain/beast-sound/src/lab.js';

const v11 = createEngineV11(E);
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('YETI '));
let failures = 0;
const placements = new Set();
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const name = Number(c.name), shiny = Number(c.shiny);
  placements.add(yetiOrnamentProfile({ id: 68, ...nameFromVariant(name) }).placement);
  const b = { id: 68, prefix: 0, suffix: 0, level: 1, health: 100, shiny, animated: 0, tier: speciesTier(68), beast_type: speciesType(68) };
  const midi = E.bytesToFelts(sampleTrackMidi(b, { species_count: 1 }, { ...GENESIS_DEFAULTS, name }, E, v11).midi);
  if (String(midi[0]) !== c.midi_len || poseidonHashMany(midi).toString() !== c.midi) { failures++; console.log(`name ${name} shiny ${shiny}: js ${midi[0]} bytes, cairo ${c.midi_len}`); }
}
const ok = failures === 0 && lines.length === 16 && placements.size === 6;
console.log(`YETI PARITY: ${lines.length - failures}/${lines.length} match, placements covered ${placements.size}/6`);
process.exit(ok ? 0 : 1);

// Parity: the Beast Special Song (name track) of two special names per species, one normal and one
// shiny, as the Beast Sound lab plays it (`sampleTrackMidi` at that name, seed 0, Genesis defaults;
// offchain/beast-sound/src/lab.js) against Cairo (beasts/beast_composer/src/composition/tracks.cairo,
// composed from the packed composer inputs, via name_track_tests.cairo).
//   FIXTURE=name_parity_fixture_ sh scripts/genesis_parity_cairo.sh /tmp/name.txt && node scripts/name_parity.mjs /tmp/name.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { GENESIS_DEFAULTS, sampleTrackMidi, speciesTier, speciesType } from '../offchain/beast-sound/src/lab.js';

const v11 = createEngineV11(E);
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('NAME '));
if (lines.length !== 150) console.log(`warning: expected 150 NAME lines, got ${lines.length}`);
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const id = Number(c.case), name = Number(c.name), shiny = Number(c.shiny);
  if (name !== 1 + ((id * 37 + shiny * 611) % 1242)) { failures++; console.log(`case ${id}: unexpected name ${name}`); }
  const b = { id, prefix: 0, suffix: 0, level: 1, health: 100, shiny, animated: 0, tier: speciesTier(id), beast_type: speciesType(id) };
  const { midi: bytes } = sampleTrackMidi(b, { species_count: 1 }, { ...GENESIS_DEFAULTS, name }, E, v11);
  const midi = E.bytesToFelts(bytes);
  const js = { midi_len: String(midi[0]), midi: poseidonHashMany(midi).toString() };
  for (const k of Object.keys(js)) if (js[k] !== c[k]) { failures++; console.log(`case ${id} name ${name} shiny ${shiny} ${k}: js ${js[k]} cairo ${c[k]}`); }
}
const ok = failures === 0 && lines.length === 150;
console.log(ok ? `NAME PARITY: all ${lines.length} tracks match Cairo` : `NAME PARITY: ${failures} mismatches over ${lines.length} tracks`);
process.exit(ok ? 0 : 1);

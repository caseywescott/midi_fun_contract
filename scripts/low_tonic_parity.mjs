// Parity: low-tonic Songs, a species' Genesis Track recipe (four voices and the countersubject) on a
// low tonic, spread wide (spacing 0), normal (1) or close (2), composed whole octaves up when its
// lowest voice would be placed under C1: the lab's `genesisMidi` with that tonic and spacing against
// Cairo (beasts/beast_composer/src/low_tonic_tests.cairo, low_tonic_parity_fixture_*).
//   cd beasts/beast_composer && for i in 0 1 2 3 4 5; do scarb test -- low_tonic_parity_fixture_$i --include-ignored; done | grep '^LOW' > /tmp/low.txt
//   node scripts/low_tonic_parity.mjs /tmp/low.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { genesisMidi } from '../offchain/beast-sound/src/lab.js';

const v11 = createEngineV11(E);
const SPACING = ['wide', 'normal', 'close'];
// genesisMidi's composer with the Song's tonic and spacing in place of the Genesis Track's (Cairo
// sets `score.tonic_keynum` and `treatment.spacing` of `genesis_song_inputs`)
const moved = (tonic, spacing) => ({
  render: (b, live, opts) => {
    const o = opts.override || {};
    return v11.render(b, live, { ...opts, override: { ...o, params: { ...(o.params || {}), tonic_keynum: tonic }, tr: { ...(o.tr || {}), spacing } } });
  },
});
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('LOW '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const midi = E.bytesToFelts(genesisMidi(Number(c.case), false, E, moved(Number(c.tonic), SPACING[Number(c.spacing)])).midi);
  if (String(midi[0]) !== c.midi_len || poseidonHashMany(midi).toString() !== c.midi) { failures++; console.log(`case ${c.case} tonic ${c.tonic} spacing ${c.spacing}: js ${midi[0]} cairo ${c.midi_len}`); }
}
const ok = failures === 0 && lines.length === 72;
console.log(`LOW TONIC PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(ok ? 0 : 1);

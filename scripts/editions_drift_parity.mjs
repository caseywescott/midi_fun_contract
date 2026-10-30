// Parity: Monthly Track Editions on a day of drift. The Cairo fixture (beasts/beast_composer
// editions_tests editions_drift_parity_fixture) prints the day's drift and the file; this replays
// the drift through offchain/beast-sound/src/editions_lite.js and compares.
//   cd beasts/beast_composer && scarb test -- editions_drift_parity_fixture --include-ignored | grep '^EDD' > /tmp/edd.txt
//   node scripts/editions_drift_parity.mjs /tmp/edd.txt
import { readFileSync } from 'node:fs';
import { editionMidi } from '../offchain/beast-sound/src/editions_lite.js';
import { speciesRecords } from '../offchain/beast-sound/onchain/editions_cairo.mjs';

const SP = speciesRecords();
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('EDD '));
let failures = 0, echoes = 0;
const knobs = new Set(), layers = { rhythm: 0, rotate: 0 };
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const drift = { rhythm: c.rhythm === '0' ? null : BigInt(c.rhythm), rotate: c.rotate === '0' ? null : BigInt(c.rotate), dayKnob: +c.knob, delta: +c.delta };
  if (c.echo === '1') echoes++;
  knobs.add(drift.dayKnob); if (drift.rhythm !== null) layers.rhythm++; if (drift.rotate !== null) layers.rotate++;
  const js = Buffer.from(editionMidi(SP[+c.sp - 1], c.shiny === '1', +c.e, BigInt(c.seed), drift, c.echo === '1').midi).toString('hex');
  if (js !== c.hex) {
    failures++;
    let i = 0; while (i < js.length && js[i] === c.hex[i]) i++;
    console.log(`edition ${c.e} species ${c.sp} knob ${c.knob} rhythm ${drift.rhythm !== null} rotate ${drift.rotate !== null}: js ${js.length / 2} B, cairo ${c.len} B, first difference at byte ${Math.floor(i / 2)}`);
  }
}
console.log(`knobs covered: ${[...knobs].sort().join(',')}; new melodies ${layers.rhythm}, rotations ${layers.rotate}, echoes ${echoes}`);
console.log(`EDITIONS DRIFT PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(failures === 0 && lines.length > 0 ? 0 : 1);

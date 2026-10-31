// Parity: the chip echo (sound presets 2 and 3) on Genesis Tracks, plain and mega. The Cairo
// fixture (beasts/beast_composer song_inputs_tests echo_parity_fixture) prints each file; this
// plays the same tracks through offchain/beast-sound/src/lab.js genesisMidi with `echo` and compares.
//   cd beasts/beast_composer && scarb test -- echo_parity_fixture --include-ignored | grep '^ECHO' > /tmp/echo.txt
//   node scripts/echo_parity.mjs /tmp/echo.txt
import { readFileSync } from 'node:fs';
import { engine as E } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { genesisMidi } from '../offchain/beast-sound/src/lab.js';

const v11 = createEngineV11(E);
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('ECHO '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const js = Buffer.from(genesisMidi(+c.id, c.shiny === '1', E, v11, { echo: true }).midi).toString('hex');
  if (js !== c.hex) {
    failures++;
    let i = 0; while (i < js.length && js[i] === c.hex[i]) i++;
    console.log(`species ${c.id} shiny ${c.shiny}: js ${js.length / 2} B, cairo ${c.len} B, first difference at byte ${Math.floor(i / 2)}`);
  }
}
console.log(`ECHO PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(failures === 0 && lines.length > 0 ? 0 : 1);

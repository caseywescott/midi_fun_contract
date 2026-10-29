// Parity: the Monthly Track Editions port (beasts/beast_composer/src/composition/editions.cairo)
// against offchain/beast-sound/src/editions_lite.js, case by case from the ED lines the Cairo fixture
// prints (whole files in hex).
//   sh scripts/editions_parity_cairo.sh /tmp/ed.txt && node scripts/editions_parity.mjs /tmp/ed.txt
import { readFileSync } from 'node:fs';
import { editionMidi } from '../offchain/beast-sound/src/editions_lite.js';
import { speciesRecords } from '../offchain/beast-sound/onchain/editions_cairo.mjs';

const SP = speciesRecords();
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('ED '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const e = +c.e, sp = +c.sp, shiny = c.shiny === '1', seed = c.seed;
  const js = Buffer.from(editionMidi(SP[sp - 1], shiny, e, 'seed:' + seed).midi).toString('hex');
  if (js !== c.hex) {
    failures++;
    let i = 0; while (i < js.length && js[i] === c.hex[i]) i++;
    const at = Math.floor(i / 2);
    console.log(`edition ${e} species ${sp} shiny ${+shiny} seed ${seed}: js ${js.length / 2} B, cairo ${c.len} B, first difference at byte ${at}`);
    console.log('  js    ' + js.slice(Math.max(0, i - 40), i + 40));
    console.log('  cairo ' + c.hex.slice(Math.max(0, i - 40), i + 40));
  }
}
console.log(`EDITIONS PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(failures === 0 && lines.length > 0 ? 0 : 1);

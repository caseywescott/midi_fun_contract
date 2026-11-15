// Sound Checks parity: the Cairo port (loot/loot_composer/src/checks.cairo) against soundCheckMidi
// (offchain/loot-sound/src/loot_checks.js), case by case from the CK lines the fixture prints.
//   KIND=checks PREFIX=CK sh scripts/rounds_parity_cairo.sh /tmp/ck.txt && node scripts/checks_parity.mjs /tmp/ck.txt
import { readFileSync } from 'node:fs';
import { SPECIES } from '../offchain/loot-sound/src/loot_species.js';
import { soundCheckMidi } from '../offchain/loot-sound/src/loot_checks.js';

const cases = JSON.parse(readFileSync(new URL('./checks_parity_cases.json', import.meta.url), 'utf8'));
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('CK '));
let failures = 0;
const seen = new Set();
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const x = cases[+c.i];
  seen.add(+c.i);
  const js = Buffer.from(soundCheckMidi(SPECIES.find((s) => s.id === x.sp), x.mega, BigInt(x.take)).midi).toString('hex');
  if (js !== c.hex) {
    failures++;
    let k = 0; while (k < js.length && js[k] === c.hex[k]) k++;
    console.log(`case ${c.i} species ${x.sp} mega ${+x.mega} p ${x.p}: js ${js.length / 2} B, cairo ${c.len} B, first difference at byte ${Math.floor(k / 2)}`);
    console.log('  js    ' + js.slice(Math.max(0, k - 40), k + 40));
    console.log('  cairo ' + (c.hex || '').slice(Math.max(0, k - 40), k + 40));
  }
}
console.log(`CHECKS PARITY: ${lines.length - failures}/${lines.length} match (${seen.size} of ${cases.length} cases run)`);
process.exit(failures === 0 && lines.length > 0 ? 0 : 1);

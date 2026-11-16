// Rounds parity: the Cairo port (loot/loot_composer/src/rounds.cairo) against roundMidi
// (offchain/loot-sound/src/loot_rounds.js), case by case from the RD lines the fixture prints.
//   sh scripts/rounds_parity_cairo.sh /tmp/rd.txt && node scripts/rounds_parity.mjs /tmp/rd.txt
import { readFileSync } from 'node:fs';
import { SPECIES } from '../offchain/loot-sound/src/loot_species.js';
import { musicalId } from '../offchain/loot-sound/src/loot_beasts.js';
import { roundMidi } from '../offchain/loot-sound/src/loot_rounds.js';

const REF = process.env.REF || '/Volumes/Extreme SSD/Generative_Music_Series/midi_fun_contract-ref101';
const L = await import(REF + '/offchain/beast-sound/src/lab.js');
const cases = JSON.parse(readFileSync(new URL('./rounds_parity_cases.json', import.meta.url), 'utf8'));
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('RD '));
let failures = 0;
const seen = new Set();
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const x = cases[+c.i];
  seen.add(+c.i);
  const sp = SPECIES.find((s) => s.id === x.sp);
  const d = x.day ? L.drift2({ id: musicalId(x.sp), prefix: 0, suffix: 0 }, x.day, L.dayAnchor()) : null;
  const js = Buffer.from(roundMidi(sp, x.mega, BigInt(x.seed), d).midi).toString('hex');
  if (js !== c.hex) {
    failures++;
    let k = 0; while (k < js.length && js[k] === c.hex[k]) k++;
    console.log(`case ${c.i} species ${x.sp} mega ${+x.mega} p ${x.p} day ${x.day}: js ${js.length / 2} B, cairo ${c.len} B, first difference at byte ${Math.floor(k / 2)}`);
    console.log('  js    ' + js.slice(Math.max(0, k - 40), k + 40));
    console.log('  cairo ' + (c.hex || '').slice(Math.max(0, k - 40), k + 40));
  }
}
console.log(`ROUNDS PARITY: ${lines.length - failures}/${lines.length} match (${seen.size} of ${cases.length} cases run)`);
process.exit(failures === 0 && lines.length > 0 ? 0 : 1);

// Parity: the Loot editions port (loot/loot_composer/src/editions.cairo) against
// offchain/loot-sound/src/loot_editions.js, case by case (scripts/editions_cases.json) from the ED
// lines the Cairo fixture prints (whole files in hex). Also reports which features the cases reach.
//   sh scripts/editions_parity_cairo.sh /path/ed.txt && node scripts/editions_parity.mjs /path/ed.txt
import { readFileSync } from 'node:fs';
import { editionMidi, editionGenome } from '../offchain/loot-sound/src/loot_editions.js';
import { SPECIES } from '../offchain/loot-sound/src/loot_species.js';

const cases = JSON.parse(readFileSync(new URL('./editions_cases.json', import.meta.url), 'utf8'));
const lines = process.argv[2] ? readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('ED ')) : [];
const got = new Map(lines.map((l) => { const c = Object.fromEntries(l.trim().split(/\s+/).slice(1).map((kv) => kv.split('='))); return [+c.i, c]; }));
let ok = 0, bad = 0;
const seen = { style: new Set(), intro: new Set(), walk: 0, alt: 0, gliss: 0, doubled: 0, drumFill: 0, accLow: 0, arp32: 0, form: new Set(), knob: new Set(), parts: new Set(), quicker: 0, theme: new Set(), mega: 0 };
for (const c of cases) {
  const sp = SPECIES.find((s) => s.id === c.sp);
  const drift = c.drift && { ...c.drift, rhythm: c.drift.rhythm === null ? null : BigInt(c.drift.rhythm), rotate: c.drift.rotate === null ? null : BigInt(c.drift.rotate) };
  const o = editionMidi(sp, c.mega, c.e, BigInt(c.seed), drift);
  const js = Buffer.from(o.midi).toString('hex'), inf = o.info;
  seen.style.add(editionGenome(c.e).style); seen.intro.add(inf.introBars); seen.walk += inf.walking ? 1 : 0; seen.alt += inf.altKind >= 0 ? 1 : 0;
  seen.gliss += inf.gliss.length; seen.doubled += inf.doubled.some(Boolean) ? 1 : 0; seen.drumFill += inf.drumEnds.some((x) => x === 1) ? 1 : 0;
  seen.accLow += inf.accompLow ? 1 : 0; seen.arp32 += inf.spread.steps.includes(60) ? 1 : 0; seen.form.add(inf.form); seen.knob.add(c.drift ? c.drift.dayKnob : 6);
  seen.parts.add(inf.parts.length); seen.quicker += inf.quicker ? 1 : 0; seen.theme.add(inf.theme); seen.mega += c.mega ? 1 : 0;
  const g = got.get(c.i);
  if (!g) continue;
  if (js === g.hex) { ok++; continue; }
  bad++;
  let i = 0; while (i < js.length && js[i] === g.hex[i]) i++;
  console.log(`case ${c.i} (e ${c.e} sp ${c.sp} mega ${+c.mega} p ${c.p} day ${c.day}): js ${js.length / 2} B, cairo ${g.len} B, first difference at byte ${Math.floor(i / 2)}`);
  console.log('  js    ' + js.slice(Math.max(0, i - 40), i + 40));
  console.log('  cairo ' + g.hex.slice(Math.max(0, i - 40), i + 40));
}
const f = (s) => [...s].sort((a, b) => (a > b ? 1 : -1)).join(' ');
console.log(`coverage: ${seen.style.size} styles, intro bars {${f(seen.intro)}}, ${seen.walk} walking, ${seen.alt} second leads, ${seen.gliss} glissandi, ${seen.doubled} doubled, ${seen.drumFill} drum fills, ${seen.accLow} accomp low, ${seen.arp32} with 32nds, ${seen.form.size} forms, knobs {${f(seen.knob)}}, part counts {${f(seen.parts)}}, ${seen.quicker} quicker, ${seen.theme.size} themes, ${seen.mega} mega`);
console.log(`EDITIONS PARITY: ${ok}/${got.size} match (${cases.length} cases defined)`);
process.exit(bad === 0 && got.size > 0 ? 0 : 1);

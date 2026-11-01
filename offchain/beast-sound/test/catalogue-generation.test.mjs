import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {generateCatalogue} from '../../../scripts/check_catalogue.mjs';
import {CHECK_CATALOGUE} from '../src/sound_check_catalogue_data.js';

const clone=()=>structuredClone(CHECK_CATALOGUE);
test('valid75-species catalogue still generates byte-identical Cairo',()=>{
  assert.equal(generateCatalogue(CHECK_CATALOGUE),readFileSync(new URL('../../../beasts/beast_composer/src/composition/check_catalogue_data.cairo',import.meta.url),'utf8'));
});
const badRows=[
  ['finalNotes underflow',r=>r.finalNotes=3,/finalNotes/],
  ['finalNotes overflow',r=>r.finalNotes=17,/finalNotes/],
  ['fractional finalNotes',r=>r.finalNotes=4.5,/finalNotes/],
  ['missing finalNotes',r=>delete r.finalNotes,/finalNotes/],
  ['unsupported program',r=>r.program=11,/program/],
  ['wrong family program',r=>r.program=1,/species family bank/],
  ['mega program as normal',r=>r.program=65,/species family bank/],
  ['negative program',r=>r.program=-1,/program/],
  ['program overflow',r=>r.program=128,/program/],
  ['fractional program',r=>r.program=1.5,/program/],
  ['coerced program',r=>r.program='9',/program/],
  ['unsupported mega',r=>r.mega=51,/mega/],
  ['coerced mega',r=>r.mega='65',/mega/],
  ['unsupported register',r=>r.register=49,/register/],
  ['missing register',r=>delete r.register,/register/],
  ['zero tempo',r=>r.tempo_us=0,/tempo_us/],
  ['20bit tempo overflow',r=>r.tempo_us=0x100000,/tempo_us/],
  ['fractional tempo',r=>r.tempo_us=100.5,/tempo_us/],
  ['nonfinite tempo',r=>r.tempo_us=Infinity,/tempo_us/],
  ['unsupported pan',r=>r.pan=2,/pan/],
  ['coerced pan',r=>r.pan='true',/pan/],
  ['missing pan',r=>delete r.pan,/pan/],
  ['short held',r=>r.held=[4],/held/],
  ['held overflow',r=>r.held=[0,16],/held/],
  ['negative held',r=>r.held=[-1,0],/held/],
  ['fractional held',r=>r.held=[0,0.5],/held/],
  ['head overflow',r=>r.head[0]=12,/head/],
  ['response underflow',r=>r.response[0]=-5,/response/],
  ['fractional head',r=>r.head[0]=0.5,/head/],
  ['sparse head',r=>delete r.head[0],/head/],
  ['short response',r=>r.response.pop(),/response/],
  ['missing head',r=>delete r.head,/head/],
  ['rhythm slot overflow',r=>r.rhythm[0]=600,/rhythm/],
  ['unsupported rhythm unit',r=>r.rhythm=[180,180,240,360],/rhythm/],
  ['wrong rhythm total',r=>r.rhythm=[120,120,120,120],/rhythm/],
  ['sparse rhythm',r=>delete r.rhythm[0],/rhythm/],
  ['fractional species',r=>r.species=1.5,/species/],
  ['wrong species order',r=>r.species=2,/species/],
  ['unknown phrase',r=>r.phrase='unknown',/phrase/],
  ['multiline name',r=>r.name='Warlock\nnew code',/name/],
];
for(const [label,mutate,error] of badRows)test(`rejects malformed catalogue: ${label}`,()=>{
  const rows=clone();mutate(rows[0]);assert.throws(()=>generateCatalogue(rows),error);
});
test('rejects missing/extra species and sparse or nonobject rows',()=>{
  const short=clone();short.pop();assert.throws(()=>generateCatalogue(short),/exactly 75/);
  const long=clone();long.push(long[0]);assert.throws(()=>generateCatalogue(long),/exactly 75/);
  const sparse=clone();delete sparse[1];assert.throws(()=>generateCatalogue(sparse),/row 2.*object/);
  const wrong=clone();wrong[0]=null;assert.throws(()=>generateCatalogue(wrong),/row 1.*object/);
});
test('packed boundary values are accepted without field spill',()=>{
  const rows=clone();Object.assign(rows[0],{finalNotes:4,held:[0,15],tempo_us:0xfffff,pan:1,mega:65});
  rows[0].head[0]=11;rows[0].response[0]=-4;
  const output=generateCatalogue(rows),meta=BigInt(output.match(/^    \((\d+),/m)[1]);
  assert.ok(meta>=0n&&meta<2n**64n);
  const lower=clone();Object.assign(lower[0],{finalNotes:16,tempo_us:1,pan:0});assert.doesNotThrow(()=>generateCatalogue(lower));
});

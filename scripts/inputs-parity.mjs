// Direct normalized-input score parity; no Beast/token reconstruction.
// Run filtered normalized_score_parity tests, then pass their captured log here.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createCoreEngine } from '../offchain/beast-sound/src/engine.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { poseidonHashMany } from '../offchain/beast-sound/src/poseidon_lite.js';
import { encodeInputs } from '../offchain/beast-sound/src/inputs.js';
import { normalizedCase, SCORE_CASE_COUNT } from '../offchain/beast-sound/test/normalized-cases.mjs';
const V=createEngineV11(createCoreEngine({poseidonHashMany}));
const lines=readFileSync(process.argv[2],'utf8').split('\n').filter(l=>l.startsWith('INPUT_SCORE '));
assert.equal(lines.length,SCORE_CASE_COUNT,'complete normalized score case set');
const seen=new Set();
for (const line of lines) {
  const row=Object.fromEntries(line.split(/\s+/).slice(1).map(x=>x.split('=')));
  const index=Number(row.case); assert(!seen.has(index),'duplicate case'); seen.add(index);
  const song=normalizedCase(index), r=V.renderInputs(song);
  const flat=[...r.form.events].sort((a,b)=>a.voice_id-b.voice_id||a.time-b.time)
    .flatMap(e=>[e.time,e.duration,e.pitch,e.velocity,e.voice_id].map(BigInt));
  const expected={notes:r.form.events.length,ticks:r.form.section_ticks,
    events:poseidonHashMany(flat),wire:poseidonHashMany(encodeInputs({kind:'Song',song})),tempo:r.params.tempo_us};
  for (const [key,value] of Object.entries(expected)) assert.equal(row[key],String(value),`case ${index} ${key}`);
}
console.log(`NORMALIZED SCORE PARITY: all${lines.length} cases match exact wire,notes,ticks,tempo and event hash`);

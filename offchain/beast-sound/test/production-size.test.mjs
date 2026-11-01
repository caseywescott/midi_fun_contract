import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {checkProductionSize} from '../../../scripts/check_production_size.mjs';
const classes=['BeastMidiProvider','BeastSoundComposer','BeastPureGenerator','BeastPureComposer'];
function fixture(run){const dir=mkdtempSync(join(tmpdir(),'production-casm-'));try{
  for(const name of classes)writeFileSync(join(dir,`beast_contracts_${name}.compiled_contract_class.json`),JSON.stringify({bytecode:['0x1']}));
  run(dir,(name,data)=>writeFileSync(join(dir,`beast_contracts_${name}.compiled_contract_class.json`),JSON.stringify(data)));
}finally{rmSync(dir,{recursive:true,force:true});}}
const helper=new URL('../../../scripts/check_production_size.mjs',import.meta.url);
test('production size gate includes pure classes and accepts the81920-felt limit',()=>fixture((dir,write)=>{
  write('BeastPureComposer',{bytecode:Array(81920).fill('0x1')});
  assert.deepEqual(checkProductionSize(dir).map(r=>r.name),classes);
  assert.equal(checkProductionSize(dir).at(-1).felts,81920);
}));
test('oversize production composer fails clearly including CLI exit status',()=>fixture((dir,write)=>{
  write('BeastPureComposer',{bytecode:Array(81921).fill('0x1')});
  assert.throws(()=>checkProductionSize(dir),/BeastPureComposer.*81921.*exceeds 81920/);
  const r=spawnSync(process.execPath,[fileURLToPath(helper),dir],{encoding:'utf8'});
  assert.equal(r.status,1);assert.match(r.stderr,/BeastPureComposer.*81921.*81920/);
}));
test('test class artifacts cannot hide a missing production artifact',()=>fixture(dir=>{
  rmSync(join(dir,'beast_contracts_BeastPureComposer.compiled_contract_class.json'));
  writeFileSync(join(dir,'beast_contracts_unittest.test.compiled_contract_class.json'),JSON.stringify({bytecode:['0x1']}));
  assert.throws(()=>checkProductionSize(dir),/BeastPureComposer.*cannot read production CASM/);
}));
test('malformed JSON, empty/missing bytecode and nonfelt entries fail',()=>fixture((dir,write)=>{
  const path=join(dir,'beast_contracts_BeastPureComposer.compiled_contract_class.json');writeFileSync(path,'{broken');
  assert.throws(()=>checkProductionSize(dir),/cannot read production CASM/);
  for(const data of [{},{bytecode:[]},{bytecode:'0x1'},{bytecode:[1]},{bytecode:['garbage']},null]){
    write('BeastPureComposer',data);assert.throws(()=>checkProductionSize(dir),/malformed production CASM/);
  }
}));

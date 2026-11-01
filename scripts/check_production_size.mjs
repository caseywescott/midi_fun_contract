// Check actual `scarb build -p beast_contracts` dev artifacts, never snforge test classes.
// node scripts/check_production_size.mjs [target/dev]
import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';

const CLASSES=['BeastMidiProvider','BeastSoundComposer','BeastPureGenerator','BeastPureComposer'];
export function checkProductionSize(directory){
  return CLASSES.map(name=>{
    const path=join(directory,`beast_contracts_${name}.compiled_contract_class.json`);
    let artifact;
    try{artifact=JSON.parse(readFileSync(path,'utf8'));}catch(error){throw Error(`${name}: cannot read production CASM artifact ${path}: ${error.message}`);}
    const code=artifact?.bytecode;
    if(!Array.isArray(code)||!code.length||code.some(felt=>typeof felt!=='string'||!/^0x[0-9a-f]+$/i.test(felt)))throw Error(`${name}: malformed production CASM bytecode in ${path}`);
    if(code.length>81920)throw Error(`${name}: production CASM ${code.length} felts exceeds 81920 (${path})`);
    return {name,felts:code.length};
  });
}

if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){
  try{for(const {name,felts} of checkProductionSize(resolve(process.argv[2]||'target/dev')))console.log(`${name}: ${felts}/81920 CASM felts`);}
  catch(error){console.error(error.message);process.exitCode=1;}
}

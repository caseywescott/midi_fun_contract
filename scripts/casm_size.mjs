// CASM bytecode felts per compiled class in target/dev (the Starknet limit is 81,920).
import { readdirSync, readFileSync } from 'node:fs';
for (const f of readdirSync('target/dev').filter((f) => f.endsWith('.compiled_contract_class.json')))
  console.log(f.replace('.compiled_contract_class.json', '').padEnd(40), JSON.parse(readFileSync('target/dev/' + f)).bytecode.length);

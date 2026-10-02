// Summarize reproducible Foundry gas/resource estimates, separating setup and contract paths.
// node onchain/measure.mjs <integration.log> <real-nft.log>
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const [flowFile,nftFile]=process.argv.slice(2);
const parse=file=>{
  const log=readFileSync(file,'utf8'),out={};
  for(const match of log.matchAll(/^\[PASS\] (\S+) \(l1_gas: ~([\d]+), l1_data_gas: ~([\d]+), l2_gas: ~([\d]+)\)\n([\s\S]*?)(?=^\[PASS\]|^[A-Z_]+ data:|^Tests:|(?![\s\S]))/gm)) {
    const detail=match[5];out[match[1].split('::').at(-1)]={l2_gas_estimate:Number(match[4]),l1_data_gas_setup:Number(match[3]),details:detail.trim().split('\n').filter(line=>/steps|builtins|sierra gas|syscalls/.test(line)).map(line=>line.trim())};
  }
  return out;
};
const flow=parse(flowFile),nft=parse(nftFile);
const delta=(table,name,setup)=>({test:table[name],setup:table[setup],l2_gas_excluding_setup:table[name].l2_gas_estimate-table[setup].l2_gas_estimate});
const classes={};
for(const name of ['BeastMidiProvider','MidiPage']) {
  const base=join(root,'contracts/midi_integration/target/dev/midi_integration_'+name);
  const sierra=JSON.parse(readFileSync(base+'.contract_class.json','utf8')),casm=JSON.parse(readFileSync(base+'.compiled_contract_class.json','utf8'));
  delete sierra.sierra_program_debug_info;
  classes[name]={casm_felts:casm.bytecode.length,sierra_felts:sierra.sierra_program.length,sierra_json_bytes_without_debug:Buffer.byteLength(JSON.stringify(sierra))};
}
const evidence={toolchains:{midi:{scarb:'2.11.4',snforge:'0.44.0',resource:'legacy Cairo steps converted by Foundry'},real_nft:{scarb:'2.18.0',snforge:'0.60.0',resource:'Sierra gas with separately built 2.11.4 callees',source_commit:'ae3fa8d0efdb8de62144abcd26984d34e90aab5b'}},classes,mock_real_presentation:{named:delta(flow,'measure_real_named_path','measure_real_setup'),heaviest:delta(flow,'measure_real_heaviest_path','measure_real_heaviest_setup')},actual_nft_and_art:{plain:delta(nft,'e2e_gas_plain_on','e2e_gas_setup_only'),fancy:delta(nft,'e2e_gas_fancy_on','e2e_gas_setup_only'),heaviest:delta(nft,'e2e_gas_heaviest_on','e2e_gas_heaviest_setup'),sound_off_whole_test:nft.e2e_gas_plain_off},limitations:['State sources are ABI-enforcing mocks; actual NFT and its PNG/GIF providers are real.','Foundry estimates are not deployed RPC call limits or transaction fee estimates.','The documented Sepolia 116-bit collection currently has zero Death Mountain source; live production path/read latency remains unavailable.','Configured RPC execution limits must be checked before enabling the page.']};
writeFileSync(new URL('dist/resource-evidence.json',import.meta.url),JSON.stringify(evidence,null,2)+'\n');console.log(JSON.stringify(evidence));

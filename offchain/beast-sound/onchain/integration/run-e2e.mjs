// Test mixed compiler artifacts against an isolated, patched ae3fa8d Beasts checkout.
// SCARB_MIDI=/path/to/scarb2.11.4 SCARB_NFT=/path/to/scarb2.18.0 SNFORGE_NFT=/path/to/snforge0.60.0
// node integration/run-e2e.mjs <isolated patched Beasts directory> [output.log]
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, openSync, readFileSync, writeFileSync, chmodSync, closeSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const [directory,logArg]=process.argv.slice(2);
if(!directory||!process.env.SCARB_NFT) throw new Error('Provide isolated patched Beasts directory and absolute SCARB_NFT (2.18.0) path');
const nft=resolve(directory), root=fileURLToPath(new URL('../../../../',import.meta.url));
if(!readFileSync(join(nft,'src/interfaces.cairo'),'utf8').includes('pub trait IMidiPage')) throw new Error('Apply beasts_nft-sound.patch first');
execFileSync(process.env.SCARB_MIDI || 'scarb',['--manifest-path',join(root,'contracts/midi_integration/Scarb.toml'),'build'],{stdio:'inherit'});
copyFileSync(new URL('sound_e2e_tests.cairo',import.meta.url),join(nft,'src/sound_e2e_tests.cairo'));
const lib=join(nft,'src/lib.cairo'),text=readFileSync(lib,'utf8');
if(!text.includes('mod sound_e2e_tests;'))writeFileSync(lib,text+'\n#[cfg(test)]\nmod sound_e2e_tests;\n');
const work=mkdtempSync(join(tmpdir(),'tinysynth-nft-'));
const wrapper=join(work,'scarb');
writeFileSync(wrapper,`#!/usr/bin/env python3
import sys,os,subprocess,json,pathlib,shutil
result=subprocess.run([os.environ['SCARB_NFT'],*sys.argv[1:]])
if result.returncode==0 and 'build' in sys.argv:
    source=pathlib.Path(os.environ['MIDI_ARTIFACTS'])
    target=pathlib.Path(os.environ['NFT_ARTIFACTS'])
    extra=json.loads((source/'midi_integration.starknet_artifacts.json').read_text())['contracts']
    for manifest in target.glob('*.starknet_artifacts.json'):
        data=json.loads(manifest.read_text())
        existing={c['contract_name'] for c in data['contracts']}
        for entry in extra:
            if entry['contract_name'] in ['MidiPage','BeastMidiProvider','MockDeathMountain'] and entry['contract_name'] not in existing:
                data['contracts'].append(entry)
                for filename in entry['artifacts'].values():
                    if filename:shutil.copyfile(source/filename,target/filename)
        manifest.write_text(json.dumps(data))
sys.exit(result.returncode)
`);chmodSync(wrapper,0o755);
const log=resolve(logArg || join(work,'e2e.log')),output=openSync(log,'w');
try {
  execFileSync(process.env.SNFORGE_NFT || 'snforge',['test','sound_e2e','--max-n-steps','4294967295','--detailed-resources'],{cwd:nft,env:{...process.env,PATH:work+':'+process.env.PATH,MIDI_ARTIFACTS:join(root,'contracts/midi_integration/target/dev'),NFT_ARTIFACTS:join(nft,'target/dev')},stdio:['ignore',output,output]});
} finally { closeSync(output); console.log('Complete NFT test log: '+log); }
console.log(readFileSync(log,'utf8').split('\n').filter(line=>/^\[PASS\]|^Tests:/.test(line)).join('\n'));

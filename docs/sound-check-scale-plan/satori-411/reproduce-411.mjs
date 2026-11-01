import fs from 'node:fs';import vm from 'node:vm';import crypto from 'node:crypto';
const source=fs.readFileSync(new URL('../references/sampler-gen-tracks.mjs',import.meta.url),'utf8');
const writer=source.slice(source.indexOf('const PPQ ='),source.indexOf('// Art\n'));
const block=source.slice(source.indexOf('// Long track\n'),source.indexOf('// Quiet vs loud\n'));
let found;vm.runInNewContext(writer+'\n'+block,{SS:{beastSynthSettings:()=>null},DATA:null,fmtT:x=>String(x),edge:(_title,o)=>{found=o.midi;}});
const expected=fs.readFileSync(new URL('./track-411.mid',import.meta.url));if(!expected.equals(Buffer.from(found)))throw Error('MIDI mismatch');
console.log('Current tools/gen_tracks.mjs Long track reproduces exact original 411 MIDI: '+found.length+' bytes; sha256 '+crypto.createHash('sha256').update(found).digest('hex'));

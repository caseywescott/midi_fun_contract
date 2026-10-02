// Verify serialized outputs from Foundry, including the real patched NFT and its real art classes.
// node onchain/verify-flow.mjs <midi integration log> <patched NFT e2e log>
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { composeBeast, decodeTokenId } from '../src/index.js';
import { tokenUri } from './page.js';
const [flowFile,nftFile]=process.argv.slice(2);
const stored=readFileSync(new URL('dist/stored.b64',import.meta.url),'utf8');
const fixtures=JSON.parse(readFileSync(new URL('fixtures/midi.json',import.meta.url),'utf8'));
const flow=readFileSync(flowFile,'utf8'), nft=readFileSync(nftFile,'utf8');
const uri=(log,label)=>{const match=log.match(new RegExp('^'+label+' (data:application/json;base64,[A-Za-z0-9+/=]+)$','m'));assert.ok(match,'missing '+label);return match[1];};
const meta=u=>JSON.parse(Buffer.from(u.split(',')[1],'base64').toString());
const html=m=>Buffer.from(m.animation_url.split(',')[1],'base64').toString();
const midi=m=>Buffer.from(html(m).match(/id="midi">([\s\S]*?)<\/script>/)[1].trim(),'base64');
const art=m=>m.image.slice('data:image/svg+xml;base64,'.length);
const compare=(off,on)=>{const {animation_url,...body}=on;assert.deepEqual(body,off);assert.equal(html(on).match(/id="art">([\s\S]*?)<\/script>/)[1].trim(),art(off));};
const off=meta(uri(flow,'NFT_OFF')), named=meta(uri(flow,'NFT_ON')), changed=meta(uri(flow,'NFT_CHANGED'));
compare(off,named);compare(off,changed);
assert.deepEqual(midi(named),Buffer.from(fixtures.find(f=>f.name==='named_fresh').midi_b64,'base64'));
assert.deepEqual(midi(changed),Buffer.from(fixtures.find(f=>f.name==='veteran').midi_b64,'base64'));
const presentation='"name":"Test","description":"Music collectible","attributes":[]';
assert.equal(uri(flow,'NFT_ON'),tokenUri(stored,presentation,art(off),midi(named)));
const records=[{name:'non_beast',uri:uri(flow,'OTHER_URI')}];
for(const flavor of ['PLAIN','FANCY']) {
  const off=meta(uri(nft,'URI_'+flavor+'_OFF')), onUri=uri(nft,'URI_'+flavor+'_ON'),on=meta(onUri);
  compare(off,on);
  const attrs=Object.fromEntries(on.attributes.map(a=>[a.trait_type,a.value]));
  const score=composeBeast(decodeTokenId(BigInt(attrs['Token ID'])),{adventurers_killed:0,scars:0,summit_held_seconds:0,rank:Number(attrs.Rank),species_count:2});
  assert.deepEqual(midi(on),Buffer.from(score.midi));
  records.push({name:'actual_'+flavor.toLowerCase(),uri:onUri});
}
const heavyUri=uri(nft,'URI_HEAVIEST_ON'), heavy=meta(heavyUri);
const attrs=Object.fromEntries(heavy.attributes.map(a=>[a.trait_type,a.value]));
const heavyScore=composeBeast(decodeTokenId(BigInt(attrs['Token ID'])),{adventurers_killed:200,scars:63,summit_held_seconds:0,rank:Number(attrs.Rank),species_count:1});
assert.deepEqual(midi(heavy),Buffer.from(heavyScore.midi));
records.push({name:'actual_heaviest',uri:heavyUri});
writeFileSync(new URL('dist/contract-uris.json',import.meta.url),JSON.stringify(records)+'\n');
const evidence=records.map(record=>{const m=meta(record.uri);return {name:record.name,uri_bytes:record.uri.length,html_bytes:Buffer.byteLength(html(m)),midi_bytes:midi(m).length,image_base64_bytes:art(m).length};});
writeFileSync(new URL('dist/metadata-evidence.json',import.meta.url),JSON.stringify({checked:'NFT fields/image exact; generic raw SMF matches independent JS composer; dynamic MIDI/art decoded exactly',cases:evidence},null,2)+'\n');
console.log(JSON.stringify(evidence));

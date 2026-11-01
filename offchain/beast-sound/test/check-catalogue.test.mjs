import test from 'node:test';
import assert from 'node:assert/strict';
import {engine as E} from '../src/index.js';
import {MODE_SCALES,soundCheckMidi,speciesTier,speciesType,nameFromVariant} from '../src/lab.js';
import {catalogueCheck,renderCatalogueCheck} from '../src/sound_check_catalogue.js';
import {CHECK_CATALOGUE} from '../src/sound_check_catalogue_data.js';
const beast=(id,name=0,shiny=0)=>({id,...nameFromVariant(name),level:1,health:100,tier:speciesTier(id),beast_type:speciesType(id),shiny,animated:0});
// Independent minimal SMF reader; assertions concern rendered musical events, not writer internals.
function read(bytes){
 const b=Buffer.from(bytes);let at=14;const tracks=[];
 while(at<b.length){assert.equal(b.toString('ascii',at,at+4),'MTrk');let p=at+8,end=p+b.readUInt32BE(at+4),time=0;const events=[];
 const vlq=()=>{let n=0,c;do{c=b[p++];n=n*128+(c&127);}while(c&128);return n;};
 while(p<end){time+=vlq();let status=b[p++];if(status===255){const kind=b[p++],length=vlq();events.push({time,kind,data:[...b.subarray(p,p+length)]});p+=length;}else{const data=[b[p++]];if((status&240)!==192&&(status&240)!==208)data.push(b[p++]);events.push({time,status,data});}}
 tracks.push(events);at=end;}
 return tracks;
}
test('75 candidates retain distinct rendered contours/rhythms, supported presets and explicit end rests',()=>{
 const signatures=new Set();
 for(let id=1;id<=75;id++){
  const r=soundCheckMidi(beast(id),E),tracks=read(r.midi),notes=tracks.flat().filter(e=>(e.status&240)===144);
  assert.ok(notes.length>0);for(const e of notes){assert.ok(e.data[0]>=0&&e.data[0]<=127);assert.ok(e.data[1]>0&&e.data[1]<=127);}
  if(id===64){assert.deepEqual(r.info.presets,[34,35,36,37,38,39,40,41]);continue;}
  assert.equal(tracks.length,2);assert.ok(tracks.every(t=>t.at(-1).kind===47&&t.at(-1).time===15360));
  const row=catalogueCheck(id);assert.equal(notes.length,34+row.finalNotes);
  assert.equal(notes.at(-1).data[0]%12,r.result.form.events[0].pitch%12);
  assert.ok(tracks[1].filter(e=>e.status===128).at(-1).time<15360);
  const first=notes[0].data[0];signatures.add(JSON.stringify(notes.map(e=>[e.time,e.data[0]-first])));
 }
 assert.equal(signatures.size,74);
});
test('unnamed palettes follow the actual Species Song swap and Satori target',()=>{
 assert.equal(soundCheckMidi(beast(39),E).info.key,'Eb harmonic minor');
 assert.equal(soundCheckMidi(beast(40),E).info.key,'D Dorian');
 const s=soundCheckMidi(beast(44),E);assert.equal(s.info.key,'A Aeolian');assert.equal(s.info.tempo_us,500000);
 assert.equal(soundCheckMidi(beast(44,1),E).info.key,'A Aeolian');
});
test('names preserve curated program/phrase while using named palette, mega preserves curated lead parity',()=>{
 for(const id of [1,33,39,40,44,68,75]){
  const plain=soundCheckMidi(beast(id),E);
  for(const nv of [1,621,1242]){const named=soundCheckMidi(beast(id,nv),E);assert.deepEqual(named.info.presets,plain.info.presets);assert.equal(named.info.phrase,plain.info.phrase);}
  assert.deepEqual(soundCheckMidi(beast(id,0,1),E).info.presets,[catalogueCheck(id).mega]);
 }
});
test('short articulation never lengthens40tick blips; boundaries stay valid and rests survive all performances',()=>{
 for(const row of CHECK_CATALOGUE.filter(x=>x.species!==64))for(const tonic of [row.register,row.register+11])for(const articulation_profile of [0,1,2,3,5]){
  const r=renderCatalogueCheck(row,{tonic,scale:MODE_SCALES[7],articulation_profile,velocity_ceiling:127}),tracks=read(r.midi),on=tracks[1].filter(e=>e.status===144),off=tracks[1].filter(e=>e.status===128);
  assert.equal(on.length,off.length);assert.equal(tracks[1].at(-1).time,15360);
  for(let i=on.length-row.finalNotes;i<on.length;i++)assert.equal(off[i].time-on[i].time,40);
 }
 for(const family of [0,1,2])assert.ok(renderCatalogueCheck(catalogueCheck(4294967295,family),{tonic:60,scale:MODE_SCALES[4]}).midi.length>0);
});

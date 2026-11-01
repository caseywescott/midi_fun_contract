import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {engine as E} from '../src/index.js';
import {createEngineV11} from '../src/engine_v11.js';
import {GENESIS_DEFAULTS,genesisMidi,sampleTrackMidi,drift2,dayAnchor} from '../src/lab.js';
import {satori411SongInputs,satori411Midi,satori411DriftedInputs,isSatori411Song} from '../src/satori411.js';
const V=createEngineV11(E),beast={id:44,prefix:0,suffix:0,level:1,health:100,shiny:0,animated:0,tier:4,beast_type:1};
test('canonical Genesis and named wrappers select the exact authored written scores',()=>{
 assert.deepEqual(Buffer.from(genesisMidi(44,false,E,V).midi),fs.readFileSync(new URL('../../../docs/sound-check-scale-plan/satori-411/track-411.mid',import.meta.url)));
 const named=sampleTrackMidi(beast,{species_count:1},{...GENESIS_DEFAULTS,name:1},E,V);
 assert.deepEqual(named.midi,satori411Midi(satori411SongInputs(1)));
});
test('Agony Bane drift shifts the written key once and preserves its authored register',()=>{
 for(const [day,tonic] of [[31,55],[32,55],[99,53],[173,55],[400,53]]){
  const result=sampleTrackMidi(beast,{species_count:1},{...GENESIS_DEFAULTS,name:1,epoch:day,driftMode:'v2',blockHashes:true},E,V);
  assert.equal(result.recipe.score.tonic_keynum,tonic);
  assert.equal(result.recipe.theme.register_band,0);
  assert(isSatori411Song(result.recipe));
 }
});
test('drifting across an octave cannot reselect the named phrase and weekly trill changes once',()=>{
 const base=satori411SongInputs(1);base.score.tonic_keynum=59;
 const x=satori411DriftedInputs(base,{day:31,rhythm:0n,rotate:262144n,dayKnob:0,delta:0});
 assert.equal(x.score.tonic_keynum,66);assert.equal(x.theme.register_band,0);
 assert.equal(x.treatment.trill,!base.treatment.trill);assert(isSatori411Song(x));
 assert.equal(base.score.tonic_keynum,59);
});
test('canonical Species and named purchase wrappers drift one immutable base at calendar boundaries',()=>{
 for(const name of [0,1])for(const seed of [null,123n])for(const day of [1,2,7,8,30,31,180,360,540]){
  const written=sampleTrackMidi(beast,{species_count:1},{...GENESIS_DEFAULTS,name,seed},E,V);
  const d=drift2({...beast,prefix:name,suffix:name},day,dayAnchor());
  const expected=satori411DriftedInputs(written.recipe,d);
  const actual=sampleTrackMidi(beast,{species_count:1},{...GENESIS_DEFAULTS,name,seed,epoch:day,driftMode:'v2',blockHashes:true},E,V);
  assert.deepEqual(actual.recipe,expected);assert.deepEqual(actual.midi,satori411Midi(expected));
 }
});

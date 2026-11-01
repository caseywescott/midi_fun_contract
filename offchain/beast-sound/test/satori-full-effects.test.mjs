import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {expectedSatori} from './reference/satori-full-effects-oracle.mjs';
import {satori411PerformanceMidi,satori411SongInputs,satori411Midi} from '../src/satori411.js';
import {satori411SynthSettings} from '../onchain/tinychip/synth_settings.mjs';
for(const name of [0,1])for(let fx=0;fx<4;fx++)test(`Satori name${name} effects${fx} equals independent original-score/Casey-arranger oracle`,()=>{
  assert.deepEqual(satori411PerformanceMidi(name,fx),expectedSatori(name,fx));
});
test('normal original Satori settings stay byte-for-byte equivalent; effect palettes contain actual selected timbres',()=>{
  assert.deepEqual(satori411SynthSettings(),JSON.parse(fs.readFileSync(new URL('../../../docs/sound-check-scale-plan/satori-411/track-411.settings.json',import.meta.url))));
  for(let fx=0;fx<4;fx++){
    const s=satori411SynthSettings(fx===1||fx===3,fx>=2), slots=s.timbres.filter(x=>!x.drum).map(x=>x.slot);
    for(const p of [0,15,17,...(fx>=2?[12]:[]),...(fx%2?[50,65]:[])])assert.ok(slots.includes(p));
    assert.equal(slots.includes(50),!!(fx%2));assert.equal(slots.includes(12),fx>=2);
  }
});

import {readSmf} from './reference/read-smf.mjs';
for(const name of [0,1])for(let fx=0;fx<4;fx++)test(`Satori name${name} effects${fx} has actual Casey mega/echo/pan/dynamic features`,()=>{
  const midi=satori411PerformanceMidi(name,fx), parsed=readSmf(midi), ch=parsed.channels;
  const mega=fx%2===1,echo=fx>=2;
  assert.equal(parsed.tempo,500000-[0,25000,30000,45000][fx]);
  assert.equal(parsed.tracks.length,5+Number(mega)+Number(echo));
  assert.equal(Math.max(...parsed.tracks.map(t=>t.end)),69120);
  const lead=ch.get(0);
  assert.equal(lead.program,mega?[50,65][(44+name)%2]:0);
  assert.equal(lead.notes.length,112);
  if(mega){
    const dbl=ch.get(3);assert.equal(dbl.program,[50,65][1-(44+name)%2]);
    assert.equal(dbl.pan,128-lead.pan);assert.equal(dbl.notes.length,112);
    for(let i=0;i<112;i++)assert.deepEqual(dbl.notes[i],{...lead.notes[i],pitch:lead.notes[i].pitch+12,velocity:Math.floor(lead.notes[i].velocity*3/4)});
    assert.ok(ch.get(9).notes.some(n=>n.time===120&&n.pitch===42),'sixteenth mega hats');
  }
  if(echo){
    const e=ch.get(mega?4:3);assert.equal(e.program,12);assert.equal(e.pan,128-lead.pan);
    assert.equal(e.notes.length,111);
    for(let i=0;i<e.notes.length;i++)assert.deepEqual(e.notes[i],{...lead.notes[i],time:lead.notes[i].time+360,duration:Math.min(lead.notes[i].duration,69120-lead.notes[i].time-360),velocity:Math.floor(lead.notes[i].velocity/2)});
    assert.equal(e.notes.at(-1).duration,120,'echo clipped at loop end');
  }
  if(fx){assert.equal(lead.notes[0].velocity,104,'Casey phrase arc/downbeat dynamics');assert.equal(lead.pan,9);}
  else{assert.equal(lead.pan,50);assert.equal(lead.notes[0].velocity,100);}
  const settings=satori411SynthSettings(mega,echo), slots=new Set(settings.timbres.filter(t=>!t.drum).map(t=>t.slot));
  for(const [channel,t] of ch)if(channel!==9)assert.ok(slots.has(t.program),`channel${channel} preset present`);
});

test('every accepted authored mega tier fill selects installed standard drum timbres',()=>{
  const drums=new Set(satori411SynthSettings(true,true).timbres.filter(t=>t.drum).map(t=>t.slot));
  for(let tier=1;tier<=5;tier++){
    const song=satori411SongInputs(1);song.score.tier=tier;song.score.articulation_profile=3;
    const rendered=readSmf(satori411Midi(song,{mega:true,echo:true}));
    for(const hit of rendered.channels.get(9).notes)assert.ok(drums.has(hit.pitch),`tier${tier} drum${hit.pitch}`);
  }
});

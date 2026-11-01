// Independent oracle: original lab411 score generator plus unmodified Casey cdcad0a arranger.
// The phrase shaping below is the readable v1.1 policy, not the production authored renderer.
import fs from 'node:fs';
import vm from 'node:vm';
import {beastFullMidi} from './casey-full-midi-cdcad0a.mjs';
const source=fs.readFileSync(new URL('../../../../docs/sound-check-scale-plan/references/sampler-gen-tracks.mjs',import.meta.url),'utf8');
const writer=source.slice(source.indexOf('const PPQ ='),source.indexOf('// Art\n'));
const score=source.slice(source.indexOf('// Long track\n'),source.indexOf('// Quiet vs loud\n'));
export function originalScore(name=0){
  const notes=[],hits=[];let midi;
  const capture=(ch,t,pitch,velocity,duration)=>{notes.push({time:t,pitch,velocity,duration,voice_id:ch,section:0});};
  const ctx={SS:{beastSynthSettings:()=>null},DATA:null,fmtT:x=>String(x),edge:(_name,x)=>{midi=x.midi;},capture,hits,named:name===1};
  const hooks=`
const on=Song.prototype.on;
Song.prototype.on=function(ch,t,n,v,d){
 if(named&&ch!==9){n-=9;if(ch===0&&t%1920===0&&d===920)d=680;else if(ch===0&&t%1920===960&&d===440){t-=240;d=680;}}
 capture(ch,t,n,v,d);return on.call(this,ch,t,n,v,d);
};
const hit=Song.prototype.hit;Song.prototype.hit=function(t,n,v){hits.push([t,n,v]);return hit.call(this,t,n,v);};
`;
  vm.runInNewContext(writer+hooks+score,ctx);
  hits.sort((a,b)=>a[0]-b[0]);return {notes,hits,midi:Uint8Array.from(midi)};
}
export function expectedSatori(name,fx){
  const {notes,hits,midi}=originalScore(name);
  if(!fx)return midi;
  const profile=[0,2,5,3][fx], ceiling=127, byVoice=new Map();
  for(const e of notes){const group=byVoice.get(e.voice_id)||[];group.push(e);byVoice.set(e.voice_id,group);}
  for(const [voice,group] of byVoice){
    const low=Math.min(...group.map(e=>e.pitch)),high=Math.max(...group.map(e=>e.pitch));
    for(const e of group){
      let v=(voice===0?80:70)+Math.round(16*(high>low?(e.pitch-low)/(high-low):0.5));
      if(e.time%1920===0)v+=Math.floor(e.time/1920)%2===0?12:4;
      e.velocity=Math.max(1,Math.min(ceiling,v));
      if(profile===1)e.duration=Math.max(60,Math.floor(e.duration/2));
      if(profile===5)e.duration=Math.max(60,Math.floor(e.duration*3/4));
    }
  }
  const mega=fx===1||fx===3,echo=fx>=2;
  return beastFullMidi({beast:{beast_type:1},params:{species_id:44,name_variant_id:name,tier:4,voice_count:3,use_countersubject:false,tempo_us:500000-[0,25000,30000,45000][fx]},
    form:{events:notes,section_ticks:69120,sections:[0]}},()=>69120,
    {lead:mega,double:mega,groove:mega,echo},
    {instruments:'beast',programs:{0:0,1:15,2:17},drums:mega?null:()=>hits});
}

// Stable species voices with authored contour, held notes, response and short articulation.
import {CHECK_CATALOGUE} from './sound_check_catalogue_data.js';
export function catalogueCheck(species,family=0){return CHECK_CATALOGUE[species<=75?species-1:family*25];}
const vlq=n=>{const b=[n&127];while((n=Math.floor(n/128)))b.unshift((n&127)|128);return b;};
const u32=n=>[(n>>>24)&255,(n>>>16)&255,(n>>>8)&255,n&255];
const chunk=(tag,b)=>[...Array.from(tag,c=>c.charCodeAt(0)),...u32(b.length),...b];
export function renderCatalogueCheck(row,{tonic,scale,tempo_us=row.tempo_us,articulation_profile=0,velocity_ceiling=100,mega=false}={}){
  const events=[],controls=[];let time=0;
  const pitch=d=>{const p=tonic+12*Math.floor(d/7)+scale[((d%7)+7)%7];return p;};
  const note=(d,slot,duration,velocity)=>{
    const short=articulation_profile===1?Math.floor(duration/2):Math.floor(duration*3/4);
    if(articulation_profile===1||articulation_profile===5)duration=Math.min(duration,Math.max(60,short));
    velocity=Math.min(velocity_ceiling,velocity+(articulation_profile===3&&time%1920===0?8:0));
    events.push({time,duration,pitch:pitch(d),velocity,voice_id:0});time+=slot;
  };
  controls.push([0,row.pan?48:64]);
  row.head.forEach((d,i)=>note(d,row.rhythm[i%4],Math.floor(row.rhythm[i%4]*5/6),96));
  row.held.forEach(d=>note(d,1920,1800,100));
  controls.push([time,row.pan?80:64]);
  row.response.forEach((d,i)=>note(d,row.rhythm[i%4],Math.floor(row.rhythm[i%4]*5/6),96));
  controls.push([time,64]);
  const last=[...row.head.slice(0,row.finalNotes-4),...row.head.slice(-4)];
  last.forEach(d=>note(d,240,40,100));
  const program=mega?row.mega:row.program;
  let track=[],at=0;
  const msg=(t,...bytes)=>{track.push(...vlq(t-at),...bytes);at=t;};
  msg(0,0xc0,program);msg(0,0xb0,7,100);
  let c=0;
  for(const e of events){while(c<controls.length&&controls[c][0]<=e.time){msg(controls[c][0],0xb0,10,controls[c][1]);c++;}msg(e.time,0x90,e.pitch,e.velocity);msg(e.time+e.duration,0x80,e.pitch,0);}
  while(c<controls.length){msg(controls[c][0],0xb0,10,controls[c][1]);c++;}
  msg(15360,0xff,0x2f,0);
  const tempo=[0,0xff,0x51,3,...u32(tempo_us).slice(1),...vlq(15360),0xff,0x2f,0];
  return {midi:Uint8Array.from([...chunk('MThd',[0,1,0,2,1,224]),...chunk('MTrk',tempo),...chunk('MTrk',track)]),events,program};
}

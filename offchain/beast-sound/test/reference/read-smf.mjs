// Small independent SMF event reader for feature assertions; no composer implementation imports.
export function readSmf(midi){
  let at=14;const tracks=[];let tempo;
  const vlq=()=>{let n=0,b;do{b=midi[at++];n=n*128+(b&127);}while(b&128);return n;};
  while(at<midi.length){const size=new DataView(midi.buffer,midi.byteOffset+at+4,4).getUint32(0);at+=8;const end=at+size;
    const t={events:[],notes:[],end:0}, held=new Map();let time=0,status=0;
    while(at<end){time+=vlq();if(midi[at]&128)status=midi[at++];
      if(status===255){const kind=midi[at++],n=vlq();if(kind===81)tempo=midi[at]*65536+midi[at+1]*256+midi[at+2];at+=n;continue;}
      if(status===240||status===247){const n=vlq();at+=n;continue;}
      const kind=status&240,channel=status&15,a=midi[at++],b=kind===192||kind===208?null:midi[at++];
      t.channel=channel;t.events.push({time,kind,channel,a,b});
      if(kind===192)t.program=a;if(kind===176&&a===10)t.pan=b;
      if(kind===144&&b){const e={time,pitch:a,velocity:b};t.notes.push(e);held.set(a,e);}
      if(kind===128||kind===144&&!b){const n=held.get(a);if(n){n.duration=time-n.time;held.delete(a);}}
    }
    t.end=time;tracks.push(t);
  }
  return {tempo,tracks,channels:new Map(tracks.filter(t=>t.channel!==undefined).map(t=>[t.channel,t]))};
}

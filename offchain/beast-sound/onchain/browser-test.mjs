// Run offline browser/audio checks. npm install playwright, then install Chromium separately.
// PLAYWRIGHT_MODULE, CHROMIUM_PATH and LD_LIBRARY_PATH may point to an existing local runtime.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { tokenUri } from './page.js';
const require=createRequire(import.meta.url);
const { chromium }=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const stored=readFileSync(new URL('dist/stored.b64',import.meta.url),'utf8');
const musicUrl = (midi,svg) => JSON.parse(Buffer.from(tokenUri(stored,fx.members,svg,midi).split(',')[1],'base64').toString()).animation_url;
const fx=JSON.parse(readFileSync(new URL('fixtures/warlock_v3.json',import.meta.url),'utf8'));
const fixtures=JSON.parse(readFileSync(new URL('fixtures/midi.json',import.meta.url),'utf8')).slice(0,4);
let contractUris=[];
try { contractUris=JSON.parse(readFileSync(new URL('dist/contract-uris.json',import.meta.url),'utf8')); } catch {}
for (const record of contractUris.filter(r=>r.name!=='non_beast')) {
  const metadata=JSON.parse(Buffer.from(record.uri.split(',')[1],'base64').toString());
  const html=Buffer.from(metadata.animation_url.split(',')[1],'base64').toString();
  const bytes=Buffer.from(html.match(/id="midi">([\s\S]*?)<\/script>/)[1].trim(),'base64');
  const at=bytes.indexOf(Buffer.from([255,81,3]));
  fixtures.push({name:record.name,midi_b64:bytes.toString('base64'),tempo_us:bytes.readUIntBE(at+3,3),animation_url:metadata.animation_url,svg_b64:metadata.image.split(',')[1]});
}
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH || undefined,args:['--no-sandbox','--autoplay-policy=user-gesture-required']});
const results=[];
try {
  const context=await browser.newContext({offline:true});
  for(const fixture of fixtures) {
    const page=await context.newPage(); const errors=[]; const network=[];
    page.on('pageerror',error=>errors.push(error.message));
    page.on('request',request=>{if(/^https?:/.test(request.url()))network.push(request.url());});
    await page.goto(fixture.animation_url || musicUrl(Buffer.from(fixture.midi_b64,'base64'),fx.svg_b64));
    assert.equal(await page.evaluate(()=>window.midiPlayer),undefined,'audio must wait for gesture');
    await page.locator('#play').click();
    await page.waitForFunction(()=>window.midiPlayer?.playing===1 && window.midiPlayer.playIndex>0);
    const initial=await page.evaluate(()=>{
      const s=window.midiPlayer;
      const analyser=s.actx.createAnalyser(); analyser.fftSize=2048; s.out.connect(analyser); window.audioProbe=analyser;
      window.playCalls=0; const play=s.playMIDI; s.playMIDI=function(...args){window.playCalls++;return play.apply(this,args);};
      return {tempo:s.song.tempo,tick_seconds:s.tick2Time,programs:s.pg.slice(),context:s.actx.state,midi_tempo:s.song.ev.find(e=>e.m[0]===65361).m[1]};
    });
    assert.equal(initial.context,'running');
    assert.ok(Math.abs(initial.midi_tempo-60000000/fixture.tempo_us)<1e-10);
    assert.ok(Math.abs(initial.tick_seconds-fixture.tempo_us/1e6/480)<1e-12);
    assert.ok(initial.programs.every(p=>p===0));
    await page.waitForTimeout(300);
    const energy=await page.evaluate(()=>{const values=new Float32Array(window.audioProbe.fftSize);window.audioProbe.getFloatTimeDomainData(values);return Math.sqrt(values.reduce((sum,x)=>sum+x*x,0)/values.length);});
    assert.ok(energy>1e-6,'must produce actual non-silent audio');
    await page.locator('#play').click(); await page.locator('#play').click();
    assert.equal(await page.evaluate(()=>window.playCalls),0,'repeated play is idempotent');
    await page.locator('#restart').click(); assert.equal(await page.evaluate(()=>window.playCalls),1);
    await page.locator('#loop').check(); assert.equal(await page.evaluate(()=>window.midiPlayer.loop),1);
    await page.locator('#stop').click(); assert.equal(await page.locator('#status').textContent(),'Stopped');
    assert.equal(await page.evaluate(()=>window.midiPlayer.playing),0);
    // Force an asynchronous AudioContext resume and Stop before it resolves.
    await page.evaluate(()=>{window.midiPlayer.actx.resume=()=>new Promise(resolve=>window.finishResume=resolve);});
    await page.locator('#restart').click(); await page.locator('#stop').click();
    await page.evaluate(()=>window.finishResume()); await page.waitForTimeout(30);
    assert.equal(await page.evaluate(()=>window.midiPlayer.playing),0);
    assert.equal(await page.locator('#status').textContent(),'Stopped');
    assert.equal(await page.locator('#artwork').getAttribute('src'),'data:image/svg+xml;base64,'+(fixture.svg_b64 || fx.svg_b64));
    assert.deepEqual(errors,[]); assert.deepEqual(network,[]);
    results.push({name:fixture.name,...initial,rms:energy,network_requests:network.length});
    await page.close();
  }
  // Non-Beast one-quarter-note SMF, tempo500001us. Test EOF and a full loop wrap quickly.
  const bytes=Buffer.from([77,84,104,100,0,0,0,6,0,0,0,1,1,224,77,84,114,107,0,0,0,20,0,255,81,3,7,161,33,0,144,60,100,131,96,128,60,0,0,255,47,0]);
  const page=await context.newPage(); const other=contractUris.find(r=>r.name==='non_beast');
  const otherUrl=other ? JSON.parse(Buffer.from(other.uri.split(',')[1],'base64').toString()).animation_url : musicUrl(bytes,fx.svg_b64);
  await page.goto(otherUrl);
  await page.locator('#play').click(); await page.waitForFunction(()=>document.querySelector('#status').textContent==='Finished');
  assert.equal(await page.evaluate(()=>window.midiPlayer.song.tempo),60000000/500001);
  await page.locator('#loop').check(); await page.locator('#restart').click(); await page.waitForTimeout(1300);
  assert.equal(await page.evaluate(()=>window.midiPlayer.playing),1);
  assert.equal(await page.locator('#status').textContent(),'Playing');
  await page.locator('#stop').click(); await page.close();
  // Stateful non-Beast SMF: late program, expression and tempo must never leak into a new start.
  const track=Buffer.from([0,255,81,3,7,161,33,0,144,60,100,129,112,128,60,0,129,112,192,40,0,176,11,16,0,255,81,3,11,113,179,0,144,64,100,135,64,128,64,0,0,255,47,0]);
  const header=Buffer.from([77,84,104,100,0,0,0,6,0,0,0,1,1,224,77,84,114,107,0,0,0,track.length]);
  const stateful=await context.newPage(); await stateful.goto(musicUrl(Buffer.concat([header,track]),fx.svg_b64));
  const late=()=>stateful.waitForFunction(()=>window.midiPlayer.pg[0]===40 && window.midiPlayer.ex[0]<0.1 && Math.abs(window.midiPlayer.song.tempo-60000000/750003)<1e-10);
  const initial=async()=>{
    await stateful.waitForFunction(()=>window.midiPlayer.playing===1 && window.midiPlayer.playIndex>0);
    const state=await stateful.evaluate(()=>({program:window.midiPlayer.pg[0],expression:window.midiPlayer.ex[0],tempo:window.midiPlayer.song.tempo}));
    assert.equal(state.program,0); assert.equal(state.expression,1); assert.equal(state.tempo,60000000/500001);
  };
  await stateful.locator('#play').click(); await initial(); await late();
  await stateful.locator('#restart').click(); await initial(); await late();
  await stateful.locator('#stop').click(); await stateful.locator('#play').click(); await initial(); await late();
  await stateful.waitForFunction(()=>document.querySelector('#status').textContent==='Finished');
  await stateful.locator('#play').click(); await initial(); await stateful.locator('#stop').click(); await stateful.close();
  const evidence={chromium:browser.version(),offline:true,passed:results.length+2,actual_contract_uris:contractUris.length,fixtures:results,controls:['Play','idempotent Play','Restart','Stop','Stop during resume','Loop wrap','EOF','stateful SMF Restart/Stop/EOF reset']};
  writeFileSync(new URL('dist/browser-evidence.json',import.meta.url),JSON.stringify(evidence,null,2)+'\n');
  console.log(JSON.stringify(evidence));
} finally { await browser.close(); }

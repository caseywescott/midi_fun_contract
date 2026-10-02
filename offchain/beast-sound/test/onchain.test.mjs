import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { animationHtml, midiHtml, pageHtml, storedSegment, tokenUri } from '../onchain/page.js';
const dir=new URL('../onchain/',import.meta.url);
const js=readFileSync(new URL('dist/player.js',dir),'utf8');
const stored=readFileSync(new URL('dist/stored.b64',dir),'utf8');
const fixtures=JSON.parse(readFileSync(new URL('fixtures/midi.json',dir),'utf8'));
const fx=JSON.parse(readFileSync(new URL('fixtures/warlock_v3.json',dir),'utf8'));
const decode=uri=>Buffer.from(uri.slice(uri.indexOf(',')+1),'base64');
const payload=(html,id)=>html.match(new RegExp(`<script type="text/plain" id="${id}">([\\s\\S]*?)</script>`))[1].trim();

test('fixed player is exactly the pinned tempo-patched dependency',()=>{
  const source=readFileSync(new URL('vendor/webaudio-tinysynth.upstream.min.js',dir),'utf8');
  assert.equal(createHash('sha256').update(source).digest('hex'),'a381bcc794f476b7e17fefb32d1e18ae053ee33392857118d3101c19eff657ec');
  const floor='Math.floor(6e7/function(s,i){return(s[i]<<16)+(s[i+1]<<8)+s[i+2]}(s,i+3))';
  assert.equal(source.split(floor).length,2);
  assert.ok(js.includes(source.replace(floor,'(6e7/function(s,i){return(s[i]<<16)+(s[i+1]<<8)+s[i+2]}(s,i+3))')));
  assert.ok(js.includes('Apache-2.0'));
  assert.equal(stored,storedSegment(js));
  assert.equal(Buffer.byteLength(pageHtml(js))%3,0);
  assert.equal(decode('data:x;base64,'+stored).length%3,0);
  assert.ok(!stored.endsWith('='));
  // The generated Cairo literal words reconstruct the same independent stored bytes.
  const cairo=readFileSync(new URL('cairo/src/page_data.cairo',dir),'utf8');
  const words=[...cairo.matchAll(/        (0x[0-9a-f]+),/g)].map(m=>Buffer.from(m[1].slice(2),'hex'));
  const pending=cairo.match(/felts.append\((0x[0-9a-f]+|0)\);\n    felts.append\((\d+)\);/);
  if(Number(pending[2])) words.push(Buffer.from(pending[1].slice(2),'hex'));
  assert.equal(Buffer.concat(words).toString('ascii'),stored);
});

test('JSON/HTML/MIDI/artwork remain byte-identical across all chunk and Base64 remainders',()=>{
  for(let n=0;n<95;n++) {
    const midi=Buffer.from(Array.from({length:n},(_,i)=>i*197%256));
    const svg=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg"><text>${'π'.repeat(n%4)} </script></text></svg>`).toString('base64');
    const members='"name":"Remainder '+n+'","attributes":[]';
    const meta=JSON.parse(decode(tokenUri(stored,members,svg,midi)));
    const html=decode(meta.animation_url).toString('utf8');
    assert.equal(html,animationHtml(js,midi,svg));
    assert.deepEqual(Buffer.from(payload(html,'midi'),'base64'),midi);
    assert.equal(payload(html,'art'),svg);
    assert.equal(meta.image,'data:image/svg+xml;base64,'+svg);
    assert.ok(html.endsWith('</script></body></html>'));
  }
});

test('representative score fixtures retain metadata and exact SMF bytes',()=>{
  for(const fixture of fixtures) {
    const midi=Buffer.from(fixture.midi_b64,'base64');
    const meta=JSON.parse(decode(tokenUri(stored,fx.members,fx.svg_b64,midi)));
    const original=JSON.parse('{'+fx.members+'}');
    for(const [key,value] of Object.entries(original)) assert.deepEqual(meta[key],value);
    const html=decode(meta.animation_url).toString('utf8');
    assert.deepEqual(Buffer.from(payload(html,'midi'),'base64'),midi);
    assert.equal(meta.image,'data:image/svg+xml;base64,'+fx.svg_b64);
    assert.equal(midi.subarray(0,4).toString(),'MThd');
  }
});

test('closed payloads carry arbitrary MIDI and script-looking artwork safely',()=>{
  const midi=Buffer.from('</script><script>window.pwned=true</script>');
  const svg=Buffer.from('<svg><!-- </script> --></svg>').toString('base64');
  assert.ok(!midiHtml(midi,svg).includes('window.pwned'));
  assert.equal((animationHtml(js,midi,svg).match(/type="text\/plain"/g)||[]).length,2);
});

test('art prefix reuse remains exact across 279-byte split transitions',()=>{
  for(const [i,n] of [276,280,556,560,836,840].entries()) {
    const svg=Buffer.alloc(n/4*3,97).toString('base64'); assert.equal(svg.length,n);
    const midi=Buffer.from(Array.from({length:31+i},(_,j)=>j*197%256));
    const members='"name":"Boundary '+n+'"'+' '.repeat(i);
    const meta=JSON.parse(decode(tokenUri(stored,members,svg,midi)));
    assert.equal(meta.image,'data:image/svg+xml;base64,'+svg);
    const html=decode(meta.animation_url).toString();
    assert.equal(html,animationHtml(js,midi,svg));
    assert.deepEqual(Buffer.from(payload(html,'midi'),'base64'),midi);
    assert.equal(payload(html,'art'),svg);
  }
});

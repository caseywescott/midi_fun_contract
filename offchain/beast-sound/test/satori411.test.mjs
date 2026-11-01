import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { decodeInputs, encodeInputs, decodeGenerationInputs, encodeGenerationInputs } from '../src/inputs.js';
import { isSatori411Song, satori411Midi, satori411SongInputs, satori411PurchasedInputs, satori411PerformanceMidi } from '../src/satori411.js';
import { satori411SynthSettings } from '../onchain/tinychip/synth_settings.mjs';
import { engine } from '../src/index.js';
const refs = new URL('../../../docs/sound-check-scale-plan/satori-411/', import.meta.url);
test('authored Satori reproduces the exact reviewed MIDI and original untrimmed settings', () => {
  assert.deepEqual(Buffer.from(satori411Midi()), fs.readFileSync(new URL('track-411.mid', refs)));
  assert.deepEqual(satori411SynthSettings(), JSON.parse(fs.readFileSync(new URL('track-411.settings.json', refs))));
});
test('Agony Bane derives a different composition using Casey named controls without replacing saved recipes', () => {
  const named = satori411SongInputs(1);
  assert.equal(named.arrangement.identity.name_variant_id, 1);
  const mapped = engine.mapV3({id:44,prefix:1,suffix:1,level:50,health:200,shiny:0,animated:0,tier:4,beast_type:1},
    {adventurers_killed:0,scars:0,summit_held_seconds:0,rank:0,species_count:1});
  assert.deepEqual([named.score.mode_id,named.score.tonic_keynum,named.theme.register_band,named.score.ornament_density,named.treatment.trill],
    [mapped.mode_id,mapped.tonic_keynum,mapped.register_band,mapped.ornament_density,mapped._ornament.allow_trill]);
  assert.notDeepEqual(satori411Midi(named), satori411Midi());
  const legacyMarked = satori411SongInputs(); legacyMarked.arrangement.identity.name_variant_id=1;
  assert.deepEqual(satori411Midi(legacyMarked), satori411Midi());
  const old = decodeInputs([5n, ...JSON.parse(fs.readFileSync(new URL('current-satori-shared-inputs.json', refs))).map(BigInt)]).song;
  assert.equal(isSatori411Song(old), false);
  const partial = structuredClone(named); partial.treatment.rhythm_seed = old.treatment.rhythm_seed;
  assert.equal(isSatori411Song(partial), false);
  const other = structuredClone(named); other.arrangement.identity.source_species_id = 43n;
  assert.equal(isSatori411Song(other), false);
});
test('authored inputs retain current canonical wire versions and roundtrip', () => {
  const x = {kind:'Song', song:satori411SongInputs(1)};
  assert.deepEqual(decodeInputs(encodeInputs(x)), x);
  const base = {base_song:x.song}; assert.deepEqual(decodeGenerationInputs(encodeGenerationInputs(base)), base);
});
test('purchases keep the authored form with deterministic key/tempo variation; effects retain timbre identity', () => {
  const base = satori411SongInputs(1), a = satori411PurchasedInputs(base, 0n), b = satori411PurchasedInputs(base, 1n);
  assert.equal(isSatori411Song(a),true);assert.equal(isSatori411Song(b),true);
  assert.notDeepEqual(satori411Midi(a),satori411Midi(b));
  for(let fx=0;fx<4;fx++)assert.ok(satori411PerformanceMidi(1,fx).length>=9720);
  assert.deepEqual(satori411PerformanceMidi(1,0),satori411Midi(base));
  assert.equal(a.score.tonic_keynum,base.score.tonic_keynum);
  assert.equal(b.score.tonic_keynum,base.score.tonic_keynum);
});

test('all supported song modes and tonic boundaries remain valid; invalid tonics reject', () => {
  for (const mode of [4,5,6,7,8,26]) for (const tonic of [24,96]) {
    const song = satori411SongInputs(); song.score.mode_id=mode; song.score.tonic_keynum=tonic;
    const midi = satori411Midi(song); assert.equal(midi.length,9720);
  }
  for(const tonic of [0,20,21,103]) {
    const song = satori411SongInputs(); song.score.tonic_keynum=tonic;
    assert.throws(()=>satori411Midi(song), /invalid song tonic/);
  }
});

// Independent event reader: compare actual notes/timing rather than recipe metadata or hashes.
function noteOns(midi, edges = false) {
  let at=14; const out=[];
  const vlq=()=>{let n=0,b;do{b=midi[at++];n=n*128+(b&127);}while(b&128);return n;};
  while(at<midi.length){const size=new DataView(midi.buffer,midi.byteOffset+at+4,4).getUint32(0);at+=8;const end=at+size;let time=0,running=0;
    while(at<end){time+=vlq();let status=midi[at];if(status&128){at++;running=status;}else status=running;
      if(status===255){at++;const len=vlq();at+=len;continue;} if(status===240||status===247){const len=vlq();at+=len;continue;}
      const a=midi[at++], b=(status&240)===192||(status&240)===208?null:midi[at++];
      if((status&240)===144&&b || edges&&(status&240)===128)out.push({channel:status&15,time,pitch:a,velocity:b,...(edges?{on:(status&240)===144}:{})});
    }
  }
  return out;
}
test('named composition retains 411 progression/contour while changing real lead rhythm and register', () => {
  const shared=noteOns(satori411Midi()), named=noteOns(satori411PerformanceMidi(1,0));
  assert.equal(shared.length,1282);assert.equal(named.length,1282);
  const normalize=rows=>rows.map(x=>({...x,pitch:x.pitch+9}));
  assert.deepEqual(named.filter(x=>x.channel===9),shared.filter(x=>x.channel===9));
  for(const ch of [1,2])assert.deepEqual(normalize(named.filter(x=>x.channel===ch)),shared.filter(x=>x.channel===ch));
  const lead=shared.filter(x=>x.channel===0), namedLead=named.filter(x=>x.channel===0);
  assert.deepEqual(namedLead.map(x=>x.pitch+9),lead.map(x=>x.pitch));
  assert.equal(namedLead.filter((x,i)=>x.time!==lead[i].time).length,28);
  assert.equal(namedLead[1].time,4*1920+720);assert.equal(lead[1].time,4*1920+960);
  assert.equal(shared[0].velocity,named[0].velocity);
});

test('Casey Song articulation keeps profile3 gates and floors staccato harp at60 ticks', () => {
  const base=satori411SongInputs(1), accent=structuredClone(base), detached=structuredClone(base);
  accent.score.articulation_profile=3;detached.score.articulation_profile=1;
  assert.deepEqual(noteOns(satori411Midi(accent),true),noteOns(satori411Midi(base),true));
  const harp=noteOns(satori411Midi(detached),true).filter(x=>x.channel===2);
  assert.equal(harp[1].time-harp[0].time,60);
});

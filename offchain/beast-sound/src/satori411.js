// Explicit authored Satori recipe. The two reserved felt markers opt into this score;
// ordinary historical species-44 recipes retain their procedural interpretation.
import { encodeInputs } from './inputs.js';
import { engine } from './index.js';
import {createEngineV11} from './engine_v11.js';
import {beastFullMidi} from './full_midi.js';
const V11=createEngineV11(engine);

const felt = (s) => BigInt('0x' + [...s].map((c) => c.charCodeAt(0).toString(16)).join(''));
export const SATORI411_THEME_MARKER = felt('SATORI_LAB_411_V1');
export const SATORI411_RHYTHM_MARKER = felt('SATORI_FORM_36_V1');
export const isSatori411Song = (x) => Number(x?.arrangement?.identity?.source_species_id) === 44
  && BigInt(x.theme.motif_seed) === SATORI411_THEME_MARKER
  && BigInt(x.treatment.rhythm_seed) === SATORI411_RHYTHM_MARKER;
export function satori411SongInputs(nameVariant = 0) {
  if (!Number.isInteger(nameVariant) || nameVariant < 0 || nameVariant > 1242) throw new Error('invalid music name');
  const x = {
    theme: { motif_seed: SATORI411_THEME_MARKER, tier: 4, register_band: 2 },
    score: { mode_id: 7, tonic_keynum: 57, tier: 4, weakness: 1, voice_count: 3, section_count: 1, stretto_lag: 1, use_inversion: false, use_countersubject: false, ornament_density: 0, articulation_profile: 0, velocity_ceiling: 127, tempo_us: 500000 },
    treatment: { rhythm_seed: SATORI411_RHYTHM_MARKER, flip_side: false, development: 0, direction: 0, spacing: 1, trill: false, prominence: 0, section_rhythm: false },
    arrangement: { family: 1, identity: { source_species_id: 44, name_variant_id: nameVariant }, channel_count: 4, channel_policy: { kind: 'Genesis' }, special: { kind: 'None' }, top_lead: true, balanced: false, weak_ties: true },
  };
  if (nameVariant === 1) {
    const p = engine.mapV3({id:44,prefix:1,suffix:1,level:50,health:200,shiny:0,animated:0,tier:4,beast_type:1},
      {adventurers_killed:0,scars:0,summit_held_seconds:0,rank:0,species_count:1});
    x.theme.register_band = p.register_band;
    x.score.mode_id = p.mode_id; x.score.tonic_keynum = p.tonic_keynum;
    x.score.ornament_density = p.ornament_density; x.treatment.trill = p._ornament.allow_trill;
  }
  return x;
}
export function satori411PurchasedInputs(base, seed) {
  const x = structuredClone(base), n = BigInt(seed);
  const named = x.theme.register_band === 0;
  if (!named) x.score.tonic_keynum = 55 + Number(n % 5n);
  x.score.tempo_us = 480000 + Number(named ? n % 5n : n / 5n % 5n) * 10000;
  x.arrangement.channel_policy = { kind: 'Seeded', seed: n };
  return x;
}
const vlq = (n) => { const b = [n & 127]; while ((n >>= 7)) b.unshift((n & 127) | 128); return b; };
const chunk = (tag, b) => [...tag].map((c) => c.charCodeAt(0)).concat([b.length >>> 24 & 255, b.length >>> 16 & 255, b.length >>> 8 & 255, b.length & 255], b);
export function satori411Midi(song = satori411SongInputs(), {mega=false,echo=false} = {}) {
  if (!isSatori411Song(song)) throw new Error('not a Satori 411 recipe');
  encodeInputs({ kind: 'Song', song }); // Enforce the existing Song domain (tonic24..96).
  const END = 69120, parts = Array.from({ length: 4 }, () => []), offset = song.score.tonic_keynum - 57;
  const push = (ch, time, priority, ...bytes) => parts[ch === 9 ? 3 : ch].push({ time, priority, bytes });
  const setup = (ch, program, pan) => { if (ch !== 9) push(ch, 0, 1, 0xc0 | ch, program); push(ch, 0, 1, 0xb0 | ch, 7, 100); push(ch, 0, 1, 0xb0 | ch, 10, pan); };
  setup(0, 0, 50); setup(1, 15, 40); setup(2, 17, 80); setup(9, 0, 64);
  const notes=[],hits=[];
  const note = (ch, t, key, velocity, duration) => {
    notes.push({time:t,duration,pitch:key+offset,velocity,voice_id:ch,section:0});
    if(mega||echo)return;
    const profile = song.score.articulation_profile;
    const dur = profile === 1 ? Math.max(60, Math.floor(duration / 2)) : profile === 5 ? Math.max(60, Math.floor(duration * 3 / 4)) : duration;
    const vel = Math.min(velocity, song.score.velocity_ceiling);
    push(ch, t, 2, 0x90 | ch, key + offset, vel); push(ch, t + dur, 0, 0x80 | ch, key + offset, 64);
  };
  const hit = (t, key, v) => {hits.push([t,key,Math.min(v,song.score.velocity_ceiling)]);push(9, t, 2, 0x99, key, Math.min(v, song.score.velocity_ceiling));};
  const turn = song.theme.register_band === 0 ? 240 : 0;
  const chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]], roots = [45, 41, 36, 43];
  for (let bar = 0; bar < 36; bar++) {
    const t = bar * 1920, c = chords[bar % 4], rest = bar >= 24 && bar < 28;
    for (let i = 0; i < 8; i++) note(1, t + i * 240, roots[bar % 4] + (i % 4 === 2 ? 7 : 0), 100, 200);
    if (bar >= 1) for (let i = 0; i < 16; i++) note(2, t + i * 120, c[i % 3] + (i % 6 > 2 ? 12 : 0) + 12, 70, 100);
    if (bar >= 4 && !rest) { note(0, t, c[1] + 24, 100, 920 - turn); note(0, t + 960 - turn, c[2] + 24, 100, 440 + turn); note(0, t + 1440, c[1] + 24, 100, 220); note(0, t + 1680, c[0] + 24, 100, 220); }
    if (bar >= 8) for (let i = 0; i < 8; i++) { hit(t + i * 240, 42, i % 2 ? 50 : 76); if (!rest) { if (i === 0 || i === 4) hit(t + i * 240, 36, 110); if (i === 2 || i === 6) hit(t + i * 240, 38, 100); } }
    if (bar === 0 || bar === 16) hit(t, 49, 100);
  }
  if(mega||echo){
    hits.sort((a,b)=>a[0]-b[0]);
    const p={...song.score,species_id:44,name_variant_id:song.arrangement.identity.name_variant_id};
    V11.shape(notes,p,END,true,song.treatment.prominence);
    return beastFullMidi({beast:{beast_type:1},params:p,form:{events:notes,section_ticks:END,sections:[0]}},()=>END,
      {lead:mega,double:mega,groove:mega,echo},
      {instruments:'beast',programs:{0:0,1:15,2:17},drums:mega?null:()=>hits});
  }
  const encodeTrack = (events) => { let at = 0; const b = []; for (const e of events.sort((a, b) => a.time - b.time || a.priority - b.priority)) { b.push(...vlq(e.time - at), ...e.bytes); at = e.time; } return [...b, ...vlq(END - at), 255, 47, 0]; };
  const us = song.score.tempo_us;
  const tempo = [0, 255, 81, 3, us >>> 16 & 255, us >>> 8 & 255, us & 255, ...vlq(END), 255, 47, 0];
  return Uint8Array.from(chunk('MThd', [0, 1, 0, 5, 1, 224]).concat(...[tempo, ...parts.map(encodeTrack)].map((b) => chunk('MTrk', b))));
}
export function satori411PerformanceMidi(nameVariant = 0, effects = 0, seed = null) {
  if (!Number.isInteger(effects) || effects < 0 || effects > 3) throw new Error('invalid sound effects');
  let x = satori411SongInputs(nameVariant);
  if (seed !== null) x = satori411PurchasedInputs(x, seed);
  if (effects) { x.score.tempo_us = Math.max(1, x.score.tempo_us - [0, 25000, 30000, 45000][effects]); x.score.articulation_profile = [0, 2, 5, 3][effects]; }
  return satori411Midi(x,{mega:effects===1||effects===3,echo:effects>=2});
}

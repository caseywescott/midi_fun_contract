// Writes loot/loot_contracts/src/front_tests.cairo: files from the deployed LootMidiProvider
// (compose / compose_drift; LootPureComposer and the pinned v1.1.0 BeastPureComposer declared) checked
// against what the Loot lab plays on the FM bank (its track(): band/choose, lifted, the volumes (MIX,
// LEAD_SOFT, LEAD_ALL, LEAD_DROP, NAME_SOFT), TOP_SOFT, and the setProgram override; orchestra_ref.mjs takes these from loot-lab.mjs): Songs
// (sound_effects 0: the lab's Mega is not v1.1's performance), Editions, Rounds and Sound Checks, with
// cases where MIX, TOP_SOFT and the low accompaniment instrument apply.
// Loot songs are identical under Beast Sound v1.0.1 and v1.1.0 (loot_contracts::v11_song_tests).
//   node scripts/front_parity.mjs <midi_fun_contract v1.0.1 checkout> [rounds]
//   sh scripts/cairo_run.sh scarb test -p loot_contracts -- front_ --include-ignored
import { writeFileSync, existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { LOOT_BEASTS } from '../offchain/loot-sound/src/loot_beasts.js';
import { SPECIES } from '../offchain/loot-sound/src/loot_species.js';
import { STYLES } from '../offchain/loot-sound/src/loot_styles.js';
import * as ED from '../offchain/loot-sound/src/loot_editions.js';
import { O, playedRef } from '../offchain/loot-sound/onchain/orchestra_ref.mjs';
const ref = process.argv[2], withRounds = process.argv[3] === 'rounds';
const src = (f) => import(pathToFileURL(join(ref, 'offchain/beast-sound/src', f)).href);
const L = await src('lab.js');
const { engine: E } = await src('index.js');
const V = (await src('engine_v11.js')).createEngineV11(E);
const anchor = L.dayAnchor();
const U64 = (1n << 64n) - 1n;
function purchaseSeed(n) { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); }
const sum = (u8) => { let h = 0; for (const b of u8) h = (Math.imul(h, 31) + b) >>> 0; return h; };
function remap(u8, band) {
  const out = u8.slice(); let i = 14; const ntr = (out[10] << 8) | out[11];
  for (let tr = 0; tr < ntr; tr++) {
    i += 4; const len = (out[i] << 24 | out[i + 1] << 16 | out[i + 2] << 8 | out[i + 3]) >>> 0; i += 4; const stop = i + len; let run = 0;
    while (i < stop) {
      let b; do { b = out[i++]; } while (b & 128);
      let s = out[i]; if (s & 128) i++; else s = run;
      if (s === 0xff) { i++; let l = 0; do { b = out[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; }
      if (s === 0xf0 || s === 0xf7) { let l = 0; do { b = out[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; }
      run = s; const ty = s & 0xf0;
      if (ty === 0xc0) { if ((s & 15) !== 9) out[i] = band[(s & 15) % band.length]; i += 1; continue; }
      if (ty === 0xd0) { i += 1; continue; }
      i += 2;
    }
    i = stop;
  }
  return out;
}
const hex = (x) => '0x' + BigInt(x).toString(16);
const drift = (day) => `DriftInputs { name_variant_id: 0, day: ${day}, day_hash: ${hex(anchor(day))}, week_hash: ${hex(anchor(Math.floor((day - 1) / 7) * 7 + 1))}, month_hash: ${hex(anchor(Math.floor((day - 1) / 30) * 30 + 1))} }`;
// a provider call: compose on day 1 (as written), compose_drift with the day's hashes after
const call = (inputs, mega, day) => (day > 1 ? `s.compose_drift(${inputs}, ${mega ? 1 : 0}, ${drift(day)})` : `s.compose(${inputs}, ${mega ? 1 : 0})`);
const beast = (id) => ({ ...LOOT_BEASTS[id - LOOT_BEASTS[0].id], ...SPECIES.find((s) => s.id === id) });
const dr = (id, day) => (day > 1 ? L.drift2({ id, prefix: 0, suffix: 0 }, day, anchor) : null);
const calls = []; let changed = 0;
const differs = (a, b) => { if (Buffer.compare(Buffer.from(a), Buffer.from(b))) changed++; };
for (const [id, name, day] of [[78, 0, 1], [92, 1242, 1], [82, 0, 45], [99, 12, 70], [105, 0, 290], [85, 0, 9], [85, 400, 45]]) {
  const x = LOOT_BEASTS[id - LOOT_BEASTS[0].id], n = L.nameFromVariant(name);
  const bb = { id, prefix: n.prefix, suffix: n.suffix, level: 1, health: 100, shiny: 0, animated: 0, tier: x.tier, beast_type: x.type };
  const opts = { ...L.GENESIS_DEFAULTS, ...(name ? { name } : {}), ...(day > 1 ? { epoch: day, driftMode: 'v2', blockHashes: true } : {}) };
  const midi = L.sampleTrackMidi(bb, { species_count: 1 }, opts, E, V).midi;
  const d = day > 1 ? L.drift2({ id, prefix: 0, suffix: 0 }, day, anchor) : null;
  const band = O.songBand(name ? 'name' : 'song', x.type, id, name, d);
  const out = remap(playedRef(name ? 'name' : 'song', midi, band), band);
  differs(out, remap(O.lifted(midi, name ? 12 : 0), band));
  calls.push(call(`LootInputs::Song(LootSongInputs { species: ${id}, name: ${name} })`, false, day), [out.length, sum(out)]);
}
const edCases = [[78, false, 1, 1, 1], [85, true, 5, 2, 1], [92, false, 9, 3, 45], [101, false, 13, 1, 290], [107, true, 15, 4, 9], [90, false, 22, 7, 100], [78, false, 15, 1, 1], [85, false, 3, 2, 1], [85, false, 10, 1, 1],
  // the edition mix (8c9284f): a high accompaniment, Speedrun an octave lower, Forest's drop and high, Speedrun high, Dungeon Dash's leads
  [78, false, 2, 3, 1], [78, false, 13, 2, 1], [98, false, 19, 1, 1], [88, false, 13, 4, 1], [78, false, 14, 3, 1]];
for (const [id, mega, e, p, day] of edCases) {
  const x = beast(id), d = dr(id, day), key = STYLES[(e - 1) % STYLES.length].key;
  const o = ED.editionMidi(x, mega, e, purchaseSeed(p), d, false, null);
  const band = O.band(key, id, e, p, d, o.info.accompLow);
  const out = remap(playedRef('edition', o.midi, band, key, { accompLow: o.info.accompLow, id, e, p }), band);
  differs(out, remap(o.midi, band));
  calls.push(call(`LootInputs::Edition(LootEditionInputs { species: ${id}, edition: ${e}, purchase: ${p} })`, mega, day), [out.length, sum(out)]);
}
if (withRounds) {
  const RD = await import('../offchain/loot-sound/src/loot_rounds.js');
  const CK = await import('../offchain/loot-sound/src/loot_checks.js');
  for (const [id, mega, r, day] of [[78, false, 0, 1], [86, true, 0, 1], [93, false, 3, 45], [102, false, 0, 290], [97, true, 2, 9], [86, false, 0, 1], [92, false, 2, 1]]) {
    const x = beast(id), d = dr(id, day);
    const midi = RD.roundMidi(x, mega, r ? purchaseSeed(r) : 0n, d).midi;
    const band = O.choose(O.ORCH.roundPools[x.type], O.ORCH.roundKinds, id, 2, d);
    const out = remap(playedRef('round', midi, band), band);
    differs(out, remap(O.lifted(midi, 7), band));
    calls.push(call(`LootInputs::Round(LootRoundInputs { species: ${id}, purchase: ${r} })`, mega, day), [out.length, sum(out)]);
  }
  for (const [id, mega, c] of [[79, false, 0], [88, true, 0], [98, false, 5], [105, true, 2], [87, false, 1], [92, false, 2]]) {
    const x = beast(id);
    const midi = CK.soundCheckMidi(x, mega, c ? purchaseSeed(c) : 0n).midi;
    const band = O.choose(O.ORCH.roundPools[x.type], O.ORCH.roundKinds, id, 2, null);
    const out = remap(playedRef('check', midi, band), band);
    differs(out, remap(midi, band));
    calls.push(call(`LootInputs::SoundCheck(LootSoundCheckInputs { species: ${id}, take: ${c} })`, mega, 1), [out.length, sum(out)]);
  }
}
let t = `// Generated by scripts/front_parity.mjs: do not edit.
use beast_composer::inputs::drift::DriftInputs;
use crate::interfaces::{
    ILootMidiProviderDispatcherTrait, LootEditionInputs, LootInputs, LootRoundInputs,
    LootSongInputs, LootSoundCheckInputs,
};
use crate::tests::{deploy, sum};
`;
for (let k = 0; k < calls.length; k += 2) {
  t += `\n#[test]\n#[ignore]\nfn front_${String(k / 2).padStart(2, '0')}() {\n    let s = deploy();\n    assert_eq!(sum(@${calls[k]}), (${calls[k + 1][0]}, ${calls[k + 1][1]}));\n}\n`;
}
writeFileSync(new URL('../loot/loot_contracts/src/front_tests.cairo', import.meta.url), t);
console.log('editions with the low accompaniment instrument:', edCases.filter(([id, mega, e, p, day]) => ED.editionMidi(beast(id), mega, e, purchaseSeed(p), dr(id, day), false, null).info.accompLow).length);
console.log(calls.length / 2, 'front cases,', changed, 'changed by the volumes or TOP_SOFT');

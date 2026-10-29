// Build public/onchain/drift-lab.html: three drift algorithms on a Beast's Species Song (its Genesis
// Track), side by side.
//   A  Contract: the reference evolution compose_staff plays (src/evolution.js resolveEvolution and
//      lab.js genesisMidi on that staff, byte for byte the Cairo: scripts/songs_staff_parity.mjs),
//      with every EvolutionConfig field editable and two labelled experiments.
//   B  Mutation chain (an idea, not in any contract): every block may mutate the track; each
//      mutation is permanent and they stack (a part joins, more ornaments, wider dynamics, a tempo
//      walk, pitch noise), so complexity grows until the track is noise.
//   C  Casey Drift: the layered calendar drift (lab.js drift2: a month's rhythm, a week's channel
//      order, a day's knob), byte for byte the Cairo song_smf_bytes with a DriftClock.
// A timeline charts how far each moves from the written track; settings travel in the URL.
//   node onchain/drift-lab-demo.mjs <webaudio-tinysynth-4bf9829.min.js> <onchain-midi-player checkout>
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { keccak } from '@scure/starknet';
import { beastName, poseidonHashMany } from '../src/index.js';
import { spriteSheet } from './lab-sprites.mjs';
import { loadBank } from './tinychip/essentials.mjs';
import { beastSynthSettings, variantPrograms, SETTINGS_VARIANTS, YETI_VARIANTS } from './tinychip/synth_settings.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const [engineFile, omp] = process.argv.slice(2);
if (!engineFile || !omp) { console.error('usage: node onchain/drift-lab-demo.mjs <engine .min.js> <onchain-midi-player checkout>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const bundle = (await build({
  stdin: {
    contents: `import { engine } from './src/index.js'; import { createEngineV11 } from './src/engine_v11.js';
      import { genesisMidi, H, labBlockHash, epochAtBlock, DRIFT_EPOCH_BLOCKS, GENESIS_CHANNELS, speciesTier } from './src/lab.js';
      import { resolveEvolution, validateEvolutionConfig } from './src/evolution.js';
      import { installSettings } from ${JSON.stringify(omp + '/player/settings.js')};
      window.BS = { engine, v11: createEngineV11(engine), genesisMidi, H, labBlockHash, epochAtBlock, DRIFT_EPOCH_BLOCKS, GENESIS_CHANNELS, speciesTier, resolveEvolution, validateEvolutionConfig, installSettings };`,
    resolveDir: here + '..', loader: 'js',
  },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;

const bank = loadBank();
const NAMES = Object.fromEntries(bank.PRESETS.map((p, i) => [p.program ?? i, p.name]));
const SPECIES = Array.from({ length: 75 }, (_, k) => ({ id: k + 1, name: beastName({ id: k + 1, prefix: 0, suffix: 0 }), tier: Math.floor((k % 25) / 5) + 1, type: Math.floor(k / 25) }));
const SPRITES = Object.fromEntries(SPECIES.map((s) => { const { n, w, png } = spriteSheet(String(s.id)); return [s.id, { n, w, png }]; }));
const GROUP_SELECTOR = keccak(new TextEncoder().encode('beasts_named_drift_v1'));
const GROUPS = SPECIES.map((s) => '0x' + poseidonHashMany([GROUP_SELECTOR, BigInt(s.id), 0n]).toString(16));
// the settings the composer serves a Species Song: the family's (beast_synth_settings), the Yeti's
const SETTINGS = { family: SETTINGS_VARIANTS.filter((v) => !v.mega).map((v) => beastSynthSettings(undefined, variantPrograms(v))), yeti: beastSynthSettings(undefined, variantPrograms(YETI_VARIANTS[0])) };
const DATA = { species: SPECIES, types: ['Magic', 'Hunter', 'Brute'], names: NAMES, groups: GROUPS, settings: SETTINGS };

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Drift Lab</title>
<link rel="icon" href="data:,">
<meta name="description" content="Three drift algorithms on a Beast's Species Song, side by side: the contract's evolution, a mutation chain, and Casey Drift.">
<style>
:root{--bg:#f6f4ef;--fg:#1d1b18;--mut:#6b655c;--card:#fff;--line:#e2ddd3;--acc:#7a3cff;--ok:#1f9d55;--warn:#b26b00;--c1:#7a3cff;--c2:#e0742a;--c3:#1f9d8c}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--warn:#f0b040;--c1:#a77bff;--c2:#f08a48;--c3:#3cc8b4}}
:root[data-theme="dark"]{--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--warn:#f0b040;--c1:#a77bff;--c2:#f08a48;--c3:#3cc8b4}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1120px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 16px;max-width:820px}
.tabs{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:14px}.tabs button{padding:10px 12px;border-radius:12px;border:2px solid var(--line);background:var(--card);color:var(--fg);text-align:left;cursor:pointer;font:inherit}
.tabs button b{display:block;font-size:15px}.tabs button span{display:block;color:var(--mut);font-size:12.5px}.tabs button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 12%,var(--card))}
.grid{display:grid;grid-template-columns:minmax(0,1fr) 380px;gap:14px}@media(max-width:900px){.grid{grid-template-columns:minmax(0,1fr)}.tabs{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px;min-width:0}
.sec{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em;margin:0 0 10px;display:flex;justify-content:space-between;align-items:center;gap:8px}
.stepper{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;margin-bottom:10px}.stepper .mid{text-align:center;min-width:0}.lbl{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}
.stepper .val{font-weight:650;font-size:16px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.stepper .val small{font-weight:400;color:var(--mut);font-size:13px}
button,select,input{font:inherit}button{cursor:pointer}button.nav{width:42px;height:42px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:17px}
.ctl{display:flex;gap:10px;flex-wrap:wrap}.ctl button{flex:1;min-width:110px;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600}.ctl button.go{background:var(--fg);color:var(--bg)}
.knob{display:grid;grid-template-columns:minmax(0,1fr) 92px;gap:4px 10px;align-items:center;margin-bottom:10px}.knob label{font-size:13.5px}.knob small{grid-column:1/-1;color:var(--mut);font-size:12px;margin-top:-4px}
.knob input[type=range]{grid-column:1/-1;width:100%;accent-color:var(--acc)}.knob input[type=number]{width:92px;padding:5px 8px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);text-align:right}
.badge{display:inline-block;border-radius:6px;padding:1px 8px;font-size:12px;font-weight:650;border:1px solid currentColor;text-transform:none;letter-spacing:0}.badge.ok{color:var(--ok)}.badge.exp{color:var(--warn)}
.err{color:#c0392b;font-size:13px;margin:4px 0 0}
.toggle{display:flex;gap:10px;align-items:flex-start;margin:8px 0;font-size:14px}.toggle input{margin-top:4px}.toggle small{display:block;color:var(--mut);font-size:12.5px}
.presets{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px}.presets button{padding:6px 10px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:13px}
.age{display:block;font-size:13px}.age input{width:100%;margin-top:6px;accent-color:var(--acc)}
#chart{width:100%;height:230px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card));cursor:crosshair;touch-action:none}
#roll{width:100%;height:170px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card))}
.legend{display:flex;flex-wrap:wrap;gap:4px 14px;margin-top:8px;font-size:12px;color:var(--mut)}.legend i{width:10px;height:10px;border-radius:3px;display:inline-block;margin-right:5px;vertical-align:-1px}
dl{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:4px 12px;margin:10px 0 0;font-size:13px}dt{color:var(--mut)}dd{margin:0;font-family:ui-monospace,monospace;font-size:12.5px;overflow-wrap:anywhere}
pre{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:10px;font-size:12px;overflow:auto;margin:8px 0 0;white-space:pre-wrap;overflow-wrap:anywhere}
.note{font-size:12.5px;color:var(--mut);margin:8px 0 0}.how{font-size:13.5px;margin:0;padding-left:18px}.how li{margin:2px 0}.kbd{font:11px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 4px}
#art{width:56px;height:56px;border-radius:8px;background:#000;image-rendering:pixelated;background-repeat:no-repeat;flex:none}.head{display:flex;gap:12px;align-items:center;margin-bottom:10px}.head b{display:block}.head span{color:var(--mut);font-size:13px}
.mode{display:none}.mode.on{display:block}
a{color:var(--acc)}
</style></head><body><main>
<h1>Drift Lab</h1>
<p class="sub">Three ways a Beast's song can change as blocks go by, all on its Species Song. A is what the contract does now (loothero's evolution). B is a mutation chain: every block may mutate the track, the mutations stack, and the song grows toward noise. C is Casey Drift, a calendar that varies the song by day, week and month without accumulating. The timeline shows how far each one moves the song from as written.</p>
<div class="tabs" role="tablist">
<button id="t-A" role="tab"><b>A · Contract evolution</b><span>loothero's: milestones unlock parts; notes re-roll each block</span></button>
<button id="t-B" role="tab"><b>B · Mutation chain</b><span>every block may mutate; mutations stack toward noise</span></button>
<button id="t-C" role="tab"><b>C · Casey Drift</b><span>day, week and month layers; nothing accumulates</span></button>
</div>
<div class="grid"><div>
<div class="card">
<div class="head"><div id="art" role="img" aria-label=""></div><div><b id="title"></b><span id="subtitle"></span></div></div>
<div class="stepper"><button class="nav" id="b-prev" aria-label="Previous Beast">◀</button><div class="mid"><div class="lbl">Species Song</div><div class="val" id="b-val"></div></div><button class="nav" id="b-next" aria-label="Next Beast">▶</button></div>
<div class="stepper"><button class="nav" id="s-prev" aria-label="Earlier birth">−</button><div class="mid"><div class="lbl">Track born at</div><div class="val" id="s-val"></div></div><button class="nav" id="s-next" aria-label="Later birth">+</button></div>
<div class="ctl"><button class="go" id="play">▶ Play</button><button id="stop">■ Stop</button><button id="ab">Compare: written</button></div>
</div>
<div class="card"><div class="sec"><span>Timeline</span><span id="badge"></span></div>
<canvas id="chart" width="1600" height="460" aria-label="Drift timeline"></canvas>
<div class="legend"><span><i style="background:var(--c1)"></i>parts changed</span><span><i style="background:var(--c2)"></i>tempo (BPM)</span><span><i style="background:var(--c3)"></i>notes changed from written</span><span id="marks"></span></div>
<label class="age" style="margin-top:12px"><span id="age-lbl"></span> <b id="age-val"></b><input type="range" id="age" min="0" max="1000" value="400" aria-label="Time since the track was born"></label>
<div class="ctl" style="margin-top:10px"><button id="lapse">▶ Time-lapse</button></div>
<dl id="readout"></dl>
</div>
<div class="card"><canvas id="roll" width="1600" height="340" aria-label="Notes at this moment"></canvas><div class="legend" id="legend"></div></div>
</div><div>
<div class="card mode" id="m-A"><div class="sec"><span>A · EvolutionConfig</span></div>
<div class="presets" id="presets"></div><div id="knobs"></div><p class="err" id="err"></p>
<div class="sec" style="margin-top:14px"><span>Experiments</span><span class="badge exp">not in the contract</span></div>
<label class="toggle"><input type="checkbox" id="x-persist"><span>Mutations persist until the next milestone<small>The notes and tempo are rolled from the latest milestone's hash instead of every block.</small></span></label>
<div class="knob"><label for="x-grow-n">Complexity grows with milestones</label><input type="number" id="x-grow-n" min="0" max="8" step="0.25"><input type="range" id="x-grow" min="0" max="8" step="0.25"><small>The velocity range and ornament chance are multiplied by 1 + growth × milestones ÷ 8.</small></div>
<ul class="how note"><li>There are 8 milestones, at birth + first age × 1, 2, 4 … 128. At each one, every locked part rolls once to join, and stays once it has.</li><li>Every block, the notes (velocity and octave ornaments) and the tempo re-roll from that block's hash. Nothing else carries over.</li><li>After the 8th milestone nothing new can happen.</li></ul>
</div>
<div class="card mode" id="m-B"><div class="sec"><span>B · Mutation chain</span><span class="badge exp">an idea, not in the contract</span></div>
<div id="bknobs"></div>
<ul class="how note"><li>Every block has a 1 in N chance of a mutation. Here a hash chain stands in for the block hashes.</li><li>Each mutation is permanent and they stack: a part joins, more octave ornaments, wider dynamics, a tempo step, or more pitch noise.</li><li>The notes stay as they are between mutations.</li><li>Only the ceilings cap the growth, so given time the track turns to noise.</li></ul>
</div>
<div class="card mode" id="m-C"><div class="sec"><span>C · Casey Drift</span><span class="badge ok">your Cairo (song_smf_bytes)</span></div>
<ul class="how"><li><b>Month</b> (30 days): two months in three re-pick the rhythm cells.</li><li><b>Week</b>: three weeks in four rotate which channels play, keeping the count, the theme and the low voice.</li><li><b>Day</b>: turns one knob. The key plan turns the other way, the episode directions swap, or the tempo moves −4, −2, +2 or +4 BPM.</li></ul>
<p class="note">Each day's version is a pure function of the song and the day, so nothing accumulates: the song wanders around its written form, and the same day always sounds the same. The page assumes 43,200 blocks a day, as the lab does, and seeds each day from its first block's hash.</p>
</div>
<div class="card"><div class="sec"><span>Export</span></div><pre id="export"></pre>
<div class="ctl" style="margin-top:8px"><button id="copy">Copy</button><button id="link">Copy link</button></div><p class="note" id="copied"></p></div>
</div></div>
<p class="note">The settings are the composer's for a Species Song: the family's presets, or the Yeti's for species 68. Block hashes are simulated. Keys: <span class="kbd">space</span> play/stop, <span class="kbd">,</span> <span class="kbd">.</span> step, <span class="kbd">1</span> <span class="kbd">2</span> <span class="kbd">3</span> mode. <a href="../">All pages</a> · <a href="editions-onchain.html">Editions Onchain</a> · <a href="lab.html">Lab</a></p>
</main>
<script>${inline(tiny)}</script>
<script>${inline(bundle)}</script>
<script>
const DATA = ${JSON.stringify(DATA)};
const SPRITES = ${JSON.stringify(SPRITES)};
const $ = (id) => document.getElementById(id), E = BS.engine, V = BS.v11;
const FIELDS = [
  ['first_milestone_age', 'First milestone (blocks after birth)', 1, 100000, 'The later milestones fall at 2, 4 … 128 times this.'],
  ['initial_unlock_bps', 'Unlock chance at the first milestone (bps)', 0, 10000, 'Each milestone rolls once per locked part.'],
  ['unlock_step_bps', 'Unlock chance added per milestone (bps)', 0, 1428, 'The 8th milestone has first + 7 × step, at most 10,000.'],
  ['max_extra_channels', 'Extra parts a staff may unlock', 0, 5, 'A Species Song has 6 parts; each tier keeps 3 to 5 of them.'],
  ['max_tempo_delta_bpm', 'Tempo nudge, up to ± (BPM)', 0, 4, 'Re-rolled every block.'],
  ['max_velocity_delta', 'Velocity drift, up to ± per note', 0, 16, 'Re-rolled every block.'],
  ['ornament_chance_bps', 'Octave ornament chance per note (bps)', 0, 10000, 'A note an eighth or longer plays its second half an octave away.'],
];
const PRESETS = {
  'Manager test config': { first_milestone_age: 5, initial_unlock_bps: 1000, unlock_step_bps: 500, max_extra_channels: 2, max_tempo_delta_bpm: 4, max_velocity_delta: 16, ornament_chance_bps: 1000 },
  'Gentle': { first_milestone_age: 20, initial_unlock_bps: 300, unlock_step_bps: 200, max_extra_channels: 1, max_tempo_delta_bpm: 1, max_velocity_delta: 4, ornament_chance_bps: 200 },
  'Restless': { first_milestone_age: 3, initial_unlock_bps: 3000, unlock_step_bps: 1000, max_extra_channels: 5, max_tempo_delta_bpm: 4, max_velocity_delta: 16, ornament_chance_bps: 4000 },
};
const BFIELDS = [
  ['mean', 'One mutation every N blocks, on average', 1, 2000, 'The chance per block is 1 in N.'],
  ['horizon', 'Timeline length (blocks)', 100, 200000, 'How far the chain and the chart run.'],
  ['orn_step', 'Ornament chance added per ornament mutation (bps)', 0, 3000, 'Up to 10,000.'],
  ['vel_step', 'Velocity range added per dynamics mutation', 0, 16, 'Up to ±64.'],
  ['noise_step', 'Pitch noise added per noise mutation (bps)', 0, 3000, 'The chance a note moves by up to an octave, up to 10,000.'],
  ['tempo_step', 'Tempo step per tempo mutation, up to ± (BPM)', 0, 8, 'A random walk, kept within ±24.'],
];
const st = { mode: 'A', s: 20, n: 1, t: { A: 20, B: 300, C: 30 }, cfg: { ...PRESETS['Manager test config'] }, persist: false, grow: 0,
  b: { mean: 20, horizon: 2000, orn_step: 600, vel_step: 4, noise_step: 400, tempo_step: 2 }, written: false };
let synth = null, playing = false, lapse = 0, cur = null, series = null, seriesKey = '', seriesJob = 0;

(function readUrl() {
  const q = new URLSearchParams(location.search), num = (k, lo, hi, d) => (q.has(k) ? Math.max(lo, Math.min(hi, Math.round(+q.get(k)) || 0)) : d);
  if (['A', 'B', 'C'].includes(q.get('mode'))) st.mode = q.get('mode');
  st.s = num('b', 1, 75, st.s + 1) - 1; st.n = num('p', 1, 1e6, st.n);
  for (const m of ['A', 'B', 'C']) st.t[m] = num('t' + m, 0, 1e9, st.t[m]);
  for (const [k, , lo, hi] of FIELDS) st.cfg[k] = num(k, lo, hi, st.cfg[k]);
  for (const [k, , lo, hi] of BFIELDS) st.b[k] = num('b_' + k, lo, hi, st.b[k]);
  st.persist = q.get('persist') === '1'; if (q.has('grow')) st.grow = Math.max(0, Math.min(8, +q.get('grow') || 0));
})();
function query() {
  const q = new URLSearchParams({ mode: st.mode, b: st.s + 1, p: st.n, tA: st.t.A, tB: st.t.B, tC: st.t.C, ...st.cfg });
  for (const [k] of BFIELDS) q.set('b_' + k, st.b[k]);
  if (st.persist) q.set('persist', '1'); if (st.grow) q.set('grow', st.grow);
  return '?' + q;
}

const sp = () => DATA.species[st.s];
const src = () => ({ 39: 40, 40: 39 }[sp().id] || sp().id);
const birth = () => 1000000n + 1000n * BigInt(st.n);
const available = () => 6 - BS.GENESIS_CHANNELS[BS.speciesTier(src())];
const group = () => DATA.groups[sp().id - 1];
// each mode's time axis: A and B in blocks, C in days; the slider is log-scaled to its range
const range = () => (st.mode === 'A' ? Math.ceil(st.cfg.first_milestone_age * 128 * 1.15) : st.mode === 'B' ? st.b.horizon : 400);
const toT = (v) => Math.round(Math.exp(v / 1000 * Math.log(range() + 1)) - 1), toPos = (t) => Math.log(t + 1) / Math.log(range() + 1);
const birthDay = () => BS.epochAtBlock(Number(birth())) + 1;
const experimental = () => st.mode === 'B' || (st.mode === 'A' && (st.persist || st.grow > 0));
function configError() { try { BS.validateEvolutionConfig(st.cfg); return ''; } catch (e) { return e.message; } }

// A: the contract's staff, then the experiments
function staffA(age) {
  const b = birth(), ctx = (a) => ({ birth: b, staff: b + BigInt(a), driftGroup: group(), hashOf: BS.labBlockHash });
  let c = BS.resolveEvolution(st.cfg, ctx(age), available());
  const k = c.milestones.length;
  if (st.persist) { const a = BS.resolveEvolution(st.cfg, ctx(k ? Number(c.milestones[k - 1].block - b) : 0), available()); c = { ...c, note_seed: a.note_seed, tempo_delta: a.tempo_delta }; }
  if (st.grow > 0) { const m = 1 + st.grow * k / 8; c = { ...c, max_velocity_delta: Math.min(64, Math.round(st.cfg.max_velocity_delta * m)), ornament_chance_bps: Math.min(10000, Math.round(st.cfg.ornament_chance_bps * m)) }; }
  return c;
}
// B: the mutation chain. The gaps between mutations are geometric with mean N (the same law as a 1 in
// N roll every block); each mutation's kind and its note seed come from the chain's hash.
let chainKey = '', chain = [];
function mutationsUpTo(age) {
  const key = [st.s, st.n, st.b.mean, st.b.horizon].join();
  if (key !== chainKey) {
    chainKey = key; chain = [];
    let h = BS.H('BEAST_MUTATION', BigInt(group()), BS.labBlockHash(birth())), at = 0;
    while (chain.length < 4000) {
      h = BS.H('BEAST_MUTATION', h);
      const u = (Number(h % 1000003n) + 1) / 1000004;
      at += Math.max(1, Math.round(-st.b.mean * Math.log(u)));
      if (at > st.b.horizon) break;
      chain.push({ at, kind: Number((h >> 64n) % 100n), h });
    }
  }
  return chain.filter((m) => m.at <= age);
}
function staffB(age) {
  const ms = mutationsUpTo(age), b = st.b;
  const c = { unlocked: 0, orn: 0, vel: 0, tempo: 0, noise: 0, note_seed: BS.labBlockHash(birth()), counts: { part: 0, ornaments: 0, dynamics: 0, tempo: 0, noise: 0 } };
  for (const m of ms) {
    let k = m.kind;
    if (k < 18 && c.unlocked >= available()) k = 18; // no part left: more ornaments instead
    if (k < 18) { c.unlocked++; c.counts.part++; }
    else if (k < 43) { c.orn = Math.min(10000, c.orn + b.orn_step); c.counts.ornaments++; }
    else if (k < 65) { c.vel = Math.min(64, c.vel + b.vel_step); c.counts.dynamics++; }
    else if (k < 80) { const step = 1 + Number((m.h >> 96n) % BigInt(Math.max(1, b.tempo_step))); c.tempo = Math.max(-24, Math.min(24, c.tempo + (Number((m.h >> 128n) % 2n) ? step : -step))); c.counts.tempo++; }
    else { c.noise = Math.min(10000, c.noise + b.noise_step); c.counts.noise++; }
    c.note_seed = m.h;
  }
  return { unlocked_extra_mask: (1 << c.unlocked) - 1, note_seed: c.note_seed, tempo_delta: b.tempo_step ? c.tempo : 0, max_velocity_delta: c.vel, ornament_chance_bps: c.orn, noise_bps: c.noise, mutations: ms.length, counts: c.counts };
}
// the song at time t on a mode's axis
function songAt(mode, t) {
  if (mode === 'C') { const day = birthDay() + t; const o = BS.genesisMidi(sp().id, false, E, V, { epoch: day, driftMode: 'v2', blockHashes: true }); return { o, day }; }
  const staff = mode === 'A' ? staffA(t) : staffB(t);
  return { o: BS.genesisMidi(sp().id, false, E, V, { staff }), staff };
}
let writtenKey = '', written = null;
function writtenSong() { const k = String(st.s); if (k !== writtenKey) { writtenKey = k; written = BS.genesisMidi(sp().id, false, E, V); } return written; }
function diff(o) {
  const key = (n) => n[0] + '|' + n[2] + '|' + n[3], w = notesOf(writtenSong().midi), d = notesOf(o.midi);
  const ws = new Set(w.notes.map(key)), ds = new Set(d.notes.map(key));
  const wv = new Set(w.notes.map((n) => n[3])), dv = new Set(d.notes.map((n) => n[3]));
  let changed = 0; for (const n of d.notes) if (!ws.has(key(n))) changed++;
  let gone = 0; for (const n of w.notes) if (!ds.has(key(n))) gone++;
  const parts = [...dv].filter((v) => !wv.has(v)).length + [...wv].filter((v) => !dv.has(v)).length;
  return { changed: Math.max(changed, gone), parts, total: d.notes.length };
}

// the timeline
function buildSeries() {
  const key = query().replace(/&?t[ABC]=\\d+/g, '');
  if (key === seriesKey) return; seriesKey = key;
  const job = ++seriesJob, mode = st.mode, N = 56, ts = [...new Set(Array.from({ length: N }, (_, i) => toT(i / (N - 1) * 1000)))];
  series = { mode, ts, pts: [] };
  let i = 0;
  (function step() {
    if (job !== seriesJob) return;
    const t0 = performance.now();
    while (i < ts.length && performance.now() - t0 < 30) {
      const r = songAt(mode, ts[i]), dd = diff(r.o);
      const tempo = mode === 'C' ? (r.o.drift.delta || 0) : r.staff.tempo_delta;
      series.pts.push({ t: ts[i], tempo, ...dd });
      i++;
    }
    chart();
    if (i < ts.length) setTimeout(step, 0);
  })();
}
function chart() {
  const cv = $('chart'), x = cv.getContext('2d'), W = cv.width, H = cv.height, css = getComputedStyle(document.body), col = (v) => css.getPropertyValue(v).trim(), fg = css.color;
  x.clearRect(0, 0, W, H);
  const pTop = 14, pH = 70, tTop = 100, tH = 140, oTop = 262, oH = 180, X = (t) => 20 + toPos(t) * (W - 40);
  x.font = '22px system-ui'; x.fillStyle = fg; x.globalAlpha = 0.55; x.fillText('parts', 24, pTop + 22); x.fillText('tempo', 24, tTop + 22); x.fillText('notes changed', 24, oTop + 22); x.globalAlpha = 1;
  // markers: A's milestones, B's mutations, C's weeks and months
  x.fillStyle = fg;
  if (st.mode === 'A') for (let k = 0; k < 8; k++) { x.globalAlpha = 0.2; x.fillRect(X(st.cfg.first_milestone_age * 2 ** k), 0, 2, H); }
  if (st.mode === 'B') { x.globalAlpha = 0.12; for (const m of mutationsUpTo(range())) x.fillRect(X(m.at), 0, 1.5, H); }
  if (st.mode === 'C') { const d0 = birthDay(); for (let t = 0; t <= range(); t++) { const d = d0 + t; if ((d - 1) % 30 === 0) { x.globalAlpha = 0.3; x.fillRect(X(t), 0, 2, H); } else if ((d - 1) % 7 === 0) { x.globalAlpha = 0.1; x.fillRect(X(t), 0, 1, H); } } }
  x.globalAlpha = 0.25; x.fillRect(20, tTop + tH / 2, W - 40, 1); x.globalAlpha = 1;
  if (series && series.mode === st.mode) {
    const maxT = Math.max(4, ...series.pts.map((p) => Math.abs(p.tempo))), maxO = Math.max(10, ...series.pts.map((p) => p.changed)), maxP = Math.max(1, ...series.pts.map((p) => p.parts));
    series.pts.forEach((p, i) => {
      const x0 = X(p.t), nx = i + 1 < series.pts.length ? X(series.pts[i + 1].t) : x0 + 6, w = Math.max(2, nx - x0 - 1);
      x.fillStyle = col('--c1'); const ph = p.parts / maxP * (pH - 28); x.fillRect(x0, pTop + pH - ph, w, ph);
      x.fillStyle = col('--c2'); x.beginPath(); x.arc(x0, tTop + tH / 2 - p.tempo / maxT * (tH / 2 - 8), 5, 0, 7); x.fill();
      x.fillStyle = col('--c3'); const h = p.changed / maxO * (oH - 30); x.fillRect(x0, oTop + oH - h, w, h);
    });
  }
  x.fillStyle = fg; x.fillRect(X(st.t[st.mode]) - 1.5, 0, 3, H);
}
$('chart').addEventListener('pointerdown', (ev) => { const r = $('chart').getBoundingClientRect(), p = ((ev.clientX - r.left) / r.width * 1600 - 20) / 1560; st.t[st.mode] = toT(Math.max(0, Math.min(1, p)) * 1000); change(); });

// display
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const COLORS = ['#7a3cff', '#e0742a', '#1f9d8c', '#c0392b', '#7f8c8d', '#2a7ae0', '#b8860b', '#888'];
const popcount = (m) => { let n = 0; while (m) { n += m & 1; m >>= 1; } return n; };
function show() {
  for (const m of ['A', 'B', 'C']) { $('t-' + m).classList.toggle('on', st.mode === m); $('m-' + m).classList.toggle('on', st.mode === m); }
  const err = st.mode === 'A' ? configError() : '';
  $('err').textContent = err ? 'Not a valid contract config: ' + err + '.' : '';
  knobsSync();
  const s = sp();
  $('b-val').innerHTML = s.id + '. ' + esc(s.name) + ' <small>tier ' + s.tier + ' ' + DATA.types[s.type] + '</small>';
  $('s-val').innerHTML = 'block ' + birth().toLocaleString() + ' <small>day ' + birthDay() + '</small>';
  const spr = SPRITES[s.id], el = $('art'); el.style.backgroundImage = 'url(data:image/png;base64,' + spr.png + ')'; el.style.backgroundSize = (spr.n * 56) + 'px 56px'; el.setAttribute('aria-label', s.name);
  const t = st.t[st.mode];
  $('age-lbl').textContent = st.mode === 'C' ? 'Day:' : 'Block:';
  $('age-val').textContent = st.mode === 'C' ? (birthDay() + t) + ' (' + t + ' days after birth)' : t.toLocaleString() + ' blocks after birth';
  $('age').value = Math.round(toPos(t) * 1000);
  $('marks').textContent = st.mode === 'A' ? '│ milestones' : st.mode === 'B' ? '│ mutations' : '│ weeks, months';
  $('badge').innerHTML = err ? '<span class="badge exp">invalid config</span>' : experimental() ? '<span class="badge exp">not in the contract</span>' : st.mode === 'C' ? '<span class="badge ok">your Cairo drift</span>' : '<span class="badge ok">exactly the contract</span>';
  $('export').textContent = exportText();
  history.replaceState(null, '', query());
  if (err) return;
  const r = songAt(st.mode, t), dd = diff(r.o);
  cur = { ...r, settings: src() === 68 ? DATA.settings.yeti : DATA.settings.family[DATA.species[src() - 1].type] };
  $('title').textContent = s.name + "'s Species Song"; $('subtitle').textContent = r.o.info.key + ' · ' + r.o.info.voices + ' voices · ' + r.o.info.tempo + ' BPM';
  let rows;
  if (st.mode === 'C') rows = [['Today', r.o.drift.label], ['Tempo', (r.o.drift.delta >= 0 ? '+' : '') + (r.o.drift.delta || 0) + ' BPM']];
  else if (st.mode === 'A') { const c = r.staff; rows = [['Milestones', c.milestones.length + ' of 8 reached'], ['Parts unlocked', popcount(c.unlocked_extra_mask) + ' of ' + Math.min(available(), st.cfg.max_extra_channels)], ['Tempo', (c.tempo_delta >= 0 ? '+' : '') + c.tempo_delta + ' BPM'], ['Velocity, ornaments', '±' + c.max_velocity_delta + ', ' + (c.ornament_chance_bps / 100).toFixed(1) + '%']]; }
  else { const c = r.staff, k = c.counts; rows = [['Mutations', c.mutations + ' so far (' + k.part + ' parts, ' + k.ornaments + ' ornaments, ' + k.dynamics + ' dynamics, ' + k.tempo + ' tempo, ' + k.noise + ' noise)'], ['Parts joined', popcount(c.unlocked_extra_mask) + ' of ' + available()], ['Tempo', (c.tempo_delta >= 0 ? '+' : '') + c.tempo_delta + ' BPM'], ['Velocity, ornaments, noise', '±' + c.max_velocity_delta + ', ' + (c.ornament_chance_bps / 100).toFixed(1) + '%, ' + (c.noise_bps / 100).toFixed(1) + '%']]; }
  rows.push(['From written', dd.changed + ' of ' + dd.total + ' notes changed' + (dd.parts ? ', ' + dd.parts + ' parts changed' : '')]);
  $('readout').innerHTML = rows.map(([a, b]) => '<dt>' + a + '</dt><dd>' + esc(b) + '</dd>').join('');
  roll(st.written ? writtenSong().midi : r.o.midi);
  $('ab').textContent = st.written ? 'Compare: drifted' : 'Compare: written';
  buildSeries(); chart();
}
function exportText() {
  if (st.mode === 'A') {
    const lines = ['EvolutionConfig {', ...FIELDS.map(([k]) => '    ' + k + ': ' + st.cfg[k] + ','), '}'];
    if (st.persist || st.grow) lines.push('// experiments (not in the contract): ' + [st.persist ? 'mutations persist until the next milestone' : '', st.grow ? 'complexity growth ' + st.grow : ''].filter(Boolean).join('; '));
    return lines.join('\\n');
  }
  if (st.mode === 'B') return '// mutation chain (an idea, not in the contract)\\n' + JSON.stringify(st.b, null, 2);
  return '// Casey Drift: drift.cairo layered_drift, no settings (43,200 blocks a day)';
}
function knobs() {
  const make = (host, fields, prefix) => { $(host).innerHTML = fields.map(([k, label, lo, hi, help]) => '<div class="knob"><label for="' + prefix + 'n-' + k + '">' + label + '</label><input type="number" id="' + prefix + 'n-' + k + '" min="' + lo + '" max="' + hi + '"><input type="range" id="' + prefix + 'k-' + k + '" min="' + lo + '" max="' + hi + '"><small>' + help + '</small></div>').join(''); };
  make('knobs', FIELDS, 'a'); make('bknobs', BFIELDS, 'b');
  for (const [k, , lo, hi] of FIELDS) { const set = (v) => { st.cfg[k] = Math.max(lo, Math.min(hi, Math.round(+v) || 0)); st.t.A = Math.min(st.t.A, range()); change(); }; $('ak-' + k).oninput = () => set($('ak-' + k).value); $('an-' + k).onchange = () => set($('an-' + k).value); }
  for (const [k, , lo, hi] of BFIELDS) { const set = (v) => { st.b[k] = Math.max(lo, Math.min(hi, Math.round(+v) || 0)); st.t.B = Math.min(st.t.B, range()); change(); }; $('bk-' + k).oninput = () => set($('bk-' + k).value); $('bn-' + k).onchange = () => set($('bn-' + k).value); }
  $('presets').innerHTML = Object.keys(PRESETS).map((n) => '<button data-p="' + esc(n) + '">' + esc(n) + '</button>').join('');
  $('presets').querySelectorAll('button').forEach((b) => b.onclick = () => { st.cfg = { ...PRESETS[b.dataset.p] }; st.t.A = Math.min(st.t.A, range()); change(); });
}
function knobsSync() {
  for (const [k] of FIELDS) { $('ak-' + k).value = st.cfg[k]; if (document.activeElement !== $('an-' + k)) $('an-' + k).value = st.cfg[k]; }
  for (const [k] of BFIELDS) { $('bk-' + k).value = st.b[k]; if (document.activeElement !== $('bn-' + k)) $('bn-' + k).value = st.b[k]; }
  $('x-persist').checked = st.persist; $('x-grow').value = st.grow; if (document.activeElement !== $('x-grow-n')) $('x-grow-n').value = st.grow;
}

function notesOf(u8) {
  const notes = [], prog = {}; let end = 0, i = 14, ntr = (u8[10] << 8) | u8[11];
  for (let tr = 0; tr < ntr; tr++) {
    i += 4; const len = (u8[i] << 24 | u8[i + 1] << 16 | u8[i + 2] << 8 | u8[i + 3]) >>> 0; i += 4; const stop = i + len; let t = 0, run = 0; const on = {};
    while (i < stop) {
      let d = 0, b; do { b = u8[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d;
      let s = u8[i]; if (s & 128) i++; else s = run;
      if (s === 0xff) { const ty = u8[i++]; let l = 0; do { b = u8[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; if (ty === 0x2f) end = Math.max(end, t); continue; }
      run = s; const ty = s & 0xf0, ch = s & 15;
      if (ty === 0xc0 || ty === 0xd0) { if (ty === 0xc0) prog[ch] = u8[i]; i += 1; continue; }
      const a = u8[i], v = u8[i + 1]; i += 2;
      if (ty === 0x90 && v) on[ch * 128 + a] = [t, v];
      else if (ty === 0x80 || ty === 0x90) { const k = ch * 128 + a; if (on[k] !== undefined) { notes.push([on[k][0], t, a, ch, on[k][1]]); delete on[k]; } }
    }
    i = stop;
  }
  return { notes, prog, end: Math.max(end, ...notes.map((n) => n[1])) };
}
let rollData = null;
function roll(midi) {
  rollData = notesOf(midi);
  const chans = [...new Set(rollData.notes.map((n) => n[3]))].sort((a, b) => a - b);
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + (ch === 9 ? 'var(--mut)' : COLORS[ch % 8]) + '"></i>' + (ch === 9 ? 'drums' : 'ch' + (ch + 1) + ' · ' + esc(DATA.names[rollData.prog[ch]] || '')) + '</span>').join('') + '<span>brightness = velocity</span>';
  draw(-1);
}
function draw(play) {
  const c = $('roll'), x = c.getContext('2d'), W = c.width, H = c.height, d = rollData; x.clearRect(0, 0, W, H); if (!d || !d.notes.length) return;
  const tones = d.notes.filter((n) => n[3] !== 9), lo = Math.min(...tones.map((n) => n[2])) - 2, hi = Math.max(...tones.map((n) => n[2])) + 2, ph = H - 40, sx = W / d.end, fg = getComputedStyle(document.body).color;
  for (const [a, b, p, ch, v] of d.notes) {
    x.globalAlpha = 0.25 + 0.75 * v / 127;
    if (ch === 9) { x.fillStyle = fg; x.fillRect(a * sx, H - 30 + (p % 8) * 3, Math.max(2, (b - a) * sx * 0.5), 3); continue; }
    x.fillStyle = COLORS[ch % 8]; x.fillRect(a * sx, 4 + (hi - p) / (hi - lo) * ph, Math.max(2, (b - a) * sx - 1), Math.max(3, ph / (hi - lo) - 1));
  }
  x.globalAlpha = 1; if (play >= 0) { x.fillStyle = fg; x.fillRect((play % d.end) * sx, 0, 3, H); }
}
(function loop() { if (playing && synth && synth.tick2Time) draw(synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time); requestAnimationFrame(loop); })();

function start() {
  if (!cur) return;
  if (!synth) synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  synth.getAudioContext().resume(); synth.stopMIDI();
  BS.installSettings(synth, cur.settings);
  const m = st.written ? writtenSong().midi : cur.o.midi;
  synth.loadMIDI(m.buffer.slice(m.byteOffset, m.byteOffset + m.length));
  synth.setLoop(1); synth.setLoopEnd(synth.getPlayStatus().maxTick); synth.playMIDI(); playing = true;
}
function stop() { if (synth) synth.stopMIDI(); playing = false; clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; draw(-1); }
function change() { show(); if (playing) start(); }
function toggleLapse() {
  if (lapse) { clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; return; }
  if (st.t[st.mode] >= range()) st.t[st.mode] = 0;
  if (!playing) { show(); start(); }
  $('lapse').textContent = '■ Stop time-lapse';
  lapse = setInterval(() => { const m = st.mode; st.t[m] = Math.min(range(), st.t[m] + Math.max(1, Math.round(st.t[m] / 6))); change(); if (st.t[m] >= range()) toggleLapse(); }, 5000);
}
const setMode = (m) => { st.mode = m; seriesKey = ''; change(); };
for (const m of ['A', 'B', 'C']) $('t-' + m).onclick = () => setMode(m);
const step = (k, d) => { if (k === 's') st.s = (st.s + d + 75) % 75; if (k === 'n') st.n = Math.max(1, st.n + d); change(); };
$('b-prev').onclick = () => step('s', -1); $('b-next').onclick = () => step('s', 1);
$('s-prev').onclick = () => step('n', -1); $('s-next').onclick = () => step('n', 1);
$('play').onclick = start; $('stop').onclick = stop; $('lapse').onclick = toggleLapse;
$('ab').onclick = () => { st.written = !st.written; change(); };
$('age').oninput = () => { st.t[st.mode] = toT(+$('age').value); show(); }; $('age').onchange = () => { if (playing) start(); };
$('x-persist').onchange = () => { st.persist = $('x-persist').checked; change(); };
$('x-grow').oninput = () => { st.grow = +$('x-grow').value; change(); }; $('x-grow-n').onchange = () => { st.grow = Math.max(0, Math.min(8, +$('x-grow-n').value || 0)); change(); };
const copy = async (text, what) => { try { await navigator.clipboard.writeText(text); $('copied').textContent = 'Copied ' + what + '.'; } catch { $('copied').textContent = 'Clipboard unavailable: select the text above.'; } };
$('copy').onclick = () => copy(exportText(), 'the settings'); $('link').onclick = () => copy(location.href, 'the link');
document.addEventListener('keydown', (ev) => {
  if (ev.target.tagName === 'INPUT' || ev.metaKey || ev.ctrlKey) return;
  if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); }
  else if (ev.key === ',' || ev.key === '.') { const m = st.mode; st.t[m] = Math.max(0, Math.min(range(), st.t[m] + (ev.key === '.' ? 1 : -1))); change(); }
  else if (['1', '2', '3'].includes(ev.key)) setMode('ABC'[+ev.key - 1]);
});
knobs(); show();
</script></body></html>`;
writeFileSync(new URL('../public/onchain/drift-lab.html', import.meta.url), html);
console.log('drift-lab.html', html.length, 'bytes');

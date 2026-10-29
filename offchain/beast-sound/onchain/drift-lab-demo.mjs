// Build public/onchain/drift-lab.html: a workbench for the Beast drift (evolution) algorithm on
// Monthly Track Edition tracks. The contract settings (EvolutionConfig, every field within
// validate_evolution_config's limits) play exactly what BeastPureComposer.compose_staff returns
// (src/evolution.js resolveEvolution and editions_lite.js staffed tracks, byte for byte the Cairo).
// Experiments (labelled as not in the contract) try changes to the algorithm itself: mutations that
// persist until the next milestone, and variation that grows with the milestones reached. A
// timeline charts every staff block; the settings travel in the URL and export as a Cairo literal.
//   node onchain/drift-lab-demo.mjs <webaudio-tinysynth-4bf9829.min.js> <onchain-midi-player checkout>
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { keccak } from '@scure/starknet';
import { beastName, poseidonHashMany } from '../src/index.js';
import { speciesRecords } from './editions_cairo.mjs';
import { spriteSheet } from './lab-sprites.mjs';
import { loadBank } from './tinychip/essentials.mjs';
import { editionSynthSettings, serializeSettings } from './tinychip/synth_settings.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const [engineFile, omp] = process.argv.slice(2);
if (!engineFile || !omp) { console.error('usage: node onchain/drift-lab-demo.mjs <engine .min.js> <onchain-midi-player checkout>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const bundle = (await build({
  stdin: {
    contents: `import * as ed from './src/editions_lite.js';
      import { resolveEvolution, validateEvolutionConfig } from './src/evolution.js'; import { labBlockHash } from './src/lab.js';
      import { installSettings } from ${JSON.stringify(omp + '/player/settings.js')};
      window.BS = { ed, installSettings, resolveEvolution, validateEvolutionConfig, labBlockHash };`,
    resolveDir: here + '..', loader: 'js',
  },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;

// The edition settings, each checked against the contract's hashes (as editions-onchain-demo.mjs).
const cairo = readFileSync(here + '../../../beasts/beast_contracts/src/synth_settings.cairo', 'utf8');
const CAIRO_HASHES = cairo.match(/EDITION_SERDE_HASHES: \[felt252; 24\] = \[([^\]]+)\]/)[1].split(',').map((s) => s.trim());
const SETTINGS = [];
for (let style = 0; style < 4; style++) for (let t = 0; t < 3; t++) for (const mega of [false, true]) {
  const s = editionSynthSettings(style, t, mega), i = (style * 3 + t) * 2 + (mega ? 1 : 0);
  if ('0x' + poseidonHashMany(serializeSettings(s)).toString(16) !== CAIRO_HASHES[i]) throw new Error('edition settings differ from the contract');
  SETTINGS[i] = s;
}
const bank = loadBank();
const NAMES = Object.fromEntries(bank.PRESETS.map((p, i) => [p.program ?? i, p.name]));
const SPECIES = speciesRecords().map((s) => ({ ...s, name: beastName({ id: s.id, prefix: 0, suffix: 0 }) }));
const SPRITES = Object.fromEntries(SPECIES.map((s) => { const { n, w, png } = spriteSheet(String(s.id)); return [s.id, { n, w, png }]; }));
const GROUP_SELECTOR = keccak(new TextEncoder().encode('beasts_named_drift_v1'));
const GROUPS = SPECIES.map((s) => '0x' + poseidonHashMany([GROUP_SELECTOR, BigInt(s.id), 0n]).toString(16));
const DATA = { species: SPECIES, types: ['Magic', 'Hunter', 'Brute'], settings: SETTINGS, names: NAMES, groups: GROUPS };

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Drift Lab</title>
<link rel="icon" href="data:,">
<meta name="description" content="Tune the Beast drift (evolution) algorithm on Monthly Track Edition tracks: contract settings, experiments, a timeline of every staff block.">
<style>
:root{--bg:#f6f4ef;--fg:#1d1b18;--mut:#6b655c;--card:#fff;--line:#e2ddd3;--acc:#7a3cff;--ok:#1f9d55;--warn:#b26b00;--c1:#7a3cff;--c2:#e0742a;--c3:#1f9d8c}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--warn:#f0b040;--c1:#a77bff;--c2:#f08a48;--c3:#3cc8b4}}
:root[data-theme="dark"]{--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--warn:#f0b040;--c1:#a77bff;--c2:#f08a48;--c3:#3cc8b4}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1120px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 18px;max-width:800px}
.grid{display:grid;grid-template-columns:minmax(0,1fr) 380px;gap:14px}@media(max-width:900px){.grid{grid-template-columns:minmax(0,1fr)}}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px;min-width:0}
.sec{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em;margin:0 0 10px;display:flex;justify-content:space-between;align-items:center;gap:8px}
.stepper{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;margin-bottom:10px}.stepper .mid{text-align:center;min-width:0}.lbl{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}
.stepper .val{font-weight:650;font-size:16px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.stepper .val small{font-weight:400;color:var(--mut);font-size:13px}
button,select,input{font:inherit}button{cursor:pointer}button.nav{width:42px;height:42px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:17px}
.ctl{display:flex;gap:10px;flex-wrap:wrap}.ctl button,.ctl select{flex:1;min-width:120px;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600}.ctl button.go{background:var(--fg);color:var(--bg)}
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
.note{font-size:12.5px;color:var(--mut);margin:8px 0 0}.kbd{font:11px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 4px}
#art{width:56px;height:56px;border-radius:8px;background:#000;image-rendering:pixelated;background-repeat:no-repeat;flex:none}.head{display:flex;gap:12px;align-items:center;margin-bottom:10px}.head b{display:block}.head span{color:var(--mut);font-size:13px}
a{color:var(--acc)}
</style></head><body><main>
<h1>Drift Lab</h1>
<p class="sub">Tune how a Beast's track drifts as blocks go by. With the contract settings, the page plays exactly what the composer's <code>compose_staff</code> returns for a Monthly Track Edition track. The experiments change the algorithm itself, are marked as not in the contract, and are there for trying ideas before porting them.</p>
<div class="grid"><div>
<div class="card">
<div class="head"><div id="art" role="img" aria-label=""></div><div><b id="title"></b><span id="subtitle"></span></div></div>
<div class="stepper"><button class="nav" id="e-prev" aria-label="Previous edition">▲</button><div class="mid"><div class="lbl">Edition</div><div class="val" id="e-val"></div></div><button class="nav" id="e-next" aria-label="Next edition">▼</button></div>
<div class="stepper"><button class="nav" id="b-prev" aria-label="Previous Beast">◀</button><div class="mid"><div class="lbl">Beast</div><div class="val" id="b-val"></div></div><button class="nav" id="b-next" aria-label="Next Beast">▶</button></div>
<div class="stepper"><button class="nav" id="s-prev" aria-label="Previous purchase">−</button><div class="mid"><div class="lbl">Purchase</div><div class="val" id="s-val"></div></div><button class="nav" id="s-next" aria-label="Next purchase">+</button></div>
<div class="ctl"><button class="go" id="play">▶ Play</button><button id="stop">■ Stop</button><button id="ab">Compare: written</button></div>
</div>
<div class="card"><div class="sec"><span>Timeline: every staff block</span><span id="badge"></span></div>
<canvas id="chart" width="1600" height="460" aria-label="Drift timeline"></canvas>
<div class="legend"><span><i style="background:var(--c1)"></i>pad unlocked</span><span><i style="background:var(--c2)"></i>tempo nudge (BPM)</span><span><i style="background:var(--c3)"></i>octave ornaments</span><span>│ milestones · click to jump</span></div>
<label class="age" style="margin-top:12px">Staff block: <b id="age-val"></b><input type="range" id="age" min="0" max="1000" value="300" aria-label="Staff block"></label>
<div class="ctl" style="margin-top:10px"><button id="lapse">▶ Time-lapse</button></div>
<dl id="readout"></dl>
</div>
<div class="card"><canvas id="roll" width="1600" height="340" aria-label="Notes at this staff block"></canvas><div class="legend" id="legend"></div></div>
</div><div>
<div class="card"><div class="sec"><span>Contract settings (EvolutionConfig)</span></div>
<div class="presets" id="presets"></div>
<div id="knobs"></div>
<p class="err" id="err"></p>
</div>
<div class="card"><div class="sec"><span>Experiments</span><span class="badge exp">not in the contract</span></div>
<label class="toggle"><input type="checkbox" id="x-persist"><span>Mutations persist until the next milestone<small>The note performance and tempo are rolled from the latest milestone's hash, not every staff block, so each mutation stays until the next one hits. This is loothero's "DNA" idea.</small></span></label>
<div class="knob"><label for="x-grow">Complexity grows with milestones</label><input type="number" id="x-grow-n" min="0" max="8" step="0.25"><input type="range" id="x-grow" min="0" max="8" step="0.25"><small>The velocity range and ornament chance are multiplied by 1 + growth × milestones reached ÷ 8. At 0 this matches the contract; push it up to drift toward noise.</small></div>
</div>
<div class="card"><div class="sec"><span>Export</span></div>
<pre id="export"></pre>
<div class="ctl" style="margin-top:8px"><button id="copy">Copy for Cairo</button><button id="link">Copy link</button></div>
<p class="note" id="copied"></p>
</div>
</div></div>
<p class="note">Edition tracks have one role a staff can unlock: the pad of tier 3 to 5 Beasts (songs can unlock up to 5). Block hashes are simulated, and purchase n is bought at block 1,000,000 + 1,000 n. Keys: <span class="kbd">space</span> play/stop, <span class="kbd">,</span> <span class="kbd">.</span> staff block. <a href="../">All pages</a> · <a href="editions-onchain.html">Editions Onchain</a></p>
</main>
<script>${inline(tiny)}</script>
<script>${inline(bundle)}</script>
<script>
const DATA = ${JSON.stringify(DATA)};
const SPRITES = ${JSON.stringify(SPRITES)};
const $ = (id) => document.getElementById(id), ED = BS.ed, N_ED = 48, U64 = (1n << 64n) - 1n;
const FIELDS = [
  ['first_milestone_age', 'First milestone (blocks after purchase)', 1, 100000, 'Milestones then fall at 2, 4 … 128 times this.'],
  ['initial_unlock_bps', 'Unlock chance at the first milestone (bps)', 0, 10000, 'Each milestone rolls once per locked role.'],
  ['unlock_step_bps', 'Unlock chance added per milestone (bps)', 0, 1428, 'The 8th milestone has first + 7 × step, at most 10,000.'],
  ['max_extra_channels', 'Extra roles a staff may unlock', 0, 5, 'Editions offer one: the pad of tiers 3 to 5.'],
  ['max_tempo_delta_bpm', 'Tempo nudge, up to ± (BPM)', 0, 4, 'Rolled every staff block.'],
  ['max_velocity_delta', 'Velocity drift, up to ± per note', 0, 16, 'Each note, every staff block.'],
  ['ornament_chance_bps', 'Octave ornament chance per note (bps)', 0, 10000, 'An eighth or longer plays its second half an octave away.'],
];
const PRESETS = {
  'Manager test config': { first_milestone_age: 5, initial_unlock_bps: 1000, unlock_step_bps: 500, max_extra_channels: 2, max_tempo_delta_bpm: 4, max_velocity_delta: 16, ornament_chance_bps: 1000 },
  'Gentle': { first_milestone_age: 20, initial_unlock_bps: 300, unlock_step_bps: 200, max_extra_channels: 1, max_tempo_delta_bpm: 1, max_velocity_delta: 4, ornament_chance_bps: 200 },
  'Restless': { first_milestone_age: 3, initial_unlock_bps: 3000, unlock_step_bps: 1000, max_extra_channels: 5, max_tempo_delta_bpm: 4, max_velocity_delta: 16, ornament_chance_bps: 4000 },
  'Slow (1,000-block first milestone)': { first_milestone_age: 1000, initial_unlock_bps: 1000, unlock_step_bps: 500, max_extra_channels: 2, max_tempo_delta_bpm: 4, max_velocity_delta: 16, ornament_chance_bps: 1000 },
};
const st = { e: 1, s: 20, n: 1, age: 20, cfg: { ...PRESETS['Manager test config'] }, persist: false, grow: 0, written: false };
let synth = null, playing = false, lapse = 0, cur = null, series = null, seriesKey = '', seriesJob = 0;

(function readUrl() {
  const q = new URLSearchParams(location.search), num = (k, lo, hi, d) => (q.has(k) ? Math.max(lo, Math.min(hi, Math.round(+q.get(k)) || 0)) : d);
  st.e = num('e', 1, N_ED, st.e); st.s = num('b', 1, 75, st.s + 1) - 1; st.n = num('p', 1, 1e6, st.n); st.age = num('age', 0, 1e9, st.age);
  for (const [k, , lo, hi] of FIELDS) if (q.has(k)) st.cfg[k] = num(k, lo, hi, st.cfg[k]);
  st.persist = q.get('persist') === '1'; if (q.has('grow')) st.grow = Math.max(0, Math.min(8, +q.get('grow') || 0));
})();
function query() { const q = new URLSearchParams({ e: st.e, b: st.s + 1, p: st.n, age: st.age, ...st.cfg }); if (st.persist) q.set('persist', '1'); if (st.grow) q.set('grow', st.grow); return '?' + q; }

function purchaseSeed(n) { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); }
const birthOf = (n) => 1000000n + 1000n * BigInt(n);
const lastMilestone = () => st.cfg.first_milestone_age * 128;
const ageMax = () => Math.ceil(lastMilestone() * 1.15);
const toAge = (v) => Math.round(Math.exp(v / 1000 * Math.log(ageMax() + 1)) - 1), toPos = (a) => Math.log(a + 1) / Math.log(ageMax() + 1);
const experimental = () => st.persist || st.grow > 0;
function configError() { try { BS.validateEvolutionConfig(st.cfg); return ''; } catch (e) { return e.message; } }

// The staff controls at age blocks after the purchase: the contract's (resolveEvolution), then the
// experiments on top.
function controlsAt(sp, age) {
  const birth = birthOf(st.n), ctx = (a) => ({ birth, staff: birth + BigInt(a), driftGroup: DATA.groups[sp.id - 1], hashOf: BS.labBlockHash });
  const avail = sp.tier > 2 ? 1 : 0;
  let c = BS.resolveEvolution(st.cfg, ctx(age), avail);
  const k = c.milestones.length;
  if (st.persist) {
    const anchor = k ? Number(c.milestones[k - 1].block - birth) : 0;
    const a = BS.resolveEvolution(st.cfg, ctx(anchor), avail);
    c = { ...c, note_seed: a.note_seed, tempo_delta: a.tempo_delta };
  }
  if (st.grow > 0) {
    const m = 1 + st.grow * k / 8;
    c = { ...c, max_velocity_delta: Math.min(126, Math.round(st.cfg.max_velocity_delta * m)), ornament_chance_bps: Math.min(10000, Math.round(st.cfg.ornament_chance_bps * m)) };
  }
  return c;
}
function trackAt(sp, age) {
  const seed = purchaseSeed(st.n), g = ED.editionGenome(st.e), mega = false;
  return { staff: controlsAt(sp, age), g, seed, mega };
}
function counts(midi) { const c = {}; for (const n of notesOf(midi).notes) c[n[3]] = (c[n[3]] || 0) + 1; return c; }

function compose() {
  const sp = DATA.species[st.s], t = trackAt(sp, st.age);
  const written = ED.editionMidi(sp, false, st.e, t.seed);
  const staffed = ED.editionMidi(sp, false, st.e, t.seed, t.staff);
  return { sp, ...t, written, staffed, settings: DATA.settings[(t.g.style * 3 + sp.type) * 2] };
}

// ── the timeline: the staff controls and the notes at log-spaced blocks, composed a few per frame ──
function buildSeries() {
  const key = query().replace(/&?age=\\d+/, '');
  if (key === seriesKey) return; seriesKey = key;
  const job = ++seriesJob, sp = DATA.species[st.s], N = 140, ages = [...new Set(Array.from({ length: N }, (_, i) => toAge(i / (N - 1) * 1000)))];
  const seed = purchaseSeed(st.n), w = counts(ED.editionMidi(sp, false, st.e, seed).midi);
  series = { ages, pts: [], w };
  let i = 0;
  (function step() {
    if (job !== seriesJob) return;
    const t0 = performance.now();
    while (i < ages.length && performance.now() - t0 < 12) {
      const c = controlsAt(sp, ages[i]), d = counts(ED.editionMidi(sp, false, st.e, seed, c).midi);
      let orn = 0; for (const ch of Object.keys(d)) if (+ch !== 4 || w[4]) orn += d[ch] - (w[ch] || 0);
      series.pts.push({ age: ages[i], pad: sp.tier > 2 && c.unlocked_extra_mask % 2 === 1, tempo: c.tempo_delta, orn, k: c.milestones.length });
      i++;
    }
    chart();
    if (i < ages.length) requestAnimationFrame(step);
  })();
}
function chart() {
  const cv = $('chart'), x = cv.getContext('2d'), W = cv.width, H = cv.height, css = getComputedStyle(document.body);
  const col = (v) => css.getPropertyValue(v).trim(), fg = css.color;
  x.clearRect(0, 0, W, H);
  const padY = 16, bandH = 30, tTop = 70, tH = 150, oTop = 250, oH = 180, X = (a) => 20 + toPos(a) * (W - 40);
  x.font = '22px system-ui'; x.fillStyle = fg; x.globalAlpha = 0.55;
  x.fillText('pad', 24, padY + 22); x.fillText('tempo', 24, tTop + 22); x.fillText('ornaments', 24, oTop + 22); x.globalAlpha = 1;
  for (let k = 0; k < 8; k++) { const a = st.cfg.first_milestone_age * 2 ** k; x.fillStyle = fg; x.globalAlpha = 0.18; x.fillRect(X(a), 0, 2, H); x.globalAlpha = 1; }
  x.globalAlpha = 0.25; x.fillStyle = fg; x.fillRect(20, tTop + tH / 2, W - 40, 1); x.globalAlpha = 1;
  if (series) {
    const maxT = Math.max(1, st.cfg.max_tempo_delta_bpm), maxO = Math.max(4, ...series.pts.map((p) => p.orn));
    series.pts.forEach((p, i) => {
      const nx = i + 1 < series.pts.length ? X(series.pts[i + 1].age) : X(p.age) + 6, x0 = X(p.age);
      if (p.pad) { x.fillStyle = col('--c1'); x.fillRect(x0, padY, Math.max(2, nx - x0), bandH); }
      x.fillStyle = col('--c2'); x.beginPath(); x.arc(x0, tTop + tH / 2 - p.tempo / maxT * (tH / 2 - 8), 5, 0, 7); x.fill();
      x.fillStyle = col('--c3'); const h = p.orn / maxO * (oH - 30); x.fillRect(x0, oTop + oH - h, Math.max(2, nx - x0 - 1), h);
    });
  }
  x.fillStyle = fg; x.fillRect(X(st.age) - 1.5, 0, 3, H);
}
$('chart').addEventListener('pointerdown', (ev) => {
  const r = $('chart').getBoundingClientRect(), p = ((ev.clientX - r.left) / r.width * 1600 - 20) / (1600 - 40);
  st.age = toAge(Math.max(0, Math.min(1, p)) * 1000); change();
});

// ── display ──
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const ROLE = { 0: 'lead', 2: 'accomp', 3: 'bass', 4: 'pad', 5: 'mega double' };
const COLORS = ['#7a3cff', '#e0742a', '#1f9d8c', '#c0392b', '#7f8c8d', '#2a7ae0'];
function show() {
  const err = configError();
  $('err').textContent = err ? 'Not a valid contract config: ' + err + '.' : '';
  knobsSync();
  if (err) { $('badge').innerHTML = '<span class="badge exp">invalid config</span>'; return; }
  cur = compose();
  const { sp, g, staff } = cur;
  $('title').textContent = g.name; $('subtitle').textContent = 'Edition ' + st.e + ' · ' + ED.ENGINES[g.engine].label + ' · ' + sp.name + ', tier ' + sp.tier + ' ' + DATA.types[sp.type];
  $('e-val').innerHTML = st.e + ' · ' + esc(g.name);
  $('b-val').innerHTML = sp.id + '. ' + esc(sp.name) + ' <small>tier ' + sp.tier + '</small>';
  $('s-val').innerHTML = '#' + st.n + ' <small>block ' + birthOf(st.n) + '</small>';
  $('badge').innerHTML = experimental() ? '<span class="badge exp">experiment: not in the contract</span>' : '<span class="badge ok">exactly the contract</span>';
  $('age').value = Math.round(toPos(st.age) * 1000);
  $('age-val').textContent = st.age.toLocaleString() + ' blocks after the purchase';
  const w = counts(cur.written.midi), d = counts(cur.staffed.midi);
  let orn = 0; for (const ch of Object.keys(d)) if (+ch !== 4 || w[4]) orn += d[ch] - (w[ch] || 0);
  const pad = sp.tier <= 2 ? 'plays as written (tier ' + sp.tier + ')' : staff.unlocked_extra_mask % 2 ? 'unlocked (+' + ((d[4] || 0) - (w[4] || 0)) + ' notes)' : 'locked';
  $('readout').innerHTML = [['Milestones', staff.milestones.length + ' of 8 reached'], ['Pad', pad], ['Tempo', (staff.tempo_delta >= 0 ? '+' : '') + staff.tempo_delta + ' BPM (' + cur.staffed.info.bpm + ' written)'], ['Velocity drift', '±' + staff.max_velocity_delta + ' per note'], ['Ornament chance', (staff.ornament_chance_bps / 100).toFixed(2) + '% per note (' + orn + ' this block)']]
    .map(([a, b]) => '<dt>' + a + '</dt><dd>' + esc(b) + '</dd>').join('');
  const s = DATA.species[st.s], spr = SPRITES[s.id], el = $('art');
  el.style.backgroundImage = 'url(data:image/png;base64,' + spr.png + ')'; el.style.backgroundSize = (spr.n * 56) + 'px 56px'; el.setAttribute('aria-label', s.name);
  roll(st.written ? cur.written.midi : cur.staffed.midi);
  $('ab').textContent = st.written ? 'Compare: drifted' : 'Compare: written';
  $('export').textContent = exportText();
  history.replaceState(null, '', query());
  buildSeries(); chart();
}
function exportText() {
  const c = st.cfg, lines = ['EvolutionConfig {', ...FIELDS.map(([k]) => '    ' + k + ': ' + c[k] + ','), '}'];
  if (experimental()) lines.push('// experiments (not in the contract): ' + [st.persist ? 'mutations persist until the next milestone' : '', st.grow ? 'complexity growth ' + st.grow : ''].filter(Boolean).join('; '));
  return lines.join('\\n');
}
function knobs() {
  $('knobs').innerHTML = FIELDS.map(([k, label, lo, hi, help]) => '<div class="knob"><label for="k-' + k + '">' + label + '</label><input type="number" id="n-' + k + '" min="' + lo + '" max="' + hi + '"><input type="range" id="k-' + k + '" min="' + lo + '" max="' + hi + '"><small>' + help + '</small></div>').join('');
  for (const [k, , lo, hi] of FIELDS) {
    const set = (v) => { st.cfg[k] = Math.max(lo, Math.min(hi, Math.round(+v) || 0)); if (k === 'first_milestone_age') st.age = Math.min(st.age, ageMax()); change(); };
    $('k-' + k).oninput = () => set($('k-' + k).value); $('n-' + k).onchange = () => set($('n-' + k).value);
  }
  $('presets').innerHTML = Object.keys(PRESETS).map((n) => '<button data-p="' + esc(n) + '">' + esc(n) + '</button>').join('');
  $('presets').querySelectorAll('button').forEach((b) => b.onclick = () => { st.cfg = { ...PRESETS[b.dataset.p] }; st.age = Math.min(st.age, ageMax()); change(); });
}
function knobsSync() {
  for (const [k] of FIELDS) { $('k-' + k).value = st.cfg[k]; if (document.activeElement !== $('n-' + k)) $('n-' + k).value = st.cfg[k]; }
  $('x-persist').checked = st.persist; $('x-grow').value = st.grow; if (document.activeElement !== $('x-grow-n')) $('x-grow-n').value = st.grow;
}

function notesOf(u8) {
  const notes = [], prog = {}; let tpq = (u8[12] << 8) | u8[13], end = 0, i = 14, ntr = (u8[10] << 8) | u8[11];
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
  return { notes, prog, tpq, end: Math.max(end, ...notes.map((n) => n[1])) };
}
let rollData = null;
function roll(midi) {
  rollData = notesOf(midi);
  const chans = [...new Set(rollData.notes.map((n) => n[3]))].sort((a, b) => a - b);
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + COLORS[ch % 6] + '"></i>' + (ROLE[ch] || 'ch' + (ch + 1)) + ' · ' + esc(DATA.names[rollData.prog[ch]] || '') + '</span>').join('') + '<span>brightness = velocity</span>';
  draw(-1);
}
function draw(play) {
  const c = $('roll'), x = c.getContext('2d'), W = c.width, H = c.height, d = rollData; x.clearRect(0, 0, W, H); if (!d || !d.notes.length) return;
  const lo = Math.min(...d.notes.map((n) => n[2])) - 2, hi = Math.max(...d.notes.map((n) => n[2])) + 2, ph = H - 12, sx = W / d.end, fg = getComputedStyle(document.body).color;
  for (const [a, b, p, ch, v] of d.notes) { x.globalAlpha = 0.25 + 0.75 * v / 127; x.fillStyle = COLORS[ch % 6]; x.fillRect(a * sx, 6 + (hi - p) / (hi - lo) * ph, Math.max(2, (b - a) * sx - 1), Math.max(3, ph / (hi - lo) - 1)); }
  x.globalAlpha = 1; if (play >= 0) { x.fillStyle = fg; x.fillRect((play % d.end) * sx, 0, 3, H); }
}
(function loop() { if (playing && synth && synth.tick2Time) draw(synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time); requestAnimationFrame(loop); })();

function start() {
  if (!cur) return;
  if (!synth) synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  synth.getAudioContext().resume(); synth.stopMIDI();
  BS.installSettings(synth, cur.settings);
  const m = (st.written ? cur.written : cur.staffed).midi;
  synth.loadMIDI(m.buffer.slice(m.byteOffset, m.byteOffset + m.length));
  synth.setLoop(1); synth.setLoopEnd(synth.getPlayStatus().maxTick); synth.playMIDI(); playing = true;
}
function stop() { if (synth) synth.stopMIDI(); playing = false; clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; draw(-1); }
function change() { show(); if (playing) start(); }
function toggleLapse() {
  if (lapse) { clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; return; }
  if (st.age >= ageMax()) st.age = 0;
  if (!playing) { show(); start(); }
  $('lapse').textContent = '■ Stop time-lapse';
  lapse = setInterval(() => { st.age = Math.min(ageMax(), st.age + Math.max(1, Math.round(st.age / 6))); change(); if (st.age >= ageMax()) toggleLapse(); }, 5000);
}

const step = (k, d) => { if (k === 'e') st.e = (st.e - 1 + d + N_ED) % N_ED + 1; if (k === 's') st.s = (st.s + d + 75) % 75; if (k === 'n') st.n = Math.max(1, st.n + d); change(); };
$('e-prev').onclick = () => step('e', -1); $('e-next').onclick = () => step('e', 1);
$('b-prev').onclick = () => step('s', -1); $('b-next').onclick = () => step('s', 1);
$('s-prev').onclick = () => step('n', -1); $('s-next').onclick = () => step('n', 1);
$('play').onclick = start; $('stop').onclick = stop; $('lapse').onclick = toggleLapse;
$('ab').onclick = () => { st.written = !st.written; change(); };
$('age').oninput = () => { st.age = toAge(+$('age').value); show(); }; $('age').onchange = () => { if (playing) start(); };
$('x-persist').onchange = () => { st.persist = $('x-persist').checked; change(); };
$('x-grow').oninput = () => { st.grow = +$('x-grow').value; change(); }; $('x-grow-n').onchange = () => { st.grow = Math.max(0, Math.min(8, +$('x-grow-n').value || 0)); change(); };
const copy = async (text, what) => { try { await navigator.clipboard.writeText(text); $('copied').textContent = 'Copied ' + what + '.'; } catch { $('copied').textContent = 'Clipboard unavailable: select the text above.'; } };
$('copy').onclick = () => copy(exportText(), 'the Cairo config'); $('link').onclick = () => copy(location.href, 'the link');
document.addEventListener('keydown', (ev) => {
  if (ev.target.tagName === 'INPUT' || ev.target.tagName === 'SELECT' || ev.metaKey || ev.ctrlKey) return;
  if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); }
  else if (ev.key === ',' || ev.key === '.') { st.age = Math.max(0, Math.min(ageMax(), st.age + (ev.key === '.' ? 1 : -1))); change(); }
});
knobs(); show();
</script></body></html>`;
writeFileSync(new URL('../public/onchain/drift-lab.html', import.meta.url), html);
console.log('drift-lab.html', html.length, 'bytes; edition settings match the contract (24/24)');

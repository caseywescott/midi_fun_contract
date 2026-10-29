// Build public/onchain/drift-lab.html: Casey Drift, the layered drift the composer plays
// (BeastPureComposer.compose_drift), on a Beast's Species Song or on a Monthly Track Edition track.
//   month (30 days)  2 in 3: songs re-pick their rhythm cells; editions get new melodies
//   week (7 days)    3 in 4: songs rotate which channels play; editions swap one part in or out and invert the accompaniment's chords
//   day              one knob: songs turn the key plan, swap episode directions or nudge the tempo;
//                    editions swap the A and B progressions or tunes, or nudge the tempo
// Each clock is seeded by the hash of its own first block (simulated here), and nothing accumulates.
// Songs: lab.js genesisMidi with drift2 (scripts/drift_parity.mjs); editions: editions_lite.js with
// drift2 (scripts/editions_drift_parity.mjs): both byte for byte the Cairo.
//   node onchain/drift-lab-demo.mjs <webaudio-tinysynth-4bf9829.min.js> <onchain-midi-player checkout>
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { beastName, poseidonHashMany } from '../src/index.js';
import { speciesRecords } from './editions_cairo.mjs';
import { spriteSheet } from './lab-sprites.mjs';
import { loadBank } from './tinychip/essentials.mjs';
import { beastSynthSettings, editionSynthSettings, serializeSettings, variantPrograms, SETTINGS_VARIANTS, YETI_VARIANTS } from './tinychip/synth_settings.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const [engineFile, omp] = process.argv.slice(2);
if (!engineFile || !omp) { console.error('usage: node onchain/drift-lab-demo.mjs <engine .min.js> <onchain-midi-player checkout>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const bundle = (await build({
  stdin: {
    contents: `import { engine } from './src/index.js'; import { createEngineV11 } from './src/engine_v11.js';
      import { genesisMidi, drift2, dayAnchor, epochAtBlock } from './src/lab.js';
      import * as ed from './src/editions_lite.js';
      import { installSettings } from ${JSON.stringify(omp + '/player/settings.js')};
      window.BS = { engine, v11: createEngineV11(engine), genesisMidi, drift2, dayAnchor, epochAtBlock, ed, installSettings };`,
    resolveDir: here + '..', loader: 'js',
  },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;

// the settings the composer serves: a Species Song's family (the Yeti's own), an edition's style
// presets (each checked against the contract's hashes)
const cairo = readFileSync(here + '../../../beasts/beast_contracts/src/synth_settings.cairo', 'utf8');
const CAIRO_HASHES = cairo.match(/EDITION_SERDE_HASHES: \[felt252; 24\] = \[([^\]]+)\]/)[1].split(',').map((s) => s.trim());
const EDITION = [];
for (let style = 0; style < 4; style++) for (let t = 0; t < 3; t++) {
  const s = editionSynthSettings(style, t, false);
  if ('0x' + poseidonHashMany(serializeSettings(s)).toString(16) !== CAIRO_HASHES[(style * 3 + t) * 2]) throw new Error('edition settings differ from the contract');
  EDITION[style * 3 + t] = s;
}
const SETTINGS = { family: SETTINGS_VARIANTS.filter((v) => !v.mega).map((v) => beastSynthSettings(undefined, variantPrograms(v))), yeti: beastSynthSettings(undefined, variantPrograms(YETI_VARIANTS[0])), edition: EDITION };
const bank = loadBank();
const NAMES = Object.fromEntries(bank.PRESETS.map((p, i) => [p.program ?? i, p.name]));
const SPECIES = speciesRecords().map((s) => ({ ...s, name: beastName({ id: s.id, prefix: 0, suffix: 0 }) }));
const SPRITES = Object.fromEntries(SPECIES.map((s) => { const { n, w, png } = spriteSheet(String(s.id)); return [s.id, { n, w, png }]; }));
const DATA = { species: SPECIES, types: ['Magic', 'Hunter', 'Brute'], names: NAMES, settings: SETTINGS };

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Drift Lab</title>
<link rel="icon" href="data:,">
<meta name="description" content="Casey Drift, the layered drift the Beast composer plays, on Species Songs and Monthly Track Edition tracks, day by day.">
<style>
:root{--bg:#f6f4ef;--fg:#1d1b18;--mut:#6b655c;--card:#fff;--line:#e2ddd3;--acc:#7a3cff;--ok:#1f9d55;--c1:#7a3cff;--c2:#e0742a;--c3:#1f9d8c;--c4:#c0392b}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--c1:#a77bff;--c2:#f08a48;--c3:#3cc8b4;--c4:#ff6b5e}}
:root[data-theme="dark"]{--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--c1:#a77bff;--c2:#f08a48;--c3:#3cc8b4;--c4:#ff6b5e}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1120px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 16px;max-width:820px}
.tabs{display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin-bottom:14px}.tabs button{padding:10px 12px;border-radius:12px;border:2px solid var(--line);background:var(--card);color:var(--fg);text-align:left;cursor:pointer;font:inherit}
.tabs button b{display:block;font-size:15px}.tabs button span{display:block;color:var(--mut);font-size:12.5px}.tabs button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 12%,var(--card))}
.grid{display:grid;grid-template-columns:minmax(0,1fr) 360px;gap:14px}@media(max-width:900px){.grid{grid-template-columns:minmax(0,1fr)}.tabs{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px;min-width:0}
.sec{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em;margin:0 0 10px;display:flex;justify-content:space-between;align-items:center;gap:8px}
.stepper{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;margin-bottom:10px}.stepper .mid{text-align:center;min-width:0}.lbl{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}
.stepper .val{font-weight:650;font-size:16px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.stepper .val small{font-weight:400;color:var(--mut);font-size:13px}
.stepper.off{display:none}
button,input{font:inherit}button{cursor:pointer}button.nav{width:42px;height:42px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:17px}
.ctl{display:flex;gap:10px;flex-wrap:wrap}.ctl button{flex:1;min-width:110px;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600}.ctl button.go{background:var(--fg);color:var(--bg)}
.badge{display:inline-block;border-radius:6px;padding:1px 8px;font-size:12px;font-weight:650;border:1px solid currentColor;text-transform:none;letter-spacing:0;color:var(--ok)}
.age{display:block;font-size:13px}.age input{width:100%;margin-top:6px;accent-color:var(--acc)}
#chart{width:100%;height:230px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card));cursor:crosshair;touch-action:none}
#roll{width:100%;height:170px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card))}
.legend{display:flex;flex-wrap:wrap;gap:4px 14px;margin-top:8px;font-size:12px;color:var(--mut)}.legend i{width:10px;height:10px;border-radius:3px;display:inline-block;margin-right:5px;vertical-align:-1px}
dl{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:4px 12px;margin:10px 0 0;font-size:13px}dt{color:var(--mut)}dd{margin:0;font-family:ui-monospace,monospace;font-size:12.5px;overflow-wrap:anywhere}
.note{font-size:12.5px;color:var(--mut);margin:8px 0 0}.how{font-size:13.5px;margin:0;padding-left:18px}.how li{margin:3px 0}.kbd{font:11px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 4px}
#art{width:56px;height:56px;border-radius:8px;background:#000;image-rendering:pixelated;background-repeat:no-repeat;flex:none}.head{display:flex;gap:12px;align-items:center;margin-bottom:10px}.head b{display:block}.head span{color:var(--mut);font-size:13px}
.mode{display:none}.mode.on{display:block}
a{color:var(--acc)}
</style></head><body><main>
<h1>Drift Lab</h1>
<p class="sub">Casey Drift is how a Beast's tracks change day by day. Each month may bring new rhythms, each week a new arrangement, and each day turns one knob. Every layer is seeded by the hash of its own first block, so nobody can hear a day before its block exists. Nothing accumulates: a day's version depends only on the track and that day. This page plays exactly what the composer contract's <code>compose_drift</code> returns.</p>
<div class="tabs" role="tablist">
<button id="t-song" role="tab"><b>Species Song</b><span>The species' Genesis Track, which every Beast of the species shares</span></button>
<button id="t-edition" role="tab"><b>Edition track</b><span>A track bought from edition 1 on: the edition's style engine</span></button>
</div>
<div class="grid"><div>
<div class="card">
<div class="head"><div id="art" role="img" aria-label=""></div><div><b id="title"></b><span id="subtitle"></span></div></div>
<div class="stepper"><button class="nav" id="b-prev" aria-label="Previous Beast">◀</button><div class="mid"><div class="lbl">Beast</div><div class="val" id="b-val"></div></div><button class="nav" id="b-next" aria-label="Next Beast">▶</button></div>
<div class="stepper" id="row-e"><button class="nav" id="e-prev" aria-label="Previous edition">▲</button><div class="mid"><div class="lbl">Edition</div><div class="val" id="e-val"></div></div><button class="nav" id="e-next" aria-label="Next edition">▼</button></div>
<div class="stepper" id="row-p"><button class="nav" id="p-prev" aria-label="Previous purchase">−</button><div class="mid"><div class="lbl">Purchase</div><div class="val" id="p-val"></div></div><button class="nav" id="p-next" aria-label="Next purchase">+</button></div>
<div class="ctl"><button class="go" id="play">▶ Play</button><button id="stop">■ Stop</button><button id="ab">Compare: written</button></div>
</div>
<div class="card"><div class="sec"><span>Timeline: one point a day</span><span class="badge">exactly compose_drift</span></div>
<canvas id="chart" width="1600" height="460" aria-label="Drift timeline"></canvas>
<div class="legend"><span><i style="background:var(--c1)"></i>a new month's rhythm</span><span><i style="background:var(--c2)"></i>tempo (BPM)</span><span><i style="background:var(--c3)"></i>notes changed from written</span><span>│ weeks, months · click to jump</span></div>
<label class="age" style="margin-top:12px">Day <b id="day-val"></b><input type="range" id="day" min="1" max="400" value="1" aria-label="Day"></label>
<div class="ctl" style="margin-top:10px"><button id="lapse">▶ Time-lapse</button></div>
<dl id="readout"></dl>
</div>
<div class="card"><canvas id="roll" width="1600" height="340" aria-label="Notes on this day"></canvas><div class="legend" id="legend"></div></div>
</div><div>
<div class="card mode" id="m-song"><div class="sec"><span>On a Species Song</span></div>
<ul class="how"><li><b>Month</b> (30 days): two months in three re-pick the rhythm cells.</li><li><b>Week</b>: three weeks in four rotate which channels play, keeping the count, the theme and the low voice.</li><li><b>Day</b>: turns one knob. The key plan turns the other way, the episode directions swap, or the tempo moves −4, −2, +2 or +4 BPM.</li></ul>
<p class="note">A Species Song's drift belongs to its species: all Beasts of a species hear the same day. A Beast's other tracks drift by its own special name.</p></div>
<div class="card mode" id="m-edition"><div class="sec"><span>On an edition track</span></div>
<ul class="how"><li><b>Month</b>: two months in three bring new melodies. Their rhythms and contour are drawn from the month's hash; the key, chords and tempo stay.</li><li><b>Week</b>: three weeks in four swap one part in or out (descant, bass, pad or percussion; one drops out when all four play) and put the accompaniment's chords in their first or second inversion.</li><li><b>Day</b>: turns one knob. The A and B progressions swap, the A and B tunes swap, or the tempo moves −4, −2, +2 or +4 BPM.</li></ul></div>
<div class="card"><div class="sec"><span>Share</span></div><div class="ctl"><button id="link">Copy link</button></div><p class="note" id="copied"></p>
<p class="note">The page assumes 43,200 blocks a day, as the lab does: a placeholder until the chain's block time is set. Block hashes are simulated. Keys: <span class="kbd">space</span> play/stop, <span class="kbd">,</span> <span class="kbd">.</span> day, <span class="kbd">1</span> <span class="kbd">2</span> track.</p></div>
</div></div>
<p class="note"><a href="../">All pages</a> · <a href="editions-onchain.html">Editions Onchain</a> · <a href="lab.html">Lab</a></p>
</main>
<script>${inline(tiny)}</script>
<script>${inline(bundle)}</script>
<script>
const DATA = ${JSON.stringify(DATA)};
const SPRITES = ${JSON.stringify(SPRITES)};
const $ = (id) => document.getElementById(id), E = BS.engine, V = BS.v11, ED = BS.ed, U64 = (1n << 64n) - 1n, DAYS = 400;
const st = { kind: 'song', s: 20, e: 1, n: 1, day: 1, written: false };
let synth = null, playing = false, lapse = 0, cur = null, series = null, seriesKey = '', seriesJob = 0;
const anchor = BS.dayAnchor();

(function readUrl() {
  const q = new URLSearchParams(location.search), num = (k, lo, hi, d) => (q.has(k) ? Math.max(lo, Math.min(hi, Math.round(+q.get(k)) || 0)) : d);
  if (q.get('track') === 'edition') st.kind = 'edition';
  st.s = num('b', 1, 75, st.s + 1) - 1; st.e = num('e', 1, 48, st.e); st.n = num('p', 1, 1e6, st.n); st.day = num('day', 1, DAYS, st.day);
})();
const query = () => '?' + new URLSearchParams({ track: st.kind, b: st.s + 1, e: st.e, p: st.n, day: st.day });

const sp = () => DATA.species[st.s];
function purchaseSeed(n) { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); }
// a track on a day: Species Songs drift by their (source) species; edition tracks by the Beast's
// species and special name (an unnamed Beast here)
function trackOn(day) {
  if (st.kind === 'song') return BS.genesisMidi(sp().id, false, E, V, day ? { epoch: day, driftMode: 'v2', blockHashes: true } : {});
  const d = day ? BS.drift2({ id: sp().id, prefix: 0, suffix: 0 }, day, anchor) : null;
  const o = ED.editionMidi(sp(), false, st.e, purchaseSeed(st.n), d);
  if (!d) return { ...o, drift: { label: 'as written' } };
  // the same layers as a song's, named for what they do to an edition track
  const w = Math.floor((day - 1) / 7) + 1, m = Math.floor((day - 1) / 30) + 1;
  const knob = d.dayKnob === 0 ? 'A and B progressions swap' : d.dayKnob === 1 ? 'A and B tunes swap' : 'tempo ' + (d.delta > 0 ? '+' : '') + d.delta + ' BPM';
  const label = ['month ' + m + (d.rhythm !== null ? ': new melodies' : ': melodies as written'),
    'week ' + w + (d.rotate !== null ? ': a part swaps, chords inverted' : ': parts and chords as written'), 'day: ' + knob].join(' \u00b7 ');
  return { ...o, drift: { ...d, label } };
}
let writtenKey = '', written = null;
function writtenTrack() { const k = [st.kind, st.s, st.e, st.n].join(); if (k !== writtenKey) { writtenKey = k; written = trackOn(0); } return written; }
function diff(o) {
  const key = (n) => n[0] + '|' + n[2] + '|' + n[3], w = notesOf(writtenTrack().midi), d = notesOf(o.midi);
  const ws = new Set(w.notes.map(key)), ds = new Set(d.notes.map(key));
  let changed = 0; for (const n of d.notes) if (!ws.has(key(n))) changed++;
  let gone = 0; for (const n of w.notes) if (!ds.has(key(n))) gone++;
  return { changed: Math.max(changed, gone), total: d.notes.length };
}
const tempoOf = (o) => (st.kind === 'song' ? (o.drift.delta || 0) : o.drift.dayKnob >= 2 ? o.drift.delta : 0);
const rhythmOf = (o) => (st.kind === 'song' ? o.drift.rhythm !== null && o.drift.rhythm !== undefined : !!(o.drift && o.drift.rhythm !== null && o.drift.rhythm !== undefined));

function buildSeries() {
  const key = [st.kind, st.s, st.e, st.n].join();
  if (key === seriesKey) return; seriesKey = key;
  const job = ++seriesJob, step = st.kind === 'song' ? 4 : 2, days = [];
  for (let d = 1; d <= DAYS; d += step) days.push(d);
  series = { pts: [], step };
  let i = 0;
  (function run() {
    if (job !== seriesJob) return;
    const t0 = performance.now();
    while (i < days.length && performance.now() - t0 < 30) { const o = trackOn(days[i]); series.pts.push({ day: days[i], tempo: tempoOf(o), rhythm: rhythmOf(o), chans: channelDiff(o).changed, ...diff(o) }); i++; }
    chart();
    if (i < days.length) setTimeout(run, 0);
  })();
}
function chart() {
  const cv = $('chart'), x = cv.getContext('2d'), W = cv.width, H = cv.height, css = getComputedStyle(document.body), col = (v) => css.getPropertyValue(v).trim(), fg = css.color;
  x.clearRect(0, 0, W, H);
  const rTop = 8, rH = 24, cTop = 38, cH = 24, tTop = 70, tH = 150, oTop = 240, oH = 200, X = (d) => 20 + (d - 1) / (DAYS - 1) * (W - 40);
  x.font = '22px system-ui'; x.fillStyle = fg; x.globalAlpha = 0.55; x.fillText('rhythm', 24, rTop + 20); x.fillText('channels', 24, cTop + 20); x.fillText('tempo', 24, tTop + 22); x.fillText('notes changed', 24, oTop + 22); x.globalAlpha = 1;
  for (let d = 1; d <= DAYS; d++) { if ((d - 1) % 30 === 0) { x.globalAlpha = 0.3; x.fillStyle = fg; x.fillRect(X(d), 0, 2, H); } else if ((d - 1) % 7 === 0) { x.globalAlpha = 0.08; x.fillStyle = fg; x.fillRect(X(d), 0, 1, H); } }
  x.globalAlpha = 0.25; x.fillRect(20, tTop + tH / 2, W - 40, 1); x.globalAlpha = 1;
  if (series) {
    const maxO = Math.max(10, ...series.pts.map((p) => p.changed)), w = Math.max(2, (W - 40) / DAYS * series.step - 1);
    for (const p of series.pts) {
      const x0 = X(p.day);
      if (p.rhythm) { x.fillStyle = col('--c1'); x.fillRect(x0, rTop, w, rH); }
      if (p.chans) { x.fillStyle = col('--c4'); x.fillRect(x0, cTop, w, cH); }
      x.fillStyle = col('--c2'); x.beginPath(); x.arc(x0, tTop + tH / 2 - p.tempo / 4 * (tH / 2 - 10), 4, 0, 7); x.fill();
      x.fillStyle = col('--c3'); const h = p.changed / maxO * (oH - 30); x.fillRect(x0, oTop + oH - h, w, h);
    }
  }
  x.fillStyle = fg; x.fillRect(X(st.day) - 1.5, 0, 3, H);
}
$('chart').addEventListener('pointerdown', (ev) => { const r = $('chart').getBoundingClientRect(), p = ((ev.clientX - r.left) / r.width * 1600 - 20) / 1560; st.day = Math.max(1, Math.min(DAYS, Math.round(1 + p * (DAYS - 1)))); change(); });

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const COLORS = ['#7a3cff', '#e0742a', '#1f9d8c', '#c0392b', '#7f8c8d', '#2a7ae0', '#b8860b', '#888'];
const EDITION_ROLES = { 0: 'lead', 1: 'descant', 2: 'accomp', 3: 'bass', 4: 'pad', 5: 'mega double' };
// a channel's name: drums, an edition part, or the song channel's preset
const chName = (ch, prog) => (ch === 9 ? 'drums' : st.kind === 'edition' ? EDITION_ROLES[ch] || 'ch' + (ch + 1) : DATA.names[prog] || 'ch' + (ch + 1));
const chansOf = (m) => { const d = notesOf(m); return [...new Set(d.notes.map((n) => n[3]))].sort((a, b) => a - b).map((ch) => [ch, d.prog[ch]]); };
/** Today's channels against the written track's: the set, and what joined or left. */
function channelDiff(o) {
  const w = chansOf(writtenTrack().midi), d = chansOf(o.midi), wk = new Set(w.map((c) => c[0])), dk = new Set(d.map((c) => c[0]));
  const added = d.filter((c) => !wk.has(c[0])), gone = w.filter((c) => !dk.has(c[0]));
  return { now: d, added, gone, changed: added.length + gone.length > 0 };
}
function show() {
  for (const k of ['song', 'edition']) { $('t-' + k).classList.toggle('on', st.kind === k); $('m-' + k).classList.toggle('on', st.kind === k); }
  $('row-e').classList.toggle('off', st.kind !== 'edition'); $('row-p').classList.toggle('off', st.kind !== 'edition');
  const s = sp();
  $('b-val').innerHTML = s.id + '. ' + esc(s.name) + ' <small>tier ' + s.tier + ' ' + DATA.types[s.type] + '</small>';
  const g = ED.editionGenome(st.e);
  $('e-val').innerHTML = st.e + ' · ' + esc(g.name) + ' <small>' + ED.ENGINES[g.engine].label + '</small>';
  $('p-val').innerHTML = '#' + st.n;
  const spr = SPRITES[s.id], el = $('art'); el.style.backgroundImage = 'url(data:image/png;base64,' + spr.png + ')'; el.style.backgroundSize = (spr.n * 56) + 'px 56px'; el.setAttribute('aria-label', s.name);
  const o = trackOn(st.day), dd = diff(o);
  cur = { o, settings: st.kind === 'edition' ? DATA.settings.edition[g.style * 3 + s.type] : s.id === 68 ? DATA.settings.yeti : DATA.settings.family[DATA.species[({ 39: 40, 40: 39 }[s.id] || s.id) - 1].type] };
  $('title').textContent = st.kind === 'song' ? s.name + "'s Species Song" : g.name;
  $('subtitle').textContent = st.kind === 'song' ? o.info.key + ' · ' + o.info.voices + ' voices' : o.info.key + ' · ' + o.info.meter + ' · ' + o.info.bpm + ' BPM written';
  $('day').value = st.day; $('day-val').textContent = st.day + ' (week ' + (Math.floor((st.day - 1) / 7) + 1) + ', month ' + (Math.floor((st.day - 1) / 30) + 1) + ')';
  const t = tempoOf(o), cd = channelDiff(o), nm = (cs) => cs.map(([ch, pr]) => chName(ch, pr)).join(', ');
  const chText = cd.now.length + ' playing' + (cd.changed ? ' (' + [cd.added.length ? '+ ' + nm(cd.added) : '', cd.gone.length ? '− ' + nm(cd.gone) : ''].filter(Boolean).join('; ') + ' vs written)' : ', as written') + ': ' + nm(cd.now);
  $('readout').innerHTML = [['Today', o.drift.label || ''], ['Channels', chText], ['Tempo', (t >= 0 ? '+' : '') + t + ' BPM'], ['From written', dd.changed + ' of ' + dd.total + ' notes changed']].map(([a, b]) => '<dt>' + a + '</dt><dd>' + esc(b) + '</dd>').join('');
  roll(st.written ? writtenTrack().midi : o.midi);
  $('ab').textContent = st.written ? 'Compare: drifted' : 'Compare: written';
  history.replaceState(null, '', query());
  buildSeries(); chart();
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
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + (ch === 9 ? 'var(--mut)' : COLORS[ch % 8]) + '"></i>' + (ch === 9 ? 'drums' : (st.kind === 'edition' ? EDITION_ROLES[ch] || 'ch' + (ch + 1) : 'ch' + (ch + 1)) + ' · ' + esc(DATA.names[rollData.prog[ch]] || '')) + '</span>').join('');
  draw(-1);
}
function draw(play) {
  const c = $('roll'), x = c.getContext('2d'), W = c.width, H = c.height, d = rollData; x.clearRect(0, 0, W, H); if (!d || !d.notes.length) return;
  const tones = d.notes.filter((n) => n[3] !== 9), lo = Math.min(...tones.map((n) => n[2])) - 2, hi = Math.max(...tones.map((n) => n[2])) + 2, ph = H - 40, sx = W / d.end, fg = getComputedStyle(document.body).color;
  for (const [a, b, p, ch, v] of d.notes) {
    x.globalAlpha = 0.3 + 0.7 * v / 127;
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
  const m = st.written ? writtenTrack().midi : cur.o.midi;
  synth.loadMIDI(m.buffer.slice(m.byteOffset, m.byteOffset + m.length));
  synth.setLoop(1); synth.setLoopEnd(synth.getPlayStatus().maxTick); synth.playMIDI(); playing = true;
}
function stop() { if (synth) synth.stopMIDI(); playing = false; clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; draw(-1); }
function change() { show(); if (playing) start(); }
function toggleLapse() {
  if (lapse) { clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; return; }
  if (st.day >= DAYS) st.day = 1;
  if (!playing) { show(); start(); }
  $('lapse').textContent = '■ Stop time-lapse';
  lapse = setInterval(() => { st.day = Math.min(DAYS, st.day + 1); change(); if (st.day >= DAYS) toggleLapse(); }, 4000);
}
const setKind = (k) => { st.kind = k; change(); };
$('t-song').onclick = () => setKind('song'); $('t-edition').onclick = () => setKind('edition');
const step = (k, d) => { if (k === 's') st.s = (st.s + d + 75) % 75; if (k === 'e') st.e = (st.e - 1 + d + 48) % 48 + 1; if (k === 'n') st.n = Math.max(1, st.n + d); change(); };
$('b-prev').onclick = () => step('s', -1); $('b-next').onclick = () => step('s', 1);
$('e-prev').onclick = () => step('e', -1); $('e-next').onclick = () => step('e', 1);
$('p-prev').onclick = () => step('n', -1); $('p-next').onclick = () => step('n', 1);
$('play').onclick = start; $('stop').onclick = stop; $('lapse').onclick = toggleLapse;
$('ab').onclick = () => { st.written = !st.written; change(); };
$('day').oninput = () => { st.day = +$('day').value; show(); }; $('day').onchange = () => { if (playing) start(); };
$('link').onclick = async () => { try { await navigator.clipboard.writeText(location.href); $('copied').textContent = 'Copied the link.'; } catch { $('copied').textContent = 'Clipboard unavailable: copy the address bar.'; } };
document.addEventListener('keydown', (ev) => {
  if (ev.target.tagName === 'INPUT' || ev.metaKey || ev.ctrlKey) return;
  if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); }
  else if (ev.key === ',' || ev.key === '.') { st.day = Math.max(1, Math.min(DAYS, st.day + (ev.key === '.' ? 1 : -1))); change(); }
  else if (ev.key === '1') setKind('song'); else if (ev.key === '2') setKind('edition');
});
show();
</script></body></html>`;
writeFileSync(new URL('../public/onchain/drift-lab.html', import.meta.url), html);
console.log('drift-lab.html', html.length, 'bytes');

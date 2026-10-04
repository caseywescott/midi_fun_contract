// Build public/onchain/compare.html: engine v1 against the v1.1 prototype (src/engine_v11.js), same
// Beast, same synth, A/B. Both scores play through TinySynth (Provable Games fork) with the onchain
// TinyChip orchestration and chip drums, and loop on the form's length like the onchain page.
//   node onchain/compare-demo.mjs        (after onchain/gallery.mjs)
import { readFileSync, writeFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { engine, decodeTokenId, beastName } from '../src/index.js';
import { createEngineV11 } from '../src/engine_v11.js';
import { loadBuiltModules } from './modules.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = here + '../public/onchain/';
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const minify = async (src) => (await build({ stdin: { contents: src, loader: 'js' }, minify: true, write: false, logLevel: 'error' })).outputFiles[0].text;

const tiny = await minify(await (await fetch('https://cdn.jsdelivr.net/gh/Provable-Games/webaudio-tinysynth@b70ba90d63c5ea657cb67ca98de90d7f778c29bd/webaudio-tinysynth.js')).text());
const TINY_NOTICE = '/*! webaudio-tinysynth (c) g200kg, Apache License 2.0; Provable Games fork b70ba90, https://github.com/Provable-Games/webaudio-tinysynth */';
const chipRuntime = readFileSync(here + 'pr3-tinychip/tinychip.min.js', 'utf8').trim();
const chipBank = readFileSync(here + 'pr3-tinychip/tinychip-bank.min.js', 'utf8').trim();
const midiModules = loadBuiltModules(['midi', 'smf']);
// the composer itself (engine v1 + the v1.1 prototype), so the history scrubber can re-render live
const composer = (await build({ stdin: { contents: "import { engine } from './src/index.js'; import { createEngineV11 } from './src/engine_v11.js'; window.BS11 = { engine, v11: createEngineV11(engine) };", resolveDir: here + '..', loader: 'js' }, bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error' })).outputFiles[0].text;
const V11M = { keys: 'mode', even: true, traj: true };
const bankCtx = {}; vm.runInNewContext(chipBank, bankCtx);
const PRESETS = bankCtx.TinyChipBank.PRESETS.map(({ program, name, category, inspired }) => ({ program, name, category, inspired }));

const v11 = createEngineV11(engine);
const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));
const cache = JSON.parse(readFileSync(here + '.gallery-cache.json', 'utf8'));
const gallery = JSON.parse(readFileSync(out + 'gallery.json', 'utf8'));
const b64 = (u8) => Buffer.from(u8).toString('base64');

const NOTE = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'];
const keys = (p, plan) => plan.map((k) => NOTE[((p.tonic_keynum + k.shift) % 12 + 12) % 12]).join(' → ');
function entry(name, beast, live, art) {
  const r1 = engine.render(beast, live), r2 = v11.render(beast, live), len = engine.formLength(r1.form);
  const r3 = v11.render(beast, live, V11M), r4 = v11.render(beast, live, { ...V11M, breath: true });
  const midiOf = (r) => b64(engine.eventsToMidi(r.form.events, r.params.tempo_us, engine.formLength(r.form)));
  const home = NOTE[((r1.params.tonic_keynum % 12) + 12) % 12];
  return {
    name, art, voices: r1.params.voice_count, sections: r1.params.section_count, tier: r1.params.tier,
    beast, live: { ...r1.live },
    keys: { v1: keys(r1.params, v11.v1KeyPlan(r1.params)), v11: keys(r2.params, r2.v11.keyPlan), v11m: 'all in ' + home + ', starting on degree ' + r3.v11.keyPlan.map((k) => ((k.degrees % 7) + 7) % 7 + 1).join(' → '), reach: v11.REACH[r1.params.tier] },
    v1: { midi: b64(engine.eventsToMidi(r1.form.events, r1.params.tempo_us, len)), m: v11.metrics(r1.form.events, r1.form) },
    v11: { midi: midiOf(r2), m: v11.metrics(r2.form.events, r2.form) },
    v11m: { midi: midiOf(r3), m: v11.metrics(r3.form.events, r3.form) },
    // breath only changes single-voice Beasts with a 3-bar theme: stored only for those
    ...(r4.v11.breathed ? { v11mb: { midi: midiOf(r4), m: v11.metrics(r4.form.events, r4.form) } } : {}),
    bars: { v1: r1.form.section_ticks / 1920, v11: r2.form.section_ticks / 1920, v11m: r3.form.section_ticks / 1920, v11mb: r4.form.section_ticks / 1920 },
  };
}
const warlockLive = { adventurers_killed: 412, scars: 7, summit_held_seconds: 0, rank: 3, species_count: 1243 };
const data = [
  entry(`${fx.name} (demo stats)`, decodeTokenId(BigInt(fx.token_id)), warlockLive, 'data:image/svg+xml;base64,' + fx.svg_b64),
  // gallery Beasts, most voices first so the counterpoint changes are easy to find
  ...gallery.map((g) => ({ g, ...cache[g.token] })).sort((a, b) => b.g.voices - a.g.voices || b.g.notes - a.g.notes)
    .map(({ g, beast, live }) => entry(`${g.name} #${g.token}`, beast, live, `beasts/${g.token}.svg`)),
];

// corpus summary over the 400 cached Beasts
function summary(pick) {
  const rows = Object.values(cache).map(({ beast, live }) => pick(beast, live)), multi = rows.filter((r) => r.voices > 1);
  const avg = (k, rs) => +(rs.reduce((a, r) => a + r[k], 0) / rs.length).toFixed(1);
  return { silent: avg('silentPct', rows), durations: avg('durations', rows), clash: avg('clashPct', multi), clashOnBeat: avg('clashOnBeatPct', multi), octave: avg('octavePct', multi), parallels: avg('parallels', multi), cadence: Math.round(100 * rows.filter((r) => r.cadence).length / rows.length) };
}
const fifthsApart = (a, b) => { const st = ((b - a) % 12 + 12) % 12, f = (st * 7) % 12; return Math.min(f, 12 - f); };
function keyStats(planOf) {
  let moves = 0, sum = 0, tritones = 0;
  for (const { beast, live } of Object.values(cache)) {
    const pl = planOf(beast, live); if (pl.length < 2) continue;
    for (let i = 0; i < pl.length; i++) { const d = fifthsApart(pl[i].shift, pl[(i + 1) % pl.length].shift); moves++; sum += d; if (d === 6) tritones++; }
  }
  return { avg: +(sum / moves).toFixed(1), tritones, moves };
}
const KEYS = { v1: keyStats((b, l) => v11.v1KeyPlan(engine.render(b, l).params)), v11: keyStats((b, l) => v11.render(b, l).v11.keyPlan) };
KEYS.v11m = { avg: '0 (one key)', tritones: 0, moves: KEYS.v11.moves };
const SUM = { v1: summary((b, l) => { const r = engine.render(b, l); return v11.metrics(r.form.events, r.form); }), v11: summary((b, l) => { const r = v11.render(b, l); return v11.metrics(r.form.events, r.form); }), v11m: summary((b, l) => { const r = v11.render(b, l, V11M); return v11.metrics(r.form.events, r.form); }), n: Object.keys(cache).length };

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beast Composer A/B</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=VT323&display=swap">
<style>
:root{--g:#4af626;--dim:rgba(74,246,38,.62);--line:rgba(74,246,38,.25);--bg:#000;--card:#070a07;--b:#ffb000;--c:#3fd0ff}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--g);font-family:"VT323",ui-monospace,monospace}
main{width:min(100% - 32px,1040px);margin:0 auto;padding:32px 0 48px}
h1{margin:0;font-weight:400;font-size:clamp(32px,6vw,52px);line-height:1;text-transform:uppercase;text-shadow:0 0 14px rgba(74,246,38,.5)}
h2{font-weight:400;font-size:24px;margin:28px 0 8px;text-transform:uppercase}
p{margin:10px 0 0;font-size:20px;color:var(--dim);max-width:76ch}
.layout{display:grid;grid-template-columns:minmax(0,240px) minmax(0,1fr);gap:24px;margin-top:20px;align-items:start}
.art{background:var(--card);border:1px solid var(--line);padding:8px}.art img{display:block;width:100%;height:auto}
.panel{display:grid;gap:16px;min-width:0}
fieldset{margin:0;min-width:0;border:1px solid var(--line);padding:12px 14px 14px;display:grid;gap:10px}
legend{padding:0 6px;font-size:18px;color:var(--dim);text-transform:uppercase}
select{font:inherit;font-size:20px;background:#000;color:var(--g);border:1px solid var(--line);padding:4px 8px;width:100%;min-width:0}
.choices{display:flex;flex-wrap:wrap;gap:8px}
button{font:inherit;font-size:20px;padding:6px 14px;background:transparent;color:var(--g);border:1px solid var(--line);cursor:pointer}
.choices button[aria-pressed="true"]{background:var(--g);color:#000}
.choices button[data-v="v11"][aria-pressed="true"]{background:var(--b);border-color:var(--b)}
.choices button[data-v="v11m"][aria-pressed="true"]{background:var(--c);border-color:var(--c);color:#000}
canvas.on.c{border-color:var(--c)}td.c{color:var(--c)}.cc{color:var(--c)}
#play{background:var(--g);color:#000;min-width:120px}
.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
label.check{display:flex;gap:8px;align-items:center;font-size:20px}
label.field{display:grid;gap:6px;font-size:18px;color:var(--dim)}
input[type=range]{width:100%;accent-color:var(--c)}
.roll{display:grid;gap:6px}.roll div{font-size:17px;color:var(--dim)}
canvas{width:100%;height:150px;background:var(--card);border:1px solid var(--line);display:block}
canvas{opacity:.55}canvas.on{border-color:var(--g);opacity:1}canvas.on.b{border-color:var(--b)}
table{border-collapse:collapse;width:100%;font-size:19px}
th,td{border:1px solid var(--line);padding:4px 8px;text-align:right}th:first-child,td:first-child{text-align:left}
th{color:var(--dim);font-weight:400}td.b{color:var(--b)}
.tablewrap{overflow-x:auto}
.note{font-size:18px;color:var(--dim)}
ul{margin:8px 0 0;padding-left:22px;font-size:19px;color:var(--dim)}li{margin:4px 0}b{color:var(--g);font-weight:400}.bb{color:var(--b)}
@media (max-width:760px){.layout{grid-template-columns:1fr}.art{max-width:240px}}
</style></head><body><main>
<h1>Beast composer: v1 vs v1.1</h1>
<p>The same Beast and the same synth, composed two ways. <b>v1</b> is the onchain composer today. <span class="bb">v1.1</span> is a prototype (JavaScript only for now) that keeps v1's themes, home keys and form and changes five things:</p>
<ul>
<li><b>Cadence:</b> the theme's last bar steps to the tonic and holds it, so each section and the loop end on purpose.</li>
<li><b>Rhythm:</b> the theme is built from 4-beat rhythm cells (long notes, dotted rhythms, short runs) picked by the Beast's motif seed, with a family per Beast type; the kill-driven ornament density decides how many passing notes appear.</li>
<li><b>No silent bars:</b> from the end of its theme until the next section, every voice plays an episode: the theme's opening bar in sequence (a step higher or lower each bar), then a half cadence onto the dominant of the next section's key. The last section leads back into the first, so the loop flows on.</li>
<li><b>Related keys:</b> sections move around the circle of fifths instead of v1's fixed shifts, which often jump a tritone. The Beast's tier sets how far they roam: tiers 4–5 stay within one fifth (I, V, IV), tier 3 two, tier 2 three, tier 1 four (a third relation such as C → E). Its type picks the sharp or flat side, and the last section comes back within a fifth of home, so the loop returns smoothly.</li>
<li><b>Same mode, even phrases (third button):</b> the same plan as diatonic transposition: every section stays in the home key and mode, and the theme starts on the planned scale degree (V = degree 5 of the home scale), so no new sharps or flats appear. Sections are an even number of bars by <em>shortening</em>: the episode is 1 or 2 bars, whichever makes the section even (4, 6 or 8 bars), so there is never more repetition than v1.1's other versions, and the theme and canon are untouched. The first bar of each pair is accented, and the drums mark the pairs and fill into each section. The checkbox lets a single-voice Beast's theme breathe instead (6 bars).</li>
<li><b>History (third version):</b> Beast data mapped to musical function by layer. Identity (species, name, type, tier) fixes the tune, mode, rhythm family and harmonic reach. Trajectory, with kills and defeats swapped after listening (the track came alive when defeats turned on the inversion, and that belongs to kills): kills bring the mirrored follower voice and the inverted, calmer development and make the bridges sink; defeats add sections, tighter stretto and faster motion, and more ornament; the second name prefix picks the ornament vocabulary (trills or passing notes). Current state: level and health set how widely the voices spread; rank sets how far the lead stands out, so a ranking shuffle changes prominence, never the tune. Try the history scrubber.</li>
<li><b>Voices:</b> every note is checked against every voice sounding with it. Thirds and sixths are preferred; clashes on the beat, unisons and parallel 5ths/8ves are avoided by moving a note a step or two.</li>
</ul>
<div class="layout">
  <div class="art"><img id="art" alt=""></div>
  <div class="panel">
    <fieldset><legend>Beast (${data.length})</legend><select id="beast" aria-label="Beast">${data.map((b, i) => `<option value="${i}">${esc(b.name)} · ${b.voices} voice${b.voices > 1 ? 's' : ''}, ${b.sections} section${b.sections > 1 ? 's' : ''}</option>`).join('')}</select></fieldset>
    <fieldset><legend>Composer</legend>
      <div class="choices" role="group" aria-label="Composer">
        <button type="button" data-v="v1" aria-pressed="true">v1 (onchain today)</button>
        <button type="button" data-v="v11" aria-pressed="false">v1.1: keys change</button>
        <button type="button" data-v="v11m" aria-pressed="false">v1.1: same mode, even phrases, history</button>
      </div>
      <div class="controls">
        <button type="button" id="play">▶ Play</button>
        <label class="check"><input type="checkbox" id="drums" checked> Drums</label>
        <span class="note" id="fillNote"></span>
        <label class="check"><input type="checkbox" id="keep" checked> Keep playing when switching</label>
      </div>
      <label class="check"><input type="checkbox" id="wholetone"> Third version in a whole-tone scale (a test for the new Beasts: six equal steps, no fifths)</label>
      <label class="check"><input type="checkbox" id="breath"> Same mode, single-voice Beasts: let the theme breathe (hold its last note a bar: 6 bars instead of 4)</label>
      <label class="field">Instrument, the same for every version
        <select id="preset"><option value="auto">Auto: the onchain orchestration (worked out from v1's score, used for every version)</option>${[...new Set(PRESETS.map((x) => x.category))].map((c) => `<optgroup label="${esc(c)}">${PRESETS.filter((x) => x.category === c).map((x) => `<option value="${x.program}"${x.program === 0 ? ' selected' : ''}>All voices: ${x.program}: ${esc(x.name)}</option>`).join('')}</optgroup>`).join('')}</select></label>
      <div class="controls">
        <button type="button" id="prev">◀ Prev</button><button type="button" id="next">Next ▶</button>
        <span class="note" id="presetNote"></span>
      </div>
      <span class="note">Switch while it plays to hear the difference: the new version starts from the top.</span>
    </fieldset>
    <fieldset><legend>History scrubber (third version)</legend>
      <span class="note">Change this Beast's history and hear the same tune take a different path. Identity (tune, mode, rhythm family, tier) never changes.</span>
      <label class="field">Kills: <b id="killsV"></b><input type="range" id="kills" min="0" max="11" step="1"></label>
      <label class="field">Defeats: <b id="scarsV"></b><input type="range" id="scars" min="0" max="10" step="1"></label>
      <label class="field">Rank <select id="rank"><option value="crown">Crown (rank 1)</option><option value="1">Top 1%</option><option value="5">Top 5%</option><option value="20">Top 20%</option><option value="rest">The rest</option></select></label>
      <div class="controls"><button type="button" id="real">Real stats</button></div>
      <span class="note" id="trajNote"></span>
    </fieldset>
    <div class="roll">
      <div>v1</div><canvas id="rollA" width="1600" height="300" class="on"></canvas>
      <div>v1.1: keys change</div><canvas id="rollB" width="1600" height="300" class="b"></canvas>
      <div>v1.1: same mode, even phrases, history <span id="custom" class="cc"></span></div><canvas id="rollC" width="1600" height="300" class="c"></canvas>
    </div>
    <div class="tablewrap"><table id="mt"></table></div>
  </div>
</div>
<h2>Across ${SUM.n} Beasts</h2>
<div class="tablewrap"><table>
<tr><th></th><th>Key moves: avg distance in 5ths</th><th>Tritone key moves</th><th>Silent time</th><th>Note lengths per score</th><th>Clashes between voices</th><th>Clashes on the beat</th><th>Unisons / octaves</th><th>Parallel 5ths/8ves per score</th><th>Ends on the tonic</th></tr>
<tr><td>v1</td><td>${KEYS.v1.avg}</td><td>${KEYS.v1.tritones} of ${KEYS.v1.moves}</td><td>${SUM.v1.silent}%</td><td>${SUM.v1.durations}</td><td>${SUM.v1.clash}%</td><td>${SUM.v1.clashOnBeat}%</td><td>${SUM.v1.octave}%</td><td>${SUM.v1.parallels}</td><td>${SUM.v1.cadence}%</td></tr>
<tr><td class="b">v1.1: keys change</td><td class="b">${KEYS.v11.avg}</td><td class="b">${KEYS.v11.tritones} of ${KEYS.v11.moves}</td><td class="b">${SUM.v11.silent}%</td><td class="b">${SUM.v11.durations}</td><td class="b">${SUM.v11.clash}%</td><td class="b">${SUM.v11.clashOnBeat}%</td><td class="b">${SUM.v11.octave}%</td><td class="b">${SUM.v11.parallels}</td><td class="b">${SUM.v11.cadence}%</td></tr>
<tr><td class="c">v1.1: same mode, even phrases, history</td><td class="c">${KEYS.v11m.avg}</td><td class="c">${KEYS.v11m.tritones} of ${KEYS.v11m.moves}</td><td class="c">${SUM.v11m.silent}%</td><td class="c">${SUM.v11m.durations}</td><td class="c">${SUM.v11m.clash}%</td><td class="c">${SUM.v11m.clashOnBeat}%</td><td class="c">${SUM.v11m.octave}%</td><td class="c">${SUM.v11m.parallels}</td><td class="c">${SUM.v11m.cadence}%</td></tr>
</table></div>
<p class="note">Drums: kick, snare backbeat and eighth-note hi-hats, phrased in bar pairs (firmer first bar, a pickup kick and an open hat closing each pair); the tier's fill replaces the snare at the end of each section while the kick and hats keep going. This page uses a fuller kick (deep pitch drop plus a click) and crisper hats than the stock chip kit.</p>
<p class="note">Clashes: seconds, sevenths and tritones between voices sounding together, as a share of all voice pairs (multi-voice Beasts). Silent time: share of the form in rests of a beat or more with no note sounding (shorter gaps are articulation). Both versions loop on the same form length; v1 rests for the closing bars, v1.1 fills them. Instruments: one TinyChip preset for every voice (pick any of the 100), or Auto, the onchain orchestration worked out from v1's score and applied to every version; chip drums.</p>
</main>
<script>${inline(midiModules.map((m) => m.js).join('\n'))}</script>
<script>${TINY_NOTICE}\n${inline(tiny)}</script>
<script>${inline(chipBank)}</script>
<script>${inline(chipRuntime)}</script>
<script>${inline(composer)}</script>
<script>
const BEASTS = ${JSON.stringify(data)};
// the data key for a version: the third button plays the breath variant when it is ticked and exists
const key = (v) => (v === 'v11m' && $('breath') && $('breath').checked && BEASTS[current].v11mb ? 'v11mb' : v);
const NAMES = ${JSON.stringify(Object.fromEntries(PRESETS.map((x) => [x.program, x.name])))};
const INSPIRED = ${JSON.stringify(Object.fromEntries(PRESETS.filter((x) => x.inspired).map((x) => [x.program, x.inspired])))};
const v1lib = BeastSound.v1, $ = (id) => document.getElementById(id);
let current = 0, version = 'v1', synth = null, playing = false;
const bytesOf = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const COLORS = ['#4af626', '#ffb000', '#3fd0ff', '#ff5ea8', '#c9a0ff', '#ffffff'];

// the drum pattern, phrased by the section: a firmer kick on the first bar of each pair, a lighter
// one on the second, and a fill into every section that grows with the Beast's tier
const FILLS = {
  A: { name: 'two snares', beats: 1, tiers: '5' },
  B: { name: 'sixteenth-note snare run', beats: 1, tiers: '4' },
  C: { name: 'two-beat snare build', beats: 2, tiers: '3' },
  D: { name: 'tom roll into a crash', beats: 2, tiers: '1-2' },
};
const fillFor = (tier) => (tier >= 5 ? 'A' : tier === 4 ? 'B' : tier === 3 ? 'C' : 'D');
// notes for one fill, relative to the start of its region (1 or 2 beats before the section end)
function fillNotes(f) {
  if (f === 'A') return [[0, 120, 38, 88], [240, 120, 38, 106]];
  if (f === 'B') return [0, 1, 2, 3].map((k) => [k * 120, 90, 38, 72 + k * 12]);
  if (f === 'C') return [[0, 120, 36, 100], [0, 120, 38, 80], [240, 120, 38, 88], ...[0, 1, 2, 3].map((k) => [480 + k * 120, 90, 38, 92 + k * 8])];
  return [50, 50, 48, 48, 47, 45, 43, 41].map((key, k) => [k * 120, 110, key, 84 + k * 4]).concat([[840, 120, 36, 110]]); // toms high to low, a kick on the last sixteenth
}
// the groove keeps going through the fills: kick and hi-hats play on, the fill takes the snare's place
function withDrums(song, sectionBars, tier) {
  const end = Math.max(song.length_ticks || 0, ...song.notes.map((n) => n[0] + n[1]));
  const bars = Math.ceil(end / 1920) * 1920, sec = (sectionBars || 4) * 1920, drums = [];
  const f = fillFor(tier), region = FILLS[f].beats * 480, fill = fillNotes(f);
  const fillKickAt = new Set(fill.filter((n) => n[2] === 36).map((n) => n[0]));
  for (let t = 0; t < bars; t += 240) {
    const rel = t % sec, bar = Math.floor(rel / 1920), second = bar % 2 === 1, b = (rel % 1920) / 480, onBeat = t % 480 === 0;
    const inFill = rel >= sec - region;
    if (rel === sec - region) for (const [st, d, key, v] of fill) drums.push([t + st, d, key, v, 9]);
    if (f === 'D' && rel === 0) drums.push([t, 960, 49, 76, 9]);                       // a soft cymbal on each section's downbeat (fill D)
    // kick: beat 1 (firmer on the first bar of a pair), a pickup on the and of 3 in the second bar,
    // and beat 3 under the fill unless the fill brings its own kick there
    if (b === 0) drums.push([t, 120, 36, second ? 104 : 122, 9]);
    if (!inFill && second && b === 2.5) drums.push([t, 120, 36, 86, 9]);
    if (inFill && b === 2 && !fillKickAt.has(rel - (sec - region))) drums.push([t, 120, 36, 100, 9]);
    // snare backbeat on 3, except where the fill plays
    if (!inFill && b === 2) drums.push([t, 120, 38, second ? 88 : 94, 9]);
    // hi-hats: eighths, accented on the beat, an open hat closing each bar pair; a touch softer under a fill
    const open = !inFill && second && b === 3.5;
    let hv = b === 0 ? 80 : onBeat ? 70 : 52;
    if (inFill) hv -= 12;
    drums.push(open ? [t, 240, 46, 64, 9] : [t, 60, 42, hv, 9]);
  }
  return { notes: song.notes.concat(drums), tempo_us: song.tempo_us, length_ticks: bars };
}
// a fuller kick and crisper hats than the stock chip kit (this page only; applied after TinyChip installs its kit)
function betterKit(s) {
  const kick = [
    { w: 'sine', t: 0, f: 150, v: 0.5, a: 0.001, h: 0.008, d: 0.12, s: 0, r: 0.06, p: 0.3, q: 0.022 },   // body: a deep pitch drop
    { w: 'nTRI', t: 0, f: 150, v: 0.12, a: 0.001, h: 0.004, d: 0.05, s: 0, r: 0.03, p: 0.4, q: 0.02 },    // a little chip grit
    { w: 'n0', t: 0, f: 3200, v: 0.16, a: 0, h: 0, d: 0.004, s: 0, r: 0.004 },                             // the click
  ];
  const hat = (d, v) => [
    { w: 'nMET', t: 0, f: 440 * 19, v, a: 0.0005, h: 0, d, s: 0, r: d / 2 },                               // metallic
    { w: 'n0', t: 0, f: 440 * 3, v: v * 0.7, a: 0.0005, h: 0, d: d * 0.7, s: 0, r: d / 3 },               // air
  ];
  s.setTimbre(1, 35, kick.map((o) => ({ ...o, f: o.w === 'n0' ? o.f : 130 })));
  s.setTimbre(1, 36, kick);
  s.setTimbre(1, 42, hat(0.014, 0.17));
  s.setTimbre(1, 44, hat(0.02, 0.13));
  s.setTimbre(1, 46, hat(0.085, 0.15));
  // a cymbal, not a noise burst: bright metallic shimmer with a long soft tail (the stock chip crash
  // is plain noise and reads as a snare on the downbeat)
  const cymbal = [
    { w: 'nMET', t: 0, f: 440 * 23, v: 0.08, a: 0.002, h: 0, d: 0.3, s: 0, r: 0.25 },
    { w: 'nMET', t: 0, f: 440 * 31, v: 0.05, a: 0.002, h: 0, d: 0.22, s: 0, r: 0.2 },
    { w: 'n0', t: 0, f: 440 * 7, v: 0.03, a: 0.003, h: 0, d: 0.12, s: 0, r: 0.1 },
  ];
  s.setTimbre(1, 49, cymbal);
  s.setTimbre(1, 57, cymbal);
}
function drawRoll(canvas, midi, tick) {
  const s = v1lib.smf.parse(midi), ctx = canvas.getContext('2d'), W = canvas.width, H = canvas.height;
  const len = Math.max(s.length_ticks || 0, ...s.notes.map((n) => n[0] + n[1]));
  const lo = Math.min(...s.notes.map((n) => n[2])) - 2, hi = Math.max(...s.notes.map((n) => n[2])) + 2;
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = 'rgba(74,246,38,.08)';
  for (let b = 0; b < len; b += 1920) ctx.fillRect(b / len * W, 0, 1, H);
  for (const [t, d, p, v, ch] of s.notes) {
    ctx.fillStyle = COLORS[ch % COLORS.length]; ctx.globalAlpha = 0.35 + 0.65 * (v / 127);
    ctx.fillRect(t / len * W, H - (p - lo + 1) / (hi - lo) * H, Math.max(2, d / len * W - 1), Math.max(3, H / (hi - lo) - 1));
  }
  ctx.globalAlpha = 1;
  if (tick != null) { ctx.fillStyle = '#fff'; ctx.fillRect(tick / len * W, 0, 3, H); }
}
function metricsTable() {
  const a = BEASTS[current].v1.m, b = BEASTS[current].v11.m, c = BEASTS[current][key('v11m')].m, bars = BEASTS[current].bars;
  const row = (label, k, f = (x) => x) => '<tr><td>' + label + '</td><td>' + f(a[k]) + '</td><td class="b">' + f(b[k]) + '</td><td class="c">' + f(c[k]) + '</td></tr>';
  $('mt').innerHTML = '<tr><th>This Beast</th><th>v1</th><th>v1.1: keys change</th><th>v1.1: same mode, even phrases, history</th></tr>' + '<tr><td>Keys by section (tier ' + BEASTS[current].tier + ': up to ' + BEASTS[current].keys.reach + ' fifth' + (BEASTS[current].keys.reach > 1 ? 's' : '') + ' away)</td><td>' + BEASTS[current].keys.v1 + '</td><td class="b">' + BEASTS[current].keys.v11 + '</td><td class="c">' + BEASTS[current].keys.v11m + '</td></tr>'
    + '<tr><td>Bars per section</td><td>' + bars.v1 + '</td><td class="b">' + bars.v11 + '</td><td class="c">' + bars[key('v11m')] + '</td></tr>'
    + row('Notes', 'notes') + row('Silent time', 'silentPct', (x) => x + '%') + row('Note lengths', 'durations')
    + (a.voices > 1 ? row('Clashes between voices', 'clashPct', (x) => x + '%') + row('Clashes on the beat', 'clashOnBeatPct', (x) => x + '%') + row('Unisons / octaves', 'octavePct', (x) => x + '%') + row('Parallel 5ths/8ves', 'parallels') : '')
    + row('Ends on the tonic', 'cadence', (x) => (x ? 'yes' : 'no'));
}
function show() {
  const b = BEASTS[current];
  $('art').src = b.art;
  drawRoll($('rollA'), b.v1.midi); drawRoll($('rollB'), b.v11.midi); drawRoll($('rollC'), b[key('v11m')].midi);
  metricsTable();
  const f = fillFor(b.tier);
  $('fillNote').textContent = 'Fill ' + f + ' (tier ' + FILLS[f].tiers + '): ' + FILLS[f].name;
  setInstrument();
}
function stop() { if (synth) synth.stopMIDI(); playing = false; $('play').textContent = '▶ Play'; }
function play() {
  // the full bank at programs 0-99 (and the chip kit); the onchain runtime adds its 20 at 129+
  if (!synth) synth = TinyChipBank.install(new WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 64 }));
  synth.getAudioContext().resume();
  const k = key(version), midi = BEASTS[current][k].midi, song = v1lib.smf.parse(midi);
  const file = $('drums').checked ? v1lib.midi.write(withDrums(song, BEASTS[current].bars[k], BEASTS[current].tier)) : bytesOf(midi);
  synth.loadMIDI(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength));
  synth.loopEnd = Math.ceil(synth.maxTick / synth.song.timebase) * synth.song.timebase;
  synth.setLoop(1);
  // the onchain orchestration, from the score without the drum track
  const channels = [...new Set(song.notes.map((n) => n[4]))].sort((a, b) => a - b);
  synth.playMIDI();
  playing = true; $('play').textContent = '■ Stop';
  setInstrument();
  betterKit(synth);
}
// One instrument choice for both versions. Auto orchestrates v1's score and gives v1.1 the same
// preset per voice, so a switch changes the notes, never the sound.
function v1Events() {
  const s = v1lib.smf.parse(BEASTS[current].v1.midi), ev = [{ t: 0, m: [0xff51, 60e6 / s.tempo_us] }];
  for (const [t, d, p, v, ch] of s.notes) ev.push({ t, m: [0x90 | ch, p, v] });
  return { ev: ev.sort((a, b) => a.t - b.t), channels: [...new Set(s.notes.map((n) => n[4]))].sort((a, b) => a - b) };
}
function setInstrument() {
  const val = $('preset').value;
  if (val === 'auto') {
    const { ev, channels } = v1Events();
    const roles = TinyChip.orchestrate(ev, channels, 1920);
    $('presetNote').textContent = channels.map((ch) => 'voice ' + (ch + 1) + ': ' + NAMES[roles[ch]]).join(' · ');
    if (!playing) return;
    TinyChip.attach(synth, { bare: true, channels: [], events: [] }); // installs the onchain runtime's presets at 129+
    betterKit(synth);                                                   // (attach reinstalls the chip kit)
    for (const ch of channels) synth.send([0xc0 | ch, 129 + roles[ch]]);
    // a voice v1.1 has that v1 lacks (none today) keeps the lead's preset
    for (let ch = 0; ch < 16; ch++) if (ch !== 9 && !(ch in roles)) synth.send([0xc0 | ch, 129 + roles[channels[channels.length - 1]]]);
    return;
  }
  const v = INSPIRED[val];
  $('presetNote').textContent = NAMES[val] + (v ? ' · inspired by ' + v : '');
  if (playing) for (let ch = 0; ch < 16; ch++) if (ch !== 9) synth.send([0xc0 | ch, +val]);
}
function stepPreset(d) { const sel = $('preset'), n = sel.options.length; sel.selectedIndex = (sel.selectedIndex + d + n) % n; setInstrument(); }
// ── history scrubber: re-render the third version with a changed history ──
const KILL_STEPS = [0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024], SCAR_STEPS = [0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512];
const nearest = (steps, x) => steps.reduce((bi, v, i) => (Math.abs(v - x) < Math.abs(steps[bi] - x) ? i : bi), 0);
const rankOf = (l) => (l.rank === 1 ? 'crown' : !l.rank || !l.species_count ? 'rest' : (l.rank * 100 / l.species_count) <= 1 ? '1' : (l.rank * 100 / l.species_count) <= 5 ? '5' : (l.rank * 100 / l.species_count) <= 20 ? '20' : 'rest');
const ORIGINAL = {};
// sliders still where the Beast's real stats put them (they snap to doublings, e.g. 412 kills shows as 512)
const atReal = () => { const B = BEASTS[current]; return +$('kills').value === nearest(KILL_STEPS, B.live.adventurers_killed) && +$('scars').value === nearest(SCAR_STEPS, B.live.scars) && $('rank').value === rankOf(B.live); };
function scrubbedLive() {
  const B = BEASTS[current], l = { ...B.live }, count = l.species_count || 1000;
  if (atReal()) return l;                                   // untouched: the exact real stats
  l.adventurers_killed = KILL_STEPS[+$('kills').value]; l.scars = SCAR_STEPS[+$('scars').value];
  const r = $('rank').value;
  l.rank = r === 'crown' ? 1 : r === 'rest' ? Math.max(2, Math.ceil(count * 0.5)) : Math.max(2, Math.floor(count * (+r) / 100));
  if (!l.species_count) l.species_count = count;
  return l;
}
function describe(t, r) {
  return r.form.sections.length + ' section' + (r.form.sections.length > 1 ? 's' : '') + ' · bridges ' + (t.direction > 0 ? 'climb' : t.direction < 0 ? 'sink' : 'alternate')
    + ' · development: ' + (r.form.sections.length < 2 ? 'none (one section)' : t.development === 'stretto' ? 'tighter stretto, faster' : t.development === 'inversion' ? 'inversion, calmer' : 'sequence')
    + ' · ornaments: ' + (t.trill ? 'trills' : 'passing notes') + ', density ' + t.ornamentDensity + ' · spacing ' + t.spacing + ' · prominence ' + t.prominence + '/3';
}
function rescore() {
  const B = BEASTS[current], live = scrubbedLive();
  if (!ORIGINAL[current]) ORIGINAL[current] = { v11m: B.v11m, v11mb: B.v11mb, bars: { ...B.bars } };
  const enc = (r) => { const u8 = BS11.engine.eventsToMidi(r.form.events, r.params.tempo_us, BS11.engine.formLength(r.form)); let s = ''; for (const x of u8) s += String.fromCharCode(x); return { midi: btoa(s), m: BS11.v11.metrics(r.form.events, r.form) }; };
  const scale = $('wholetone').checked ? 'wholetone' : 'mode';
  const r = BS11.v11.render(B.beast, live, { keys: 'mode', even: true, traj: true, scale }), rb = BS11.v11.render(B.beast, live, { keys: 'mode', even: true, traj: true, breath: true, scale });
  B.v11m = enc(r); B.bars.v11m = r.form.section_ticks / 1920;
  if (rb.v11.breathed) { B.v11mb = enc(rb); B.bars.v11mb = rb.form.section_ticks / 1920; }
  const real = live.adventurers_killed === B.live.adventurers_killed && live.scars === B.live.scars && rankOf(live) === rankOf(B.live);
  $('custom').textContent = [real ? '' : 'scrubbed history', scale === 'wholetone' ? 'whole tone' : ''].filter(Boolean).map((x) => '(' + x + ')').join(' ');
  $('trajNote').textContent = describe(r.v11.trajectory, r);
  $('killsV').textContent = live.adventurers_killed; $('scarsV').textContent = live.scars;
  show();
  if (playing && version === 'v11m') { stop(); play(); }
}
function loadHistory() {
  const l = BEASTS[current].live;
  $('kills').value = nearest(KILL_STEPS, l.adventurers_killed); $('scars').value = nearest(SCAR_STEPS, l.scars); $('rank').value = rankOf(l);
  $('killsV').textContent = l.adventurers_killed; $('scarsV').textContent = l.scars;
  const o = ORIGINAL[current]; if (o) { Object.assign(BEASTS[current], { v11m: o.v11m, v11mb: o.v11mb, bars: o.bars }); delete ORIGINAL[current]; }
  $('custom').textContent = '';
  const r = BS11.v11.render(BEASTS[current].beast, l, { keys: 'mode', even: true, traj: true });
  $('trajNote').textContent = describe(r.v11.trajectory, r);
}
function setVersion(v) {
  const was = playing && $('keep').checked; stop(); version = v;
  document.querySelectorAll('[data-v]').forEach((x) => x.setAttribute('aria-pressed', x.dataset.v === v));
  $('rollA').classList.toggle('on', v === 'v1'); $('rollB').classList.toggle('on', v === 'v11'); $('rollC').classList.toggle('on', v === 'v11m');
  if (was) play();
}
(function tickLoop() {
  if (playing && synth) {
    const t = synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time, loop = synth.loopEnd || synth.maxTick;
    const tick = t < 0 ? 0 : t % loop, b = BEASTS[current];
    drawRoll({ v1: $('rollA'), v11: $('rollB'), v11m: $('rollC') }[version], b[key(version)].midi, tick);
  }
  requestAnimationFrame(tickLoop);
})();
$('play').addEventListener('click', () => (playing ? stop() : play()));
$('beast').addEventListener('change', (e) => { const was = playing; stop(); const prev = current; current = +e.target.value; if (ORIGINAL[prev]) { const o = ORIGINAL[prev]; Object.assign(BEASTS[prev], { v11m: o.v11m, v11mb: o.v11mb, bars: o.bars }); delete ORIGINAL[prev]; } loadHistory(); if ($('wholetone').checked) rescore(); show(); if (was) play(); });
$('drums').addEventListener('change', () => { if (playing) { stop(); play(); } });
['kills', 'scars'].forEach((id) => $(id).addEventListener('input', () => { $(id + 'V').textContent = (id === 'kills' ? KILL_STEPS : SCAR_STEPS)[+$(id).value]; }));
['kills', 'scars', 'rank'].forEach((id) => $(id).addEventListener('change', rescore));
$('real').addEventListener('click', () => { const was = playing && version === 'v11m'; loadHistory(); if ($('wholetone').checked) return rescore(); show(); if (was) { stop(); play(); } });
// whole tone: re-render the third version (with the scrubber's current history); off restores it
$('wholetone').addEventListener('change', () => {
  if ($('wholetone').checked) return rescore();
  if (atReal()) { const was = playing && version === 'v11m'; loadHistory(); show(); if (was) { stop(); play(); } } else rescore();
});
$('breath').addEventListener('change', () => { show(); if (playing && version === 'v11m') { stop(); play(); } });
$('preset').addEventListener('change', setInstrument);
$('prev').addEventListener('click', () => stepPreset(-1));
$('next').addEventListener('click', () => stepPreset(1));
document.querySelectorAll('[data-v]').forEach((btn) => btn.addEventListener('click', () => setVersion(btn.dataset.v)));
loadHistory();
show();
setInstrument();
</script></body></html>`;
writeFileSync(out + 'compare.html', html);
console.log(`compare.html: ${(html.length / 1000).toFixed(0)} KB · ${data.length} Beasts`);
console.log('v1  ', JSON.stringify(SUM.v1));
console.log('v1.1', JSON.stringify(SUM.v11));

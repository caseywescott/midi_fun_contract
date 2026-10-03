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
const bankCtx = {}; vm.runInNewContext(chipBank, bankCtx);
const PRESETS = bankCtx.TinyChipBank.PRESETS.map(({ program, name, category, inspired }) => ({ program, name, category, inspired }));

const v11 = createEngineV11(engine);
const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));
const cache = JSON.parse(readFileSync(here + '.gallery-cache.json', 'utf8'));
const gallery = JSON.parse(readFileSync(out + 'gallery.json', 'utf8'));
const b64 = (u8) => Buffer.from(u8).toString('base64');

function entry(name, beast, live, art) {
  const r1 = engine.render(beast, live), r2 = v11.render(beast, live), len = engine.formLength(r1.form);
  return {
    name, art, voices: r1.params.voice_count, sections: r1.params.section_count,
    v1: { midi: b64(engine.eventsToMidi(r1.form.events, r1.params.tempo_us, len)), m: v11.metrics(r1.form.events) },
    v11: { midi: b64(engine.eventsToMidi(r2.form.events, r2.params.tempo_us, len)), m: v11.metrics(r2.form.events) },
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
  return { durations: avg('durations', rows), clash: avg('clashPct', multi), clashOnBeat: avg('clashOnBeatPct', multi), octave: avg('octavePct', multi), parallels: avg('parallels', multi), cadence: Math.round(100 * rows.filter((r) => r.cadence).length / rows.length) };
}
const SUM = { v1: summary((b, l) => v11.metrics(engine.render(b, l).form.events)), v11: summary((b, l) => v11.metrics(v11.render(b, l).form.events)), n: Object.keys(cache).length };

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beast Composer A/B</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=VT323&display=swap">
<style>
:root{--g:#4af626;--dim:rgba(74,246,38,.62);--line:rgba(74,246,38,.25);--bg:#000;--card:#070a07;--b:#ffb000}
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
#play{background:var(--g);color:#000;min-width:120px}
.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
label.check{display:flex;gap:8px;align-items:center;font-size:20px}
label.field{display:grid;gap:6px;font-size:18px;color:var(--dim)}
.roll{display:grid;gap:6px}.roll div{font-size:17px;color:var(--dim)}
canvas{width:100%;height:150px;background:var(--card);border:1px solid var(--line);display:block}
canvas.on{border-color:var(--g)}canvas.on.b{border-color:var(--b)}
table{border-collapse:collapse;width:100%;font-size:19px}
th,td{border:1px solid var(--line);padding:4px 8px;text-align:right}th:first-child,td:first-child{text-align:left}
th{color:var(--dim);font-weight:400}td.b{color:var(--b)}
.tablewrap{overflow-x:auto}
.note{font-size:18px;color:var(--dim)}
ul{margin:8px 0 0;padding-left:22px;font-size:19px;color:var(--dim)}li{margin:4px 0}b{color:var(--g);font-weight:400}.bb{color:var(--b)}
@media (max-width:760px){.layout{grid-template-columns:1fr}.art{max-width:240px}}
</style></head><body><main>
<h1>Beast composer: v1 vs v1.1</h1>
<p>The same Beast and the same synth, composed two ways. <b>v1</b> is the onchain composer today. <span class="bb">v1.1</span> is a prototype (JavaScript only for now) that keeps v1's themes, keys and form and changes three things:</p>
<ul>
<li><b>Cadence:</b> the theme's last bar steps to the tonic and holds it, so each section and the loop end on purpose.</li>
<li><b>Rhythm:</b> the theme is built from 4-beat rhythm cells (long notes, dotted rhythms, short runs) picked by the Beast's motif seed, with a family per Beast type; the kill-driven ornament density decides how many passing notes appear.</li>
<li><b>Voices:</b> every note is checked against every voice sounding with it. Thirds and sixths are preferred; clashes on the beat, unisons and parallel 5ths/8ves are avoided by moving a note a step or two.</li>
</ul>
<div class="layout">
  <div class="art"><img id="art" alt=""></div>
  <div class="panel">
    <fieldset><legend>Beast (${data.length})</legend><select id="beast" aria-label="Beast">${data.map((b, i) => `<option value="${i}">${esc(b.name)} · ${b.voices} voice${b.voices > 1 ? 's' : ''}, ${b.sections} section${b.sections > 1 ? 's' : ''}</option>`).join('')}</select></fieldset>
    <fieldset><legend>Composer</legend>
      <div class="choices" role="group" aria-label="Composer">
        <button type="button" data-v="v1" aria-pressed="true">v1 (onchain today)</button>
        <button type="button" data-v="v11" aria-pressed="false">v1.1 (prototype)</button>
      </div>
      <div class="controls">
        <button type="button" id="play">▶ Play</button>
        <label class="check"><input type="checkbox" id="drums" checked> Drums</label>
        <label class="check"><input type="checkbox" id="keep" checked> Keep playing when switching</label>
      </div>
      <label class="field">Instrument, the same for v1 and v1.1
        <select id="preset"><option value="auto">Auto: the onchain orchestration (worked out from v1's score, used for both)</option>${[...new Set(PRESETS.map((x) => x.category))].map((c) => `<optgroup label="${esc(c)}">${PRESETS.filter((x) => x.category === c).map((x) => `<option value="${x.program}"${x.program === 0 ? ' selected' : ''}>All voices: ${x.program}: ${esc(x.name)}</option>`).join('')}</optgroup>`).join('')}</select></label>
      <div class="controls">
        <button type="button" id="prev">◀ Prev</button><button type="button" id="next">Next ▶</button>
        <span class="note" id="presetNote"></span>
      </div>
      <span class="note">Switch while it plays to hear the difference: the new version starts from the top.</span>
    </fieldset>
    <div class="roll">
      <div>v1</div><canvas id="rollA" width="1600" height="300" class="on"></canvas>
      <div>v1.1</div><canvas id="rollB" width="1600" height="300" class="b"></canvas>
    </div>
    <div class="tablewrap"><table id="mt"></table></div>
  </div>
</div>
<h2>Across ${SUM.n} Beasts</h2>
<div class="tablewrap"><table>
<tr><th></th><th>Note lengths per score</th><th>Clashes between voices</th><th>Clashes on the beat</th><th>Unisons / octaves</th><th>Parallel 5ths/8ves per score</th><th>Ends on the tonic</th></tr>
<tr><td>v1</td><td>${SUM.v1.durations}</td><td>${SUM.v1.clash}%</td><td>${SUM.v1.clashOnBeat}%</td><td>${SUM.v1.octave}%</td><td>${SUM.v1.parallels}</td><td>${SUM.v1.cadence}%</td></tr>
<tr><td class="b">v1.1</td><td class="b">${SUM.v11.durations}</td><td class="b">${SUM.v11.clash}%</td><td class="b">${SUM.v11.clashOnBeat}%</td><td class="b">${SUM.v11.octave}%</td><td class="b">${SUM.v11.parallels}</td><td class="b">${SUM.v11.cadence}%</td></tr>
</table></div>
<p class="note">Clashes: seconds, sevenths and tritones between voices sounding together, as a share of all voice pairs (multi-voice Beasts). Both versions loop on the form's length, with the same closing rest. Instruments: one TinyChip preset for every voice (pick any of the 100), or Auto, the onchain orchestration worked out from v1's score and applied to both versions; chip drums.</p>
</main>
<script>${inline(midiModules.map((m) => m.js).join('\n'))}</script>
<script>${TINY_NOTICE}\n${inline(tiny)}</script>
<script>${inline(chipBank)}</script>
<script>${inline(chipRuntime)}</script>
<script>
const BEASTS = ${JSON.stringify(data)};
const NAMES = ${JSON.stringify(Object.fromEntries(PRESETS.map((x) => [x.program, x.name])))};
const INSPIRED = ${JSON.stringify(Object.fromEntries(PRESETS.filter((x) => x.inspired).map((x) => [x.program, x.inspired])))};
const v1lib = BeastSound.v1, $ = (id) => document.getElementById(id);
let current = 0, version = 'v1', synth = null, playing = false;
const bytesOf = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const COLORS = ['#4af626', '#ffb000', '#3fd0ff', '#ff5ea8', '#c9a0ff', '#ffffff'];

function withDrums(song) {
  const end = Math.max(song.length_ticks || 0, ...song.notes.map((n) => n[0] + n[1]));
  const bars = Math.ceil(end / 1920) * 1920, drums = [];
  for (let t = 0; t < bars; t += 240) {
    const b = t / 480, onBeat = t % 480 === 0;
    if (onBeat && b % 4 === 0) drums.push([t, 120, 36, 110, 9]);
    if (onBeat && b % 4 === 2) drums.push([t, 120, 38, 90, 9]);
    drums.push([t, 60, 42, onBeat ? 70 : 50, 9]);
  }
  return { notes: song.notes.concat(drums), tempo_us: song.tempo_us, length_ticks: bars };
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
  const a = BEASTS[current].v1.m, b = BEASTS[current].v11.m;
  const row = (label, k, f = (x) => x) => '<tr><td>' + label + '</td><td>' + f(a[k]) + '</td><td class="b">' + f(b[k]) + '</td></tr>';
  $('mt').innerHTML = '<tr><th>This Beast</th><th>v1</th><th>v1.1</th></tr>' + row('Notes', 'notes') + row('Note lengths', 'durations')
    + (a.voices > 1 ? row('Clashes between voices', 'clashPct', (x) => x + '%') + row('Clashes on the beat', 'clashOnBeatPct', (x) => x + '%') + row('Unisons / octaves', 'octavePct', (x) => x + '%') + row('Parallel 5ths/8ves', 'parallels') : '')
    + row('Ends on the tonic', 'cadence', (x) => (x ? 'yes' : 'no'));
}
function show() {
  const b = BEASTS[current];
  $('art').src = b.art;
  drawRoll($('rollA'), b.v1.midi); drawRoll($('rollB'), b.v11.midi);
  metricsTable();
  setInstrument();
}
function stop() { if (synth) synth.stopMIDI(); playing = false; $('play').textContent = '▶ Play'; }
function play() {
  // the full bank at programs 0-99 (and the chip kit); the onchain runtime adds its 20 at 129+
  if (!synth) synth = TinyChipBank.install(new WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 64 }));
  synth.getAudioContext().resume();
  const midi = BEASTS[current][version].midi, song = v1lib.smf.parse(midi);
  const file = $('drums').checked ? v1lib.midi.write(withDrums(song)) : bytesOf(midi);
  synth.loadMIDI(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength));
  synth.loopEnd = Math.ceil(synth.maxTick / synth.song.timebase) * synth.song.timebase;
  synth.setLoop(1);
  // the onchain orchestration, from the score without the drum track
  const channels = [...new Set(song.notes.map((n) => n[4]))].sort((a, b) => a - b);
  synth.playMIDI();
  playing = true; $('play').textContent = '■ Stop';
  setInstrument();
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
function setVersion(v) {
  const was = playing && $('keep').checked; stop(); version = v;
  document.querySelectorAll('[data-v]').forEach((x) => x.setAttribute('aria-pressed', x.dataset.v === v));
  $('rollA').classList.toggle('on', v === 'v1'); $('rollB').classList.toggle('on', v === 'v11');
  if (was) play();
}
(function tickLoop() {
  if (playing && synth) {
    const t = synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time, loop = synth.loopEnd || synth.maxTick;
    const tick = t < 0 ? 0 : t % loop, b = BEASTS[current];
    drawRoll(version === 'v1' ? $('rollA') : $('rollB'), b[version].midi, tick);
  }
  requestAnimationFrame(tickLoop);
})();
$('play').addEventListener('click', () => (playing ? stop() : play()));
$('beast').addEventListener('change', (e) => { const was = playing; stop(); current = +e.target.value; show(); if (was) play(); });
$('drums').addEventListener('change', () => { if (playing) { stop(); play(); } });
$('preset').addEventListener('change', setInstrument);
$('prev').addEventListener('click', () => stepPreset(-1));
$('next').addEventListener('click', () => stepPreset(1));
document.querySelectorAll('[data-v]').forEach((btn) => btn.addEventListener('click', () => setVersion(btn.dataset.v)));
show();
setInstrument();
</script></body></html>`;
writeFileSync(out + 'compare.html', html);
console.log(`compare.html: ${(html.length / 1000).toFixed(0)} KB · ${data.length} Beasts`);
console.log('v1  ', JSON.stringify(SUM.v1));
console.log('v1.1', JSON.stringify(SUM.v11));

// Build public/onchain/engines.html: the same onchain MIDI played by two sound engines.
//   node onchain/engines-demo.mjs        (after onchain/build.mjs and onchain/gallery.mjs)
//
// Each Beast's MIDI is what the Cairo composer's get_score_midi returns (the package engine writes
// identical bytes; test/golden.test.mjs checks them against Cairo). Engines:
//   chip  our library: smf (parse) → play (scheduler) → synth (chip voices + drums)
//   tiny  webaudio-tinysynth by g200kg (Apache-2.0), a General MIDI synth that reads MIDI files
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { composeBeast, decodeTokenId } from '../src/index.js';
import { loadBuiltModules } from './modules.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = here + '../public/onchain/';
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');

// tinysynth, minified, with its license notice kept
const tinySrc = await (await fetch('https://cdn.jsdelivr.net/gh/g200kg/webaudio-tinysynth@master/webaudio-tinysynth.js')).text();
const tiny = (await build({ stdin: { contents: tinySrc, loader: 'js' }, minify: true, write: false, logLevel: 'error' })).outputFiles[0].text;
const TINY_NOTICE = '/*! webaudio-tinysynth (c) g200kg, Apache License 2.0, https://github.com/g200kg/webaudio-tinysynth */';
// TinyChip: 50 chiptune presets + a chip drum kit for tinysynth, from its own setTimbre/noiseBuf hooks
const chipPack = (await build({ stdin: { contents: readFileSync(here + 'tinysynth-chip.js', 'utf8'), loader: 'js' }, minify: true, write: false, logLevel: 'error' })).outputFiles[0].text;
globalThis.window = globalThis; await import('./tinysynth-chip.js');
const CHIP_PRESETS = globalThis.TinyChip.PRESETS.map(({ program, name, category }) => ({ program, name, category }));

const chipModules = loadBuiltModules(['midi', 'synth', 'play', 'smf']);
const chipBytes = chipModules.reduce((n, m) => n + m.js.length, 0);

// Beasts: the Warlock demo (heaviest score) plus gallery Beasts across the complexity range
const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));
const cache = JSON.parse(readFileSync(here + '.gallery-cache.json', 'utf8'));
const gallery = JSON.parse(readFileSync(out + 'gallery.json', 'utf8'));
const pick = [0.15, 0.6, 0.85, 1].map((q) => gallery[Math.min(gallery.length - 1, Math.round(q * (gallery.length - 1)))]);
const beasts = [
  { name: 'Warlock (demo stats)', svg: Buffer.from(fx.svg_b64, 'base64').toString('utf8'), song: composeBeast(decodeTokenId(BigInt(fx.token_id)), { adventurers_killed: 412, scars: 7, summit_held_seconds: 86400, rank: 3, species_count: 1243 }) },
  ...pick.map((g) => ({ name: `${g.name} #${g.token}`, svg: readFileSync(out + `beasts/${g.token}.svg`, 'utf8'), song: composeBeast(cache[g.token].beast, cache[g.token].live) })),
];
const data = beasts.map((b) => ({
  name: b.name,
  svg: 'data:image/svg+xml;base64,' + Buffer.from(b.svg).toString('base64'),
  midi: Buffer.from(b.song.midi).toString('base64'),
  notes: b.song.events.length,
  voices: new Set(b.song.events.map((e) => e.voice)).size,
  bytes: b.song.midi.length,
  felts: Math.ceil(b.song.midi.length / 31) + 1,
}));

const GM = [[80, 'Lead 1 (square)'], [81, 'Lead 2 (sawtooth)'], [87, 'Lead 8 (bass + lead)'], [82, 'Lead 3 (calliope)'], [38, 'Synth Bass 1'], [6, 'Harpsichord'], [0, 'Acoustic Grand Piano'], [48, 'String Ensemble'], [73, 'Flute']];

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beast MIDI Engines</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=VT323&display=swap">
<style>
:root{--g:#4af626;--dim:rgba(74,246,38,.62);--line:rgba(74,246,38,.25);--bg:#000;--card:#070a07}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--g);font-family:"VT323",ui-monospace,monospace}
body::after{content:"";position:fixed;inset:0;pointer-events:none;background:repeating-linear-gradient(to bottom,transparent 0 2px,rgba(0,0,0,.2) 2px 3px)}
main{width:min(100% - 32px,960px);margin:0 auto;padding:32px 0 48px}
h1{margin:0;font-weight:400;font-size:clamp(34px,7vw,54px);line-height:1;text-transform:uppercase;text-shadow:0 0 14px rgba(74,246,38,.5)}
p{margin:10px 0 0;font-size:20px;color:var(--dim);max-width:70ch}
code{font:inherit;color:var(--g)}
.layout{display:grid;grid-template-columns:minmax(0,300px) minmax(0,1fr);gap:24px;margin-top:24px;align-items:start}
.art{background:var(--card);border:1px solid var(--line);padding:10px}.art img{display:block;width:100%;height:auto}
.panel{display:grid;gap:18px}
fieldset{margin:0;min-width:0;border:1px solid var(--line);padding:12px 14px 14px;display:grid;gap:10px}
legend{padding:0 6px;font-size:18px;color:var(--dim);text-transform:uppercase}
.choices{display:flex;flex-wrap:wrap;gap:8px}
.choices button,.controls button{font:inherit;font-size:20px;padding:6px 14px;background:transparent;color:var(--g);border:1px solid var(--line);cursor:pointer}
.choices button[aria-pressed="true"]{background:var(--g);color:#000}
.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
.controls #play{background:var(--g);color:#000;min-width:120px}
select{font:inherit;font-size:20px;background:#000;color:var(--g);border:1px solid var(--line);padding:4px 8px;width:100%;min-width:0}
label#gmRow,#chipRow label{display:grid;gap:6px;font-size:18px;color:var(--dim)}
#chipRow{display:grid;gap:10px}#chipRow label.check{display:flex;color:var(--g)}
label.check{display:flex;gap:8px;align-items:center;font-size:20px}
.facts{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px}
.fact{border:1px solid var(--line);padding:8px 10px}.fact b{display:block;font-weight:400;font-size:24px}.fact small{font-size:16px;color:var(--dim)}
.note{font-size:18px;color:var(--dim)}
[hidden]{display:none!important}
@media (max-width:720px){.layout{grid-template-columns:1fr}.art{max-width:320px}}
</style></head><body><main>
<h1>One MIDI, three engines</h1>
<p>Each Beast's music is a standard MIDI file, the bytes the Cairo composer's <code>get_score_midi</code> returns onchain. Switch the engine that plays it: our chip synth (MIDI parsed into chiptune voices), webaudio-tinysynth (a General MIDI synth), or tinysynth with the TinyChip pack (50 chiptune presets and a chip drum kit, built from tinysynth's own timbre engine). Same notes, same file.</p>
<div class="layout">
  <div class="art"><img id="art" alt=""></div>
  <div class="panel">
    <fieldset><legend>Beast</legend><select id="beast" aria-label="Beast">${data.map((b, i) => `<option value="${i}">${esc(b.name)} (${b.notes} notes)</option>`).join('')}</select></fieldset>
    <fieldset><legend>Sound engine</legend>
      <div class="choices" role="group" aria-label="Sound engine">
        <button type="button" data-engine="chip" aria-pressed="true">Chip synth (ours)</button>
        <button type="button" data-engine="tiny" aria-pressed="false">TinySynth (General MIDI)</button>
        <button type="button" data-engine="tinychip" aria-pressed="false">TinySynth + chip pack</button>
      </div>
      <label id="gmRow" hidden>Instrument <select id="gm">${GM.map(([n, label]) => `<option value="${n}">${n}: ${esc(label)}</option>`).join('')}</select></label>
      <div id="chipRow" hidden>
        <label>Chip preset (${CHIP_PRESETS.length}) <select id="chipPreset">${[...new Set(CHIP_PRESETS.map((p) => p.category))].map((c) => `<optgroup label="${esc(c)}">${CHIP_PRESETS.filter((p) => p.category === c).map((p) => `<option value="${p.program}">${p.program}: ${esc(p.name)}</option>`).join('')}</optgroup>`).join('')}</select></label>
        <label class="check"><input type="checkbox" id="bassVoice" checked> Lowest voice on Triangle Bass</label>
      </div>
      <span class="note" id="engineNote"></span>
    </fieldset>
    <div class="controls">
      <button type="button" id="play">▶ Play</button>
      <label class="check"><input type="checkbox" id="drums" checked> Drums</label>
      <button type="button" id="dl">Download .mid</button>
    </div>
    <div class="facts">
      <div class="fact"><b id="fNotes"></b><small>notes</small></div>
      <div class="fact"><b id="fBytes"></b><small>MIDI bytes</small></div>
      <div class="fact"><b id="fFelts"></b><small>felts onchain</small></div>
      <div class="fact"><b id="fEngine"></b><small>engine size</small></div>
    </div>
    <p class="note">Drums are not in the MIDI file: the chip engine adds its own pattern, and for tinysynth the page adds the same pattern as a General MIDI drum track (channel 10), played by the GM kit or the TinyChip chip kit.</p>
  </div>
</div>
</main>
<script>${inline(chipModules.map((m) => m.js).join('\n'))}</script>
<script>${TINY_NOTICE}\n${inline(tiny)}</script>
<script>${inline(chipPack)}</script>
<script>
const BEASTS = ${JSON.stringify(data)};
const SIZES = { chip: ${chipBytes}, tiny: ${tiny.length}, tinychip: ${tiny.length + chipPack.length} };
const v1 = BeastSound.v1;
const $ = (id) => document.getElementById(id);
let engine = 'chip', current = 0, handle = null, tiny = null, tinyOn = false, tinyChip = null;
const BASS_PROGRAM = 20; // TinyChip: Triangle Bass (NES)
const bytesOf = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

// The chip engine's drum pattern as General MIDI drums (kick 36, snare 38, hats 42 / open 46).
function withDrums(song) {
  const end = Math.max(...song.notes.map((n) => n[0] + n[1]));
  const bars = Math.ceil(end / 1920) * 1920, drums = [];
  for (let t = 0; t < bars; t += 240) {
    const beat = t / 480, onBeat = t % 480 === 0;
    if (onBeat && beat % 4 === 0) drums.push([t, 120, 36, 110, 9]);
    if (onBeat && beat % 4 === 2) drums.push([t, 120, 38, 90, 9]);
    drums.push([t, 60, !onBeat && Math.random() < 0.125 ? 46 : 42, onBeat ? 70 : 50, 9]);
  }
  return { notes: song.notes.concat(drums), tempo_us: song.tempo_us };
}

function stop() {
  if (handle) { handle.stop(); handle = null; }
  if (tinyOn) { (tinyOn === 'chip' ? tinyChip : tiny).stopMIDI(); tinyOn = false; }
  $('play').textContent = '▶ Play';
}
function play() {
  const b = BEASTS[current];
  const song = v1.smf.parse(b.midi);
  if (engine === 'chip') {
    handle = v1.play(song, { drums: $('drums').checked });
  } else {
    // Separate instances: the chip pack rewrites programs 0-49 and the drum map
    if (engine === 'tiny' && !tiny) tiny = new WebAudioTinySynth({ quality: 1, useReverb: 0 });
    if (engine === 'tinychip' && !tinyChip) tinyChip = TinyChip.install(new WebAudioTinySynth({ quality: 1, useReverb: 0 }));
    const synth = engine === 'tiny' ? tiny : tinyChip;
    synth.getAudioContext().resume();
    const file = $('drums').checked ? v1.midi.write(withDrums(song)) : bytesOf(b.midi);
    synth.loadMIDI(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength));
    synth.setLoop(1);
    synth.playMIDI();
    tinyOn = engine === 'tiny' ? 'gm' : 'chip';
    setProgram();
  }
  $('play').textContent = '■ Stop';
}
function setProgram() {
  if (tinyOn === 'gm') {
    const prg = +$('gm').value;
    for (let ch = 0; ch < 16; ch++) if (ch !== 9) tiny.send([0xc0 | ch, prg]);
  } else if (tinyOn === 'chip') {
    const prg = +$('chipPreset').value;
    // the voice with the lowest average pitch can take the bass preset
    const notes = v1.smf.parse(BEASTS[current].midi).notes, avg = {};
    for (const n of notes) (avg[n[4]] ||= []).push(n[2]);
    const voices = Object.keys(avg).map(Number);
    const low = voices.length > 1 ? voices.reduce((a, v) => (avg[v].reduce((x, y) => x + y, 0) / avg[v].length < avg[a].reduce((x, y) => x + y, 0) / avg[a].length ? v : a)) : -1;
    for (let ch = 0; ch < 16; ch++) if (ch !== 9) tinyChip.send([0xc0 | ch, $('bassVoice').checked && ch === low ? BASS_PROGRAM : prg]);
  }
}
function show() {
  const b = BEASTS[current];
  $('art').src = b.svg;
  $('fNotes').textContent = b.notes;
  $('fBytes').textContent = b.bytes.toLocaleString();
  $('fFelts').textContent = b.felts;
  $('fEngine').textContent = (SIZES[engine] / 1000).toFixed(1) + ' KB';
  $('gmRow').hidden = engine !== 'tiny';
  $('chipRow').hidden = engine !== 'tinychip';
  $('engineNote').textContent = engine === 'chip'
    ? 'MIDI parsed by the smf module, played by our chip synth (Triangle lead, panned voices).'
    : engine === 'tiny' ? 'MIDI loaded straight into tinysynth; pick any General MIDI instrument.'
    : 'Tinysynth with the TinyChip pack: sampled 8-bit waveforms (pulse, NES triangle, 4-bit saw, GB wave, LFSR noise) through its own timbre engine, plus a chip drum kit.';
}
$('play').addEventListener('click', () => ((handle || tinyOn) ? stop() : play()));
$('beast').addEventListener('change', (e) => { const was = handle || tinyOn; stop(); current = +e.target.value; show(); if (was) play(); });
$('drums').addEventListener('change', () => { if (handle || tinyOn) { stop(); play(); } });
$('gm').addEventListener('change', setProgram);
$('chipPreset').addEventListener('change', setProgram);
$('bassVoice').addEventListener('change', setProgram);
document.querySelectorAll('[data-engine]').forEach((btn) => btn.addEventListener('click', () => {
  const was = handle || tinyOn; stop();
  engine = btn.dataset.engine;
  document.querySelectorAll('[data-engine]').forEach((x) => x.setAttribute('aria-pressed', x === btn));
  show(); if (was) play();
}));
$('dl').addEventListener('click', () => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([bytesOf(BEASTS[current].midi)], { type: 'audio/midi' }));
  a.download = 'beast-' + current + '.mid'; a.click();
});
show();
</script></body></html>`;
writeFileSync(out + 'engines.html', html);
console.log(`engines.html: ${(html.length / 1000).toFixed(0)} KB · ${data.length} Beasts · chip engine ${chipBytes} B · tinysynth ${tiny.length} B`);

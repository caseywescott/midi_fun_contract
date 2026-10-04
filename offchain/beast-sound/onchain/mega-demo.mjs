// Build public/onchain/mega.html: a Beast normal against mega (the shiny flag), A/B, as
// onchain-tinysynth plays it: the self-contained MIDI (src/full_midi.js, with the mega arrangement
// options) through the class's pinned engine with the Beast SynthSettings timbres installed.
//   node onchain/mega-demo.mjs <onchain-tinysynth>/tests/vendor/webaudio-tinysynth-<ref>.min.js
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { beastSynthSettings } from './tinychip/synth_settings.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const engineFile = process.argv[2];
if (!engineFile) { console.error('usage: node onchain/mega-demo.mjs <webaudio-tinysynth engine .min.js>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const NOTICE = '/*! webaudio-tinysynth (c) g200kg, Apache License 2.0; Provable Games fork as pinned by onchain-tinysynth, https://github.com/Provable-Games/webaudio-tinysynth */';
const composer = (await build({
  stdin: { contents: "import { engine, beastName } from './src/index.js'; import { beastFullMidi } from './src/full_midi.js'; window.BS = { engine, beastName, beastFullMidi };", resolveDir: here + '..', loader: 'js' },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;
const W = { Sine: 'sine', Square: 'square', Sawtooth: 'sawtooth', Triangle: 'triangle', WhiteNoise: 'n0', MetallicNoise: 'n1' };
const settings = beastSynthSettings();
const timbres = settings.timbres.map((t) => [t.drum ? 1 : 0, t.slot, t.operators.map((o) => ({ g: o.route, w: W[o.wave], v: o.volume / 1e4, t: o.ratio / 1e4, f: o.offset_hz / 1e4, a: o.attack / 1e4, h: o.hold / 1e4, d: o.decay / 1e4, s: o.sustain / 1e4, r: o.release / 1e4, p: o.pitch_ratio / 1e4, q: o.pitch_time / 1e4, k: o.key_scale / 1e4 }))]);

// Beasts to try: the live rank-1 Warlock, then a spread of genesis species (Magical, Hunter, Brute)
const SPECIES = [
  ['Sorrow Peak Warlock', { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, tier: 1, beast_type: 0 }],
  ...[[1, 'T1'], [6, 'T2'], [11, 'T3'], [16, 'T4'], [21, 'T5'], [26, 'T1'], [31, 'T2'], [41, 'T4'], [51, 'T1'], [53, 'T1'], [61, 'T3'], [71, 'T5']].map(([id]) => [null, { id }]),
];

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beast Mega A/B</title>
<style>
:root{--bg:#f6f4ef;--fg:#1d1b18;--mut:#6b655c;--card:#fff;--line:#e2ddd3;--acc:#7a3cff;--acc2:#e0b000}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--acc2:#ffd23f}}
:root[data-theme="dark"]{--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--acc2:#ffd23f}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:760px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 20px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px}
label{display:block;font-size:13px;color:var(--mut);margin-bottom:4px}select{width:100%;padding:8px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font:inherit}
.row{display:grid;grid-template-columns:1fr 1fr;gap:12px}@media(max-width:520px){.row{grid-template-columns:1fr}}
.ab{display:grid;grid-template-columns:1fr 1fr;gap:10px}.ab button{padding:16px;border-radius:12px;border:2px solid var(--line);background:var(--bg);color:var(--fg);font:600 17px system-ui;cursor:pointer}
.ab button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 14%,var(--bg))}.ab button.mega.on{border-color:var(--acc2);background:color-mix(in srgb,var(--acc2) 18%,var(--bg))}
.ctl{display:flex;gap:10px;margin-top:12px}.ctl button{flex:1;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--fg);color:var(--bg);font:600 15px system-ui;cursor:pointer}.ctl button.stop{background:var(--bg);color:var(--fg)}
.chk{display:grid;grid-template-columns:1fr 1fr;gap:8px 16px}@media(max-width:520px){.chk{grid-template-columns:1fr}}.chk label{display:flex;gap:8px;align-items:flex-start;color:var(--fg);font-size:14px;margin:0}.chk small{display:block;color:var(--mut);font-size:12px}
#info{font:12px/1.6 ui-monospace,monospace;color:var(--mut);white-space:pre-wrap;margin:0}
</style></head><body><main>
<h1>Beast Mega A/B</h1>
<p class="sub">Normal against mega (the shiny flag), as onchain-tinysynth plays it: the self-contained MIDI through the class's engine with the Beast sound settings. Switch while playing to compare.</p>
<div class="card"><div class="row">
<div><label for="beast">Beast</label><select id="beast"></select></div>
<div><label for="state">Live state</label><select id="state"><option value="calm">Calm: no kills, rank 500</option><option value="veteran" selected>Veteran: 40 kills, 9 defeats, rank 1</option></select></div>
</div></div>
<div class="card"><div class="ab"><button id="normal" class="on">Normal</button><button id="mega" class="mega">Mega ✦</button></div>
<div class="ctl"><button id="play">▶ Play</button><button id="stop" class="stop">■ Stop</button></div></div>
<div class="card"><label>Mega ingredients</label><div class="chk">
<label><input type="checkbox" id="o-shiny" checked><span>Shiny flag in the score<small>today's effect: 120 → 126 BPM, louder, tenuto</small></span></label>
<label><input type="checkbox" id="o-double" checked><span>Octave doubling<small>the lead an octave up on a bright preset, panned opposite</small></span></label>
<label><input type="checkbox" id="o-groove" checked><span>Mega groove<small>sixteenth hats, an extra kick, a crash on every section</small></span></label>
<label><input type="checkbox" id="o-lift" checked><span>Final lift<small>the last section a whole step up, home again on the loop</small></span></label>
<div><label for="o-reverb" style="margin-top:4px">Mega reverb (SynthSettings.reverb)</label><select id="o-reverb"><option value="0">0 (off, as normal)</option><option value="10">10</option><option value="15" selected>15</option><option value="20">20</option><option value="30">30 (the class's default)</option></select></div>
</div></div>
<div class="card"><pre id="info"></pre></div>
</main>
<script>${NOTICE}\n${inline(tiny)}</script>
<script>${inline(composer)}</script>
<script>
const TIMBRES = ${JSON.stringify(timbres)};
const SPECIES = ${JSON.stringify(SPECIES)};
const LIVE = { calm: { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954 },
  veteran: { adventurers_killed: 40, scars: 9, summit_held_seconds: 0, rank: 1, species_count: 954 } };
const $ = (id) => document.getElementById(id);
const beasts = SPECIES.map(([name, b]) => {
  const full = b.tier ? b : { prefix: 0, suffix: 0, level: 30, health: 120, tier: Math.floor(((b.id - 1) % 25) / 5) + 1, beast_type: Math.floor((b.id - 1) / 25), ...b };
  return { name: name || BS.beastName({ ...full, shiny: 0, animated: 0 }), b: full };
});
beasts.forEach((x, i) => $('beast').add(new Option(x.name + '  (tier ' + x.b.tier + ')', i)));
let mega = false, synth = null, playing = false;
function make() {
  const x = beasts[+$('beast').value], live = LIVE[$('state').value];
  const shiny = mega && $('o-shiny').checked ? 1 : 0;
  const r = BS.engine.render({ ...x.b, shiny, animated: 0 }, live);
  const opts = mega ? { double: $('o-double').checked, groove: $('o-groove').checked, lift: $('o-lift').checked } : {};
  const midi = BS.beastFullMidi(r, BS.engine.formLength, opts);
  const reverb = mega ? +$('o-reverb').value : 0;
  $('info').textContent = (mega ? 'MEGA' : 'normal') + ' · ' + (60000000 / r.params.tempo_us).toFixed(1) + ' BPM · ' + r.params.voice_count + ' voices · tier ' + r.params.tier + ' · ' + Math.round(BS.engine.formLength(r.form) / r.form.section_ticks) + ' sections · ' + midi.length + ' bytes MIDI · reverb ' + reverb;
  return { midi, reverb };
}
function ensure() {
  if (synth) return synth;
  synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  synth.setQuality(1); synth.setMasterVol(0.4); synth.setVoices(64);
  for (const [drum, slot, ops] of TIMBRES) synth.setTimbre(drum, slot, ops.map((o) => ({ ...o })));
  return synth;
}
function start() {
  const s = ensure(), { midi, reverb } = make();
  s.getAudioContext().resume();
  s.stopMIDI(); s.setReverbLev(reverb / 100);
  s.loadMIDI(midi.buffer.slice(midi.byteOffset, midi.byteOffset + midi.length));
  s.setLoop(1); s.setLoopEnd(s.getPlayStatus().maxTick); s.playMIDI(); playing = true;
}
function refresh() { if (playing) start(); else make(); }
$('play').onclick = start;
$('stop').onclick = () => { if (synth) synth.stopMIDI(); playing = false; };
$('normal').onclick = () => { mega = false; $('normal').classList.add('on'); $('mega').classList.remove('on'); refresh(); };
$('mega').onclick = () => { mega = true; $('mega').classList.add('on'); $('normal').classList.remove('on'); refresh(); };
for (const id of ['beast', 'state', 'o-shiny', 'o-double', 'o-groove', 'o-lift', 'o-reverb']) $(id).onchange = refresh;
make();
</script></body></html>`;
writeFileSync(here + '../public/onchain/mega.html', html);
console.log('public/onchain/mega.html', html.length, 'bytes');

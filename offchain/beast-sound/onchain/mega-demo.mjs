// Build public/onchain/mega.html: a Beast normal against mega (the shiny flag), A/B, as
// onchain-midi-player plays it: the self-contained MIDI (src/full_midi.js, with the mega arrangement
// options) through the class's pinned engine with the Beast TinySynthSettings timbres installed. The
// score comes from composer v1.1 with the compare page's chosen options (same mode, even phrases,
// history: src/engine_v11.js) or engine v1 (onchain today); the Beasts and their live states are the
// compare page's (the Warlock with demo stats, then the gallery).
//   node onchain/mega-demo.mjs <onchain-midi-player>/tests/vendor/webaudio-tinysynth-<ref>.min.js
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { beastSynthSettings } from './tinychip/synth_settings.mjs';
import { decodeTokenId } from '../src/index.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const engineFile = process.argv[2];
if (!engineFile) { console.error('usage: node onchain/mega-demo.mjs <webaudio-tinysynth engine .min.js>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const NOTICE = '/*! webaudio-tinysynth (c) g200kg, Apache License 2.0; Provable Games fork as pinned by onchain-midi-player, https://github.com/Provable-Games/webaudio-tinysynth */';
const composer = (await build({
  stdin: { contents: "import { engine, beastName } from './src/index.js'; import { createEngineV11 } from './src/engine_v11.js'; import { beastFullMidi } from './src/full_midi.js'; window.BS = { engine, v11: createEngineV11(engine), beastName, beastFullMidi };", resolveDir: here + '..', loader: 'js' },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;
const W = { Sine: 'sine', Square: 'square', Sawtooth: 'sawtooth', Triangle: 'triangle', WhiteNoise: 'n0', MetallicNoise: 'n1' };
const settings = beastSynthSettings();
// Custom(i) plays settings.waves[i] (Samples), registered under the name onchain-midi-player's player gives it
const waves = settings.waves.map((w) => w.Samples.map((v) => v / 128));
const timbres = settings.timbres.map((t) => [t.drum ? 1 : 0, t.slot, t.operators.map((o) => ({ g: o.route, w: typeof o.wave === 'string' ? W[o.wave] : 'nS' + o.wave.Custom, v: o.volume / 1e4, t: o.ratio / 1e4, f: o.offset_hz / 1e4, a: o.attack / 1e4, h: o.hold / 1e4, d: o.decay / 1e4, s: o.sustain / 1e4, r: o.release / 1e4, p: o.pitch_ratio / 1e4, q: o.pitch_time / 1e4, k: o.key_scale / 1e4 }))]);

// the compare page's Beasts: the Warlock with its demo stats, then the gallery (most voices first)
const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));
const cache = JSON.parse(readFileSync(here + '.gallery-cache.json', 'utf8'));
const gallery = JSON.parse(readFileSync(here + '../public/onchain/gallery.json', 'utf8'));
const plain = (b) => Object.fromEntries(Object.entries(b).map(([k, v]) => [k, typeof v === 'bigint' ? Number(v) : v]));
const BEASTS = [
  { name: fx.name + ' (demo stats)', beast: plain(decodeTokenId(BigInt(fx.token_id))), live: { adventurers_killed: 412, scars: 7, summit_held_seconds: 0, rank: 3, species_count: 1243 } },
  ...gallery.map((g) => ({ g, ...cache[g.token] })).sort((a, b) => (b.g.voices ?? 0) - (a.g.voices ?? 0) || (b.g.notes ?? 0) - (a.g.notes ?? 0))
    .map(({ g, beast, live }) => ({ name: g.name + ' #' + g.token, beast: plain(beast), live })),
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
<p class="sub">Normal against mega (the shiny flag; Normal plays every Beast unshiny, Mega shiny), as onchain-midi-player plays it: the self-contained MIDI through the class's engine with the Beast sound settings (every voice on the Triangle Lead for now, reverb 30). Switch while playing to compare.</p>
<div class="card"><div class="row">
<div><label for="beast">Beast</label><select id="beast"></select></div>
<div><label for="composer">Composer</label><select id="composer"><option value="v11m" selected>v1.1: same mode, even phrases, history (compare page)</option><option value="v1">v1 (onchain today)</option></select></div>
</div></div>
<div class="card"><div class="ab"><button id="normal" class="on">Normal</button><button id="mega" class="mega">Mega ✦</button></div>
<div class="ctl"><button id="play">▶ Play</button><button id="stop" class="stop">■ Stop</button></div></div>
<div class="card"><label>Mega ingredients</label><div class="chk">
<label><input type="checkbox" id="o-shiny" checked><span>Shiny flag in the score<small>today's only audible effect: 120 → 126 BPM (same notes)</small></span></label>
<label><input type="checkbox" id="o-double" checked><span>Octave doubling<small>the lead an octave up on a bright preset, panned opposite</small></span></label>
<label><input type="checkbox" id="o-groove" checked><span>Mega groove<small>sixteenth hats, an extra kick, a crash on every section</small></span></label>
<label><input type="checkbox" id="o-lift" checked><span>Final lift<small>the last section a whole step up, home again on the loop</small></span></label>
</div></div>
<div class="card"><pre id="info"></pre></div>
</main>
<script>${NOTICE}\n${inline(tiny)}</script>
<script>${inline(composer)}</script>
<script>
const TIMBRES = ${JSON.stringify(timbres)}, WAVES = ${JSON.stringify(waves)};
const BEASTS = ${JSON.stringify(BEASTS)};
const $ = (id) => document.getElementById(id);
BEASTS.forEach((x, i) => $('beast').add(new Option(x.name + '  (tier ' + x.beast.tier + (x.beast.shiny ? ', shiny' : '') + ')', i)));
let mega = false, synth = null, playing = false;
function make() {
  const x = BEASTS[+$('beast').value], live = x.live;
  const shiny = mega && $('o-shiny').checked ? 1 : 0;
  const beast = { ...x.beast, shiny };
  const r = $('composer').value === 'v1' ? BS.engine.render(beast, live) : BS.v11.render(beast, live, { keys: 'mode', even: true, traj: true });
  const opts = mega ? { double: $('o-double').checked, groove: $('o-groove').checked, lift: $('o-lift').checked } : {};
  const midi = BS.beastFullMidi(r, BS.engine.formLength, opts);
  const reverb = ${settings.reverb};
  $('info').textContent = (mega ? 'MEGA' : 'normal') + ' · ' + ($('composer').value === 'v1' ? 'v1' : 'v1.1') + ' · ' + r.form.events.length + ' notes · ' + (60000000 / r.params.tempo_us).toFixed(1) + ' BPM · ' + r.params.voice_count + ' voices · tier ' + r.params.tier + ' · ' + Math.round(BS.engine.formLength(r.form) / r.form.section_ticks) + ' sections · ' + midi.length + ' bytes MIDI · reverb ' + reverb;
  return { midi, reverb };
}
function ensure() {
  if (synth) return synth;
  synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  synth.setQuality(${settings.quality}); synth.setMasterVol(${settings.master_vol} / 100); synth.setVoices(${settings.voices});
  WAVES.forEach((s, i) => synth.setSampleWave('nS' + i, s));
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
for (const id of ['beast', 'composer', 'o-shiny', 'o-double', 'o-groove', 'o-lift']) $(id).onchange = refresh;
make();
</script></body></html>`;
writeFileSync(here + '../public/onchain/mega.html', html);
console.log('public/onchain/mega.html', html.length, 'bytes');

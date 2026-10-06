// Build public/onchain/lab.html: the Beast Sound lab, four listening prototypes (src/lab.js) on composer
// v1.1 and the self-contained MIDI, through onchain-midi-player's pinned engine with all 20 TinyChip
// timbres: event tracks (from each Beast's real Death Mountain records, onchain/.events-cache.json),
// the scale-start progression, the never-ending drift, and Yeti specials.
//   node onchain/events-cache.mjs && node onchain/lab-demo.mjs <onchain-midi-player>/tests/vendor/webaudio-tinysynth-<ref>.min.js
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { beastSynthSettings } from './tinychip/synth_settings.mjs';
import { ESSENTIALS, loadBank } from './tinychip/essentials.mjs';
import { decodeTokenId } from '../src/index.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const engineFile = process.argv[2];
if (!engineFile) { console.error('usage: node onchain/lab-demo.mjs <webaudio-tinysynth engine .min.js>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const NOTICE = '/*! webaudio-tinysynth (c) g200kg, Apache License 2.0; Provable Games fork as pinned by onchain-midi-player, https://github.com/Provable-Games/webaudio-tinysynth */';
const composer = (await build({
  stdin: { contents: "import { engine, beastName } from './src/index.js'; import { createEngineV11 } from './src/engine_v11.js'; import * as lab from './src/lab.js'; window.BS = { engine, v11: createEngineV11(engine), beastName, lab };", resolveDir: here + '..', loader: 'js' },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;
const W = { Sine: 'sine', Square: 'square', Sawtooth: 'sawtooth', Triangle: 'triangle', WhiteNoise: 'n0', MetallicNoise: 'n1' };
const settings = beastSynthSettings(undefined, ESSENTIALS);
const PRESET_NAMES = Object.fromEntries(loadBank().PRESETS.filter((x) => ESSENTIALS.includes(x.program)).map((x) => [x.program, x.name]));
const waves = settings.waves.map((w) => w.Samples.map((v) => v / 128));
const timbres = settings.timbres.map((t) => [t.drum ? 1 : 0, t.slot, t.operators.map((o) => ({ g: o.route, w: typeof o.wave === 'string' ? W[o.wave] : 'nS' + o.wave.Custom, v: o.volume / 1e4, t: o.ratio / 1e4, f: o.offset_hz / 1e4, a: o.attack / 1e4, h: o.hold / 1e4, d: o.decay / 1e4, s: o.sustain / 1e4, r: o.release / 1e4, p: o.pitch_ratio / 1e4, q: o.pitch_time / 1e4, k: o.key_scale / 1e4 }))]);

const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));
const cache = JSON.parse(readFileSync(here + '.gallery-cache.json', 'utf8'));
const gallery = JSON.parse(readFileSync(here + '../public/onchain/gallery.json', 'utf8'));
const events = JSON.parse(readFileSync(here + '.events-cache.json', 'utf8'));
const plain = (b) => Object.fromEntries(Object.entries(b).map(([k, v]) => [k, typeof v === 'bigint' ? Number(v) : v]));
const BEASTS = [
  { name: fx.name + ' (demo stats)', art: 'data:image/svg+xml;base64,' + fx.svg_b64, beast: plain(decodeTokenId(BigInt(fx.token_id))), live: { adventurers_killed: 412, scars: 7, summit_held_seconds: 0, rank: 3, species_count: 1243 }, events: events.warlock },
  ...gallery.map((g) => ({ g, ...cache[g.token] })).sort((a, b) => (b.g.voices ?? 0) - (a.g.voices ?? 0) || (b.g.notes ?? 0) - (a.g.notes ?? 0))
    .map(({ g, beast, live }) => ({ name: g.name + ' #' + g.token, art: 'beasts/' + g.token + '.svg', beast: plain(beast), live, events: events[g.token] })),
];

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beast Sound Lab</title>
<style>
:root{--bg:#f6f4ef;--fg:#1d1b18;--mut:#6b655c;--card:#fff;--line:#e2ddd3;--acc:#7a3cff;--acc2:#e0b000}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--acc2:#ffd23f}}
:root[data-theme="dark"]{--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--acc2:#ffd23f}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:760px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 20px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px}
label{display:block;font-size:13px;color:var(--mut);margin-bottom:4px}select{width:100%;padding:8px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font:inherit}
.row{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px}@media(max-width:520px){.row{grid-template-columns:1fr}}
.ab{display:grid;grid-template-columns:1fr 1fr;gap:10px}.ab button{padding:16px;border-radius:12px;border:2px solid var(--line);background:var(--bg);color:var(--fg);font:600 17px system-ui;cursor:pointer}
.ab button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 14%,var(--bg))}.ab button.mega.on{border-color:var(--acc2);background:color-mix(in srgb,var(--acc2) 18%,var(--bg))}
.ctl{display:flex;gap:10px;margin-top:12px}.ctl button{flex:1;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--fg);color:var(--bg);font:600 15px system-ui;cursor:pointer}.ctl button.stop{background:var(--bg);color:var(--fg)}
.chk{display:grid;grid-template-columns:1fr 1fr;gap:8px 16px}@media(max-width:520px){.chk{grid-template-columns:1fr}}.chk label{display:flex;gap:8px;align-items:flex-start;color:var(--fg);font-size:14px;margin:0}.chk small{display:block;color:var(--mut);font-size:12px}
#info{font:12px/1.6 ui-monospace,monospace;color:var(--mut);white-space:pre-wrap;margin:0}
.tabs{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}.tabs button{padding:10px 6px;border-radius:10px;border:2px solid var(--line);background:var(--bg);color:var(--fg);font:600 14px system-ui;cursor:pointer}.tabs button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 14%,var(--bg))}.panel{display:none}.panel.on{display:block}input[type=range]{width:100%}.note{font-size:13px;color:var(--mut);margin:8px 0 0}.beastcard{display:grid;grid-template-columns:125px 1fr;gap:16px;align-items:center}#art{width:125px;height:175px;border-radius:8px;object-fit:contain;background:#000}@media(max-width:420px){.beastcard{grid-template-columns:96px 1fr}#art{width:96px;height:134px}}\n</style></head><body><main>
<h1>Beast Sound Lab</h1>
<p class="sub">Four prototypes on composer v1.1, played as onchain-midi-player plays a token_uri (the self-contained MIDI, the class's engine, the TinyChip timbres). Pick a Beast, a tab, then play; changes apply while playing.</p>
<div class="card beastcard"><img id="art" alt="" width="125" height="175"><div><label for="beast">Beast</label><select id="beast"></select>
<div class="ctl"><button id="play">&#9654; Play</button><button id="stop" class="stop">&#9632; Stop</button></div></div></div>
<div class="card"><div class="tabs"><button id="t-track" class="on">Event tracks</button><button id="t-progression">Progression</button><button id="t-drift">Drift</button><button id="t-yeti">Yeti</button></div>
<div id="p-track" class="panel on" style="margin-top:14px"><div class="row" style="grid-template-columns:2fr 1fr"><div><label for="track">Track (Beasts V3 change_track)</label><select id="track"></select></div><div><label for="variation">Variation</label><select id="variation"><option value="0">Original (free)</option><option value="1">Variation 1 (1 $SKULL)</option><option value="2">Variation 2 (1 $SKULL)</option><option value="3">Variation 3 (1 $SKULL)</option></select></div></div>
<p class="note">Origin: the Beast with no history. Each kill or defeat in its Death Mountain record makes a track: kills get the inverted development and rising episodes, defeats a tighter stretto, falling episodes and softer notes; the event's seed makes the rest of the choices. Beasts with no events get an example kill and defeat.</p></div>
<div id="p-progression" class="panel" style="margin-top:14px"><label for="level">Unlocked layers: <b id="levelv">0</b> of 5</label><input type="range" id="level" min="0" max="5" value="0">
<div class="ctl" style="margin-top:6px"><button id="reroll" class="stop">Another unlock order</button></div>
<p class="note">Level 0 is the Beast's own scale in its type's feel. Each $SKULL unlock reveals a layer (the theme first, then the rest in an order fixed per Beast; onchain, the unlock transaction's block hash).</p></div>
<div id="p-drift" class="panel" style="margin-top:14px"><label for="day">Day (epoch): <b id="dayv">0</b></label><input type="range" id="day" min="0" max="30" value="0">
<p class="note">A never-ending track: each epoch (a day of blocks, seeded by the epoch's first block hash, readable once 10 blocks old) turns at most one small knob; most days it plays as written.</p></div>
<div id="p-yeti" class="panel" style="margin-top:14px"><div class="chk">
<label><input type="checkbox" id="y-rock" checked><span>Rock groove<small>175 BPM, kick 1 and 3, snare backbeat, crash and tom fill each section</small></span></label>
<label><input type="checkbox" id="y-yodel"><span>Yodel<small>the lead leaps an octave on every other note</small></span></label>
<label><input type="checkbox" id="y-avalanche" checked><span>Avalanche<small>a two-octave sixteenth run down to end each section</small></span></label>
<label><input type="checkbox" id="y-stomp"><span>Stomp<small>three-quarter speed, kick every beat, bass an octave down (instead of rock)</small></span></label>
</div><p class="note">Ideas for a Yeti special (species 68); picking this tab selects a Yeti.</p></div></div>
<div class="card"><pre id="info"></pre></div>
</main>
<script>${NOTICE}\n${inline(tiny)}</script>
<script>${inline(composer)}</script>
<script>
const TIMBRES = ${JSON.stringify(timbres)}, WAVES = ${JSON.stringify(waves)}, NAMES = ${JSON.stringify(PRESET_NAMES)};
const BEASTS = ${JSON.stringify(BEASTS)};
const L = BS.lab, $ = (id) => document.getElementById(id);
const TYPES = ['Magic', 'Hunter', 'Brute'];
let mode = 'track', synth = null, playing = false, reroll = 0;
BEASTS.forEach((x, i) => $('beast').add(new Option(x.name + '  (tier ' + x.beast.tier + (x.beast.id === 68 ? ', YETI' : '') + ')', i)));
const day = (ts) => ts ? new Date(ts * 1000).toISOString().slice(0, 10) : 'undated';
function showArt() { $('art').src = BEASTS[+$('beast').value].art; $('art').alt = BEASTS[+$('beast').value].name; }
function fillTracks() {
  showArt();
  const x = BEASTS[+$('beast').value], ev = (x.events && x.events.events) || [];
  $('track').innerHTML = '';
  $('track').add(new Option('Origin (always available)', 'o'));
  ev.forEach((e, i) => $('track').add(new Option((e.kind === 1 ? 'Kill #' + (e.index + 1) : 'Defeat #' + (e.index + 1)) + ' \u00b7 ' + day(e.timestamp) + (e.adventurer_id !== '0' ? ' \u00b7 adventurer ' + e.adventurer_id : ''), String(i))));
  if (!ev.length) { $('track').add(new Option('Example kill (no events yet)', 'xk')); $('track').add(new Option('Example defeat (no events yet)', 'xd')); }
}
function programsOf(u8) {
  const out = {}; let p = 14; const n = (u8[10] << 8) | u8[11];
  for (let k = 0; k < n; k++) { const len = (u8[p + 4] << 24) | (u8[p + 5] << 16) | (u8[p + 6] << 8) | u8[p + 7];
    for (let i = p + 9; i < p + 8 + len - 1; i++) if (u8[i - 1] === 0 && (u8[i] & 0xf0) === 0xc0) { out[u8[i] & 15] = u8[i + 1]; break; }
    p += 8 + len; }
  return out;
}
function make() {
  const x = BEASTS[+$('beast').value], b = x.beast;
  let args = {}, head = '';
  if (mode === 'track') {
    const v = $('track').value, ev = (x.events && x.events.events) || [], variation = +$('variation').value;
    let track, event = null;
    if (v === 'o') track = { kind: 0, index: 0, variation: 0 };
    else if (v === 'xk' || v === 'xd') { const kind = v === 'xk' ? 1 : 2; track = { kind, index: 0, variation }; event = { kind, index: 0, timestamp: 0, adventurer_id: '0', seed: '0' }; }
    else { event = ev[+v]; track = { kind: event.kind, index: event.index, variation }; }
    args = { track, event };
    head = 'track_id 0x' + L.encodeTrack(track).toString(16) + (track.kind ? ' \u00b7 ' + (track.kind === 1 ? 'kill' : 'defeat') + ' #' + (track.index + 1) + ', variation ' + track.variation + (event && (event.seed !== '0' || event.adventurer_id !== '0') ? ' \u00b7 seeded from the record' : ' \u00b7 seeded from the Beast, index and time (record has no detail)') : ' \u00b7 origin');
  } else if (mode === 'progression') {
    const seed = L.H('UNLOCK', L.entityHash(b), reroll), lvl = +$('level').value;
    args = { unlocked: lvl, seed };
    const order = L.unlockOrder(seed);
    head = 'unlock order: ' + order.map((n, i) => (i < lvl ? n.toUpperCase() : n)).join(' > ') + (lvl === 0 ? ' \u00b7 now: the scale' : '');
  } else if (mode === 'drift') {
    args = { epoch: +$('day').value };
    head = 'day ' + args.epoch + ': ' + L.drift(b, args.epoch).label;
  } else {
    args = { ideas: { rock: $('y-rock').checked && !$('y-stomp').checked, yodel: $('y-yodel').checked, avalanche: $('y-avalanche').checked, stomp: $('y-stomp').checked } };
    head = 'Yeti ideas: ' + Object.entries(args.ideas).filter(([, on]) => on).map(([k]) => k).join(' + ') + (b.id !== 68 ? ' (on a non-Yeti)' : '');
  }
  const out = L.labMidi(mode, b, x.live, args, BS.engine, BS.v11), midi = out.midi;
  const pg = programsOf(midi);
  const ch = Object.entries(pg).map(([c, p]) => 'ch' + (+c + 1) + ' ' + p + ' ' + (NAMES[p] || '')).join(' \u00b7 ');
  $('info').textContent = head + '\\n' + TYPES[b.beast_type] + ' \u00b7 ' + midi.length + ' bytes MIDI\\n' + ch;
  return midi;
}
function ensure() {
  if (synth) return synth;
  synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  synth.setQuality(1); synth.setMasterVol(${settings.master_vol} / 100); synth.setVoices(64); synth.setReverbLev(${settings.reverb} / 100);
  WAVES.forEach((s, i) => synth.setSampleWave('nS' + i, s));
  for (const [drum, slot, ops] of TIMBRES) synth.setTimbre(drum, slot, ops.map((o) => ({ ...o })));
  return synth;
}
function start() {
  const s = ensure(), midi = make();
  s.getAudioContext().resume(); s.stopMIDI();
  s.loadMIDI(midi.buffer.slice(midi.byteOffset, midi.byteOffset + midi.length));
  s.setLoop(1); s.setLoopEnd(s.getPlayStatus().maxTick); s.playMIDI(); playing = true;
}
function refresh() { if (playing) start(); else make(); }
function tab(m) {
  mode = m; for (const t of ['track', 'progression', 'drift', 'yeti']) { $('t-' + t).classList.toggle('on', t === m); $('p-' + t).classList.toggle('on', t === m); }
  if (m === 'yeti' && BEASTS[+$('beast').value].beast.id !== 68) { const i = BEASTS.findIndex((x) => x.beast.id === 68); if (i >= 0) { $('beast').value = i; fillTracks(); } }
  refresh();
}
for (const t of ['track', 'progression', 'drift', 'yeti']) $('t-' + t).onclick = () => tab(t);
$('play').onclick = start;
$('stop').onclick = () => { if (synth) synth.stopMIDI(); playing = false; };
$('beast').onchange = () => { fillTracks(); refresh(); };
$('level').oninput = () => { $('levelv').textContent = $('level').value; refresh(); };
$('day').oninput = () => { $('dayv').textContent = $('day').value; refresh(); };
$('reroll').onclick = () => { reroll++; refresh(); };
for (const id of ['track', 'variation', 'y-rock', 'y-yodel', 'y-avalanche', 'y-stomp']) $(id).onchange = refresh;
fillTracks(); make();
</script></body></html>`;
writeFileSync(here + '../public/onchain/lab.html', html);
console.log('public/onchain/lab.html', html.length, 'bytes');

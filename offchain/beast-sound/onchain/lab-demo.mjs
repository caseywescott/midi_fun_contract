// Build public/onchain/lab.html: the Beast Sound lab on composer v1.1 and the self-contained MIDI, through
// onchain-midi-player's pinned engine with all 20 TinyChip timbres. Pick a Beast (one of the 75 species);
// the Tracks tab samples its tracks by special name (0 = the Genesis Track, 1-1242 the prefix/suffix
// pairs) and seed (a block hash); the other tabs are the never-ending drift
// and Yeti specials (src/lab.js).
// Every card is shown animated and tempo-synced (onchain/lab-sprites.mjs: the species GIF as a PNG sprite
// sheet stepped on the beat, the card's loops on whole beats, restarted at each pass as heard).
//   node onchain/lab-demo.mjs <onchain-midi-player>/tests/vendor/webaudio-tinysynth-<ref>.min.js
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { beastSynthSettings } from './tinychip/synth_settings.mjs';
import { ESSENTIALS, loadBank } from './tinychip/essentials.mjs';
import { beastName } from '../src/index.js';
import { spriteSheet } from './lab-sprites.mjs';

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
// The 75 species as genesis Beasts (tier and type follow from the id); the card is the Warlock's genesis
// card with the name, tier, type and power filled in, and the species' sprite in place of its art.
const BEASTS = Array.from({ length: 75 }, (_, k) => {
  const id = k + 1, beast = { id, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 0, animated: 0, tier: Math.floor((k % 25) / 5) + 1, beast_type: Math.floor(k / 25) };
  return { name: beastName(beast), beast, live: { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1 } };
});
const CARD = Buffer.from(fx.svg_b64, 'base64').toString();
const PREFIXES = Array.from({ length: 69 }, (_, k) => beastName({ id: 1, prefix: k + 1, suffix: 1 }).split(' ').slice(0, -2).join(' '));
const SUFFIXES = Array.from({ length: 18 }, (_, k) => beastName({ id: 1, prefix: 1, suffix: k + 1 }).split(' ').slice(-2, -1)[0]);
const SPRITES = Object.fromEntries(BEASTS.flatMap((x) => [String(x.beast.id), x.beast.id + 's']).map((k) => { const { n, w, png } = spriteSheet(k); return [k, { n, w, png }]; }));

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
#roll{width:100%;height:220px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card))}.legend{display:flex;flex-wrap:wrap;gap:6px 14px;margin-top:10px;font-size:13px}.legend span{display:inline-flex;align-items:center;gap:6px}.legend i{width:12px;height:12px;border-radius:3px;display:inline-block}#info{font:12px/1.6 ui-monospace,monospace;color:var(--mut);white-space:pre-wrap;margin:0}
button:disabled{opacity:.45;cursor:default}button.mini{padding:6px 10px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font:600 13px system-ui;cursor:pointer}.offer{margin:12px 0 8px;padding:10px 12px;border:1px solid var(--line,#ddd);border-radius:10px;font-size:14px;line-height:1.45}.offer b{font-size:15px}.tabs{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}input[type=text],input[type=number]{width:100%;padding:8px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font:13px ui-monospace,monospace}.tabs button{padding:10px 6px;border-radius:10px;border:2px solid var(--line);background:var(--bg);color:var(--fg);font:600 14px system-ui;cursor:pointer}.tabs button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 14%,var(--bg))}.panel{display:none}.panel.on{display:block}input[type=range]{width:100%}.note{font-size:13px;color:var(--mut);margin:8px 0 0}.beastcard{display:grid;grid-template-columns:125px 1fr;gap:16px;align-items:center}#art{width:125px;height:175px;border-radius:8px;object-fit:contain;background:#000}@media(max-width:420px){.beastcard{grid-template-columns:96px 1fr}#art{width:96px;height:134px}}\n</style></head><body><main>
<h1>Beast Sound Lab</h1>
<p class="sub">Composer v1.1 prototypes, played as onchain-midi-player plays a token_uri (the self-contained MIDI, the class's engine, the TinyChip timbres). Pick a Beast, sample its tracks by name and seed, then play; changes apply while playing.</p>
<div class="card beastcard"><img id="art" alt="" width="125" height="175"><div><label for="beast">Beast</label><select id="beast"></select>
<label style="margin-top:8px;display:flex;gap:8px;align-items:center;color:var(--fg)"><input type="checkbox" id="shiny"> Shiny (mega sound on top)</label>
<div class="ctl"><button id="play">&#9654; Play</button><button id="stop" class="stop">&#9632; Stop</button></div>
<label for="speed" style="margin-top:12px">Art speed (one sprite frame per)</label><select id="speed"><option value="auto" selected>Auto: eighth note, quarter above 150 BPM</option><option value="0.5">Eighth note</option><option value="1">Quarter note</option><option value="2">Half note</option></select>
<p class="note" id="artinfo"></p></div></div>
<div class="card"><div class="tabs"><button id="t-tracks" class="on">Tracks</button><button id="t-drift">Drift</button><button id="t-yeti">Yeti</button></div>
<div id="p-tracks" class="panel on" style="margin-top:14px">
<label for="name">Special name: <b id="namev">Genesis Track</b></label>
<div class="row" style="grid-template-columns:1fr 96px;align-items:center"><input type="range" id="name" min="0" max="1242" value="0"><input type="number" id="namen" min="0" max="1242" value="0"></div>
<label style="margin-top:12px;display:flex;gap:8px;align-items:center;color:var(--fg)"><input type="checkbox" id="drift-on"> Drift on top: day <b id="tdayv">1</b></label><label style="margin-top:4px;display:flex;gap:8px;align-items:center;color:var(--fg)"><input type="checkbox" id="fl-on"> Flourishes grow with age: trills, mordents, turns, suspensions, passing notes and anticipations in 16ths across the voices, 0% on day 1 rising toward 8% of the theme’s notes and 4% of the others’, one per beat</label>
<input type="range" id="tday" min="1" max="1242" value="1" disabled>
<select id="dv" style="margin-top:6px"><option value="v2" selected>Layered drift: monthly rhythm, weekly channel rotation, a daily key-plan, episode or tempo change</option><option value="v1">One-knob drift (v1: one small change a day)</option></select>
<label for="seed" style="margin-top:10px">Seed (a block hash; 0 = the Genesis seed)</label><input type="text" id="seed" spellcheck="false" value="0" placeholder="0">
<div class="ctl"><button id="newseed" class="stop">New hash</button><button id="noseed" class="stop">Seed 0 (Genesis)</button><button id="sample">Random sample</button></div>
<div class="row" style="grid-template-columns:1fr 1fr;margin-top:12px"><div><label for="theme">Motif</label><select id="theme"><option value="species" selected>Species motif in every track</option><option value="name">Each name re-seeds the motif (v1.1 today)</option></select></div>
<div><label for="gkey">Genesis key</label><select id="gkey"><option value="rule" selected>v1.1 rule: Phrygian, tonic = id mod 12</option><option value="spread">Spread: a canonical name's key per species</option><option value="proposed">Proposed: spread key + suggested tempo</option></select></div></div>
<label for="bpm" style="margin-top:12px">Tempo: <b id="bpmv">auto</b></label>
<div class="row" style="grid-template-columns:1fr auto auto auto;align-items:center;gap:8px"><input type="range" id="bpm" min="60" max="200" step="1" value="120"><button id="bpm-down" class="mini">−4</button><button id="bpm-up" class="mini">+4</button><button id="bpm-auto" class="mini">Auto</button></div>
<label for="mix" style="margin-top:12px">Mix</label><select id="mix"><option value="balanced" selected>Balanced: leads down, plucks up, panning halved (prototype)</option><option value="">v1.1 (what get_midi plays today)</option></select>
<label style="margin-top:12px;display:flex;gap:8px;align-items:center;color:var(--fg)"><input type="checkbox" id="toplead" checked> Topline never a pluck: the highest voice takes the family's free lead (v1.1 can give it a pluck)</label>
<label for="ties" style="margin-top:12px">Repeated notes in the inner voices (3 or more voices; never the bass, topline or theme)</label><select id="ties"><option value="weak" selected>Tie off the strong beats (re-strike on 1 and 3)</option><option value="all">Tie every repeat (up to a bar)</option><option value="">Strike every repeat (v1.1)</option></select>
<label for="chan" style="margin-top:12px">Channels</label><select id="chan"><option value="rarity" selected>Rarity: the seed picks 3–6 (6 is 1 in 25); Genesis by tier</option><option value="tier">By tier (v1.1: 4/4/3/2/2 voices)</option><option value="3">Force 3</option><option value="4">Force 4</option><option value="5">Force 5</option><option value="6">Force 6 (rare)</option></select>
<p class="note">Name 0 is the species' Genesis Track, the base every Beast of the species starts with. Names 1–1242 are the 69 × 18 prefix/suffix pairs: the prefix sets the key, mode and register, the suffix the ornament style. The seed (in the auction, the block hash of the previous purchase) sets the development, episode direction, sections, spacing, which side the theme sits and the rhythm, and how many of the six channels play (four canon voices, countersubject, drums; same presets): most tracks 3–5, 1 in 25 all 6. The theme and the lowest voice always play. Every Beast of a species shares the notes; shiny only adds the mega sound. The address bar keeps the current sample, so a link plays it again.</p></div>
<div id="p-drift" class="panel" style="margin-top:14px"><label for="day">Day (epoch): <b id="dayv">1</b></label><input type="range" id="day" min="1" max="1242" value="1">
<p class="note">This tab plays the plain v1.1 Beast, not the Tracks sample: Genesis traits with no history (one section; the tier's voices and countersubject; v1.1's genesis key; shiny adds its tempo bump and the mega sound). For drift on a sampled track, use "Drift on top" in Tracks. A never-ending track: each epoch (a day of blocks, seeded by the epoch's first block hash, readable once 10 blocks old) turns at most one small knob; most days it plays as written.</p></div>
<div id="p-yeti" class="panel" style="margin-top:14px"><div class="chk">
<label><input type="checkbox" id="y-rock" checked><span>Rock groove<small>175 BPM, kick 1 and 3, snare backbeat, crash and tom fill each section</small></span></label>
<label><input type="checkbox" id="y-yodel"><span>Yodel<small>the lead leaps an octave on every other note</small></span></label>
<label><input type="checkbox" id="y-avalanche" checked><span>Avalanche<small>a two-octave sixteenth arpeggio down through the closing chord to end each section</small></span></label>
<label><input type="checkbox" id="y-stomp"><span>Stomp<small>three-quarter speed, kick every beat, bass an octave down (instead of rock)</small></span></label>
</div><p class="note">Ideas for a Yeti special (species 68); picking this tab selects a Yeti.</p></div></div>
<div class="card"><canvas id="roll" width="1600" height="440"></canvas><div id="legend" class="legend"></div><p class="note" id="clock"></p></div>
<div class="card"><pre id="info"></pre></div>
</main>
<script>${NOTICE}\n${inline(tiny)}</script>
<script>${inline(composer)}</script>
<script>
const TIMBRES = ${JSON.stringify(timbres)}, WAVES = ${JSON.stringify(waves)}, NAMES = ${JSON.stringify(PRESET_NAMES)};
const BEASTS = ${JSON.stringify(BEASTS)};
const SPRITES = ${JSON.stringify(SPRITES)};
const L = BS.lab, $ = (id) => document.getElementById(id);
const TYPES = ['Magic', 'Hunter', 'Brute'];
let mode = 'tracks', synth = null, playing = false;
// a day count as an age since launch: day 365 is a year in
const age = (d) => { const y = Math.floor(d / 365), m = Math.floor((d % 365) / 30.42); return d + ' (' + (y ? y + ' yr ' : '') + m + ' mo)'; };
const CARD = ${JSON.stringify(CARD)}, PREFIXES = ${JSON.stringify(PREFIXES)}, SUFFIXES = ${JSON.stringify(SUFFIXES)};
let bpmSet = null; // null = the track's own tempo
const randHash = () => { const a = new Uint8Array(31); crypto.getRandomValues(a); return '0x' + [...a].map((x) => x.toString(16).padStart(2, '0')).join(''); };
const curBeast = () => ({ ...BEASTS[+$('beast').value].beast, shiny: $('shiny').checked ? 1 : 0 });
const spKey = () => curBeast().id + (curBeast().shiny ? 's' : '');
const nameText = (n) => { if (!n) return ''; const f = L.nameFromVariant(n); return PREFIXES[f.prefix - 1] + ' ' + SUFFIXES[f.suffix - 1]; };
const trackName = () => { const n = +$('name').value; return (n ? nameText(n) + ' ' : '') + BEASTS[+$('beast').value].name; };
const seedOf = () => { const v = $('seed').value.trim(); if (!v) return null; try { const x = BigInt(/^0x/i.test(v) || /[a-f]/i.test(v) ? (v.startsWith('0x') ? v : '0x' + v) : v); return x === 0n ? null : x; } catch { return null; } }; // 0 = the Genesis seed
const devName = (t) => t.development + ', episodes ' + (t.direction > 0 ? 'rising' : t.direction < 0 ? 'falling' : 'alternating') + ', ' + t.sections + ' sections, ' + t.spacing + ' spacing' + (t.trill ? ', trills' : '');
function saveHash() {
  // every tab's state, so a link plays what is heard (the Tracks fields stay, the other tabs add theirs)
  const q = { b: curBeast().id, n: $('name').value, s: $('seed').value.trim(), shiny: $('shiny').checked ? 1 : 0, theme: $('theme').value, gkey: $('gkey').value, ch: $('chan').value, mix: $('mix').value || 'v11', tie: $('ties').value || 'off', top: $('toplead').checked ? 1 : 0, ...(bpmSet ? { bpm: bpmSet } : {}) };
  if ($('drift-on').checked || $('fl-on').checked) q.tday = $('tday').value;
  if ($('drift-on').checked) q.dv = $('dv').value;
  if ($('fl-on').checked) q.fl = 1;
  if (mode !== 'tracks') q.tab = mode;
  if (mode === 'drift') q.day = $('day').value;
  if (mode === 'yeti') q.yeti = ['y-rock', 'y-yodel', 'y-avalanche', 'y-stomp'].filter((id) => $(id).checked).map((id) => id.slice(2)).join('.');
  try { history.replaceState(null, '', '#' + new URLSearchParams(q).toString()); } catch {}
}
function loadHash() {
  const q = new URLSearchParams(location.hash.slice(1));
  if (q.get('b')) $('beast').value = String(Math.min(75, Math.max(1, +q.get('b') || 1)) - 1);
  if (q.get('n')) $('name').value = $('namen').value = String(Math.min(1242, Math.max(0, +q.get('n') || 0)));
  if (q.has('s')) $('seed').value = q.get('s') || '0';
  $('shiny').checked = q.get('shiny') === '1';
  if (q.get('theme')) $('theme').value = q.get('theme');
  if (q.get('gkey')) $('gkey').value = q.get('gkey');
  if (q.get('ch')) $('chan').value = q.get('ch');
  if (+q.get('bpm')) bpmSet = Math.min(200, Math.max(60, +q.get('bpm')));
  if (q.get('fl') === '1') $('fl-on').checked = true;
  if (q.has('tday')) { $('drift-on').checked = q.has('dv') || !q.has('fl'); $('tday').disabled = false; $('tday').value = q.get('tday'); $('tdayv').textContent = age(+$('tday').value); }
  if (q.get('dv')) $('dv').value = q.get('dv');
  if (q.has('top')) $('toplead').checked = q.get('top') === '1';
  if (q.get('tie')) $('ties').value = q.get('tie') === 'off' ? '' : q.get('tie');
  if (q.get('mix')) $('mix').value = q.get('mix') === 'v11' ? '' : q.get('mix');
  if (q.has('day')) { $('day').value = q.get('day'); $('dayv').textContent = age(+$('day').value); }
  if (q.has('yeti')) { const on = q.get('yeti').split('.'); for (const k of ['rock', 'yodel', 'avalanche', 'stomp']) $('y-' + k).checked = on.includes(k); }
  return ['drift', 'yeti'].includes(q.get('tab')) ? q.get('tab') : 'tracks';
}
function showName() { const n = +$('name').value; $('namev').textContent = n ? '#' + n + ' ' + nameText(n) : 'Genesis Track'; }
BEASTS.forEach((x, i) => $('beast').add(new Option(x.beast.id + '. ' + x.name + '  (tier ' + x.beast.tier + ' ' + TYPES[x.beast.beast_type] + ')', i)));
// ── Tempo-synced art (loothero's "BPM animation sync", as in Provable-Games/beast-sound-check) ──
// Every Beast is shown animated: the card's art element is replaced by its species GIF as a PNG
// sprite sheet in a nested <svg> viewport, stepped by a discrete SMIL <animate> whose frame is a
// note value (by default an eighth, a quarter above 150 BPM). The card's own SMIL loops run on
// whole beats (keep-alive 4, shiny rim rotation 16, logo pulse 8). Like the onchain player, the art
// restarts (a fresh blob URL, so a new animation timeline) when tick 0 of each pass is heard.
let tempo = { bpm: 120, tpq: 480, tempos: 0, pass: 0 }, artRun = 0, artShown = 0;
const svgText = {};
function tempoOf(u8) { // the MIDI's tempo meta (FF 51 03, microseconds per quarter) and ticks per quarter
  let uspq = 500000, n = 0;
  for (let i = 14; i + 5 < u8.length; i++) if (u8[i] === 0xff && u8[i + 1] === 0x51 && u8[i + 2] === 3) { if (!n++) uspq = (u8[i + 3] << 16) | (u8[i + 4] << 8) | u8[i + 5]; i += 5; }
  return { bpm: 60e6 / uspq, tpq: (u8[12] << 8) | u8[13], tempos: n, pass: 0 };
}
function cardSvg() { // the genesis card with this Beast's name, tier, type and power (level 1)
  const b = curBeast(), name = trackName(), size = name.length > 22 ? 16 : name.length > 16 ? 20 : name.length > 11 ? 26 : 34;
  return CARD.replace(/>Warlock<\\/text>/, '>' + name + '</text>').replace("font-size:34px", 'font-size:' + size + 'px')
    .replace(/(>TIER<\\/text><text[^>]*>)1</, '$1' + b.tier + '<').replace(/>Magic</, '>' + TYPES[b.beast_type] + '<')
    .replace(/(>POWER<\\/text><text[^>]*>)5</, '$1' + (6 - b.tier) + '<');
}
const CARD_BEATS = { '2.2s': 4, '6s': 16, '3s': 8 }; // the card's loops, as in beast-sound-check's "Card synced"
const secs = (v) => String(+v.toFixed(6)) + 's';
function beatsPerFrame(bpm) { const v = $('speed').value; return v === 'auto' ? (bpm > 150 ? 1 : 0.5) : +v; }
function artTiming(i) {
  const sp = SPRITES[spKey()], beat = 60 / tempo.bpm, bpf = beatsPerFrame(tempo.bpm);
  return { key: spKey(), frames: sp.n, bpm: +tempo.bpm.toFixed(2), beatsPerFrame: bpf, frameMs: +(beat * bpf * 1000).toFixed(1), dur: secs(sp.n * beat * bpf), beat };
}
// The synced SVG. phase (seconds into the pass) starts every loop that far in (a negative begin),
// for a change made while playing.
function syncSvg(svg, i, phase) {
  const sp = SPRITES[spKey()], t = artTiming(i), begin = phase > 0 ? " begin='-" + secs(phase) + "'" : '';
  svg = svg.replace(/<(animate|animateTransform)\\b([^>]*?) dur='([^']+)'/g, (m, tag, pre, d) => {
    const beats = CARD_BEATS[d] || Math.max(1, Math.round(parseFloat(d) / t.beat));
    return '<' + tag + pre + " dur='" + secs(beats * t.beat) + "'" + begin;
  });
  const sprite = (x, y, w, h) => "<svg x='" + x + "' y='" + y + "' width='" + w + "' height='" + h + "' viewBox='0 0 " + sp.w + ' ' + sp.w + "'><image x='0' y='0' width='" + sp.n * sp.w + "' height='" + sp.w
    + "' style='image-rendering:pixelated; image-rendering:-moz-crisp-edges; -ms-interpolation-mode:nearest-neighbor;' href='data:image/png;base64," + sp.png + "'><animate attributeName='x' values='"
    + Array.from({ length: sp.n }, (_, k) => k ? -k * sp.w : 0).join(';') + "' dur='" + t.dur + "' calcMode='discrete' repeatCount='indefinite'" + begin + "/></image></svg>";
  const attr = (s, a) => (new RegExp('\\\\b' + a + "='([^']*)'").exec(s) || [])[1];
  const fo = /<foreignObject\\b[^>]*>[\\s\\S]*?<\\/foreignObject>/.exec(svg) || /<image\\b[^>]*href='data:image\\/(?:gif|png)[^']*'[^>]*?(?:\\/>|>\\s*<\\/image>)/.exec(svg);
  if (!fo) throw new Error('no art element in the card SVG');
  const el = fo[0], head = el.slice(0, el.indexOf('>'));
  return svg.slice(0, fo.index) + sprite(attr(head, 'x') || 0, attr(head, 'y') || 0, attr(head, 'width') || 128, attr(head, 'height') || 128) + svg.slice(fo.index + el.length);
}
let artKey = '';
// Shows the art for the current Beast, tempo and speed as a fresh blob URL, swapped in once decoded.
// live: playing, so start the loops at the pass position heard now.
async function renderArt(live, force) {
  const i = +$('beast').value, x = BEASTS[i], t = artTiming(i), key = i + '|' + t.dur + '|' + trackName() + '|' + spKey();
  if (!force && !live && key === artKey) return;
  artKey = key;
  const n = ++artRun;
  let svg = null, phase = 0;
  try { svg = cardSvg(); } catch (e) { console.warn(e); }
  if (n !== artRun) return;
  if (live && synth) { // seconds since tick 0 of the pass being heard
    const ctx = synth.getAudioContext(), st = synth.getPlayStatus().startTime;
    phase = ctx.currentTime - (ctx.outputLatency || 0) - st;
    if (tempo.pass > 0) phase = ((phase % tempo.pass) + tempo.pass) % tempo.pass;
  }
  let url = '';
  try { if (svg) url = URL.createObjectURL(new Blob([syncSvg(svg, i, phase)], { type: 'image/svg+xml' })); }
  catch (e) { console.warn(e); }
  const img = new Image();
  img.id = 'art'; img.alt = trackName(); img.width = 125; img.height = 175;
  img.onload = img.onerror = () => {
    if (n < artShown) { if (url.startsWith('blob:')) URL.revokeObjectURL(url); return; }
    artShown = n;
    const old = $('art');
    old.replaceWith(img);
    if (old.src.startsWith('blob:')) URL.revokeObjectURL(old.src);
  };
  img.src = url;
  const note = { 0.5: 'eighth note', 1: 'quarter note', 2: 'half note' }[t.beatsPerFrame];
  window.LAB_ART = { ...t, synced: url.startsWith('blob:') };
  $('artinfo').textContent = 'Art: species ' + (curBeast().shiny ? curBeast().id + ' shiny' : curBeast().id) + ', ' + t.frames + ' frames, one per ' + note + ' (' + t.frameMs + ' ms) at ' + t.bpm + ' BPM'
    + (tempo.tempos > 1 ? ' (first of ' + tempo.tempos + ' tempos)' : '') + '; loop ' + t.dur + '; card loops 4, 16 and 8 beats.' + (url.startsWith('blob:') ? '' : ' (card art not found; showing it unsynced)');
}
// Restart the art at tick 0 of each pass as heard (getPlayStatus().startTime plus outputLatency),
// polling startTime every 50 ms as onchain-midi-player's player does; a pass start already past is skipped.
let followRun = 0, followTimer = 0, followPoll = 0;
function stopFollowing() { followRun++; clearTimeout(followTimer); clearInterval(followPoll); followTimer = 0; }
function followPasses(s) {
  stopFollowing();
  const current = followRun, ctx = s.getAudioContext();
  let synced;
  const sync = (first) => {
    if (current !== followRun || followTimer) return;
    const latest = s.getPlayStatus().startTime, lag = ctx.outputLatency || 0;
    if (latest === synced) return;
    const delay = latest == null ? 0 : latest - ctx.currentTime + lag;
    synced = latest;
    if (!first && (latest == null || delay < 0)) return;
    followTimer = setTimeout(() => {
      followTimer = 0;
      if (current !== followRun) return;
      if (first || ctx.currentTime - latest - lag < 0.05) renderArt(false, true);
      sync();
    }, Math.max(0, delay * 1000));
  };
  sync(true);
  followPoll = setInterval(() => sync(), 50);
}
function programsOf(u8) {
  const out = {}; let p = 14; const n = (u8[10] << 8) | u8[11];
  for (let k = 0; k < n; k++) { const len = (u8[p + 4] << 24) | (u8[p + 5] << 16) | (u8[p + 6] << 8) | u8[p + 7];
    for (let i = p + 9; i < p + 8 + len - 1; i++) if (u8[i - 1] === 0 && (u8[i] & 0xf0) === 0xc0) { out[u8[i] & 15] = u8[i + 1]; break; }
    p += 8 + len; }
  return out;
}
// ── piano roll: the self-contained MIDI as played (notes by channel, drums on the bottom strip),
// bar lines with bar numbers and seconds on top, and a playhead that follows the synth ──
const ROLL_COLORS = ['#7a3cff', '#e0a800', '#1fb6a6', '#ff5c8a', '#4a90e2', '#f07b2a', '#8bc34a', '#c06bd6'];
let rollData = null;
function notesOf(u8) { // SMF notes [start, length, pitch, velocity, channel] in ticks
  const tpq = (u8[12] << 8) | u8[13], n = (u8[10] << 8) | u8[11], out = [];
  let p = 14, len = 0;
  const vlq = (st) => { let v = 0, b; do { b = u8[st.i++]; v = (v << 7) | (b & 127); } while (b & 128); return v; };
  for (let k = 0; k < n; k++) {
    const L = (u8[p + 4] << 24) | (u8[p + 5] << 16) | (u8[p + 6] << 8) | u8[p + 7], st = { i: p + 8 }, end = p + 8 + L, on = {};
    let t = 0, rs = 0;
    while (st.i < end) {
      t += vlq(st);
      let s0 = u8[st.i];
      if (s0 & 128) { st.i++; if (s0 < 0xf0) rs = s0; } else s0 = rs;
      if (s0 === 0xff) { st.i++; st.i += vlq(st); continue; }
      if (s0 === 0xf0 || s0 === 0xf7) { st.i += vlq(st); continue; }
      const hi = s0 & 0xf0, ch = s0 & 15, a = u8[st.i++], c = hi === 0xc0 || hi === 0xd0 ? 0 : u8[st.i++];
      if (hi === 0x90 && c > 0) (on[ch * 128 + a] ||= []).push([t, c]);
      else if (hi === 0x80 || hi === 0x90) { const q = on[ch * 128 + a]; if (q && q.length) { const [t0, v] = q.shift(); out.push([t0, Math.max(1, t - t0), a, v, ch]); } }
    }
    for (const [key, q] of Object.entries(on)) for (const [t0, v] of q) out.push([t0, tpq / 8, key % 128, v, Math.floor(key / 128)]); // hits with no note-off (drums)
    len = Math.max(len, t); p = end;
  }
  return { tpq, notes: out, len };
}
function drawRoll(tick) {
  const c = $('roll'), ctx = c.getContext('2d'), W = c.width, H = c.height, d = rollData;
  ctx.clearRect(0, 0, W, H);
  if (!d || !d.notes.length) return;
  const fg = getComputedStyle(document.body).color, top = 58, drumKeys = [...new Set(d.notes.filter((x) => x[4] === 9).map((x) => x[2]))].sort((a, b) => b - a), drumH = drumKeys.length ? Math.min(90, 14 * drumKeys.length + 8) : 0, mH = H - top - drumH - 6;
  const pitched = d.notes.filter((x) => x[4] !== 9), lo = Math.min(...pitched.map((x) => x[2])) - 1, hi = Math.max(...pitched.map((x) => x[2])) + 1;
  const X = (t) => t / d.len * W, bar = d.tpq * 4, secPerTick = 60 / tempo.bpm / d.tpq;
  ctx.font = '20px system-ui'; ctx.textBaseline = 'top';
  const bars = Math.ceil(d.len / bar), every = bars > 48 ? 4 : bars > 24 ? 2 : 1;
  for (let b = 0; b <= bars; b++) {
    const x = X(b * bar);
    ctx.globalAlpha = b % 4 === 0 ? 0.28 : 0.12; ctx.fillStyle = fg; ctx.fillRect(x, top - 6, 1.5, H - top + 6);
    if (b < bars && b % every === 0) { ctx.globalAlpha = 0.75; ctx.fillText(String(b + 1), x + 4, 2); }
  }
  // seconds along the top, right of the bar numbers' row
  ctx.globalAlpha = 0.5; ctx.textAlign = 'right'; ctx.font = '18px system-ui';
  const total = d.len * secPerTick, step = total > 60 ? 10 : 5;
  for (let sct = step; sct < total; sct += step) { const x = X(sct / secPerTick); ctx.fillRect(x, top - 10, 1, 6); ctx.fillText(sct + 's', x - 3, 28); }
  ctx.textAlign = 'left';
  for (const [t, dur, pitch, vel, ch] of d.notes) {
    ctx.fillStyle = ch === 9 ? fg : ROLL_COLORS[ch % ROLL_COLORS.length];
    ctx.globalAlpha = (ch === 9 ? 0.25 : 0.35) + 0.6 * (vel / 127);
    if (ch === 9) { const rh = (drumH - 8) / drumKeys.length; ctx.fillRect(X(t), H - drumH + 4 + drumKeys.indexOf(pitch) * rh, 5, Math.max(3, rh - 2)); continue; }
    const rowH = mH / (hi - lo + 1), y = top + (hi - pitch) * rowH, w = Math.max(3, X(dur) - 1.5), h = Math.max(3, rowH - 1);
    if (d.marks && d.marks.has(ch + ':' + t + ':' + pitch)) { ctx.globalAlpha = 1; ctx.fillStyle = '#ff2d2d'; ctx.fillRect(X(t) - 1, y - 1, Math.max(8, w + 2), h + 2); ctx.strokeStyle = fg; ctx.lineWidth = 2; ctx.strokeRect(X(t) - 4, y - 4, Math.max(8, w + 2) + 6, h + 8); continue; } // a flourish
    ctx.fillRect(X(t), y, w, h);
  }
  ctx.globalAlpha = 1;
  if (tick != null) { ctx.fillStyle = fg; ctx.fillRect(X(tick), 0, 3, H); }
  const fmt = (x) => Math.floor(x / 60) + ':' + String(Math.floor(x % 60)).padStart(2, '0');
  $('clock').textContent = (tick != null ? fmt(tick * secPerTick) + ' / ' : '') + fmt(total) + ' \u00b7 ' + bars + ' bars at ' + Math.round(tempo.bpm) + ' BPM, looping';
}
function setRoll(midi, marks) {
  rollData = notesOf(midi);
  rollData.marks = new Set((marks || []).map((m) => ((m.voice || 0) & 15) + ':' + m.time + ':' + m.pitch));
  const pg = programsOf(midi), chans = [...new Set(rollData.notes.map((x) => x[4]))].sort((a, b) => a - b);
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + (ch === 9 ? 'var(--mut)' : ROLL_COLORS[ch % ROLL_COLORS.length]) + '"></i>ch' + (ch + 1) + ' ' + (ch === 9 ? 'drums' : (pg[ch] !== undefined ? (NAMES[pg[ch]] || 'program ' + pg[ch]) : '')) + '</span>').join('') + (rollData.marks.size ? '<span><i style="background:#ff2d2d;outline:2px solid var(--fg);outline-offset:1px"></i>flourish (16th)</span>' : '');
  drawRoll(null);
}
(function rollLoop() {
  if (playing && synth && rollData && synth.tick2Time) {
    const t = synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time, loop = synth.loopEnd || synth.maxTick;
    drawRoll(t < 0 ? 0 : t % loop);
  }
  requestAnimationFrame(rollLoop);
})();
function make() {
  const x = BEASTS[+$('beast').value], b = curBeast();
  let args = {}, head = '', out;
  if (mode === 'tracks') {
    const seed = seedOf(), epoch = $('drift-on').checked ? +$('tday').value : null, flourishDay = $('fl-on').checked ? +$('tday').value : null;
    args = { name: +$('name').value, seed, theme: $('theme').value, genesisKey: $('gkey').value, epoch, channels: $('chan').value, bpm: bpmSet, driftMode: $('dv').value, mix: $('mix').value || null, flourishDay, ties: $('ties').value || false, topLead: $('toplead').checked };
    out = L.labMidi('sample', b, x.live, args, BS.engine, BS.v11);
    const f = out.info;
    if (bpmSet === null) $('bpm').value = f.tempo;
    $('bpmv').textContent = f.tempo + ' BPM' + (bpmSet === null ? ' (auto)' : '');
    head = trackName() + (args.name ? '' : ' (Genesis Track)') + ' \u00b7 ' + f.key + ' \u00b7 ' + f.tempo + ' BPM \u00b7 ' + (f.channels ? f.channels.length + ' channels' + (f.channels.length === 6 ? ' (RARE)' : '') + ': ' + f.channels.join(', ') : f.voices + ' voices') + '\\n' + devName(f) + (seed === null ? ' \u00b7 seed 0 (Genesis)' : ' \u00b7 seed 0x' + seed.toString(16).slice(0, 12) + '\u2026') + (f.tied ? ' \u00b7 ' + f.tied + ' repeats tied' : '') + (f.flourishes ? ' \u00b7 ' + f.flourishes.count + ' flourish' + (f.flourishes.count === 1 ? '' : 'es') + (f.flourishes.count ? ' on ' + f.flourishes.voices + ' voice' + (f.flourishes.voices > 1 ? 's' : '') + ': ' + Object.entries(f.flourishes.shapes).map(([k, n]) => n + ' ' + k + (n > 1 ? (k.endsWith('s') ? 'es' : 's') : '')).join(', ') : '') + ' (day ' + flourishDay + ': ' + (100 * f.flourishes.share).toFixed(1) + '% of the theme\u2019s notes, ' + (100 * f.flourishes.share / 2).toFixed(1) + '% of the others\u2019)' : '') + (epoch !== null ? ' \u00b7 drift day ' + epoch + ': ' + out.drift.label : '');
  } else if (mode === 'drift') {
    args = { epoch: +$('day').value };
    head = 'day ' + args.epoch + ': ' + L.drift(b, args.epoch).label;
  } else {
    args = { ideas: { rock: $('y-rock').checked && !$('y-stomp').checked, yodel: $('y-yodel').checked, avalanche: $('y-avalanche').checked, stomp: $('y-stomp').checked } };
    head = 'Yeti ideas: ' + Object.entries(args.ideas).filter(([, on]) => on).map(([k]) => k).join(' + ') + (b.id !== 68 ? ' (on a non-Yeti)' : '');
  }
  if (!out) out = L.labMidi(mode, b, x.live, args, BS.engine, BS.v11);
  saveHash();
  const midi = out.midi;
  tempo = tempoOf(midi);
  setRoll(midi, out.info && out.info.flourishes ? out.info.flourishes.notes : null);
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
  tempo.pass = s.getPlayStatus().maxTick / tempo.tpq * 60 / tempo.bpm;
  followPasses(s);
}
function refresh() { if (playing) start(); else { make(); renderArt(false); } }
function tab(m) {
  mode = m; for (const t of ['tracks', 'drift', 'yeti']) { $('t-' + t).classList.toggle('on', t === m); $('p-' + t).classList.toggle('on', t === m); }
  if (m === 'yeti' && BEASTS[+$('beast').value].beast.id !== 68) { const i = BEASTS.findIndex((x) => x.beast.id === 68); if (i >= 0) $('beast').value = i; }
  refresh();
}
for (const t of ['tracks', 'drift', 'yeti']) $('t-' + t).onclick = () => tab(t);
$('name').oninput = () => { $('namen').value = $('name').value; showName(); refresh(); };
$('namen').onchange = () => { $('name').value = String(Math.min(1242, Math.max(0, Math.round(+$('namen').value) || 0))); $('namen').value = $('name').value; showName(); refresh(); };
$('seed').onchange = refresh;
$('newseed').onclick = () => { $('seed').value = randHash(); refresh(); };
$('noseed').onclick = () => { $('seed').value = '0'; refresh(); };
$('sample').onclick = () => { const a = new Uint32Array(1); crypto.getRandomValues(a); $('name').value = $('namen').value = String(1 + (a[0] % 1242)); $('seed').value = randHash(); showName(); refresh(); };
for (const id of ['theme', 'gkey', 'shiny', 'chan', 'dv', 'mix', 'ties', 'toplead']) $(id).onchange = refresh;
const setBpm = (v) => { bpmSet = v === null ? null : Math.min(200, Math.max(60, Math.round(v))); if (bpmSet !== null) $('bpm').value = bpmSet; refresh(); };
$('bpm').onchange = () => setBpm(+$('bpm').value);
$('bpm').oninput = () => { $('bpmv').textContent = $('bpm').value + ' BPM'; };
$('bpm-down').onclick = () => setBpm(+$('bpm').value - 4);
$('bpm-up').onclick = () => setBpm(+$('bpm').value + 4);
$('bpm-auto').onclick = () => setBpm(null);
$('drift-on').onchange = $('fl-on').onchange = () => { $('tday').disabled = !$('drift-on').checked && !$('fl-on').checked; refresh(); };
$('tday').oninput = () => { $('tdayv').textContent = age(+$('tday').value); refresh(); };
$('play').onclick = start;
$('stop').onclick = () => { if (synth) synth.stopMIDI(); playing = false; stopFollowing(); drawRoll(null); };
$('speed').onchange = () => renderArt(playing);
$('beast').onchange = refresh;
$('day').oninput = () => { $('dayv').textContent = age(+$('day').value); refresh(); };
for (const id of ['y-rock', 'y-yodel', 'y-avalanche', 'y-stomp']) $(id).onchange = refresh;
{ const t = loadHash(); showName(); if (t !== 'tracks') tab(t); else refresh(); }
</script></body></html>`;
writeFileSync(here + '../public/onchain/lab.html', html);
console.log('public/onchain/lab.html', html.length, 'bytes');

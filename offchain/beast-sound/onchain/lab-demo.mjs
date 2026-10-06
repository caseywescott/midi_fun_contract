// Build public/onchain/lab.html: the Beast Sound lab, four listening prototypes (src/lab.js) on composer
// v1.1 and the self-contained MIDI, through onchain-midi-player's pinned engine with all 20 TinyChip
// timbres: event tracks (from each Beast's real Death Mountain records, onchain/.events-cache.json),
// the scale-start progression, the never-ending drift, and Yeti specials.
// Every Beast's card is shown animated and tempo-synced (onchain/lab-sprites.mjs: its species GIF as a PNG
// sprite sheet stepped on the beat, the card's loops on whole beats, restarted at each pass as heard).
//   node onchain/events-cache.mjs && node onchain/lab-demo.mjs <onchain-midi-player>/tests/vendor/webaudio-tinysynth-<ref>.min.js
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { beastSynthSettings } from './tinychip/synth_settings.mjs';
import { ESSENTIALS, loadBank } from './tinychip/essentials.mjs';
import { decodeTokenId } from '../src/index.js';
import { spriteKey, spriteSheet } from './lab-sprites.mjs';

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
  { name: fx.name + ' (demo stats)', art: 'data:image/svg+xml;base64,' + fx.svg_b64, sp: spriteKey(decodeTokenId(BigInt(fx.token_id))), beast: plain(decodeTokenId(BigInt(fx.token_id))), live: { adventurers_killed: 412, scars: 7, summit_held_seconds: 0, rank: 3, species_count: 1243 }, events: events.warlock },
  ...gallery.map((g) => ({ g, ...cache[g.token] })).sort((a, b) => (b.g.voices ?? 0) - (a.g.voices ?? 0) || (b.g.notes ?? 0) - (a.g.notes ?? 0))
    .map(({ g, beast, live }) => ({ name: g.name + ' #' + g.token, art: 'beasts/' + g.token + '.svg', sp: spriteKey(beast), beast: plain(beast), live, events: events[g.token] })),
];
// Every Beast is shown animated: its species GIF (shiny variant for shiny Beasts) as a PNG sprite sheet.
const SPRITES = Object.fromEntries([...new Set(BEASTS.map((x) => x.sp))].sort().map((k) => { const { n, w, png } = spriteSheet(k); return [k, { n, w, png }]; }));

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
button:disabled{opacity:.45;cursor:default}.offer{margin:12px 0 8px;padding:10px 12px;border:1px solid var(--line,#ddd);border-radius:10px;font-size:14px;line-height:1.45}.offer b{font-size:15px}.tabs{display:grid;grid-template-columns:repeat(5,1fr);gap:8px}@media(max-width:520px){.tabs{grid-template-columns:repeat(3,1fr)}}.tabs button{padding:10px 6px;border-radius:10px;border:2px solid var(--line);background:var(--bg);color:var(--fg);font:600 14px system-ui;cursor:pointer}.tabs button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 14%,var(--bg))}.panel{display:none}.panel.on{display:block}input[type=range]{width:100%}.note{font-size:13px;color:var(--mut);margin:8px 0 0}.beastcard{display:grid;grid-template-columns:125px 1fr;gap:16px;align-items:center}#art{width:125px;height:175px;border-radius:8px;object-fit:contain;background:#000}@media(max-width:420px){.beastcard{grid-template-columns:96px 1fr}#art{width:96px;height:134px}}\n</style></head><body><main>
<h1>Beast Sound Lab</h1>
<p class="sub">Five prototypes on composer v1.1, played as onchain-midi-player plays a token_uri (the self-contained MIDI, the class's engine, the TinyChip timbres). Pick a Beast, a tab, then play; changes apply while playing.</p>
<div class="card beastcard"><img id="art" alt="" width="125" height="175"><div><label for="beast">Beast</label><select id="beast"></select>
<div class="ctl"><button id="play">&#9654; Play</button><button id="stop" class="stop">&#9632; Stop</button></div>
<label for="speed" style="margin-top:12px">Art speed (one sprite frame per)</label><select id="speed"><option value="auto" selected>Auto: eighth note, quarter above 150 BPM</option><option value="0.5">Eighth note</option><option value="1">Quarter note</option><option value="2">Half note</option></select>
<p class="note" id="artinfo"></p></div></div>
<div class="card"><div class="tabs"><button id="t-tracks" class="on">Tracks</button><button id="t-track">Event tracks</button><button id="t-progression">Progression</button><button id="t-drift">Drift</button><button id="t-yeti">Yeti</button></div>
<div id="p-tracks" class="panel on" style="margin-top:14px">
<div class="row" style="grid-template-columns:1fr 1fr"><div><label>Track slots</label><b id="slots">0 of 1 used</b></div><div><label>Spent</label><b id="spent">0 $SKULL · 0 $CORPSE</b></div></div>
<div class="offer" id="offer"></div>
<div class="ctl"><button id="preview" class="stop">Preview the offer</button><button id="buy-track">Buy</button></div>
<div class="ctl" style="margin-top:6px"><button id="buy-slot" class="stop">+1 slot (1 $SKULL)</button><button id="discard" class="stop">Discard selected track</button></div>
<label for="owned" style="margin-top:12px">Playing (Beasts V3 select_track)</label><select id="owned"></select>
<label style="margin-top:12px;display:flex;gap:8px;align-items:center;color:var(--fg)"><input type="checkbox" id="drift-on"> Drift on top: day <b id="tdayv">0</b></label><input type="range" id="tday" min="0" max="30" value="0" disabled>
<p class="note">loothero's model: every Beast of a species starts with the same base track (all Warlocks play the same notes; shiny adds the mega sound on top). Each Beast has one new track on offer at a time, sold by a gradual Dutch auction (here 1 second = 1 hour: 100 $CORPSE halving every 12 h, floor 5). Buying needs a free slot ($SKULL adds one). The next offer is forged from the purchase block's hash, readable 10 blocks later, so nobody knows it in advance, but anyone can hear an offer before buying. A bought track keeps the species theme and instruments; its seed picks a key and mode, an ornament style, the development, direction, sections, spacing and rhythm. Prices are placeholders.</p></div>
<div id="p-track" class="panel" style="margin-top:14px"><div class="row" style="grid-template-columns:2fr 1fr"><div><label for="track">Track (Beasts V3 change_track)</label><select id="track"></select></div><div><label for="variation">Variation</label><select id="variation"><option value="0">Original (free)</option><option value="1">Variation 1 (1 $SKULL)</option><option value="2">Variation 2 (1 $SKULL)</option><option value="3">Variation 3 (1 $SKULL)</option></select></div></div>
<p class="note">Origin: the Beast with no history. Each kill or defeat in its Death Mountain record makes a track: kills get the inverted development and rising episodes, defeats a tighter stretto, falling episodes and softer notes; the event's seed makes the rest of the choices. Beasts with no events get an example kill and defeat.</p></div>
<div id="p-progression" class="panel" style="margin-top:14px"><label for="levels">Levels</label><select id="levels"><option value="3" selected>3 levels, loothero's order: THEME &gt; CANON + PALETTE &gt; COUNTERSUBJECT + DRUMS</option><option value="5">5 levels, a random order per Beast</option></select>
<label for="level" style="margin-top:10px">Unlocked: <b id="levelv">0</b> of <b id="levelmax">3</b></label><input type="range" id="level" min="0" max="3" value="0">
<div class="ctl" style="margin-top:6px"><button id="reroll" class="stop" style="display:none">Another unlock order</button></div>
<p class="note">Level 0 is the Beast's own scale in its type's feel. Each $SKULL unlock reveals more: with 3 levels, the theme, then the canon and the full palette, then the countersubject and the drums, the same for every Beast. With 5 levels, one layer at a time in an order fixed per Beast (onchain, the unlock transaction's block hash).</p></div>
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
const SPRITES = ${JSON.stringify(SPRITES)};
const L = BS.lab, $ = (id) => document.getElementById(id);
const TYPES = ['Magic', 'Hunter', 'Brute'];
let mode = 'tracks', synth = null, playing = false, reroll = 0;
const OWN = {}; // per Beast: { capacity, tracks: [{ seed, n }], selected: -1 base | i | 'offer', offer: { n, seed, opened } | null, forging: ms }
let spentSkull = 0, spentCorpse = 0;
const randHash = () => { const a = new Uint8Array(31); crypto.getRandomValues(a); return BigInt('0x' + [...a].map((x) => x.toString(16).padStart(2, '0')).join('')); };
const tokenKey = () => BigInt($('beast').value) + 1n;
const own = () => (OWN[$('beast').value] ||= { capacity: 1, tracks: [], selected: -1, offer: { n: 0, seed: L.offerSeed(tokenKey(), 0, randHash()), opened: Date.now() }, forging: 0 });
const hoursOpen = (o) => (Date.now() - o.offer.opened) / 1000;
const devName = (t) => t.development + ', episodes ' + (t.direction > 0 ? 'rising' : t.direction < 0 ? 'falling' : 'alternating') + ', ' + t.sections + ' sections, ' + t.spacing + ' spacing' + (t.trill ? ', trills' : '');
const KEYS = {}, keyOf = (seed) => (KEYS[$('beast').value + ':' + seed] ??= L.labMidi('species', BEASTS[+$('beast').value].beast, BEASTS[+$('beast').value].live, { seed, epoch: null }, BS.engine, BS.v11).key);
const speciesName = () => BEASTS[+$('beast').value].name.split(/ [#(]/)[0].split(' ').pop();
const describe = (seed) => keyOf(seed) + ' \u00b7 ' + devName(L.speciesTrackTreatment(seed));
function fillOffer() {
  const o = own(), full = o.tracks.length >= o.capacity;
  if (!o.offer) { const left = Math.max(0, Math.ceil((o.forging - Date.now()) / 1000)); $('offer').innerHTML = '<b>Forging the next track\u2026</b><br>waiting for the purchase block to be 10 blocks old (' + left + ' s)'; $('buy-track').disabled = $('preview').disabled = true; $('buy-track').textContent = 'Forging\u2026'; return; }
  const price = L.gdaPrice(hoursOpen(o));
  $('offer').innerHTML = '<b>On offer: track #' + (o.offer.n + 1) + '</b> \u00b7 ' + Math.floor(hoursOpen(o)) + ' h into the auction<br>' + describe(o.offer.seed) + '<br>Price now <b>' + price + ' $CORPSE</b>' + (price <= L.GDA.floor ? ' (floor)' : '');
  $('preview').disabled = false; $('preview').textContent = o.selected === 'offer' ? 'Previewing' : 'Preview the offer';
  $('buy-track').disabled = full; $('buy-track').textContent = full ? 'Slots full: add a slot' : 'Buy for ' + price + ' $CORPSE';
}
function fillOwned() {
  const o = own();
  $('owned').innerHTML = '';
  $('owned').add(new Option('Base track (every ' + speciesName() + ')', '-1'));
  o.tracks.forEach((t, i) => $('owned').add(new Option('Track #' + (t.n + 1) + ': ' + describe(t.seed), String(i))));
  if (o.offer) $('owned').add(new Option('Offer preview: track #' + (o.offer.n + 1), 'offer'));
  $('owned').value = String(o.selected);
  $('slots').textContent = o.tracks.length + ' of ' + o.capacity + ' used';
  $('spent').textContent = spentSkull + ' $SKULL \u00b7 ' + spentCorpse + ' $CORPSE';
  $('discard').disabled = typeof o.selected !== 'number' || o.selected < 0;
  fillOffer();
}
setInterval(() => {
  if (mode !== 'tracks') return;
  const o = own();
  if (!o.offer && Date.now() >= o.forging) { o.offer = { n: o.nextN, seed: L.offerSeed(tokenKey(), o.nextN, o.pendingHash), opened: Date.now() }; fillOwned(); }
  else fillOffer();
}, 1000);

BEASTS.forEach((x, i) => $('beast').add(new Option(x.name + '  (tier ' + x.beast.tier + (x.beast.id === 68 ? ', YETI' : '') + ')', i)));
const day = (ts) => ts ? new Date(ts * 1000).toISOString().slice(0, 10) : 'undated';
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
function cardSvg(i) { // the card SVG text: the Warlock's data URI, or the gallery card fetched once
  const x = BEASTS[i];
  if (!svgText[i]) {
    svgText[i] = x.art.startsWith('data:') ? Promise.resolve(new TextDecoder().decode(Uint8Array.from(atob(x.art.slice(x.art.indexOf(',') + 1)), (c) => c.charCodeAt(0))))
      : fetch(x.art).then((r) => { if (!r.ok) throw new Error(x.art + ': HTTP ' + r.status); return r.text(); });
    svgText[i].catch(() => { delete svgText[i]; });
  }
  return svgText[i];
}
const CARD_BEATS = { '2.2s': 4, '6s': 16, '3s': 8 }; // the card's loops, as in beast-sound-check's "Card synced"
const secs = (v) => String(+v.toFixed(6)) + 's';
function beatsPerFrame(bpm) { const v = $('speed').value; return v === 'auto' ? (bpm > 150 ? 1 : 0.5) : +v; }
function artTiming(i) {
  const sp = SPRITES[BEASTS[i].sp], beat = 60 / tempo.bpm, bpf = beatsPerFrame(tempo.bpm);
  return { key: BEASTS[i].sp, frames: sp.n, bpm: +tempo.bpm.toFixed(2), beatsPerFrame: bpf, frameMs: +(beat * bpf * 1000).toFixed(1), dur: secs(sp.n * beat * bpf), beat };
}
// The synced SVG. phase (seconds into the pass) starts every loop that far in (a negative begin),
// for a change made while playing.
function syncSvg(svg, i, phase) {
  const sp = SPRITES[BEASTS[i].sp], t = artTiming(i), begin = phase > 0 ? " begin='-" + secs(phase) + "'" : '';
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
  const i = +$('beast').value, x = BEASTS[i], t = artTiming(i), key = i + '|' + t.dur;
  if (!force && !live && key === artKey) return;
  artKey = key;
  const n = ++artRun;
  let svg = null, phase = 0;
  try { svg = await cardSvg(i); } catch (e) { console.warn(e); }
  if (n !== artRun) return;
  if (live && synth) { // seconds since tick 0 of the pass being heard
    const ctx = synth.getAudioContext(), st = synth.getPlayStatus().startTime;
    phase = ctx.currentTime - (ctx.outputLatency || 0) - st;
    if (tempo.pass > 0) phase = ((phase % tempo.pass) + tempo.pass) % tempo.pass;
  }
  let url = x.art;
  try { if (svg) url = URL.createObjectURL(new Blob([syncSvg(svg, i, phase)], { type: 'image/svg+xml' })); }
  catch (e) { console.warn(e); }
  const img = new Image();
  img.id = 'art'; img.alt = x.name; img.width = 125; img.height = 175;
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
  $('artinfo').textContent = 'Art: species ' + (x.beast.shiny ? x.beast.id + ' shiny' : x.beast.id) + ', ' + t.frames + ' frames, one per ' + note + ' (' + t.frameMs + ' ms) at ' + t.bpm + ' BPM'
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
function fillTracks() {
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
  if (mode === 'tracks') {
    const o = own(), sel = o.selected, seed = sel === 'offer' ? o.offer.seed : sel >= 0 ? o.tracks[sel].seed : null, epoch = $('drift-on').checked ? +$('tday').value : null;
    args = { seed, epoch };
    head = (seed === null ? 'base track of every ' + speciesName() + ' (species only)' : (sel === 'offer' ? 'previewing the offer, track #' + (o.offer.n + 1) : 'track #' + (o.tracks[sel].n + 1)) + ': ' + describe(seed) + ' \u00b7 seed 0x' + seed.toString(16).slice(0, 12) + '\u2026') + (epoch !== null ? ' \u00b7 drift day ' + epoch + ': ' + L.drift(b, epoch).label : '');
  } else if (mode === 'track') {
    const v = $('track').value, ev = (x.events && x.events.events) || [], variation = +$('variation').value;
    let track, event = null;
    if (v === 'o') track = { kind: 0, index: 0, variation: 0 };
    else if (v === 'xk' || v === 'xd') { const kind = v === 'xk' ? 1 : 2; track = { kind, index: 0, variation }; event = { kind, index: 0, timestamp: 0, adventurer_id: '0', seed: '0' }; }
    else { event = ev[+v]; track = { kind: event.kind, index: event.index, variation }; }
    args = { track, event };
    head = 'track_id 0x' + L.encodeTrack(track).toString(16) + (track.kind ? ' \u00b7 ' + (track.kind === 1 ? 'kill' : 'defeat') + ' #' + (track.index + 1) + ', variation ' + track.variation + (event && (event.seed !== '0' || event.adventurer_id !== '0') ? ' \u00b7 seeded from the record' : ' \u00b7 seeded from the Beast, index and time (record has no detail)') : ' \u00b7 origin');
  } else if (mode === 'progression') {
    const seed = L.H('UNLOCK', L.entityHash(b), reroll), lvl = +$('level').value;
    const three = $('levels').value === '3';
    args = { unlocked: lvl, seed, three };
    if (three) head = 'levels: ' + L.THREE_LEVELS.map((g, i) => (i < lvl ? g.map((n) => n.toUpperCase()) : g).join(' + ')).join(' > ') + (lvl === 0 ? ' \u00b7 now: the scale' : '');
    else { const order = L.unlockOrder(seed); head = 'unlock order: ' + order.map((n, i) => (i < lvl ? n.toUpperCase() : n)).join(' > ') + (lvl === 0 ? ' \u00b7 now: the scale' : ''); }
  } else if (mode === 'drift') {
    args = { epoch: +$('day').value };
    head = 'day ' + args.epoch + ': ' + L.drift(b, args.epoch).label;
  } else {
    args = { ideas: { rock: $('y-rock').checked && !$('y-stomp').checked, yodel: $('y-yodel').checked, avalanche: $('y-avalanche').checked, stomp: $('y-stomp').checked } };
    head = 'Yeti ideas: ' + Object.entries(args.ideas).filter(([, on]) => on).map(([k]) => k).join(' + ') + (b.id !== 68 ? ' (on a non-Yeti)' : '');
  }
  const out = L.labMidi(mode === 'tracks' ? 'species' : mode, b, x.live, args, BS.engine, BS.v11), midi = out.midi;
  tempo = tempoOf(midi);
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
  mode = m; for (const t of ['tracks', 'track', 'progression', 'drift', 'yeti']) { $('t-' + t).classList.toggle('on', t === m); $('p-' + t).classList.toggle('on', t === m); }
  if (m === 'yeti' && BEASTS[+$('beast').value].beast.id !== 68) { const i = BEASTS.findIndex((x) => x.beast.id === 68); if (i >= 0) { $('beast').value = i; fillTracks(); } }
  refresh();
}
for (const t of ['tracks', 'track', 'progression', 'drift', 'yeti']) $('t-' + t).onclick = () => tab(t);
$('buy-slot').onclick = () => { own().capacity++; spentSkull++; fillOwned(); };
$('buy-track').onclick = () => {
  const o = own(); if (!o.offer || o.tracks.length >= o.capacity) return;
  spentCorpse += L.gdaPrice(hoursOpen(o));
  o.tracks.push({ seed: o.offer.seed, n: o.offer.n }); o.selected = o.tracks.length - 1;
  // the next offer comes from this purchase block's hash, readable 10 blocks later (~3 s here)
  o.nextN = o.offer.n + 1; o.pendingHash = randHash(); o.offer = null; o.forging = Date.now() + 3000;
  fillOwned(); refresh();
};
$('preview').onclick = () => { const o = own(); if (!o.offer) return; o.selected = 'offer'; fillOwned(); if (playing) refresh(); else $('play').click(); };
$('discard').onclick = () => { const o = own(); if (typeof o.selected !== 'number' || o.selected < 0) return; o.tracks.splice(o.selected, 1); o.selected = -1; fillOwned(); refresh(); };
$('owned').onchange = () => { const v = $('owned').value; own().selected = v === 'offer' ? 'offer' : +v; fillOwned(); refresh(); };
$('drift-on').onchange = () => { $('tday').disabled = !$('drift-on').checked; refresh(); };
$('tday').oninput = () => { $('tdayv').textContent = $('tday').value; refresh(); };
$('play').onclick = start;
$('stop').onclick = () => { if (synth) synth.stopMIDI(); playing = false; stopFollowing(); };
$('speed').onchange = () => renderArt(playing);
$('beast').onchange = () => { fillTracks(); fillOwned(); refresh(); };
$('level').oninput = () => { $('levelv').textContent = $('level').value; refresh(); };
$('levels').onchange = () => { const max = $('levels').value; $('level').max = max; if (+$('level').value > +max) $('level').value = max; $('levelmax').textContent = max; $('levelv').textContent = $('level').value; $('reroll').style.display = max === '5' ? '' : 'none'; refresh(); };
$('day').oninput = () => { $('dayv').textContent = $('day').value; refresh(); };
$('reroll').onclick = () => { reroll++; refresh(); };
for (const id of ['track', 'variation', 'y-rock', 'y-yodel', 'y-avalanche', 'y-stomp']) $(id).onchange = refresh;
fillTracks(); fillOwned(); refresh();
</script></body></html>`;
writeFileSync(here + '../public/onchain/lab.html', html);
console.log('public/onchain/lab.html', html.length, 'bytes');

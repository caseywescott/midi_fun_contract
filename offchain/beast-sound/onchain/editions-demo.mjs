// Build public/onchain/editions.html: the Monthly Track Editions (src/editions_lite.js, the engine
// BeastMidiProvider.get_edition_midi plays byte for byte; src/editions.js is the larger prototype). Step
// through editions (one per UTC month), Beasts and track seeds; play each through onchain-midi-player's
// pinned engine with the whole TinyChip bank (100 presets); mark each edition Keep / Maybe / Reject.
// Edition 0 is today's seeded canon (src/lab.js genesisMidi with a seed).
//   node onchain/editions-demo.mjs <webaudio-tinysynth-4bf9829.min.js>
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { engine as ENGINE, beastName } from '../src/index.js';
import { createEngineV11 } from '../src/engine_v11.js';
import * as LAB from '../src/lab.js';
import { spriteSheet } from './lab-sprites.mjs';
import { presets, drums, waves } from './tinychip/presets/convert.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const engineFile = process.argv[2];
if (!engineFile) { console.error('usage: node onchain/editions-demo.mjs <webaudio-tinysynth engine .min.js>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const bundle = (await build({
  stdin: { contents: "import { engine } from './src/index.js'; import { createEngineV11 } from './src/engine_v11.js'; import { genesisMidi, labBlockHash } from './src/lab.js'; import * as ed from './src/editions_lite.js'; window.BS = { engine, v11: createEngineV11(engine), genesisMidi, labBlockHash, ed };", resolveDir: here + '..', loader: 'js' },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;

// The 75 species: tonic and theme from their Genesis Track (key, mode, the picked theme's degrees)
const V11E = createEngineV11(ENGINE);
const TYPES = ['Magic', 'Hunter', 'Brute'];
const SPECIES = Array.from({ length: 75 }, (_, k) => {
  const id = k + 1, tier = Math.floor((k % 25) / 5) + 1, type = Math.floor(k / 25);
  const o = LAB.genesisMidi(id, false, ENGINE, V11E);
  return { id, name: beastName({ id, prefix: 0, suffix: 0 }), tier, type, tonicPc: o.result.params.tonic_keynum % 12, key: o.info.key, degrees: o.result.form.theme.degrees };
});
const SPRITES = Object.fromEntries(SPECIES.flatMap((s) => [String(s.id), s.id + 's']).map((k) => { const { n, w, png } = spriteSheet(k); return [k, { n, w, png }]; }));
const DATA = {
  species: SPECIES, types: TYPES,
  presets: presets.map((p) => ({ program: p.program, name: p.name, operators: p.operators })),
  drums: drums.map((d) => ({ key: d.key, operators: d.operators })),
  waves: waves.map((w) => w.Samples),
};

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Monthly Track Editions</title>
<style>
:root{--bg:#f6f4ef;--fg:#1d1b18;--mut:#6b655c;--card:#fff;--line:#e2ddd3;--acc:#7a3cff;--keep:#1f9d55;--maybe:#c08a00;--rej:#c0392b}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--keep:#3ccf7e;--maybe:#f0c040;--rej:#ff6b5b}}
:root[data-theme="dark"]{--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--keep:#3ccf7e;--maybe:#f0c040;--rej:#ff6b5b}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1080px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 18px;max-width:760px}
.grid{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:14px}@media(max-width:860px){.grid{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px}
.stepper{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;margin-bottom:12px}
.stepper .mid{text-align:center;min-width:0}.stepper .lbl{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}.stepper .val{font-weight:650;font-size:17px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.stepper .val small{font-weight:400;color:var(--mut);font-size:13px}
button{font:inherit;cursor:pointer}button.nav{width:44px;height:44px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:18px}
.ctl{display:flex;gap:10px;flex-wrap:wrap}.ctl button,.ctl select{flex:1;min-width:120px;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600}
.ctl button.go{background:var(--fg);color:var(--bg)}
.ed-head{display:grid;grid-template-columns:96px 1fr;gap:14px;align-items:center}
#art{width:96px;height:96px;border-radius:10px;background:#000;image-rendering:pixelated;background-repeat:no-repeat}
.ename{font-size:22px;font-weight:700;margin:0}.emonth{color:var(--acc);font-weight:600;font-size:14px}.edesc{color:var(--mut);font-size:14px;margin:2px 0 0}
dl{display:grid;grid-template-columns:max-content 1fr;gap:3px 12px;margin:12px 0 0;font-size:13px}dt{color:var(--mut)}dd{margin:0;font-family:ui-monospace,monospace;font-size:12.5px;overflow-wrap:anywhere}
#roll{width:100%;height:220px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card))}
.legend{display:flex;flex-wrap:wrap;gap:4px 12px;margin-top:8px;font-size:12px}.legend i{width:10px;height:10px;border-radius:3px;display:inline-block;margin-right:5px;vertical-align:-1px}
.verdict{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.verdict button{padding:10px;border-radius:10px;border:2px solid var(--line);background:var(--bg);color:var(--fg);font-weight:650}
.verdict button.on[data-v=keep]{border-color:var(--keep);background:color-mix(in srgb,var(--keep) 16%,var(--bg))}.verdict button.on[data-v=maybe]{border-color:var(--maybe);background:color-mix(in srgb,var(--maybe) 18%,var(--bg))}.verdict button.on[data-v=reject]{border-color:var(--rej);background:color-mix(in srgb,var(--rej) 14%,var(--bg))}
textarea{width:100%;min-height:64px;margin-top:8px;padding:8px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font:13px/1.4 system-ui}
.list{display:grid;gap:4px;max-height:640px;overflow:auto}.row{display:grid;grid-template-columns:34px 1fr auto;gap:8px;align-items:center;padding:6px 8px;border:1px solid var(--line);border-radius:8px;background:var(--bg);cursor:pointer;text-align:left;color:var(--fg)}
.row.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 13%,var(--bg))}.row .n{font:12px ui-monospace,monospace;color:var(--mut)}.row b{font-size:13.5px;display:block}.row small{color:var(--mut);font-size:12px}
.dot{width:10px;height:10px;border-radius:50%;background:var(--line)}.dot.keep{background:var(--keep)}.dot.maybe{background:var(--maybe)}.dot.reject{background:var(--rej)}
.sec{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em;margin:10px 0 4px}
label.chk{display:flex;gap:8px;align-items:center;font-size:14px;margin-top:10px}.note{font-size:12.5px;color:var(--mut);margin:8px 0 0}
.kbd{font:11px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 4px}
</style></head><body><main>
<h1>Monthly Track Editions</h1>
<p class="sub">Prototype: each month brings a different style for newly bought tracks. Step through editions, Beasts and seeds, listen, and mark each edition. The Beast carries into every style through its species tonic, the opening of its Genesis theme, its type's instrument shade, and the mega lead when shiny. The seed (a stand-in mint block hash) picks the song inside the style.</p>
<div class="grid"><div>
<div class="card">
<div class="stepper"><button class="nav" id="e-prev" title="Previous edition (↑)">▲</button><div class="mid"><div class="lbl">Edition</div><div class="val" id="e-val"></div></div><button class="nav" id="e-next" title="Next edition (↓)">▼</button></div>
<div class="stepper"><button class="nav" id="b-prev" title="Previous Beast (←)">◀</button><div class="mid"><div class="lbl">Beast</div><div class="val" id="b-val"></div></div><button class="nav" id="b-next" title="Next Beast (→)">▶</button></div>
<div class="stepper"><button class="nav" id="s-prev" title="Previous seed ([)">−</button><div class="mid"><div class="lbl">Track seed</div><div class="val" id="s-val"></div></div><button class="nav" id="s-next" title="Next seed (])">+</button></div>
<label class="chk"><input type="checkbox" id="shiny"> Shiny (mega lead, octave double)</label>
<div class="ctl" style="margin-top:12px"><button class="go" id="play">▶ Play</button><button id="stop">■ Stop</button></div>
<div class="ctl" style="margin-top:8px"><select id="tour"><option value="editions">Tour: every edition, this Beast</option><option value="beasts">Tour: every Beast, this edition</option><option value="seeds">Tour: seeds 1–10, this Beast and edition</option></select><select id="dwell"><option value="30">30 s each</option><option value="loop">One full loop each</option><option value="15">15 s each</option></select><button id="tourgo">▶ Start tour</button></div>
<p class="note">Keys: <span class="kbd">↑</span> <span class="kbd">↓</span> edition · <span class="kbd">←</span> <span class="kbd">→</span> Beast · <span class="kbd">[</span> <span class="kbd">]</span> seed · <span class="kbd">space</span> play/stop. Changes play straight away while playing. The address bar keeps the current pick.</p>
</div>
<div class="card"><div class="ed-head"><div id="art" role="img" aria-label=""></div><div><div class="emonth" id="emonth"></div><p class="ename" id="ename"></p><p class="edesc" id="edesc"></p></div></div><dl id="info"></dl></div>
<div class="card"><canvas id="roll" width="1600" height="440"></canvas><div class="legend" id="legend"></div></div>
</div><div>
<div class="card"><div class="sec" style="margin-top:0">Your verdict on this edition</div>
<div class="verdict"><button data-v="keep">Keep</button><button data-v="maybe">Maybe</button><button data-v="reject">Reject</button></div>
<textarea id="vnote" placeholder="Notes on this edition (saved in this browser)"></textarea>
<div class="ctl" style="margin-top:8px"><button id="export">Copy all verdicts</button></div><p class="note" id="vsum"></p></div>
<div class="card"><div class="sec" style="margin-top:0">Calendar</div><div class="list" id="list"></div>
<p class="note">From November 2026 the four onchain styles take turns (waltz, chorale, lullaby, dirge); each pass through them moves on the mode, tempo and form. These are the tracks BeastMidiProvider composes onchain, byte for byte.</p></div>
</div></div>
</main>
<script>${inline(tiny)}</script>
<script>${inline(bundle)}</script>
<script>
const DATA = ${JSON.stringify(DATA)};
const SPRITES = ${JSON.stringify(SPRITES)};
const $ = (id) => document.getElementById(id), ED = BS.ed, N_ED = 48;
const PNAME = Object.fromEntries(DATA.presets.map((p) => [p.program, p.name]));
const st = { e: 1, s: 0, n: 1, shiny: false };
let synth = null, playing = false, rollData = null, tourOn = false, tourTimer = 0, passSec = 0;

// ── state in the URL ──
(function readUrl() { const q = new URLSearchParams(location.search); if (q.has('e')) st.e = Math.max(0, Math.min(N_ED - 1, +q.get('e') || 0)); if (q.has('b')) st.s = Math.max(0, Math.min(74, (+q.get('b') || 1) - 1)); if (q.has('seed')) st.n = Math.max(1, +q.get('seed') || 1); st.shiny = q.get('shiny') === '1'; $('shiny').checked = st.shiny; })();
function writeUrl() { const q = new URLSearchParams({ e: st.e, b: st.s + 1, seed: st.n }); if (st.shiny) q.set('shiny', '1'); history.replaceState(null, '', '?' + q); }

// ── verdicts (this browser only) ──
const VKEY = 'editions.verdicts.v1';
let verdicts = {}; try { verdicts = JSON.parse(localStorage.getItem(VKEY) || '{}') || {}; } catch {}
const saveV = () => { try { localStorage.setItem(VKEY, JSON.stringify(verdicts)); } catch {} };
document.querySelectorAll('.verdict button').forEach((b) => b.onclick = () => { const v = verdicts[st.e] || {}; v.v = v.v === b.dataset.v ? null : b.dataset.v; verdicts[st.e] = v; saveV(); show(); });
$('vnote').oninput = () => { const v = verdicts[st.e] || {}; v.note = $('vnote').value; verdicts[st.e] = v; saveV(); };
$('export').onclick = async () => {
  const lines = []; for (let e = 0; e < N_ED; e++) { const v = verdicts[e]; if (!v || (!v.v && !v.note)) continue; const g = ED.editionGenome(e); lines.push(e + ' ' + g.month + ' · ' + g.name + ' (' + ED.ENGINES[g.engine].label + '): ' + (v.v || '-') + (v.note ? ' — ' + v.note.replace(/\\s+/g, ' ') : '')); }
  const text = lines.join('\\n') || 'No verdicts yet.';
  try { await navigator.clipboard.writeText(text); $('vsum').textContent = 'Copied ' + lines.length + ' verdicts.'; } catch { $('vnote').value = text; $('vsum').textContent = 'Clipboard unavailable: the list is in the notes box.'; }
};

// ── composing ──
const seedHash = (n) => BS.labBlockHash(1000000 + n * 43200);
function compose() {
  const sp = DATA.species[st.s];
  if (st.e === 0) {
    const o = BS.genesisMidi(sp.id, st.shiny, BS.engine, BS.v11, { seed: seedHash(st.n) });
    const g = ED.editionGenome(0), i = o.info;
    return { midi: o.midi, info: { edition: 0, month: g.month, name: g.name, engine: ED.ENGINES.canon.label, desc: ED.ENGINES.canon.desc, key: i.key, meter: '4/4', bpm: i.tempo, form: i.sections + ' sections, ' + i.voices + ' voices, ' + i.development, channels: i.channels.join(', ') } };
  }
  return ED.editionMidi(sp, st.shiny, st.e, 'seed:' + st.n);
}

// ── display ──
const ROLE = { 0: 'lead', 1: 'counter', 2: 'accomp', 3: 'bass', 4: 'pad', 5: 'tenor', 6: 'mega double', 9: 'drums' };
const COLORS = ['#7a3cff', '#e0742a', '#1f9d8c', '#c0392b', '#7f8c8d', '#2a7ae0', '#e0b000', '#9b59b6', '#16a085', '#888'];
let cur = null;
function show() {
  const sp = DATA.species[st.s], g = ED.editionGenome(st.e);
  cur = compose();
  const i = cur.info;
  $('e-val').innerHTML = st.e + ' · ' + g.name + ' <small>' + g.month + '</small>';
  $('b-val').innerHTML = sp.id + '. ' + sp.name + ' <small>tier ' + sp.tier + ' ' + DATA.types[sp.type] + '</small>';
  $('s-val').innerHTML = '#' + st.n + ' <small>' + seedHash(st.n).toString(16).slice(0, 10) + '…</small>';
  $('emonth').textContent = g.month + (g.curated ? ' · hand-picked' : ' · generated');
  $('ename').textContent = g.name; $('edesc').textContent = i.desc;
  const rows = [['Engine', i.engine], ['Key', i.key + (st.e ? '  (species: ' + sp.key + ')' : '')], ['Meter / tempo', i.meter + ' · ' + i.bpm + ' BPM' + (i.seconds ? ' · ' + i.seconds + ' s loop' : '')], ['Form', i.form]];
  if (i.grammar) rows.push(['Harmony', i.grammar], ['Progressions', 'A: ' + i.progA + '   B: ' + i.progB], ['Accomp / bass / drums', i.accomp + ' / ' + i.bass + ' / ' + i.drums]);
  if (i.channels) rows.push(['Channels', i.channels]);
  $('info').innerHTML = rows.map(([a, b]) => '<dt>' + a + '</dt><dd>' + String(b).replace(/</g, '&lt;') + '</dd>').join('');
  const v = verdicts[st.e] || {};
  document.querySelectorAll('.verdict button').forEach((b) => b.classList.toggle('on', v.v === b.dataset.v));
  $('vnote').value = v.note || '';
  const counts = { keep: 0, maybe: 0, reject: 0 }; Object.values(verdicts).forEach((x) => x && x.v && counts[x.v]++);
  $('vsum').textContent = counts.keep + ' keep · ' + counts.maybe + ' maybe · ' + counts.reject + ' reject';
  art(sp); list(); roll(cur.midi); writeUrl();
}
function art(sp) {
  const k = sp.id + (st.shiny ? 's' : ''), s = SPRITES[k] || SPRITES[String(sp.id)], el = $('art'), scale = 96 / s.w;
  el.style.backgroundImage = 'url(data:image/png;base64,' + s.png + ')';
  el.style.backgroundSize = (s.n * 96) + 'px 96px';
  el.setAttribute('aria-label', sp.name);
  el.getAnimations().forEach((a) => a.cancel());
  const bpm = (cur && cur.info.bpm) || 120, frames = Array.from({ length: s.n }, (_, f) => ({ backgroundPosition: (-f * 96) + 'px 0' }));
  if (s.n > 1) el.animate(frames, { duration: s.n * 60000 / bpm / 2, iterations: Infinity, easing: 'steps(' + s.n + ', jump-none)' });
  void scale;
}
function list() {
  const L = $('list'); if (!L.children.length) for (let e = 0; e < N_ED; e++) { const g = ED.editionGenome(e), b = document.createElement('button'); b.className = 'row'; b.dataset.e = e; b.innerHTML = '<span class="n">' + e + '</span><span><b>' + g.name + '</b><small>' + g.month + ' · ' + ED.ENGINES[g.engine].label + '</small></span><span class="dot"></span>'; b.onclick = () => { st.e = e; change(); }; L.appendChild(b); }
  [...L.children].forEach((b) => { const e = +b.dataset.e, v = (verdicts[e] || {}).v; b.classList.toggle('on', e === st.e); b.querySelector('.dot').className = 'dot' + (v ? ' ' + v : ''); });
  const on = L.querySelector('.row.on'); if (on) on.scrollIntoView({ block: 'nearest' });
}

// ── piano roll ──
function notesOf(u8) {
  const notes = [], prog = {}; let tpq = (u8[12] << 8) | u8[13], end = 0, i = 8 + 6, ntr = (u8[10] << 8) | u8[11];
  for (let tr = 0; tr < ntr; tr++) {
    i += 4; const len = (u8[i] << 24 | u8[i + 1] << 16 | u8[i + 2] << 8 | u8[i + 3]) >>> 0; i += 4; const stop = i + len; let t = 0, run = 0; const on = {};
    while (i < stop) {
      let d = 0, b; do { b = u8[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d;
      let s = u8[i]; if (s & 128) i++; else s = run;
      if (s === 0xff) { const ty = u8[i++]; let l = 0; do { b = u8[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; if (ty === 0x2f) end = Math.max(end, t); continue; }
      if (s === 0xf0 || s === 0xf7) { let l = 0; do { b = u8[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; }
      run = s; const ty = s & 0xf0, ch = s & 15;
      if (ty === 0xc0 || ty === 0xd0) { if (ty === 0xc0) prog[ch] = u8[i]; i += 1; continue; }
      const a = u8[i], v = u8[i + 1]; i += 2;
      if (ty === 0x90 && v) on[ch * 128 + a] = t;
      else if (ty === 0x80 || ty === 0x90) { const k = ch * 128 + a; if (on[k] !== undefined) { notes.push([on[k], t, a, ch]); delete on[k]; } }
    }
    i = stop;
  }
  return { notes, prog, tpq, end: Math.max(end, ...notes.map((n) => n[1])) };
}
function roll(midi) {
  rollData = notesOf(midi);
  const chans = [...new Set(rollData.notes.map((n) => n[3]))].sort((a, b) => a - b);
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + (ch === 9 ? 'var(--mut)' : COLORS[ch % 10]) + '"></i>' + (st.e ? ROLE[ch] + ' ' : 'ch' + (ch + 1) + ' ') + (ch === 9 ? (st.e ? '' : 'drums') : (PNAME[rollData.prog[ch]] || '')) + '</span>').join('');
  draw(-1);
}
function draw(play) {
  const c = $('roll'), x = c.getContext('2d'), W = c.width, H = c.height, d = rollData; x.clearRect(0, 0, W, H); if (!d) return;
  const tones = d.notes.filter((n) => n[3] !== 9), lo = Math.min(...tones.map((n) => n[2])) - 2, hi = Math.max(...tones.map((n) => n[2])) + 2, drumH = 40, top = 6, ph = H - drumH - top - 6, sx = W / d.end;
  const fg = getComputedStyle(document.body).color;
  x.globalAlpha = 0.12; x.fillStyle = fg; const [mn, md] = String((cur && cur.info.meter) || '4/4').split('/').map(Number), bar = d.tpq * 4 * mn / md; for (let t = 0; t < d.end; t += bar) x.fillRect(t * sx, 0, 1, H); x.globalAlpha = 1;
  for (const [a, b, p, ch] of d.notes) {
    if (ch === 9) { x.fillStyle = fg; x.globalAlpha = 0.4; x.fillRect(a * sx, H - drumH + (p % 10) * 3.5, Math.max(2, (b - a) * sx * 0.5), 3); x.globalAlpha = 1; continue; }
    x.fillStyle = COLORS[ch % 10]; x.fillRect(a * sx, top + (hi - p) / (hi - lo) * ph, Math.max(2, (b - a) * sx - 1), Math.max(3, ph / (hi - lo) - 1));
  }
  if (play >= 0) { x.fillStyle = fg; x.fillRect((play % d.end) * sx, 0, 3, H); }
}
(function loop() { if (playing && synth && synth.tick2Time) { const t = synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time; draw(t); } requestAnimationFrame(loop); })();

// ── the synth, installed as onchain-midi-player installs settings ──
const FIX = (v) => v / 10000, TSW = { Sine: 'sine', Square: 'square', Sawtooth: 'sawtooth', Triangle: 'triangle', WhiteNoise: 'n0', MetallicNoise: 'n1' };
const FIELDS = [['volume', 'v'], ['ratio', 't'], ['offset_hz', 'f'], ['attack', 'a'], ['hold', 'h'], ['decay', 'd'], ['sustain', 's'], ['release', 'r'], ['pitch_ratio', 'p'], ['pitch_time', 'q'], ['key_scale', 'k']];
const toOps = (ops) => ops.map((o) => { const p = { g: o.route, w: typeof o.wave === 'object' ? 'nS' + o.wave.Custom : TSW[o.wave] }; for (const [n, k] of FIELDS) p[k] = FIX(o[n]); return p; });
function ensure() {
  if (synth) return synth;
  synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  DATA.waves.forEach((w, i) => synth.setSampleWave('nS' + i, w.map((v) => v / 128)));
  synth.setQuality(1); synth.setMasterVol(0.4); synth.setReverbLev(0.3); synth.setVoices(64);
  for (const p of DATA.presets) synth.setTimbre(0, p.program, toOps(p.operators));
  for (const d of DATA.drums) synth.setTimbre(1, d.key, toOps(d.operators));
  return synth;
}
function start() {
  const s = ensure(), m = cur.midi;
  s.getAudioContext().resume(); s.stopMIDI();
  s.loadMIDI(m.buffer.slice(m.byteOffset, m.byteOffset + m.length));
  s.setLoop(1); s.setLoopEnd(s.getPlayStatus().maxTick); s.playMIDI(); playing = true;
  passSec = rollData.end / rollData.tpq * 60 / (cur.info.bpm || 120);
  if (tourOn) scheduleTour();
}
function stop() { tourOn = false; clearTimeout(tourTimer); $('tourgo').textContent = '▶ Start tour'; if (synth) synth.stopMIDI(); playing = false; draw(-1); }
function change() { show(); if (playing) start(); }

// ── tours ──
function scheduleTour() {
  clearTimeout(tourTimer);
  const dw = $('dwell').value, secs = dw === 'loop' ? passSec : +dw;
  tourTimer = setTimeout(() => {
    const mode = $('tour').value;
    if (mode === 'editions') { if (st.e + 1 >= N_ED) return stop(); st.e++; }
    else if (mode === 'beasts') { if (st.s + 1 >= 75) return stop(); st.s++; }
    else { if (st.n >= 10) return stop(); st.n++; }
    show(); start();
  }, secs * 1000 + 300);
}
$('tourgo').onclick = () => { if (tourOn) return stop(); tourOn = true; $('tourgo').textContent = '■ Stop tour'; if ($('tour').value === 'seeds') st.n = 1; show(); start(); };

// ── controls ──
const step = (k, d) => { if (k === 'e') st.e = (st.e + d + N_ED) % N_ED; if (k === 's') st.s = (st.s + d + 75) % 75; if (k === 'n') st.n = Math.max(1, st.n + d); change(); };
$('e-prev').onclick = () => step('e', -1); $('e-next').onclick = () => step('e', 1);
$('b-prev').onclick = () => step('s', -1); $('b-next').onclick = () => step('s', 1);
$('s-prev').onclick = () => step('n', -1); $('s-next').onclick = () => step('n', 1);
$('shiny').onchange = () => { st.shiny = $('shiny').checked; change(); };
$('play').onclick = () => { start(); };
$('stop').onclick = stop;
document.addEventListener('keydown', (ev) => {
  if (ev.target.tagName === 'TEXTAREA' || ev.target.tagName === 'SELECT' || ev.metaKey || ev.ctrlKey) return;
  const k = { ArrowUp: ['e', -1], ArrowDown: ['e', 1], ArrowLeft: ['s', -1], ArrowRight: ['s', 1], '[': ['n', -1], ']': ['n', 1] }[ev.key];
  if (k) { ev.preventDefault(); step(...k); } else if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); }
});
show();
</script></body></html>`;
writeFileSync(new URL('../public/onchain/editions.html', import.meta.url), html);
console.log('editions.html', html.length, 'bytes');

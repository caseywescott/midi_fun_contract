// Build public/loot-lab.html: every track a Loot Dungeon Beast plays, to audition before launch.
// Species Song, Name Song and Sound Check are the Beasts v1.0.1 composer's (its JS reference, lab.js);
// Monthly Track Editions are src/loot_editions.js (Realm of Common Tones and Kingdom of Sweets
// harmony). Drift is Casey Drift on Species Songs and editions. Sound effects: 0 regular, 1 mega.
// Instruments: the sample bank (12 kHz BRR, ten CC0 VSCO 2 instruments; midi_fun_contract branch
// feat/snes-brr-pipeline, onchain/snes/dist/bank.min.js) by default, each channel's role mapped to a
// bank instrument; drums stay on TinySynth's chip kit. TinyChip presets remain a toggle.
//   node onchain/loot-lab.mjs <engine .min.js> <onchain-midi-player checkout> <midi_fun_contract checkout at v1.0.1> <bank.min.js>
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { build } from 'esbuild';
import { LOOT_BEASTS } from '../src/loot_beasts.js';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';

const here = fileURLToPath(new URL('.', import.meta.url));
// optional: the output name, then label/bank pairs to compare (local evaluation); the Instruments button
// cycles the sample bank, each extra bank, then TinyChip
const [engineFile, omp, ref, bankFile, outName = 'loot-lab.html', ...pairs] = process.argv.slice(2);
const extras = []; for (let i = 0; i + 1 < pairs.length; i += 2) extras.push([pairs[i], pairs[i + 1]]);
if (!engineFile || !omp || !ref || !bankFile) { console.error('usage: node onchain/loot-lab.mjs <engine .min.js> <onchain-midi-player checkout> <midi_fun_contract checkout> <bank.min.js>'); process.exit(2); }
const BSRC = join(ref, 'offchain/beast-sound');
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
// the sample bank, its globals named for what they are
const clean = (f) => { const js = readFileSync(f, 'utf8').replace(/SnesBank/g, 'SampleBank').replace(/__snesSampler/g, '__sampleLayer').replace(/SNES sampler/g, 'Sampler').replace(/snes-brr-1/g, 'brr-1'); if (/snes/i.test(js)) throw new Error('bank script still names SNES'); return js; };
const bankJs = [clean(bankFile) + '\nwindow.Banks=[SampleBank];', ...extras.map(([, f]) => clean(f) + '\nwindow.Banks.push(SampleBank);')].join('\n');
const INSTS = ['sample bank', ...extras.map(([label]) => label), 'TinyChip'];
const bundle = (await build({
  stdin: {
    contents: `import { engine } from ${JSON.stringify(BSRC + '/src/index.js')}; import { createEngineV11 } from ${JSON.stringify(BSRC + '/src/engine_v11.js')};
      import * as lab from ${JSON.stringify(BSRC + '/src/lab.js')};
      import * as ed from './src/loot_editions.js';
      import { installSettings } from ${JSON.stringify(omp + '/player/settings.js')};
      window.BS = { engine, v11: createEngineV11(engine), lab, ed, installSettings };`,
    resolveDir: here + '..', loader: 'js',
  },
  nodePaths: [join(BSRC, 'node_modules')], bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;

// the settings: a family's presets (mega adds the mega leads) for songs and Sound Checks; for an
// edition, the presets of the Beasts style it borrows its figures and palette from
const ST = await import(pathToFileURL(join(BSRC, 'onchain/tinychip/synth_settings.mjs')).href);
const { STYLES: BEAST_STYLES } = await import(pathToFileURL(join(BSRC, 'src/editions_lite.js')).href);
const FAMILY = ST.SETTINGS_VARIANTS.map((v) => ST.beastSynthSettings(undefined, ST.variantPrograms(v)));
const EDITION = STYLES.map((S) => { const src = BEAST_STYLES.findIndex((x) => x.key === S.source); return [0, 1, 2].map((t) => [false, true].map((m) => ST.editionSynthSettings(src, t, m))); });
const { loadBank } = await import(pathToFileURL(join(BSRC, 'onchain/tinychip/essentials.mjs')).href);
const bank = loadBank();
const NAMES = Object.fromEntries(bank.PRESETS.map((p, i) => [p.program ?? i, p.name]));
const BEASTS = LOOT_BEASTS.map((b) => ({ ...b, ...SPECIES.find((s) => s.id === b.id) }));
// the bank's instruments (MIDI programs) and the orchestration: an edition style's roles (lead,
// accompaniment, bass, pad; the descant plays the lead, the mega double a glockenspiel or flute), a
// song channel's instrument by family (channel 0 the theme, 4 the countersubject)
const BANK = { piano: 0, glockenspiel: 9, marimba: 12, cello: 42, pizzicato: 45, harp: 46, timpani: 47, strings: 48, clarinet: 71, flute: 73 };
const ROLES = {
  overworld: ['clarinet', 'pizzicato', 'cello', 'strings'], field: ['flute', 'harp', 'cello', 'strings'],
  lullaby: ['flute', 'harp', 'cello', 'strings'], forest: ['clarinet', 'marimba', 'pizzicato', 'strings'],
  temple: ['clarinet', 'harp', 'cello', 'strings'], boss: ['strings', 'marimba', 'cello', 'strings'],
  flowers: ['flute', 'harp', 'cello', 'strings'], toymarch: ['glockenspiel', 'pizzicato', 'cello', 'clarinet'],
  adagio: ['strings', 'piano', 'cello', 'strings'], sugarplum: ['glockenspiel', 'pizzicato', 'clarinet', 'strings'],
  trepak: ['strings', 'pizzicato', 'cello', 'clarinet'], arabian: ['clarinet', 'harp', 'cello', 'strings'],
};
const ORCH = {
  edition: Object.fromEntries(STYLES.map((S) => { const [lead, acc, bass, pad] = ROLES[S.key].map((n) => BANK[n]); return [S.key, [lead, lead, acc, bass, pad, lead === BANK.glockenspiel ? BANK.flute : BANK.glockenspiel]]; })),
  song: [
    ['flute', 'clarinet', 'harp', 'cello', 'glockenspiel', 'strings', 'harp', 'strings'],
    ['clarinet', 'strings', 'marimba', 'cello', 'pizzicato', 'strings', 'marimba', 'strings'],
    ['strings', 'cello', 'piano', 'cello', 'clarinet', 'strings', 'piano', 'strings'],
  ].map((r) => r.map((n) => BANK[n])),
  names: Object.fromEntries(Object.entries(BANK).map(([k, v]) => [v, k])),
};
if (Object.keys(ROLES).length !== STYLES.length || STYLES.some((S) => !ROLES[S.key])) throw new Error('every style needs sample roles');
const DATA = { insts: INSTS, orch: ORCH, beasts: BEASTS, types: ['Magic', 'Hunter', 'Brute'], names: NAMES, family: FAMILY, edition: EDITION, styles: STYLES.map((s) => ({ key: s.key, label: s.label, desc: s.desc, home: s.home })) };

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Loot Dungeon Sound Lab</title>
<link rel="icon" href="data:,">
<meta name="description" content="Every track a Loot Dungeon Beast plays: Species Song, Name Song, Sound Check and Monthly Track Editions in Realm and Sweets harmony, with Casey Drift.">
<style>
:root{--bg:#f4f1ea;--fg:#1c1a17;--mut:#6b655c;--card:#fff;--line:#e0dace;--acc:#8a2be2;--gold:#b8860b}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#121016;--fg:#ece6f2;--mut:#9a92a8;--card:#1d1a24;--line:#2d2938;--acc:#b37bff;--gold:#e0b34a}}
:root[data-theme="dark"]{--bg:#121016;--fg:#ece6f2;--mut:#9a92a8;--card:#1d1a24;--line:#2d2938;--acc:#b37bff;--gold:#e0b34a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}h1{font-size:23px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 16px;max-width:820px}
.tabs{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:14px}.tabs button{padding:10px 12px;border-radius:12px;border:2px solid var(--line);background:var(--card);color:var(--fg);text-align:left;cursor:pointer;font:inherit}
.tabs button b{display:block}.tabs button span{display:block;color:var(--mut);font-size:12.5px}.tabs button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 12%,var(--card))}
@media(max-width:760px){.tabs{grid-template-columns:1fr 1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px;min-width:0}
.row{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;margin-bottom:10px}.row .mid{text-align:center;min-width:0}.lbl{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}
.val{font-weight:650;font-size:16px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.val small{font-weight:400;color:var(--mut);font-size:13px}.row.off{display:none}
button,input{font:inherit}button.nav{width:42px;height:42px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:17px;cursor:pointer}
.ctl{display:flex;gap:10px;flex-wrap:wrap}.ctl button{flex:1;min-width:110px;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600;cursor:pointer}.ctl button.go{background:var(--fg);color:var(--bg)}.ctl button.on{border-color:var(--gold);color:var(--gold)}
.age{display:block;font-size:13px;margin-top:10px}.age input{width:100%;margin-top:6px;accent-color:var(--acc)}.age.off{display:none}
#roll{width:100%;height:220px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card))}
.legend{display:flex;flex-wrap:wrap;gap:4px 14px;margin-top:8px;font-size:12px;color:var(--mut)}.legend i{width:10px;height:10px;border-radius:3px;display:inline-block;margin-right:5px;vertical-align:-1px}
dl{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:4px 12px;margin:0;font-size:13px}dt{color:var(--mut)}dd{margin:0;font-family:ui-monospace,monospace;font-size:12.5px;overflow-wrap:anywhere}
.note{font-size:12.5px;color:var(--mut);margin:8px 0 0}.kbd{font:11px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 4px}
.styles{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:8px}.styles button{text-align:left;padding:8px 10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);cursor:pointer;font:inherit}.styles button b{display:block;font-size:14px}.styles button span{font-size:12px;color:var(--mut)}.styles button.on{border-color:var(--acc)}
h2{font-size:13px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em;margin:0 0 10px}
</style></head><body><main>
<h1>Loot Dungeon Sound Lab</h1>
<p class="sub">Every track the 30 Loot Dungeon Beasts play. Species Songs, Name Songs and Sound Checks come from the Beasts composer unchanged. Monthly Track Editions are new: the edition engine with chromatic harmony after <i>Realm of Common Tones</i> (mode mixture, chromatic mediants, common-tone pivots) and <i>Kingdom of Sweets</i> (applied dominants, diminished sevenths, the Neapolitan and German sixth). Sound effects: regular or mega. Instruments: a ten-instrument sample bank (harp, marimba, glockenspiel, strings, cello, flute, pizzicato, clarinet, timpani, piano) at 12 kHz, with the TinyChip presets one click away. Beast ids, tiers and families are placeholders until the final list.</p>
<div class="tabs" role="tablist">
<button id="t-song"><b>Species Song</b><span>shared by every Beast of the species</span></button>
<button id="t-name"><b>Name Song</b><span>a Beast with a special name</span></button>
<button id="t-check"><b>Sound Check</b><span>the Beast's warm-up</span></button>
<button id="t-edition"><b>Edition</b><span>a track bought from edition 1</span></button>
</div>
<div class="card">
<div class="row"><button class="nav" id="b-prev" aria-label="Previous Beast">◀</button><div class="mid"><div class="lbl">Beast</div><div class="val" id="b-val"></div></div><button class="nav" id="b-next" aria-label="Next Beast">▶</button></div>
<div class="row" id="row-n"><button class="nav" id="n-prev" aria-label="Previous name">−</button><div class="mid"><div class="lbl">Special name</div><div class="val" id="n-val"></div></div><button class="nav" id="n-next" aria-label="Next name">+</button></div>
<div class="row" id="row-e"><button class="nav" id="e-prev" aria-label="Previous edition">▲</button><div class="mid"><div class="lbl">Edition</div><div class="val" id="e-val"></div></div><button class="nav" id="e-next" aria-label="Next edition">▼</button></div>
<div class="row" id="row-p"><button class="nav" id="p-prev" aria-label="Previous purchase">−</button><div class="mid"><div class="lbl">Purchase</div><div class="val" id="p-val"></div></div><button class="nav" id="p-next" aria-label="Next purchase">+</button></div>
<div class="ctl"><button class="go" id="play">▶ Play</button><button id="stop">■ Stop</button><button id="mega">Mega: off</button><button id="inst">Instruments: sample bank</button></div>
<label class="age" id="row-d">Drift day <b id="d-val"></b> (1 = as written)<input type="range" id="day" min="1" max="400" value="1" aria-label="Drift day"></label>
</div>
<div class="card"><h2 id="title"></h2><dl id="readout"></dl></div>
<div class="card"><canvas id="roll" width="1600" height="440" aria-label="Notes"></canvas><div class="legend" id="legend"></div></div>
<div class="card" id="stylecard"><h2>Edition styles · one a month, in turn</h2><div class="styles" id="styles"></div></div>
<p class="note"><a href="/" style="color:var(--acc)">All pages</a> · <a href="/onchain/lab.html" style="color:var(--acc)">Beasts Lab</a> · <a href="/onchain/drift-lab.html" style="color:var(--acc)">Drift Lab</a></p>
<p class="note">Keys: <span class="kbd">space</span> play/stop, <span class="kbd">←</span> <span class="kbd">→</span> Beast, <span class="kbd">↑</span> <span class="kbd">↓</span> edition, <span class="kbd">[</span> <span class="kbd">]</span> purchase, <span class="kbd">m</span> mega. Block hashes for drift are simulated. Samples: VSCO 2 Community Edition by Versilian Studios (CC0).</p>
</main>
<script>${inline(tiny)}</script>
<script>${inline(bundle)}</script>
<script>${inline(bankJs)}</script>
<script>
const DATA = ${JSON.stringify(DATA)};
const $ = (id) => document.getElementById(id), E = BS.engine, V = BS.v11, L = BS.lab, ED = BS.ed, U64 = (1n << 64n) - 1n, N = DATA.beasts.length, NSTYLE = DATA.styles.length;
const st = { kind: 'song', b: 0, name: 1, e: 1, p: 1, day: 1, mega: false, inst: 0 };
(function readUrl() {
  const q = new URLSearchParams(location.search), num = (k, lo, hi, d) => (q.has(k) ? Math.max(lo, Math.min(hi, Math.round(+q.get(k)) || 0)) : d);
  if (['song', 'name', 'check', 'edition'].includes(q.get('track'))) st.kind = q.get('track');
  st.b = num('b', 0, N - 1, 0); st.name = num('name', 1, L.NAME_COUNT, 1); st.e = num('e', 1, NSTYLE * 2, 1); st.p = num('p', 1, 1e6, 1); st.day = num('day', 1, 400, 1); st.mega = q.get('mega') === '1'; st.inst = q.get('inst') === 'chip' ? DATA.insts.length - 1 : Math.max(0, Math.min(DATA.insts.length - 1, +(q.get('inst') || 0) || 0));
})();
let synth = null, playing = false, cur = null, layer = null, layerBank = -1, setProgram0 = null;
const isChip = () => st.inst === DATA.insts.length - 1;
const anchor = L.dayAnchor();
const beast = () => DATA.beasts[st.b];
function purchaseSeed(n) { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); }
const bOf = (x, named) => { const n = named ? L.nameFromVariant(st.name) : { prefix: 0, suffix: 0 }; return { id: x.id, prefix: n.prefix, suffix: n.suffix, level: 1, health: 100, shiny: st.mega ? 1 : 0, animated: 0, tier: x.tier, beast_type: x.type }; };
function track() {
  const x = beast(), day = st.day > 1 ? st.day : null;
  if (st.kind === 'edition') {
    const d = day ? L.drift2({ id: x.id, prefix: 0, suffix: 0 }, day, anchor) : null;
    const o = ED.editionMidi(x, st.mega, st.e, purchaseSeed(st.p), d);
    return { midi: o.midi, info: o.info, settings: DATA.edition[(st.e - 1) % NSTYLE][x.type][st.mega ? 1 : 0], orch: DATA.orch.edition[DATA.styles[(st.e - 1) % NSTYLE].key] };
  }
  const settings = DATA.family[x.type * 2 + (st.mega ? 1 : 0)];
  const orch = DATA.orch.song[x.type];
  if (st.kind === 'check') { const o = L.soundCheckMidi(bOf(x, false), E); return { midi: o.midi, info: o.info, settings, orch }; }
  const opts = { ...L.GENESIS_DEFAULTS, ...(st.kind === 'name' ? { name: st.name } : {}), ...(day ? { epoch: day, driftMode: 'v2', blockHashes: true } : {}) };
  const o = L.sampleTrackMidi(bOf(x, st.kind === 'name'), { species_count: 1 }, opts, E, V);
  return { midi: o.midi, info: o.info, settings, orch };
}
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const COLORS = ['#8a2be2', '#e0742a', '#1f9d8c', '#c0392b', '#7f8c8d', '#2a7ae0', '#b8860b', '#888'];
function show() {
  for (const k of ['song', 'name', 'check', 'edition']) $('t-' + k).classList.toggle('on', st.kind === k);
  $('row-n').classList.toggle('off', st.kind !== 'name'); $('row-e').classList.toggle('off', st.kind !== 'edition'); $('row-p').classList.toggle('off', st.kind !== 'edition');
  $('row-d').classList.toggle('off', st.kind === 'check' || st.kind === 'name');
  const x = beast();
  $('b-val').innerHTML = x.id + '. ' + esc(x.name) + ' <small>tier ' + x.tier + ' ' + DATA.types[x.type] + '</small>';
  const nm = L.nameFromVariant(st.name); $('n-val').innerHTML = '#' + st.name + ' <small>prefix ' + nm.prefix + ', suffix ' + nm.suffix + '</small>';
  const g = ED.editionGenome(st.e), S = DATA.styles[g.style];
  $('e-val').innerHTML = st.e + ' · ' + esc(g.name) + ' <small>' + esc(S.label) + ' · ' + g.month + '</small>';
  $('p-val').innerHTML = '#' + st.p;
  $('mega').textContent = 'Mega: ' + (st.mega ? 'on' : 'off'); $('mega').classList.toggle('on', st.mega);
  $('inst').textContent = 'Instruments: ' + DATA.insts[st.inst];
  $('d-val').textContent = st.day; $('day').value = st.day;
  cur = track();
  const i = cur.info || {};
  const rows = st.kind === 'edition'
    ? [['Style', S.label + ' (' + i.family + ')'], ['Key', i.key], ['Meter / tempo', i.meter + ' · ' + i.bpm + ' BPM'], ['Form', i.form], ['A', i.progA], ['B', i.progB], ...(i.progC ? [['C', i.progC]] : []), ['Parts', i.parts.join(', ')], ['Theme', i.theme], ['Ornaments', i.ornaments], ['Phrasing', i.phrasing], ['Length', i.seconds + ' s']]
    : st.kind === 'check' ? [['Key', i.key], ['Preset', (i.presets || []).map((p) => DATA.names[p] || p).join(', ')], ['Pattern', (i.pattern || []).join(' ')]]
    : [['Key', i.key], ['Voices', i.voices], ['Tempo', i.bpm ? i.bpm + ' BPM' : ''], ['Drift', st.day > 1 ? 'day ' + st.day : 'as written']];
  $('title').textContent = { song: x.name + "'s Species Song", name: x.name + "'s Name Song", check: x.name + "'s Sound Check", edition: g.name }[st.kind] + (st.mega ? ' · mega' : '');
  $('readout').innerHTML = rows.filter((r) => r[1] !== undefined && r[1] !== '').map(([a, b]) => '<dt>' + a + '</dt><dd>' + esc(b) + '</dd>').join('');
  $('styles').innerHTML = DATA.styles.map((s, k) => '<button data-k="' + k + '" class="' + (st.kind === 'edition' && g.style === k ? 'on' : '') + '"><b>' + (k + 1) + '. ' + esc(s.label) + '</b><span>' + (k < 6 ? 'Realm' : 'Sweets') + ' · ' + esc(s.desc) + '</span></button>').join('');
  for (const bt of $('styles').querySelectorAll('button')) bt.onclick = () => { st.kind = 'edition'; st.e = +bt.dataset.k + 1; change(); };
  roll(cur.midi);
  history.replaceState(null, '', '?' + new URLSearchParams({ track: st.kind, b: st.b, name: st.name, e: st.e, p: st.p, day: st.day, ...(st.mega ? { mega: 1 } : {}), ...(st.inst ? { inst: isChip() ? 'chip' : st.inst } : {}) }));
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
const ROLES = { 0: 'lead', 1: 'descant', 2: 'accomp', 3: 'bass', 4: 'pad', 5: 'mega double' };
// a channel's instrument as it sounds: the bank's (the orchestration) or the TinyChip preset
const instName = (ch, prog) => (isChip() || !cur ? DATA.names[prog] || '' : DATA.orch.names[cur.orch[ch % cur.orch.length]] || '');
let rollData = null;
function roll(midi) {
  rollData = notesOf(midi);
  const chans = [...new Set(rollData.notes.map((n) => n[3]))].sort((a, b) => a - b);
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + (ch === 9 ? 'var(--mut)' : COLORS[ch % 8]) + '"></i>' + (ch === 9 ? 'drums' : (st.kind === 'edition' ? ROLES[ch] : 'ch' + (ch + 1)) + ' · ' + esc(instName(ch, rollData.prog[ch]))) + '</span>').join('');
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
  if (layer && (isChip() || layerBank !== st.inst)) { synth.setProgram = setProgram0; layer.dispose(); layer = null; layerBank = -1; }
  if (!isChip() && !layer) { layer = Banks[st.inst].attach(synth, { maxVoices: 24 }); layerBank = st.inst; setProgram0 = synth.setProgram; synth.setProgram = (ch, p, ...r) => setProgram0.call(synth, ch, ch === 9 || !cur ? p : cur.orch[ch % cur.orch.length], ...r); }
  const m = cur.midi;
  synth.loadMIDI(m.buffer.slice(m.byteOffset, m.byteOffset + m.length));
  synth.setLoop(1); synth.setLoopEnd(synth.getPlayStatus().maxTick); synth.playMIDI(); playing = true;
}
function stop() { if (synth) synth.stopMIDI(); playing = false; draw(-1); }
function change() { show(); if (playing) start(); }
const setKind = (k) => { st.kind = k; change(); };
for (const k of ['song', 'name', 'check', 'edition']) $('t-' + k).onclick = () => setKind(k);
const step = (k, d) => { if (k === 'b') st.b = (st.b + d + N) % N; if (k === 'n') st.name = Math.max(1, Math.min(L.NAME_COUNT, st.name + d)); if (k === 'e') st.e = (st.e - 1 + d + NSTYLE * 2) % (NSTYLE * 2) + 1; if (k === 'p') st.p = Math.max(1, st.p + d); change(); };
$('b-prev').onclick = () => step('b', -1); $('b-next').onclick = () => step('b', 1);
$('n-prev').onclick = () => step('n', -1); $('n-next').onclick = () => step('n', 1);
$('e-prev').onclick = () => step('e', -1); $('e-next').onclick = () => step('e', 1);
$('p-prev').onclick = () => step('p', -1); $('p-next').onclick = () => step('p', 1);
$('play').onclick = start; $('stop').onclick = stop; $('mega').onclick = () => { st.mega = !st.mega; change(); }; $('inst').onclick = () => { st.inst = (st.inst + 1) % DATA.insts.length; change(); };
$('day').oninput = () => { st.day = +$('day').value; show(); }; $('day').onchange = () => { if (playing) start(); };
document.addEventListener('keydown', (ev) => {
  if (ev.target.tagName === 'INPUT' || ev.metaKey || ev.ctrlKey) return;
  if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); }
  else if (ev.key === 'ArrowLeft' || ev.key === 'ArrowRight') step('b', ev.key === 'ArrowRight' ? 1 : -1);
  else if (ev.key === 'ArrowUp' || ev.key === 'ArrowDown') { ev.preventDefault(); step('e', ev.key === 'ArrowDown' ? 1 : -1); }
  else if (ev.key === '[' || ev.key === ']') step('p', ev.key === ']' ? 1 : -1);
  else if (ev.key === 'm') { st.mega = !st.mega; change(); }
});
show();
</script></body></html>`;
mkdirSync(new URL('../public/', import.meta.url), { recursive: true });
writeFileSync(new URL('../public/' + outName, import.meta.url), html);
console.log(outName, html.length, 'bytes');

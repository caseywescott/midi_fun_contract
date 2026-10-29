// Build public/onchain/editions-onchain.html: Monthly Track Editions as BeastPureComposer plays them.
// A purchase from edition 1 is ComposerInputs::Edition (species, edition, the purchase hash's low 64
// bits); compose() returns the style engine's MIDI (src/editions_lite.js, byte for byte the Cairo
// editions.cairo) and edition_synth_settings(style, type, mega) (synth_settings.mjs
// editionSynthSettings, each value's Serde hash checked here against the contract's
// EDITION_SERDE_HASHES). The page installs those settings with onchain-midi-player's own
// player/settings.js on its pinned engine, and can switch back to the family-only settings the
// composer served before, to hear the difference. Drift: compose_staff plays the edition on a staff
// (src/evolution.js resolveEvolution, byte for byte the Cairo, from simulated block hashes and the
// manager's test evolution config): the pad of tiers 3-5 can unlock at milestones and stays, and
// every staff block performs the notes and nudges the tempo.
//   node onchain/editions-onchain-demo.mjs <webaudio-tinysynth-4bf9829.min.js> <onchain-midi-player checkout>
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { keccak } from '@scure/starknet';
import { beastName, poseidonHashMany } from '../src/index.js';
import { speciesRecords } from './editions_cairo.mjs';
import { spriteSheet } from './lab-sprites.mjs';
import { loadBank } from './tinychip/essentials.mjs';
import { beastPrograms, beastSynthSettings, editionSynthSettings, serializeSettings } from './tinychip/synth_settings.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const [engineFile, omp] = process.argv.slice(2);
if (!engineFile || !omp) { console.error('usage: node onchain/editions-onchain-demo.mjs <engine .min.js> <onchain-midi-player checkout>'); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
const bundle = (await build({
  stdin: {
    contents: `import * as ed from './src/editions_lite.js'; import { encodeInputs } from './src/inputs.js';
      import { resolveEvolution, milestoneBlocks } from './src/evolution.js'; import { labBlockHash } from './src/lab.js';
      import { installSettings } from ${JSON.stringify(omp + '/player/settings.js')};
      window.BS = { ed, encodeInputs, installSettings, resolveEvolution, milestoneBlocks, labBlockHash };`,
    resolveDir: here + '..', loader: 'js',
  },
  bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;

// The contract's constants, read from the generated Cairo: the page shows each settings value's hash
// next to the one the contract carries, and refuses to build if any differs.
const cairo = readFileSync(here + '../../../beasts/beast_contracts/src/synth_settings.cairo', 'utf8');
const CAIRO_HASHES = cairo.match(/EDITION_SERDE_HASHES: \[felt252; 24\] = \[([^\]]+)\]/)[1].split(',').map((s) => s.trim());
const hash = (s) => '0x' + poseidonHashMany(serializeSettings(s)).toString(16);
const SETTINGS = [];
for (let style = 0; style < 4; style++) for (let t = 0; t < 3; t++) for (const mega of [false, true]) {
  const s = editionSynthSettings(style, t, mega), i = (style * 3 + t) * 2 + (mega ? 1 : 0);
  if (hash(s) !== CAIRO_HASHES[i]) throw new Error(`edition settings ${style}/${t}/${mega}: generator and contract differ`);
  SETTINGS[i] = { s, hash: CAIRO_HASHES[i] };
}
const FAMILY = [0, 1, 2].flatMap((t) => [false, true].map((mega) => beastSynthSettings(undefined, beastPrograms(t, mega))));
const bank = loadBank();
const NAMES = Object.fromEntries(bank.PRESETS.map((p, i) => [p.program ?? i, p.name]));
const SPECIES = speciesRecords().map((s) => ({ ...s, name: beastName({ id: s.id, prefix: 0, suffix: 0 }) }));
const SPRITES = Object.fromEntries(SPECIES.flatMap((s) => [String(s.id), s.id + 's']).map((k) => { const { n, w, png } = spriteSheet(k); return [k, { n, w, png }]; }));
// The Sound Manager's drift group of an unnamed Beast: poseidon(selector!("beasts_named_drift_v1"),
// species, name 0) (stored_purchase.cairo named_group), and its test evolution config
// (originals_tests.cairo sample_evolution_config).
const GROUP_SELECTOR = keccak(new TextEncoder().encode('beasts_named_drift_v1'));
const GROUPS = SPECIES.map((s) => '0x' + poseidonHashMany([GROUP_SELECTOR, BigInt(s.id), 0n]).toString(16));
const EVOLUTION = { first_milestone_age: 5, initial_unlock_bps: 1000, unlock_step_bps: 500, max_extra_channels: 2, max_tempo_delta_bpm: 4, max_velocity_delta: 16, ornament_chance_bps: 1000 };
const DATA = { species: SPECIES, types: ['Magic', 'Hunter', 'Brute'], settings: SETTINGS, family: FAMILY, names: NAMES, groups: GROUPS, evolution: EVOLUTION };

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Editions Onchain</title>
<link rel="icon" href="data:,">
<meta name="description" content="Monthly Track Editions as BeastPureComposer plays them: the style engine's MIDI and each style's TinyChip presets, installed the way onchain-midi-player installs them.">
<style>
:root{--bg:#f6f4ef;--fg:#1d1b18;--mut:#6b655c;--card:#fff;--line:#e2ddd3;--acc:#7a3cff;--ok:#1f9d55;--warn:#c08a00}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--warn:#f0c040}}
:root[data-theme="dark"]{--bg:#15141a;--fg:#ece8f4;--mut:#9a94a8;--card:#1f1d26;--line:#2e2b38;--acc:#a77bff;--ok:#3ccf7e;--warn:#f0c040}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1080px;margin:0 auto;padding:24px 16px 48px}h1{font-size:22px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 18px;max-width:780px}
.grid{display:grid;grid-template-columns:minmax(0,1fr) 360px;gap:14px}@media(max-width:880px){.grid{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px;min-width:0}
.stepper{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;margin-bottom:12px}
.stepper .mid{text-align:center;min-width:0}.lbl,.sec{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}.stepper .val{font-weight:650;font-size:17px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.stepper .val small{font-weight:400;color:var(--mut);font-size:13px}
.sec{margin:0 0 8px}
button,select{font:inherit;cursor:pointer}button.nav{width:44px;height:44px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:18px}
.ctl{display:flex;gap:10px;flex-wrap:wrap}.ctl button,.ctl select{flex:1;min-width:130px;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600}
.ctl button.go{background:var(--fg);color:var(--bg)}
.seg{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:10px}.seg button{padding:9px;border-radius:10px;border:2px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600;font-size:13.5px}.seg button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 14%,var(--bg))}
.ed-head{display:grid;grid-template-columns:96px 1fr;gap:14px;align-items:center}
#art{width:96px;height:96px;border-radius:10px;background:#000;image-rendering:pixelated;background-repeat:no-repeat}
.ename{font-size:22px;font-weight:700;margin:0}.emonth{color:var(--acc);font-weight:600;font-size:14px}.edesc{color:var(--mut);font-size:14px;margin:2px 0 0}
dl{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:4px 12px;margin:12px 0 0;font-size:13px}dt{color:var(--mut)}dd{margin:0;font-family:ui-monospace,monospace;font-size:12.5px;overflow-wrap:anywhere}
#roll{width:100%;height:220px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card))}
.legend{display:flex;flex-wrap:wrap;gap:4px 12px;margin-top:8px;font-size:12px}.legend i{width:10px;height:10px;border-radius:3px;display:inline-block;margin-right:5px;vertical-align:-1px}
.flow{display:grid;gap:8px;font-size:13px}.flow div{border-left:3px solid var(--acc);padding:2px 0 2px 10px}.flow code{font:12px ui-monospace,monospace;overflow-wrap:anywhere}
.ok{color:var(--ok);font-weight:650}.badge{display:inline-block;border-radius:6px;padding:0 6px;font-size:12px;font-weight:650;border:1px solid currentColor}
.presets{display:grid;gap:4px;font-size:13px}.presets div{display:grid;grid-template-columns:70px 1fr auto;gap:8px;align-items:baseline}.presets .r{color:var(--mut);font-size:12px}.presets .p{font:12px ui-monospace,monospace;color:var(--mut)}.presets .off{opacity:.5}
.list{display:grid;gap:4px;max-height:420px;overflow:auto}.row{display:grid;grid-template-columns:30px 1fr;gap:8px;align-items:center;padding:6px 8px;border:1px solid var(--line);border-radius:8px;background:var(--bg);cursor:pointer;text-align:left;color:var(--fg)}
.row.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 13%,var(--bg))}.row .n{font:12px ui-monospace,monospace;color:var(--mut)}.row b{font-size:13.5px;display:block}.row small{color:var(--mut);font-size:12px}
.note{font-size:12.5px;color:var(--mut);margin:8px 0 0}
.age{display:block;font-size:13px;margin-top:12px}.age input{width:100%;margin-top:6px;accent-color:var(--acc)}
.miles{position:relative;height:30px;margin-top:4px}.miles span{position:absolute;top:4px;width:12px;height:12px;margin-left:-6px;border-radius:50%;border:2px solid var(--line);background:var(--bg)}
.miles span.hit{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 30%,var(--bg))}.miles span.unlock{background:var(--ok);border-color:var(--ok)}
.miles i{position:absolute;top:0;bottom:0;width:2px;margin-left:-1px;background:var(--fg)}.kbd{font:11px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 4px}
a{color:var(--acc)}
</style></head><body><main>
<h1>Monthly Track Editions, onchain</h1>
<p class="sub">From edition 1, a track bought for a Beast is played by that edition's style engine, and in Live mode it drifts as blocks go by. The style is waltz, chorale, lullaby or dirge, taking turns, and it plays the species' theme with the instruments chosen for that style. This page plays exactly what the Beast composer contract returns. The MIDI is byte for byte the contract's, and the instruments are the contract's own settings. Both are installed the way onchain-midi-player installs them.</p>
<div class="grid"><div>
<div class="card">
<div class="stepper"><button class="nav" id="e-prev" title="Previous edition (↑)">▲</button><div class="mid"><div class="lbl">Edition</div><div class="val" id="e-val"></div></div><button class="nav" id="e-next" title="Next edition (↓)">▼</button></div>
<div class="stepper"><button class="nav" id="b-prev" title="Previous Beast (←)">◀</button><div class="mid"><div class="lbl">Beast</div><div class="val" id="b-val"></div></div><button class="nav" id="b-next" title="Next Beast (→)">▶</button></div>
<div class="stepper"><button class="nav" id="s-prev" title="Previous purchase ([)">−</button><div class="mid"><div class="lbl">Purchase seed</div><div class="val" id="s-val"></div></div><button class="nav" id="s-next" title="Next purchase (])">+</button></div>
<div class="ctl"><select id="fx" aria-label="Sound effect"><option value="0">Sound effect 0: as written</option><option value="1">Sound effect 1: mega leads</option><option value="2">Sound effect 2: no change for editions</option><option value="3">Sound effect 3: mega leads</option></select></div>
<div class="seg" role="group" aria-label="Instruments"><button id="i-new" class="on">Edition presets</button><button id="i-old">Before: family settings only</button></div>
<div class="ctl" style="margin-top:12px"><button class="go" id="play">▶ Play</button><button id="stop">■ Stop</button></div>
</div>
<div class="card"><div class="sec">Drift</div>
<div class="seg" role="group" aria-label="Sound mode"><button id="m-orig">Original: as written</button><button id="m-live" class="on">Live: on a staff</button></div>
<label class="age">Staff block: <b id="age-val"></b><input type="range" id="age" min="0" max="1000" value="274" aria-label="Staff block"></label>
<div class="miles" id="miles" aria-hidden="true"></div>
<div class="ctl"><button id="lapse">▶ Time-lapse</button></div>
<dl id="drift"></dl>
<p class="note">The settings are the Sound Manager's test evolution config. Milestones fall 5, 10, 20 … 640 blocks after the purchase. At each one the pad of a tier 3 to 5 Beast can unlock with a 10% chance, rising 5% per milestone, and once unlocked it stays. Every staff block also re-performs the notes (velocity ±16, a 10% chance of an octave second half) and nudges the tempo by up to 4 BPM. Live mode plays the block 10 before the current one, and Original mode plays the track as written. Block hashes are simulated.</p>
<p class="note">Keys: <span class="kbd">↑</span> <span class="kbd">↓</span> edition · <span class="kbd">←</span> <span class="kbd">→</span> Beast · <span class="kbd">[</span> <span class="kbd">]</span> purchase · <span class="kbd">i</span> instruments · <span class="kbd">,</span> <span class="kbd">.</span> staff block · <span class="kbd">space</span> play/stop. Changes play straight away while playing.</p>
</div>
<div class="card"><div class="ed-head"><div id="art" role="img" aria-label=""></div><div><div class="emonth" id="emonth"></div><p class="ename" id="ename"></p><p class="edesc" id="edesc"></p></div></div><dl id="info"></dl></div>
<div class="card"><canvas id="roll" width="1600" height="440"></canvas><div class="legend" id="legend"></div></div>
</div><div>
<div class="card"><div class="sec">What the contracts do</div><div class="flow" id="flow"></div></div>
<div class="card"><div class="sec">Instruments in the returned settings</div><div class="presets" id="presets"></div><p class="note" id="setnote"></p></div>
<div class="card"><div class="sec">Calendar</div><div class="list" id="list"></div>
<p class="note">Edition 0's purchases are bought songs from the Beast's own composer, not shown here. From edition 1 the four styles take turns, and each pass through them changes the mode, tempo and form. An edition is a period on the Sound Manager's edition clock; the months here are the editions page's calendar.</p></div>
</div></div>
<p class="note"><a href="../">All pages</a> · <a href="editions.html">Editions prototype</a></p>
</main>
<script>${inline(tiny)}</script>
<script>${inline(bundle)}</script>
<script>
const DATA = ${JSON.stringify(DATA)};
const SPRITES = ${JSON.stringify(SPRITES)};
const $ = (id) => document.getElementById(id), ED = BS.ed, N_ED = 48, U64 = (1n << 64n) - 1n;
// the default: a tier 5 Beast whose first purchase unlocks its pad at the third milestone (20 blocks)
const st = { e: 1, s: 20, n: 1, fx: 0, presets: true, live: true, age: 5 };
let lapse = 0;
let synth = null, playing = false, rollData = null, cur = null;

(function readUrl() { const q = new URLSearchParams(location.search); if (q.has('e')) st.e = Math.max(1, Math.min(N_ED, +q.get('e') || 1)); if (q.has('b')) st.s = Math.max(0, Math.min(74, (+q.get('b') || 1) - 1)); if (q.has('p')) st.n = Math.max(1, +q.get('p') || 1); if (q.has('fx')) st.fx = Math.max(0, Math.min(3, +q.get('fx') || 0)); st.presets = q.get('i') !== 'before'; if (q.has('mode')) st.live = q.get('mode') !== 'original'; if (q.has('age')) st.age = Math.max(0, Math.min(700, +q.get('age') || 0)); })();
function writeUrl() { const q = new URLSearchParams({ e: st.e, b: st.s + 1, p: st.n, fx: st.fx, mode: st.live ? 'live' : 'original', age: st.age }); if (!st.presets) q.set('i', 'before'); history.replaceState(null, '', '?' + q); }

// A stand-in purchase: the manager seeds generate_inputs with a purchase hash; the generator keeps
// its low 64 bits. Here purchase n's hash is a fixed mix of n (no chain needed).
function purchaseSeed(n) { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); }
const mega = () => st.fx === 1 || st.fx === 3;

// A stand-in chain: purchase n is bought at block 1,000,000 + 1000 n; block hashes are the lab's.
const birthOf = (n) => 1000000n + 1000n * BigInt(n);
function staffAt(sp, birth, age) {
  return BS.resolveEvolution(DATA.evolution, { birth, staff: birth + BigInt(age), driftGroup: DATA.groups[sp.id - 1], hashOf: BS.labBlockHash }, sp.tier > 2 ? 1 : 0);
}
function compose() {
  const sp = DATA.species[st.s], seed = purchaseSeed(st.n), g = ED.editionGenome(st.e), birth = birthOf(st.n);
  const staff = st.live ? staffAt(sp, birth, st.age) : null;
  const written = ED.editionMidi(sp, mega(), st.e, seed);
  const out = staff ? ED.editionMidi(sp, mega(), st.e, seed, staff) : written;
  const i = (g.style * 3 + sp.type) * 2 + (mega() ? 1 : 0);
  const settings = st.presets ? DATA.settings[i].s : DATA.family[sp.type * 2 + (mega() ? 1 : 0)];
  const wire = BS.encodeInputs({ kind: 'Edition', edition: { identity: { source_species_id: BigInt(sp.id), name_variant_id: 0 }, edition: st.e, seed } });
  // the milestone (index) at which the pad unlocked, if it has
  let unlockAt = -1;
  if (staff && sp.tier > 2 && staff.unlocked_extra_mask % 2) unlockAt = staff.milestones.findIndex((m) => staffAt(sp, birth, Number(m.block - birth)).unlocked_extra_mask % 2 === 1);
  return { ...out, written: written.midi, sp, seed, g, i, settings, wire, staff, birth, unlockAt };
}

const ROLE = { 0: 'lead', 2: 'accomp', 3: 'bass', 4: 'pad', 5: 'mega double' };
const COLORS = ['#7a3cff', '#e0742a', '#1f9d8c', '#c0392b', '#7f8c8d', '#2a7ae0'];
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
function show() {
  cur = compose();
  const { sp, g, info } = cur;
  $('e-val').innerHTML = st.e + ' · ' + esc(g.name) + ' <small>' + g.month + '</small>';
  $('b-val').innerHTML = sp.id + '. ' + esc(sp.name) + ' <small>tier ' + sp.tier + ' ' + DATA.types[sp.type] + '</small>';
  $('s-val').innerHTML = '#' + st.n + ' <small>0x' + cur.seed.toString(16).padStart(16, '0') + '</small>';
  $('emonth').textContent = 'Edition ' + st.e + ' · ' + g.month;
  $('ename').textContent = g.name; $('edesc').textContent = ED.ENGINES[g.engine].desc || ED.ENGINES[g.engine].label;
  $('info').innerHTML = [['Style', ED.ENGINES[g.engine].label], ['Key', info.key], ['Meter / tempo', info.meter + ' · ' + info.bpm + ' BPM'], ['Form', info.form], ['Harmony', info.grammar], ['Progressions', 'A: ' + info.progA + '   B: ' + info.progB]]
    .filter(([, v]) => v !== undefined).map(([a, b]) => '<dt>' + a + '</dt><dd>' + esc(b) + '</dd>').join('');
  const wire = '[' + cur.wire.map((v) => v > 0xffffffffn ? '0x' + v.toString(16) : v.toString()).join(', ') + ']';
  $('flow').innerHTML = [
    '<b>Purchase</b> in edition ' + st.e + ', for species ' + sp.id + '. <code>generate_inputs(base, ' + st.e + ', purchase hash)</code> returns an Edition. The seed is the hash\\'s low 64 bits.',
    '<b>ComposerInputs</b> on the wire (codec 5, Edition = tag 2): <code>' + wire + '</code>',
    (cur.staff ? '<b>compose_staff(inputs, ' + st.fx + ', config, context)</b> at staff block ' + (cur.birth + BigInt(st.age)) + ' (' + cur.staff.milestones.length + ' milestones reached) returns ' : '<b>compose(inputs, ' + st.fx + ')</b> returns ') + cur.midi.length + ' bytes of MIDI from the ' + ED.ENGINES[g.engine].label.toLowerCase() + ' engine and <code>edition_synth_settings(' + g.style + ', ' + sp.type + ', ' + mega() + ')</code>.',
    '<b>Settings hash</b> <code>' + DATA.settings[cur.i].hash.slice(0, 18) + '…</code> <span class="badge ok">matches the contract</span>',
  ].map((x) => '<div>' + x + '</div>').join('');
  const prog = notesOf(cur.midi).prog, slots = new Set(cur.settings.timbres.filter((t) => !t.drum).map((t) => t.slot));
  $('presets').innerHTML = Object.entries(prog).map(([ch, p]) => '<div class="' + (slots.has(p) ? '' : 'off') + '"><span class="r">' + (ROLE[ch] || 'ch' + (+ch + 1)) + '</span><span>' + esc(DATA.names[p] || 'program ' + p) + '</span><span class="p">' + p + (slots.has(p) ? '' : ' · built-in') + '</span></div>').join('');
  $('setnote').textContent = st.presets
    ? 'These settings carry ' + cur.settings.timbres.length + ' TinyChip presets and ' + cur.settings.waves.length + ' sampled chip waves. Every program the file selects has its own preset.'
    : 'Before: the family settings (' + cur.settings.timbres.filter((t) => !t.drum).length + ' presets). The faded programs are not in them, so TinySynth plays its built-in General MIDI sounds instead.';
  $('i-new').classList.toggle('on', st.presets); $('i-old').classList.toggle('on', !st.presets);
  drift();
  $('fx').value = String(st.fx);
  art(sp); list(); roll(cur.midi); writeUrl();
}
// the staff block on a log scale: each milestone (5 x 2^k blocks) gets about the same room
const AGE_MAX = 700, toAge = (v) => Math.round(Math.exp(v / 1000 * Math.log(AGE_MAX + 1)) - 1), toPos = (a) => Math.log(a + 1) / Math.log(AGE_MAX + 1);
function counts(midi) { const c = {}; for (const n of notesOf(midi).notes) c[n[3]] = (c[n[3]] || 0) + 1; return c; }
function drift() {
  $('m-orig').classList.toggle('on', !st.live); $('m-live').classList.toggle('on', st.live);
  $('age').value = Math.round(toPos(st.age) * 1000); $('age').disabled = !st.live; $('lapse').disabled = !st.live;
  $('age-val').textContent = st.live ? st.age + ' blocks after the purchase' : 'none (Original)';
  const sp = cur.sp, M = $('miles');
  M.innerHTML = Array.from({ length: 8 }, (_, k) => 5 * 2 ** k).map((a, k) => '<span style="left:' + (toPos(a) * 100) + '%" class="' + (st.live && a <= st.age ? 'hit' : '') + (k === cur.unlockAt ? ' unlock' : '') + '" title="milestone ' + (k + 1) + ': ' + a + ' blocks"></span>').join('') + (st.live ? '<i style="left:' + (toPos(st.age) * 100) + '%"></i>' : '');
  if (!cur.staff) { $('drift').innerHTML = '<dt>Staff</dt><dd>none: the track as written</dd>'; return; }
  const w = counts(cur.written), d = counts(cur.midi), padAdded = (d[4] || 0) - (w[4] || 0);
  let orn = 0; for (const ch of Object.keys(d)) if (+ch !== 4 || w[4]) orn += d[ch] - (w[ch] || 0);
  const pad = sp.tier <= 2 ? 'plays as written (tier ' + sp.tier + ')' : cur.staff.unlocked_extra_mask % 2 ? 'unlocked at milestone ' + (cur.unlockAt + 1) + ' (' + 5 * 2 ** cur.unlockAt + ' blocks): +' + padAdded + ' notes' : 'locked (tier ' + sp.tier + '; ' + cur.staff.milestones.length + ' of 8 milestones rolled)';
  const rows = [['Milestones', cur.staff.milestones.length + ' of 8 reached'], ['Pad', pad], ['Tempo', (cur.staff.tempo_delta >= 0 ? '+' : '') + cur.staff.tempo_delta + ' BPM (' + cur.info.bpm + ' written)'], ['Octave ornaments', orn + ' notes this block'], ['Velocity drift', '±' + cur.staff.max_velocity_delta + ' per note'], ['Note seed', '0x' + cur.staff.note_seed.toString(16).slice(0, 16) + '…']];
  $('drift').innerHTML = rows.map(([a, b]) => '<dt>' + a + '</dt><dd>' + esc(b) + '</dd>').join('');
}
function art(sp) {
  const s = SPRITES[sp.id + (mega() ? 's' : '')] || SPRITES[String(sp.id)], el = $('art');
  el.style.backgroundImage = 'url(data:image/png;base64,' + s.png + ')';
  el.style.backgroundSize = (s.n * 96) + 'px 96px';
  el.setAttribute('aria-label', sp.name);
  el.getAnimations().forEach((a) => a.cancel());
  const bpm = (cur && cur.info.bpm) || 120, frames = Array.from({ length: s.n }, (_, f) => ({ backgroundPosition: (-f * 96) + 'px 0' }));
  if (s.n > 1) el.animate(frames, { duration: s.n * 60000 / bpm / 2, iterations: Infinity, easing: 'steps(' + s.n + ', jump-none)' });
}
function list() {
  const L = $('list');
  if (!L.children.length) for (let e = 1; e <= N_ED; e++) { const g = ED.editionGenome(e), b = document.createElement('button'); b.className = 'row'; b.dataset.e = e; b.innerHTML = '<span class="n">' + e + '</span><span><b>' + esc(g.name) + '</b><small>' + g.month + ' · ' + ED.ENGINES[g.engine].label + '</small></span>'; b.onclick = () => { st.e = e; change(); }; L.appendChild(b); }
  [...L.children].forEach((b) => b.classList.toggle('on', +b.dataset.e === st.e));
  const on = L.querySelector('.row.on'); if (on) on.scrollIntoView({ block: 'nearest' });
}

function notesOf(u8) {
  const notes = [], prog = {}; let tpq = (u8[12] << 8) | u8[13], end = 0, i = 14, ntr = (u8[10] << 8) | u8[11];
  for (let tr = 0; tr < ntr; tr++) {
    i += 4; const len = (u8[i] << 24 | u8[i + 1] << 16 | u8[i + 2] << 8 | u8[i + 3]) >>> 0; i += 4; const stop = i + len; let t = 0, run = 0; const on = {};
    while (i < stop) {
      let d = 0, b; do { b = u8[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d;
      let s = u8[i]; if (s & 128) i++; else s = run;
      if (s === 0xff) { const ty = u8[i++]; let l = 0; do { b = u8[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; if (ty === 0x2f) end = Math.max(end, t); continue; }
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
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + COLORS[ch % 6] + '"></i>' + (ROLE[ch] || 'ch' + (ch + 1)) + ' · ' + esc(DATA.names[rollData.prog[ch]] || '') + '</span>').join('');
  draw(-1);
}
function draw(play) {
  const c = $('roll'), x = c.getContext('2d'), W = c.width, H = c.height, d = rollData; x.clearRect(0, 0, W, H); if (!d || !d.notes.length) return;
  const lo = Math.min(...d.notes.map((n) => n[2])) - 2, hi = Math.max(...d.notes.map((n) => n[2])) + 2, top = 6, ph = H - 12, sx = W / d.end;
  const fg = getComputedStyle(document.body).color;
  const [mn, md] = String(cur.info.meter || '4/4').split('/').map(Number), bar = d.tpq * 4 * mn / md;
  x.globalAlpha = 0.12; x.fillStyle = fg; for (let t = 0; t < d.end; t += bar) x.fillRect(t * sx, 0, 1, H); x.globalAlpha = 1;
  for (const [a, b, p, ch] of d.notes) { x.fillStyle = COLORS[ch % 6]; x.fillRect(a * sx, top + (hi - p) / (hi - lo) * ph, Math.max(2, (b - a) * sx - 1), Math.max(3, ph / (hi - lo) - 1)); }
  if (play >= 0) { x.fillStyle = fg; x.fillRect((play % d.end) * sx, 0, 3, H); }
}
(function loop() { if (playing && synth && synth.tick2Time) { const t = synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time; draw(t); } requestAnimationFrame(loop); })();

// The engine, with the returned settings installed by onchain-midi-player's own installSettings
// (custom waves, quality, which resets every program to the built-ins, volume, reverb, voices, then
// each timbre).
function start() {
  if (!synth) synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  synth.getAudioContext().resume(); synth.stopMIDI();
  BS.installSettings(synth, cur.settings);
  const m = cur.midi;
  synth.loadMIDI(m.buffer.slice(m.byteOffset, m.byteOffset + m.length));
  synth.setLoop(1); synth.setLoopEnd(synth.getPlayStatus().maxTick); synth.playMIDI(); playing = true;
}
function stop() { if (synth) synth.stopMIDI(); playing = false; clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; draw(-1); }
// the time-lapse: the staff block moves on every few seconds, faster as the milestones spread out
function toggleLapse() {
  if (lapse) { clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; return; }
  if (!st.live) return;
  if (st.age >= 700) st.age = 0;
  if (!playing) { show(); start(); }
  $('lapse').textContent = '■ Stop time-lapse';
  lapse = setInterval(() => { st.age = Math.min(700, st.age + Math.max(1, Math.round(st.age / 6))); show(); start(); if (st.age >= 700) { clearInterval(lapse); lapse = 0; $('lapse').textContent = '▶ Time-lapse'; } }, 5000);
}
function change() { show(); if (playing) start(); }

const step = (k, d) => { if (k === 'e') st.e = (st.e - 1 + d + N_ED) % N_ED + 1; if (k === 's') st.s = (st.s + d + 75) % 75; if (k === 'n') st.n = Math.max(1, st.n + d); change(); };
$('e-prev').onclick = () => step('e', -1); $('e-next').onclick = () => step('e', 1);
$('b-prev').onclick = () => step('s', -1); $('b-next').onclick = () => step('s', 1);
$('s-prev').onclick = () => step('n', -1); $('s-next').onclick = () => step('n', 1);
$('fx').onchange = () => { st.fx = +$('fx').value; change(); };
$('i-new').onclick = () => { st.presets = true; change(); }; $('i-old').onclick = () => { st.presets = false; change(); };
$('play').onclick = start; $('stop').onclick = stop;
$('m-orig').onclick = () => { st.live = false; change(); }; $('m-live').onclick = () => { st.live = true; change(); };
$('age').oninput = () => { st.age = toAge(+$('age').value); show(); }; $('age').onchange = () => { if (playing) start(); };
$('lapse').onclick = toggleLapse;
document.addEventListener('keydown', (ev) => {
  if (ev.target.tagName === 'SELECT' || ev.metaKey || ev.ctrlKey) return;
  const k = { ArrowUp: ['e', -1], ArrowDown: ['e', 1], ArrowLeft: ['s', -1], ArrowRight: ['s', 1], '[': ['n', -1], ']': ['n', 1] }[ev.key];
  if (k) { ev.preventDefault(); step(...k); } else if ((ev.key === ',' || ev.key === '.') && st.live) { st.age = Math.max(0, Math.min(700, st.age + (ev.key === '.' ? 1 : -1))); change(); } else if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); } else if (ev.key === 'i') { st.presets = !st.presets; change(); }
});
show();
</script></body></html>`;
writeFileSync(new URL('../public/onchain/editions-onchain.html', import.meta.url), html);
console.log('editions-onchain.html', html.length, 'bytes; settings hashes match the contract (24/24)');

// Build public/onchain/beatsync.html: animated Beast art stepped with its music by BeatSync.
//   node onchain/beatsync-demo.mjs        (after onchain/gallery.mjs)
//
// Beasts: the Warlock (demo stats) and every gallery Beast. Five gallery Beasts are minted animated;
// the others are static and are shown with their species' GIF (onchain/fixtures/beast_gifs.json, the
// GIFs from the Beasts art contracts), as they'd look if animated. Gallery SVGs are fetched when picked.
// Each Beast's onchain MIDI plays through tinysynth with TinyChip: Auto uses the onchain orchestration
// (PR #3's runtime), or any preset of the full bank. BeatSync
// (onchain/beatsync.js, the module in the onchain page player) decodes the Beast's GIF and shows the
// frame due at the audible tinysynth tick. The toggle compares 'beat' (one frame per eighth note),
// 'native' (the GIF's own delays on the audio clock) and 'off' (the browser's own GIF timer), and a
// second panel always shows the browser's GIF for comparison.
import { readFileSync, writeFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { composeBeast, decodeTokenId } from '../src/index.js';
import { loadBuiltModules } from './modules.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = here + '../public/onchain/';
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const minify = async (src) => (await build({ stdin: { contents: src, loader: 'js' }, minify: true, write: false, logLevel: 'error' })).outputFiles[0].text;

const tinySrc = await (await fetch('https://cdn.jsdelivr.net/gh/g200kg/webaudio-tinysynth@master/webaudio-tinysynth.js')).text();
const tiny = await minify(tinySrc);
const TINY_NOTICE = '/*! webaudio-tinysynth (c) g200kg, Apache License 2.0, https://github.com/g200kg/webaudio-tinysynth */';
// TinyChip as PR #3 builds it: the onchain runtime (orchestration) and the full bank (manual presets)
const chipRuntime = readFileSync(here + 'pr3-tinychip/tinychip.min.js', 'utf8').trim();
const chipBank = readFileSync(here + 'pr3-tinychip/tinychip-bank.min.js', 'utf8').trim();
const beatsync = await minify(readFileSync(here + 'beatsync.js', 'utf8'));
const midiModules = loadBuiltModules(['midi', 'smf']);

const bankCtx = {}; vm.runInNewContext(chipBank, bankCtx);
const CHIP_PRESETS = bankCtx.TinyChipBank.PRESETS.map(({ program, name, category, inspired }) => ({ program, name, category, inspired }));
const INSPIRED = Object.fromEntries(CHIP_PRESETS.filter((p) => p.inspired).map((p) => [p.program, p.inspired]));

const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));
const cache = JSON.parse(readFileSync(here + '.gallery-cache.json', 'utf8'));
const gallery = JSON.parse(readFileSync(out + 'gallery.json', 'utf8'));
const allGifs = JSON.parse(readFileSync(here + 'fixtures/beast_gifs.json', 'utf8'));
const midiOf = (song) => ({ midi: Buffer.from(song.midi).toString('base64'), notes: song.events.length });
const warlockSong = composeBeast(decodeTokenId(BigInt(fx.token_id)), { adventurers_killed: 412, scars: 7, summit_held_seconds: 86400, rank: 3, species_count: 1243 });
const data = [
  { name: `${fx.name} (demo stats)`, svg: Buffer.from(fx.svg_b64, 'base64').toString('utf8'), animated: 1, ...midiOf(warlockSong) },
  ...gallery
    .map((g) => {
      const { beast, live } = cache[g.token];
      return { name: `${g.name} #${g.token}`, token: g.token, animated: beast.animated, gif: beast.animated ? undefined : `${beast.id}${beast.shiny ? 's' : ''}`, ...midiOf(composeBeast(beast, live)) };
    })
    .sort((a, b) => b.animated - a.animated || a.name.localeCompare(b.name)),
];
const GIFS = Object.fromEntries([...new Set(data.map((b) => b.gif).filter(Boolean))].map((k) => [k, allGifs[k]]));

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beast BeatSync</title>
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
.layout{display:grid;grid-template-columns:minmax(0,340px) minmax(0,1fr);gap:24px;margin-top:24px;align-items:start}
.arts{display:grid;gap:12px}
.art{background:var(--card);border:1px solid var(--line);padding:10px;display:grid}
.art .stack{display:grid}.art .stack img{grid-area:1/1;display:block;width:100%;height:auto}
.art small{font-size:17px;color:var(--dim);margin-top:6px}
.ref{display:grid;grid-template-columns:96px 1fr;gap:12px;align-items:center}
.panel{display:grid;gap:18px}
fieldset{margin:0;min-width:0;border:1px solid var(--line);padding:12px 14px 14px;display:grid;gap:10px}
legend{padding:0 6px;font-size:18px;color:var(--dim);text-transform:uppercase}
.choices{display:flex;flex-wrap:wrap;gap:8px}
.choices button,.controls button{font:inherit;font-size:20px;padding:6px 14px;background:transparent;color:var(--g);border:1px solid var(--line);cursor:pointer}
.choices button[aria-pressed="true"]{background:var(--g);color:#000}
.controls{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
.controls #play{background:var(--g);color:#000;min-width:120px}
select{font:inherit;font-size:20px;background:#000;color:var(--g);border:1px solid var(--line);padding:4px 8px;width:100%;min-width:0}
label.check{display:flex;gap:8px;align-items:center;font-size:20px}
label.field{display:grid;gap:6px;font-size:18px;color:var(--dim)}
.strip{display:flex;flex-wrap:wrap;gap:8px}
.strip canvas{width:64px;height:64px;image-rendering:pixelated;border:2px solid var(--line);background:var(--card)}
.strip canvas.on{border-color:var(--g);box-shadow:0 0 10px rgba(74,246,38,.6)}
.beats{display:flex;gap:6px}.beats span{flex:1;height:14px;border:1px solid var(--line)}.beats span.on{background:var(--g)}
.facts{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:8px}
.fact{border:1px solid var(--line);padding:8px 10px}.fact b{display:block;font-weight:400;font-size:24px}.fact small{font-size:16px;color:var(--dim)}
.note{font-size:18px;color:var(--dim)}
[hidden]{display:none!important}
@media (max-width:720px){.layout{grid-template-columns:1fr}.arts{max-width:340px}}
</style></head><body><main>
<h1>Beast art on the beat</h1>
<p>Browsers give a page no control over a GIF's frames, so an animated Beast's GIF runs on its own timer and drifts against its music. BeatSync decodes the GIF from the token's SVG and shows the frame due at the moment you are hearing, taken from the synth's audio clock. Toggle the modes to compare. The small panel is always the browser's own GIF.</p>
<p>The Warlock and five gallery Beasts are minted animated. The other gallery Beasts are static, so they are shown with their species' animated GIF from the Beasts art contracts, as they would look minted animated. Their music is their own.</p>
<div class="layout">
  <div class="arts">
    <div class="art"><div class="stack"><img id="art" alt=""></div><small id="artLabel">BeatSync</small></div>
    <div class="art ref"><img id="ref" alt="" style="width:96px;height:auto"><small>Browser GIF (its own timer, for comparison)</small></div>
  </div>
  <div class="panel">
    <fieldset><legend>Beast (${data.length})</legend><select id="beast" aria-label="Beast">${[['Minted animated', 1], ['Static art, shown with its species GIF', 0]].map(([label, a]) => `<optgroup label="${label}">${data.map((b, i) => (b.animated === a ? `<option value="${i}">${esc(b.name)} (${b.notes} notes)</option>` : '')).join('')}</optgroup>`).join('')}</select></fieldset>
    <fieldset><legend>Chip patch</legend>
      <label class="field">TinyChip preset (${CHIP_PRESETS.length}) <select id="chipPreset"><option value="auto">Auto: the onchain orchestration (tinychip-2)</option>${[...new Set(CHIP_PRESETS.map((p) => p.category))].map((c) => `<optgroup label="${esc(c)}">${CHIP_PRESETS.filter((p) => p.category === c).map((p) => `<option value="${p.program}">${p.program}: ${esc(p.name)}</option>`).join('')}</optgroup>`).join('')}</select></label>
      <span class="note" id="chipInspired"></span>
      <div class="controls">
        <button type="button" id="prevPreset" aria-label="Previous preset">◀ Prev</button>
        <button type="button" id="nextPreset" aria-label="Next preset">Next ▶</button>
        <label class="check"><input type="checkbox" id="bassVoice" checked> Lowest voice on Triangle Bass</label>
      </div>
    </fieldset>
    <fieldset><legend>Frame timing</legend>
      <div class="choices" role="group" aria-label="Frame timing">
        <button type="button" data-mode="beat" aria-pressed="true">Beat-locked</button>
        <button type="button" data-mode="native" aria-pressed="false">Native timing</button>
        <button type="button" data-mode="off" aria-pressed="false">Off (browser GIF)</button>
      </div>
      <span class="note" id="modeNote"></span>
    </fieldset>
    <div class="controls">
      <button type="button" id="play">▶ Play</button>
      <label class="check"><input type="checkbox" id="drums" checked> Drums</label>
    </div>
    <fieldset><legend>Now showing</legend>
      <div class="strip" id="strip"></div>
      <div class="beats" id="beats" aria-hidden="true"><span></span><span></span><span></span><span></span><span></span><span></span><span></span><span></span></div>
      <span class="note" id="pos">Stopped: the art is the browser's GIF.</span>
    </fieldset>
    <div class="facts">
      <div class="fact"><b id="fFrames"></b><small>GIF frames</small></div>
      <div class="fact"><b id="fGif"></b><small>GIF loop</small></div>
      <div class="fact"><b id="fBeat"></b><small>frames on eighths</small></div>
      <div class="fact"><b id="fDrift"></b><small>browser GIF slip / loop</small></div>
    </div>
    <p class="note">Music: the Beast's onchain MIDI through webaudio-tinysynth with TinyChip: Auto plays the onchain page's orchestration (20 presets, one per voice); or pick any of the ${CHIP_PRESETS.length} presets in the full bank. Chip drums. BeatSync is ${(beatsync.length / 1000).toFixed(1)} KB, the same module the onchain page can store.</p>
  </div>
</div>
</main>
<script>${inline(midiModules.map((m) => m.js).join('\n'))}</script>
<script>${TINY_NOTICE}\n${inline(tiny)}</script>
<script>${inline(chipBank)}</script>
<script>${inline(chipRuntime)}</script>
<script>${inline(beatsync)}</script>
<script>
const BEASTS = ${JSON.stringify(data)};
const GIFS = ${JSON.stringify(GIFS)};
const INSPIRED = ${JSON.stringify(INSPIRED)};
const NAMES = ${JSON.stringify(Object.fromEntries(CHIP_PRESETS.map((p) => [p.program, p.name])))};
const BASS_PROGRAM = 20; // TinyChip: Triangle Bass (NES)
const v1 = BeastSound.v1;
const $ = (id) => document.getElementById(id);
const NOTES = { beat: 'One frame per eighth note, so the creature moves on the beat.', native: "The GIF's own frame delays, timed by the audio clock, so it never drifts.", off: "The browser's GIF timer, as on a marketplace: it drifts against the music." };
let current = 0, mode = 'beat', synth = null, playing = false, beat = null, strip = [], loading = 0;
const svgs = {};
const bytesOf = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const svgUri = (svg) => 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svg)));

// The chip engine's drum pattern as General MIDI drums (kick 36, snare 38, hats 42), played by the chip kit.
function withDrums(song) {
  const end = Math.max(...song.notes.map((n) => n[0] + n[1]));
  const bars = Math.ceil(end / 1920) * 1920, drums = [];
  for (let t = 0; t < bars; t += 240) {
    const b = t / 480, onBeat = t % 480 === 0;
    if (onBeat && b % 4 === 0) drums.push([t, 120, 36, 110, 9]);
    if (onBeat && b % 4 === 2) drums.push([t, 120, 38, 90, 9]);
    drums.push([t, 60, 42, onBeat ? 70 : 50, 9]);
  }
  return { notes: song.notes.concat(drums), tempo_us: song.tempo_us };
}

// A Beast's SVG: inline (Warlock), or fetched from the gallery; static art gets its species' GIF.
async function svgOf(b) {
  if (b.svg) return b.svg;
  if (!svgs[b.token]) {
    const svg = await (await fetch('beasts/' + b.token + '.svg')).text();
    svgs[b.token] = b.gif ? svg.replace(/data:image\\/png;base64,[A-Za-z0-9+/=]+/, 'data:image/gif;base64,' + GIFS[b.gif]) : svg;
  }
  return svgs[b.token];
}
async function load() {
  const b = BEASTS[current], me = ++loading;
  const svg = await svgOf(b);
  if (me !== loading) return false; // a later pick won
  if (beat) beat.detach();
  const old = $('art'), img = old.cloneNode();
  old.replaceWith(img);
  img.src = svgUri(svg);
  $('ref').src = img.src;
  beat = BeatSync.attach({ img, svg, mode, synth: () => synth });
  // the frame strip: each decoded frame, highlighted while it is the one shown
  const gif = BeatSync.decodeGif(bytesOf(/data:image\\/gif;base64,([A-Za-z0-9+/=]+)/.exec(svg)[1]));
  $('strip').replaceChildren(...(strip = gif.frames.map((f, i) => {
    const cv = document.createElement('canvas');
    cv.width = gif.width; cv.height = gif.height;
    cv.getContext('2d').putImageData(new ImageData(f.rgba, gif.width, gif.height), 0, 0);
    cv.title = 'frame ' + (i + 1) + ' · ' + f.delay + ' ms';
    return cv;
  })));
  const eighth = v1.smf.parse(b.midi).tempo_us / 2000, cycle = beat.delays.reduce((a, d) => a + d, 0), beatCycle = eighth * beat.frames;
  $('fFrames').textContent = beat.frames;
  $('fGif').textContent = cycle + ' ms';
  $('fBeat').textContent = Math.round(beatCycle) + ' ms';
  $('fDrift').textContent = Math.round(Math.abs(beatCycle - cycle)) + ' ms';
  return true;
}
function stop() { if (synth) synth.stopMIDI(); playing = false; $('play').textContent = '▶ Play'; }
function play() {
  if (!synth) synth = TinyChipBank.install(new WebAudioTinySynth({ quality: 1, useReverb: 0 }));
  synth.getAudioContext().resume();
  const song = v1.smf.parse(BEASTS[current].midi);
  const file = $('drums').checked ? v1.midi.write(withDrums(song)) : bytesOf(BEASTS[current].midi);
  synth.loadMIDI(file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength));
  synth.setLoop(1);
  synth.playMIDI();
  playing = true;
  setProgram();
  $('play').textContent = '■ Stop';
}
// the chosen preset on every voice; the voice with the lowest average pitch can take the bass preset
// Auto: what the onchain page plays. TinyChip.attach orchestrates the bare score (presets at 129 + id).
function setProgram() {
  const auto = $('chipPreset').value === 'auto';
  $('bassVoice').disabled = auto;
  if (auto) {
    $('chipInspired').textContent = 'Each voice gets a preset from its register, rests and tempo, as on the onchain page.';
    if (!playing) return;
    const channels = [...new Set(v1.smf.parse(BEASTS[current].midi).notes.map((n) => n[4]))].sort((a, b) => a - b);
    // the score without the demo's drum track, as the onchain player sees it before adding its drums
    const r = TinyChip.attach(synth, { bare: true, channels, events: synth.song.ev.filter((e) => e.m[0] >= 0xf0 || (e.m[0] & 15) !== 9) });
    $('chipInspired').textContent = 'Orchestration ' + r.orchestration + ': ' + channels.map((ch) => 'voice ' + (ch + 1) + ' ' + NAMES[r.presets[ch]]).join(' · ');
    return;
  }
  const v = INSPIRED[$('chipPreset').value];
  $('chipInspired').textContent = v ? 'Inspired by ' + v : 'Generic chip voice';
  if (!playing) return;
  const prg = +$('chipPreset').value, avg = {};
  for (const n of v1.smf.parse(BEASTS[current].midi).notes) (avg[n[4]] ||= []).push(n[2]);
  const mean = (v) => avg[v].reduce((x, y) => x + y, 0) / avg[v].length;
  const voices = Object.keys(avg).map(Number);
  const low = voices.length > 1 ? voices.reduce((a, v) => (mean(v) < mean(a) ? v : a)) : -1;
  for (let ch = 0; ch < 16; ch++) if (ch !== 9) synth.send([0xc0 | ch, $('bassVoice').checked && ch === low ? BASS_PROGRAM : prg]);
}
function stepPreset(d) {
  const sel = $('chipPreset'), n = sel.options.length;
  sel.selectedIndex = (sel.selectedIndex + d + n) % n;
  setProgram();
}
function setMode(next) {
  mode = next;
  if (beat) beat.setMode(mode);
  document.querySelectorAll('[data-mode]').forEach((x) => x.setAttribute('aria-pressed', x.dataset.mode === mode));
  $('modeNote').textContent = NOTES[mode];
  $('artLabel').textContent = mode === 'off' ? 'Browser GIF (BeatSync off)' : 'BeatSync: ' + (mode === 'beat' ? 'beat-locked' : 'native timing');
}
// readout: the frame BeatSync shows and the eighth note in the bar being heard (read after
// BeatSync's own animation-frame step, so both come from the same moment)
(function readout() {
  const tick = synth && BeatSync.audibleTick(synth), k = beat ? beat.shown : -1;
  strip.forEach((cv, i) => cv.classList.toggle('on', i === k));
  const eighth = tick == null ? -1 : Math.floor(tick / (synth.song.timebase / 8));
  document.querySelectorAll('#beats span').forEach((s, i) => s.classList.toggle('on', i === eighth % 8));
  $('pos').textContent = tick == null ? "Stopped: the art is the browser's GIF."
    : 'Bar ' + (Math.floor(eighth / 8) + 1) + ', eighth ' + (eighth % 8 + 1) + (k < 0 ? ' · browser GIF' : ' · frame ' + (k + 1) + ' of ' + strip.length);
  requestAnimationFrame(() => setTimeout(readout));
})();
$('play').addEventListener('click', () => (playing ? stop() : play()));
// keep playing across a switch, even when another pick arrives while an SVG is still loading
let resume = false;
$('beast').addEventListener('change', async (e) => {
  resume = resume || playing;
  stop();
  current = +e.target.value;
  if (await load() && resume) { resume = false; play(); }
});
$('drums').addEventListener('change', () => { if (playing) { stop(); play(); } });
$('chipPreset').addEventListener('change', setProgram);
$('bassVoice').addEventListener('change', setProgram);
$('prevPreset').addEventListener('click', () => stepPreset(-1));
$('nextPreset').addEventListener('click', () => stepPreset(1));
document.querySelectorAll('[data-mode]').forEach((btn) => btn.addEventListener('click', () => setMode(btn.dataset.mode)));
load();
setMode('beat');
setProgram();
</script></body></html>`;
writeFileSync(out + 'beatsync.html', html);
console.log(`beatsync.html: ${(html.length / 1000).toFixed(0)} KB · ${data.length} Beasts · ${Object.keys(GIFS).length} species GIFs · BeatSync ${beatsync.length} B`);

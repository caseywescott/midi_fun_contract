// Build public/onchain/cue-demo.html: Beasts whose art follows the music's structure (CueSync over
// BeatSync), against today's tempo-only BeatSync. Self-contained; nothing is fetched.
//   node onchain/cues/build-demo.mjs [webaudio-tinysynth-4bf9829.min.js]
// The engine is onchain-midi-player's pinned TinySynth (the README's SHA-256 8ad79ab8…); default
// $BEAST_ENGINE, then ../.beast-sound-cache/webaudio-tinysynth-4bf9829.min.js beside the repository.
// Each Beast plays its Species Song exactly as BeastMidiProvider.get_midi composes it (genesisMidi):
// the cues are read from the render result next to the MIDI; the MIDI bytes are not modified.
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { engine as E, decodeTokenId } from '../../src/index.js';
import { createEngineV11 } from '../../src/engine_v11.js';
import { genesisMidi } from '../../src/lab.js';
import { beastSynthSettings } from '../tinychip/synth_settings.mjs';
import { ESSENTIALS } from '../tinychip/essentials.mjs';
import { songCues, withCueTrack, cueTrack, markerText } from './cues.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const ENGINE_SHA = '8ad79ab8214e45a601e7d929e676b34b78e3f2b4200fd751d6548cf2b7df7749';
const engineFile = [process.argv[2], process.env.BEAST_ENGINE, here + '../../../../../.beast-sound-cache/webaudio-tinysynth-4bf9829.min.js'].find((f) => f && existsSync(f));
if (!engineFile) { console.error('usage: node onchain/cues/build-demo.mjs <webaudio-tinysynth-4bf9829.min.js> (see onchain/README.md for how to recover it)'); process.exit(2); }
const tiny = readFileSync(engineFile, 'utf8');
const sha = createHash('sha256').update(readFileSync(engineFile)).digest('hex');
if (sha !== ENGINE_SHA) { console.error(`engine sha256 ${sha} is not the pinned ${ENGINE_SHA}`); process.exit(2); }
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const minify = async (file) => (await build({ entryPoints: [file], minify: true, format: 'iife', target: 'es2020', write: false, logLevel: 'error' })).outputFiles[0].text;

// Contrasting Beasts from the gallery: three animated GIFs (a shiny tier-1 Magic with five channels, a
// tier-5 Hunter, a tier-3 Brute) and a static Yeti (rock groove, avalanche), to show the cue layer
// moves even art BeatSync cannot step.
const PICKS = [
  { token: 1949, short: 'Jiangshi', badge: 'GIF · shiny · tier 1' },
  { token: 58886, short: 'Giant', badge: 'GIF · tier 3' },
  { token: 8303, short: 'Spider', badge: 'GIF · tier 5' },
  { token: 3553, short: 'Basilisk', badge: 'GIF · tier 1' },
  { token: 54798, short: 'Yeti', badge: 'static · tier 4' },
];
const gallery = JSON.parse(readFileSync(here + '../../public/onchain/gallery.json', 'utf8'));
const v11 = createEngineV11(E);
const beasts = PICKS.map((p) => {
  const g = gallery.find((x) => x.token === p.token);
  const b = decodeTokenId(BigInt(g.token_id));
  const svg = readFileSync(here + `../../public/onchain/beasts/${p.token}.svg`, 'utf8');
  const r = genesisMidi(b.id, b.shiny, E, v11);
  const midi = Uint8Array.from(r.midi);
  const cues = songCues(r.result, midi);
  const withCues = withCueTrack(midi, cues.cues), withBars = withCueTrack(midi, cues.cues, { bars: true });
  const markers = cues.cues.filter((c) => c.type !== 'bar');
  const { notes, ...rest } = cues; // notes ride separately (the meters and the strip)
  return {
    token: p.token, name: g.name, short: p.short, badge: p.badge, species: b.id, shiny: b.shiny, tier: b.tier,
    key: r.info.key, bpm: Math.round(60e6 / cues.tempo_us), svg, gif: /data:image\/gif/.test(svg),
    midi: Buffer.from(midi).toString('base64'), notes, cues: rest,
    marker: { midi: midi.length, bytes: withCues.length - midi.length, bytesBars: withBars.length - midi.length, count: markers.length, track: cueTrack(cues.cues).length, preview: markers.map((c) => `${(c.tick / cues.bar + 1).toFixed(2).replace(/\.00$/, '')}:${markerText(c)}`).join('  ') },
  };
});

const settings = beastSynthSettings(undefined, ESSENTIALS);
const W = { Sine: 'sine', Square: 'square', Sawtooth: 'sawtooth', Triangle: 'triangle', WhiteNoise: 'n0', MetallicNoise: 'n1' };
const DATA = {
  beasts,
  settings: {
    quality: settings.quality, reverb: settings.reverb, master_vol: settings.master_vol, voices: settings.voices,
    waves: settings.waves.map((w) => w.Samples.map((v) => v / 128)),
    timbres: settings.timbres.map((t) => [t.drum ? 1 : 0, t.slot, t.operators.map((o) => ({ g: o.route, w: typeof o.wave === 'string' ? W[o.wave] : 'nS' + o.wave.Custom, v: o.volume / 1e4, t: o.ratio / 1e4, f: o.offset_hz / 1e4, a: o.attack / 1e4, h: o.hold / 1e4, d: o.decay / 1e4, s: o.sustain / 1e4, r: o.release / 1e4, p: o.pitch_ratio / 1e4, q: o.pitch_time / 1e4, k: o.key_scale / 1e4 }))]),
  },
};

const NOTICE = '/*! webaudio-tinysynth (c) g200kg, Apache License 2.0; Provable Games fork as pinned by onchain-midi-player, https://github.com/Provable-Games/webaudio-tinysynth */';
const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Music-driven Beasts</title>
<style>
:root{--bg:#101014;--fg:#ece9f2;--mut:#9893a6;--card:#19181f;--line:#2b2935;--acc:#ffcf4a;color-scheme:dark}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,sans-serif}
main{max-width:1060px;margin:0 auto;padding:22px 16px 40px}
h1{font-size:22px;margin:0 0 2px;letter-spacing:.01em}p.sub{color:var(--mut);margin:0 0 16px;max-width:760px}
.pick{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-bottom:14px}
.pick button{display:flex;flex-direction:column;align-items:center;gap:2px;padding:8px 6px;border-radius:12px;border:1px solid var(--line);background:var(--card);color:var(--fg);font:600 13px system-ui;cursor:pointer}
.pick button img{width:46px;height:64px;object-fit:cover;object-position:center 30%;border-radius:6px;image-rendering:pixelated}
.pick button small{color:var(--mut);font-weight:400;font-size:11px}.pick button.on{border-color:var(--acc);box-shadow:0 0 0 1px var(--acc) inset}
.grid{display:grid;grid-template-columns:minmax(0,1.05fr) minmax(0,1fr);gap:14px;align-items:start}
@media(max-width:760px){.grid{grid-template-columns:1fr}.grid>div:last-child{order:-1}.pick{grid-template-columns:repeat(3,1fr)}#log{min-height:0}}
.stage{--key-hue:240;--flash:0;--sweep:0;--settle:0;position:relative;border-radius:16px;overflow:hidden;aspect-ratio:5/6;border:1px solid var(--line);
 background:radial-gradient(120% 90% at 50% 40%,hsl(var(--key-hue) 45% calc(20% + 10% * var(--sweep))) 0%,hsl(var(--key-hue) 35% 8%) 70%);transition:background .6s}
.stage::after{content:"";position:absolute;inset:0;background:radial-gradient(circle at 50% 42%,rgba(255,255,255,.95),rgba(255,240,200,.25) 45%,transparent 70%);opacity:var(--flash);pointer-events:none;mix-blend-mode:screen}
.stage::before{content:"";position:absolute;inset:0;background:rgba(10,14,30,.55);opacity:calc(var(--settle) * .7);pointer-events:none;z-index:1}
#art{position:absolute;inset:6% 12%;transform-origin:50% 60%;will-change:transform,filter;z-index:0}
#art img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;image-rendering:pixelated}
.meters{display:flex;gap:6px;margin-top:8px;flex-wrap:wrap}
.meter{flex:1;min-width:70px;position:relative;height:30px;border-radius:8px;background:var(--card);border:1px solid var(--line);overflow:hidden;--e:0}
.meter i{position:absolute;left:0;bottom:0;top:0;width:calc(100% * var(--e));background:var(--c);opacity:.75}
.meter span{position:relative;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-size:11px;padding:0 7px;line-height:28px;color:#fff;text-shadow:0 1px 2px #000}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px;margin-bottom:12px}
.ctl{display:flex;gap:8px;flex-wrap:wrap}
button.big{padding:11px 18px;border-radius:10px;border:0;background:var(--fg);color:var(--bg);font:700 15px system-ui;cursor:pointer;min-width:110px}button.big.on{background:var(--acc)}
.seg{display:flex;flex:1;min-width:250px;border:1px solid var(--line);border-radius:10px;overflow:hidden}
.seg button{flex:1;padding:10px 8px;border:0;background:transparent;color:var(--mut);font:600 13px system-ui;cursor:pointer}.seg button.on{background:#2c2a38;color:var(--fg)}
.seg button.on#m-music{background:color-mix(in srgb,var(--acc) 22%,#1c1b24);color:#fff}
#mode-note{color:var(--mut);font-size:13px;margin:8px 0 0}
#name{font-weight:700;font-size:17px}.facts{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}.facts span{font-size:12px;color:var(--mut);border:1px solid var(--line);border-radius:999px;padding:1px 8px}
.now{display:flex;justify-content:space-between;align-items:baseline;gap:8px}#now{font-weight:600}#bar{color:var(--mut);font:12px ui-monospace,monospace;white-space:nowrap}
#log{list-style:none;margin:8px 0 0;padding:0;font-size:13px;min-height:168px}
#log li{display:flex;align-items:center;gap:8px;padding:3px 0;border-top:1px solid var(--line);animation:in .35s ease-out}
#log li i{width:9px;height:9px;border-radius:50%;background:var(--c,#888);flex:none}#log li em{margin-left:auto;color:var(--mut);font:11px ui-monospace,monospace}
#log li.section i{--c:#7aa7ff;border-radius:2px}#log li.cadence i{--c:#8cc8ff;border-radius:2px;height:4px}#log li.climax i{--c:#ffd65a}#log li.episode i{--c:#666}
#log li.climax span{color:#ffd65a;font-weight:700}
@keyframes in{from{opacity:0;transform:translateX(-6px)}to{opacity:1}}
canvas#strip{width:100%;display:block;height:120px;border-radius:8px;background:#0b0b0f}
.legend{display:flex;flex-wrap:wrap;gap:4px 14px;color:var(--mut);font-size:12px;margin-top:8px}
#marker{font-size:13px;color:var(--mut)}#marker b{color:var(--fg)}#marker code{display:block;margin-top:6px;font:11px/1.6 ui-monospace,monospace;color:var(--fg);word-break:break-word}
.react{font-size:13px;color:var(--mut);margin:0;padding-left:18px}.react b{color:var(--fg)}
@media (prefers-reduced-motion:reduce){#log li{animation:none}}
</style></head><body><main>
<h1>Music-driven Beasts</h1>
<p class="sub">Each Beast plays its Species Song, exactly the MIDI its token plays. Today (BeatSync) a GIF steps one frame per eighth note, so it follows the tempo and nothing else. Here the composer's own structure drives the art too: the sections and their keys, each voice's theme entry, the climax and the final cadence, plus every note's velocity. Switch modes while it plays to compare.</p>
<div class="pick" id="pick"></div>
<div class="grid">
 <div>
  <div class="stage" id="stage"><div id="art"></div></div>
  <div class="meters" id="meters"></div>
 </div>
 <div>
  <div class="card">
   <div class="ctl"><button class="big" id="play" type="button">▶ Play</button>
    <div class="seg" role="group" aria-label="Animation mode"><button id="m-tempo" type="button">Tempo only (today)</button><button id="m-music" type="button">Music-driven</button></div></div>
   <p id="mode-note"></p>
  </div>
  <div class="card"><div id="name"></div><div class="facts" id="facts"></div></div>
  <div class="card"><div class="now"><span id="now">Press Play (or space).</span><span id="bar"></span></div><ul id="log" aria-live="polite"></ul></div>
 </div>
</div>
<div class="card"><canvas id="strip" aria-label="Cue timeline"></canvas>
 <div class="legend"><span>▶ theme entry</span><span>◆ countersubject</span><span>▬ cadence (pale: half cadence, bright: final)</span><span>★ climax</span><span>bands: sections, coloured like the stage</span></div></div>
<div class="card"><ul class="react">
 <li><b>Theme entries</b>: a pulse and a glow in the entering voice's colour (the theme voice strongest).</li>
 <li><b>Sections</b>: the backdrop changes with each section's key area, with a sweep on its downbeat.</li>
 <li><b>Climax</b>: a punch, a palette flash and a flash of light, and the frames run on sixteenths for that bar.</li>
 <li><b>Cadences</b>: the Beast bows and dims and its frames slow to quarter notes; on the final cadence they slow again and hold still until the loop starts over.</li>
 <li><b>Velocity</b>: every note-on lights its voice's meter and the art breathes with the overall energy; every bar line gives a small nudge.</li>
</ul></div>
<div class="card" id="marker"></div>
</main>
<script>${NOTICE}
${inline(tiny)}</script>
<script>${inline(await minify(here + '../beatsync/beatsync.js'))}</script>
<script>${inline(await minify(here + 'cuesync.js'))}</script>
<script>const DATA=${inline(JSON.stringify(DATA))};</script>
<script>${inline(await minify(here + 'demo.js'))}</script>
</body></html>`;
const out = here + '../../public/onchain/cue-demo.html';
writeFileSync(out, html);
console.log(`public/onchain/cue-demo.html ${html.length} bytes`);
for (const b of beasts) console.log(`  ${b.name} (species ${b.species}${b.shiny ? ', shiny' : ''}): ${b.key}, ${b.bpm} BPM, MIDI ${b.marker.midi} B, cue track +${b.marker.bytes} B (${b.marker.count} markers), +${b.marker.bytesBars} B with bars\n    ${b.marker.preview}`);

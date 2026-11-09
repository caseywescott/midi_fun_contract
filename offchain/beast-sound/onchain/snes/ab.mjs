// Build dist-ab/ab.html: the 16 kHz and mixed 12 kHz banks, each through the sampler as it was
// (browser linear resampling, instant voice stealing, 8 voices) and as fixed (whole-factor windowed-sinc
// upsampling at decode, 5 ms fades on stolen voices, 16 voices). The BRR data is identical in both;
// only playback differs. Measure renders each variant offline at 48 kHz and reports the energy above
// 8.5 kHz (no bank sample carries content there, so it is resampling images) and detected clicks.
//   npm run snes:build && npm run snes:build:12k && node onchain/snes/ab.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url)), out = resolve(here, 'dist-ab');
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const bank16 = readFileSync(resolve(here, 'dist/bank.min.js'), 'utf8'), bank12 = readFileSync(resolve(here, 'dist-12k/bank.min.js'), 'utf8');
const demo = (await build({ stdin: { contents: "import {demoSequence,scheduleDemo} from './demo.js';window.SnesDemo={sequence:demoSequence,schedule:scheduleDemo};", resolveDir: here }, bundle: true, minify: true, write: false })).outputFiles[0].text;

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SNES Sampler A/B</title><link rel="icon" href="data:,">
<style>
:root{--bg:#141723;--fg:#f2eee4;--mut:#a9aebb;--card:#1d2131;--line:#2e3348;--acc:#e6b450;--ok:#57c785;--bad:#ef6f6c}
@media (prefers-color-scheme:light){:root:not([data-theme="dark"]){--bg:#f5f3ee;--fg:#1b1d24;--mut:#5d6170;--card:#fff;--line:#dcd8cf;--acc:#9a6b00;--ok:#1f8a4c;--bad:#c0392b}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 system-ui,sans-serif}
main{max-width:900px;margin:0 auto;padding:28px 16px 48px}h1{font-size:23px;margin:0 0 6px}p{margin:0 0 12px}.mut{color:var(--mut)}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:14px 0}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}@media(max-width:600px){.grid{grid-template-columns:1fr}}
button,select{font:inherit;color:var(--fg);background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:10px 12px;cursor:pointer}
.v{text-align:left}.v b{display:block}.v span{font-size:13px;color:var(--mut)}.v.on{border-color:var(--acc);box-shadow:0 0 0 1px var(--acc) inset}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}h2{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:var(--mut);margin:0 0 10px}
table{width:100%;border-collapse:collapse;font-size:14px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line)}td.n{font-variant-numeric:tabular-nums}
.kbd{font:12px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 5px}#status{min-height:1.5em}
</style></head><body><main>
<h1>SNES Sampler A/B</h1>
<p class="mut">The same BRR banks through the sampler before and after the playback fixes. Before: the browser resamples each 12&ndash;16 kHz sample with linear interpolation, and a stolen voice is cut instantly (8 voices). After: each sample is upsampled once at load with a windowed sinc, and stolen voices fade over 5 ms (16 voices). The stored bank and its onchain cost are unchanged.</p>
<div class="card"><h2>Variant <span class="kbd">1</span>&ndash;<span class="kbd">4</span></h2><div class="grid" id="variants"></div></div>
<div class="card"><h2>Listen</h2>
<div class="row"><select id="content" aria-label="What to play"><option value="demo">All ten sounds, then the ensemble (42 s)</option><option value="sweep">One sound, two octaves up and down</option><option value="busy">Busy ensemble (voice stealing)</option></select>
<select id="inst" aria-label="Sound"></select>
<button id="play">&#9654; Play</button><button id="stop">&#9632; Stop</button></div>
<p id="status" class="mut"></p>
<p class="mut">Listen on headphones. Sustained strings, cello and clarinet show the resampling difference most; the busy ensemble shows the voice-steal clicks. <span class="kbd">space</span> play/stop.</p></div>
<div class="card"><h2>Measure (offline render at 48 kHz)</h2>
<div class="row"><button id="measure">Measure all four</button><span class="mut" id="mstatus"></span></div>
<table id="results"><thead><tr><th>Variant</th><th>Images above 8.5 kHz</th><th>Clicks detected</th><th>Peak</th></tr></thead><tbody></tbody></table>
<p class="mut">Images: energy above 8.5 kHz relative to the whole render; no sample in either bank has content there, so it comes from resampling. Clicks: samples whose third difference jumps far above the surrounding 10 ms.</p></div>
</main>
<script>${inline(bank16)}window.Bank16=window.SnesBank;</script>
<script>${inline(bank12)}window.Bank12=window.SnesBank;</script>
<script>${inline(demo)}</script>
<script>
const $ = (id) => document.getElementById(id);
const BEFORE = { upsample: false, softSteal: false, maxVoices: 8 }, AFTER = { upsample: true, softSteal: true, maxVoices: 16 };
const VARIANTS = [
  { label: '16 kHz · before', desc: 'current playback', B: Bank16, opt: BEFORE },
  { label: '16 kHz · after', desc: 'sinc upsampling, soft voice stealing', B: Bank16, opt: AFTER },
  { label: '12 kHz mix · before', desc: 'current playback (the crackly one)', B: Bank12, opt: BEFORE },
  { label: '12 kHz mix · after', desc: 'sinc upsampling, soft voice stealing', B: Bank12, opt: AFTER },
];
let cur = 1, ac = null, sampler = null, run = null, timer = 0;
$('variants').innerHTML = VARIANTS.map((v, i) => '<button class="v" data-i="' + i + '"><b>' + (i + 1) + '. ' + v.label + '</b><span>' + v.desc + '</span></button>').join('');
const seen = new Set();
for (const i of Bank16.bank.instruments) if (!seen.has(i.id)) { seen.add(i.id); const o = document.createElement('option'); o.value = i.id; o.textContent = i.id; $('inst').append(o); }
$('inst').value = 'cello';
function paint() { document.querySelectorAll('.v').forEach((b) => b.classList.toggle('on', +b.dataset.i === cur)); $('inst').style.display = $('content').value === 'sweep' ? '' : 'none'; }
/** The notes to play: the demo, a two-octave sweep of one sound, or the ensemble twice as dense. */
function sequence(bank) {
  const kind = $('content').value;
  if (kind === 'demo') return SnesDemo.sequence(bank);
  if (kind === 'sweep') {
    const inst = bank.instruments.find((i) => i.id === $('inst').value), notes = [];
    const steps = [-12, -7, -5, 0, 4, 7, 12, 16, 19, 24, 19, 12, 7, 0];
    steps.forEach((s, k) => notes.push({ id: inst.id, program: inst.program, channel: 0, note: inst.rootNote + s, velocity: 104, time: k * 0.45, duration: 0.4, pan: 0 }));
    return { notes, sections: [{ time: 0, label: inst.id + ' sweep' }], duration: steps.length * 0.45 + 1.2 };
  }
  const base = SnesDemo.sequence(bank), start = base.sections.find((s) => s.label === 'Pocket orchestra').time;
  const ens = base.notes.filter((n) => n.time >= start).map((n) => ({ ...n, time: n.time - start }));
  const notes = [...ens, ...ens.map((n) => ({ ...n, time: n.time + 0.25, note: n.note + 12 })), ...ens.map((n) => ({ ...n, time: n.time + 8 })), ...ens.map((n) => ({ ...n, time: n.time + 8.25, note: n.note + 7 }))].sort((a, b) => a.time - b.time);
  return { notes, sections: [{ time: 0, label: 'busy ensemble' }], duration: Math.max(...notes.map((n) => n.time + n.duration)) + 1.5 };
}
function schedule(smp, ctx, seq, dest, t0) {
  const buses = new Map();
  for (const n of seq.notes) {
    if (!buses.has(n.channel)) { const p = ctx.createStereoPanner(); p.pan.value = n.pan; p.connect(dest); buses.set(n.channel, p); }
    smp.noteOn({ ...n, time: t0 + n.time, destination: buses.get(n.channel) });
    smp.noteOff(n.channel, n.note, t0 + n.time + n.duration);
  }
  return { start: t0, dispose() { smp.stop(); for (const p of buses.values()) p.disconnect(); } };
}
function stop() { clearInterval(timer); if (run) { run.dispose(); run = null; } if (sampler) { sampler.dispose(); sampler = null; } $('status').textContent = ''; }
function play() {
  stop(); if (!ac) ac = new AudioContext(); ac.resume();
  const v = VARIANTS[cur], seq = sequence(v.B.bank);
  sampler = v.B.createSampler(ac, v.opt);
  run = schedule(sampler, ac, seq, ac.destination, ac.currentTime + 0.1);
  timer = setInterval(() => {
    const t = ac.currentTime - run.start;
    $('status').textContent = v.label + ' · ' + (seq.sections.filter((s) => s.time <= t).at(-1)?.label ?? 'starting') + ' · ' + Math.max(0, t).toFixed(1) + ' s';
    if (t > seq.duration) stop();
  }, 100);
}
document.querySelectorAll('.v').forEach((b) => (b.onclick = () => { cur = +b.dataset.i; paint(); if (run) play(); }));
$('play').onclick = play; $('stop').onclick = stop; $('content').onchange = () => { paint(); if (run) play(); }; $('inst').onchange = () => { if (run) play(); };
document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'SELECT') return;
  if (e.key === ' ') { e.preventDefault(); run ? stop() : play(); }
  if (e.key >= '1' && e.key <= '4') { cur = +e.key - 1; paint(); if (run) play(); }
});
// offline measurement
function biquadHP(x, rate, f) {
  const w = 2 * Math.PI * f / rate, c = Math.cos(w), al = Math.sin(w) / (2 * 0.7071);
  const b0 = (1 + c) / 2, b1 = -(1 + c), b2 = (1 + c) / 2, a0 = 1 + al, a1 = -2 * c, a2 = 1 - al, y = new Float32Array(x.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < x.length; i++) { const v = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0; x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v; }
  return y;
}
function clicks(x, rate) {
  const n = x.length, win = Math.round(rate * 0.01), d = new Float32Array(n);
  for (let i = 3; i < n; i++) d[i] = Math.abs(x[i] - 3 * x[i - 1] + 3 * x[i - 2] - x[i - 3]);
  let c = 0, last = -1e9;
  for (let i = win; i < n - win; i++) {
    if (d[i] < 0.01) continue;
    let s = 0; for (let j = i - win; j < i + win; j += 8) s += d[j];
    if (d[i] > 12 * s / (2 * win / 8) && i - last > win) { c++; last = i; }
  }
  return c;
}
async function measure(v) {
  const rate = 48000, seq = sequence(v.B.bank), ctx = new OfflineAudioContext(2, Math.ceil((seq.duration + 0.3) * rate), rate);
  const smp = v.B.createSampler(ctx, v.opt); schedule(smp, ctx, seq, ctx.destination, 0.1);
  const r = await ctx.startRendering(), L = r.getChannelData(0), R = r.getChannelData(1), m = new Float32Array(L.length);
  let peak = 0; for (let i = 0; i < m.length; i++) { m[i] = (L[i] + R[i]) / 2; peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i])); }
  let hp = biquadHP(biquadHP(m, rate, 8500), rate, 8500), eh = 0, et = 0;
  for (let i = 0; i < m.length; i++) { eh += hp[i] * hp[i]; et += m[i] * m[i]; }
  return { images: 10 * Math.log10(eh / et), clicks: clicks(m, rate), peak };
}
$('measure').onclick = async () => {
  const rows = [];
  for (const [i, v] of VARIANTS.entries()) {
    $('mstatus').textContent = 'rendering ' + v.label + '…';
    const r = await measure(v); rows.push([v, r]);
    $('results').tBodies[0].innerHTML = rows.map(([v, r]) => '<tr><td>' + v.label + '</td><td class="n">' + r.images.toFixed(1) + ' dB</td><td class="n">' + r.clicks + '</td><td class="n">' + r.peak.toFixed(3) + '</td></tr>').join('');
  }
  $('mstatus').textContent = 'done (' + $('content').selectedOptions[0].textContent + ')';
  window.MEASURED = rows.map(([v, r]) => ({ variant: v.label, ...r }));
};
paint();
</script></body></html>`;
mkdirSync(out, { recursive: true });
writeFileSync(resolve(out, 'ab.html'), html);
console.log('dist-ab/ab.html', html.length, 'bytes');

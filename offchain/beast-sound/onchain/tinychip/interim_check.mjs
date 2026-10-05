// How close the SynthSettings timbres (synth_settings.mjs: built-in waves, and the sampled waves
// registered as onchain-tinysynth's player does) come to TinyChip's own presets and drums (sampled
// chip waves), rendered offline in Chrome through one TinySynth engine:
//   PLAYWRIGHT_CORE=/path/to/node_modules/playwright-core node onchain/tinychip/interim_check.mjs <engine.min.js>
//   (onchain-tinysynth's pinned engine: tests/vendor/webaudio-tinysynth-<ref>.min.js in its repo;
//   CHROME=/path/to/chrome to override the browser; default: macOS Google Chrome)
//
// Each preset plays loudness.mjs's phrase (E3 B3 E4 B4 E5, 0.3 s each, velocity 100), each drum four
// hits. Loudness is K-weighted mean square, as in loudness.mjs; brightness is the spectral centroid
// of 4096 samples in the middle of E4 (drums: the third hit's window). Fails (exit 1) when a timbre
// is more than TOLERANCE_DB from its original, TinyChip's own loudness tolerance, or a noise timbre
// more than NOISE_TOLERANCE_DB: TinySynth fills its noises with Math.random, so those move by up to
// 0.75 dB from one render to the next.
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { bankData, ESSENTIALS } from './essentials.mjs';
import { BEAST_DRUMS, beastSynthSettings } from './synth_settings.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const TOLERANCE_DB = 0.5, NOISE_TOLERANCE_DB = 1;
const engine = process.argv[2];
if (!engine) { console.error('usage: node onchain/tinychip/interim_check.mjs <engine.min.js>'); process.exit(2); }
const { chromium } = (await import(process.env.PLAYWRIGHT_CORE ? pathToFileURL(process.env.PLAYWRIGHT_CORE + '/index.js').href : 'playwright-core')).default;

const D = { g: 0, w: 'sine', t: 1, f: 0, v: 0.5, a: 0, h: 0.01, d: 0.01, s: 0, r: 0.05, p: 1, q: 1, k: 0 };
const W = { Sine: 'sine', Square: 'square', Sawtooth: 'sawtooth', Triangle: 'triangle', WhiteNoise: 'n0', MetallicNoise: 'n1' };
const data = bankData();
// every essential, not only the ones the settings carry now, so any can be chosen
const settings = beastSynthSettings(data, ESSENTIALS, BEAST_DRUMS);
// Custom(i) plays wave i as onchain-tinysynth's player registers it (player/settings.js waveName)
const tinysynth = (ops) => ops.map((o) => ({ g: o.route, w: typeof o.wave === 'string' ? W[o.wave] : 'nS' + o.wave.Custom, v: o.volume / 1e4, t: o.ratio / 1e4, f: o.offset_hz / 1e4, a: o.attack / 1e4, h: o.hold / 1e4, d: o.decay / 1e4, s: o.sustain / 1e4, r: o.release / 1e4, p: o.pitch_ratio / 1e4, q: o.pitch_time / 1e4, k: o.key_scale / 1e4 }));
const items = settings.timbres.map((t) => ({
  drum: t.drum, slot: t.slot, noise: t.operators.some((o) => o.wave === 'WhiteNoise' || o.wave === 'MetallicNoise'),
  orig: (t.drum ? data.drums[t.slot] : data.presets[t.slot]).map((o) => ({ ...D, ...o })),
  interim: tinysynth(t.operators),
}));
const runtime = readFileSync(here + 'tinychip.js', 'utf8');
const waves = runtime.slice(runtime.indexOf('  function lfsr'), runtime.indexOf("  // tinysynth's operator defaults"));

const dir = mkdtempSync(join(tmpdir(), 'tinychip-interim-'));
writeFileSync(join(dir, 'ts.js'), readFileSync(engine));
writeFileSync(join(dir, 'items.js'), `window.ITEMS = ${JSON.stringify(items)};\nwindow.SAMPLED = ${JSON.stringify(settings.waves.map((w) => w.Samples))};\n${waves}\nwindow.registerWaves = registerWaves;`);
writeFileSync(join(dir, 'measure.html'), `<!doctype html><body><script src="ts.js"></script><script src="items.js"></script><script>
window.addEventListener('unhandledrejection', (e) => e.preventDefault());
function centroid(d, c0, SR) {
  const N = 4096, re = new Float64Array(N), im = new Float64Array(N);
  for (let k = 0; k < N; k++) re[k] = (d[c0 + k] || 0) * (0.5 - 0.5 * Math.cos((2 * Math.PI * k) / N));
  for (let i = 1, j = 0; i < N; i++) { let bit = N >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) [re[i], re[j]] = [re[j], re[i]]; }
  for (let len = 2; len <= N; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    for (let s = 0; s < N; s += len) for (let k = 0; k < len / 2; k++) {
      const wr = Math.cos(ang * k), wi = Math.sin(ang * k), u = s + k, v = u + len / 2;
      const tr = re[v] * wr - im[v] * wi, ti = re[v] * wi + im[v] * wr;
      re[v] = re[u] - tr; im[v] = im[u] - ti; re[u] += tr; im[u] += ti;
    }
  }
  let num = 0, den = 0;
  for (let k = 1; k < N / 2; k++) { const m = Math.hypot(re[k], im[k]); num += (m * k * SR) / N; den += m; }
  return den ? num / den : 0;
}
window.measure = async (which) => {
  const SR = 44100, NOTES = [52, 59, 64, 71, 76], ON = 0.3, GAP = 0.05, SLOT = NOTES.length * (ON + GAP) + 0.4;
  const off = new OfflineAudioContext(1, Math.ceil(SR * (ITEMS.length * SLOT + 0.5)), SR);
  const shelf = off.createBiquadFilter(); shelf.type = 'highshelf'; shelf.frequency.value = 1681; shelf.gain.value = 4;
  const hp = off.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 38; hp.Q.value = 0.5;
  shelf.connect(hp); hp.connect(off.destination);
  const synth = new WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 4096 });
  synth.setAudioContext(off, shelf);
  if (which === 'orig') registerWaves(synth);
  else SAMPLED.forEach((s, i) => synth.setSampleWave('nS' + i, s.map((v) => v / 128)));
  ITEMS.forEach((it) => synth.setTimbre(it.drum ? 1 : 0, it.slot, it[which]));
  ITEMS.forEach((it, i) => {
    const t0 = 0.05 + i * SLOT;
    if (it.drum) for (let j = 0; j < 4; j++) synth.send([0x99, it.slot, 100], t0 + j * 0.4);
    else { synth.send([0xc0, it.slot], t0 - 0.01); NOTES.forEach((n, j) => { const t = t0 + j * (ON + GAP); synth.send([0x90, n, 100], t); synth.send([0x80, n, 0], t + ON); }); }
  });
  const d = (await off.startRendering()).getChannelData(0);
  return ITEMS.map((it, i) => {
    const a = Math.floor((0.05 + i * SLOT) * SR), b = Math.floor((0.05 + i * SLOT + NOTES.length * (ON + GAP) + 0.2) * SR);
    let ms = 0; for (let k = a; k < b; k++) ms += d[k] * d[k];
    return [10 * Math.log10(ms / (b - a) + 1e-12), centroid(d, Math.floor((0.05 + i * SLOT + 2 * (ON + GAP) + 0.1) * SR), SR)];
  });
};
</script>`);

const browser = await chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--allow-file-access-from-files'] });
const page = await browser.newPage();
await page.goto(pathToFileURL(join(dir, 'measure.html')).href);
const orig = await page.evaluate(() => window.measure('orig'));
const interim = await page.evaluate(() => window.measure('interim'));
await browser.close();

let worst = 0, worstNoise = 0;
items.forEach((it, i) => {
  const diff = interim[i][0] - orig[i][0], ratio = interim[i][1] / orig[i][1];
  if (it.noise) worstNoise = Math.max(worstNoise, Math.abs(diff)); else worst = Math.max(worst, Math.abs(diff));
  console.log(`${(it.drum ? 'drum ' : 'program ') + it.slot}`.padEnd(12) + `${diff >= 0 ? '+' : ''}${diff.toFixed(2)} dB  brightness x${ratio.toFixed(2)}${it.noise ? '  (noise)' : ''}`);
});
console.log(`worst loudness difference ${worst.toFixed(2)} dB (tolerance ${TOLERANCE_DB}), noise timbres ${worstNoise.toFixed(2)} dB (tolerance ${NOISE_TOLERANCE_DB})`);
process.exit(worst <= TOLERANCE_DB && worstNoise <= NOISE_TOLERANCE_DB ? 0 : 1);

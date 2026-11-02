// PLAYWRIGHT_CORE=/absolute/path/to/playwright node onchain/snes/browser-check.mjs
// Synthetic test signal only; does not add samples to the user's manifest.
import assert from 'node:assert/strict';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { bundleBank } from './build.mjs';
import { encodeBRR } from './brr.js';
import { DEFAULT_ENVELOPE } from './bank.js';
import { storedSegment, animationHtml } from '../page.js';
const { chromium } = await import(process.env.PLAYWRIGHT_CORE ? pathToFileURL(process.env.PLAYWRIGHT_CORE + '/index.mjs').href : 'playwright-core');
const pcm = Int16Array.from({ length: 1024 }, (_, i) => Math.round(14000 * Math.sin(2 * Math.PI * i / 64)));
const bank = { format: 'BSBRR1', samples: [{ rate: 16000, loopStart: 0, data: Buffer.from(encodeBRR(pcm, 0)).toString('base64') }], instruments: [{ id: 'test', program: 0, sample: 0, rootNote: 60, tuneCents: 0, volume: 0.5, envelope: DEFAULT_ENVELOPE }] };
const script = await bundleBank(bank);
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_EXECUTABLE, args: ['--autoplay-policy=no-user-gesture-required'] });
try {
  const context = await browser.newContext({ offline: true });
  const page = await context.newPage(), errors = [], requests = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.route('**/*', (route) => { requests.push(route.request().url()); return route.abort(); });
  await page.setContent(`<script>${script}</script>`);
  const audio = await page.evaluate(async () => {
    const rms = (data, start, end) => Math.sqrt(data.slice(start * 32000, end * 32000).reduce((sum, x) => sum + x * x, 0) / ((end - start) * 32000));
    const frequency = (data) => { let crossings = 0; for (let i = 3201; i < 9600; i++) if (data[i - 1] <= 0 && data[i] > 0) crossings++; return crossings / 0.2; };
    async function render(note, count = 1, stealStop = false, echo = false) {
      const ac = new OfflineAudioContext(1, 32000, 32000), sampler = SnesBank.createSampler(ac, { smoothing: false, echo, maxVoices: stealStop ? 1 : 8 });
      for (let i = 0; i < count; i++) sampler.noteOn({ note, time: 0 });
      if (stealStop) { sampler.noteOn({ note, time: 0.5 }); sampler.stop(undefined, 0.25); }
      else sampler.noteOff(0, note, 0.4);
      const output = await ac.startRendering(); sampler.dispose(); return output.getChannelData(0);
    }
    const root = await render(60), octave = await render(72), eight = await render(60, 8), ten = await render(60, 10), stopped = await render(60, 1, true), echoed = await render(60, 1, false, true);
    return { rootHz: frequency(root), octaveHz: frequency(octave), sound: rms(root, 0.1, 0.3), released: rms(root, 0.65, 0.9), polyphonyRatio: rms(ten, 0.1, 0.3) / rms(eight, 0.1, 0.3), stopped: rms(stopped, 0.3, 0.9), echoTail: rms(echoed, 0.6, 0.7) };
  });
  assert.ok(audio.sound > 0.01); assert.ok(Math.abs(audio.octaveHz / audio.rootHz - 2) < 0.06);
  assert.ok(audio.released < 1e-5); assert.ok(Math.abs(audio.polyphonyRatio - 1) < 0.01);
  assert.ok(audio.stopped < 1e-5); assert.ok(audio.echoTail > 1e-5);

  // Real TinySynth integration: program fallback, sustain, bend, and immediate stop.
  const tiny = readFileSync(new URL('../dist/tinysynth.min.js', import.meta.url), 'utf8');
  await page.addScriptTag({ content: tiny });
  const adapter = await page.evaluate(async () => {
    const synth = new WebAudioTinySynth({ quality: 1, useReverb: 0 });
    const ac = synth.getAudioContext(); await ac.resume();
    const installed = SnesBank.attach(synth, { echo: false });
    synth.send([0x90, 60, 100]);
    const sampled = installed.sampler.activeVoices;
    synth.send([0xb0, 64, 127]); synth.send([0x80, 60, 0]); synth.send([0xe0, 127, 127]);
    const sustained = installed.sampler.activeVoices;
    synth.send([0xb0, 64, 0]);
    synth.send([0xc1, 10]); synth.send([0x91, 64, 80]);
    const fallback = synth.notetab.some((n) => n.ch === 1);
    synth.allSoundOff(0); synth.allSoundOff(1);
    const stopped = installed.sampler.activeVoices;
    installed.dispose(); const restored = !synth.__snesSampler;
    await ac.close(); return { sampled, sustained, fallback, stopped, restored };
  });
  assert.deepEqual(adapter, { sampled: 1, sustained: 1, fallback: true, stopped: 0, restored: true });

  // A real generated token page starts/stops with an embedded MIDI and no network.
  const { build } = await import('esbuild');
  const player = await build({ entryPoints: [fileURLToPath(new URL('player-src.js', import.meta.url))], bundle: true, minify: true, write: false });
  const pageScript = [tiny, script, player.outputFiles[0].text].join('\n');
  assert.equal(storedSegment(pageScript).length % 372, 0);
  const midi = Uint8Array.from([77,84,104,100,0,0,0,6,0,0,0,1,1,224,77,84,114,107,0,0,0,13,0,144,60,100,131,96,128,60,0,0,255,47,0]);
  await page.setContent(animationHtml(pageScript, midi, '<svg xmlns="http://www.w3.org/2000/svg"/>'));
  await page.getByRole('button', { name: 'Play', exact: true }).click();
  await page.waitForFunction(() => SOUND.synth?.__snesSampler.activeVoices > 0);
  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  assert.equal(await page.evaluate(() => SOUND.synth.__snesSampler.activeVoices), 0);
  assert.deepEqual(errors, []); assert.deepEqual(requests, []);
  console.log(JSON.stringify({ audio, adapter, tokenPage: 'play/stop passed', networkRequests: requests.length }, null, 2));
} finally { await browser.close(); }

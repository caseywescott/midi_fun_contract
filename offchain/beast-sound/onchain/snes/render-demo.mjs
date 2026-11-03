// Render and verify the ACTUAL bundled bank using Web Audio, with all network blocked.
// PLAYWRIGHT_CORE=/path/to/playwright node onchain/snes/render-demo.mjs [output-directory]
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url)), out = resolve(process.argv[2] ?? resolve(here, 'dist'));
const { chromium } = await import(process.env.PLAYWRIGHT_CORE ? pathToFileURL(process.env.PLAYWRIGHT_CORE + '/index.mjs').href : 'playwright-core');
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_EXECUTABLE, args: ['--autoplay-policy=no-user-gesture-required'] });
try {
  const context = await browser.newContext({ offline: true }), page = await context.newPage(), errors = [], requests = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.route('**/*', (r) => { requests.push(r.request().url()); return r.abort(); });
  await page.setContent(readFileSync(resolve(out, 'lab.html'), 'utf8'));
  assert.equal(await page.locator('#instrument option').count(), 10);
  await page.getByRole('button', { name: 'Play all + ensemble' }).click();
  await page.waitForFunction(() => document.getElementById('status').textContent === 'harp');
  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  const result = await page.evaluate(async () => {
    const rate = 32000, bank = SnesBank.bank;
    const ac = new OfflineAudioContext(2, Math.ceil((SnesDemo.sequence(bank).duration + 0.2) * rate), rate);
    const output = ac.createGain(); output.gain.value = 0.8; output.connect(ac.destination);
    const sampler = SnesBank.createSampler(ac), sequence = SnesDemo.schedule(sampler, ac, bank, output, 0.1);
    const rendered = await ac.startRendering(), length = Math.ceil((sequence.duration + 0.1) * rate);
    const channels = [rendered.getChannelData(0), rendered.getChannelData(1)];
    let peak = 0, clipped = 0;
    const bytes = new Uint8Array(length * 4), view = new DataView(bytes.buffer);
    for (let i = 0; i < length; i++) for (let ch = 0; ch < 2; ch++) {
      const v = channels[ch][i]; if (!Number.isFinite(v)) throw new Error('Non-finite output');
      peak = Math.max(peak, Math.abs(v)); if (Math.abs(v) >= 1) clipped++;
      view.setInt16((i * 2 + ch) * 2, Math.round(Math.max(-1, Math.min(1, v)) * 32767), true);
    }
    const sections = sequence.sections.map((s, i) => {
      const start = Math.floor((s.time + 0.1) * rate), stop = Math.floor(((sequence.sections[i + 1]?.time ?? sequence.duration) + 0.1) * rate);
      let sum = 0; for (let n = start; n < stop; n++) for (const c of channels) sum += c[n] ** 2;
      return { ...s, rms: Math.sqrt(sum / ((stop - start) * 2)) };
    });
    let text = ''; for (let i = 0; i < bytes.length; i += 8192) text += String.fromCharCode(...bytes.subarray(i, i + 8192));
    sequence.dispose(); sampler.dispose();
    return { pcm: btoa(text), rate, channels: 2, seconds: length / rate, peak, clipped, sections };
  });
  assert.equal(result.clipped, 0); assert.ok(result.peak > 0.05 && result.peak < 0.95);
  assert.equal(result.sections.length, 11); assert.ok(result.sections.every((s) => s.rms > 0.002));
  assert.deepEqual(errors, []); assert.deepEqual(requests, []);
  const pcm = Buffer.from(result.pcm, 'base64'), header = Buffer.alloc(44);
  header.write('RIFF'); header.writeUInt32LE(pcm.length + 36, 4); header.write('WAVEfmt ', 8); header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22); header.writeUInt32LE(result.rate, 24); header.writeUInt32LE(result.rate * 4, 28);
  header.writeUInt16LE(4, 32); header.writeUInt16LE(16, 34); header.write('data', 36); header.writeUInt32LE(pcm.length, 40);
  writeFileSync(resolve(out, 'audition.wav'), Buffer.concat([header, pcm]));
  const { pcm: _, ...report } = result;
  report.networkRequests = requests.length; report.pageErrors = errors;
  writeFileSync(resolve(out, 'audio-report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
} finally { await browser.close(); }

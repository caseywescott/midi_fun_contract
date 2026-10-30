// Optional real-browser smoke check. Install Playwright locally, or set PLAYWRIGHT_MODULE
// to its index.mjs. Run against `npm run serve:labs`; no RPC is used.
import assert from 'node:assert/strict';
import { mkdirSync } from 'node:fs';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const base = process.argv[2] || 'http://127.0.0.1:8788';
const out = process.argv[3] || '/tmp/beasts-v3-lab-preview';
mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const errors = [], remote = [];
const context = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
await context.route('**/*', (route) => {
  const url = route.request().url();
  if (/^https?:/.test(url) && !url.startsWith(base + '/')) { remote.push(url); return route.abort(); }
  return route.continue();
});
const page = await context.newPage();
page.on('pageerror', (e) => errors.push(e.message));
const ready = () => page.waitForFunction(() => document.querySelector('#art')?.complete && document.querySelector('#art')?.naturalWidth === 250 && document.querySelectorAll('.beast-midi-notes').length === 1);
const sameMidi = async () => assert.equal(await page.evaluate(() => JSON.stringify(window.__notesMidi) === JSON.stringify(window.__loadedMidi) && window.__loadedMidi?.length > 14), true, 'audio and notes must use identical MIDI');
const canvasHash = () => page.evaluate(() => {
  const c = document.querySelector('.beast-midi-notes');
  return c.getContext('2d').getImageData(0, 0, c.width, c.height).data.reduce((a, v) => (a * 31 + v) >>> 0, 0);
});
try {
  for (const name of (process.env.LAB_PAGES?.split(',') || ['drift-lab', 'editions-onchain', 'lab'])) {
    const route = name === 'lab' ? '#b=21' : '?track=song&b=21&e=1&p=1&day=1';
    await page.goto(base + '/onchain/' + name + '.html' + route);
    await ready();
    await page.evaluate(() => {
      const Constructor = window.WebAudioTinySynth;
      window.WebAudioTinySynth = function (...args) {
        const synth = new Constructor(...args), load = synth.loadMIDI;
        synth.loadMIDI = (bytes) => { window.__loadedMidi = Array.from(new Uint8Array(bytes)); return load(bytes); };
        return synth;
      };
      const show = cardPreview.show;
      cardPreview.show = (selection, midi) => { window.__notesMidi = Array.from(midi); return show(selection, midi); };
    });
    await page.click('#play');
    await page.waitForTimeout(700);
    await sameMidi();
    const first = await canvasHash();
    await page.waitForTimeout(700);
    assert.notEqual(await canvasHash(), first, 'notes must move while playing');
    if (name === 'drift-lab') {
      await page.evaluate(() => { const day = document.querySelector('#day'); day.value = 61; day.dispatchEvent(new Event('input')); });
      await sameMidi();
      for (const selector of ['#echo', '#ab', '#t-edition', '#e-next', '#p-next', '#b-next']) { await page.click(selector); await sameMidi(); }
    } else if (name === 'editions-onchain') {
      await page.selectOption('#fx', '3'); await sameMidi();
      for (const selector of ['#e-next', '#s-next', '#b-next', '#i-old']) { await page.click(selector); await sameMidi(); }
    } else {
      await page.check('#shiny'); await sameMidi();
      await page.selectOption('#beast', '74'); await sameMidi();
      for (const selector of ['#t-genesis', '#t-yeti']) { await page.click(selector); await sameMidi(); }
      await page.selectOption('#speed', '1'); await sameMidi();
    }
    await ready();
    assert.equal(await page.locator('.beast-midi-notes').count(), 1, 'old notes canvases must be removed');
    await page.screenshot({ path: `${out}/${name}-desktop.png`, fullPage: true });
    await page.click('#stop');
    const stopped = await canvasHash();
    await page.waitForTimeout(300);
    assert.equal(await canvasHash(), stopped, 'notes must stand still after stop');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(base + '/onchain/' + name + '.html' + route);
    await ready();
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, name + ': mobile horizontal overflow');
    await page.screenshot({ path: `${out}/${name}-mobile.png`, fullPage: true });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.click('#play');
    const reduced = await canvasHash();
    await page.waitForTimeout(300);
    assert.equal(await canvasHash(), reduced, 'reduced-motion notes must stand still');
    await page.click('#stop');
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    await page.setViewportSize({ width: 1280, height: 1000 });
    console.log(name + ': identical audio/visual MIDI, live notes, controls, cleanup, stop, desktop and mobile passed');
  }
  assert.deepEqual(errors, []);
  assert.deepEqual(remote, []);
  console.log('No page errors or external network requests. Screenshots: ' + out);
} finally { await browser.close(); }

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
const logo = () => page.evaluate(async () => {
  const svg = new DOMParser().parseFromString(await (await fetch(document.querySelector('#art').src)).text(), 'image/svg+xml');
  return {
    tier: Number([...svg.querySelectorAll('text')].find((e) => e.textContent === 'TIER').nextElementSibling.textContent),
    fill: svg.querySelector('#logoPulse path').getAttribute('fill'),
  };
});
const canvasHash = () => page.evaluate(() => {
  const c = document.querySelector('.beast-midi-notes');
  return c.getContext('2d').getImageData(0, 0, c.width, c.height).data.reduce((a, v) => (a * 31 + v) >>> 0, 0);
});
try {
  for (const name of (process.env.LAB_PAGES?.split(',') || ['drift-lab', 'editions-onchain', 'lab'])) {
    const route = name === 'lab' ? '#b=21' : '?track=song&b=21&e=1&p=1&day=1';
    await page.goto(base + '/onchain/' + name + '.html' + route);
    await ready();
    if (name === 'drift-lab') {
      const logos = await page.evaluate(async () => {
        const results = [], img = document.querySelector('#art');
        for (const sp of DATA.species) for (const shiny of [false, true]) {
          cardPreview.show({ id: sp.id, shiny, name: sp.name }, selectedMidi());
          await img.decode();
          const svg = new DOMParser().parseFromString(await (await fetch(img.src)).text(), 'image/svg+xml');
          results.push({ id: sp.id, tier: sp.tier, shiny, fill: svg.querySelector('#logoPulse path').getAttribute('fill') });
        }
        return results;
      });
      // Canonical regular tier palette and shiny gradient from the official renderer.
      const expected = { 1: '#ff8800', 2: '#8c00bf', 3: '#0000ff', 4: '#00ff00', 5: '#ffffff' };
      assert.equal(logos.length, 150);
      for (const logo of logos) assert.equal(logo.fill, logo.shiny ? 'url(#logo_pastel_rainbow)' : expected[logo.tier], `species ${logo.id}, shiny ${logo.shiny}: incorrect logo`);
      console.log('All 75 species: regular logo matches tier, shiny logo retains rainbow');
      await page.reload(); await ready();
    }
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
      for (const tab of ['tracks', 'genesis', 'drift', 'yeti', 'sc']) {
        await page.click('#t-' + tab); await sameMidi();
        const colors = ['#ff8800', '#8c00bf', '#0000ff', '#00ff00', '#ffffff'];
        for (let tier = 1; tier <= 5; tier++) {
          await page.selectOption('#beast', String((tier - 1) * 5));
          for (const shiny of [false, true]) {
            await page.setChecked('#shiny', shiny); await sameMidi();
            assert.deepEqual(await logo(), { tier, fill: shiny ? 'url(#logo_pastel_rainbow)' : colors[tier - 1] }, tab + ': incorrect card tier or logo');
          }
        }
        console.log('Lab ' + tab + ': all five tier colors, shiny rainbow and matching MIDI passed');
      }
      // Undoing swaps while stopped must redraw the selected track's opening notes too.
      await page.click('#t-genesis');
      await page.selectOption('#swapA', '21'); await page.selectOption('#swapB', '1');
      await page.click('#swapgo'); await sameMidi();
      await page.click('#stop');
      const swapped = await page.evaluate(() => JSON.stringify(window.__notesMidi));
      await page.click('#gsclear');
      assert.equal(await page.evaluate(() => JSON.stringify(window.__notesMidi) === JSON.stringify(Array.from(activeMidi))), true, 'Genesis undo-all must refresh idle notes');
      assert.notEqual(await page.evaluate(() => JSON.stringify(window.__notesMidi)), swapped, 'undo-all must show the restored track');
      await page.click('#t-yeti'); await page.click('#play'); await sameMidi();
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

// Headless check of public/onchain/cue-demo.html (Playwright; set PLAYWRIGHT_MODULE to its index.mjs if
// it is not installed here, and CHROMIUM_PATH to a Chromium or headless-shell binary). Plays every Beast, checks cues fire on the audio clock, BeatSync frames
// follow the real clock in tempo mode and CueSync's warped clock in music mode (held at the final
// cadence), the climax hit, no page errors and no requests, and saves screenshots.
//   node onchain/cues/demo-check.mjs [out-dir]
import assert from 'node:assert/strict';
import { mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const here = fileURLToPath(new URL('.', import.meta.url));
const out = process.argv[2] || '/tmp/cue-demo-check';
mkdirSync(out, { recursive: true });
const url = pathToFileURL(here + '../../public/onchain/cue-demo.html').href;
const browser = await chromium.launch({ headless: true, args: ['--autoplay-policy=no-user-gesture-required'], ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}) });
const errors = [], requests = [], stats = [];
try {
  const context = await browser.newContext({ viewport: { width: 1200, height: 1000 } });
  await context.route('**/*', (route) => { const u = route.request().url(); if (!u.startsWith('file:') && !u.startsWith('data:')) { requests.push(u); return route.abort(); } return route.continue(); });
  const page = await context.newPage();
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.goto(url);
  await page.waitForFunction(() => window.DEMO_STATE && document.querySelectorAll('.pick button').length === 5);
  const count = await page.evaluate(() => DATA.beasts.length);
  await page.click('#play');
  await page.waitForFunction(() => DEMO_STATE.cs.tick != null, null, { timeout: 10000 });
  const wait = (ms) => page.waitForTimeout(ms);
  // jump the audio to a tick (the frame clock and cue firing follow the audible tick)
  const seek = (tick) => page.evaluate((t) => { DEMO_STATE.synth.locateMIDI(t); }, tick);
  // seek and wait until what is heard has got there (tinysynth's look-ahead lags the jump)
  const seekHeard = async (tick) => { await seek(tick); await page.waitForFunction((t) => { const x = DEMO_STATE.cs.tick; return x != null && x >= t && x < t + 1920; }, tick, { timeout: 8000 }); };

  for (let i = 0; i < count; i++) {
    await page.click(`.pick button:nth-child(${i + 1})`);
    await page.waitForFunction(() => DEMO_STATE.playing && DEMO_STATE.cs.tick != null, null, { timeout: 10000 });
    const info = await page.evaluate(() => { const b = DATA.beasts[DEMO_STATE.beast]; return { name: b.name, gif: b.gif, frames: DEMO_STATE.beat ? DEMO_STATE.beat.frames : 0, cues: b.cues.cues, length: b.cues.length }; });
    // music mode from the top: sections, entries and bars fire within ~2.5 s
    await page.selectOption('#fmode', 'music');
    await page.evaluate(() => { DEMO_STATE.fired.length = 0; });
    await seekHeard(0);
    const samples = [];
    for (let k = 0; k < 10; k++) { await wait(250); samples.push(await page.evaluate(() => ({ tick: DEMO_STATE.cs.tick, shown: DEMO_STATE.beat ? DEMO_STATE.beat.shown : -1, transform: document.getElementById('art').style.transform }))); }
    const fired = await page.evaluate(() => DEMO_STATE.fired.map((f) => f.type));
    assert.ok(fired.includes('section') && fired.includes('entry') && fired.includes('bar'), `${info.name}: cues fired ${fired.join(',')}`);
    const rising = samples.slice(1).filter((s, k) => s.tick > samples[k].tick).length;
    assert.ok(rising >= samples.length - 2, `${info.name}: the audible tick advances ${samples.map((s) => Math.round(s.tick)).join(',')}`);
    assert.ok(samples.some((s) => s.transform && s.transform !== ''), `${info.name}: the cue layer moves the art`);
    if (info.gif) assert.ok(new Set(samples.map((s) => s.shown)).size >= 2, `${info.name}: GIF frames step`);
    else assert.equal(info.frames, 0, `${info.name}: static art has no BeatSync`);

    // climax: the hit (hue rotation) right after the climax tick
    const climax = info.cues.find((c) => c.type === 'climax');
    await seek(Math.max(0, climax.tick - 240));
    await page.waitForFunction((t) => DEMO_STATE.cs.tick >= t && DEMO_STATE.cs.tick < t + 960, climax.tick, { timeout: 5000 });
    await wait(60);
    const hit = await page.evaluate(() => document.getElementById('art').style.filter);
    assert.match(hit, /hue-rotate\((?!0deg)\d+deg\)/, `${info.name}: climax flash (${hit})`);
    if (i === 0) await page.screenshot({ path: `${out}/climax.png` });

    // final cadence: frames hold while the audio runs on (music mode), and step again in tempo mode
    if (info.gif) {
      const hold = info.length - Math.floor((info.length - info.cues.find((c) => c.type === 'cadence' && c.final).tick) / 2);
      await seek(hold + 60);
      await page.waitForFunction((t) => DEMO_STATE.cs.tick >= t, hold + 60, { timeout: 5000 });
      const held = [];
      for (let k = 0; k < 4; k++) { held.push(await page.evaluate(() => ({ shown: DEMO_STATE.beat.shown, tick: DEMO_STATE.cs.tick }))); await wait(120); }
      const inHold = held.filter((h) => h.tick >= hold && h.tick < info.length - 30);
      assert.ok(inHold.length >= 2 && new Set(inHold.map((h) => h.shown)).size === 1, `${info.name}: frames hold through the final cadence ${JSON.stringify(held)}`);
      if (i === 0) await page.screenshot({ path: `${out}/final-cadence.png` });
      // tempo mode: BeatSync on the real synth clock, no cue layer
      await page.selectOption('#fmode', 'tempo');
      const tempo = await page.evaluate(() => ({ same: DEMO_STATE.cs.frameSynth() === DEMO_STATE.synth, transform: document.getElementById('art').style.transform }));
      assert.equal(tempo.same, true, `${info.name}: tempo mode = today's BeatSync clock`);
      await wait(100);
      assert.equal(await page.evaluate(() => document.getElementById('art').style.transform), '', `${info.name}: tempo mode leaves the art alone`);
      await page.selectOption('#fmode', 'music');
    }
    // the frame modes: BeatSync shows the frame CueSync asks for, each mode's frame follows its track,
    // and the effects switch is independent; frame changes per second are reported (jitter)
    if (info.gif) {
      await page.check('#fx');
      for (const m of ['melody', 'contour', 'harmony']) {
        await page.selectOption('#fmode', m);
        assert.equal(await page.evaluate(() => [DEMO_STATE.mode, DEMO_STATE.effects, document.getElementById('fmode').selectedOptions[0].textContent].join('|')),
          `${m}|true|${{ melody: 'Melody steps', contour: 'Contour', harmony: 'Harmony' }[m]}`);
        await seekHeard(0);
        // 3 s of every animation frame: the frame shown, the frame asked for, the frame due from the track
        const r = await page.evaluate((mode) => new Promise((done) => {
          const cs = DEMO_STATE.cs, beat = DEMO_STATE.beat, tr = cs.tracks, n = beat.frames, rows = [];
          const lastAt = (arr, t) => { let k = -1; for (let i = 0; i < arr.length && arr[i][0] <= t; i++) k = i; return k; };
          const due = (t) => {
            const i = lastAt(mode === 'harmony' ? tr.harmony : tr.melody, t);
            if (mode === 'melody') return (i + 1) % n;
            if (mode === 'harmony') return i < 0 ? 0 : Math.round(tr.harmony[i][1] * (n - 1) / 3);
            let k = 0; for (let j = 1; j <= i; j++) k = (k + Math.sign(tr.melody[j][1] - tr.melody[j - 1][1]) + n) % n; return k;
          };
          const t0 = performance.now();
          (function f() {
            const t = cs.tick;
            if (t != null) rows.push({ t, shown: beat.shown, asked: cs.frame, due: due(t) });
            if (performance.now() - t0 < 3000) requestAnimationFrame(f); else done(rows);
          })();
        }), m);
        const agree = r.filter((x) => x.asked === x.due).length / r.length, shown = r.filter((x) => x.shown === x.asked).length / r.length;
        assert.ok(r.length > 30 && agree > 0.9 && shown > 0.85, `${info.name} ${m}: asked=due ${agree.toFixed(2)}, shown=asked ${shown.toFixed(2)} over ${r.length}`);
        const changes = r.slice(1).filter((x, k) => x.shown !== r[k].shown).length, secs = (r.at(-1).t - r[0].t) / 480 * (info.cues.length ? 1 : 1);
        const distinct = new Set(r.map((x) => x.shown)).size;
        stats.push({ beast: info.name, mode: m, frames: info.frames, distinct, changesPer3s: changes, tempoSecs: secs });
        assert.ok(distinct >= 2, `${info.name} ${m}: only ${distinct} frame(s) in 3 s`);
      }
      // harmony lands on frame 0 at the final cadence's arrival
      const arrival = await page.evaluate(() => { const h = DEMO_STATE.cs.tracks.harmony; return h[h.length - 1]; });
      assert.equal(arrival[1], 0);
      await page.selectOption('#fmode', 'harmony');
      await seek(arrival[0] + 30);
      await page.waitForFunction((t) => DEMO_STATE.cs.tick >= t, arrival[0] + 30, { timeout: 5000 });
      await wait(80);
      assert.equal(await page.evaluate(() => DEMO_STATE.beat.shown), 0, `${info.name}: harmony rests on frame 0 at the final cadence`);
      // effects off: frame logic alone, the art untouched
      await page.uncheck('#fx');
      await wait(120);
      assert.equal(await page.evaluate(() => document.getElementById('art').style.transform), '', `${info.name}: effects off leaves the art alone`);
      // m cycles the modes
      const cyc = [];
      for (let k = 0; k < 5; k++) { await page.keyboard.press('m'); cyc.push(await page.evaluate(() => DEMO_STATE.mode)); }
      assert.deepEqual(cyc, ['tempo', 'music', 'melody', 'contour', 'harmony']);
      await page.selectOption('#fmode', 'music');
    }
    console.log(`ok ${info.name}: ${info.gif ? info.frames + '-frame GIF' : 'static'}, fired ${new Set(fired).size} cue types in 2.5 s, climax ${hit.match(/hue-rotate\([^)]*\)/)[0]}`);
  }
  await seek(0);
  await page.click('.pick button:nth-child(1)');
  await wait(1800);
  await page.screenshot({ path: `${out}/desktop.png`, fullPage: true });
  await page.setViewportSize({ width: 390, height: 900 });
  await wait(400);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert.equal(overflow, false, 'no horizontal scroll at phone width');
  await page.screenshot({ path: `${out}/mobile.png`, fullPage: true });
  await page.click('#play');
  assert.deepEqual(errors, [], 'no page errors');
  assert.deepEqual(requests, [], 'no network requests');
  for (const x of stats) console.log(`  ${x.beast.padEnd(28)} ${x.mode.padEnd(8)} ${x.frames} frames, ${x.distinct} shown, ${x.changesPer3s} frame changes in 3 s`);
  console.log(`cue demo ok: ${count} Beasts, screenshots in ${out}`);
} finally {
  await browser.close();
}

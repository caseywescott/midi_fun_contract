// Offline browser check of the TinySynth page: open each token's real animation_url (decoded from
// its token_uri) in headless Chromium with every network request blocked, tap, and verify playback.
//   npm i --no-save playwright-core@1.62.1   (matches Chromium build 1234; any matching pair works)
//   PLAYWRIGHT_CORE=/path/to/node_modules/playwright-core node onchain/browser-check.mjs
//
// Prints one JSON line per page and exits non-zero on any failed check. Extra arguments are files
// holding Beast token_uris returned by a deployed NFT (e.g. from integration/e2e_devnet.mjs); they
// are checked the same way, as bare scores at the tempo their MIDI declares.
import { TINYCHIP_ONCHAIN } from './tinychip/config.mjs';
import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { encodeTokenId, engine } from '../src/index.js';
import { tokenUri } from './page.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const { chromium } = await import(process.env.PLAYWRIGHT_CORE ? pathToFileURL(process.env.PLAYWRIGHT_CORE + '/index.mjs').href : 'playwright-core');
const stored = readFileSync(here + 'dist/stored.b64', 'utf8');
const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));

const beastMidi = (tokenId, live) => Uint8Array.from(engine.toMidiFile(engine.render(engine.decodeTokenId(BigInt(tokenId)), { ...live, summit_held_seconds: 0 })));
const heaviestId = encodeTokenId({ id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 });

/** A one-bar score that picks its own instruments (marimba, bass) and plays a hi-hat: not bare. */
function writtenScore() {
  const ev = [0, 0xff, 0x51, 3, 0x07, 0xa1, 0x20, 0, 0xc0, 12, 0, 0xc1, 33];
  const notes = [60, 62, 64, 67, 69, 67, 64, 62];
  notes.forEach((n, i) => {
    ev.push(0, 0x90, n, 100);
    if (i === 0) ev.push(0, 0x91, 36, 90);
    if (i % 2 === 0) ev.push(0, 0x99, 42, 70);
    ev.push(0x81, 0x40, 0x80, n, 64); // 200 ticks later
  });
  ev.push(0, 0x81, 36, 64, 0, 0xff, 0x2f, 0);
  const u32 = (v) => [v >>> 24, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
  return Uint8Array.from([0x4d, 0x54, 0x68, 0x64, ...u32(6), 0, 0, 0, 1, 1, 0xe0, 0x4d, 0x54, 0x72, 0x6b, ...u32(ev.length), ...ev]);
}

/** First tempo meta event (FF 51 03) of a MIDI file, as BPM. */
function midiTempo(midi) {
  for (let i = 0; i + 5 < midi.length; i++) if (midi[i] === 0xff && midi[i + 1] === 0x51 && midi[i + 2] === 3) return 60e6 / ((midi[i + 3] << 16) | (midi[i + 4] << 8) | midi[i + 5]);
  return 120;
}
const jsonOf = (uri) => (uri.startsWith('data:application/json;utf8,') ? JSON.parse(decodeURIComponent(uri.slice(27))) : JSON.parse(Buffer.from(uri.slice(uri.indexOf(',') + 1), 'base64').toString('utf8')));
const midiOfUri = (uri) => {
  const meta = jsonOf(uri);
  const html = Buffer.from(meta.animation_url.slice(meta.animation_url.indexOf(',') + 1), 'base64').toString('utf8');
  return Uint8Array.from(Buffer.from(html.match(/id="midi">([^<]*)<\/script>/)[1].replace(/\s+/g, ''), 'base64'));
};

const PAGES = [
  { name: 'genesis Warlock (bare Beast score)', midi: beastMidi(fx.token_id, fx.live), bare: true, tempo: 60e6 / 455000 },
  { name: 'heaviest Beast score', midi: beastMidi(heaviestId, { adventurers_killed: 200, scars: 63, rank: 1, species_count: 1243 }), bare: true, tempo: 60e6 / 455000 },
  { name: 'score with its own instruments', midi: writtenScore(), bare: false, tempo: 60e6 / 500000, programs: { 0: 12, 1: 33 } },
];

for (const file of process.argv.slice(2)) {
  const uri = readFileSync(file, 'utf8').trim();
  const midi = midiOfUri(uri);
  PAGES.push({ name: file.split('/').pop(), uri, midi, bare: true, tempo: midiTempo(midi) });
}

const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
let failed = 0;
for (const p of PAGES) {
  const context = await browser.newContext({ offline: true });
  const requests = [];
  await context.route('**/*', (route) => { requests.push(route.request().url().slice(0, 60)); route.abort(); });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  const uri = p.uri ?? tokenUri(stored, fx.members, fx.svg_b64, p.midi);
  const meta = jsonOf(uri);
  await page.goto(meta.animation_url);
  await page.waitForFunction(() => document.querySelector('body > img')?.complete);
  const art = await page.evaluate(() => { const i = document.querySelector('body > img'); return { w: i.naturalWidth, h: i.naturalHeight }; });
  const midiOk = await page.evaluate((n) => window.SOUND.midi?.length === n, p.midi.length);

  await page.mouse.click(200, 200); // the gesture that starts audio
  await page.waitForFunction(() => window.SOUND.synth?.getPlayStatus().play === 1);
  const audio = await page.evaluate(() => {
    const s = window.SOUND.synth;
    const an = s.actx.createAnalyser(); an.fftSize = 2048; s.comp.connect(an);
    window.__peak = 0;
    window.__notes = [];
    const note = s._note;
    s._note = (t, ch, n, v, prog) => { window.__notes.push(ch); return note(t, ch, n, v, prog); };
    window.__timer = setInterval(() => { const d = new Float32Array(an.fftSize); an.getFloatTimeDomainData(d); for (const x of d) window.__peak = Math.max(window.__peak, Math.abs(x)); }, 20);
    return { state: s.actx.state, loopEnd: s.loopEnd, maxTick: s.maxTick, timebase: s.song.timebase, bare: window.SOUND.bare, orchestration: window.SOUND.orchestration };
  });
  await page.waitForTimeout(2500);
  // Tempo and program changes take effect as TinySynth plays them, so read them once it has.
  const played = await page.evaluate(() => {
    const s = window.SOUND.synth;
    return { peak: window.__peak, channels: [...new Set(window.__notes)].sort((a, b) => a - b), tick: s.getPlayStatus().curTick, tempo: s.song.tempo, pg: s.pg.slice(0, 10) };
  });
  Object.assign(audio, { tempo: played.tempo, pg: played.pg });
  // Stop (tap again), then the restart button, which plays from the top.
  await page.mouse.click(200, 200);
  const stopped = await page.evaluate(() => window.SOUND.synth.getPlayStatus().play);
  await page.click('button[aria-label="Restart"]');
  const restarted = await page.evaluate(() => ({ play: window.SOUND.synth.getPlayStatus().play, tick: window.SOUND.synth.getPlayStatus().curTick, label: document.querySelector('button[aria-label="Stop sound"]') !== null }));
  // Let the loop wrap at least once on the short score.
  let wrapped = null;
  if (!p.bare) {
    const loopSec = (audio.loopEnd / (audio.timebase / 4)) * (60 / audio.tempo);
    let maxTick = 0, sawWrap = false;
    for (let t = 0; t < loopSec * 2.2 * 1000; t += 100) {
      const tick = await page.evaluate(() => window.SOUND.synth.getPlayStatus().curTick);
      if (tick < maxTick) sawWrap = true;
      maxTick = Math.max(maxTick, tick);
      await page.waitForTimeout(100);
    }
    wrapped = sawWrap && (await page.evaluate(() => window.SOUND.synth.getPlayStatus().play)) === 1;
  }

  const checks = {
    art: art.w > 0 && art.h > 0,
    midi: midiOk,
    running: audio.state === 'running',
    tempo: Math.abs(audio.tempo - p.tempo) < 1e-9,
    loopWholeBars: audio.loopEnd % audio.timebase === 0 && audio.loopEnd >= audio.maxTick,
    // bare Beast scores take the TinyChip orchestration when the pack is stored onchain
    orchestration: audio.bare === p.bare && audio.orchestration === (p.bare && TINYCHIP_ONCHAIN ? 'tinychip-1' : 1)
      // the player's own lead is program 128; TinyChip's lead (its program 0) sits at 129
      && (p.bare ? played.channels.filter((c) => c !== 9).every((c) => audio.pg[c] === (TINYCHIP_ONCHAIN ? 129 : 128)) && played.channels.includes(9)
        : Object.entries(p.programs).every(([c, g]) => audio.pg[c] === g)),
    sound: played.peak > 0.001,
    stop: stopped === 0,
    restart: restarted.play === 1 && restarted.tick < 480 && restarted.label,
    loop: wrapped !== false,
    offline: requests.length === 0,
    errors: errors.length === 0,
  };
  const ok = Object.values(checks).every(Boolean);
  if (!ok) failed++;
  console.log(JSON.stringify({ page: p.name, ok, checks, midiBytes: p.midi.length, tempo: audio.tempo, loopEnd: audio.loopEnd, channels: played.channels, peak: +played.peak.toFixed(3), requests, errors }));
  await context.close();
}
await browser.close();
process.exit(failed ? 1 : 0);

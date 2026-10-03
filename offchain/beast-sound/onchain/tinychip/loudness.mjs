// Match the loudness of every TinyChip preset and write the gains into tinysynth-chip.js.
//   PUPPETEER_CORE=/path/to/node_modules/puppeteer-core node onchain/tinychip/loudness.mjs   (after onchain/build.mjs)
//   (CHROME=/path/to/chrome to override the browser; default: macOS Google Chrome)
//
// Each preset plays the same 5-note phrase (E3 B3 E4 B4 E5, 0.3 s each, velocity 100) on channel 1
// through tinysynth's own output chain (including its compressor), rendered offline in Chrome. The
// render passes through a K-weighting filter (ITU-R BS.1770: +4 dB high shelf near 1.7 kHz, 38 Hz
// high-pass), and loudness is the mean-square level of the phrase in dB. Gains move every preset to
// the pack's median; the compressor makes this slightly nonlinear, so it repeats until every preset
// is within TOLERANCE_DB.
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const TOLERANCE_DB = 0.5, MAX_ROUNDS = 6;
const puppeteer = (await import(process.env.PUPPETEER_CORE ? pathToFileURL(process.env.PUPPETEER_CORE + '/lib/esm/puppeteer/puppeteer-core.js').href : 'puppeteer-core')).default;
const tinysynth = readFileSync(here + '../dist/tinysynth.min.js', 'utf8'); // the pinned, patched build the page uses
const pack = readFileSync(here + 'tinysynth-chip.js', 'utf8');

const dir = mkdtempSync(join(tmpdir(), 'tinychip-'));
writeFileSync(join(dir, 'ts.js'), tinysynth);
writeFileSync(join(dir, 'pack.js'), pack);
writeFileSync(join(dir, 'measure.html'), `<!doctype html><body><script src="ts.js"></script><script src="pack.js"></script><script>
window.addEventListener('unhandledrejection', (e) => e.preventDefault());
window.measure = async (gains) => {
  const SR = 44100, NOTES = [52, 59, 64, 71, 76], ON = 0.3, GAP = 0.05, SLOT = NOTES.length * (ON + GAP) + 0.4;
  const P = TinyChipBank.PRESETS, off = new OfflineAudioContext(1, Math.ceil(SR * (P.length * SLOT + 0.5)), SR);
  const shelf = off.createBiquadFilter(); shelf.type = 'highshelf'; shelf.frequency.value = 1681; shelf.gain.value = 4;
  const hp = off.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 38; hp.Q.value = 0.5;
  shelf.connect(hp); hp.connect(off.destination);
  const synth = new WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 4096 });
  synth.setAudioContext(off, shelf);
  TinyChipBank.install(synth, { gains });
  P.forEach((pr, i) => {
    synth.send([0xc0, pr.program], 0);
    NOTES.forEach((n, j) => { const t = 0.05 + i * SLOT + j * (ON + GAP); synth.send([0x90, n, 100], t); synth.send([0x80, n, 0], t + ON); });
  });
  const d = (await off.startRendering()).getChannelData(0);
  return P.map((pr, i) => {
    const a = Math.floor((0.05 + i * SLOT) * SR), b = Math.floor((0.05 + i * SLOT + NOTES.length * (ON + GAP) + 0.2) * SR);
    let ms = 0; for (let k = a; k < b; k++) ms += d[k] * d[k];
    return 10 * Math.log10(ms / (b - a) + 1e-12);
  });
};
</script>`);

const browser = await puppeteer.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: 'new', args: ['--allow-file-access-from-files'] });
const page = await browser.newPage();
await page.goto(pathToFileURL(join(dir, 'measure.html')).href, { waitUntil: 'load' });
const presets = await page.evaluate(() => TinyChipBank.PRESETS.map((p) => p.name));
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return (s[(s.length - 1) >> 1] + s[s.length >> 1]) / 2; };

let gains = presets.map(() => 1), loud, target, spread;
const before = await page.evaluate((g) => window.measure(g), gains);
target = median(before);
loud = before;
for (let round = 1; round <= MAX_ROUNDS; round++) {
  gains = gains.map((g, i) => g * 10 ** ((target - loud[i]) / 20));
  loud = await page.evaluate((g) => window.measure(g), gains);
  spread = Math.max(...loud.map((l) => Math.abs(l - target)));
  console.log(`round ${round}: worst deviation ${spread.toFixed(2)} dB`);
  if (spread < TOLERANCE_DB) break;
}
await browser.close();

const range = (xs) => `${(Math.min(...xs) - target).toFixed(1)} to +${(Math.max(...xs) - target).toFixed(1)} dB`;
console.log(`before: ${range(before)} around the median · after: ${range(loud)}`);
const src = readFileSync(here + 'tinysynth-chip.js', 'utf8').replace(/  const LOUDNESS = \[[^\]]*\];/, `  const LOUDNESS = [${gains.map((g) => +g.toFixed(3)).join(', ')}];`);
writeFileSync(here + 'tinysynth-chip.js', src);
writeFileSync(here + 'loudness.json', JSON.stringify({ target_db: +target.toFixed(2), tolerance_db: TOLERANCE_DB, presets: presets.map((name, i) => ({ program: i, name, before_db: +(before[i] - target).toFixed(2), after_db: +(loud[i] - target).toFixed(2), gain: +gains[i].toFixed(3) })) }, null, 1));
console.log('wrote LOUDNESS into tinysynth-chip.js and loudness.json');

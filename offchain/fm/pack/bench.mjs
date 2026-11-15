// Chrome timings and a worker-path check for the pack against the reference bank script.
//   node pack/bench.mjs [runs=5]
// Serves offchain/fm on localhost, loads pack/bench.html with each bank script, alternating, and reports medians:
// evalMs (script loaded and bank built), needMs/soundMs (a typical track's zones ready / first notes scheduled),
// allFirstMs (every instrument's first take rendered), and checks that the zones the pack's workers rendered
// hash the same as the reference's.
import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const root = fileURLToPath(new URL('..', import.meta.url)), runs = +(process.argv[2] ?? 5);
const PW = process.env.PW ?? '/Volumes/Extreme SSD/Generative_Music_Series/.beast-sound-cache/pw/node_modules/playwright-core';
const { chromium } = createRequire(import.meta.url)(PW);
const server = createServer((req, res) => { const f = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://x').pathname)); if (!f.startsWith(root) || !existsSync(f)) { res.writeHead(404); return res.end(); } res.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript' }[extname(f)] ?? 'application/octet-stream' }); res.end(readFileSync(f)); }).listen(0);
const port = server.address().port, banks = { reference: 'kankyo.min.js', pack: 'dist/loot-fm-pack.min.js' };
const browser = await chromium.launch({ channel: 'chrome', args: ['--autoplay-policy=no-user-gesture-required', '--enable-precise-memory-info'] });
async function run(bank, mode) {
  const page = await browser.newPage(); page.on('pageerror', (e) => console.error('page error', e.message));
  await page.goto(`http://localhost:${port}/pack/bench.html?bank=/${banks[bank]}&mode=${mode}`);
  await page.waitForFunction(() => window.RESULT, null, { timeout: 300000, polling: 50 });
  const r = await page.evaluate(() => window.RESULT); await page.close(); return r;
}
const med = (xs) => { const s = [...xs].sort((a, b) => a - b); return +s[s.length >> 1].toFixed(1); };
const out = {};
for (const mode of (process.env.MODES ?? 'first,all,serial').split(',')) for (let i = 0; i < runs; i++) for (const bank of Object.keys(banks)) { const r = await run(bank, mode); for (const [k, v] of Object.entries(r)) ((out[bank] ??= {})[k] ??= []).push(v); }
const summary = Object.fromEntries(Object.entries(out).map(([b, o]) => [b, Object.fromEntries(Object.entries(o).map(([k, v]) => [k, { median: med(v), runs: v.map((x) => Math.round(x)) }]))]));
console.log(JSON.stringify(summary, null, 1));
// worker-path parity: hashes of every first take as rendered in the browser's workers
const [a, b] = [await run('reference', 'hash'), await run('pack', 'hash')];
const same = a.hashes.length === b.hashes.length && a.hashes.every((h, i) => h.join() === b.hashes[i].join());
console.log(`first takes rendered in Chrome workers: ${b.hashes.length}, ${same ? 'all identical to the reference' : 'DIFFERENT'}`);
if (!same) process.exitCode = 1;
await browser.close(); server.close();

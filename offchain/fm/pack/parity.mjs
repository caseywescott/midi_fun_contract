// Sound parity: every zone and take of the Kankyo bank rendered by the reference (the worker engine inside
// kankyo.min.js) and by the pack's engine, compared sample by sample.
//   node pack/parity.mjs [engine module, default pack/engine.js] [instrument filter regex] [--defs dist bank defs]
import { loadReference, workerEngine } from './ref.mjs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const [engFile = 'pack/engine.js', filter = '.', ...rest] = process.argv.slice(2);
const { zone } = await import(pathToFileURL(resolve(engFile)).href);
const ref = loadReference(), old = workerEngine(ref.text);
const owner = (ix) => ref.bank.instruments.find((i) => i.sample === ix || i.takes?.includes(ix)).id.replace(/-\d+$/, '').replace(/^tom$/, 'tom');
// the definitions the pack renders: by default the reference's own; with --pack, the ones the pack decodes
let jobs = ref.jobs.map((j, ix) => ({ id: owner(ix), a: j.a }));
if (rest[0] === '--pack') { const { packJobs } = await import(pathToFileURL(resolve(rest[1] ?? 'pack/data.mjs')).href); const mine = packJobs(); if (mine.length !== jobs.length) throw new Error(`job count ${mine.length} vs ${jobs.length}`); jobs = jobs.map((j, i) => ({ ...j, b: mine[i] })); }
const per = {}; let tOld = 0, tNew = 0, worst = 0;
for (const j of jobs) {
  if (!new RegExp(filter).test(j.id)) continue;
  const [d, m, k, t] = j.a, b = j.b ?? j.a;
  let t0 = performance.now(); const x = old(d, m, k, t); tOld += performance.now() - t0;
  t0 = performance.now(); const y = zone(b[0], b[1], b[2], b[3] < 0 ? undefined : b[3]).make(); tNew += performance.now() - t0;
  const p = (per[j.id] ??= { zones: 0, samples: 0, differing: 0, maxAbs: 0, lenMismatch: 0 });
  p.zones++; p.samples += x.length;
  if (x.length !== y.length) { p.lenMismatch++; continue; }
  for (let i = 0; i < x.length; i++) if (x[i] !== y[i] && !(x[i] !== x[i] && y[i] !== y[i])) { p.differing++; const e = Math.abs(x[i] - y[i]); if (!(e <= p.maxAbs)) p.maxAbs = e; }
  worst = Math.max(worst, p.maxAbs);
}
for (const [id, p] of Object.entries(per)) console.log(id.padEnd(12), String(p.zones).padStart(3), 'zones', String(p.samples).padStart(8), 'samples', p.differing ? `${p.differing} differ, max |d| ${p.maxAbs.toExponential(2)} (${(p.maxAbs / 32768).toExponential(2)} FS)` : 'bit-identical', p.lenMismatch ? `LENGTH MISMATCH ${p.lenMismatch}` : '');
console.log(`render time: reference ${(tOld / 1000).toFixed(1)} s, pack ${(tNew / 1000).toFixed(1)} s; worst |d| ${worst} = ${(worst / 32768).toExponential(2)} of full scale`);
process.exitCode = Object.values(per).some((p) => p.lenMismatch || p.maxAbs / 32768 >= 1e-6) ? 1 : 0;

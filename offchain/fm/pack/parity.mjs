// Sound parity: every zone and take of the Kankyo bank rendered by the reference (the worker engine inside
// kankyo.min.js) and by the pack, compared sample by sample, plus the bank's instrument table.
//   node pack/parity.mjs [--dist dist/loot-fm-pack.min.js | --engine pack/engine.js] [instrument regex]
// --dist (default) runs the built pack script itself (its main-thread renderer, the same code its workers run);
// --engine renders the reference's own definitions with an engine module (for working on the engine).
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { loadReference, workerEngine } from './ref.mjs';
const args = process.argv.slice(2), mode = args[0]?.startsWith('--') ? args.shift() : '--dist', file = args[0] && !/^[a-z|.()-]*$/i.test(args[0]) || args[0]?.includes('/') ? args.shift() : (mode === '--dist' ? 'dist/loot-fm-pack.min.js' : 'pack/engine.js'), filter = new RegExp(args[0] ?? '.');
const ref = loadReference(), old = workerEngine(ref.text);
const owner = (ix) => ref.bank.instruments.find((i) => i.sample === ix || i.takes?.includes(ix)).id.replace(/-\d+$/, '');
let renderNew;
if (mode === '--dist') {
  const win = {}, fail = () => { throw new Error('no workers here'); };
  new Function('window', 'self', 'navigator', 'URL', 'Blob', 'Worker', 'setTimeout', readFileSync(file, 'utf8'))(win, win, {}, { createObjectURL: fail }, class {}, class {}, () => 0);
  const bank = win.LootFmPack.bank, strip = (i) => JSON.stringify({ ...i, credit: undefined, last: undefined });
  if (bank.instruments.length !== ref.bank.instruments.length || bank.samples.length !== ref.bank.samples.length) throw new Error('bank shape differs');
  bank.instruments.forEach((i, n) => { if (strip(i) !== strip(ref.bank.instruments[n])) throw new Error(`instrument ${i.id} differs:\n${strip(i)}\n${strip(ref.bank.instruments[n])}`); });
  bank.samples.forEach((s, n) => { const r = ref.bank.samples[n]; if (s.rate !== r.rate || s.loopStart !== r.loopStart || s.smoothing !== r.smoothing || s.ready !== r.ready) throw new Error('sample metadata differs ' + n); });
  console.log(`instrument table: ${bank.instruments.length} instruments, ${bank.samples.length} samples, identical`);
  renderNew = (ix) => bank.samples[ix].render();
} else {
  const { zone } = await import(pathToFileURL(resolve(file)).href);
  renderNew = (ix) => { const [d, m, k, t] = ref.jobs[ix].a; return zone(d, m, k, t < 0 ? undefined : t).make(); };
}
const per = {}; let tOld = 0, tNew = 0, worst = 0;
ref.jobs.forEach((j, ix) => {
  const id = owner(ix); if (!filter.test(id)) return;
  const [d, m, k, t] = j.a;
  let t0 = performance.now(); const x = old(d, m, k, t); tOld += performance.now() - t0;
  t0 = performance.now(); const y = renderNew(ix); tNew += performance.now() - t0;
  const p = (per[id] ??= { zones: 0, samples: 0, differing: 0, maxAbs: 0, lenMismatch: 0 });
  p.zones++; p.samples += x.length;
  if (x.length !== y.length) { p.lenMismatch++; return; }
  for (let i = 0; i < x.length; i++) if (x[i] !== y[i] && !(x[i] !== x[i] && y[i] !== y[i])) { p.differing++; const e = Math.abs(x[i] - y[i]); if (!(e <= p.maxAbs)) p.maxAbs = e; }
  worst = Math.max(worst, p.maxAbs);
});
for (const [id, p] of Object.entries(per)) console.log(id.padEnd(12), String(p.zones).padStart(3), 'zones', String(p.samples).padStart(8), 'samples', p.differing ? `${p.differing} differ, max |d| ${p.maxAbs.toExponential(2)} (${(p.maxAbs / 32768).toExponential(2)} of full scale)` : 'bit-identical', p.lenMismatch ? `LENGTH MISMATCH ${p.lenMismatch}` : '');
console.log(`${mode} ${file}: render time reference ${(tOld / 1000).toFixed(1)} s, pack ${(tNew / 1000).toFixed(1)} s (one thread); worst |d| ${worst} = ${(worst / 32768).toExponential(2)} of full scale`);
process.exitCode = Object.values(per).some((p) => p.lenMismatch || p.maxAbs / 32768 >= 1e-6) ? 1 : 0;

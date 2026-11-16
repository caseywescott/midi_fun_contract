// Sound parity: every zone and take of the Kankyo bank rendered by the reference (the worker engine inside
// kankyo.min.js) and by the pack, compared sample by sample, plus the bank's instrument table. Then extra takes
// the bank does not hold, for the instruments that use the engine's section/formant/fm-violin, `nmod` and `bend`
// paths (their settings follow the pitch): each zone at its root + 2 semitones, as a take beyond the bank's
// (take T for an instrument with T takes) and plain (no take), and at its root as that extra take.
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
let renderNew, renderAny;
if (mode === '--dist') {
  const win = {}, fail = () => { throw new Error('no workers here'); };
  new Function('window', 'self', 'navigator', 'URL', 'Blob', 'Worker', 'setTimeout', readFileSync(file, 'utf8'))(win, win, {}, { createObjectURL: fail }, class {}, class {}, () => 0);
  const bank = win.LootFmPack.bank, strip = (i) => JSON.stringify({ ...i, credit: undefined, last: undefined });
  if (bank.instruments.length !== ref.bank.instruments.length || bank.samples.length !== ref.bank.samples.length) throw new Error('bank shape differs');
  bank.instruments.forEach((i, n) => { if (strip(i) !== strip(ref.bank.instruments[n])) throw new Error(`instrument ${i.id} differs:\n${strip(i)}\n${strip(ref.bank.instruments[n])}`); });
  bank.samples.forEach((s, n) => { const r = ref.bank.samples[n]; if (s.rate !== r.rate || s.loopStart !== r.loopStart || s.smoothing !== r.smoothing || s.ready !== r.ready) throw new Error('sample metadata differs ' + n); });
  console.log(`instrument table: ${bank.instruments.length} instruments, ${bank.samples.length} samples, identical`);
  renderNew = (ix) => bank.samples[ix].render();
  // the same script loaded as its own worker renders any [instrument row, midi, zone, take]
  const wk = { postMessage: (y) => { wk.out = y; } };
  new Function('window', 'self', 'importScripts', readFileSync(file, 'utf8'))(undefined, wk, () => {});
  renderAny = (row, d, m, k, t) => { wk.onmessage({ data: [row, m, k, t] }); return wk.out; };
} else {
  const { zone } = await import(pathToFileURL(resolve(file)).href);
  renderNew = (ix) => { const [d, m, k, t] = ref.jobs[ix].a; return zone(d, m, k, t < 0 ? undefined : t).make(); };
  renderAny = (row, d, m, k, t) => zone(d, m, k, t < 0 ? undefined : t).make();
}
const per = {}; let tOld = 0, tNew = 0, worst = 0;
const compare = (id, [d, m, k, t], render) => {
  let t0 = performance.now(); const x = old(d, m, k, t); tOld += performance.now() - t0;
  t0 = performance.now(); const y = render(); tNew += performance.now() - t0;
  const p = (per[id] ??= { zones: 0, samples: 0, differing: 0, maxAbs: 0, lenMismatch: 0 });
  p.zones++; p.samples += x.length;
  if (x.length !== y.length) { p.lenMismatch++; return; }
  for (let i = 0; i < x.length; i++) if (x[i] !== y[i] && !(x[i] !== x[i] && y[i] !== y[i])) { p.differing++; const e = Math.abs(x[i] - y[i]); if (!(e <= p.maxAbs)) p.maxAbs = e; }
  worst = Math.max(worst, p.maxAbs);
};
ref.jobs.forEach((j, ix) => { const id = owner(ix); if (filter.test(id)) compare(id, j.a, () => renderNew(ix)); });
// extra takes for the pitch-dependent paths added with the 2026-11-16 bank
const FEATURES = { section: (d) => d.section, choir: (d) => d.choir, form: (d) => d.form, fmv: (d) => d.fmv, nmod: (d) => d.nmod, bend: (d) => d.bend };
const used = Object.fromEntries(Object.keys(FEATURES).map((f) => [f, []])), rows = [], seen = new Set();
ref.jobs.forEach((j, ix) => { const inst = ref.bank.instruments.find((i) => i.sample === ix); if (!inst || inst.drum !== undefined) return; const id = owner(ix); if (!seen.has(id)) { seen.add(id); rows.push({ id, d: j.a[0], zones: [] }); } rows.at(-1).zones.push(j.a); });
let extra = 0;
rows.forEach(({ id, d, zones }, row) => {
  const fs = Object.keys(FEATURES).filter((f) => FEATURES[f](d)); fs.forEach((f) => used[f].push(id));
  if (!fs.length || !filter.test(id)) return;
  const T = d.takes || 1, tx = T > 1 ? T : -1;
  for (const [, m, k] of zones) for (const a of [[d, m + 2, k, tx], ...(T > 1 ? [[d, m + 2, k, -1], [d, m, k, tx]] : [])]) { compare(id + '+', a, () => renderAny(row, ...a)); extra++; }
});
console.log('features:', Object.entries(used).map(([f, ids]) => `${f} ${ids.join(', ') || 'NONE'}`).join('; '));
const unused = Object.keys(used).filter((f) => !used[f].length);
if (unused.length) console.log('WARNING: no instrument exercises ' + unused.join(', '));
for (const [id, p] of Object.entries(per)) console.log(id.padEnd(12), String(p.zones).padStart(3), 'zones', String(p.samples).padStart(8), 'samples', p.differing ? `${p.differing} differ, max |d| ${p.maxAbs.toExponential(2)} (${(p.maxAbs / 32768).toExponential(2)} of full scale)` : 'bit-identical', p.lenMismatch ? `LENGTH MISMATCH ${p.lenMismatch}` : '');
console.log(`${mode} ${file}: render time reference ${(tOld / 1000).toFixed(1)} s, pack ${(tNew / 1000).toFixed(1)} s (one thread); worst |d| ${worst} = ${(worst / 32768).toExponential(2)} of full scale`);
console.log(`${ref.jobs.length} bank zone takes and ${extra} extra takes, ${rows.length} instruments + ${new Set(ref.bank.instruments.filter((i) => i.drum !== undefined).map((i) => i.id)).size} drums`);
process.exitCode = unused.length || Object.values(per).some((p) => p.lenMismatch || p.maxAbs / 32768 >= 1e-6) ? 1 : 0;

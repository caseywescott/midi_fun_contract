// Reference: the built Kankyo bank (kankyo.min.js) run in Node. Its worker script (the second copy of the
// engine, the one that renders in the lab) and its job list ([definition, midi, zone, take] per sample).
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
const here = fileURLToPath(new URL('..', import.meta.url));
export function loadReference(file = here + 'kankyo.min.js') {
  let text = readFileSync(file, 'utf8');
  // expose the job list; no workers, no timers
  text = text.replace('window.SnesBank={bank:', 'window.SnesBank={jobs:f0,bank:');
  if (!text.includes('jobs:f0')) throw new Error('could not patch reference');
  const win = {}, ctx = { window: win, navigator: {}, setTimeout: () => 0, URL: { createObjectURL() { throw new Error('no'); } }, Blob: class {}, Worker: class {}, console, atob: (s) => Buffer.from(s, 'base64').toString('binary') };
  vm.runInNewContext(text, ctx);
  return { bank: win.SnesBank.bank, jobs: win.SnesBank.jobs, text };
}
// the worker copy of the engine as a function (d, m, k, take) => Float32Array
export function workerEngine(text) {
  const start = text.indexOf('Y0=`'), end = text.indexOf('`', start + 4);
  if (start < 0) throw new Error('worker text not found');
  const W = vm.runInNewContext(text.slice(start + 3, end + 1));
  let out = null; const self = { postMessage: (y) => { out = y; } };
  new Function('self', W)(self); // in this realm (a vm context's global lookups are slow, which would flatter the pack)
  return (d, m, k, t) => { self.onmessage({ data: [d, m, k, t] }); return out; };
}

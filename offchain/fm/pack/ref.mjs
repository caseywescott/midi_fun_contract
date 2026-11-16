// Reference: the built Kankyo bank (kankyo.min.js) run in Node. Its worker script (the second copy of the
// engine, the one that renders in the lab) and its job list ([definition, midi, zone, take] per sample).
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
const here = fileURLToPath(new URL('..', import.meta.url));
export function loadReference(file = here + 'kankyo.min.js') {
  const orig = readFileSync(file, 'utf8'); let text = orig;
  // expose the job list (its minified name read from `need`, which loops over it); no workers, no timers
  const jobs = text.match(/for\(let ([\w$]+) of ([\w$]+)\)\1\.prog===/)?.[2];
  text = text.replace('window.SnesBank={bank:', `window.SnesBank={jobs:${jobs},bank:`);
  if (!jobs || !text.includes(`jobs:${jobs},`)) throw new Error('could not patch reference');
  const win = {}, ctx = { window: win, navigator: {}, setTimeout: () => 0, URL: { createObjectURL() { throw new Error('no'); } }, Blob: class {}, Worker: class {}, console, atob: (s) => Buffer.from(s, 'base64').toString('binary') };
  vm.runInNewContext(text, ctx);
  return { bank: win.SnesBank.bank, jobs: win.SnesBank.jobs, text: orig };
}
// the worker copy of the engine as a function (d, m, k, take) => Float32Array
export function workerEngine(text) {
  // the template literal holding the worker script (the one with self.onmessage)
  const m = [...text.matchAll(/[\w$]+=`/g)].map((x) => [x.index + x[0].length - 1, text.indexOf('`', x.index + x[0].length)]).find(([a, b]) => text.slice(a, b).includes('self.onmessage'));
  if (!m) throw new Error('worker text not found');
  const W = vm.runInNewContext(text.slice(m[0], m[1] + 1));
  let out = null; const self = { postMessage: (y) => { out = y; } };
  new Function('self', W)(self); // in this realm (a vm context's global lookups are slow, which would flatter the pack)
  return (d, m, k, t) => { self.onmessage({ data: [d, m, k, t] }); return out; };
}

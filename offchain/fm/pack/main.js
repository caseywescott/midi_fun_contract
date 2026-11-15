// The Loot FM pack: the Kankyo FM instruments as one script. Loaded in a page it builds the bank and starts
// rendering every instrument's key zones in background workers; loaded as a worker (by itself: the workers'
// script is this script's own source, `LootFmPack`, the function build.mjs wraps it in) it renders zones.
// Page API (window.LootFmPack, also window.SnesBank, the name the Loot lab loads bank scripts by):
//   bank                      the BSBRR1 bank: { format, name, samples, instruments } (samples render on demand)
//   need([[program, note]])   render those zones first (drums: program -1, note = key); a Promise when they are ready, .pending
//   ready()                   a Promise for every instrument's first take
//   progress()                { done, total } first takes rendered
//   createSampler(audioContext, options) / attach(tinySynth, options)   play the bank (runtime.js API)
//   version
import { zone, RATE } from './engine.js';
import { attach, createSampler } from './sampler.js';
import { decode } from './data.js';
const VERSION = 1;
const worker = typeof window === 'undefined' && typeof importScripts === 'function';
if (worker) {
  let set;
  self.onmessage = (e) => { set ??= decode(); const [r, m, k, t] = e.data, d = r < 0 ? set.drums[~r].d : set.inst[r].d, y = zone(d, m, k, t < 0 ? undefined : t).make(); self.postMessage(y, [y.buffer]); };
} else {
  const set = decode(), defOf = (r) => (r < 0 ? set.drums[~r].d : set.inst[r].d);
  const bank = { format: 'BSBRR1', name: 'kankyo', samples: [], instruments: [] }, jobs = [];
  // roughly how long a zone takes to render (samples x operators and filters), so that among zones of the same
  // priority the longest start first and the workers finish together
  const cost = (d, m) => { const z = d.zones ? d.zones[0] : d; return (d.sus ? d.pre + 65536 : (d.len ?? 2.5) * RATE * (m < 60 ? 1 : 0.8)) * (2 + (z.ops?.length ?? 2) + ((z.eq ?? d.eq)?.length ?? 0) / 2 + (d.air ? 4 : 0)); };
  const finish = (j, y) => { if (j.state === 2) return; j.state = 2; if (y) j.s.pcm = y; j.s.ready = true; j.wait.splice(0).forEach((f) => f()); };
  // a sample: rendered by a worker ahead of time, or here the moment it is played before that; playing a zone's
  // first take queues its other takes
  const add = (prog, lo, hi, take, z, r, m, k, pri) => {
    const s = { rate: RATE, loopStart: z.loopStart, smoothing: false, ...(take > 0 ? { ready: false } : {}), render: () => {
      if (!s.pcm) { s.pcm = z.make(); finish(j); }
      const p = s.pcm; s.pcm = null;
      if (take <= 0) for (const o of jobs) if (o.prog === prog && o.lo === lo && o.take > 0 && o.state === 0 && o.pri < 2) o.pri = 2;
      pump(); return p;
    } }, j = { s, a: [r, m, k, take], prog, lo, hi, take, pri, state: 0, wait: [], cost: cost(defOf(r), m) };
    jobs.push(j); return bank.samples.push(s) - 1;
  };
  set.inst.forEach(({ id, program, lo, hi, volume, env: [attack, decay, sustain, release], d }, r) => {
    for (let m = lo, k = 0; m <= hi; m += 4, k++) {
      const T = d.takes || 1, idx = [], keys = [k ? m - 1 : 0, m + 4 > hi ? 127 : m + 2]; let first;
      for (let t = 0; t < T; t++) { const z = zone(d, m, k, T > 1 ? t : undefined); first ??= z; idx.push(add(program, keys[0], keys[1], T > 1 ? t : -1, z, r, m, k, t ? -1 : 1)); }
      bank.instruments.push({ id: id + '-' + m, program, sample: idx[0], ...(T > 1 ? { takes: idx } : {}), ...(d.human ? { human: d.human } : {}), rootNote: m, tuneCents: first.tune, volume, envelope: { attack, decay, sustain, release }, keys, ...(d.slur ? { slur: 1 } : {}) });
    }
  });
  set.drums.forEach(({ id, key, volume, d }, r) => bank.instruments.push({ id, drum: key, sample: add(-1, key, key, -1, zone(d, 60, 0), ~r, 60, 0, 6), rootNote: key, tuneCents: 0, volume, envelope: { attack: 0, decay: 0, sustain: 1, release: 0.3 } }));
  let pool = [], timer = 0;
  try {
    // eslint-disable-next-line no-undef
    const url = URL.createObjectURL(new Blob(['(' + LootFmPack + ')()'], { type: 'text/javascript' }));
    for (let i = Math.max(1, Math.min(6, (navigator.hardwareConcurrency || 4) - 1)); i--;) {
      const w = new Worker(url);
      w.onmessage = (e) => { const j = w.job; w.job = null; finish(j, j.state === 2 ? null : e.data); pump(); };
      w.onerror = () => { const j = w.job; w.job = null; pool = pool.filter((x) => x !== w); if (j && j.state === 1) j.state = 0; pump(); };
      pool.push(w);
    }
  } catch (e) { pool = []; }
  const next = () => { let b = null; for (const j of jobs) if (j.state === 0 && j.pri > 0 && (!b || j.pri > b.pri || (j.pri === b.pri && j.cost > b.cost))) b = j; return b; };
  function pump() {
    if (pool.length) { for (const w of pool) { if (w.job) continue; const j = next(); if (!j) return; j.state = 1; w.job = j; w.postMessage(j.a); } }
    else if (!timer) timer = setTimeout(() => { timer = 0; const j = next(); if (j) { j.s.pcm = zone(defOf(j.a[0]), j.a[1], j.a[2], j.a[3] < 0 ? undefined : j.a[3]).make(); finish(j); pump(); } }, 20);
  }
  const need = (list) => {
    const ps = [];
    for (const [prog, note] of list) for (const j of jobs) if (j.prog === prog && j.take <= 0 && note >= j.lo && note <= j.hi && j.state !== 2) { if (j.state === 0) j.pri = 5; ps.push(new Promise((f) => j.wait.push(f))); }
    pump(); const p = Promise.all(ps); p.pending = ps.length > 0; return p;
  };
  const firsts = jobs.filter((j) => j.take <= 0);
  setTimeout(pump, 0);
  const api = { bank, need, version: VERSION,
    ready: () => Promise.all(firsts.filter((j) => j.state !== 2).map((j) => new Promise((f) => j.wait.push(f)))),
    progress: () => ({ done: firsts.filter((j) => j.state === 2).length, total: firsts.length }),
    attach: (s, o) => attach(s, bank, o), createSampler: (a, o) => createSampler(a, bank, o) };
  window.SnesBank = window.LootFmPack = api;
}

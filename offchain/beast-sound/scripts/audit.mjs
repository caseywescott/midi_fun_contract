// Whole-collection audit: render every one of the 93,225 genesis-species identities.
//
//   node scripts/audit.mjs [--engine 2] [--state calm|veteran|both] [--species 1-75] [--threads N]
//
// Reports render failures (any Beast that cannot be rendered), distinct melodies (motif hashes)
// and distinct scores. A melody is shared when two identities get the same motif hash.
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { cpus } from 'node:os';
import { fileURLToPath } from 'node:url';

const STATES = {
  // No history: lowest stretto, fewest sections.
  calm: { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 600, species_count: 1243 },
  // Everything maxed: tightest stretto, 5 sections, scars, crown, Summit glory.
  veteran: { adventurers_killed: 200, scars: 63, summit_held_seconds: 500 * 3600, rank: 1, species_count: 1243 },
};

if (isMainThread) {
  const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : d; };
  const engineVersion = Number(arg('engine', 1));
  const states = arg('state', 'both') === 'both' ? ['calm', 'veteran'] : [arg('state')];
  const [s0, s1] = arg('species', '1-75').split('-').map(Number);
  const threads = Number(arg('threads', cpus().length));
  const jobs = [];
  for (let id = s0; id <= (s1 || s0); id++) jobs.push(id);
  const started = Date.now();
  for (const state of states) {
    const results = await Promise.all(Array.from({ length: threads }, (_, t) => new Promise((resolve, reject) => {
      const w = new Worker(fileURLToPath(import.meta.url), { workerData: { ids: jobs.filter((_, i) => i % threads === t), state, engineVersion } });
      w.on('message', resolve); w.on('error', reject);
    })));
    const motifs = new Map(), scores = new Set(), failures = [];
    let rendered = 0;
    for (const r of results) {
      rendered += r.rendered;
      failures.push(...r.failures);
      for (const [m, n] of r.motifs) motifs.set(m, (motifs.get(m) || 0) + n);
      for (const s of r.scores) scores.add(s);
    }
    const shared = [...motifs.values()].filter((n) => n > 1);
    console.log(`engine v${engineVersion} · ${state} · ${jobs.length} species · ${rendered + failures.length} identities`);
    console.log(`  failures          ${failures.length}${failures.length ? '  e.g. ' + failures.slice(0, 5).map((f) => `${f.id}/${f.prefix}/${f.suffix}: ${f.error}`).join('; ') : ''}`);
    console.log(`  distinct melodies ${motifs.size}  (${shared.length} melodies shared by ${shared.reduce((a, b) => a + b, 0)} identities; largest group ${Math.max(0, ...motifs.values())})`);
    console.log(`  distinct scores   ${scores.size}`);
  }
  console.log(`  time ${((Date.now() - started) / 1000).toFixed(0)} s on ${threads} threads`);
} else {
  const { composeBeast, genesisBeast } = await import('../src/index.js');
  const { ids, state, engineVersion } = workerData;
  const motifs = new Map(), scores = [], failures = [];
  let rendered = 0;
  for (const id of ids) {
    for (let v = 0; v < 1243; v++) {
      const prefix = v === 0 ? 0 : 1 + Math.floor((v - 1) / 18), suffix = v === 0 ? 0 : 1 + ((v - 1) % 18);
      const beast = genesisBeast({ id, prefix, suffix, level: 80, health: 300 });
      const live = { ...STATES[state], rank: prefix === 0 ? 0 : STATES[state].rank };
      try {
        const song = composeBeast(beast, live, { engineVersion });
        const m = song.motifHash.toString();
        motifs.set(m, (motifs.get(m) || 0) + 1);
        scores.push(song.scoreHash.toString());
        rendered++;
      } catch (e) {
        failures.push({ id, prefix, suffix, error: e.message });
      }
    }
  }
  parentPort.postMessage({ rendered, failures, motifs: [...motifs], scores });
}

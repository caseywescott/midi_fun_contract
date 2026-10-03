// Engine v2 parity: offchain engine_v2.js vs the Cairo reference (v2_parity_fixture).
//
//   scarb test -- --include-ignored --filter v2_parity_fixture | grep V2PARITY > /tmp/v2parity.txt
//   node scripts/beast_v2_parity.mjs /tmp/v2parity.txt           # compare
//   node scripts/beast_v2_parity.mjs /tmp/v2parity.txt --write   # also refresh test/golden_v2.json
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { engine as E, engineV2 as V2, poseidonHashMany } from '../offchain/beast-sound/src/index.js';

const B = (id, prefix, suffix, level, health, shiny, animated, tier, beast_type) => ({ id, prefix, suffix, level, health, shiny, animated, tier, beast_type });
const L = (kills, scars, hours, rank, count) => ({ adventurers_killed: kills, scars, summit_held_seconds: hours * 3600, rank, species_count: count });

// Must match src/tests/test_beast_engine_v2.cairo::v2_parity_fixture.
export const CASES = [
  [B(1, 57, 15, 126, 229, 0, 0, 1, 0), L(0, 0, 0, 500, 954)],
  [B(1, 57, 15, 126, 229, 0, 0, 1, 0), L(40, 9, 25, 1, 954)],
  [B(29, 0, 0, 1, 100, 1, 1, 1, 1), L(3, 0, 0, 0, 1200)],
  [B(47, 13, 6, 22, 60, 0, 1, 5, 1), L(1, 4, 2, 300, 1100)],
  [B(76, 12, 4, 30, 80, 1, 0, 3, 2), L(100, 20, 456, 2, 40)],
  [B(51, 61, 13, 180, 900, 1, 1, 1, 2), L(70, 3, 400, 1, 1100)],
];

export function fingerprintV2(beast, live) {
  const r = V2.renderV2(beast, live);
  const midi = E.bytesToFelts(E.eventsToMidi(r.form.events, r.params.tempo_us, E.formLength(r.form)));
  return {
    score: r.form.score_hash.toString(), events: String(r.form.events.length),
    checksum: E.eventChecksum(r.form.events).toString(),
    midi_len: String(midi[0]), midi_hash: poseidonHashMany(midi).toString(),
  };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.includes('V2PARITY'));
  if (lines.length !== CASES.length) throw new Error(`expected ${CASES.length} V2PARITY lines, got ${lines.length}`);
  let failures = 0;
  const golden = [];
  CASES.forEach(([b, l], i) => {
    const js = fingerprintV2(b, l);
    const cairo = Object.fromEntries(lines[i].trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
    for (const k of Object.keys(js)) {
      if (js[k] !== cairo[k]) { failures += 1; console.log(`case ${i} ${k.padEnd(9)} FAIL js=${js[k]} cairo=${cairo[k]}`); }
    }
    golden.push({ beast: b, live: l, expected: Object.fromEntries(Object.keys(js).map((k) => [k, cairo[k]])) });
  });
  console.log(failures === 0 ? `V2 PARITY: all ${CASES.length} cases match Cairo (${CASES.length * 5} checks)` : `V2 PARITY: ${failures} mismatches`);
  if (failures === 0 && process.argv.includes('--write')) {
    const out = new URL('../offchain/beast-sound/test/golden_v2.json', import.meta.url);
    writeFileSync(out, JSON.stringify({ source: 'src/tests/test_beast_engine_v2.cairo::v2_parity_fixture', cases: golden }, null, 1) + '\n');
    console.log('wrote', decodeURIComponent(out.pathname));
  }
  process.exit(failures === 0 ? 0 : 1);
}

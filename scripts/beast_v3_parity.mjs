// Parity: offchain engine (offchain/beast-sound) vs the Cairo reference (beast_v3_parity_fixture).
//
//   scarb test -- --include-ignored --filter beast_v3_parity_fixture | grep PARITY > /tmp/parity.txt
//   node scripts/beast_v3_parity.mjs /tmp/parity.txt           # compare
//   node scripts/beast_v3_parity.mjs /tmp/parity.txt --write   # also refresh golden fixtures
//
// Run from midi_fun_contract/ after `npm install` in offchain/beast-sound.
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';

// Must match the cases in src/tests/test_beast_v3_sound.cairo::beast_v3_parity_fixture.
export const CASES = [
  [{ id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 }, { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954 }],
  [{ id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 }, { adventurers_killed: 40, scars: 9, summit_held_seconds: 90000, rank: 1, species_count: 954 }],
  [{ id: 29, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 1, animated: 1, tier: 1, beast_type: 1 }, { adventurers_killed: 3, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1200 }],
  [{ id: 47, prefix: 13, suffix: 6, level: 22, health: 60, shiny: 0, animated: 1, tier: 5, beast_type: 1 }, { adventurers_killed: 1, scars: 4, summit_held_seconds: 7200, rank: 300, species_count: 1100 }],
  [{ id: 76, prefix: 12, suffix: 4, level: 30, health: 80, shiny: 1, animated: 0, tier: 3, beast_type: 2 }, { adventurers_killed: 100, scars: 20, summit_held_seconds: 1642000, rank: 2, species_count: 40 }],
];

export function fingerprint(beast, live) {
  const r = E.render(beast, live);
  const midi = E.bytesToFelts(E.toMidiFile(r));
  const bsn = E.bytesToFelts(E.encodeBsn(r));
  return {
    seed: r.seed.toString(), params: r.params_hash.toString(), score: r.form.score_hash.toString(),
    state: r.state_hash.toString(), events: String(r.form.events.length), checksum: E.eventChecksum(r.form.events).toString(),
    midi_len: String(midi[0]), midi_hash: poseidonHashMany(midi).toString(),
    bsn_len: String(bsn[0]), bsn_hash: poseidonHashMany(bsn).toString(),
  };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.includes('PARITY'));
  if (lines.length !== CASES.length) throw new Error(`expected ${CASES.length} PARITY lines, got ${lines.length}`);
  let failures = 0;
  const golden = [];
  CASES.forEach(([b, live], i) => {
    const js = fingerprint(b, live);
    const cairo = Object.fromEntries(lines[i].trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
    for (const k of Object.keys(js)) {
      if (js[k] !== cairo[k]) { failures += 1; console.log(`case ${i} ${k.padEnd(9)} FAIL js=${js[k]} cairo=${cairo[k]}`); }
    }
    // The client path: BSN1 felts -> decoder -> MIDI must equal the Cairo MIDI file.
    const r = E.render(b, live);
    const roundTrip = poseidonHashMany(E.bytesToFelts(E.bsnToMidi(E.bytesToFelts(E.encodeBsn(r))))).toString();
    if (roundTrip !== cairo.midi_hash) { failures += 1; console.log(`case ${i} bsn->midi FAIL`); }
    golden.push({ beast: b, live, expected: Object.fromEntries(Object.keys(js).map((k) => [k, cairo[k]])) });
  });
  console.log(failures === 0 ? `PARITY: all ${CASES.length} cases match Cairo (${CASES.length * 11} checks)` : `PARITY: ${failures} mismatches`);
  if (failures === 0 && process.argv.includes('--write')) {
    const out = new URL('../offchain/beast-sound/test/golden.json', import.meta.url);
    writeFileSync(out, JSON.stringify({ source: 'src/tests/test_beast_v3_sound.cairo::beast_v3_parity_fixture', cases: golden }, null, 1) + '\n');
    console.log('wrote', decodeURIComponent(out.pathname));
  }
  process.exit(failures === 0 ? 0 : 1);
}

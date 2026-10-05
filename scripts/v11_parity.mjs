// Parity: composer v1.1 (offchain/beast-sound/src/engine_v11.js with the compare page's options:
// same mode, even phrases, history) against Cairo (contracts/beast_music: beast_v11, v11_parity_fixture).
// Compares each case's note count, section length, events hash and self-contained MIDI hash.
//   (cd contracts/beast_music && scarb test -- --include-ignored --filter v11_parity_fixture | grep V11 > /tmp/v11.txt)
//   node scripts/v11_parity.mjs /tmp/v11.txt
import { readFileSync } from 'node:fs';
import { engine as E, poseidonHashMany } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { beastFullMidi } from '../offchain/beast-sound/src/full_midi.js';

const v11 = createEngineV11(E), OPTIONS = { keys: 'mode', even: true, traj: true };

// Must match v11_case in contracts/beast_music/src/tests.cairo.
export function v11Case(id) {
  const named = id % 3 !== 0;
  const beast = {
    id, prefix: named ? (id % 69) + 1 : 0, suffix: named ? (id % 18) + 1 : 0,
    level: [5, 40, 120, 255][id % 4], health: [80, 150, 600, 1023][Math.floor(id / 3) % 4],
    shiny: id % 2, animated: Math.floor(id / 5) % 2, tier: Math.floor(((id - 1) % 25) / 5) + 1, beast_type: Math.floor((id - 1) / 25),
  };
  const live = [
    { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954 },
    { adventurers_killed: 40, scars: 9, summit_held_seconds: 0, rank: 1, species_count: 954 },
    { adventurers_killed: 3, scars: 30, summit_held_seconds: 0, rank: 50, species_count: 954 },
    { adventurers_killed: 500, scars: 63, summit_held_seconds: 0, rank: 0, species_count: 1243 },
    { adventurers_killed: 7, scars: 7, summit_held_seconds: 0, rank: 2, species_count: 0 },
    { adventurers_killed: 8, scars: 20, summit_held_seconds: 0, rank: 10, species_count: 954 },
  ][id % 6];
  return [beast, live];
}

const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('V11 '));
if (lines.length !== 75) throw new Error(`expected 75 V11 lines, got ${lines.length}`);
let failures = 0;
const branches = { stretto: 0, inversion: 0, sequence: 0, rise: 0, fall: 0, alternate: 0, wide: 0, normal: 0, close: 0, trill: 0, countersubject: 0 };
for (const line of lines) {
  const cairo = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const [beast, live] = v11Case(Number(cairo.case));
  const r = v11.render(beast, live, OPTIONS), t = r.v11.trajectory;
  if (r.form.sections.length > 1) branches[t.development]++;
  branches[t.direction > 0 ? 'rise' : t.direction < 0 ? 'fall' : 'alternate']++;
  branches[t.spacing]++;
  if (t.trill) branches.trill++;
  if (r.params.use_countersubject) branches.countersubject++;
  const flat = [...r.form.events].sort((a, b) => a.voice_id - b.voice_id || a.time - b.time).flatMap((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id].map(BigInt));
  const midi = E.bytesToFelts(beastFullMidi(r, E.formLength));
  const js = {
    notes: String(r.form.events.length), ticks: String(r.form.section_ticks),
    events: poseidonHashMany(flat).toString(), midi_len: String(midi[0]), midi: poseidonHashMany(midi).toString(),
  };
  for (const k of Object.keys(js)) if (js[k] !== cairo[k]) { failures++; console.log(`case ${cairo.case} ${k}: js ${js[k]} cairo ${cairo[k]}`); }
}
console.log('branches covered:', JSON.stringify(branches));
console.log(failures === 0 ? `V11 PARITY: all ${lines.length} cases match Cairo (notes, section length, events, MIDI)` : `V11 PARITY: ${failures} mismatches`);
process.exit(failures === 0 ? 0 : 1);

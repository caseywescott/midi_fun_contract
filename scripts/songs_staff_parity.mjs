// Parity: staffed Species Songs (the reference evolution on the Genesis Track's inputs). The Cairo
// fixture (beasts/beast_contracts pure_composer_tests songs_staff_parity_fixture) prints
// compose_staff's file per case; this resolves the same staff with offchain/beast-sound/src/evolution.js
// and composes it with lab.js genesisMidi, and compares.
//   cd beasts/beast_contracts && scarb test -- songs_staff_parity_fixture --include-ignored | grep '^SGS' > /tmp/sgs.txt
//   node scripts/songs_staff_parity.mjs /tmp/sgs.txt
import { readFileSync } from 'node:fs';
import { engine } from '../offchain/beast-sound/src/index.js';
import { createEngineV11 } from '../offchain/beast-sound/src/engine_v11.js';
import { genesisMidi, sampleTrackMidi, GENESIS_DEFAULTS } from '../offchain/beast-sound/src/lab.js';
import { resolveEvolution } from '../offchain/beast-sound/src/evolution.js';
import { shortString } from '../offchain/beast-sound/src/engine.js';

const v11 = createEngineV11(engine);
const GENESIS_CHANNELS = { 1: 5, 2: 5, 3: 4, 4: 3, 5: 3 };
const tierOf = (id) => (id <= 75 ? Math.floor(((id - 1) % 25) / 5) + 1 : 2);
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('SGS '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const sp = +c.sp, staffBlock = BigInt(c.staff), src = { 39: 40, 40: 39 }[sp] || sp;
  const config = { first_milestone_age: 10, initial_unlock_bps: +c.unlock, unlock_step_bps: 0, max_extra_channels: +c.extra, max_tempo_delta_bpm: 4, max_velocity_delta: +c.vel, ornament_chance_bps: +c.orn };
  const hashOf = (b) => (b === staffBlock ? shortString('staff') : b + shortString('h'));
  const staff = resolveEvolution(config, { birth: c.birth, staff: c.staff, driftGroup: shortString('group'), hashOf }, 6 - GENESIS_CHANNELS[tierOf(src)]);
  const o = sp <= 75 ? genesisMidi(sp, false, engine, v11, { staff })
    : sampleTrackMidi({ id: sp, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 0, animated: 0, tier: 2, beast_type: 1 }, { species_count: 1 }, { ...GENESIS_DEFAULTS, staff }, engine, v11);
  const js = Buffer.from(o.midi).toString('hex');
  if (js !== c.hex) {
    failures++;
    let i = 0; while (i < js.length && js[i] === c.hex[i]) i++;
    console.log(`species ${sp}: js ${js.length / 2} B, cairo ${c.len} B, first difference at byte ${Math.floor(i / 2)} (mask ${staff.unlocked_extra_mask}, tempo ${staff.tempo_delta})`);
  }
}
console.log(`SONGS STAFF PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(failures === 0 && lines.length > 0 ? 0 : 1);

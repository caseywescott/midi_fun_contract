// Parity: staffed Monthly Track Editions. The Cairo fixture (beasts/beast_contracts
// pure_composer_tests editions_staff_parity_fixture) prints compose_staff's file per case; this
// resolves the same staff with offchain/beast-sound/src/evolution.js and composes it with
// editions_lite.js, and compares.
//   cd beasts/beast_contracts && scarb test -- editions_staff_parity_fixture --include-ignored | grep '^EDS' > /tmp/eds.txt
//   node scripts/editions_staff_parity.mjs /tmp/eds.txt
import { readFileSync } from 'node:fs';
import { editionMidi } from '../offchain/beast-sound/src/editions_lite.js';
import { resolveEvolution } from '../offchain/beast-sound/src/evolution.js';
import { shortString } from '../offchain/beast-sound/src/engine.js';
import { speciesRecords } from '../offchain/beast-sound/onchain/editions_cairo.mjs';

const SP = speciesRecords();
const lines = readFileSync(process.argv[2], 'utf8').split('\n').filter((l) => l.startsWith('EDS '));
let failures = 0;
for (const line of lines) {
  const c = Object.fromEntries(line.trim().split(/\s+/).slice(1).map((kv) => kv.split('=')));
  const sp = SP[+c.sp - 1], staffBlock = BigInt(c.staff);
  const config = { first_milestone_age: 10, initial_unlock_bps: +c.unlock, unlock_step_bps: 0, max_extra_channels: 5, max_tempo_delta_bpm: 4, max_velocity_delta: +c.vel, ornament_chance_bps: +c.orn };
  const hashOf = (b) => (b === staffBlock ? shortString('staff') : b + shortString('h'));
  const staff = resolveEvolution(config, { birth: c.birth, staff: c.staff, driftGroup: shortString('group'), hashOf }, sp.tier > 2 ? 1 : 0);
  const mega = c.fx === '1' || c.fx === '3';
  const js = Buffer.from(editionMidi(sp, mega, +c.e, BigInt(c.seed), staff).midi).toString('hex');
  if (js !== c.hex) {
    failures++;
    let i = 0; while (i < js.length && js[i] === c.hex[i]) i++;
    console.log(`edition ${c.e} species ${c.sp} fx ${c.fx}: js ${js.length / 2} B, cairo ${c.len} B, first difference at byte ${Math.floor(i / 2)} (mask ${staff.unlocked_extra_mask}, tempo ${staff.tempo_delta})`);
  }
}
console.log(`EDITIONS STAFF PARITY: ${lines.length - failures}/${lines.length} match`);
process.exit(failures === 0 && lines.length > 0 ? 0 : 1);

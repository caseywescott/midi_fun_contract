// A Beast track's staff (evolution) for pages and tooling, byte for byte the Cairo:
// beast_composer::inputs::evolution (config, milestone blocks, validation) and
// composition/evolution.cairo (resolve_evolution: the unlocked extra roles, the note seed and the
// tempo nudge). The manager reads the block hashes; here the caller supplies them.
import { poseidonHashMany } from '@scure/starknet';
import { shortString } from './engine.js';

export const MILESTONE_COUNT = 8;
const U64_MAX = (1n << 64n) - 1n;
const H = (...xs) => poseidonHashMany(xs.map((x) => (typeof x === 'string' ? shortString(x) : BigInt(x))));
const must = (ok, message) => { if (!ok) throw new Error(message); };

export function validateEvolutionConfig(c) {
  must(c.first_milestone_age >= 1, 'zero milestone age');
  must(BigInt(c.first_milestone_age) <= U64_MAX / 128n, 'milestone age too large');
  must(c.initial_unlock_bps + 7 * c.unlock_step_bps <= 10000, 'invalid unlock probability');
  must(c.max_extra_channels <= 5, 'too many extra channels');
  must(c.max_tempo_delta_bpm <= 4, 'invalid staff tempo range');
  must(c.max_velocity_delta <= 16, 'invalid staff velocity range');
  must(c.ornament_chance_bps <= 10000, 'invalid staff ornaments');
  must(c.max_tempo_delta_bpm > 0 || c.max_velocity_delta > 0 || c.ornament_chance_bps > 0, 'no staff variation');
}

/** The milestones reached by `staff`: birth + age * 2^k, k = 0..7 (blocks as bigint). */
export function milestoneBlocks(c, birth, staff) {
  validateEvolutionConfig(c);
  birth = BigInt(birth); staff = BigInt(staff);
  must(staff >= birth, 'staff before birth');
  const out = []; let age = BigInt(c.first_milestone_age);
  for (let i = 0; i < MILESTONE_COUNT; i++) {
    const block = birth + age;
    if (block > U64_MAX || block > staff) break;
    out.push(block); age *= 2n;
  }
  return out;
}

/**
 * The staff controls of a track born at `birth` and played at `staff`, its drift group and the
 * hashes of the staff block and of each milestone (`hashOf(block)`), with `availableExtra` roles
 * past its written channels.
 */
export function resolveEvolution(c, { birth, staff, driftGroup, hashOf }, availableExtra) {
  driftGroup = BigInt(driftGroup); // a felt: a bigint or a hex string, never a short string
  const milestones = milestoneBlocks(c, birth, staff).map((block) => ({ block, hash: BigInt(hashOf(block)) }));
  const staffHash = BigInt(hashOf(BigInt(staff)));
  must(staffHash !== 0n && milestones.every((m) => m.hash !== 0n), 'missing staff hash');
  const eligible = Math.min(availableExtra, c.max_extra_channels);
  let mask = 0;
  for (let feature = 0; feature < eligible; feature++) {
    for (let i = 0; i < milestones.length; i++) {
      const roll = H('BEAST_UNLOCK_V1', driftGroup, feature, milestones[i].block, milestones[i].hash);
      if (roll % 10000n < BigInt(c.initial_unlock_bps + i * c.unlock_step_bps)) { mask += 1 << feature; break; }
    }
  }
  const seed = H('BEAST_STAFF_V1', driftGroup, BigInt(staff), staffHash);
  const roll = Number((seed % (1n << 32n)) % BigInt(2 * c.max_tempo_delta_bpm + 1));
  return {
    unlocked_extra_mask: mask, note_seed: seed, tempo_delta: roll - c.max_tempo_delta_bpm,
    max_velocity_delta: c.max_velocity_delta, ornament_chance_bps: c.ornament_chance_bps,
    milestones,
  };
}

/** drift.cairo `nudge_tempo`: a tempo (microseconds per quarter) moved by `delta` BPM. */
export function nudgeTempo(tempoUs, delta) {
  const t = BigInt(tempoUs), d = 60000000n + BigInt(delta) * t;
  return Number((2n * 60000000n * t + d) / (2n * d));
}

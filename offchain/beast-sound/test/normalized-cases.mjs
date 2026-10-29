import { decodeInputs } from '../src/inputs.js';
const baseWire = [4,1,2,2,1,4,60,3,2,4,3,2,1,1,3,0,109,500000,47,1,1,2,0,1,2,0,0,1,37,4,1,17,0,1,0,1].map(BigInt);
export const SCORE_CASE_COUNT = 46;
export function normalizedCase(index) {
  const x = decodeInputs(baseWire).song;
  const changes = [null,
    () => x.theme.motif_seed = 12n, () => x.theme.tier = 5, () => x.theme.register_band = 0,
    () => x.score.mode_id = 5, () => x.score.tonic_keynum = 65, () => x.score.tier = 1,
    () => x.score.weakness = 1, () => x.score.voice_count = 3, () => x.score.section_count = 2,
    () => x.score.stretto_lag = 4, () => x.score.use_inversion = false,
    () => x.score.use_countersubject = false, () => x.score.ornament_density = 7,
    () => x.score.articulation_profile = 1, () => x.score.articulation_profile = 2,
    () => x.score.articulation_profile = 3, () => x.score.articulation_profile = 5,
    () => x.score.velocity_ceiling = 72, () => x.score.tempo_us = 400001,
    () => x.treatment.rhythm_seed = 27n, () => x.treatment.flip_side = false,
    () => x.treatment.development = 2, () => x.treatment.direction = 1,
    () => x.treatment.spacing = 2, () => x.treatment.trill = false, () => x.treatment.prominence = 0,
    () => x.arrangement.identity.source_species_id = 2n,
    () => x.arrangement.identity.name_variant_id = 38,
  ];
  if (!Number.isInteger(index) || index < 0 || index >= SCORE_CASE_COUNT) throw new Error('unknown normalized case');
  if (index >=29 && index <41) { x.score.mode_id = [4,5,6,7,8,26][(index-29)%6]; x.score.tonic_keynum = index <35 ?24:96; }
  else if (index >=41) {
    x.treatment.section_rhythm = true;
    if (index ===42) x.treatment.rhythm_seed = 0n;
    if (index ===43) x.theme.tier = 5;
    if (index ===44) x.score.ornament_density = 7;
    if (index ===45) { x.score.voice_count = 2; x.score.use_countersubject = false; x.arrangement.channel_count = 3; }
  } else changes[index]?.();
  return x;
}

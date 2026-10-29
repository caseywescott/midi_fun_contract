/** Canonical musical wire inputs. Integer seeds/u64 identities decode as bigint. */
export type Integer = number | bigint;
export interface MusicIdentity { source_species_id: Integer; name_variant_id: number }
export interface ThemeInputs { motif_seed: Integer; tier: number; register_band: number }
export interface ScoreInputs {
  mode_id: number; tonic_keynum: number; tier: number; weakness: number;
  voice_count: number; section_count: number; stretto_lag: number;
  use_inversion: boolean; use_countersubject: boolean; ornament_density: number;
  articulation_profile: number; velocity_ceiling: number; tempo_us: number;
}
export interface TreatmentInputs {
  rhythm_seed: Integer; flip_side: boolean; development: number; direction: number;
  spacing: number; trill: boolean; prominence: number; section_rhythm: boolean;
}
export type ChannelPolicy = { kind: 'Genesis' } | { kind: 'Seeded'; seed: Integer };
export type SpecialArrangement = { kind: 'None' } | { kind: 'Yeti'; name_variant_id: number };
export interface ArrangementInputs {
  family: number; identity: MusicIdentity; channel_count: number;
  channel_policy: ChannelPolicy; special: SpecialArrangement;
  top_lead: boolean; balanced: boolean; weak_ties: boolean;
}
export interface SongInputs {
  theme: ThemeInputs; score: ScoreInputs; treatment: TreatmentInputs; arrangement: ArrangementInputs;
}
export interface SoundCheckInputs {
  identity: MusicIdentity; mode_id: number; tonic_keynum: number; family: number;
  tempo_us: number; velocity_ceiling: number; articulation_profile: number;
}
/** A Monthly Track Edition's track (edition 1 and later; species 1..=75). */
export interface EditionInputs { identity: MusicIdentity; edition: number; seed: Integer }
export type ComposerInputs = { kind: 'Song'; song: SongInputs } | { kind: 'SoundCheck'; check: SoundCheckInputs }
  | { kind: 'Edition'; edition: EditionInputs };
export interface GenerationInputs { base_song: SongInputs }
export const COMPOSER_INPUTS_VERSION: 5;
export const EDITION_SPECIES_MAX: bigint;
export const GENERATION_INPUTS_VERSION: 2;
export const MAX_TEMPO_US: 1048575;
export const FIELD_P: bigint;
export function encodeInputs(inputs: ComposerInputs): bigint[];
export function decodeInputs(values: Integer[]): ComposerInputs;
export function encodeGenerationInputs(inputs: GenerationInputs): bigint[];
export function decodeGenerationInputs(values: Integer[]): GenerationInputs;

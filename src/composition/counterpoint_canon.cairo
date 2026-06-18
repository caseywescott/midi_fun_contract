//! Canon integration for linear counterpoint.
//!
//! Maps rhythm-tile leader motifs to multi-voice counterpoint and provides pitch
//! lookup for canon voice rendering.

use core::array::ArrayTrait;
use koji::composition::counterpoint::{
    CounterpointParams, ModeSpec, VoicePlacement, build_mode_timeline_with_masks,
    generate_n_voice_counterpoint_sparse, is_rest_pitch, mode_to_id, motion_bias_contrary,
    onset_mask_from_pitches,
};
use koji::composition::rhythmic_tiling::RhythmicCanon;
use koji::composition::symmetry_engine::add_pitch;
use koji::midi::modes::mode_steps;
use koji::midi::pitch::get_notes_of_key;
use koji::midi::types::{Modes, PitchClass};

#[derive(Drop, Serde)]
pub struct CanonHarmonyPlan {
    pub voices: Array<Array<u8>>,
    pub tile_len: u32,
    /// Per-tile onset mask (1 = sounding, 0 = rest) aligned with `voices`.
    pub onset_mask: Array<u32>,
}

/// 7-note Lydian pitch-world bitmask for `tonic` (matches symmetry-engine leaders).
pub fn lydian_pitch_world_mask(tonic: PitchClass) -> u16 {
    let steps = mode_steps(Modes::Lydian(()));
    let pcs = get_notes_of_key(tonic, steps);
    let mut mask: u16 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        mask = add_pitch(mask, *pcs.at(i));
        i += 1;
    };
    mask
}

/// Build a per-note mode timeline from section-local parameters (one entry per tile).
pub fn uniform_mode_timeline(
    tile_len: u32,
    mode: Modes,
    pitch_world_mask: u16,
    tonic: PitchClass,
) -> ModeSpec {
    let mut mode_ids: Array<u8> = ArrayTrait::new();
    let mut world_ids: Array<u16> = ArrayTrait::new();
    let mut transpositions: Array<u8> = ArrayTrait::new();
    let mut tonic_notes: Array<u8> = ArrayTrait::new();
    let mut tonic_octaves: Array<u8> = ArrayTrait::new();
    let mut pitch_world_masks: Array<u16> = ArrayTrait::new();
    let mid = mode_to_id(mode);
    let mut i: u32 = 0;
    loop {
        if i >= tile_len {
            break;
        }
        mode_ids.append(mid);
        world_ids.append(0);
        transpositions.append(0);
        tonic_notes.append(tonic.note);
        tonic_octaves.append(tonic.octave);
        pitch_world_masks.append(pitch_world_mask);
        i += 1;
    };
    ModeSpec::Timeline(
        build_mode_timeline_with_masks(
            mode_ids, world_ids, transpositions, tonic_notes, tonic_octaves, pitch_world_masks,
        ),
    )
}

pub fn canon_counterpoint_params(
    seed: felt252,
    mode_spec: ModeSpec,
    default_tonic: PitchClass,
    register_lo: u8,
    register_hi: u8,
) -> CounterpointParams {
    CounterpointParams {
        seed,
        tonic: default_tonic,
        mode_spec,
        register_lo,
        register_hi,
        max_melodic_leap: 12,
        motion_bias: motion_bias_contrary(),
        voice_placement: VoicePlacement::BelowCantus(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
        require_invertible_at_octave: false,
    }
}

/// Generate harmony voices for a canon leader motif (voice 0 = cantus).
///
/// Uses sparse onset alignment when the motif contains [`REST_PITCH`] rests.
pub fn plan_canon_harmony(
    cantus_motif: Span<u8>,
    base_params: @CounterpointParams,
    num_voices: u32,
) -> CanonHarmonyPlan {
    let mask = onset_mask_from_pitches(cantus_motif);
    plan_canon_harmony_sparse(cantus_motif, mask.span(), base_params, num_voices)
}

/// Generate harmony with explicit per-tile onset mask (1 = sounding, 0 = rest).
pub fn plan_canon_harmony_sparse(
    cantus_motif: Span<u8>,
    onset_mask: Span<u32>,
    base_params: @CounterpointParams,
    num_voices: u32,
) -> CanonHarmonyPlan {
    let tile_len: u32 = cantus_motif.len().try_into().unwrap();
    let voices = generate_n_voice_counterpoint_sparse(
        cantus_motif, onset_mask, base_params, num_voices,
    );
    CanonHarmonyPlan {
        tile_len,
        voices,
        onset_mask: span_to_mask_array(onset_mask),
    }
}

fn span_to_mask_array(mask: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= mask.len() {
            break;
        }
        out.append(*mask.at(i));
        i += 1;
    };
    out
}

/// True when `(voice_id, tile_idx)` is a rest (no note should sound).
pub fn harmony_plan_is_rest(plan: @CanonHarmonyPlan, voice_id: u32, tile_idx: u32) -> bool {
    assert(tile_idx < plan.onset_mask.len(), 'mask OOB');
    if *plan.onset_mask.at(tile_idx.try_into().unwrap()) == 0 {
        return true;
    }
    is_rest_pitch(pitch_from_harmony_plan(plan, voice_id, tile_idx))
}

/// Pitch for `(voice_id, tile_idx)` from a precomputed harmony plan.
pub fn pitch_from_harmony_plan(plan: @CanonHarmonyPlan, voice_id: u32, tile_idx: u32) -> u8 {
    assert(voice_id < plan.voices.len(), 'voice OOB');
    let voice = plan.voices.at(voice_id);
    assert(tile_idx < voice.len(), 'tile OOB');
    *voice.at(tile_idx.try_into().unwrap())
}

/// Convenience: leader motif + Lydian section params → multi-voice plan.
///
/// `world_mask` may be 0 to auto-build the 7-note Lydian collection for `tonic`.
pub fn plan_lydian_canon_harmony(
    seed: felt252,
    cantus_motif: Span<u8>,
    tonic: PitchClass,
    world_mask: u16,
    num_voices: u32,
) -> CanonHarmonyPlan {
    let tile_len: u32 = cantus_motif.len().try_into().unwrap();
    let pitch_world = if world_mask == 0 {
        lydian_pitch_world_mask(tonic)
    } else {
        world_mask
    };
    let mode_spec = uniform_mode_timeline(tile_len, Modes::Lydian(()), pitch_world, tonic);
    let params = canon_counterpoint_params(seed, mode_spec, tonic, 48, 84);
    plan_canon_harmony(cantus_motif, @params, num_voices)
}

/// Lydian canon harmony with explicit onset mask.
pub fn plan_lydian_canon_harmony_sparse(
    seed: felt252,
    cantus_motif: Span<u8>,
    onset_mask: Span<u32>,
    tonic: PitchClass,
    world_mask: u16,
    num_voices: u32,
) -> CanonHarmonyPlan {
    let tile_len: u32 = cantus_motif.len().try_into().unwrap();
    let pitch_world = if world_mask == 0 {
        lydian_pitch_world_mask(tonic)
    } else {
        world_mask
    };
    let mode_spec = uniform_mode_timeline(tile_len, Modes::Lydian(()), pitch_world, tonic);
    let params = canon_counterpoint_params(seed, mode_spec, tonic, 48, 84);
    plan_canon_harmony_sparse(cantus_motif, onset_mask, @params, num_voices)
}

/// Number of tiling-participant voices in a canon (for default voice count).
pub fn count_tiling_voices(canon: @RhythmicCanon) -> u32 {
    let mut count: u32 = 0;
    let voices = *canon.voices;
    let mut i: u32 = 0;
    loop {
        if i >= voices.len() {
            break;
        }
        if (*voices.at(i)).tiling_participant {
            count += 1;
        }
        i += 1;
    };
    count
}

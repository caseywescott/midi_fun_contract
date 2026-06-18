//! Invertible counterpoint at the octave.
//!
//! A two-voice texture is "invertible at the octave" when either voice can be raised (or
//! lowered) by an octave and the result is still consonant.  The single prohibition is the
//! Perfect Fifth: a P5 (7 semitones) becomes a P4 (5 semitones) after octave inversion, and
//! P4 is dissonant in bare two-voice Renaissance or Species writing.
//!
//! This module validates, inverts, and guides counterpoint generation toward invertible pairs.
//! It wraps (does not modify) the existing `counterpoint_canon` output.

use core::array::ArrayTrait;
use koji::composition::aesthetic_profile::{
    AestheticProfile, PROFILE_RENAISSANCE_INVERTIBLE_ID, profile_by_id, vertical_ok,
};
use koji::composition::canon_rules::{CanonConfig, abs_i32, config_by_id};
use koji::composition::counterpoint::{
    CounterpointParams, REST_PITCH, clone_mode_spec, is_rest_pitch,
};
use koji::composition::counterpoint_canon::{
    CanonHarmonyPlan, plan_canon_harmony, plan_canon_harmony_sparse,
};
use koji::composition::melodic_canon::{
    MelodicCanon, all_pairs_clash_free, exact_imitation, generate_canon_with_config_length,
};

// ─────────────────────────────────────────────────────────────
// Interval helpers (chromatic / semitone basis)
// ─────────────────────────────────────────────────────────────

/// Semitone interval between two MIDI keynums, reduced to within one octave [0, 11].
pub fn semitone_class(a: u8, b: u8) -> u8 {
    let diff: u8 = if b > a {
        b - a
    } else {
        a - b
    };
    diff % 12
}

/// True when the semitone interval class represents a Perfect Fifth (7 semitones mod 12).
pub fn is_perfect_fifth_class(a: u8, b: u8) -> bool {
    semitone_class(a, b) == 7
}

/// True when the pair is safe for octave inversion (no P5 between sounding notes).
pub fn ic_pair_safe(a: u8, b: u8) -> bool {
    if is_rest_pitch(a) || is_rest_pitch(b) {
        return true;
    }
    !is_perfect_fifth_class(a, b)
}

/// Interval class on a diatonic or chromatic lattice.
pub fn lattice_interval_class(octave: u32, a: i32, b: i32) -> u32 {
    assert(octave > 0, 'bad lattice octave');
    abs_i32(a - b) % octave
}

/// The fifth class for the current lattice: 4 on mod-7, 7 on mod-12.
pub fn lattice_fifth_class(octave: u32) -> u32 {
    if octave == 12 {
        7
    } else {
        4
    }
}

/// True iff the lattice vertical avoids the interval that becomes a fourth after octave inversion.
pub fn lattice_ic_safe(octave: u32, a: i32, b: i32) -> bool {
    lattice_interval_class(octave, a, b) != lattice_fifth_class(octave)
}

/// Profile-aware convertibility gate: style-legal and octave-invertible.
pub fn vertical_ok_invertible(profile: @AestheticProfile, a: i32, b: i32) -> bool {
    vertical_ok(profile, a, b) && lattice_ic_safe(*profile.octave, a, b)
}

// ─────────────────────────────────────────────────────────────
// InvertibleVerticalPolicy — composable style + IC gate
// ─────────────────────────────────────────────────────────────

/// Composable vertical-legality policy that layers an IC check on top of any `AestheticProfile`.
/// Both `require_ic_safe = false` (plain style gate) and `require_ic_safe = true` (IC-aware) are
/// supported so callers can toggle IC enforcement without swapping profiles.
#[derive(Copy, Drop)]
pub struct InvertibleVerticalPolicy {
    pub profile: AestheticProfile,
    /// When true, additionally forbids the Perfect Fifth class on the lattice — the single
    /// interval that breaks invertibility at the octave (P5 → P4 after inversion).
    pub require_ic_safe: bool,
}

/// Evaluate the policy for a pair of diatonic degrees.
/// Returns true iff style-legal AND (when require_ic_safe) IC-safe.
pub fn vertical_ok_with_policy(policy: @InvertibleVerticalPolicy, a: i32, b: i32) -> bool {
    if !vertical_ok(policy.profile, a, b) {
        return false;
    }
    if *policy.require_ic_safe {
        lattice_ic_safe(*policy.profile.octave, a, b)
    } else {
        true
    }
}

/// Convenience constructor: Renaissance IC profile (id 25) with IC-safe required.
/// Use this for strict Renaissance invertible counterpoint.
pub fn renaissance_ic_policy() -> InvertibleVerticalPolicy {
    InvertibleVerticalPolicy {
        profile: profile_by_id(PROFILE_RENAISSANCE_INVERTIBLE_ID),
        require_ic_safe: true,
    }
}

/// General-purpose policy constructor by profile id.
pub fn ic_policy_from_id(profile_id: u32, require_ic_safe: bool) -> InvertibleVerticalPolicy {
    InvertibleVerticalPolicy { profile: profile_by_id(profile_id), require_ic_safe }
}

// ─────────────────────────────────────────────────────────────
// Sequence-level validation
// ─────────────────────────────────────────────────────────────

/// True iff every simultaneous note pair avoids P5, making the pair invertible at the octave.
/// `voice_a` and `voice_b` are note sequences of equal length (MIDI keynums; REST_PITCH = rest).
pub fn is_invertible_at_octave(voice_a: Span<u8>, voice_b: Span<u8>) -> bool {
    assert(voice_a.len() == voice_b.len(), 'voice len mismatch');
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= voice_a.len() || !ok {
            break;
        }
        if !ic_pair_safe(*voice_a.at(i), *voice_b.at(i)) {
            ok = false;
        }
        i += 1;
    };
    ok
}

/// Count the number of simultaneous P5 intervals in a pair of voices.
pub fn count_fifths(voice_a: Span<u8>, voice_b: Span<u8>) -> u32 {
    assert(voice_a.len() == voice_b.len(), 'voice len mismatch');
    let mut count: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= voice_a.len() {
            break;
        }
        let a = *voice_a.at(i);
        let b = *voice_b.at(i);
        if !is_rest_pitch(a) && !is_rest_pitch(b) && is_perfect_fifth_class(a, b) {
            count += 1;
        }
        i += 1;
    };
    count
}

// ─────────────────────────────────────────────────────────────
// Octave inversion
// ─────────────────────────────────────────────────────────────

/// Raise all sounding pitches in `voice` by 12 semitones (one octave).
/// Rests are passed through unchanged.
pub fn raise_octave(voice: Span<u8>) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= voice.len() {
            break;
        }
        let p = *voice.at(i);
        if is_rest_pitch(p) {
            out.append(REST_PITCH);
        } else if p > 115 {
            out.append(127);
        } else {
            out.append(p + 12);
        }
        i += 1;
    };
    out
}

/// Lower all sounding pitches in `voice` by 12 semitones (one octave).
/// Rests are passed through unchanged.
pub fn lower_octave(voice: Span<u8>) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= voice.len() {
            break;
        }
        let p = *voice.at(i);
        if is_rest_pitch(p) {
            out.append(REST_PITCH);
        } else if p >= 12 {
            out.append(p - 12);
        } else {
            out.append(p); // already at the bottom; clamp
        }
        i += 1;
    };
    out
}

/// Perform octave inversion: raise `voice_a` (the lower voice) by one octave.
/// Returns `(new_a, voice_b)` where `new_a` is now above `voice_b`.
pub fn octave_invert_pair(
    voice_a: Span<u8>, voice_b: Span<u8>,
) -> (Array<u8>, Array<u8>) {
    let new_a = raise_octave(voice_a);
    let mut b_copy: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= voice_b.len() {
            break;
        }
        b_copy.append(*voice_b.at(i));
        i += 1;
    };
    (new_a, b_copy)
}

// ─────────────────────────────────────────────────────────────
// IC-aware harmony planning
// ─────────────────────────────────────────────────────────────

/// Result of IC-validated harmony planning: the plan plus an invertibility flag.
#[derive(Drop)]
pub struct ICHarmonyResult {
    pub plan: CanonHarmonyPlan,
    /// True when every simultaneous note pair in the plan is invertible at the octave
    /// (no P5 between any two voices that are both sounding).
    pub is_invertible: bool,
    /// Number of P5 violations found (0 = fully invertible).
    pub fifth_count: u32,
}

/// Validate all voice-pair combinations in a `CanonHarmonyPlan` for IC safety.
fn count_plan_fifths(plan: @CanonHarmonyPlan) -> u32 {
    let nv = plan.voices.len();
    let tile_len = *plan.tile_len;
    let mut total_fifths: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= nv {
            break;
        }
        let mut j: u32 = i + 1;
        loop {
            if j >= nv {
                break;
            }
            let vi = plan.voices.at(i);
            let vj = plan.voices.at(j);
            let mut t: u32 = 0;
            loop {
                if t >= tile_len {
                    break;
                }
                let ti: usize = t.try_into().unwrap();
                let om = *plan.onset_mask.at(ti);
                if om == 1 {
                    let pi = *vi.at(ti);
                    let pj = *vj.at(ti);
                    if !is_rest_pitch(pi) && !is_rest_pitch(pj) && is_perfect_fifth_class(pi, pj) {
                        total_fifths += 1;
                    }
                }
                t += 1;
            };
            j += 1;
        };
        i += 1;
    };
    total_fifths
}

/// Copy counterpoint params and make the vertical predicate convertible at the octave.
pub fn counterpoint_params_require_ic(base_params: @CounterpointParams) -> CounterpointParams {
    CounterpointParams {
        seed: *base_params.seed,
        tonic: *base_params.tonic,
        mode_spec: clone_mode_spec(base_params.mode_spec),
        register_lo: *base_params.register_lo,
        register_hi: *base_params.register_hi,
        max_melodic_leap: *base_params.max_melodic_leap,
        motion_bias: *base_params.motion_bias,
        voice_placement: *base_params.voice_placement,
        forbid_parallel_perfects: *base_params.forbid_parallel_perfects,
        forbid_similar_perfects: *base_params.forbid_similar_perfects,
        require_invertible_at_octave: true,
    }
}

/// Generate harmony voices and report whether the result is invertible at the octave.
pub fn plan_ic_canon_harmony(
    cantus_motif: Span<u8>, base_params: @CounterpointParams, num_voices: u32,
) -> ICHarmonyResult {
    let ic_params = counterpoint_params_require_ic(base_params);
    let plan = plan_canon_harmony(cantus_motif, @ic_params, num_voices);
    let fifth_count = count_plan_fifths(@plan);
    ICHarmonyResult { is_invertible: fifth_count == 0, fifth_count, plan }
}

/// Generate harmony with explicit onset mask and report invertibility.
pub fn plan_ic_canon_harmony_sparse(
    cantus_motif: Span<u8>,
    onset_mask: Span<u32>,
    base_params: @CounterpointParams,
    num_voices: u32,
) -> ICHarmonyResult {
    let ic_params = counterpoint_params_require_ic(base_params);
    let plan = plan_canon_harmony_sparse(cantus_motif, onset_mask, @ic_params, num_voices);
    let fifth_count = count_plan_fifths(@plan);
    ICHarmonyResult { is_invertible: fifth_count == 0, fifth_count, plan }
}

// ─────────────────────────────────────────────────────────────
// Melodic-canon integration
// ─────────────────────────────────────────────────────────────

/// Validate that every simultaneous pair in a `MelodicCanon` avoids the invertibility-breaking
/// fifth class on the canon's own lattice.
pub fn all_pairs_octave_invertible(canon: @MelodicCanon) -> bool {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let len = degs.len();
    let nv = voices.len();
    let octave = *canon.octave;
    let mut total = len;
    let mut vi: u32 = 0;
    loop {
        if vi >= nv {
            break;
        }
        let e = *voices.at(vi);
        if len + e.entry > total {
            total = len + e.entry;
        }
        vi += 1;
    };

    let mut t: u32 = 0;
    let mut ok = true;
    loop {
        if t >= total || !ok {
            break;
        }
        let mut a: u32 = 0;
        loop {
            if a >= nv || !ok {
                break;
            }
            let va = *voices.at(a);
            let mut b: u32 = a + 1;
            loop {
                if b >= nv || !ok {
                    break;
                }
                let vb = *voices.at(b);
                let sound_a = t >= va.entry && (t - va.entry) < len;
                let sound_b = t >= vb.entry && (t - vb.entry) < len;
                if sound_a && sound_b {
                    let da = *degs.at(t - va.entry) + va.offset;
                    let db = *degs.at(t - vb.entry) + vb.offset;
                    if !lattice_ic_safe(octave, da, db) {
                        ok = false;
                    }
                }
                b += 1;
            };
            a += 1;
        };
        t += 1;
    };
    ok
}

/// Validate the full convertible-counterpoint invariant under a style profile.
pub fn all_pairs_convertible_counterpoint(
    canon: @MelodicCanon, profile: @AestheticProfile,
) -> bool {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let len = degs.len();
    let nv = voices.len();
    let mut total = len;
    let mut vi: u32 = 0;
    loop {
        if vi >= nv {
            break;
        }
        let e = *voices.at(vi);
        if len + e.entry > total {
            total = len + e.entry;
        }
        vi += 1;
    };

    let mut t: u32 = 0;
    let mut ok = true;
    loop {
        if t >= total || !ok {
            break;
        }
        let mut a: u32 = 0;
        loop {
            if a >= nv || !ok {
                break;
            }
            let va = *voices.at(a);
            let mut b: u32 = a + 1;
            loop {
                if b >= nv || !ok {
                    break;
                }
                let vb = *voices.at(b);
                let sound_a = t >= va.entry && (t - va.entry) < len;
                let sound_b = t >= vb.entry && (t - vb.entry) < len;
                if sound_a && sound_b {
                    let da = *degs.at(t - va.entry) + va.offset;
                    let db = *degs.at(t - vb.entry) + vb.offset;
                    if !vertical_ok_invertible(profile, da, db) {
                        ok = false;
                    }
                }
                b += 1;
            };
            a += 1;
        };
        t += 1;
    };
    ok
}

/// Reuse a Renaissance canon config but judge it with the stricter octave-invertible profile.
pub fn invertible_config_from_canon(config: CanonConfig) -> CanonConfig {
    assert(config.octave == 7, 'ic config diatonic');
    CanonConfig {
        config_id: config.config_id,
        offsets: config.offsets,
        name: config.name,
        octave: config.octave,
        profile_id: PROFILE_RENAISSANCE_INVERTIBLE_ID,
    }
}

/// Generate a melodic canon that is correct both as a canon and as octave-invertible counterpoint.
pub fn generate_invertible_canon_with_config(
    seed: felt252, config: CanonConfig, length: u32,
) -> MelodicCanon {
    let ic_config = invertible_config_from_canon(config);
    let canon = generate_canon_with_config_length(seed, ic_config, length);
    let profile = profile_by_id(PROFILE_RENAISSANCE_INVERTIBLE_ID);
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_clash_free(@canon, @profile), 'ic canon clash');
    assert(all_pairs_octave_invertible(@canon), 'canon not IC');
    canon
}

/// Convenience wrapper by legacy Renaissance config id (`0..6`).
pub fn generate_invertible_melodic_canon(
    seed: felt252, config_id: u32, length: u32,
) -> MelodicCanon {
    generate_invertible_canon_with_config(seed, config_by_id(config_id), length)
}

/// IC-safe canon realized in an explicit mode and tonic.
/// Structurally identical to `generate_invertible_melodic_canon`; only the pitch realization
/// (mode scale + tonic keynum) differs.  Diatonic degrees are unchanged, so all IC invariants
/// verified inside `generate_invertible_melodic_canon` remain valid.
pub fn generate_invertible_melodic_canon_mode(
    seed: felt252, config_id: u32, length: u32, mode_id: u8, tonic_keynum: u8,
) -> MelodicCanon {
    let base = generate_invertible_melodic_canon(seed, config_id, length);
    MelodicCanon {
        config_id: base.config_id,
        config_name: base.config_name,
        offsets: base.offsets,
        leader_degrees: base.leader_degrees,
        leader_steps: base.leader_steps,
        mode_id,
        tonic_keynum,
        time_unit: base.time_unit,
        voices: base.voices,
        octave: base.octave,
        profile_id: base.profile_id,
    }
}

// ─────────────────────────────────────────────────────────────
// Diatonic interval helpers for the inversion-canon layer
// ─────────────────────────────────────────────────────────────

/// Convert a diatonic step count to its generic class (mod 7, in 0..6).
pub fn diatonic_class(step: i32) -> u32 {
    let abs_step: u32 = if step < 0 {
        (-step).try_into().unwrap()
    } else {
        step.try_into().unwrap()
    };
    abs_step % 7
}

/// True iff `diatonic_class(step)` is a Perfect Fifth class (4 in 0-indexed 0=unison, 4=fifth).
pub fn is_diatonic_fifth(step: i32) -> bool {
    diatonic_class(step) == 4
}

/// True iff the diatonic interval between two degrees avoids the perfect fifth.
/// Used by the countersubject generation to enforce invertibility on the diatonic lattice.
pub fn diatonic_ic_safe(deg_a: i32, deg_b: i32) -> bool {
    !is_diatonic_fifth(deg_a - deg_b)
}

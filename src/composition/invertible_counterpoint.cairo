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
use koji::composition::counterpoint::{CounterpointParams, REST_PITCH, is_rest_pitch};
use koji::composition::counterpoint_canon::{
    CanonHarmonyPlan, plan_canon_harmony, plan_canon_harmony_sparse,
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

/// Generate harmony voices and report whether the result is invertible at the octave.
pub fn plan_ic_canon_harmony(
    cantus_motif: Span<u8>, base_params: @CounterpointParams, num_voices: u32,
) -> ICHarmonyResult {
    let plan = plan_canon_harmony(cantus_motif, base_params, num_voices);
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
    let plan = plan_canon_harmony_sparse(cantus_motif, onset_mask, base_params, num_voices);
    let fifth_count = count_plan_fifths(@plan);
    ICHarmonyResult { is_invertible: fifth_count == 0, fifth_count, plan }
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

//! Invertible counterpoint at the octave.
//!
//! A two-voice texture is "invertible at the octave" when either voice can be raised (or
//! lowered) by an octave and the result is still consonant.  The single prohibition is the
//! Perfect Fifth: a P5 (7 semitones) becomes a P4 (5 semitones) after octave inversion, and
//! P4 is dissonant in bare two-voice Renaissance or Species writing.
//!
//! This module validates, inverts, and guides counterpoint generation toward invertible pairs.
//! It wraps (does not modify) the existing `counterpoint_canon` output.

use crate::composition::counterpoint::is_rest_pitch;

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

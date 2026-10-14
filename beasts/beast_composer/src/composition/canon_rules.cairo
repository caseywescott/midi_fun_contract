//! Renaissance Improvised-Canon — Rules Engine.
//!
//! Formalizes the stretto-fuga pedagogy of Schubert / Cumming / Collins: a canon *is a rule*
//! ("you do everything I do a fifth higher than me"). Because every follower is an exact delayed
//! transposition of the leader, contrapuntal correctness is a property of the leader's melody
//! alone, governed by the **lag-difference identity**:
//!
//!   vertical(t) = T − ( L(t) − L(t − k) )
//!
//! where `T` is the (signed, diatonic) interval of imitation and `k` the time lag. This module
//! derives, in closed form, the permitted leader melodic alphabet for any configuration — never
//! by search.
//!
//! See `docs/renaissance_canon_improvisation_spec.md` for the full specification.

/// Absolute value of a signed diatonic interval, as a `u32`.
pub fn abs_i32(x: i32) -> u32 {
    if x < 0 {
        (-x).try_into().unwrap()
    } else {
        x.try_into().unwrap()
    }
}

/// Generic interval class (size mod 7) between two diatonic degrees / steps.
/// 0 = unison/octave, 1 = 2nd, 2 = 3rd, 3 = 4th, 4 = 5th, 5 = 6th, 6 = 7th.
pub fn generic_class(a: i32, b: i32) -> u32 {
    abs_i32(a - b) % 7
}

/// Renaissance two-voice consonance: unison/octave (0), 3rd (2), 5th (4), 6th (5).
/// The perfect fourth (3) is dissonant in the bare two-voice frame; 2nd (1) and 7th (6) dissonant.
pub fn is_consonant_class(cls: u32) -> bool {
    let c = cls % 7;
    c == 0 || c == 2 || c == 4 || c == 5
}

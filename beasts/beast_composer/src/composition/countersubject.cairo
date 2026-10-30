//! Countersubject — a second fixed melody that always accompanies the subject.
//!
//! A countersubject (CS) is an independent melodic idea heard simultaneously with the subject
//! throughout the exposition.  When voice 2 enters with the subject, voice 1 plays the CS
//! against it — and the CS must work both above AND below the subject (invertible counterpoint
//! at the octave).  This requires:
//!   1. Consonance against the subject at every beat.
//!   2. No Perfect Fifth verticals (IC constraint for octave invertibility).
//!   3. Good melodic shape: mostly conjunct motion, no augmented intervals.
//!
//! No existing files are modified.

use core::array::ArrayTrait;
use crate::composition::canon_rules::abs_i32;
use crate::composition::invertible_counterpoint::diatonic_ic_safe;
use crate::composition::melodic_canon::{DEFAULT_VELOCITY, NoteEvent, REGISTER_BAND, realize_degree};
use crate::lcg::LCG;
use crate::opaque::opaque;
use crate::rng::{RandomSource, bounded};

// ─────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────

/// Generation parameters for the countersubject walk.
#[derive(Copy, Drop)]
pub struct CountersubjectConfig {
    /// Starting degree offset from the subject's starting degree (degree 0).
    /// Typical: +2 (third above) or −2 (third below).
    pub start_offset: i32,
    /// Maximum melodic step size (in diatonic steps).  2 = prefer conjunct motion.
    pub max_step: u32,
    /// Apply IC constraint (forbid diatonic P5 verticals against subject). true = invertible.
    pub enforce_invertible: bool,
}

/// Default configuration: starts a third above, mostly conjunct, invertible.
pub fn default_countersubject_config() -> CountersubjectConfig {
    CountersubjectConfig { start_offset: 2, max_step: 3, enforce_invertible: true }
}

// ─────────────────────────────────────────────────────────────
// Countersubject struct
// ─────────────────────────────────────────────────────────────

/// A fully-specified countersubject: diatonic degrees parallel to the subject.
#[derive(Drop)]
pub struct Countersubject {
    /// CS diatonic degrees; `cs_degrees[p]` sounds simultaneously with `subject_degrees[p]`.
    pub degrees: Array<i32>,
    pub octave: u32,
    pub mode_id: u8,
    pub tonic_keynum: u8,
    pub time_unit: u32,
}

// ─────────────────────────────────────────────────────────────
// Candidate generation
// ─────────────────────────────────────────────────────────────

/// Whether a CS degree may sound against the subject's: consonant and, with `enforce_ic`, not a
/// diatonic fifth. Both rules read the same interval class, `|cs_deg - subject_deg| % 7`
/// (`generic_class`, and `diatonic_class` of the same difference): consonant is 0, 2, 4 or 5, and
/// the fifth is 4. The subtraction and the absolute value are checked as in those.
// Inlined: a call per candidate costs more than the test.
#[inline(always)]
fn cs_allowed(cs_deg: i32, subject_deg: i32, enforce_ic: bool) -> bool {
    let cls = abs_i32(cs_deg - subject_deg) % 7;
    cls == 0 || cls == 2 || cls == 5 || (cls == 4 && !enforce_ic)
}

/// Candidate CS steps at position p: consonant against the subject, IC-safe, ≤ max_step.
// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
fn cs_candidates(
    cs_cur: i32, subject_next: i32, max_step: u32, enforce_ic: bool, lo: i32, hi: i32,
) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let max_s: i32 = max_step.try_into().unwrap();
    // The steps -max_s..=max_s that land in the register band lo..=hi, as the degrees they land on.
    // `+ -max_s`, not `- max_s`: the same addition (and its panic) as the first step of the
    // original
    let lowest = cs_cur + -max_s;
    let highest = cs_cur + max_s;
    let first = if lowest > lo {
        lowest
    } else {
        lo
    };
    let last = if highest < hi {
        highest
    } else {
        hi
    };
    let mut cs_next = first;
    while cs_next <= last {
        if cs_allowed(cs_next, subject_next, enforce_ic) {
            out.append(cs_next - cs_cur);
        }
        cs_next += 1;
    }
    out
}

fn cs_degree_valid(cs_deg: i32, subject_deg: i32, enforce_ic: bool, lo: i32, hi: i32) -> bool {
    cs_deg >= lo && cs_deg <= hi && cs_allowed(cs_deg, subject_deg, enforce_ic)
}

fn nearest_safe_cs_degree(
    requested: i32, subject_deg: i32, enforce_ic: bool, lo: i32, hi: i32,
) -> i32 {
    if cs_degree_valid(requested, subject_deg, enforce_ic, lo, hi) {
        return requested;
    }
    let mut radius: u32 = opaque(1);
    loop {
        if radius > 14 {
            break;
        }
        let r: i32 = radius.try_into().unwrap();
        let up = requested + r;
        if cs_degree_valid(up, subject_deg, enforce_ic, lo, hi) {
            return up;
        }
        let down = requested - r;
        if cs_degree_valid(down, subject_deg, enforce_ic, lo, hi) {
            return down;
        }
        radius += 1;
    }
    assert(false, 'no safe cs start');
    requested
}

// ─────────────────────────────────────────────────────────────
// Generator
// ─────────────────────────────────────────────────────────────

/// Generate a countersubject alongside `subject_degrees`.
/// The CS has the same length as the subject; each degree is chosen to be consonant
/// (and optionally IC-safe) against the simultaneous subject degree.
pub fn generate_countersubject(
    subject_degrees: Span<i32>,
    config: @CountersubjectConfig,
    seed: felt252,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
) -> Countersubject {
    let len = subject_degrees.len();
    assert(len >= 1, 'subject must be non-empty');

    let s: u256 = seed.into();
    let init: u32 = (s % 256).try_into().unwrap();
    let mut rng = LCG { state: init, multiplier: 5, increment: 3, modulus: 256 };

    let hw: i32 = REGISTER_BAND;
    let start_deg = nearest_safe_cs_degree(
        config.start_offset, *subject_degrees.at(0), config.enforce_invertible, -hw, hw,
    );
    let mut degrees: Array<i32> = ArrayTrait::new();
    degrees.append(start_deg);

    let mut p: u32 = 1;
    loop {
        if p >= len {
            break;
        }
        let cs_cur = *degrees.at(degrees.len() - 1);
        let subject_next = *subject_degrees.at(p);
        let cands = cs_candidates(
            cs_cur, subject_next, config.max_step, config.enforce_invertible, -hw, hw,
        );
        // If invertibility is required, relax melodic step size before relaxing IC.
        let pool: Array<i32> = if cands.len() != 0 {
            cands
        } else if config.enforce_invertible {
            cs_candidates(cs_cur, subject_next, 14, true, -hw, hw)
        } else {
            cs_candidates(cs_cur, subject_next, config.max_step, false, -hw, hw)
        };
        if config.enforce_invertible {
            assert(pool.len() != 0, 'no ic cs candidate');
        }
        // Last-resort: allow any in-band step
        let final_pool: Array<i32> = if pool.len() != 0 {
            pool
        } else {
            let mut fb: Array<i32> = ArrayTrait::new();
            let max_s: i32 = config.max_step.try_into().unwrap();
            let mut m: i32 = -max_s;
            loop {
                if m > max_s {
                    break;
                }
                let next = cs_cur + m;
                if next >= -hw && next <= hw {
                    fb.append(m);
                }
                m += 1;
            }
            fb
        };
        let (raw, next_rng) = rng.draw();
        rng = next_rng;
        let m = if final_pool.len() != 0 {
            *final_pool.at(bounded(raw, final_pool.len()))
        } else {
            0
        };
        degrees.append(cs_cur + m);
        p += 1;
    }

    Countersubject { degrees, octave, mode_id, tonic_keynum, time_unit }
}

// ─────────────────────────────────────────────────────────────
// Event emission
// ─────────────────────────────────────────────────────────────

/// Emit the countersubject as NoteEvents starting at `start_time` on `voice_id`.
pub fn countersubject_to_note_events(
    cs: @Countersubject, start_time: u32, voice_id: u32,
) -> Array<NoteEvent> {
    let degs = @cs.degrees;
    let unit = cs.time_unit;
    let octave = cs.octave;
    let mode = cs.mode_id;
    let tonic = cs.tonic_keynum;
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut p: u32 = 0;
    loop {
        if p >= degs.len() {
            break;
        }
        out
            .append(
                NoteEvent {
                    time: start_time + p * unit,
                    duration: unit,
                    pitch: realize_degree(octave, *degs.at(p), tonic, mode),
                    velocity: DEFAULT_VELOCITY,
                    voice_id,
                },
            );
        p += 1;
    }
    out
}

/// True iff every simultaneous pair avoids diatonic P5 (IC-safe for octave inversion).
pub fn countersubject_invertible(subject: Span<i32>, cs: @Countersubject) -> bool {
    assert(subject.len() == cs.degrees.len(), 'subject/cs len mismatch');
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= subject.len() || !ok {
            break;
        }
        if !diatonic_ic_safe(*cs.degrees.at(i), *subject.at(i)) {
            ok = false;
        }
        i += 1;
    }
    ok
}

/// The candidate and degree checks against the original: `generic_class`, `is_consonant_class` and
/// `diatonic_ic_safe` called one after the other, over every step in `-max_step..=max_step`.
#[cfg(test)]
mod tests {
    use crate::composition::canon_rules::{generic_class, is_consonant_class};
    use crate::composition::invertible_counterpoint::diatonic_ic_safe;
    use super::{
        cs_candidates, cs_degree_valid, default_countersubject_config, generate_countersubject,
    };

    fn reference_degree_valid(
        cs_deg: i32, subject_deg: i32, enforce_ic: bool, lo: i32, hi: i32,
    ) -> bool {
        if cs_deg < lo || cs_deg > hi {
            return false;
        }
        let cls = generic_class(cs_deg, subject_deg);
        if !is_consonant_class(cls) {
            return false;
        }
        if enforce_ic && !diatonic_ic_safe(cs_deg, subject_deg) {
            return false;
        }
        true
    }

    fn reference_candidates(
        cs_cur: i32, subject_next: i32, max_step: u32, enforce_ic: bool, lo: i32, hi: i32,
    ) -> Array<i32> {
        let mut out: Array<i32> = ArrayTrait::new();
        let max_s: i32 = max_step.try_into().unwrap();
        let mut m: i32 = -max_s;
        while m <= max_s {
            if reference_degree_valid(cs_cur + m, subject_next, enforce_ic, lo, hi) {
                out.append(m);
            }
            m += 1;
        }
        out
    }

    /// Positions in and out of the register band, subjects well past it, the steps the generator
    /// uses (3, and 14 to relax them) and none, and the bands: ±7, a narrow one, one degree, none.
    /// `cs_cur` in `lo..=hi` (-8..=8 in three tests, so that no test run holds too much).
    fn candidates_are_the_original_from(lo: i32, hi: i32) {
        let bands = array![(-7_i32, 7_i32), (-2, 4), (0, 0), (3, -3)];
        let mut cs_cur: i32 = lo;
        while cs_cur <= hi {
            let mut subject: i32 = -14;
            while subject <= 14 {
                for max_step in array![0_u32, 3, 14] {
                    for enforce_ic in array![true, false] {
                        for band in bands.span() {
                            let (lo, hi) = *band;
                            assert!(
                                cs_candidates(cs_cur, subject, max_step, enforce_ic, lo, hi)
                                    .span() == reference_candidates(
                                        cs_cur, subject, max_step, enforce_ic, lo, hi,
                                    )
                                    .span(),
                            );
                        }
                    }
                }
                subject += 1;
            }
            cs_cur += 1;
        }
    }

    #[test]
    #[available_gas(100000000000)]
    fn candidates_are_the_original_0() {
        candidates_are_the_original_from(-8, -3);
    }

    #[test]
    #[available_gas(100000000000)]
    fn candidates_are_the_original_1() {
        candidates_are_the_original_from(-2, 3);
    }

    #[test]
    #[available_gas(100000000000)]
    fn candidates_are_the_original_2() {
        candidates_are_the_original_from(4, 8);
    }

    #[test]
    #[available_gas(100000000000)]
    fn degree_validity_is_the_original() {
        let mut cs_deg: i32 = -9;
        while cs_deg <= 9 {
            let mut subject: i32 = -16;
            while subject <= 16 {
                for enforce_ic in array![true, false] {
                    assert!(
                        cs_degree_valid(
                            cs_deg, subject, enforce_ic, -7, 7,
                        ) == reference_degree_valid(cs_deg, subject, enforce_ic, -7, 7),
                    );
                }
                subject += 1;
            }
            cs_deg += 1;
        }
    }

    // A subject degree far off the CS band panics where the subtraction leaves i32, as before.

    #[test]
    #[should_panic(expected: ('i32_sub Overflow',))]
    fn a_subject_below_the_range_panics() {
        cs_candidates(0, -0x7fffffff - 1, 3, true, -7, 7);
    }

    #[test]
    #[should_panic(expected: ('i32_sub Overflow',))]
    fn the_original_panics_below_the_range_too() {
        reference_candidates(0, -0x7fffffff - 1, 3, true, -7, 7);
    }

    #[test]
    #[should_panic(expected: ('i32_sub Underflow',))]
    fn a_subject_above_the_range_panics() {
        cs_candidates(0, 0x7fffffff, 3, true, -7, 7);
    }

    #[test]
    #[should_panic(expected: ('i32_sub Underflow',))]
    fn the_original_panics_above_the_range_too() {
        reference_candidates(0, 0x7fffffff, 3, true, -7, 7);
    }

    /// -1 less the largest i32 is the smallest, which has no absolute value.
    #[test]
    #[should_panic(expected: ('i32_neg Underflow',))]
    fn the_smallest_difference_panics() {
        cs_candidates(-1, 0x7fffffff, 0, true, -7, 7);
    }

    #[test]
    #[should_panic(expected: ('i32_neg Underflow',))]
    fn the_original_panics_on_it_too() {
        reference_candidates(-1, 0x7fffffff, 0, true, -7, 7);
    }

    /// The degrees are the walk over the subject from the seed: the octave, mode, tonic and time
    /// unit only ride along, which is what lets `build_section` make them once for all sections.
    #[test]
    #[available_gas(100000000000)]
    fn the_degrees_depend_on_the_subject_and_seed_alone() {
        let subject = array![0, 2, 4, 2, 0, -2, 0, 3, 5, 4, 2, 1, -1, 0, 2, 0];
        let config = default_countersubject_config();
        let mut n: u32 = 1;
        while n < 20 {
            let seed: felt252 = n.into();
            let want = generate_countersubject(subject.span(), @config, seed, 7, 5, 60, 480);
            for octave in array![7_u32, 12] {
                for mode in array![0_u8, 1, 5, 7] {
                    for tonic in array![24_u8, 60, 96] {
                        let got = generate_countersubject(
                            subject.span(), @config, seed, octave, mode, tonic, 240,
                        );
                        assert!(got.degrees == want.degrees);
                    }
                }
            }
            n += 1;
        }
    }
}

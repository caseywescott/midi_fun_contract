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
use koji::lcg::LCG;
use koji::rng::{RandomSource, bounded};
use koji::composition::canon_rules::{abs_i32, generic_class, is_consonant_class};
use koji::composition::invertible_counterpoint::diatonic_ic_safe;
use koji::composition::melodic_canon::{
    NoteEvent, realize_degree, DEFAULT_VELOCITY, REGISTER_BAND,
};

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

/// Countersubject that starts a third below — fits under the subject.
pub fn below_countersubject_config() -> CountersubjectConfig {
    CountersubjectConfig { start_offset: -2, max_step: 3, enforce_invertible: true }
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

/// Candidate CS steps at position p: consonant against the subject, IC-safe, ≤ max_step.
fn cs_candidates(
    cs_cur: i32,
    subject_next: i32,
    max_step: u32,
    enforce_ic: bool,
    lo: i32,
    hi: i32,
) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let max_s: i32 = max_step.try_into().unwrap();
    let mut m: i32 = -max_s;
    loop {
        if m > max_s {
            break;
        }
        let cs_next = cs_cur + m;
        // 1. Register band
        if cs_next < lo || cs_next > hi {
            m += 1;
            continue;
        }
        // 2. Consonant against subject
        let cls = generic_class(cs_next, subject_next);
        if !is_consonant_class(cls) {
            m += 1;
            continue;
        }
        // 3. IC constraint: no diatonic P5 vertical
        if enforce_ic && !diatonic_ic_safe(cs_next, subject_next) {
            m += 1;
            continue;
        }
        out.append(m);
        m += 1;
    };
    out
}

fn cs_degree_valid(
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

fn nearest_safe_cs_degree(
    requested: i32, subject_deg: i32, enforce_ic: bool, lo: i32, hi: i32,
) -> i32 {
    if cs_degree_valid(requested, subject_deg, enforce_ic, lo, hi) {
        return requested;
    }
    let mut radius: u32 = 1;
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
    };
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
        *config.start_offset,
        *subject_degrees.at(0),
        *config.enforce_invertible,
        -hw,
        hw,
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
            cs_cur,
            subject_next,
            *config.max_step,
            *config.enforce_invertible,
            -hw,
            hw,
        );
        // If invertibility is required, relax melodic step size before relaxing IC.
        let pool: Array<i32> = if cands.len() > 0 {
            cands
        } else if *config.enforce_invertible {
            cs_candidates(cs_cur, subject_next, 14, true, -hw, hw)
        } else {
            cs_candidates(cs_cur, subject_next, *config.max_step, false, -hw, hw)
        };
        if *config.enforce_invertible {
            assert(pool.len() > 0, 'no ic cs candidate');
        }
        // Last-resort: allow any in-band step
        let final_pool: Array<i32> = if pool.len() > 0 {
            pool
        } else {
            let mut fb: Array<i32> = ArrayTrait::new();
            let max_s: i32 = (*config.max_step).try_into().unwrap();
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
            };
            fb
        };
        let (raw, next_rng) = rng.draw();
        rng = next_rng;
        let m = if final_pool.len() > 0 {
            *final_pool.at(bounded(raw, final_pool.len()))
        } else {
            0
        };
        degrees.append(cs_cur + m);
        p += 1;
    };

    Countersubject { degrees, octave, mode_id, tonic_keynum, time_unit }
}

// ─────────────────────────────────────────────────────────────
// Event emission
// ─────────────────────────────────────────────────────────────

/// Emit the countersubject as NoteEvents starting at `start_time` on `voice_id`.
pub fn countersubject_to_note_events(
    cs: @Countersubject, start_time: u32, voice_id: u32,
) -> Array<NoteEvent> {
    let degs = cs.degrees;
    let unit = *cs.time_unit;
    let octave = *cs.octave;
    let mode = *cs.mode_id;
    let tonic = *cs.tonic_keynum;
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut p: u32 = 0;
    loop {
        if p >= degs.len() {
            break;
        }
        out.append(
            NoteEvent {
                time: start_time + p * unit,
                duration: unit,
                pitch: realize_degree(octave, *degs.at(p), tonic, mode),
                velocity: DEFAULT_VELOCITY,
                voice_id,
            },
        );
        p += 1;
    };
    out
}

/// Emit the countersubject transposed by `offset` diatonic degrees
/// (used when the CS appears above or below after inversion).
pub fn countersubject_transposed_to_note_events(
    cs: @Countersubject, offset: i32, start_time: u32, voice_id: u32,
) -> Array<NoteEvent> {
    let degs = cs.degrees;
    let unit = *cs.time_unit;
    let octave = *cs.octave;
    let mode = *cs.mode_id;
    let tonic = *cs.tonic_keynum;
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut p: u32 = 0;
    loop {
        if p >= degs.len() {
            break;
        }
        let deg = *degs.at(p) + offset;
        out.append(
            NoteEvent {
                time: start_time + p * unit,
                duration: unit,
                pitch: realize_degree(octave, deg, tonic, mode),
                velocity: DEFAULT_VELOCITY,
                voice_id,
            },
        );
        p += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Validators
// ─────────────────────────────────────────────────────────────

/// True iff every CS degree is consonant against the corresponding subject degree.
pub fn countersubject_consonant(subject: Span<i32>, cs: @Countersubject) -> bool {
    assert(subject.len() == cs.degrees.len(), 'subject/cs len mismatch');
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= subject.len() || !ok {
            break;
        }
        let cls = generic_class(*cs.degrees.at(i), *subject.at(i));
        if !is_consonant_class(cls) {
            ok = false;
        }
        i += 1;
    };
    ok
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
    };
    ok
}

// ─────────────────────────────────────────────────────────────
// Combined output
// ─────────────────────────────────────────────────────────────

/// Emit NoteEvents for the leader voice and a generated countersubject together.
/// Both voices start at `start_time`; the CS sounds simultaneously with the leader.
/// The `Countersubject` is generated from `leader_degrees` and rendered on `cs_voice_id`.
/// Connects the countersubject to the `FollowerSpec` dispatch model: the CS is an independently
/// generated voice, not a mathematical transform of the leader, but this function gives callers
/// a single call to get the combined two-voice output.
pub fn canon_with_countersubject(
    leader_degrees: Span<i32>,
    cs_config: @CountersubjectConfig,
    seed: felt252,
    start_time: u32,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
    leader_voice_id: u32,
    cs_voice_id: u32,
) -> Array<NoteEvent> {
    let len = leader_degrees.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut p: u32 = 0;
    loop {
        if p >= len {
            break;
        }
        out.append(
            NoteEvent {
                time: start_time + p * time_unit,
                duration: time_unit,
                pitch: realize_degree(octave, *leader_degrees.at(p), tonic_keynum, mode_id),
                velocity: DEFAULT_VELOCITY,
                voice_id: leader_voice_id,
            },
        );
        p += 1;
    };
    let cs = generate_countersubject(
        leader_degrees, cs_config, seed, octave, mode_id, tonic_keynum, time_unit,
    );
    let cs_events = countersubject_to_note_events(@cs, start_time, cs_voice_id);
    let mut i: u32 = 0;
    loop {
        if i >= cs_events.len() {
            break;
        }
        out.append(*cs_events.at(i));
        i += 1;
    };
    out
}

/// True iff every CS melodic step stays within `max_step` diatonic degrees.
pub fn countersubject_conjunct(cs: @Countersubject, max_step: u32) -> bool {
    let degs = cs.degrees;
    if degs.len() < 2 {
        return true;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i + 1 >= degs.len() || !ok {
            break;
        }
        let step = abs_i32(*degs.at(i + 1) - *degs.at(i));
        if step > max_step {
            ok = false;
        }
        i += 1;
    };
    ok
}

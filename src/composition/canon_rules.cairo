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

use core::array::ArrayTrait;

// ──────────────────────────────────────────────────────────
// Generic diatonic intervals & consonance
// ──────────────────────────────────────────────────────────

/// Lowest / highest leader melodic step considered (descending / ascending octave).
pub const STEP_MIN: i32 = -7;
pub const STEP_MAX: i32 = 7;

/// Maximum number of canonic voices supported (historical ceiling for strict improvised canon).
pub const MAX_CANON_VOICES: u32 = 4;

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

/// True if the class is a *perfect* consonance (unison/octave or fifth) — used by the
/// parallel-perfect avoidance rule.
pub fn is_perfect_class(cls: u32) -> bool {
    let c = cls % 7;
    c == 0 || c == 4
}

/// Is leader melodic step `m` consonant for a single follower at interval of imitation `t`
/// (lag 1)? Vertical = `t − m`; consonant iff its generic class is consonant.
pub fn step_is_consonant(t: i32, m: i32) -> bool {
    is_consonant_class(generic_class(t, m))
}

// ──────────────────────────────────────────────────────────
// Permitted leader alphabet (Table 1)
// ──────────────────────────────────────────────────────────

/// The full harmonic alphabet of permitted leader steps for interval of imitation `t`,
/// over the range `[STEP_MIN, STEP_MAX]`. This *is* Table 1, derived from the identity.
pub fn allowed_leader_steps(t: i32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i > 14 {
            break;
        }
        let mi: i32 = i.try_into().unwrap();
        let m: i32 = mi - 7; // range -7..=7
        if step_is_consonant(t, m) {
            out.append(m);
        }
        i += 1;
    };
    out
}

/// The improvisation-friendly stylistic subset: steps no larger than a fifth (`|m| <= 4`),
/// excluding awkward 6th/7th/octave leaps. For `t = +4` this is exactly Schubert's
/// {unison, ↑3rd, ↑5th, ↓2nd, ↓4th}.
pub fn stylistic_subset(t: i32) -> Array<i32> {
    let full = allowed_leader_steps(t);
    keep_within_skip(full.span(), 4)
}

/// Keep only steps whose melodic size is `<= max_size`.
pub fn keep_within_skip(steps: Span<i32>, max_size: u32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        let m = *steps.at(i);
        if abs_i32(m) <= max_size {
            out.append(m);
        }
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Set operations on i32 step arrays
// ──────────────────────────────────────────────────────────

pub fn contains_i32(set: Span<i32>, v: i32) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    loop {
        if i >= set.len() {
            break;
        }
        if *set.at(i) == v {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

pub fn negate_steps(set: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= set.len() {
            break;
        }
        out.append(-*set.at(i));
        i += 1;
    };
    out
}

pub fn intersect_steps(a: Span<i32>, b: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        let v = *a.at(i);
        if contains_i32(b, v) {
            out.append(v);
        }
        i += 1;
    };
    out
}

/// Order-insensitive set equality for i32 arrays.
pub fn step_set_eq(a: Span<i32>, b: Span<i32>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= a.len() {
            break;
        }
        if !contains_i32(b, *a.at(i)) {
            ok = false;
            break;
        }
        i += 1;
    };
    ok
}

// ──────────────────────────────────────────────────────────
// Multi-voice constraints
// ──────────────────────────────────────────────────────────

/// A pairwise constraint on the leader: the cumulative leader span over `w` consecutive notes,
/// compared to the relative interval `d` between the two voices, must be consonant.
#[derive(Copy, Drop)]
pub struct PairConstraint {
    /// Relative interval of imitation between the two voices (`T_j − T_i`).
    pub d: i32,
    /// Window length = entry-order distance `j − i` between the voices.
    pub w: u32,
}

/// All pairwise constraints for a stacked canon whose voice offsets are `offsets`
/// (entry order; voice `j` enters `j` structural notes after the leader).
pub fn pair_constraints(offsets: Span<i32>) -> Array<PairConstraint> {
    let mut out: Array<PairConstraint> = ArrayTrait::new();
    let n = offsets.len();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let mut j: u32 = i + 1;
        loop {
            if j >= n {
                break;
            }
            out.append(PairConstraint { d: *offsets.at(j) - *offsets.at(i), w: j - i });
            j += 1;
        };
        i += 1;
    };
    out
}

/// The permitted leader alphabet from *adjacent* (window-1) voice pairs only: the intersection
/// of `allowed_leader_steps` over every consecutive offset difference. This is the per-step
/// alphabet; longer-window constraints are enforced during the walk.
pub fn allowed_steps_multivoice(offsets: Span<i32>) -> Array<i32> {
    // Start from the full range, intersect each adjacent pair's single-step alphabet.
    let mut acc: Array<i32> = full_step_range();
    let n = offsets.len();
    let mut i: u32 = 0;
    loop {
        if i + 1 >= n {
            break;
        }
        let rel = *offsets.at(i + 1) - *offsets.at(i);
        acc = intersect_steps(acc.span(), allowed_leader_steps(rel).span());
        i += 1;
    };
    acc
}

/// The stylistic (|m| <= 4) version of the multi-voice adjacent alphabet. For the three-voice
/// "fifth below + octave" canon this is exactly {unison, ↑4th, ↓3rd, ↓5th} — Schubert's rule.
pub fn stylistic_multivoice(offsets: Span<i32>) -> Array<i32> {
    keep_within_skip(allowed_steps_multivoice(offsets).span(), 4)
}

/// Every diatonic step from `STEP_MIN` to `STEP_MAX`.
pub fn full_step_range() -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i > 14 {
            break;
        }
        let mi: i32 = i.try_into().unwrap();
        out.append(mi - 7);
        i += 1;
    };
    out
}

/// Check that a tentative leader step `m` at position `pos` (1-based count of committed steps so
/// far is `pos`, with `prev_steps` holding the committed steps) satisfies every pairwise
/// constraint whose window closes at this note. Fully local — no search, no backtracking.
pub fn step_satisfies_constraints(
    constraints: Span<PairConstraint>, prev_steps: Span<i32>, m: i32,
) -> bool {
    let pos = prev_steps.len() + 1; // number of steps after adding m (note index from 1)
    let mut c: u32 = 0;
    let mut ok = true;
    loop {
        if c >= constraints.len() {
            break;
        }
        let pc = *constraints.at(c);
        if pos >= pc.w {
            // window = the last pc.w steps, i.e. (pc.w - 1) committed steps + m
            let mut windowsum: i32 = m;
            let mut t: u32 = 0;
            loop {
                if t + 1 >= pc.w {
                    break;
                }
                windowsum += *prev_steps.at(prev_steps.len() - 1 - t);
                t += 1;
            };
            if !is_consonant_class(generic_class(pc.d, windowsum)) {
                ok = false;
                break;
            }
        }
        c += 1;
    };
    ok
}

// ──────────────────────────────────────────────────────────
// Canon configurations
// ──────────────────────────────────────────────────────────

/// A canon configuration: the voice offsets (signed diatonic; `offsets[0] == 0` for the leader)
/// in entry order. Voice `j` enters `j` structural notes after the leader.
#[derive(Drop)]
pub struct CanonConfig {
    pub config_id: u32,
    pub offsets: Span<i32>,
    pub name: felt252,
}

pub fn config_fifth_above() -> CanonConfig {
    CanonConfig { config_id: 0, offsets: array![0_i32, 4].span(), name: 'fifth_above' }
}

pub fn config_fifth_below() -> CanonConfig {
    CanonConfig { config_id: 1, offsets: array![0_i32, -4].span(), name: 'fifth_below' }
}

pub fn config_octave_above() -> CanonConfig {
    CanonConfig { config_id: 2, offsets: array![0_i32, 7].span(), name: 'octave_above' }
}

pub fn config_unison() -> CanonConfig {
    CanonConfig { config_id: 3, offsets: array![0_i32, 0].span(), name: 'unison' }
}

/// Three voices: leader, a fifth below, then an octave above that (a fourth above the leader).
/// Entry order offsets: [0, −4, +3]. Derives the conversation's "no up-a-step" rule.
pub fn config_three_voice_5b_8va() -> CanonConfig {
    CanonConfig { config_id: 4, offsets: array![0_i32, -4, 3].span(), name: 'three_5b_8va' }
}

/// Three voices middle→high→low: leader, a fifth above, then an octave below that.
/// Offsets: [0, +4, −3].
pub fn config_three_voice_5a_8vb() -> CanonConfig {
    CanonConfig { config_id: 5, offsets: array![0_i32, 4, -3].span(), name: 'three_5a_8vb' }
}

/// Four voices: stacked imitation at the fifth below (Cumming & Schubert four-voice points).
/// Offsets: [0, −4, −8, −12].
pub fn config_four_voice_5b_stack() -> CanonConfig {
    CanonConfig { config_id: 6, offsets: array![0_i32, -4, -8, -12].span(), name: 'four_5b_stack' }
}

pub fn num_configs() -> u32 {
    7
}

pub fn config_by_index(i: u32) -> CanonConfig {
    let k = i % num_configs();
    if k == 0 {
        config_fifth_above()
    } else if k == 1 {
        config_fifth_below()
    } else if k == 2 {
        config_octave_above()
    } else if k == 3 {
        config_unison()
    } else if k == 4 {
        config_three_voice_5b_8va()
    } else if k == 5 {
        config_three_voice_5a_8vb()
    } else {
        config_four_voice_5b_stack()
    }
}

/// Lookup by stable `config_id` (not seed index).
pub fn config_by_id(id: u32) -> CanonConfig {
    if id == 0 {
        config_fifth_above()
    } else if id == 1 {
        config_fifth_below()
    } else if id == 2 {
        config_octave_above()
    } else if id == 3 {
        config_unison()
    } else if id == 4 {
        config_three_voice_5b_8va()
    } else if id == 5 {
        config_three_voice_5a_8vb()
    } else {
        config_four_voice_5b_stack()
    }
}

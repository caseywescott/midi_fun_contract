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

/// A canon configuration: the voice offsets (signed; `offsets[0] == 0` for the leader) in entry
/// order. Voice `j` enters `j` structural notes after the leader. `octave` selects the lattice the
/// offsets/steps live on (7 = diatonic / tonal answer; 12 = chromatic / real answer), and
/// `profile_id` selects the default [`AestheticProfile`] (0 = Renaissance, 1 = jazz, …) under which
/// the canon's verticals are judged.
#[derive(Drop, Copy)]
pub struct CanonConfig {
    pub config_id: u32,
    pub offsets: Span<i32>,
    pub name: felt252,
    /// Lattice octave size: 7 (diatonic) or 12 (chromatic). Defaults to 7 for legacy configs.
    pub octave: u32,
    /// Default aesthetic profile id. 0 (Renaissance) for the legacy diatonic configs.
    pub profile_id: u32,
}

pub fn config_fifth_above() -> CanonConfig {
    CanonConfig {
        config_id: 0, offsets: array![0_i32, 4].span(), name: 'fifth_above', octave: 7, profile_id: 0,
    }
}

pub fn config_fifth_below() -> CanonConfig {
    CanonConfig {
        config_id: 1, offsets: array![0_i32, -4].span(), name: 'fifth_below', octave: 7,
        profile_id: 0,
    }
}

pub fn config_octave_above() -> CanonConfig {
    CanonConfig {
        config_id: 2, offsets: array![0_i32, 7].span(), name: 'octave_above', octave: 7,
        profile_id: 0,
    }
}

pub fn config_unison() -> CanonConfig {
    CanonConfig {
        config_id: 3, offsets: array![0_i32, 0].span(), name: 'unison', octave: 7, profile_id: 0,
    }
}

/// Three voices: leader, a fifth below, then an octave above that (a fourth above the leader).
/// Entry order offsets: [0, −4, +3]. Derives the conversation's "no up-a-step" rule.
pub fn config_three_voice_5b_8va() -> CanonConfig {
    CanonConfig {
        config_id: 4, offsets: array![0_i32, -4, 3].span(), name: 'three_5b_8va', octave: 7,
        profile_id: 0,
    }
}

/// Three voices middle→high→low: leader, a fifth above, then an octave below that.
/// Offsets: [0, +4, −3].
pub fn config_three_voice_5a_8vb() -> CanonConfig {
    CanonConfig {
        config_id: 5, offsets: array![0_i32, 4, -3].span(), name: 'three_5a_8vb', octave: 7,
        profile_id: 0,
    }
}

/// Four voices: stacked imitation at the fifth below (Cumming & Schubert four-voice points).
/// Offsets: [0, −4, −8, −12].
pub fn config_four_voice_5b_stack() -> CanonConfig {
    CanonConfig {
        config_id: 6, offsets: array![0_i32, -4, -8, -12].span(), name: 'four_5b_stack', octave: 7,
        profile_id: 0,
    }
}

pub fn num_configs() -> u32 {
    7
}

// ──────────────────────────────────────────────────────────
// Chromatic (mod-12) configurations — extended-harmony aesthetics
// ──────────────────────────────────────────────────────────
// Offsets are in SEMITONES. These are accessed by explicit id via `profiled_config_by_id`; they
// are intentionally NOT part of `config_by_index` / `num_configs`, so the seed-driven Renaissance
// generator's behavior is unchanged.

/// Four-voice stacked real canon spelling a major-seventh chord (root, M3, P5, M7). Jazz profile.
pub fn config_maj7_stack() -> CanonConfig {
    CanonConfig {
        config_id: 7, offsets: array![0_i32, 4, 7, 11].span(), name: 'maj7_stack', octave: 12,
        profile_id: 1,
    }
}

/// Four-voice stacked real canon spelling a minor-seventh chord (root, m3, P5, m7). Jazz profile.
pub fn config_min7_stack() -> CanonConfig {
    CanonConfig {
        config_id: 8, offsets: array![0_i32, 3, 7, 10].span(), name: 'min7_stack', octave: 12,
        profile_id: 1,
    }
}

/// Four-voice dominant-seventh shape for impressionist planing (root, M3, P5, m7). Planing profile.
pub fn config_dom7_planing() -> CanonConfig {
    CanonConfig {
        config_id: 9, offsets: array![0_i32, 4, 7, 10].span(), name: 'dom7_planing', octave: 12,
        profile_id: 3,
    }
}

/// Three-voice quartal stack (two perfect fourths). Quartal profile.
pub fn config_quartal_stack() -> CanonConfig {
    CanonConfig {
        config_id: 10, offsets: array![0_i32, 5, 10].span(), name: 'quartal_stack', octave: 12,
        profile_id: 2,
    }
}

/// Four-voice quartal stack (three perfect fourths). Quartal profile.
pub fn config_quartal4_stack() -> CanonConfig {
    CanonConfig {
        config_id: 11, offsets: array![0_i32, 5, 10, 15].span(), name: 'quartal4_stack', octave: 12,
        profile_id: 2,
    }
}

/// Four-voice mixed-interval tension stack (P4, P5, M7 over the root). Hindemith graded-tension
/// profile — a rich sonority that is permitted (no half-step collision) but high on Series 2.
pub fn config_hindemith4_stack() -> CanonConfig {
    CanonConfig {
        config_id: 12, offsets: array![0_i32, 5, 7, 11].span(), name: 'hindemith4', octave: 12,
        profile_id: 4,
    }
}

/// Four-voice dominant-ninth planing shape (root, M3, m7, M9). A larger color block than the
/// original dom7 planing config while staying within the four-voice strict-canon ceiling.
pub fn config_dom9_planing() -> CanonConfig {
    CanonConfig {
        config_id: 16, offsets: array![0_i32, 4, 10, 14].span(), name: 'dom9_planing',
        octave: 12, profile_id: 3,
    }
}

/// Lydian Imaj9/#11 color without the fifth (root, M3, M7, M9). Lydian profile.
pub fn config_lydian_maj9_stack() -> CanonConfig {
    CanonConfig {
        config_id: 17, offsets: array![0_i32, 4, 11, 14].span(), name: 'lydian_maj9',
        octave: 12, profile_id: 7,
    }
}

/// Dominant altered shell with b9 (root, M3, m7, b9). Dominant-altered profile admits class 1.
pub fn config_dominant_altered_stack() -> CanonConfig {
    CanonConfig {
        config_id: 18, offsets: array![0_i32, 4, 10, 13].span(), name: 'dom_alt_b9',
        octave: 12, profile_id: 8,
    }
}

/// Whole-tone augmented dominant color (root, M3, aug5, m7). Whole-tone planing profile.
pub fn config_whole_tone_stack() -> CanonConfig {
    CanonConfig {
        config_id: 19, offsets: array![0_i32, 4, 8, 10].span(), name: 'whole_tone',
        octave: 12, profile_id: 9,
    }
}

/// Octatonic diminished-axis stack (minor-third cycle). Octatonic profile.
pub fn config_octatonic_axis_stack() -> CanonConfig {
    CanonConfig {
        config_id: 20, offsets: array![0_i32, 3, 6, 9].span(), name: 'oct_axis',
        octave: 12, profile_id: 10,
    }
}

/// Suspended/quartal shell (root, M2, P4, m7). Sus-quartal profile.
pub fn config_sus_quartal_stack() -> CanonConfig {
    CanonConfig {
        config_id: 21, offsets: array![0_i32, 2, 5, 10].span(), name: 'sus_quartal',
        octave: 12, profile_id: 11,
    }
}

/// Pandiatonic white-key cluster/sixth sonority on the diatonic lattice.
pub fn config_pandiatonic_stack() -> CanonConfig {
    CanonConfig {
        config_id: 22, offsets: array![0_i32, 1, 4, 6].span(), name: 'pandiatonic',
        octave: 7, profile_id: 12,
    }
}

/// Spectral-ish dominant-series shell (root, M3, P5, m7). Spectral profile.
pub fn config_spectral_stack() -> CanonConfig {
    CanonConfig {
        config_id: 23, offsets: array![0_i32, 4, 7, 10].span(), name: 'spectral',
        octave: 12, profile_id: 13,
    }
}

/// Bartok axis stack (minor-third/tritone cycle). Bartok-axis profile.
pub fn config_bartok_axis_stack() -> CanonConfig {
    CanonConfig {
        config_id: 24, offsets: array![0_i32, 3, 6, 9].span(), name: 'bartok_axis',
        octave: 12, profile_id: 14,
    }
}

/// Softer chromatic cluster (root, m2, m3). Cluster-soft profile.
pub fn config_cluster_soft_stack() -> CanonConfig {
    CanonConfig {
        config_id: 25, offsets: array![0_i32, 1, 3].span(), name: 'cluster_soft',
        octave: 12, profile_id: 15,
    }
}

/// Major-seventh real answer for intentionally modulating canon-per-tonos behavior.
pub fn config_canon_per_tonos_stack() -> CanonConfig {
    CanonConfig {
        config_id: 26, offsets: array![0_i32, 4, 7, 11].span(), name: 'per_tonos',
        octave: 12, profile_id: 16,
    }
}

/// Four-voice impressionist added-6/9 sonority (root, M3, M6, M9). Warm tertian color without
/// stacked altered tensions; the fifth is left to the walk. Impressionist added-6/9 profile (17).
pub fn config_impressionist_added6_stack() -> CanonConfig {
    CanonConfig {
        config_id: 27, offsets: array![0_i32, 4, 9, 14].span(), name: 'impr_add6',
        octave: 12, profile_id: 17,
    }
}

/// Four-voice bitonal split: two major-third dyads a tritone apart (C/E over F#/A#). The tritone
/// poles read as color, not collision. Bitonal split-field profile (18).
pub fn config_bitonal_split_stack() -> CanonConfig {
    CanonConfig {
        config_id: 28, offsets: array![0_i32, 4, 6, 10].span(), name: 'bitonal',
        octave: 12, profile_id: 18,
    }
}

/// Four-voice Phrygian cadential shell (root, b2, P4, m6) — the b2 semitone gravity is the idiom.
/// Phrygian-cadential profile (19) admits class 1 as color.
pub fn config_phrygian_cadential_stack() -> CanonConfig {
    CanonConfig {
        config_id: 29, offsets: array![0_i32, 1, 5, 8].span(), name: 'phrygian',
        octave: 12, profile_id: 19,
    }
}

/// Four-voice stacked perfect fifths (C–G–D–A) — the open-fifth pentatonic field. Pentatonic
/// open-fifths profile (20) suppresses semitone, tritone and major-seventh friction.
pub fn config_pentatonic_open_stack() -> CanonConfig {
    CanonConfig {
        config_id: 30, offsets: array![0_i32, 7, 14, 21].span(), name: 'penta_open',
        octave: 12, profile_id: 20,
    }
}

/// Three-voice major triad (root, M3, P5) — the parsimonious triad PLR transforms pivot around.
/// Neo-Riemannian triadic profile (21).
pub fn config_neo_riemannian_stack() -> CanonConfig {
    CanonConfig {
        config_id: 31, offsets: array![0_i32, 4, 7].span(), name: 'neo_riem',
        octave: 12, profile_id: 21,
    }
}

/// Three-voice impressionist add-6/9 (root, M3, M6). Profile 17.
pub fn config_impressionist_added6_3v() -> CanonConfig {
    CanonConfig {
        config_id: 32, offsets: array![0_i32, 4, 9].span(), name: 'impr_add6_3',
        octave: 12, profile_id: 17,
    }
}

/// Three-voice bitonal split (C/E + F# dyad). Profile 18.
pub fn config_bitonal_split_3v() -> CanonConfig {
    CanonConfig {
        config_id: 33, offsets: array![0_i32, 4, 6].span(), name: 'bitonal_3',
        octave: 12, profile_id: 18,
    }
}

/// Three-voice Phrygian cadential shell (root, b2, P4). Profile 19.
pub fn config_phrygian_cadential_3v() -> CanonConfig {
    CanonConfig {
        config_id: 34, offsets: array![0_i32, 1, 5].span(), name: 'phrygian_3',
        octave: 12, profile_id: 19,
    }
}

/// Three-voice pentatonic open fifths (root, P5, P5+P5). Profile 20.
pub fn config_pentatonic_open_3v() -> CanonConfig {
    CanonConfig {
        config_id: 35, offsets: array![0_i32, 7, 14].span(), name: 'penta_open_3',
        octave: 12, profile_id: 20,
    }
}

/// Four-voice neo-Riemannian triad + M7 (root, M3, P5, M7). Profile 21.
pub fn config_neo_riemannian_4v() -> CanonConfig {
    CanonConfig {
        config_id: 36, offsets: array![0_i32, 4, 7, 11].span(), name: 'neo_riem_4',
        octave: 12, profile_id: 21,
    }
}

/// Four-voice impressionist add-6/9 (smooth: no semitone melody / ornament fill). Profile 23.
pub fn config_impressionist_added6_smooth_stack() -> CanonConfig {
    CanonConfig {
        config_id: 37, offsets: array![0_i32, 4, 9, 14].span(), name: 'impr_smooth',
        octave: 12, profile_id: 23,
    }
}

/// Three-voice impressionist add-6/9 smooth. Profile 23.
pub fn config_impressionist_added6_smooth_3v() -> CanonConfig {
    CanonConfig {
        config_id: 38, offsets: array![0_i32, 4, 9].span(), name: 'impr_smooth_3',
        octave: 12, profile_id: 23,
    }
}

/// Four-voice pentatonic open-fifths smooth. Profile 22.
pub fn config_pentatonic_open_smooth_stack() -> CanonConfig {
    CanonConfig {
        config_id: 39, offsets: array![0_i32, 7, 14, 21].span(), name: 'penta_smooth',
        octave: 12, profile_id: 22,
    }
}

/// Three-voice pentatonic open-fifths smooth. Profile 22.
pub fn config_pentatonic_open_smooth_3v() -> CanonConfig {
    CanonConfig {
        config_id: 40, offsets: array![0_i32, 7, 14].span(), name: 'penta_smooth_3',
        octave: 12, profile_id: 22,
    }
}

/// Four-voice jazz improvised canon (maj7 stack, turnaround harmony). Profile 24.
pub fn config_jazz_improv_stack() -> CanonConfig {
    CanonConfig {
        config_id: 41, offsets: array![0_i32, 4, 7, 11].span(), name: 'jazz_improv',
        octave: 12, profile_id: 24,
    }
}

/// Three-voice jazz improvised canon (root, M3, P5). Profile 24.
pub fn config_jazz_improv_3v() -> CanonConfig {
    CanonConfig {
        config_id: 42, offsets: array![0_i32, 4, 7].span(), name: 'jazz_improv_3',
        octave: 12, profile_id: 24,
    }
}

// ──────────────────────────────────────────────────────────
// Ligeti micropolyphony configs — diatonic clusters + chromatic cluster band
// ──────────────────────────────────────────────────────────

/// Two-voice octave canon on the white-key (diatonic) lattice — the opening of Ligeti's Étude
/// No. 15 "White on White." Slow, tender, strictly diatonic. Ligeti-white profile.
pub fn config_white_on_white() -> CanonConfig {
    CanonConfig {
        config_id: 13, offsets: array![0_i32, 7].span(), name: 'white_on_white', octave: 7,
        profile_id: 5,
    }
}

/// Four-voice stacked-*second* diatonic canon: a moving white-key cluster band (micropolyphony in
/// miniature). Every vertical is a diatonic 2nd/3rd — all CLASH under Renaissance, all color under
/// the Ligeti-white profile, so the walker produces the cluster by construction. Ligeti-white.
pub fn config_ligeti_cluster() -> CanonConfig {
    CanonConfig {
        config_id: 14, offsets: array![0_i32, 1, 2, 3].span(), name: 'ligeti_cluster', octave: 7,
        profile_id: 5,
    }
}

/// Three-voice stacked-semitone canon on the chromatic lattice: a dense chromatic cluster band
/// (Lux Aeterna texture). The half-step is the idiom here, so it uses the chromatic-micropolyphony
/// profile that un-gates class 1.
pub fn config_ligeti_micro() -> CanonConfig {
    CanonConfig {
        config_id: 15, offsets: array![0_i32, 1, 2].span(), name: 'ligeti_micro', octave: 12,
        profile_id: 6,
    }
}

/// Number of profiled configs reachable by `profiled_config_by_id` (diatonic 0..6, chromatic 7..12,
/// Ligeti 13..15, extended catalogue 16..26, complementary catalogue 27..40, jazz improv 41..42).
pub fn num_profiled_configs() -> u32 {
    43
}

/// Lookup any config (diatonic or chromatic) by stable id. Used by the profile-aware generator.
pub fn profiled_config_by_id(id: u32) -> CanonConfig {
    if id == 7 {
        config_maj7_stack()
    } else if id == 8 {
        config_min7_stack()
    } else if id == 9 {
        config_dom7_planing()
    } else if id == 10 {
        config_quartal_stack()
    } else if id == 11 {
        config_quartal4_stack()
    } else if id == 12 {
        config_hindemith4_stack()
    } else if id == 13 {
        config_white_on_white()
    } else if id == 14 {
        config_ligeti_cluster()
    } else if id == 15 {
        config_ligeti_micro()
    } else if id == 16 {
        config_dom9_planing()
    } else if id == 17 {
        config_lydian_maj9_stack()
    } else if id == 18 {
        config_dominant_altered_stack()
    } else if id == 19 {
        config_whole_tone_stack()
    } else if id == 20 {
        config_octatonic_axis_stack()
    } else if id == 21 {
        config_sus_quartal_stack()
    } else if id == 22 {
        config_pandiatonic_stack()
    } else if id == 23 {
        config_spectral_stack()
    } else if id == 24 {
        config_bartok_axis_stack()
    } else if id == 25 {
        config_cluster_soft_stack()
    } else if id == 26 {
        config_canon_per_tonos_stack()
    } else if id == 27 {
        config_impressionist_added6_stack()
    } else if id == 28 {
        config_bitonal_split_stack()
    } else if id == 29 {
        config_phrygian_cadential_stack()
    } else if id == 30 {
        config_pentatonic_open_stack()
    } else if id == 31 {
        config_neo_riemannian_stack()
    } else if id == 32 {
        config_impressionist_added6_3v()
    } else if id == 33 {
        config_bitonal_split_3v()
    } else if id == 34 {
        config_phrygian_cadential_3v()
    } else if id == 35 {
        config_pentatonic_open_3v()
    } else if id == 36 {
        config_neo_riemannian_4v()
    } else if id == 37 {
        config_impressionist_added6_smooth_stack()
    } else if id == 38 {
        config_impressionist_added6_smooth_3v()
    } else if id == 39 {
        config_pentatonic_open_smooth_stack()
    } else if id == 40 {
        config_pentatonic_open_smooth_3v()
    } else if id == 41 {
        config_jazz_improv_stack()
    } else if id == 42 {
        config_jazz_improv_3v()
    } else {
        config_by_id(id)
    }
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

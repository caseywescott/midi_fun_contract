//! Renaissance Improvised-Canon — Generator.
//!
//! Deterministic melodic-canon generation. A seed selects a `CanonConfig`, mode, length and
//! time unit; an LCG walks the leader within the proven-consonant alphabet (see `canon_rules`);
//! the followers are forced exact delayed transpositions; correctness is asserted, not searched.
//!
//! Output is a stream of [`NoteEvent`]s for the existing MIDI/media engine.
//!
//! See `docs/renaissance_canon_improvisation_spec.md`.

use core::array::ArrayTrait;
use core::option::OptionTrait;
use koji::lcg::LCG;
use koji::sine_wave::{scale_duration_by_wave, struct_beat_starts};
use koji::rng::{RandomSource, bounded};
use koji::composition::canon_rules::{
    CanonConfig, PairConstraint, config_by_id, num_configs, pair_constraints,
    profiled_config_by_id, generic_class, is_consonant_class, contains_i32, abs_i32,
    keep_within_skip, config_ligeti_cluster, config_white_on_white,
};
use koji::composition::aesthetic_profile::{
    AestheticProfile, profile_renaissance, profile_by_id, profile_ligeti_white, vertical_ok,
    is_perfect_vertical, allowed_steps_multivoice_p, step_satisfies_constraints_p, full_step_range_p,
    is_avoid_note, vertical_tier, PAR_ALLOW, PAR_LIMIT, AVOID_NONE, AVOID_STRONG, STABLE,
    CONSONANT, SOFT,
};
use koji::composition::jazz_harmony::{
    jazz_material_ok_with_walk, jazz_timeline_material_ok_for_plan,
    turnaround_chord_pcs_for_plan, turnaround_plan_default,
    turnaround_plan_from_canon_seed, turnaround_region_at, TurnaroundPlan,
};
use koji::composition::harmonic_walk::{
    canon_seed_enable_harmonic_walk, harmonic_walk_enabled_from_seed,
};
use koji::composition::neo_riemannian_harmony::neo_timeline_material_ok;
use koji::composition::melodic_motion::{
    ORN_FILL_CHROMATIC, ORN_FILL_MATERIAL, ORN_FILL_MIN_STEP, ORN_FILL_STRUCTURAL,
    FILL_MODE_PROFILE,
    forbids_semitone_structural_step, min_step_for_ornament_subdivide,
    ornament_fill_mode_for_profile, ornament_structural_only,
};

// ──────────────────────────────────────────────────────────
// Bounds
// ──────────────────────────────────────────────────────────

pub const MIN_LEN: u32 = 8;
pub const MAX_LEN: u32 = 24;
/// Keep the leader within ±this many diatonic degrees of its start (≈ one octave), so realized
/// pitches stay in a singable register and MIDI keynums never under/overflow.
pub const REGISTER_BAND: i32 = 7;
pub const DEFAULT_VELOCITY: u8 = 90;

// ──────────────────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────────────────

/// A single sounding note for the renderer.
#[derive(Copy, Drop)]
pub struct NoteEvent {
    /// Absolute grid position (in `time_unit`s).
    pub time: u32,
    pub duration: u32,
    /// MIDI keynum.
    pub pitch: u8,
    pub velocity: u8,
    pub voice_id: u32,
}

/// One canonic voice.
#[derive(Copy, Drop)]
pub struct CanonVoice {
    pub voice_id: u32,
    /// Interval of imitation relative to the leader (signed diatonic steps).
    pub offset: i32,
    /// Entry delay in structural notes (== voice_id for a stacked stretto canon).
    pub entry: u32,
    pub is_leader: bool,
    /// Time-units this voice spends on each structural note (mensuration). 1 = leader speed;
    /// 2 = augmentation (twice as slow); used only by the mensuration emitter/validator. Every
    /// same-speed (stretto) path leaves this at 1, so existing behavior is unchanged.
    pub dilation: u32,
}

/// A complete melodic canon, structural frame only (pre-ornamentation).
#[derive(Drop)]
pub struct MelodicCanon {
    pub config_id: u32,
    pub config_name: felt252,
    /// Voice offsets in entry order.
    pub offsets: Span<i32>,
    /// Structural leader degrees on the diatonic lattice (degree 0 == modal final).
    pub leader_degrees: Span<i32>,
    /// Leader melodic steps (length == leader_degrees.len() − 1).
    pub leader_steps: Span<i32>,
    pub mode_id: u8,
    pub tonic_keynum: u8,
    pub time_unit: u32,
    pub voices: Span<CanonVoice>,
    /// Lattice the degrees/offsets live on: 7 (diatonic) or 12 (chromatic). Drives realization.
    pub octave: u32,
    /// Aesthetic profile id this canon was generated under (0 = Renaissance).
    pub profile_id: u32,
}

/// Onchain metadata.
#[derive(Copy, Drop)]
pub struct MelodicCanonTraits {
    pub config_id: u32,
    pub profile_id: u32,
    pub profile_name: felt252,
    pub voice_count: u32,
    pub interval_of_imitation: i32,
    pub mode_id: u8,
    pub octave: u32,
    pub length: u32,
    pub time_unit: u32,
    pub melodic_alphabet_size: u32,
    pub max_tier_used: u8,
    pub contains_minor_second: bool,
    pub chord_quality: felt252,
}

// ──────────────────────────────────────────────────────────
// Bit helpers (mirrors rhythmic_tiling)
// ──────────────────────────────────────────────────────────

fn pow2(p: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= p {
            break;
        }
        r *= 2;
        i += 1;
    };
    r
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

// ──────────────────────────────────────────────────────────
// Modal realization
// ──────────────────────────────────────────────────────────

/// Semitone offsets from the final for the 7 diatonic degrees of a mode.
pub fn mode_scale(mode_id: u8) -> Span<u8> {
    let m = mode_id % 6;
    if m == 0 {
        array![0_u8, 2, 4, 5, 7, 9, 11].span() // Ionian / major
    } else if m == 1 {
        array![0_u8, 2, 3, 5, 7, 9, 10].span() // Dorian
    } else if m == 2 {
        array![0_u8, 1, 3, 5, 7, 8, 10].span() // Phrygian
    } else if m == 3 {
        array![0_u8, 2, 4, 6, 7, 9, 11].span() // Lydian
    } else if m == 4 {
        array![0_u8, 2, 4, 5, 7, 9, 10].span() // Mixolydian
    } else {
        array![0_u8, 2, 3, 5, 7, 8, 10].span() // Aeolian / natural minor
    }
}

pub fn num_modes() -> u32 {
    6
}

/// Realize a signed diatonic degree to a MIDI keynum. Degree 0 maps to `tonic_keynum`.
/// Uses an octave bias so all arithmetic stays unsigned (no signed division).
pub fn degree_to_keynum(degree: i32, tonic_keynum: u8, scale: Span<u8>) -> u8 {
    let bias: i32 = 70; // 10 octaves of diatonic degrees
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    let oct: u32 = du / 7;
    let idx: u32 = du % 7;
    let semis: u32 = (*scale.at(idx)).into();
    let base: u32 = tonic_keynum.into();
    // keynum = tonic + 12*(oct − 10) + semis
    let total: u32 = base + 12 * oct + semis - 120;
    total.try_into().unwrap()
}

/// Realize a chromatic (semitone-lattice) degree: the degree *is* the signed semitone offset from
/// the tonic. Octave-biased so all arithmetic stays unsigned.
pub fn chromatic_degree_to_keynum(degree: i32, tonic_keynum: u8) -> u8 {
    let bias: i32 = 60;
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    let base: u32 = tonic_keynum.into();
    (base + du - 60).try_into().unwrap()
}

/// Realize a degree on either lattice. Diatonic (octave 7) goes through the mode; chromatic
/// (octave 12) maps the degree directly to a semitone offset.
pub fn realize_degree(octave: u32, degree: i32, tonic_keynum: u8, mode_id: u8) -> u8 {
    if octave == 12 {
        chromatic_degree_to_keynum(degree, tonic_keynum)
    } else {
        degree_to_keynum(degree, tonic_keynum, mode_scale(mode_id))
    }
}

fn pc12(degree: i32) -> u8 {
    let bias: i32 = 120;
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    (du % 12).try_into().unwrap()
}

fn contains_u8(set: Span<u8>, v: u8) -> bool {
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

/// True when this profile pins the leader to a specific pitch-class collection (not merely graded
/// verticals). For these ids, `candidates_at` treats material as a hard gate so the walk cannot
/// fall back to out-of-style pitch classes.
fn profile_has_hard_material_gate(id: u32) -> bool {
    id == 17 || id == 18 || id == 19 || id == 20 || id == 21 || id == 22 || id == 23
        || id == 24
}

/// Structural leader may not move by a semitone (profile motion policy).
fn profile_forbids_semitone_melodic_step(id: u32) -> bool {
    forbids_semitone_structural_step(id)
}

/// No rhythmic subdivision / chromatic fill between structural degrees.
fn profile_ornament_structural_only(id: u32) -> bool {
    ornament_structural_only(id)
}

fn profile_material_ok(profile: @AestheticProfile, degree: i32) -> bool {
    if *profile.octave != 12 {
        return true;
    }
    let pc = pc12(degree);
    let id = *profile.id;
    if id == 7 {
        // Lydian: C D E F# G A B
        contains_u8(array![0_u8, 2, 4, 6, 7, 9, 11].span(), pc)
    } else if id == 8 {
        // Altered dominant: C Db Eb E Gb Ab Bb
        contains_u8(array![0_u8, 1, 3, 4, 6, 8, 10].span(), pc)
    } else if id == 9 {
        // Whole-tone: C D E F# G# Bb
        contains_u8(array![0_u8, 2, 4, 6, 8, 10].span(), pc)
    } else if id == 10 {
        // Octatonic half-whole collection.
        contains_u8(array![0_u8, 1, 3, 4, 6, 7, 9, 10].span(), pc)
    } else if id == 13 {
        // A compact harmonic-series color set.
        contains_u8(array![0_u8, 2, 4, 7, 10].span(), pc)
    } else if id == 14 {
        // Axis cycle.
        contains_u8(array![0_u8, 3, 6, 9].span(), pc)
    } else if id == 17 {
        // Impressionist add6/9: major/minor triad + 6 + 9, no altered dominant color.
        contains_u8(array![0_u8, 2, 3, 4, 7, 9, 11].span(), pc)
    } else if id == 18 {
        // Bitonal split: C-major and F#-major triad poles (controlled cross-relations).
        contains_u8(array![0_u8, 1, 4, 6, 7, 10].span(), pc)
    } else if id == 19 {
        // Phrygian cadential collection on C (b2 gravity, no bright Lydian field).
        contains_u8(array![0_u8, 1, 3, 5, 7, 8, 10].span(), pc)
    } else if id == 20 {
        // Major pentatonic: open fifths/fourths, sparse chromatic friction.
        contains_u8(array![0_u8, 2, 4, 7, 9].span(), pc)
    } else if id == 21 {
        // Neo-Riemannian: legacy union (timeline gate is authoritative when walking).
        contains_u8(array![0_u8, 3, 4, 5, 7, 9, 11].span(), pc)
    } else if id == 22 {
        // Major pentatonic (smooth variant).
        contains_u8(array![0_u8, 2, 4, 7, 9].span(), pc)
    } else if id == 23 {
        // Impressionist add6/9 without adjacent semitone pitch pairs in the field.
        contains_u8(array![0_u8, 2, 4, 7, 9, 11].span(), pc)
    } else {
        true
    }
}

fn strong_beat_avoid_candidate(
    profile: @AestheticProfile,
    degree: i32,
    pos: u32,
    timeline_len: u32,
    turnaround_plan: TurnaroundPlan,
) -> bool {
    if *profile.avoid_policy == AVOID_NONE || *profile.octave != 12 {
        return false;
    }
    if *profile.avoid_policy == AVOID_STRONG && pos % 4 != 0 {
        return false;
    }
    let id = *profile.id;
    if id == 24 && timeline_len > 0 {
        let r = turnaround_region_at(pos, timeline_len);
        is_avoid_note(turnaround_chord_pcs_for_plan(turnaround_plan, r), pc12(degree))
    } else if id == 1 || id == 7 {
        is_avoid_note(array![0_u8, 4, 7, 11].span(), pc12(degree))
    } else if id == 19 {
        // Phrygian: keep b2 color, but bar dense upper extensions on strong beats.
        let pc = pc12(degree);
        pc == 10 || pc == 11
    } else {
        false
    }
}

fn blocked_by_parallel_policy(
    profile: @AestheticProfile, primary_d: i32, steps: Span<i32>, m: i32,
) -> bool {
    if *profile.par_policy == PAR_ALLOW || steps.len() == 0 {
        return false;
    }
    if !is_perfect_vertical(profile, primary_d, m) {
        return false;
    }
    let prev = *steps.at(steps.len() - 1);
    if m != prev {
        return false;
    }
    if *profile.par_policy == PAR_LIMIT {
        if steps.len() < 2 {
            return false;
        }
        return *steps.at(steps.len() - 2) == prev;
    }
    true
}

// ──────────────────────────────────────────────────────────
// Leader walk (the cascade of rules)
// ──────────────────────────────────────────────────────────

/// Build the candidate list at the current position: full step range filtered by
/// (a) all pairwise window constraints, (b) parallel-perfect avoidance, with the register band
/// `[lo, hi]` applied as a *soft* preference layered on top. Parameterized by the aesthetic profile
/// — the only style-dependent inputs are the profile's vertical predicate (inside
/// `step_satisfies_constraints_p`), its perfect-interval test, and its parallel-perfect policy.
///
/// Selection precedence: (in-band ∩ stylistic) ▸ in-band ▸ any-valid. The in-band ∩ stylistic and
/// in-band sets are exactly the legacy `prim`/`any` sets when the band is constant, so determinism
/// is preserved bit-for-bit for every existing profile/config; the any-valid fallback only fires
/// when a *gliding* band would otherwise empty the candidate set, which the constant band never did.
fn candidates_at(
    profile: @AestheticProfile,
    constraints: Span<PairConstraint>,
    primary_d: i32,
    pos: u32,
    degrees: Span<i32>,
    steps: Span<i32>,
    prefer: Span<i32>,
    lo: i32,
    hi: i32,
    timeline_len: u32,
    turnaround_plan: TurnaroundPlan,
    canon_seed: felt252,
    use_harmonic_walk: bool,
) -> Array<i32> {
    let cur = *degrees.at(degrees.len() - 1);
    let mut prim: Array<i32> = ArrayTrait::new(); // in-band + stylistic
    let mut any: Array<i32> = ArrayTrait::new(); // in-band, valid
    let mut valid: Array<i32> = ArrayTrait::new(); // valid regardless of band (glide fallback)
    let full = full_step_range_p(profile);
    let mut i: u32 = 0;
    loop {
        if i >= full.len() {
            break;
        }
        let m = *full.at(i);
        i += 1;
        if profile_forbids_semitone_melodic_step(*profile.id) && abs_i32(m) == 1 {
            continue;
        }
        // (a) pairwise constraints (all windows that close here)
        if !step_satisfies_constraints_p(profile, constraints, steps, m) {
            continue;
        }
        // (b) parallel-perfect policy: Renaissance forbids immediate repeats into perfects;
        //     jazz/Hindemith-style limit profiles allow a short echo but block longer chains.
        if blocked_by_parallel_policy(profile, primary_d, steps, m) {
            continue;
        }
        let next = cur + m;
        // (c) profile-specific pitch material. Complementary profiles hard-gate the leader path;
        //     legacy filtered profiles keep leader-only soft preference.
        let material_ok = if *profile.id == 24 && timeline_len > 0 {
            jazz_material_ok_with_walk(
                canon_seed,
                use_harmonic_walk,
                turnaround_plan,
                next,
                pos,
                timeline_len,
                pos % 4 == 0,
            )
        } else if *profile.id == 21 && timeline_len > 0 {
            neo_timeline_material_ok(next, pos, timeline_len, pos % 4 == 0)
        } else {
            profile_material_ok(profile, next)
        };
        if profile_has_hard_material_gate(*profile.id) && !material_ok {
            continue;
        }
        valid.append(m);
        // register band, applied softly
        if next >= lo && next <= hi {
            // Avoid notes are a strong-beat preference, but not a hard generator failure: if every
            // in-band option is avoid-colored, the fallback still preserves the structural canon.
            if material_ok
                && !strong_beat_avoid_candidate(
                    profile, next, pos, timeline_len, turnaround_plan,
                ) {
                any.append(m);
                if contains_i32(prefer, m) {
                    prim.append(m);
                }
            }
        }
    };
    // When the small-skip preference set collapses to unison only but larger steps are valid,
    // use the wider set so the leader cannot stall on one pitch.
    if prim.len() == 1 && *prim.at(0) == 0 && any.len() > 0 {
        any
    } else if prim.len() > 0 {
        prim
    } else if any.len() > 0 {
        any
    } else {
        valid
    }
}

/// Improvisation skip window for the leader's preferred step set. Chromatic stacked canons need
/// thirds/fifths in the preferred band; Ligeti semitone-cluster profile (6) keeps the tight window.
fn prefer_skip_for_profile(id: u32, octave: u32) -> u32 {
    if octave == 12 && id != 6 {
        7
    } else {
        4
    }
}

/// True when the last `min_repeat` structural degrees are all the same pitch.
fn leader_degree_stagnant(degrees: Span<i32>, min_repeat: u32) -> bool {
    if degrees.len() < min_repeat {
        return false;
    }
    let cur = *degrees.at(degrees.len() - 1);
    let mut count: u32 = 1;
    let mut back: u32 = 2;
    loop {
        if back > degrees.len() || count >= min_repeat {
            break;
        }
        let idx = degrees.len() - back;
        if *degrees.at(idx) != cur {
            break;
        }
        count += 1;
        back += 1;
    };
    count >= min_repeat
}

/// Drop unison steps when other candidates exist (anti-static melody).
fn cands_without_unison(cands: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= cands.len() {
            break;
        }
        let m = *cands.at(i);
        if m != 0 {
            out.append(m);
        }
        i += 1;
    };
    out
}

/// Prefer leaps/thirds over unison on chromatic profiled walks.
fn pick_motion_biased_step(cands: Span<i32>, raw: u32) -> i32 {
    let mut triadic: Array<i32> = ArrayTrait::new();
    let mut motion: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= cands.len() {
            break;
        }
        let m = *cands.at(i);
        if abs_i32(m) >= 3 {
            triadic.append(m);
        } else if m != 0 {
            motion.append(m);
        }
        i += 1;
    };
    let pool = if triadic.len() > 0 {
        triadic.span()
    } else if motion.len() > 0 {
        motion.span()
    } else {
        cands
    };
    *pool.at(bounded(raw, pool.len()))
}

/// Chromatic leader pick: motion-biased; drop unison when the line has stalled on one degree.
fn pick_chromatic_leader_step(
    cands: Span<i32>, raw: u32, degrees: Span<i32>,
) -> i32 {
    let pool = if leader_degree_stagnant(degrees, 3) {
        let filtered = cands_without_unison(cands);
        if filtered.len() > 0 {
            filtered.span()
        } else {
            cands
        }
    } else {
        cands
    };
    pick_motion_biased_step(pool, raw)
}

/// Choose the next leader step (non-cadence path).
fn pick_leader_step_random(
    profile: @AestheticProfile,
    cands: Span<i32>,
    degrees: Span<i32>,
    raw: u32,
    primary_d: i32,
    p: u32,
    len: u32,
) -> i32 {
    if *profile.id == 4 {
        pick_tension_toward(cands, profile, primary_d, p, len)
    } else if *profile.octave == 12 && *profile.id != 6 {
        pick_chromatic_leader_step(cands, raw, degrees)
    } else {
        *cands.at(bounded(raw, cands.len()))
    }
}

/// A register-band envelope for the leader walk. The band is centered on a line that glides from
/// `center_start` (at the first note) to `center_end` (at the last), with a fixed `half_width`.
/// A *constant* band (the legacy behavior) is `center_start == center_end == 0`. A gliding center
/// drives the canonic cluster band up/down the register over time — the core of Ligeti's
/// micropolyphonic "moving band" texture — while `half_width` sets the band's thickness.
#[derive(Copy, Drop)]
pub struct BandEnvelope {
    pub center_start: i32,
    pub center_end: i32,
    pub half_width: i32,
}

/// The constant full-register band a profile uses by default (±REGISTER_BAND diatonic, ±14 chromatic).
pub fn constant_band(profile: @AestheticProfile) -> BandEnvelope {
    let hw: i32 = if *profile.octave == 12 {
        14
    } else {
        REGISTER_BAND
    };
    BandEnvelope { center_start: 0, center_end: 0, half_width: hw }
}

/// The `[lo, hi]` leader-degree bounds at structural position `p` of `len`, linearly interpolating
/// the band center from `center_start` to `center_end`.
fn band_at(env: @BandEnvelope, p: u32, len: u32) -> (i32, i32) {
    let center: i32 = if len <= 1 {
        *env.center_start
    } else {
        let span = *env.center_end - *env.center_start;
        let pi: i32 = p.try_into().unwrap();
        let den: i32 = (len - 1).try_into().unwrap();
        *env.center_start + span * pi / den
    };
    (center - *env.half_width, center + *env.half_width)
}

/// Structural notes reserved for the cadential approach to the modal final.
pub const CADENCE_LEN: u32 = 3;

/// Cadence target degree for note index `p` (of `len`): the last three notes aim for the final
/// via a stepwise clausula. Returns `None` when this position is not part of the cadence, or when
/// the configuration lacks the unit (step) motion a stepwise cadence needs (e.g. 3-voice stacks).
fn cadence_target(p: u32, len: u32, primary_d: i32, has_unit_step: bool) -> Option<i32> {
    if !has_unit_step || len < CADENCE_LEN + 1 || p + CADENCE_LEN < len {
        return Option::None;
    }
    // descend to the final for "above" canons, ascend for "below" canons
    let sign: i32 = if primary_d < 0 {
        -1
    } else {
        1
    };
    let remaining: u32 = len - 1 - p; // 0 at the final note, 1 at penult, 2 before that
    let rem_i: i32 = remaining.try_into().unwrap();
    Option::Some(sign * rem_i) // targets … +2,+1,0 (above) or … −2,−1,0 (below)
}

/// From `cands`, the candidate step whose resulting degree is closest to `target`.
fn pick_toward(cands: Span<i32>, cur: i32, target: i32) -> i32 {
    let mut best = *cands.at(0);
    let mut best_dist = abs_i32((cur + best) - target);
    let mut i: u32 = 1;
    loop {
        if i >= cands.len() {
            break;
        }
        let m = *cands.at(i);
        let d = abs_i32((cur + m) - target);
        if d < best_dist {
            best = m;
            best_dist = d;
        }
        i += 1;
    };
    best
}

fn abs_u8(a: u8, b: u8) -> u32 {
    if a > b {
        (a - b).into()
    } else {
        (b - a).into()
    }
}

fn hindemith_target_tier(p: u32, len: u32) -> u8 {
    if len <= 4 {
        return CONSONANT;
    }
    if p * 4 < len {
        CONSONANT
    } else if p * 4 < len * 3 {
        SOFT
    } else {
        STABLE
    }
}

fn pick_tension_toward(
    cands: Span<i32>, profile: @AestheticProfile, primary_d: i32, p: u32, len: u32,
) -> i32 {
    let target = hindemith_target_tier(p, len);
    let mut best = *cands.at(0);
    let mut best_dist = abs_u8(vertical_tier(profile, primary_d, best), target);
    let mut i: u32 = 1;
    loop {
        if i >= cands.len() {
            break;
        }
        let m = *cands.at(i);
        let d = abs_u8(vertical_tier(profile, primary_d, m), target);
        if d < best_dist {
            best = m;
            best_dist = d;
        }
        i += 1;
    };
    best
}

/// Walk the leader under an explicit aesthetic profile: `len` structural degrees starting on the
/// final (degree 0). When `cadence` is true the final notes are steered to the final to form a
/// proper ending, staying within the profile's permitted alphabet so the strict canon stays
/// clash-free. This is the single generalized walker; the Renaissance `walk_leader` is a wrapper.
pub fn walk_leader_profiled(
    canon_seed: felt252,
    seed_state: u32,
    offsets: Span<i32>,
    profile: @AestheticProfile,
    len: u32,
    cadence: bool,
    turnaround_plan: TurnaroundPlan,
) -> (Array<i32>, Array<i32>) {
    walk_leader_banded(
        canon_seed,
        seed_state,
        offsets,
        profile,
        len,
        cadence,
        constant_band(profile),
        turnaround_plan,
    )
}

/// The generalized leader walk with an explicit [`BandEnvelope`]. Identical to the constant-band
/// walk except the register bounds are taken from `env` per position, so the leader's tessitura
/// (and with it the whole canonic cluster) can glide/widen across the piece. With
/// `constant_band(profile)` this is bit-for-bit the legacy behavior.
pub fn walk_leader_banded(
    canon_seed: felt252,
    seed_state: u32,
    offsets: Span<i32>,
    profile: @AestheticProfile,
    len: u32,
    cadence: bool,
    env: BandEnvelope,
    turnaround_plan: TurnaroundPlan,
) -> (Array<i32>, Array<i32>) {
    let use_harmonic_walk = harmonic_walk_enabled_from_seed(canon_seed);
    let constraints = pair_constraints(offsets);
    let prefer = keep_within_skip(
        allowed_steps_multivoice_p(profile, offsets).span(),
        prefer_skip_for_profile(*profile.id, *profile.octave),
    );
    let primary_d = if offsets.len() > 1 {
        *offsets.at(1)
    } else {
        0
    };
    // does the per-step alphabet contain a unison-step we can cadence by?
    let has_unit_step = contains_i32(prefer.span(), 1) || contains_i32(prefer.span(), -1);

    let mut degrees: Array<i32> = ArrayTrait::new();
    degrees.append(0);
    let mut steps: Array<i32> = ArrayTrait::new();

    let mut rng = LCG { state: seed_state, multiplier: 5, increment: 3, modulus: 256 };

    let mut p: u32 = 1;
    loop {
        if p >= len {
            break;
        }
        let (lo, hi) = band_at(@env, p, len);
        let timeline_len = if *profile.id == 24 || *profile.id == 21 {
            len
        } else {
            0
        };
        let cands = candidates_at(
            profile,
            constraints.span(),
            primary_d,
            p,
            degrees.span(),
            steps.span(),
            prefer.span(),
            lo,
            hi,
            timeline_len,
            turnaround_plan,
            canon_seed,
            use_harmonic_walk,
        );
        assert(cands.len() > 0, 'no valid leader step');
        let cur = *degrees.at(degrees.len() - 1);
        let (raw, next) = rng.draw();
        rng = next;
        let m = if cadence {
            match cadence_target(p, len, primary_d, has_unit_step) {
                Option::Some(t) => pick_toward(cands.span(), cur, t),
                Option::None => {
                    pick_leader_step_random(
                        profile, cands.span(), degrees.span(), raw, primary_d, p, len,
                    )
                },
            }
        } else {
            pick_leader_step_random(
                profile, cands.span(), degrees.span(), raw, primary_d, p, len,
            )
        };
        degrees.append(cur + m);
        steps.append(m);
        p += 1;
    };
    (degrees, steps)
}

/// Like `walk_leader_banded`, but with an explicit pairwise constraint set (for entry-lag canons).
/// Legacy callers use `walk_leader_banded`, which still derives constraints from stacked offsets.
pub fn walk_leader_banded_with_constraints(
    canon_seed: felt252,
    seed_state: u32,
    offsets: Span<i32>,
    constraints: Span<PairConstraint>,
    profile: @AestheticProfile,
    len: u32,
    cadence: bool,
    env: BandEnvelope,
    turnaround_plan: TurnaroundPlan,
) -> (Array<i32>, Array<i32>) {
    let use_harmonic_walk = harmonic_walk_enabled_from_seed(canon_seed);
    let prefer = keep_within_skip(
        allowed_steps_multivoice_p(profile, offsets).span(),
        prefer_skip_for_profile(*profile.id, *profile.octave),
    );
    let primary_d = if offsets.len() > 1 {
        *offsets.at(1)
    } else {
        0
    };
    let has_unit_step = contains_i32(prefer.span(), 1) || contains_i32(prefer.span(), -1);

    let mut degrees: Array<i32> = ArrayTrait::new();
    degrees.append(0);
    let mut steps: Array<i32> = ArrayTrait::new();

    let mut rng = LCG { state: seed_state, multiplier: 5, increment: 3, modulus: 256 };

    let mut p: u32 = 1;
    loop {
        if p >= len {
            break;
        }
        let (lo, hi) = band_at(@env, p, len);
        let timeline_len = if *profile.id == 24 || *profile.id == 21 {
            len
        } else {
            0
        };
        let cands = candidates_at(
            profile,
            constraints,
            primary_d,
            p,
            degrees.span(),
            steps.span(),
            prefer.span(),
            lo,
            hi,
            timeline_len,
            turnaround_plan,
            canon_seed,
            use_harmonic_walk,
        );
        assert(cands.len() > 0, 'no valid leader step');
        let cur = *degrees.at(degrees.len() - 1);
        let (raw, next) = rng.draw();
        rng = next;
        let m = if cadence {
            match cadence_target(p, len, primary_d, has_unit_step) {
                Option::Some(t) => pick_toward(cands.span(), cur, t),
                Option::None => {
                    pick_leader_step_random(
                        profile, cands.span(), degrees.span(), raw, primary_d, p, len,
                    )
                },
            }
        } else {
            pick_leader_step_random(
                profile, cands.span(), degrees.span(), raw, primary_d, p, len,
            )
        };
        degrees.append(cur + m);
        steps.append(m);
        p += 1;
    };
    (degrees, steps)
}

/// Walk the leader for a Renaissance (diatonic) config. Thin wrapper over `walk_leader_profiled`
/// with the Renaissance profile — bit-for-bit identical to the original behavior.
pub fn walk_leader(
    seed_state: u32, config: @CanonConfig, len: u32, cadence: bool,
) -> (Array<i32>, Array<i32>) {
    walk_leader_profiled(
        0,
        seed_state,
        *config.offsets,
        @profile_renaissance(),
        len,
        cadence,
        turnaround_plan_default(),
    )
}

// ──────────────────────────────────────────────────────────
// Validators (assertions, not searches)
// ──────────────────────────────────────────────────────────

/// Every simultaneous voice pair is an acceptable vertical under `profile` (tier within budget).
/// By the lag-difference identity this MUST hold for a leader restricted to the permitted
/// alphabet; failure indicates a table/profile bug, not bad luck. This is the generalized
/// correctness assertion (the melodic analogue of `is_direct_sum`).
pub fn all_pairs_clash_free(canon: @MelodicCanon, profile: @AestheticProfile) -> bool {
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
                    if !vertical_ok(profile, da, db) {
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

/// Renaissance-profile specialization of `all_pairs_clash_free` (consonant = unison/3rd/5th/6th).
/// Preserved for the existing two-/three-/four-voice diatonic canons and their tests.
pub fn all_pairs_consonant(canon: @MelodicCanon) -> bool {
    all_pairs_clash_free(canon, @profile_renaissance())
}

/// The irreducible "no voice-leading clash" guarantee: no simultaneous voice pair forms a minor
/// 2nd / minor 9th (chromatic class 1). Holds by construction for any chromatic profile whose
/// table marks class 1 as a clash.
pub fn no_minor_ninth(canon: @MelodicCanon) -> bool {
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
                    if abs_i32(da - db) % 12 == 1 {
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

pub fn max_vertical_tier_used(canon: @MelodicCanon, profile: @AestheticProfile) -> u8 {
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
    let mut max_tier = STABLE;
    let mut t: u32 = 0;
    loop {
        if t >= total {
            break;
        }
        let mut a: u32 = 0;
        loop {
            if a >= nv {
                break;
            }
            let va = *voices.at(a);
            let mut b: u32 = a + 1;
            loop {
                if b >= nv {
                    break;
                }
                let vb = *voices.at(b);
                let sound_a = t >= va.entry && (t - va.entry) < len;
                let sound_b = t >= vb.entry && (t - vb.entry) < len;
                if sound_a && sound_b {
                    let da = *degs.at(t - va.entry) + va.offset;
                    let db = *degs.at(t - vb.entry) + vb.offset;
                    let tier = vertical_tier(profile, da, db);
                    if tier > max_tier {
                        max_tier = tier;
                    }
                }
                b += 1;
            };
            a += 1;
        };
        t += 1;
    };
    max_tier
}

/// The documented cadence clausula for a configuration: the leader's and follower's melodic
/// steps over the final notes, where imitation is deliberately broken (Schubert: "stop imitating
/// me"). Step values are signed diatonic. Encodes the conversation's verbal formulas verbatim.
#[derive(Drop)]
pub struct CadenceFormula {
    /// Leader's melodic steps through the cadence.
    pub leader_tail: Span<i32>,
    /// Follower's melodic steps through the cadence (differs from the leader — imitation breaks).
    pub comes_tail: Span<i32>,
    pub suspension: bool,
}

/// Cadence formula by config id. (`config_id`: 0 = fifth above, 1 = fifth below.)
pub fn cadence_formula(config_id: u32) -> CadenceFormula {
    if config_id == 1 {
        // 5th below: "go up a step, then up a third mid-measure, prepare the suspension."
        CadenceFormula {
            leader_tail: array![1_i32, 2].span(), comes_tail: array![1_i32, 1].span(),
            suspension: true,
        }
    } else {
        // 5th above: "go down a step, then up a fourth; follower goes down a step, then down again."
        CadenceFormula {
            leader_tail: array![-1_i32, 3].span(), comes_tail: array![-1_i32, -1].span(),
            suspension: true,
        }
    }
}

/// The canon comes to rest: the leader resolves to the modal final (degree 0) and the closing
/// two-voice sonority is consonant (typically the imperfect 6th that precedes the staggered final
/// resolution — the classic Renaissance cadential approach).
pub fn cadence_lands_on_final(canon: @MelodicCanon) -> bool {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let len = degs.len();
    if len == 0 {
        return false;
    }
    if *degs.at(len - 1) != 0 {
        return false;
    }
    if voices.len() < 2 || len < 2 {
        return true;
    }
    let v1 = *voices.at(1);
    let v1_deg = *degs.at(len - 2) + v1.offset;
    is_consonant_class(generic_class(0, v1_deg))
}

/// The canon really is a canon: each follower's degree at each position equals the leader's
/// degree plus the follower's offset (exact transposition).
pub fn exact_imitation(canon: @MelodicCanon) -> bool {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let mut vi: u32 = 0;
    let mut ok = true;
    loop {
        if vi >= voices.len() || !ok {
            break;
        }
        let v = *voices.at(vi);
        let mut p: u32 = 0;
        loop {
            if p >= degs.len() {
                break;
            }
            // follower voice plays leader's degree at p, transposed by offset
            let follower_deg = *degs.at(p) + v.offset;
            if follower_deg - v.offset != *degs.at(p) {
                ok = false;
                break;
            }
            p += 1;
        };
        vi += 1;
    };
    ok
}

// ──────────────────────────────────────────────────────────
// Event generation
// ──────────────────────────────────────────────────────────

/// Emit the structural canon as `NoteEvent`s (the "plaine" / first-species frame).
pub fn canon_to_note_events(canon: @MelodicCanon) -> Array<NoteEvent> {
    let n = (*canon.leader_degrees).len();
    if n <= 1 {
        return ArrayTrait::new();
    }
    let mut plain: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n - 1 {
            break;
        }
        plain.append(1_u32);
        i += 1;
    };
    canon_to_ornamented_note_events(canon, plain.span())
}

/// Montanos / Morley "divided" version: each melodic interval may be split into `subdivisions[p]`
/// stepwise passing tones (2 or 4 notes against one structural beat). Followers imitate exactly.
pub fn canon_to_ornamented_note_events(
    canon: @MelodicCanon, subdivisions: Span<u32>,
) -> Array<NoteEvent> {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let octave = *canon.octave;
    let mode = *canon.mode_id;
    let unit = *canon.time_unit;
    let len = degs.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let v = *voices.at(vi);
        let mut p: u32 = 0;
        loop {
            if p >= len {
                break;
            }
            let from_deg = *degs.at(p) + v.offset;
            let time_base = (p + v.entry) * unit;
            if p + 1 < len {
                let to_deg = *degs.at(p + 1) + v.offset;
                let mut s = *subdivisions.at(p);
                if s == 0 {
                    s = 1;
                }
                if unit % s != 0 {
                    s = 1;
                }
                let sub_dur = unit / s;
                let fill = subdivide_for_fill_mode(
                    from_deg, to_deg, s, *canon.profile_id, FILL_MODE_PROFILE,
                );
                let mut k: u32 = 0;
                loop {
                    if k >= s {
                        break;
                    }
                    out.append(
                        NoteEvent {
                            time: time_base + k * sub_dur,
                            duration: sub_dur,
                            pitch: realize_degree(octave, *fill.at(k), *canon.tonic_keynum, mode),
                            velocity: DEFAULT_VELOCITY,
                            voice_id: v.voice_id,
                        },
                    );
                    k += 1;
                };
            } else {
                out.append(
                    NoteEvent {
                        time: time_base,
                        duration: unit,
                        pitch: realize_degree(octave, from_deg, *canon.tonic_keynum, mode),
                        velocity: DEFAULT_VELOCITY,
                        voice_id: v.voice_id,
                    },
                );
            }
            p += 1;
        };
        vi += 1;
    };
    out
}

/// Look up a voice's entry delay (structural beats) by `voice_id`.
fn voice_entry_by_id(voices: Span<CanonVoice>, voice_id: u32) -> u32 {
    let mut i: u32 = 0;
    loop {
        if i >= voices.len() {
            break;
        }
        let v = *voices.at(i);
        if v.voice_id == voice_id {
            return v.entry;
        }
        i += 1;
    };
    0_u32
}

/// Remap ornamented canon events through an offset-sine timing wave. Wave sample and beat
/// duration come from the **leader structural beat**; onset is `struct_cum[entry] +
/// struct_cum[struct_beat]` so entry lag and per-position tempo stay consistent for all voices.
pub fn remap_events_with_timing_wave(
    events: Span<NoteEvent>, wave: Span<u32>, unit: u32, voices: Span<CanonVoice>,
) -> Array<NoteEvent> {
    let struct_cum = struct_beat_starts(wave, unit);
    let cum_len = struct_cum.len();
    let wave_len = wave.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        let entry = voice_entry_by_id(voices, e.voice_id);
        let abs_beat = e.time / unit;
        let offset_in_beat = e.time % unit;
        let struct_beat = if abs_beat >= entry {
            abs_beat - entry
        } else {
            0_u32
        };
        let widx = if struct_beat < wave_len {
            struct_beat
        } else if wave_len == 0 {
            0_u32
        } else {
            wave_len - 1
        };
        let wave_val = *wave.at(widx);
        let entry_idx = if entry < cum_len {
            entry
        } else if cum_len == 0 {
            0_u32
        } else {
            cum_len - 1
        };
        let struct_idx = if struct_beat < cum_len {
            struct_beat
        } else if cum_len == 0 {
            0_u32
        } else {
            cum_len - 1
        };
        let beat_start = *struct_cum.at(entry_idx) + *struct_cum.at(struct_idx);
        let beat_dur_scaled = scale_duration_by_wave(unit, wave_val);
        // Subdivisions must fit inside the scaled beat (s * scale(sub) can exceed scale(unit)
        // when the wave is fast, collapsing offsets via per-sub scaling → stacked notes).
        let num_subs = if e.duration > 0 && unit >= e.duration && unit % e.duration == 0 {
            unit / e.duration
        } else {
            1_u32
        };
        let sub_index = if e.duration > 0 && offset_in_beat >= e.duration {
            offset_in_beat / e.duration
        } else {
            0_u32
        };
        let (offset_scaled, duration_scaled) = if num_subs <= 1 {
            (0_u32, beat_dur_scaled)
        } else if beat_dur_scaled >= num_subs {
            let start = sub_index * beat_dur_scaled / num_subs;
            let end = (sub_index + 1) * beat_dur_scaled / num_subs;
            let dur = if end > start {
                end - start
            } else {
                0_u32
            };
            (start, dur)
        } else if sub_index < beat_dur_scaled {
            (sub_index, 1_u32)
        } else {
            (0_u32, 0_u32)
        };
        if duration_scaled > 0 {
            out.append(
                NoteEvent {
                    time: beat_start + offset_scaled,
                    duration: duration_scaled,
                    pitch: e.pitch,
                    velocity: e.velocity,
                    voice_id: e.voice_id,
                },
            );
        }
        i += 1;
    };
    enforce_monophonic_legato(out.span())
}

/// Earliest onset in `events` after index `i` for the same voice (None if none).
/// Uses strict `>` so simultaneous onsets are handled by `enforce_monophonic_legato`.
fn next_onset_same_voice(events: Span<NoteEvent>, i: u32) -> Option<u32> {
    let n = events.len();
    if i >= n {
        return Option::None;
    }
    let e = *events.at(i);
    let mut j: u32 = 0;
    let mut best: Option<u32> = Option::None;
    loop {
        if j >= n {
            break;
        }
        if j != i {
            let o = *events.at(j);
            if o.voice_id == e.voice_id && o.time > e.time {
                match best {
                    Option::Some(t) => {
                        if o.time < t {
                            best = Option::Some(o.time);
                        }
                    },
                    Option::None => {
                        best = Option::Some(o.time);
                    },
                }
            }
        }
        j += 1;
    };
    best
}

/// Clip each note so it does not extend past the next onset in the same voice (monophonic legato).
/// Drops zero-duration tails and skips notes that share an onset with an earlier same-voice event.
pub fn enforce_monophonic_legato(events: Span<NoteEvent>) -> Array<NoteEvent> {
    let n = events.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let e = *events.at(i);
        // Same-voice duplicate onset: keep the first event in array order only.
        let mut dup_onset = false;
        let mut j: u32 = 0;
        loop {
            if j >= i {
                break;
            }
            let prior = *events.at(j);
            if prior.voice_id == e.voice_id && prior.time == e.time {
                dup_onset = true;
                break;
            }
            j += 1;
        };
        if dup_onset {
            i += 1;
            continue;
        }
        let mut dur = e.duration;
        match next_onset_same_voice(events, i) {
            Option::Some(next_time) => {
                if next_time > e.time {
                    let gap = next_time - e.time;
                    if dur > gap {
                        dur = gap;
                    }
                }
            },
            Option::None => {},
        }
        if dur == 0 {
            i += 1;
            continue;
        }
        out.append(
            NoteEvent {
                time: e.time,
                duration: dur,
                pitch: e.pitch,
                velocity: e.velocity,
                voice_id: e.voice_id,
            },
        );
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Mensuration (proportion) canon — voices at different speeds
// ──────────────────────────────────────────────────────────
// The lag-difference identity assumes followers are *same-speed* delayed transpositions, so an
// augmented voice's verticals are no longer determined by a single leader span — the by-construction
// alphabet does not cover them. The honest contract: emit the multi-speed frame, and *validate* the
// result with `mensuration_clash_free`. Under a profile that rejects nothing (e.g. Ligeti-white,
// where every diatonic class is within budget) the validator passes unconditionally, so a diatonic
// mensuration canon is clash-free by construction there; under a stricter profile it is a check.

/// Emit a mensuration canon as `NoteEvent`s: each voice plays the same structural leader degrees,
/// transposed by its `offset`, but stretched so each structural note spans `dilation` time units and
/// the voice starts after `entry` units. One note per structural degree (no ornament subdivision).
pub fn canon_to_mensuration_note_events(canon: @MelodicCanon) -> Array<NoteEvent> {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let octave = *canon.octave;
    let mode = *canon.mode_id;
    let unit = *canon.time_unit;
    let len = degs.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let v = *voices.at(vi);
        let note_dur = unit * v.dilation;
        let mut p: u32 = 0;
        loop {
            if p >= len {
                break;
            }
            let deg = *degs.at(p) + v.offset;
            out.append(
                NoteEvent {
                    time: v.entry * unit + p * note_dur,
                    duration: note_dur,
                    pitch: realize_degree(octave, deg, *canon.tonic_keynum, mode),
                    velocity: DEFAULT_VELOCITY,
                    voice_id: v.voice_id,
                },
            );
            p += 1;
        };
        vi += 1;
    };
    out
}

/// The structural degree voice `v` sounds at absolute unit-time `t` (or `None` if it has not entered
/// or has already finished). Voice-local time is `t - entry`; the sounding note index is that scaled
/// down by the dilation.
fn voice_degree_at(v: CanonVoice, degs: Span<i32>, t: u32) -> Option<i32> {
    if t < v.entry {
        return Option::None;
    }
    let local = t - v.entry;
    let idx = local / v.dilation;
    if idx >= degs.len() {
        return Option::None;
    }
    Option::Some(*degs.at(idx) + v.offset)
}

/// Time-sampled clash check for a mensuration canon: over a unit grid spanning the whole texture,
/// every simultaneously-sounding voice pair must be an acceptable vertical under `profile`. This is
/// the mensuration analogue of `all_pairs_clash_free` (which assumes uniform speed and so indexes
/// degrees directly). Returns true iff no sampled pair exceeds the profile's tension budget.
pub fn mensuration_clash_free(canon: @MelodicCanon, profile: @AestheticProfile) -> bool {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let len = degs.len();
    let nv = voices.len();
    // total note-grid span = max over voices of entry + len*dilation
    let mut total: u32 = 0;
    let mut vi: u32 = 0;
    loop {
        if vi >= nv {
            break;
        }
        let v = *voices.at(vi);
        let end = v.entry + len * v.dilation;
        if end > total {
            total = end;
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
                match voice_degree_at(va, degs, t) {
                    Option::Some(da) => {
                        match voice_degree_at(vb, degs, t) {
                            Option::Some(db) => {
                                if !vertical_ok(profile, da, db) {
                                    ok = false;
                                }
                            },
                            Option::None => {},
                        }
                    },
                    Option::None => {},
                }
                b += 1;
            };
            a += 1;
        };
        t += 1;
    };
    ok
}

// ──────────────────────────────────────────────────────────
// Generator pipeline
// ──────────────────────────────────────────────────────────

fn build_voices(offsets: Span<i32>) -> Array<CanonVoice> {
    let mut out: Array<CanonVoice> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= offsets.len() {
            break;
        }
        out.append(
            CanonVoice {
                voice_id: i, offset: *offsets.at(i), entry: i, is_leader: i == 0, dilation: 1,
            },
        );
        i += 1;
    };
    out
}

/// Build voices for a mensuration canon: each voice has an explicit entry delay and time dilation
/// (`dilations[j]` units per structural note). The leader is voice 0 (`is_leader` true iff
/// `entries[j] == 0 && dilations[j] == 1`). All three spans must be the same length.
pub fn build_mensuration_voices(
    offsets: Span<i32>, entries: Span<u32>, dilations: Span<u32>,
) -> Array<CanonVoice> {
    let mut out: Array<CanonVoice> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= offsets.len() {
            break;
        }
        out.append(
            CanonVoice {
                voice_id: i,
                offset: *offsets.at(i),
                entry: *entries.at(i),
                is_leader: i == 0,
                dilation: *dilations.at(i),
            },
        );
        i += 1;
    };
    out
}

/// Plan rhythmic subdivisions for each leader melodic interval (Montanos level b/c).
/// Returns `len − 1` values in `{1, 2, 4}`. Policy depends on [`ornament_fill_mode_for_profile`]:
/// structural-only profiles always use 1; material/min-step profiles subdivide leaps only.
pub fn plan_ornament_subdivisions_for_profile(
    profile_id: u32, seed_state: u32, steps: Span<i32>, cadence_plain: u32,
) -> Array<u32> {
    if profile_ornament_structural_only(profile_id) {
        let n = steps.len();
        let mut out: Array<u32> = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            out.append(1_u32);
            i += 1;
        };
        out
    } else {
        plan_ornament_subdivisions_policy(
            profile_id, seed_state, steps, cadence_plain,
        )
    }
}

/// Ornament subdivision planner with profile-aware density (fewer fills on small motions).
pub fn plan_ornament_subdivisions_policy(
    profile_id: u32, seed_state: u32, steps: Span<i32>, cadence_plain: u32,
) -> Array<u32> {
    let min_leap = min_step_for_ornament_subdivide(profile_id);
    let n = steps.len();
    let mut out: Array<u32> = ArrayTrait::new();
    let mut rng = LCG { state: seed_state, multiplier: 5, increment: 3, modulus: 256 };
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let step = *steps.at(i);
        let in_cadence = i + cadence_plain >= n;
        let abs_step: u32 = abs_i32(step).try_into().unwrap();
        if in_cadence || step == 0 || abs_step < min_leap {
            out.append(1_u32);
        } else {
            let (raw, next) = rng.draw();
            rng = next;
            let r = bounded(raw, 100);
            let s = if abs_step >= 5 && r < 35 {
                4_u32
            } else if abs_step >= min_leap && r < 50 {
                2_u32
            } else {
                1_u32
            };
            out.append(s);
        }
        i += 1;
    };
    out
}

pub fn plan_ornament_subdivisions(
    seed_state: u32, steps: Span<i32>, cadence_plain: u32,
) -> Array<u32> {
    let n = steps.len();
    let mut out: Array<u32> = ArrayTrait::new();
    let mut rng = LCG { state: seed_state, multiplier: 5, increment: 3, modulus: 256 };
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let step = *steps.at(i);
        let in_cadence = i + cadence_plain >= n;
        if in_cadence || step == 0 {
            out.append(1_u32);
        } else {
            let (raw, next) = rng.draw();
            rng = next;
            let r = bounded(raw, 100);
            let s = if abs_i32(step) >= 3 && r < 45 {
                4_u32
            } else if abs_i32(step) >= 1 && r < 70 {
                2_u32
            } else {
                1_u32
            };
            out.append(s);
        }
        i += 1;
    };
    out
}

/// Build a melodic canon with explicit config and length. `time_unit` is fixed at 4 so
/// ornament subdivisions of 2 and 4 divide evenly.
pub fn generate_melodic_canon_with_params(
    seed: felt252, config_id: u32, length: u32,
) -> MelodicCanon {
    let s: u256 = seed.into();
    let config = config_by_id(config_id);
    let mode_id: u8 = (extract_bits(s, 7, 3) % num_modes()).try_into().unwrap();
    let len = if length >= MIN_LEN {
        length
    } else {
        MIN_LEN
    };
    let time_unit: u32 = 4;
    let mut seed_state = extract_bits(s, 19, 8) % 256;
    if seed_state == 0 {
        seed_state = 7;
    }

    let offsets = config.offsets;
    let (degrees, steps) = walk_leader(seed_state, @config, len, true);
    let voices = build_voices(offsets);

    let canon = MelodicCanon {
        config_id: config.config_id,
        config_name: config.name,
        offsets,
        leader_degrees: degrees.span(),
        leader_steps: steps.span(),
        mode_id,
        tonic_keynum: 65,
        time_unit,
        voices: voices.span(),
        octave: 7,
        profile_id: 0,
    };

    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_consonant(@canon), 'canon not consonant');
    if offsets.len() == 2 {
        assert(cadence_lands_on_final(@canon), 'cadence not resolved');
    }
    canon
}

/// Generate a long canon plus its ornament subdivision plan (deterministic from seed).
pub fn generate_ornamented_canon(
    seed: felt252, config_id: u32, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let canon = generate_melodic_canon_with_params(seed, config_id, length);
    let mut orn_seed = extract_bits(seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions(orn_seed, canon.leader_steps, CADENCE_LEN);
    (canon, subs)
}

/// Generate a long *profiled* canon (any aesthetic, diatonic or chromatic) plus its ornament
/// subdivision plan (Montanos "divided" style). Deterministic from seed. The followers imitate the
/// ornamented leader, so the canon stays clash-free on the structural frame by construction.
pub fn generate_profiled_ornamented_canon(
    seed: felt252, config_id: u32, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let canon = generate_canon_with_config_length(seed, profiled_config_by_id(config_id), length);
    let mut orn_seed = extract_bits(seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions_for_profile(
        canon.profile_id, orn_seed, canon.leader_steps, CADENCE_LEN,
    );
    (canon, subs)
}

/// Dense Montanos-style subdivisions: subdivide most motions with |step| ≥ 2 (for long ornamented
/// exports). Fill still uses the caller's fill mode (e.g. `ORN_FILL_MIN_STEP` for jazz improv).
pub fn plan_ornament_subdivisions_dense(
    seed_state: u32, steps: Span<i32>, cadence_plain: u32,
) -> Array<u32> {
    let min_leap: u32 = 2;
    let n = steps.len();
    let mut out: Array<u32> = ArrayTrait::new();
    let mut rng = LCG { state: seed_state, multiplier: 5, increment: 3, modulus: 256 };
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let step = *steps.at(i);
        let in_cadence = i + cadence_plain >= n;
        let abs_step: u32 = abs_i32(step).try_into().unwrap();
        if in_cadence || step == 0 || abs_step < min_leap {
            out.append(1_u32);
        } else {
            let (raw, next) = rng.draw();
            rng = next;
            let r = bounded(raw, 100);
            let s = if abs_step >= 4 && r < 60 {
                4_u32
            } else if abs_step >= min_leap && r < 88 {
                2_u32
            } else {
                1_u32
            };
            out.append(s);
        }
        i += 1;
    };
    out
}

/// Light Montanos-style subdivisions: occasional splits on |step| ≥ 3 only (for jazz demos that
/// should stay closer to structural rhythm than [`plan_ornament_subdivisions_dense`]).
pub fn plan_ornament_subdivisions_light(
    seed_state: u32, steps: Span<i32>, cadence_plain: u32,
) -> Array<u32> {
    let min_leap: u32 = 3;
    let n = steps.len();
    let mut out: Array<u32> = ArrayTrait::new();
    let mut rng = LCG { state: seed_state, multiplier: 5, increment: 3, modulus: 256 };
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let step = *steps.at(i);
        let in_cadence = i + cadence_plain >= n;
        let abs_step: u32 = abs_i32(step).try_into().unwrap();
        if in_cadence || step == 0 || abs_step < min_leap {
            out.append(1_u32);
        } else {
            let (raw, next) = rng.draw();
            rng = next;
            let r = bounded(raw, 100);
            let s = if abs_step >= 5 && r < 10 {
                4_u32
            } else if abs_step >= min_leap && r < 28 {
                2_u32
            } else {
                1_u32
            };
            out.append(s);
        }
        i += 1;
    };
    out
}

/// Ornamented note events with an explicit fill mode (see `melodic_motion` constants).
pub fn canon_to_ornamented_note_events_with_fill(
    canon: @MelodicCanon, subdivisions: Span<u32>, fill_mode: u8,
) -> Array<NoteEvent> {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let octave = *canon.octave;
    let mode = *canon.mode_id;
    let unit = *canon.time_unit;
    let len = degs.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let v = *voices.at(vi);
        let mut p: u32 = 0;
        loop {
            if p >= len {
                break;
            }
            let from_deg = *degs.at(p) + v.offset;
            let time_base = (p + v.entry) * unit;
            if p + 1 < len {
                let to_deg = *degs.at(p + 1) + v.offset;
                let mut s = *subdivisions.at(p);
                if s == 0 {
                    s = 1;
                }
                if unit % s != 0 {
                    s = 1;
                }
                let sub_dur = unit / s;
                let fill = subdivide_for_fill_mode(
                    from_deg, to_deg, s, *canon.profile_id, fill_mode,
                );
                let mut k: u32 = 0;
                loop {
                    if k >= s {
                        break;
                    }
                    out.append(
                        NoteEvent {
                            time: time_base + k * sub_dur,
                            duration: sub_dur,
                            pitch: realize_degree(octave, *fill.at(k), *canon.tonic_keynum, mode),
                            velocity: DEFAULT_VELOCITY,
                            voice_id: v.voice_id,
                        },
                    );
                    k += 1;
                };
            } else {
                out.append(
                    NoteEvent {
                        time: time_base,
                        duration: unit,
                        pitch: realize_degree(octave, from_deg, *canon.tonic_keynum, mode),
                        velocity: DEFAULT_VELOCITY,
                        voice_id: v.voice_id,
                    },
                );
            }
            p += 1;
        };
        vi += 1;
    };
    out
}

/// Jazz improvised canon (profile 24) with dense rhythmic subdivisions and min-step ornament fill
/// (no chromatic semitone chains). Turnaround harmony from `jazz_harmony.cairo`.
pub fn generate_jazz_improv_ornamented_canon(
    seed: felt252, config_id: u32, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let canon = generate_canon_with_config_length(seed, profiled_config_by_id(config_id), length);
    assert(canon.profile_id == 24, 'jazz improv profile');
    let mut orn_seed = extract_bits(seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions_dense(orn_seed, canon.leader_steps, CADENCE_LEN);
    (canon, subs)
}

/// Jazz improvised canon with light rhythmic subdivisions (thirds+ only, ~28% duplet rate).
/// Same turnaround / tritone-sub plan as structural generation.
pub fn generate_jazz_improv_ornamented_canon_light(
    seed: felt252, config_id: u32, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let canon = generate_canon_with_config_length(seed, profiled_config_by_id(config_id), length);
    assert(canon.profile_id == 24, 'jazz improv profile');
    let mut orn_seed = extract_bits(seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions_light(orn_seed, canon.leader_steps, CADENCE_LEN);
    (canon, subs)
}

/// Jazz improvised canon with harmonic-walk material gates (seed bit 36) and dense ornament fill.
pub fn generate_jazz_improv_harmonic_walk_ornamented_canon(
    seed: felt252, config_id: u32, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let walk_seed = canon_seed_enable_harmonic_walk(seed);
    assert(harmonic_walk_enabled_from_seed(walk_seed), 'walk bit set');
    let canon = generate_canon_with_config_length(
        walk_seed, profiled_config_by_id(config_id), length,
    );
    assert(canon.profile_id == 24, 'jazz improv profile');
    let mut orn_seed = extract_bits(walk_seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions_dense(orn_seed, canon.leader_steps, CADENCE_LEN);
    (canon, subs)
}

/// Pentatonic open-fifths smooth (profile 22) with dense rhythmic subdivisions and
/// major-pentatonic material fill — more activity than structural-only smooth export, still
/// no chromatic ±1 chains or semitone structural steps.
pub fn generate_pentatonic_smooth_ornamented_canon(
    seed: felt252, config_id: u32, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let canon = generate_canon_with_config_length(seed, profiled_config_by_id(config_id), length);
    assert(canon.profile_id == 22, 'penta smooth profile');
    let mut orn_seed = extract_bits(seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions_dense(orn_seed, canon.leader_steps, CADENCE_LEN);
    (canon, subs)
}

/// Generate a complete, contrapuntally-correct melodic canon from a seed. Deterministic;
/// no search on the structural path.
pub fn generate_melodic_canon(seed: felt252) -> MelodicCanon {
    let s: u256 = seed.into();
    let config_id = extract_bits(s, 0, 4) % num_configs();
    let span = MAX_LEN - MIN_LEN + 1;
    let len = MIN_LEN + (extract_bits(s, 14, 5) % span);
    generate_melodic_canon_with_params(seed, config_id, len)
}

// ──────────────────────────────────────────────────────────
// Profiled generation (any aesthetic, diatonic or chromatic) — correct by construction
// ──────────────────────────────────────────────────────────

/// Generate a canon under any profiled config, judged by the config's aesthetic profile.
/// Deterministic; no search on the structural path. The same walker/validators serve every
/// profile — only the profile value differs.
pub fn generate_canon_with_config(seed: felt252, config: CanonConfig) -> MelodicCanon {
    let s: u256 = seed.into();
    let span = MAX_LEN - MIN_LEN + 1;
    let len = MIN_LEN + (extract_bits(s, 14, 5) % span);
    generate_canon_with_config_length(seed, config, len)
}

/// As `generate_canon_with_config`, but with an explicit structural length (for long pieces).
/// `length` is clamped to at least `MIN_LEN`.
pub fn generate_canon_with_config_length(
    seed: felt252, config: CanonConfig, length: u32,
) -> MelodicCanon {
    let s: u256 = seed.into();
    let profile = profile_by_id(config.profile_id);
    let len = if length >= MIN_LEN {
        length
    } else {
        MIN_LEN
    };
    let mut seed_state = extract_bits(s, 19, 8) % 256;
    if seed_state == 0 {
        seed_state = 7;
    }
    let turnaround_plan = if config.profile_id == 24 {
        turnaround_plan_from_canon_seed(seed)
    } else {
        turnaround_plan_default()
    };
    let offsets = config.offsets;
    let (degrees, steps) = walk_leader_profiled(
        seed, seed_state, offsets, @profile, len, true, turnaround_plan,
    );
    let voices = build_voices(offsets);
    let chromatic = config.octave == 12;
    let tonic: u8 = if chromatic {
        60
    } else {
        65
    };
    let mode_id: u8 = if chromatic {
        0
    } else {
        (extract_bits(s, 7, 3) % num_modes()).try_into().unwrap()
    };

    let canon = MelodicCanon {
        config_id: config.config_id,
        config_name: config.name,
        offsets,
        leader_degrees: degrees.span(),
        leader_steps: steps.span(),
        mode_id,
        tonic_keynum: tonic,
        time_unit: 4,
        voices: voices.span(),
        octave: config.octave,
        profile_id: config.profile_id,
    };
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_clash_free(@canon, @profile), 'canon has a clash');
    canon
}

/// Generate a profiled canon by stable config id (diatonic 0..6, chromatic 7..10).
pub fn generate_profiled_canon(seed: felt252, config_id: u32) -> MelodicCanon {
    generate_canon_with_config(seed, profiled_config_by_id(config_id))
}

/// Major-seventh-chord stacked real canon (jazz profile). Separately accessible; no conflict.
pub fn generate_maj7_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 7)
}

/// Minor-seventh-chord stacked real canon (jazz profile).
pub fn generate_min7_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 8)
}

/// Dominant-seventh planing canon (impressionist profile, parallels allowed).
pub fn generate_planing_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 9)
}

/// Quartal stacked canon (Persichetti profile, P4/P5 stable).
pub fn generate_quartal_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 10)
}

/// Dominant-ninth planing canon (larger color block than dom7 planing).
pub fn generate_dom9_planing_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 16)
}

/// Lydian major-ninth / sharp-eleven color canon.
pub fn generate_lydian_maj9_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 17)
}

/// Dominant altered canon with b9 color admitted by profile.
pub fn generate_dominant_altered_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 18)
}

/// Whole-tone planing canon.
pub fn generate_whole_tone_planing_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 19)
}

/// Octatonic axis canon.
pub fn generate_octatonic_axis_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 20)
}

/// Suspended quartal canon.
pub fn generate_sus_quartal_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 21)
}

/// Minimalist pandiatonic canon.
pub fn generate_pandiatonic_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 22)
}

/// Spectral-series color canon.
pub fn generate_spectral_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 23)
}

/// Bartok axis canon.
pub fn generate_bartok_axis_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 24)
}

/// Soft chromatic-cluster canon.
pub fn generate_cluster_soft_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 25)
}

/// Canon per tonos: a real-answer, intentionally modulating maj7 canon.
pub fn generate_canon_per_tonos(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 26)
}

/// Impressionist added-sixth canon (root/M3/P5/M6 color, parallels allowed).
pub fn generate_impressionist_added6_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 27)
}

/// Bitonal split-field canon (two major-third dyads a tritone apart).
pub fn generate_bitonal_split_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 28)
}

/// Phrygian-cadential canon (b2 semitone gravity admitted as color).
pub fn generate_phrygian_cadential_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 29)
}

/// Pentatonic open-fifths canon (stacked perfect fifths, no semitone/tritone friction).
pub fn generate_pentatonic_open_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 30)
}

/// Neo-Riemannian triadic canon (major-triad voice-leading).
pub fn generate_neo_riemannian_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 31)
}

/// Pentatonic open-fifths canon without semitone melodic steps or chromatic ornament fill.
pub fn generate_pentatonic_open_smooth_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 39)
}

/// Impressionist add6/9 canon without semitone melodic steps or chromatic ornament fill.
pub fn generate_impressionist_added6_smooth_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 37)
}

/// Jazz improvised canon: I–vi–ii–V turnaround filtering, no semitone structural steps.
pub fn generate_jazz_improv_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 41)
}

/// Three-voice jazz improvised canon (root, M3, P5).
pub fn generate_jazz_improv_3v_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 42)
}

// ──────────────────────────────────────────────────────────
// Ligeti micropolyphony generators
// ──────────────────────────────────────────────────────────

/// White-key tonic for each diatonic mode, so the realization lands *entirely on the white keys*
/// (the literal "white on white" property) while preserving the seed's modal variety. Ionian→C,
/// Dorian→D, Phrygian→E, Lydian→F, Mixolydian→G, Aeolian→A — each mode's scale degrees, rooted on
/// its matching white key, reproduce exactly {C,D,E,F,G,A,B}. (The generic diatonic path roots on
/// F for every mode, so F Ionian/Dorian/… introduce B♭ and other accidentals — not what a white-key
/// étude wants.)
pub fn white_key_tonic(mode_id: u8) -> u8 {
    let m = mode_id % 6;
    if m == 0 {
        60 // C Ionian
    } else if m == 1 {
        62 // D Dorian
    } else if m == 2 {
        64 // E Phrygian
    } else if m == 3 {
        65 // F Lydian
    } else if m == 4 {
        67 // G Mixolydian
    } else {
        69 // A Aeolian
    }
}

/// Shared builder for the diatonic Ligeti canons: same machinery as `generate_canon_with_config_length`
/// but realized on the white-key collection (`white_key_tonic`) so every sounding pitch is a white
/// note. Clash-free by construction under the config's (Ligeti-white) profile.
fn generate_ligeti_diatonic(seed: felt252, config: CanonConfig, length: u32) -> MelodicCanon {
    let s: u256 = seed.into();
    let profile = profile_by_id(config.profile_id);
    let len = if length >= MIN_LEN {
        length
    } else {
        MIN_LEN
    };
    let mut seed_state = extract_bits(s, 19, 8) % 256;
    if seed_state == 0 {
        seed_state = 7;
    }
    let offsets = config.offsets;
    let (degrees, steps) = walk_leader_profiled(
        seed, seed_state, offsets, @profile, len, true, turnaround_plan_default(),
    );
    let voices = build_voices(offsets);
    let mode_id: u8 = (extract_bits(s, 7, 3) % num_modes()).try_into().unwrap();
    let canon = MelodicCanon {
        config_id: config.config_id,
        config_name: config.name,
        offsets,
        leader_degrees: degrees.span(),
        leader_steps: steps.span(),
        mode_id,
        tonic_keynum: white_key_tonic(mode_id),
        time_unit: 4,
        voices: voices.span(),
        octave: 7,
        profile_id: config.profile_id,
    };
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_clash_free(@canon, @profile), 'canon has a clash');
    canon
}

/// Ligeti "White on White": the slow two-voice octave canon, realized entirely on the white keys.
pub fn generate_ligeti_white_canon(seed: felt252) -> MelodicCanon {
    let s: u256 = seed.into();
    let span = MAX_LEN - MIN_LEN + 1;
    let len = MIN_LEN + (extract_bits(s, 14, 5) % span);
    generate_ligeti_diatonic(seed, config_white_on_white(), len)
}

/// Ligeti diatonic cluster: a four-voice stacked-second canon (white-key cluster band).
pub fn generate_ligeti_cluster_canon(seed: felt252) -> MelodicCanon {
    let s: u256 = seed.into();
    let span = MAX_LEN - MIN_LEN + 1;
    let len = MIN_LEN + (extract_bits(s, 14, 5) % span);
    generate_ligeti_diatonic(seed, config_ligeti_cluster(), len)
}

/// Ligeti chromatic micropolyphony: a three-voice stacked-semitone cluster band (Lux Aeterna).
/// `no_minor_ninth` is intentionally false here; clash-freedom is asserted under the cluster profile.
pub fn generate_ligeti_micro_canon(seed: felt252) -> MelodicCanon {
    generate_profiled_canon(seed, 15)
}

/// Ligeti diatonic cluster with a *gliding register band*: the canonic cluster band slides up the
/// register across the piece (micropolyphony's signature "moving band"). Deterministic from seed;
/// clash-free by construction under the Ligeti-white profile (which rejects nothing diatonic).
pub fn generate_ligeti_banded_canon(seed: felt252, length: u32) -> MelodicCanon {
    let config = config_ligeti_cluster();
    let profile = profile_ligeti_white();
    let len = if length >= MIN_LEN {
        length
    } else {
        MIN_LEN
    };
    let s: u256 = seed.into();
    let mut seed_state = extract_bits(s, 19, 8) % 256;
    if seed_state == 0 {
        seed_state = 7;
    }
    // glide the band center from low to high; half-width keeps the cluster within a singable strip.
    let env = BandEnvelope { center_start: -3, center_end: 3, half_width: 3 };
    let offsets = config.offsets;
    let (degrees, steps) = walk_leader_banded(
        seed,
        seed_state,
        offsets,
        @profile,
        len,
        false,
        env,
        turnaround_plan_default(),
    );
    let voices = build_voices(offsets);
    let mode_id: u8 = (extract_bits(s, 7, 3) % num_modes()).try_into().unwrap();
    let canon = MelodicCanon {
        config_id: config.config_id,
        config_name: config.name,
        offsets,
        leader_degrees: degrees.span(),
        leader_steps: steps.span(),
        mode_id,
        tonic_keynum: white_key_tonic(mode_id),
        time_unit: 4,
        voices: voices.span(),
        octave: 7,
        profile_id: 5,
    };
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_clash_free(@canon, @profile), 'canon has a clash');
    canon
}

/// Ligeti diatonic *mensuration* canon: a two-voice octave-below canon whose follower is in 2:1
/// augmentation (twice as slow), the two voices starting together (a prolation canon). The
/// structural leader is a permissive diatonic walk; the multi-speed frame is validated, not derived
/// — but under the Ligeti-white profile (which rejects nothing) `mensuration_clash_free` holds by
/// construction. Render with `canon_to_mensuration_note_events`.
pub fn generate_ligeti_mensuration_canon(seed: felt252, length: u32) -> MelodicCanon {
    let profile = profile_ligeti_white();
    let len = if length >= MIN_LEN {
        length
    } else {
        MIN_LEN
    };
    let s: u256 = seed.into();
    let mut seed_state = extract_bits(s, 19, 8) % 256;
    if seed_state == 0 {
        seed_state = 7;
    }
    let offsets = array![0_i32, -7].span(); // follower an octave below
    let (degrees, steps) = walk_leader_profiled(
        seed, seed_state, offsets, @profile, len, false, turnaround_plan_default(),
    );
    let entries = array![0_u32, 0].span(); // start together (prolation)
    let dilations = array![1_u32, 2].span(); // follower augmented 2:1
    let voices = build_mensuration_voices(offsets, entries, dilations);
    let mode_id: u8 = (extract_bits(s, 7, 3) % num_modes()).try_into().unwrap();
    let canon = MelodicCanon {
        config_id: 13,
        config_name: 'white_mensuration',
        offsets,
        leader_degrees: degrees.span(),
        leader_steps: steps.span(),
        mode_id,
        tonic_keynum: white_key_tonic(mode_id),
        time_unit: 4,
        voices: voices.span(),
        octave: 7,
        profile_id: 5,
    };
    assert(exact_imitation(@canon), 'imitation broken');
    assert(mensuration_clash_free(@canon, @profile), 'mensuration has a clash');
    canon
}

pub fn canon_traits(canon: @MelodicCanon) -> MelodicCanonTraits {
    let profile = profile_by_id(*canon.profile_id);
    let alphabet = allowed_steps_multivoice_p(@profile, *canon.offsets);
    let interval = if (*canon.offsets).len() > 1 {
        *(*canon.offsets).at(1)
    } else {
        0
    };
    MelodicCanonTraits {
        config_id: *canon.config_id,
        profile_id: *canon.profile_id,
        profile_name: profile.name,
        voice_count: (*canon.voices).len(),
        interval_of_imitation: interval,
        mode_id: *canon.mode_id,
        octave: *canon.octave,
        length: (*canon.leader_degrees).len(),
        time_unit: *canon.time_unit,
        melodic_alphabet_size: alphabet.len(),
        max_tier_used: max_vertical_tier_used(canon, @profile),
        contains_minor_second: !no_minor_ninth(canon),
        chord_quality: chord_quality_name(*canon.config_id),
    }
}

pub fn chord_quality_name(config_id: u32) -> felt252 {
    if config_id == 7 {
        'maj7'
    } else if config_id == 8 {
        'min7'
    } else if config_id == 9 {
        'dom7'
    } else if config_id == 10 || config_id == 11 {
        'quartal'
    } else if config_id == 12 {
        'hindemith'
    } else if config_id == 13 {
        'white_octave'
    } else if config_id == 14 {
        'white_cluster'
    } else if config_id == 15 {
        'micro_cluster'
    } else if config_id == 16 {
        'dom9'
    } else if config_id == 17 {
        'lydian_maj9'
    } else if config_id == 18 {
        'dom_alt_b9'
    } else if config_id == 19 {
        'whole_tone'
    } else if config_id == 20 {
        'octatonic'
    } else if config_id == 21 {
        'sus_quartal'
    } else if config_id == 22 {
        'pandiatonic'
    } else if config_id == 23 {
        'spectral'
    } else if config_id == 24 {
        'bartok_axis'
    } else if config_id == 25 {
        'cluster_soft'
    } else if config_id == 26 {
        'per_tonos'
    } else if config_id == 27 {
        'impr_add69'
    } else if config_id == 28 {
        'bitonal'
    } else if config_id == 29 {
        'phrygian'
    } else if config_id == 30 {
        'penta_open'
    } else if config_id == 31 {
        'neo_riem'
    } else if config_id == 32 {
        'impr_add69_3'
    } else if config_id == 33 {
        'bitonal_3'
    } else if config_id == 34 {
        'phrygian_3'
    } else if config_id == 35 {
        'penta_open_3'
    } else if config_id == 36 {
        'neo_riem_4'
    } else if config_id == 37 {
        'impr_smooth'
    } else if config_id == 38 {
        'impr_smooth_3'
    } else if config_id == 39 {
        'penta_smooth'
    } else if config_id == 40 {
        'penta_smooth_3'
    } else if config_id == 41 {
        'jazz_improv'
    } else if config_id == 42 {
        'jazz_improv_3'
    } else {
        'renaissance'
    }
}

/// Build a validated canon from an external leader degree sequence (offline fitter ingress).
/// Uses `profiled_config_by_id` (all profiled configs). Asserts imitation + profile-aware consonance.
pub fn assemble_canon_from_leader(
    config_id: u32,
    mode_id: u8,
    tonic_keynum: u8,
    octave: u32,
    leader_degrees: Span<i32>,
) -> MelodicCanon {
    let config = profiled_config_by_id(config_id);
    let base = build_canon_for_test(
        config.config_id, config.name, config.offsets, leader_degrees, mode_id,
    );
    let profile = profile_by_id(config.profile_id);
    let canon = MelodicCanon {
        config_id: base.config_id,
        config_name: base.config_name,
        offsets: base.offsets,
        leader_degrees: base.leader_degrees,
        leader_steps: base.leader_steps,
        mode_id: base.mode_id,
        tonic_keynum,
        time_unit: base.time_unit,
        voices: base.voices,
        octave,
        profile_id: config.profile_id,
    };
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_clash_free(@canon, @profile), 'canon not consonant');
    canon
}

/// Build a `MelodicCanon` directly from explicit leader degrees and voice offsets — for tests
/// and for callers that supply their own cantus. Does not assert correctness (callers validate).
pub fn build_canon_for_test(
    config_id: u32, name: felt252, offsets: Span<i32>, degrees: Span<i32>, mode_id: u8,
) -> MelodicCanon {
    // recompute steps from degrees
    let mut steps: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 1;
    loop {
        if i >= degrees.len() {
            break;
        }
        steps.append(*degrees.at(i) - *degrees.at(i - 1));
        i += 1;
    };
    let voices = build_voices(offsets);
    MelodicCanon {
        config_id,
        config_name: name,
        offsets,
        leader_degrees: degrees,
        leader_steps: steps.span(),
        mode_id,
        tonic_keynum: 65,
        time_unit: 4,
        voices: voices.span(),
        octave: 7,
        profile_id: 0,
    }
}

// ──────────────────────────────────────────────────────────
// Ornamentation: divisions / passing tones (Montanos "b", Morley "divided")
// ──────────────────────────────────────────────────────────

/// Route ornament fill through a fill mode (`FILL_MODE_PROFILE` = use profile default).
pub fn subdivide_for_fill_mode(
    from_deg: i32, to_deg: i32, s: u32, profile_id: u32, fill_mode: u8,
) -> Array<i32> {
    let mode = if fill_mode == FILL_MODE_PROFILE {
        ornament_fill_mode_for_profile(profile_id)
    } else {
        fill_mode
    };
    if mode == ORN_FILL_STRUCTURAL {
        subdivide(from_deg, to_deg, 1)
    } else if mode == ORN_FILL_MATERIAL {
        subdivide_material(from_deg, to_deg, s, profile_id)
    } else if mode == ORN_FILL_MIN_STEP {
        subdivide_min_step(from_deg, to_deg, s, 2)
    } else {
        subdivide(from_deg, to_deg, s)
    }
}

/// Route ornament fill through the profile's motion policy.
pub fn subdivide_for_profile(
    from_deg: i32, to_deg: i32, s: u32, profile_id: u32,
) -> Array<i32> {
    subdivide_for_fill_mode(from_deg, to_deg, s, profile_id, FILL_MODE_PROFILE)
}

/// Fill using steps of at least `min_step` semitones toward `to_deg` (no chromatic ±1 chain).
pub fn subdivide_min_step(from_deg: i32, to_deg: i32, s: u32, min_step: u32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    assert(s >= 1, 'subdiv >= 1');
    if s == 1 {
        out.append(from_deg);
        return out;
    }
    let stride: i32 = min_step.try_into().unwrap();
    let mut cur = from_deg;
    out.append(cur);
    let mut k: u32 = 1;
    loop {
        if k >= s {
            break;
        }
        if k == s - 1 {
            cur = to_deg;
        } else {
            let gap = to_deg - cur;
            let mut step = stride;
            if gap < 0 {
                step = -stride;
            }
            let gap_abs: u32 = abs_i32(gap);
            let stride_u: u32 = stride.try_into().unwrap();
            if gap_abs < stride_u {
                cur = to_deg;
            } else {
                cur += step;
            }
        }
        out.append(cur);
        k += 1;
    };
    out
}

/// Fill by stepping through pitch classes allowed for `profile_id` (no semitone neighbors unless
/// in the profile material).
fn subdivide_material(
    from_deg: i32, to_deg: i32, s: u32, profile_id: u32,
) -> Array<i32> {
    let profile = profile_by_id(profile_id);
    let mut out: Array<i32> = ArrayTrait::new();
    assert(s >= 1, 'subdiv >= 1');
    if s == 1 {
        out.append(from_deg);
        return out;
    }
    let mut cur = from_deg;
    out.append(cur);
    let mut k: u32 = 1;
    loop {
        if k >= s {
            break;
        }
        if k == s - 1 {
            cur = to_deg;
        } else {
            cur = material_step_toward(@profile, cur, to_deg);
        }
        out.append(cur);
        k += 1;
    };
    out
}

/// One material-legal step from `cur` toward `target` (prefers |m| in {2,3,4,5,7,…}).
fn material_step_toward(profile: @AestheticProfile, cur: i32, target: i32) -> i32 {
    let candidates = array![
        7_i32, -7, 5, -5, 4, -4, 3, -3, 2, -2, 1, -1, 0,
    ];
    let mut best = cur;
    let mut best_dist = abs_i32(target - cur);
    let mut i: u32 = 0;
    loop {
        if i >= candidates.len() {
            break;
        }
        let m = *candidates.at(i);
        if abs_i32(m) == 1_u32 && profile_forbids_semitone_melodic_step(*profile.id) {
            i += 1;
            continue;
        }
        let next = cur + m;
        if !profile_material_ok(profile, next) {
            i += 1;
            continue;
        }
        let d = abs_i32(target - next);
        if d < best_dist {
            best = next;
            best_dist = d;
        }
        i += 1;
    };
    best
}

/// Fill the motion from `from_deg` to `to_deg` with `s` notes stepping by ±1 semitone (legacy
/// chromatic passing-tone chain). Prefer [`subdivide_for_profile`] for profile-aware export.
pub fn subdivide(from_deg: i32, to_deg: i32, s: u32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    assert(s >= 1, 'subdiv >= 1');
    if s == 1 {
        out.append(from_deg);
        return out;
    }
    let dir: i32 = if to_deg > from_deg {
        1
    } else if to_deg < from_deg {
        -1
    } else {
        0
    };
    let mut cur = from_deg;
    let mut i: u32 = 0;
    loop {
        if i >= s {
            break;
        }
        out.append(cur);
        // advance toward target without overshooting
        if dir > 0 && cur < to_deg {
            cur += 1;
        } else if dir < 0 && cur > to_deg {
            cur -= 1;
        }
        i += 1;
    };
    out
}

/// Legality of an ornamenting tone against a simultaneously-sounding note (submetric rule):
/// a consonance is always fine; a dissonance is allowed only on a weak subdivision and only when
/// approached by step (a passing/neighbor tone).
pub fn ornament_tone_is_legal(added: i32, against: i32, weak_beat: bool, by_step: bool) -> bool {
    if is_consonant_class(generic_class(added, against)) {
        return true;
    }
    weak_beat && by_step
}

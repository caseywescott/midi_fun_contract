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
use koji::lcg::LCG;
use koji::rng::{RandomSource, bounded};
use koji::composition::canon_rules::{
    CanonConfig, PairConstraint, config_by_index, config_by_id, num_configs, pair_constraints,
    allowed_steps_multivoice, stylistic_multivoice, full_step_range, step_satisfies_constraints,
    generic_class, is_consonant_class, is_perfect_class, contains_i32, abs_i32,
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
}

/// Onchain metadata.
#[derive(Copy, Drop)]
pub struct MelodicCanonTraits {
    pub config_id: u32,
    pub voice_count: u32,
    pub interval_of_imitation: i32,
    pub mode_id: u8,
    pub length: u32,
    pub time_unit: u32,
    pub melodic_alphabet_size: u32,
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

// ──────────────────────────────────────────────────────────
// Leader walk (the cascade of rules)
// ──────────────────────────────────────────────────────────

/// Build the candidate list at the current position: full step range filtered by
/// (a) the register band, (b) all pairwise window constraints, (c) parallel-perfect avoidance.
fn candidates_at(
    constraints: Span<PairConstraint>,
    primary_d: i32,
    degrees: Span<i32>,
    steps: Span<i32>,
    prefer: Span<i32>,
) -> Array<i32> {
    let cur = *degrees.at(degrees.len() - 1);
    let mut prim: Array<i32> = ArrayTrait::new(); // stylistic + valid
    let mut any: Array<i32> = ArrayTrait::new(); // valid at all (fallback)
    let full = full_step_range();
    let mut i: u32 = 0;
    loop {
        if i >= full.len() {
            break;
        }
        let m = *full.at(i);
        i += 1;
        // (a) register band
        let next = cur + m;
        if next > REGISTER_BAND || next < -REGISTER_BAND {
            continue;
        }
        // (b) pairwise constraints (all windows that close here)
        if !step_satisfies_constraints(constraints, steps, m) {
            continue;
        }
        // (c) parallel-perfect: don't repeat a step that yields a perfect interval
        if steps.len() > 0 {
            let prev = *steps.at(steps.len() - 1);
            if m == prev && is_perfect_class(generic_class(primary_d, m)) {
                continue;
            }
        }
        any.append(m);
        if contains_i32(prefer, m) {
            prim.append(m);
        }
    };
    if prim.len() > 0 {
        prim
    } else {
        any
    }
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

/// Walk the leader: `len` structural degrees starting on the modal final (degree 0). When
/// `cadence` is true, the final notes are steered to the modal final to form a proper ending
/// (the "break out of the pattern" the conversation describes), staying within the alphabet so
/// the strict canon remains consonant.
pub fn walk_leader(
    seed_state: u32, config: @CanonConfig, len: u32, cadence: bool,
) -> (Array<i32>, Array<i32>) {
    let constraints = pair_constraints(*config.offsets);
    let prefer = stylistic_multivoice(*config.offsets);
    let primary_d = if (*config.offsets).len() > 1 {
        *(*config.offsets).at(1)
    } else {
        0
    };
    // does the per-step alphabet contain a unison-step (a 2nd) we can cadence by?
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
        let cands = candidates_at(
            constraints.span(), primary_d, degrees.span(), steps.span(), prefer.span(),
        );
        // There is always at least the unison option in practice; assert for safety.
        assert(cands.len() > 0, 'no valid leader step');
        let cur = *degrees.at(degrees.len() - 1);
        let m = if cadence {
            match cadence_target(p, len, primary_d, has_unit_step) {
                Option::Some(t) => pick_toward(cands.span(), cur, t),
                Option::None => {
                    let (raw, next) = rng.draw();
                    rng = next;
                    *cands.at(bounded(raw, cands.len()))
                },
            }
        } else {
            let (raw, next) = rng.draw();
            rng = next;
            *cands.at(bounded(raw, cands.len()))
        };
        degrees.append(cur + m);
        steps.append(m);
        p += 1;
    };
    (degrees, steps)
}

// ──────────────────────────────────────────────────────────
// Validators (assertions, not searches)
// ──────────────────────────────────────────────────────────

/// Every pair of voices is consonant wherever both sound. By the lag-difference identity this
/// MUST hold for a leader restricted to the permitted alphabet; failure indicates a bug.
pub fn all_pairs_consonant(canon: @MelodicCanon) -> bool {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let len = degs.len();
    let nv = voices.len();
    // total structural ticks = len + (max entry)
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
        // for each ordered voice pair, if both sound at t, check consonance
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
                    if !is_consonant_class(generic_class(da, db)) {
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
    let scale = mode_scale(*canon.mode_id);
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
                let fill = subdivide(from_deg, to_deg, s);
                let mut k: u32 = 0;
                loop {
                    if k >= s {
                        break;
                    }
                    out.append(
                        NoteEvent {
                            time: time_base + k * sub_dur,
                            duration: sub_dur,
                            pitch: degree_to_keynum(*fill.at(k), *canon.tonic_keynum, scale),
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
                        pitch: degree_to_keynum(from_deg, *canon.tonic_keynum, scale),
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
                voice_id: i, offset: *offsets.at(i), entry: i, is_leader: i == 0,
            },
        );
        i += 1;
    };
    out
}

/// Plan rhythmic subdivisions for each leader melodic interval (Montanos level b/c).
/// Returns `len − 1` values in `{1, 2, 4}`; cadence tail and repeated notes stay undivided.
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

/// Generate a complete, contrapuntally-correct melodic canon from a seed. Deterministic;
/// no search on the structural path.
pub fn generate_melodic_canon(seed: felt252) -> MelodicCanon {
    let s: u256 = seed.into();
    let config_id = extract_bits(s, 0, 4) % num_configs();
    let span = MAX_LEN - MIN_LEN + 1;
    let len = MIN_LEN + (extract_bits(s, 14, 5) % span);
    generate_melodic_canon_with_params(seed, config_id, len)
}

pub fn canon_traits(canon: @MelodicCanon) -> MelodicCanonTraits {
    let alphabet = allowed_steps_multivoice(*canon.offsets);
    let interval = if (*canon.offsets).len() > 1 {
        *(*canon.offsets).at(1)
    } else {
        0
    };
    MelodicCanonTraits {
        config_id: *canon.config_id,
        voice_count: (*canon.voices).len(),
        interval_of_imitation: interval,
        mode_id: *canon.mode_id,
        length: (*canon.leader_degrees).len(),
        time_unit: *canon.time_unit,
        melodic_alphabet_size: alphabet.len(),
    }
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
    }
}

// ──────────────────────────────────────────────────────────
// Ornamentation: divisions / passing tones (Montanos "b", Morley "divided")
// ──────────────────────────────────────────────────────────

/// Fill the motion from `from_deg` to `to_deg` with `s` diatonic notes (a division). The first
/// note is the structural degree; remaining notes step toward `to_deg` (passing tones), holding
/// the target once reached. Returns `s` diatonic degrees.
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

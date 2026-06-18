//! Canon by inversion — the follower imitates by mirroring every interval.
//!
//! Standard transposition canon: follower_degree(t) = leader_degree(t - lag) + T
//! Inversion canon:              follower_degree(t) = pivot − leader_degree(t - lag)
//!
//! The lag-difference vertical for inversion:
//!   vertical(t) = L(t) + L(t − lag) − pivot
//! which is consonant iff  abs(L(t) + L(t−lag) − pivot) % 7  is in {0,2,4,5}.
//! This is a position-dependent (not just step-dependent) constraint, but remains
//! fully checkable in O(1) per candidate step during the leader walk.
//!
//! No existing files are modified.

use core::array::ArrayTrait;
use koji::lcg::LCG;
use koji::rng::{RandomSource, bounded};
use koji::composition::canon_rules::{abs_i32, is_consonant_class};
use koji::composition::melodic_canon::{NoteEvent, realize_degree, DEFAULT_VELOCITY, REGISTER_BAND};

// ─────────────────────────────────────────────────────────────
// Follower specification
// ─────────────────────────────────────────────────────────────

/// How a follower voice imitates the leader.
///
/// `Transposition` and `Inversion` are fully implemented — degree computation is O(1).
/// `Retrograde`, `Augmentation`, and `Diminution` require the full leader sequence or change the
/// temporal grid; `follower_degree_for_spec` panics for those variants.  Use
/// `follower_degree_retrograde`, `realize_augmented_follower`, and `realize_diminuted_follower`
/// (to be added alongside the event emitters) once the time-aware paths are built.
#[derive(Copy, Drop)]
pub enum FollowerSpec {
    /// Classic canon: follower degree = leader_degree + transposition.
    Transposition: i32,
    /// Mirror canon: follower degree = pivot − leader_degree.  Intervals are inverted.
    Inversion: i32,
    /// Retrograde canon: follower plays the leader's sequence in reverse order.
    /// Requires the full `leader_degrees` array — use `follower_degree_retrograde` instead.
    Retrograde,
    /// Mensuration (augmentation) canon: each leader note is held for `factor` time units.
    /// Overlap windows shift non-trivially — use `realize_augmented_follower` instead.
    Augmentation: u32,
    /// Diminution canon: each leader note is compressed to `1/factor` time units.
    /// Overlap windows shift non-trivially — use `realize_diminuted_follower` instead.
    Diminution: u32,
}

/// Compute the follower's diatonic degree given the leader's degree and the follower spec.
/// Only valid for `Transposition` and `Inversion` — the other variants require sequence-level
/// context (full array + position) and panic at runtime with a descriptive message.
pub fn follower_degree_for_spec(spec: FollowerSpec, leader_deg: i32) -> i32 {
    match spec {
        FollowerSpec::Transposition(t) => leader_deg + t,
        FollowerSpec::Inversion(pivot) => pivot - leader_deg,
        FollowerSpec::Retrograde => panic!("Retrograde requires full array; use follower_degree_retrograde"),
        FollowerSpec::Augmentation(_) => panic!("Augmentation requires time-aware emitter; use realize_augmented_follower"),
        FollowerSpec::Diminution(_) => panic!("Diminution requires time-aware emitter; use realize_diminuted_follower"),
    }
}

/// Compute the follower degree for a Retrograde canon at position `pos` in a sequence of `len`.
/// `leader_degrees[len - 1 - pos]` gives the reversed index.
pub fn follower_degree_retrograde(leader_degrees: Span<i32>, pos: u32) -> i32 {
    let len = leader_degrees.len();
    assert(pos < len, 'retrograde pos out of bounds');
    *leader_degrees.at(len - 1 - pos)
}

// ─────────────────────────────────────────────────────────────
// Inversion canon struct
// ─────────────────────────────────────────────────────────────

/// A two-voice canon in which the follower imitates by melodic inversion.
#[derive(Drop)]
pub struct InversionCanon {
    /// Leader diatonic degrees (degree 0 = modal final).
    pub leader_degrees: Array<i32>,
    /// Inversion pivot: follower_degree(t) = pivot − leader_degree(t − lag).
    pub pivot: i32,
    /// Entry lag in structural beats.
    pub lag: u32,
    /// Lattice octave size: 7 (diatonic) or 12 (chromatic).
    pub octave: u32,
    pub mode_id: u8,
    pub tonic_keynum: u8,
    pub time_unit: u32,
    pub leader_voice_id: u32,
    pub follower_voice_id: u32,
}

// ─────────────────────────────────────────────────────────────
// Consonance check for the inversion vertical
// ─────────────────────────────────────────────────────────────

/// Vertical interval class for the inversion canon at a given step.
/// `cur`         = current leader degree (before taking step m)
/// `prev_at_lag` = leader degree `lag` positions ago
/// `pivot`       = inversion axis
/// Returns the generic class of the resulting vertical (0–6).
pub fn inversion_vertical_class(cur: i32, m: i32, prev_at_lag: i32, pivot: i32) -> u32 {
    let future = cur + m;
    let vertical = future + prev_at_lag - pivot;
    abs_i32(vertical) % 7
}

/// True when step `m` produces a consonant vertical against an inverted follower.
/// When `in_overlap` is false the follower has not yet entered — any step is valid.
pub fn inversion_step_consonant(
    cur: i32, m: i32, prev_at_lag: i32, pivot: i32, in_overlap: bool,
) -> bool {
    if !in_overlap {
        return true;
    }
    is_consonant_class(inversion_vertical_class(cur, m, prev_at_lag, pivot))
}

// ─────────────────────────────────────────────────────────────
// Candidate set
// ─────────────────────────────────────────────────────────────

/// All diatonic steps in [−7, 7] that produce consonant inversion verticals,
/// further filtered to the register band [lo, hi].
fn inversion_candidates(
    cur: i32, prev_at_lag: i32, pivot: i32, in_overlap: bool, lo: i32, hi: i32,
) -> Array<i32> {
    let mut band: Array<i32> = ArrayTrait::new();
    let mut any: Array<i32> = ArrayTrait::new();
    let mut mi: u32 = 0;
    loop {
        if mi > 14 {
            break;
        }
        let m: i32 = mi.try_into().unwrap() - 7;
        if inversion_step_consonant(cur, m, prev_at_lag, pivot, in_overlap) {
            any.append(m);
            let next = cur + m;
            if next >= lo && next <= hi {
                band.append(m);
            }
        }
        mi += 1;
    };
    if band.len() > 0 {
        band
    } else {
        any
    }
}

// ─────────────────────────────────────────────────────────────
// Leader walk for inversion canon
// ─────────────────────────────────────────────────────────────

/// Walk the leader for an inversion canon of `len` structural degrees.
/// Returns `(leader_degrees, leader_steps)`.
pub fn walk_leader_for_inversion(
    seed: felt252, len: u32, pivot: i32, lag: u32,
) -> (Array<i32>, Array<i32>) {
    assert(len >= 2, 'len must be >= 2');
    assert(lag >= 1, 'lag must be >= 1');

    let s: u256 = seed.into();
    let init: u32 = (s % 256).try_into().unwrap();
    let mut rng = LCG { state: init, multiplier: 5, increment: 3, modulus: 256 };

    let hw: i32 = REGISTER_BAND;
    let mut degrees: Array<i32> = ArrayTrait::new();
    degrees.append(0);
    let mut steps: Array<i32> = ArrayTrait::new();

    let mut p: u32 = 1;
    loop {
        if p >= len {
            break;
        }
        let cur = *degrees.at(degrees.len() - 1);
        let in_overlap = degrees.len() >= lag;
        let prev_at_lag: i32 = if in_overlap {
            *degrees.at(degrees.len() - lag)
        } else {
            0
        };
        let cands = inversion_candidates(cur, prev_at_lag, pivot, in_overlap, -hw, hw);
        let pool = if cands.len() > 0 {
            cands.span()
        } else {
            // safety: use full range (should not fire for well-chosen pivots)
            array![0_i32].span()
        };
        let (raw, next_rng) = rng.draw();
        rng = next_rng;
        let m = *pool.at(bounded(raw, pool.len()));
        degrees.append(cur + m);
        steps.append(m);
        p += 1;
    };
    (degrees, steps)
}

// ─────────────────────────────────────────────────────────────
// Generator
// ─────────────────────────────────────────────────────────────

/// Generate a two-voice inversion canon.
/// `pivot` = 0 inverts around the final; `pivot = T` places the follower at interval T from
/// the leader at the starting note.  A common choice: `pivot = 4` (fifth above the final).
pub fn generate_inversion_canon(
    seed: felt252,
    len: u32,
    pivot: i32,
    lag: u32,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
    leader_voice_id: u32,
    follower_voice_id: u32,
) -> InversionCanon {
    let (degrees, _steps) = walk_leader_for_inversion(seed, len, pivot, lag);
    InversionCanon {
        leader_degrees: degrees, pivot, lag, octave, mode_id, tonic_keynum, time_unit,
        leader_voice_id, follower_voice_id,
    }
}

// ─────────────────────────────────────────────────────────────
// Event emission
// ─────────────────────────────────────────────────────────────

/// Emit NoteEvents for both voices of the inversion canon.
/// The follower enters `lag` structural beats after the leader and mirrors its degrees.
pub fn inversion_canon_to_note_events(canon: @InversionCanon) -> Array<NoteEvent> {
    let degs = canon.leader_degrees;
    let len = degs.len();
    let unit = *canon.time_unit;
    let pivot = *canon.pivot;
    let lag = *canon.lag;
    let octave = *canon.octave;
    let mode = *canon.mode_id;
    let tonic = *canon.tonic_keynum;
    let mut out: Array<NoteEvent> = ArrayTrait::new();

    // Leader voice
    let mut p: u32 = 0;
    loop {
        if p >= len {
            break;
        }
        let deg = *degs.at(p);
        out.append(
            NoteEvent {
                time: p * unit,
                duration: unit,
                pitch: realize_degree(octave, deg, tonic, mode),
                velocity: DEFAULT_VELOCITY,
                voice_id: *canon.leader_voice_id,
            },
        );
        p += 1;
    };

    // Inverted follower voice: degree(t) = pivot - leader_degree(t - lag)
    let mut p: u32 = 0;
    loop {
        if p >= len {
            break;
        }
        let follower_deg = pivot - *degs.at(p);
        out.append(
            NoteEvent {
                time: (p + lag) * unit,
                duration: unit,
                pitch: realize_degree(octave, follower_deg, tonic, mode),
                velocity: DEFAULT_VELOCITY,
                voice_id: *canon.follower_voice_id,
            },
        );
        p += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Validators
// ─────────────────────────────────────────────────────────────

/// True iff every simultaneous vertical in the inversion canon is consonant
/// (generic class in {0, 2, 4, 5}).
pub fn inversion_canon_clash_free(canon: @InversionCanon) -> bool {
    let degs = canon.leader_degrees;
    let len = degs.len();
    let lag = *canon.lag;
    let pivot = *canon.pivot;
    // Overlap: leader position p and follower based on leader[p - lag].
    // Follower is at absolute time p + lag, playing pivot - degs[p].
    // Leader at time p + lag plays degs[p + lag] (when p + lag < len).
    // Vertical at absolute time T = p + lag: leader[p+lag] vs (pivot - leader[p]).
    let mut p: u32 = 0;
    let mut ok = true;
    loop {
        if !ok {
            break;
        }
        let t_leader = p + lag;
        if t_leader >= len {
            break;
        }
        let leader_deg = *degs.at(t_leader);
        let vertical = leader_deg + *degs.at(p) - pivot;
        let cls = abs_i32(vertical) % 7;
        if !is_consonant_class(cls) {
            ok = false;
        }
        p += 1;
    };
    ok
}

/// True iff the follower's melodic intervals are exact negations of the leader's
/// (strict melodic inversion, not mere transposition).
pub fn strict_melodic_inversion(canon: @InversionCanon) -> bool {
    let degs = canon.leader_degrees;
    let len = degs.len();
    if len < 2 {
        return true;
    }
    let pivot = *canon.pivot;
    // Follower step at p = follower[p+1] - follower[p]
    //   = (pivot - degs[p+1]) - (pivot - degs[p])
    //   = degs[p] - degs[p+1]
    //   = -(degs[p+1] - degs[p]) = -(leader step at p)
    // This always holds by construction; the validator just confirms the arithmetic.
    let mut p: u32 = 0;
    let mut ok = true;
    loop {
        if p + 1 >= len || !ok {
            break;
        }
        let leader_step = *degs.at(p + 1) - *degs.at(p);
        let f0 = pivot - *degs.at(p);
        let f1 = pivot - *degs.at(p + 1);
        let follower_step = f1 - f0;
        if follower_step != -leader_step {
            ok = false;
        }
        p += 1;
    };
    ok
}

/// Default pivot choice: the interval that places the follower's opening note at a fifth
/// above the final (diatonic degree 4).  Works for diatonic lattice (octave = 7) canons.
pub fn pivot_at_fifth() -> i32 {
    4_i32
}

/// Pivot that places the follower's opening on a third above (diatonic degree 2).
pub fn pivot_at_third() -> i32 {
    2_i32
}

/// Pivot that places the follower in exact contrary motion (unison pivot — leader and
/// follower both start at degree 0, mirroring symmetrically).
pub fn pivot_at_unison() -> i32 {
    0_i32
}

// ─────────────────────────────────────────────────────────────
// Time-aware follower event emitters
// ─────────────────────────────────────────────────────────────

/// Emit NoteEvents for a retrograde follower: plays the leader sequence in reverse order.
/// The follower enters at `entry_time` and moves at the same rate as the leader.
/// `transposition` offsets all follower diatonic degrees (0 = exact retrograde).
pub fn realize_retrograde_follower(
    leader_degrees: Span<i32>,
    transposition: i32,
    entry_time: u32,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
    voice_id: u32,
) -> Array<NoteEvent> {
    let len = leader_degrees.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut j: u32 = 0;
    loop {
        if j >= len {
            break;
        }
        let deg = *leader_degrees.at(len - 1 - j) + transposition;
        out.append(
            NoteEvent {
                time: entry_time + j * time_unit,
                duration: time_unit,
                pitch: realize_degree(octave, deg, tonic_keynum, mode_id),
                velocity: DEFAULT_VELOCITY,
                voice_id,
            },
        );
        j += 1;
    };
    out
}

/// Emit NoteEvents for an augmented (slowed) follower: each leader note is stretched by `factor`.
/// Each note lasts `factor * time_unit`; total follower duration = `len * factor * time_unit`.
/// `transposition` shifts follower diatonic degrees. `entry_time` is absolute start time.
pub fn realize_augmented_follower(
    leader_degrees: Span<i32>,
    transposition: i32,
    factor: u32,
    entry_time: u32,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
    voice_id: u32,
) -> Array<NoteEvent> {
    assert(factor >= 1, 'factor must be >= 1');
    let len = leader_degrees.len();
    let aug_unit = time_unit * factor;
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut j: u32 = 0;
    loop {
        if j >= len {
            break;
        }
        let deg = *leader_degrees.at(j) + transposition;
        out.append(
            NoteEvent {
                time: entry_time + j * aug_unit,
                duration: aug_unit,
                pitch: realize_degree(octave, deg, tonic_keynum, mode_id),
                velocity: DEFAULT_VELOCITY,
                voice_id,
            },
        );
        j += 1;
    };
    out
}

/// Emit NoteEvents for a diminuted (sped-up) follower: each leader note is compressed by `factor`.
/// Each note lasts `time_unit / factor`; total follower duration = `len * time_unit / factor`.
/// `time_unit` must be divisible by `factor`.
pub fn realize_diminuted_follower(
    leader_degrees: Span<i32>,
    transposition: i32,
    factor: u32,
    entry_time: u32,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
    voice_id: u32,
) -> Array<NoteEvent> {
    assert(factor >= 1, 'factor must be >= 1');
    assert(time_unit % factor == 0, 'time_unit not divisible');
    let len = leader_degrees.len();
    let dim_unit = time_unit / factor;
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut j: u32 = 0;
    loop {
        if j >= len {
            break;
        }
        let deg = *leader_degrees.at(j) + transposition;
        out.append(
            NoteEvent {
                time: entry_time + j * dim_unit,
                duration: dim_unit,
                pitch: realize_degree(octave, deg, tonic_keynum, mode_id),
                velocity: DEFAULT_VELOCITY,
                voice_id,
            },
        );
        j += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Pairwise clash validators for non-uniform-speed followers
// ─────────────────────────────────────────────────────────────

/// True iff every simultaneous vertical between the leader and a retrograde follower is consonant.
/// The follower enters `lag` structural beats after the leader and plays degrees in reverse.
/// Overlap spans beats [lag, len−1] (both voices sounding).
pub fn retrograde_follower_clash_free(
    leader_degrees: Span<i32>, transposition: i32, lag: u32,
) -> bool {
    let len = leader_degrees.len();
    if lag >= len {
        return true;
    }
    let mut t: u32 = lag;
    let mut ok = true;
    loop {
        if t >= len || !ok {
            break;
        }
        // Leader at beat t plays degrees[t].
        // Follower (entered at lag) is at position j = t − lag, playing degrees[len−1−j].
        let j = t - lag;
        let rev_idx = len - 1 - j;
        let leader_deg = *leader_degrees.at(t);
        let follower_deg = *leader_degrees.at(rev_idx) + transposition;
        let vertical = leader_deg - follower_deg;
        if !is_consonant_class(abs_i32(vertical) % 7) {
            ok = false;
        }
        t += 1;
    };
    ok
}

/// True iff every leader beat that overlaps an augmented follower produces a consonant vertical.
/// `entry_beat` = follower entry in structural beats (= entry_time / time_unit).
/// `factor` = augmentation factor; follower note j is sounding during leader beats
///   [entry_beat + j*factor, entry_beat + (j+1)*factor − 1].
pub fn augmented_follower_clash_free(
    leader_degrees: Span<i32>, transposition: i32, factor: u32, entry_beat: u32,
) -> bool {
    assert(factor >= 1, 'factor must be >= 1');
    let len = leader_degrees.len();
    let mut p: u32 = 0;
    let mut ok = true;
    loop {
        if p >= len || !ok {
            break;
        }
        if p >= entry_beat {
            let follower_j = (p - entry_beat) / factor;
            if follower_j < len {
                let leader_deg = *leader_degrees.at(p);
                let follower_deg = *leader_degrees.at(follower_j) + transposition;
                let vertical = leader_deg - follower_deg;
                if !is_consonant_class(abs_i32(vertical) % 7) {
                    ok = false;
                }
            }
        }
        p += 1;
    };
    ok
}

// ─────────────────────────────────────────────────────────────
// Unified follower spec dispatcher
// ─────────────────────────────────────────────────────────────

/// Emit NoteEvents for any `FollowerSpec` transform of `leader_degrees`.
///
/// - `Transposition(t)`: classic delayed canon; follower plays leader + t at same speed.
/// - `Inversion(pivot)`: mirror canon; follower plays pivot − leader at same speed.
/// - `Retrograde`: follower plays leader in reverse order at same speed (transposition = 0).
/// - `Augmentation(f)`: follower plays at 1/f speed (each note lasts f × time_unit).
/// - `Diminution(f)`: follower plays at f× speed (each note lasts time_unit / f).
///   Requires time_unit divisible by f.
///
/// `entry_time` is the absolute start time for the follower (typically lag × time_unit).
pub fn apply_follower_spec_events(
    leader_degrees: Span<i32>,
    spec: FollowerSpec,
    entry_time: u32,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
    voice_id: u32,
) -> Array<NoteEvent> {
    let len = leader_degrees.len();
    match spec {
        FollowerSpec::Transposition(t) => {
            let mut out: Array<NoteEvent> = ArrayTrait::new();
            let mut j: u32 = 0;
            loop {
                if j >= len {
                    break;
                }
                let deg = *leader_degrees.at(j) + t;
                out.append(
                    NoteEvent {
                        time: entry_time + j * time_unit,
                        duration: time_unit,
                        pitch: realize_degree(octave, deg, tonic_keynum, mode_id),
                        velocity: DEFAULT_VELOCITY,
                        voice_id,
                    },
                );
                j += 1;
            };
            out
        },
        FollowerSpec::Inversion(pivot) => {
            let mut out: Array<NoteEvent> = ArrayTrait::new();
            let mut j: u32 = 0;
            loop {
                if j >= len {
                    break;
                }
                let deg = pivot - *leader_degrees.at(j);
                out.append(
                    NoteEvent {
                        time: entry_time + j * time_unit,
                        duration: time_unit,
                        pitch: realize_degree(octave, deg, tonic_keynum, mode_id),
                        velocity: DEFAULT_VELOCITY,
                        voice_id,
                    },
                );
                j += 1;
            };
            out
        },
        FollowerSpec::Retrograde => {
            realize_retrograde_follower(
                leader_degrees, 0, entry_time, octave, mode_id, tonic_keynum, time_unit, voice_id,
            )
        },
        FollowerSpec::Augmentation(factor) => {
            realize_augmented_follower(
                leader_degrees, 0, factor, entry_time, octave, mode_id, tonic_keynum, time_unit,
                voice_id,
            )
        },
        FollowerSpec::Diminution(factor) => {
            realize_diminuted_follower(
                leader_degrees, 0, factor, entry_time, octave, mode_id, tonic_keynum, time_unit,
                voice_id,
            )
        },
    }
}

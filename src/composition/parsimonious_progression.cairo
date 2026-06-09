//! Profile 5 — Parsimonious Seventh-Chord Voice Leading (Neo-Riemannian).
//!
//! A *different* generation mode from the stretto-fuga canon: instead of a melodic leader imitated
//! by followers, this engine emits a **progression of seventh chords** in which every voice moves
//! by at most a whole step (≤ 2 semitones) from one chord to the next — the by-construction
//! analogue of the alphabet restriction, applied to chord-to-chord motion (Cohn 1997; Douthett &
//! Steinbach 1998; Childs 1998).
//!
//! Correctness by construction: every transition is drawn from a table of moves that are each
//! *verified* to displace each voice by ≤ 2 semitones and to land on another recognized seventh
//! chord, so `voice_leading_smooth` and `no_minor_ninth_in_chords` always hold. No search.
//!
//! See `docs/extended_harmony_canon_spec.md` § Profile 5.

use core::array::ArrayTrait;
use koji::lcg::LCG;
use koji::rng::{RandomSource, bounded};
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::canon_rules::abs_i32;

pub const PARSI_VELOCITY: u8 = 88;

/// Seventh-chord qualities, as close-voiced semitone interval sets above the root. The chain
/// maj7 ↔ dom7 ↔ min7 ↔ half-dim7 differs by exactly one semitone on one voice at each link,
/// so a quality "morph" is a single-semitone parsimonious move with three common tones.
pub fn chord_intervals(quality: u8) -> Span<i32> {
    if quality == 0 {
        array![0_i32, 4, 7, 11].span() // maj7
    } else if quality == 1 {
        array![0_i32, 4, 7, 10].span() // dom7
    } else if quality == 2 {
        array![0_i32, 3, 7, 10].span() // min7
    } else {
        array![0_i32, 3, 6, 10].span() // half-diminished 7
    }
}

pub fn quality_name(quality: u8) -> felt252 {
    if quality == 0 {
        'maj7'
    } else if quality == 1 {
        'dom7'
    } else if quality == 2 {
        'min7'
    } else {
        'halfdim7'
    }
}

/// The four voice pitches (absolute MIDI keynums) of `(root, quality)` over `base`.
fn voice_pitches(base: u8, root: i32, quality: u8) -> Array<i32> {
    let iv = chord_intervals(quality);
    let b: i32 = base.into();
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= iv.len() {
            break;
        }
        out.append(b + root + *iv.at(i));
        i += 1;
    };
    out
}

/// Append the 4 voices of a chord at `time` to the event list.
fn emit_chord(ref out: Array<NoteEvent>, base: u8, root: i32, quality: u8, time: u32, unit: u32) {
    let pitches = voice_pitches(base, root, quality);
    let mut c: u32 = 0;
    loop {
        if c >= pitches.len() {
            break;
        }
        out
            .append(
                NoteEvent {
                    time,
                    duration: unit,
                    pitch: (*pitches.at(c)).try_into().unwrap(),
                    velocity: PARSI_VELOCITY,
                    voice_id: c,
                },
            );
        c += 1;
    };
}

/// Build the candidate next-states `(root, quality)` reachable from `(root, quality)` by a
/// parsimonious move: a quality morph along the chain (one semitone, root fixed), or a chromatic /
/// whole-step transposition of the whole chord (root motion ±1 or ±2, quality fixed). Every option
/// displaces each voice by ≤ 2 semitones by construction.
fn candidate_moves(root: i32, quality: u8) -> (Array<i32>, Array<u8>) {
    let mut roots: Array<i32> = ArrayTrait::new();
    let mut quals: Array<u8> = ArrayTrait::new();
    // quality morphs (single-semitone, three common tones)
    if quality < 3 {
        roots.append(root);
        quals.append(quality + 1);
    }
    if quality > 0 {
        roots.append(root);
        quals.append(quality - 1);
    }
    // chord transpositions (preserve quality; all voices move together by k)
    let ks = array![1_i32, -1, 2, -2];
    let mut i: u32 = 0;
    loop {
        if i >= ks.len() {
            break;
        }
        let nr = root + *ks.at(i);
        if nr >= -7 && nr <= 7 {
            roots.append(nr);
            quals.append(quality);
        }
        i += 1;
    };
    (roots, quals)
}

/// Generate a deterministic parsimonious seventh-chord progression of `nsteps` chords, starting on
/// a major-seventh chord on the tonic. Returns one `NoteEvent` per voice per step (4 voices). Each
/// chord is consonant (a seventh chord, no internal m2) and each voice moves ≤ 2 semitones.
pub fn generate_parsimonious_progression(seed: felt252, nsteps: u32) -> Array<NoteEvent> {
    let s: u256 = seed.into();
    let base: u8 = 60;
    let unit: u32 = 4;
    let mut state: u32 = (s % 256).try_into().unwrap();
    if state == 0 {
        state = 11;
    }
    let mut rng = LCG { state, multiplier: 5, increment: 3, modulus: 256 };

    let mut root: i32 = 0;
    let mut quality: u8 = 0; // maj7

    let mut out: Array<NoteEvent> = ArrayTrait::new();
    emit_chord(ref out, base, root, quality, 0, unit);

    let mut step: u32 = 1;
    loop {
        if step >= nsteps {
            break;
        }
        let (roots, quals) = candidate_moves(root, quality);
        let (raw, next) = rng.draw();
        rng = next;
        let idx = bounded(raw, roots.len());
        root = *roots.at(idx);
        quality = *quals.at(idx);
        emit_chord(ref out, base, root, quality, step * unit, unit);
        step += 1;
    };
    out
}

/// Grid ticks for one `nchords`-chord passage (`unit = 4` per chord).
pub fn parsimonious_progression_cycle_ticks(nchords: u32) -> u32 {
    nchords * 4
}

/// Decorate the chord tone `p` over `s` sub-beats, leaning toward the next chord tone `q`. The
/// strong sub-beat (index 0) is always the structural chord tone (so the harmony stays the
/// seventh-chord progression); the weak sub-beats add neighbor / passing motion, and the final
/// sub-beat steps toward `q` for a smooth arrival. `up` chooses an upper vs. lower neighbor.
fn ornament_cell(p: i32, q: i32, s: u32, up: bool) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    if s <= 1 {
        out.append(p);
        return out;
    }
    let nb: i32 = if up {
        2
    } else {
        -2
    };
    let delta = q - p;
    let toward_q: i32 = if delta > 0 {
        1
    } else if delta < 0 {
        -1
    } else {
        0
    };
    let mut i: u32 = 0;
    loop {
        if i >= s {
            break;
        }
        let v = if i == 0 {
            p
        } else if i == s - 1 {
            if toward_q != 0 {
                p + toward_q
            } else {
                p + nb
            }
        } else if i % 2 == 1 {
            p + nb
        } else {
            p
        };
        out.append(v);
        i += 1;
    };
    out
}

/// As `generate_parsimonious_progression`, but each chord tone is **subdivided** into 2 or 4
/// decorated notes per voice (neighbor / passing ornamentation), seeded for variety. The structural
/// chord tones (strong sub-beats) still form the same parsimonious seventh-chord progression, so
/// `voice_leading_smooth` holds on the strong-beat reduction; the weak-beat decorations add the
/// dense ornamentation. Events are emitted voice-major; each carries an absolute `time`.
pub fn generate_ornamented_parsimonious_progression(
    seed: felt252, nchords: u32,
) -> Array<NoteEvent> {
    let s256: u256 = seed.into();
    let base: u8 = 60;
    let b: i32 = base.into();
    let unit: u32 = 4;

    // 1. Walk the chord sequence (same as the block generator).
    let mut state: u32 = (s256 % 256).try_into().unwrap();
    if state == 0 {
        state = 11;
    }
    let mut rng = LCG { state, multiplier: 5, increment: 3, modulus: 256 };
    let mut roots_seq: Array<i32> = ArrayTrait::new();
    let mut quals_seq: Array<u8> = ArrayTrait::new();
    let mut root: i32 = 0;
    let mut quality: u8 = 0;
    roots_seq.append(root);
    quals_seq.append(quality);
    let mut step: u32 = 1;
    loop {
        if step >= nchords {
            break;
        }
        let (roots, quals) = candidate_moves(root, quality);
        let (raw, next) = rng.draw();
        rng = next;
        let idx = bounded(raw, roots.len());
        root = *roots.at(idx);
        quality = *quals.at(idx);
        roots_seq.append(root);
        quals_seq.append(quality);
        step += 1;
    };

    // 2. Ornament: per voice, per chord, subdivide the chord tone with decoration.
    let mut orn_state: u32 = ((s256 / 256) % 256).try_into().unwrap();
    if orn_state == 0 {
        orn_state = 19;
    }
    let mut orng = LCG { state: orn_state, multiplier: 5, increment: 3, modulus: 256 };

    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut c: u32 = 0;
    loop {
        if c >= 4 {
            break;
        }
        let mut k: u32 = 0;
        loop {
            if k >= nchords {
                break;
            }
            let iv_k = chord_intervals(*quals_seq.at(k));
            let p: i32 = b + *roots_seq.at(k) + *iv_k.at(c);
            let q: i32 = if k + 1 < nchords {
                let iv_n = chord_intervals(*quals_seq.at(k + 1));
                b + *roots_seq.at(k + 1) + *iv_n.at(c)
            } else {
                p
            };
            // bias toward heavy subdivision (4) for dense ornamentation
            let (raw, next) = orng.draw();
            orng = next;
            let r = bounded(raw, 100);
            let mut subs = if r < 60 {
                4_u32
            } else if r < 90 {
                2_u32
            } else {
                1_u32
            };
            if unit % subs != 0 {
                subs = 1;
            }
            let fill = ornament_cell(p, q, subs, (c + k) % 2 == 0);
            let sub_dur = unit / subs;
            let mut i: u32 = 0;
            loop {
                if i >= subs {
                    break;
                }
                let vel: u8 = if i == 0 {
                    PARSI_VELOCITY
                } else {
                    70
                };
                out
                    .append(
                        NoteEvent {
                            time: k * unit + i * sub_dur,
                            duration: sub_dur,
                            pitch: (*fill.at(i)).try_into().unwrap(),
                            velocity: vel,
                            voice_id: c,
                        },
                    );
                i += 1;
            };
            k += 1;
        };
        c += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Validators (assertions, not searches)
// ──────────────────────────────────────────────────────────

/// Every voice moves at most `max` semitones between consecutive chords. With 4 voices the events
/// are laid out chord-major (voices 0..3 then the next chord), so voice `c` of chord `k` is at
/// index `k*4 + c`.
pub fn voice_leading_smooth(events: Span<NoteEvent>, max: u32) -> bool {
    let nv: u32 = 4;
    if events.len() < nv {
        return true;
    }
    let chords = events.len() / nv;
    let mut k: u32 = 1;
    let mut ok = true;
    loop {
        if k >= chords || !ok {
            break;
        }
        let mut c: u32 = 0;
        loop {
            if c >= nv {
                break;
            }
            let prev: i32 = (*events.at((k - 1) * nv + c)).pitch.into();
            let cur: i32 = (*events.at(k * nv + c)).pitch.into();
            if abs_i32(cur - prev) > max {
                ok = false;
                break;
            }
            c += 1;
        };
        k += 1;
    };
    ok
}

/// No chord contains a minor 2nd / minor 9th between any two of its voices (chromatic class 1).
pub fn no_minor_ninth_in_chords(events: Span<NoteEvent>) -> bool {
    let nv: u32 = 4;
    let chords = events.len() / nv;
    let mut k: u32 = 0;
    let mut ok = true;
    loop {
        if k >= chords || !ok {
            break;
        }
        let mut a: u32 = 0;
        loop {
            if a >= nv || !ok {
                break;
            }
            let mut b: u32 = a + 1;
            loop {
                if b >= nv {
                    break;
                }
                let pa: i32 = (*events.at(k * nv + a)).pitch.into();
                let pb: i32 = (*events.at(k * nv + b)).pitch.into();
                if abs_i32(pa - pb) % 12 == 1 {
                    ok = false;
                    break;
                }
                b += 1;
            };
            a += 1;
        };
        k += 1;
    };
    ok
}

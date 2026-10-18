//! Composer v1.1: engine v1's theme and parameters, recomposed. Byte-identical to
//! `createEngineV11(engine).render(beast, live, { keys: 'mode', even: true, traj: true })` in
//! offchain/beast-sound/src/engine_v11.js (the options chosen on the compare page).
//!
//! - Cadence: the theme's last bar steps to the tonic and holds it.
//! - Rhythm: the theme in 4-beat rhythm cells, picked by the motif seed from a family chosen by the
//!   Beast's type; `ornament_density` gates the cells with passing notes.
//! - Voices: every follower note is checked against everything sounding with it (thirds and sixths
//!   preferred; clashes on the beat, unisons and parallel 5ths/8ves avoided by moving a step or
//!   two).
//! - Episodes: no silent bars. From the end of its line to the next section every voice sequences
//!   the theme's opening bar, then makes a half cadence onto the next section's dominant.
//! - Key plan, same mode: every section stays in the home key and mode; the theme starts on the
//!   planned scale degree (a circle-of-fifths plan whose reach is set by the tier).
//! - Even phrases: a section is the canon plus an episode of 1 or 2 bars, whichever makes it an
//! even
//!   number of bars; the first bar of each pair is accented.
//! - History: kills and defeats are swapped at the input. Episodes rise when (swapped) kills
//!   outnumber defeats; later sections develop by the dominant history (stretto, inversion or
//!   sequence); the second name prefix picks trills or passing notes; level and health set voice
//!   spacing; the real rank sets only the lead's prominence.
//!
//! The voice checks score candidates in quarter points (the JS scores times 4), so every score is
//! an integer and ties break the same way (first candidate wins).

use core::dict::{Felt252Dict, Felt252DictEntryTrait, Felt252DictTrait};
use core::num::traits::CheckedSub;
use crate::composition::beast_score::{
    BeastForm, build_beast_theme, canonical_to_melodic_mode, derive_beast_sound_seeds,
    transposed_tonic,
};
use crate::composition::beast_trait_map::{BeastCompositionParams, prefix2_ornament_policy};
use crate::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, beast_sound_seed, is_genesis,
    map_v3_beast_to_composition_params, v3_music_state,
};
use crate::composition::countersubject::{default_countersubject_config, generate_countersubject};
use crate::composition::melodic_canon::{NoteEvent, degree_to_keynum, mode_scale};

const TU: u32 = 480;
const BAR: u32 = 1920;
/// Slot sources: 0-3 a beat of the 4-beat group (that beat's theme degree), then these.
const SRC_PASSING: u8 = 4;
const SRC_TONIC: u8 = 5;
const SRC_TRILL: u8 = 6;
/// Developments for sections after the first.
pub const DEV_SEQUENCE: u8 = 0;
pub const DEV_STRETTO: u8 = 1;
pub const DEV_INVERSION: u8 = 2;

#[derive(Copy, Drop)]
struct Slot {
    time: u32,
    duration: u32,
    src: u8,
    group: u32,
    degree: i32,
}

/// The Beast data mapped to musical function (engine_v11.js `trajectory`).
#[derive(Copy, Drop)]
struct Trajectory {
    /// Episodes rise (1), fall (-1) or alternate by section (0).
    direction: i32,
    development: u8,
    /// Voice offsets: 0 wide, 1 normal, 2 close.
    spacing: u8,
    prominence: u32,
    trill: bool,
}

/// Overrides on the mapped parameters (engine_v11.js `override`), as the lab's Genesis Track uses
/// them: `None` keeps the mapped value. The theme is still built from the mapped parameters; the
/// rhythm, sections, voices and key use the overridden ones.
#[derive(Copy, Drop)]
pub struct V11Override {
    pub voice_count: Option<u32>,
    pub section_count: Option<u8>,
    pub mode_id: Option<u8>,
    pub tonic_keynum: Option<u8>,
    pub register_band: Option<u8>,
    pub ornament_density: Option<u8>,
    pub name_variant_id: Option<u32>,
    pub use_countersubject: Option<bool>,
    /// Seven semitone offsets from the tonic, realized in place of the mode's scale.
    pub scale: Option<Span<u8>>,
    /// Trills in place of passing notes, in place of the name's ornament policy.
    pub trill: Option<bool>,
    /// A bought track's treatment (engine_v11.js `override.rhythmSeed`, `flipSide`, `tr`): the seed
    /// that picks the theme's rhythm cells, the key plan mirrored, the development (DEV_*), the
    /// episodes' direction (1, -1, 0) and the voice spacing (0 wide, 1 normal, 2 close).
    pub rhythm_seed: Option<felt252>,
    pub flip_side: Option<bool>,
    pub development: Option<u8>,
    pub direction: Option<i32>,
    pub spacing: Option<u8>,
}

/// No overrides: `build_v11_score_with(beast, live, no_override())` is `build_v11_score`.
pub fn no_override() -> V11Override {
    V11Override {
        voice_count: Option::None,
        section_count: Option::None,
        mode_id: Option::None,
        tonic_keynum: Option::None,
        register_band: Option::None,
        ornament_density: Option::None,
        name_variant_id: Option::None,
        use_countersubject: Option::None,
        scale: Option::None,
        trill: Option::None,
        rhythm_seed: Option::None,
        flip_side: Option::None,
        development: Option::None,
        direction: Option::None,
        spacing: Option::None,
    }
}

fn apply_override(p: BeastCompositionParams, ov: V11Override) -> BeastCompositionParams {
    BeastCompositionParams {
        voice_count: match ov.voice_count {
            Option::Some(x) => x,
            Option::None => p.voice_count,
        },
        section_count: match ov.section_count {
            Option::Some(x) => x,
            Option::None => p.section_count,
        },
        mode_id: match ov.mode_id {
            Option::Some(x) => x,
            Option::None => p.mode_id,
        },
        tonic_keynum: match ov.tonic_keynum {
            Option::Some(x) => x,
            Option::None => p.tonic_keynum,
        },
        register_band: match ov.register_band {
            Option::Some(x) => x,
            Option::None => p.register_band,
        },
        ornament_density: match ov.ornament_density {
            Option::Some(x) => x,
            Option::None => p.ornament_density,
        },
        name_variant_id: match ov.name_variant_id {
            Option::Some(x) => x,
            Option::None => p.name_variant_id,
        },
        use_countersubject: match ov.use_countersubject {
            Option::Some(x) => x,
            Option::None => p.use_countersubject,
        },
        ..p,
    }
}

/// A v1.1 score: its events (in voice-then-time generation order, each voice chronological), the
/// section length, and the parameters it was composed with.
#[derive(Drop)]
pub struct V11Score {
    pub events: Array<NoteEvent>,
    pub section_ticks: u32,
    pub params: BeastCompositionParams,
}

// ── rhythm cells: (start, duration, source) ──
fn cell(name: u8) -> Span<(u32, u32, u8)> {
    if name == 0 { // plain
        array![(0, 480, 0), (480, 480, 1), (960, 480, 2), (1440, 480, 3)].span()
    } else if name == 1 { // long
        array![(0, 960, 0), (960, 480, 2), (1440, 480, 3)].span()
    } else if name == 2 { // dotted
        array![(0, 720, 0), (720, 240, SRC_PASSING), (960, 480, 2), (1440, 480, 3)].span()
    } else if name == 3 { // run
        array![(0, 240, 0), (240, 240, SRC_PASSING), (480, 480, 1), (960, 480, 2), (1440, 480, 3)]
            .span()
    } else if name == 4 { // lilt
        array![(0, 480, 0), (480, 240, 1), (720, 240, SRC_PASSING), (960, 960, 2)].span()
    } else if name == 5 { // syncop
        array![(0, 480, 0), (480, 720, 1), (1200, 240, SRC_PASSING), (1440, 480, 3)].span()
    } else if name == 6 { // halves
        array![(0, 960, 0), (960, 960, 2)].span()
    } else { // cadence
        array![(0, 480, 0), (480, 480, 1), (960, 960, SRC_TONIC)].span()
    }
}

fn has_passing(name: u8) -> bool {
    name >= 2 && name <= 5
}

/// Cell families by `weakness % 3`: flowing, driving, heavy.
fn family(weakness: u8) -> Span<u8> {
    let w = weakness % 3;
    if w == 0 {
        array![0, 3, 4, 1].span()
    } else if w == 1 {
        array![0, 2, 5, 3].span()
    } else {
        array![0, 1, 2, 6].span()
    }
}

fn mix(h: u32, x: u32) -> u32 {
    let a: u64 = (h ^ x).into();
    let m: u32 = ((a * 0x9e3779b1) % 0x100000000).try_into().unwrap();
    m ^ (m / 0x8000)
}

fn sign(x: i32) -> i32 {
    if x > 0 {
        1
    } else if x < 0 {
        -1
    } else {
        0
    }
}

fn abs_i32(x: i32) -> i32 {
    if x < 0 {
        -x
    } else {
        x
    }
}

fn theme_rhythm(
    p: @BeastCompositionParams, degrees: Span<i32>, motif_seed: felt252,
) -> Array<Slot> {
    let groups = degrees.len() / 4;
    let fam = family(p.weakness);
    let seed: u256 = motif_seed.into();
    let mut h: u32 = (seed % 4294967291).try_into().unwrap();
    let mut slots: Array<Slot> = array![];
    let mut g: u32 = 0;
    while g < groups {
        h = mix(h, g + 1);
        let name = if g == groups - 1 {
            7
        } else if g == 0 {
            *fam.at(h % 2)
        } else {
            let n = *fam.at(h % 4);
            if has_passing(n) && (h / 256) % 8 >= p.ornament_density.into() + 2 {
                0
            } else {
                n
            }
        };
        for (start, duration, src) in cell(name) {
            let degree = if *src == SRC_TONIC {
                0
            } else if *src < 4 {
                *degrees.at(g * 4 + (*src).into())
            } else {
                0 // a passing note: set below
            };
            slots
                .append(
                    Slot {
                        time: g * BAR + *start, duration: *duration, src: *src, group: g, degree,
                    },
                );
        }
        g += 1;
    }
    // passing notes move toward the next slot: passing, upper neighbour or anticipation
    let n = slots.len();
    let mut out: Array<Slot> = array![];
    let mut i: u32 = 0;
    while i < n {
        let mut s = *slots.at(i);
        if s.src == SRC_PASSING {
            let a = slots.at(i - 1).degree;
            let b = if i + 1 < n {
                slots.at(i + 1).degree
            } else {
                0
            };
            let d = b - a;
            s.degree = if abs_i32(d) >= 2 {
                a + sign(d)
            } else if d == 0 {
                a + 1
            } else {
                b
            };
        }
        out.append(s);
        i += 1;
    }
    out
}

/// The theme's last bar steps to the tonic: [x, ±1, ±1, 0].
fn cadence_theme(degrees: Span<i32>) -> Array<i32> {
    let n = degrees.len();
    let step: i32 = if *degrees.at(n - 4) >= 0 {
        1
    } else {
        -1
    };
    let mut out: Array<i32> = array![];
    let mut i: u32 = 0;
    while i < n {
        out
            .append(
                if i == n - 3 || i == n - 2 {
                    step
                } else if i == n - 1 {
                    0
                } else {
                    *degrees.at(i)
                },
            );
        i += 1;
    }
    out
}

// ── key plan (same mode): the scale degree each section's theme starts on ──
fn reach(tier: u8) -> i32 {
    if tier == 1 {
        4
    } else if tier == 2 {
        3
    } else if tier == 3 {
        2
    } else {
        1
    }
}

fn fifths_plan(n: u32, r: i32) -> Array<i32> {
    if n <= 1 {
        return array![0];
    }
    if n == 2 {
        return array![0, if r >= 3 {
            r
        } else {
            1
        }];
    }
    if n == 3 {
        return if r >= 2 {
            array![0, r, 1]
        } else {
            array![0, 1, -1]
        };
    }
    let mut out: Array<i32> = array![0, 1, r];
    let mut last = r;
    while out.len() < n - 1 {
        last = if last - 1 > 1 {
            last - 1
        } else {
            1
        };
        out.append(last);
    }
    out.append(if r >= 2 {
        1
    } else {
        -1
    });
    out
}

/// Scale-degree shift per section (a diatonic fifth is 4 steps), in the nearest register.
fn degree_plan(p: @BeastCompositionParams, flip: bool) -> Array<i32> {
    let type_side: i32 = if p.weakness == 1 {
        -1
    } else {
        1
    };
    let side = if flip {
        -type_side
    } else {
        type_side
    };
    let mut out: Array<i32> = array![];
    for f in fifths_plan(p.section_count.into(), reach(p.tier)) {
        let dg = (f * side * 4 + 700) % 7;
        out.append(if dg > 3 {
            dg - 7
        } else {
            dg
        });
    }
    out
}

fn offsets(spacing: u8) -> Span<i32> {
    if spacing == 0 {
        array![0, -4, 7, -11].span()
    } else if spacing == 1 {
        array![0, -4, 3, -8].span()
    } else {
        array![0, -2, 2, -5].span()
    }
}

/// The placed notes on a 120-tick grid: (voice, cell) -> index into the section's notes + 1. Every
/// onset and length the voice checks see is a multiple of 120 ticks (asserted), and a voice's notes
/// never overlap, so a voice has at most one note per cell.
const CELL: u32 = 120;

/// The grid key of a voice's cell, `voice * 2^20 + cell`, in felt252 arithmetic: no overflow
/// checks. It is the same number as the u32 sum for voice ids below 4096 (`overlaps` asserts that
/// there are no more voices).
fn cell_key(voice: u32, cell: u32) -> felt252 {
    voice.into() * 0x100000 + cell.into()
}

/// Reserved grid key per voice (no section reaches this cell): the cell after the last cell of the
/// voice's placed notes so far (0: nothing placed yet). A voice that has not started, or whose
/// notes end before a new one starts, is skipped on this alone; its cells are not read.
const SPAN_END: u32 = 0xFFFFF;

/// Appends a note to the section and records it on the grid.
// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
fn put(ref out: Array<NoteEvent>, ref grid: Felt252Dict<u32>, e: NoteEvent) {
    assert(e.time % CELL == 0 && e.duration % CELL == 0 && e.duration > 0, 'v11: off grid');
    out.append(e);
    let idx = out.len();
    let first_cell = e.time / CELL;
    let end_cell = (e.time + e.duration) / CELL;
    let (entry, span_end) = grid.entry(cell_key(e.voice_id, SPAN_END));
    grid = entry.finalize(if end_cell > span_end {
        end_cell
    } else {
        span_end
    });
    // The note's cells, first_cell ..< end_cell, are one run of keys; there is at least one cell
    // (the assert), so the loop may check at its end. Four to a pass: a pass costs more than an
    // insert.
    let mut key = cell_key(e.voice_id, first_cell);
    let stop = cell_key(e.voice_id, end_cell);
    loop {
        grid.insert(key, idx);
        key += 1;
        if key == stop {
            break;
        }
        grid.insert(key, idx);
        key += 1;
        if key == stop {
            break;
        }
        grid.insert(key, idx);
        key += 1;
        if key == stop {
            break;
        }
        grid.insert(key, idx);
        key += 1;
        if key == stop {
            break;
        }
    }
}

/// The notes of the other voices that sound with a new note of `self_voice` (its own earlier notes
/// end before it starts), voice by voice and in time order within a voice, read off the grid: each
/// an `overlap` of its pitch, whether it meets the new note on a strong beat, and the interval
/// class of the previous note's pitch against that voice's note before (12 when there is none).
/// `has_prev`, `prev_pitch` and `prev_cell` describe the previous note.
fn overlaps(
    placed: Span<NoteEvent>,
    ref grid: Felt252Dict<u32>,
    voices: u32,
    self_voice: u32,
    time: u32,
    duration: u32,
    has_prev: bool,
    prev_pitch: u32,
    prev_cell: u32,
) -> Array<Overlap> {
    let mut ov: Array<Overlap> = array![];
    let end = time + duration;
    // `cell_key` has room for 4096 voices; past that its checked u32 predecessor panicked, so do we
    assert(voices <= 0x1000, 'u32_mul Overflow');
    let mut u: u32 = if self_voice == 0 {
        1
    } else {
        0
    };
    // a zero-length note covers no cell and overlaps nothing
    if duration == 0 || u >= voices {
        return ov;
    }
    // The new note covers the cells c0 ..= c1. Both loops below check at their end, which saves a
    // function call per pass over a `while`: a pass is certain for the voice (u < voices) and for
    // the cells (c0 <= c_last).
    let c0 = time / CELL;
    let c1 = (end - 1) / CELL;
    loop {
        // the cells before a voice's first note are empty, and those after its last are not read
        let span_end = grid.get(cell_key(u, SPAN_END));
        if span_end > c0 {
            let c_last = if span_end - 1 < c1 {
                span_end - 1
            } else {
                c1
            };
            let mut c = c0;
            loop {
                let idx = grid.get(cell_key(u, c));
                if idx == 0 {
                    c += 1;
                } else {
                    let q = *placed.at(idx - 1);
                    c = (q.time + q.duration) / CELL; // jump past this note
                    let strong = (if time > q.time {
                        time
                    } else {
                        q.time
                    }) % TU == 0;
                    let before_ic: u32 = if has_prev {
                        let b = grid.get(cell_key(u, prev_cell));
                        if b != 0 {
                            ic32(prev_pitch, (placed.at(b - 1).pitch).into())
                        } else {
                            12
                        }
                    } else {
                        12
                    };
                    ov.append(overlap(q.pitch, strong, before_ic));
                }
                if c > c_last {
                    break;
                }
            }
        }
        u += 1;
        if u == self_voice {
            u += 1;
        }
        if u >= voices {
            break;
        }
    }
    ov
}

/// How an interval scores, by (the candidate's pitch class - the other note's) % 12, twice over so
/// that the row for one other note is a slice of it: 0 consonant, 1 dissonant (2nds, tritone,
/// 7ths), 2 unison or octave, 3 perfect fifth if the candidate is not below the other note, 4
/// perfect fifth if it is. A fifth (|a - b| % 12 = 7) and a fourth (5, consonant) are told apart by
/// which note is higher; every other interval class is the same either way round.
const INTERVAL_KINDS: [u8; 24] = [
    2, 1, 1, 0, 0, 4, 1, 3, 0, 0, 1, 1, 2, 1, 1, 0, 0, 4, 1, 3, 0, 0, 1, 1,
];

/// A note sounding with the candidates, with what their scores need of it.
#[derive(Copy, Drop)]
struct Overlap {
    pitch: u32,
    /// The kinds of interval against this note by the candidate's pitch class: the 12 entries of
    /// `INTERVAL_KINDS` from 12 minus this note's pitch class on.
    kinds: Span<u8>,
    /// What a dissonance with it costs: 40 on a strong beat, 8 off it.
    dissonance: u32,
    /// The interval class of `prev` against this voice's note before, or 12 when there is none.
    before_ic: u32,
}

/// The overlap of a placed note of `pitch`, on a strong beat or not, with `before_ic`.
fn overlap(pitch: u8, strong: bool, before_ic: u32) -> Overlap {
    let pitch: u32 = pitch.into();
    Overlap {
        pitch,
        kinds: INTERVAL_KINDS.span().slice(12 - pitch % 12, 12),
        dissonance: if strong {
            40
        } else {
            8
        },
        before_ic,
    }
}

fn ic32(a: u32, b: u32) -> u32 {
    (if a > b {
        a - b
    } else {
        b - a
    }) % 12
}

/// What the overlapping note `o` adds to the score of the candidate `p` (pitch class `pc`) after
/// `prev_pitch`, in quarter points: 8 or 40 for a dissonance, 16 or 24 for an octave or unison, 2
/// for a perfect fifth, and 32 more for parallel octaves/unisons or fifths with what this voice and
/// the other had before.
// On purpose (gas): a call per overlap costs more than the body.
#[inline(always)]
fn overlap_points(o: Overlap, p: u32, pc: u32, prev_pitch: u32) -> u32 {
    let kind = *o.kinds.at(pc);
    if kind == 0 {
        0
    } else if kind == 1 {
        o.dissonance
    } else if kind == 2 {
        if o.before_ic == 0 && prev_pitch != p {
            if p == o.pitch {
                56
            } else {
                48
            }
        } else if p == o.pitch {
            24
        } else {
            16
        }
    } else {
        let fifth = if kind == 3 {
            p >= o.pitch
        } else {
            p < o.pitch
        };
        if !fifth {
            0
        } else if o.before_ic == 7 && prev_pitch != p {
            34
        } else {
            2
        }
    }
}

/// The first of the candidates (base score, pitch) with the lowest score against the overlapping
/// notes: the base, 12 for a leap of more than 9 semitones from the previous pitch, and the points
/// of every overlap. Scores in quarter points.
///
/// Bases are never negative (`near` and the followers' candidates: 0, 6 or 12; `dominant`: 3 times
/// a distance of at most 9), and no overlap or leap scores less than 0, so a score only grows as it
/// is added up. A candidate is dropped as soon as it goes past `limit`, the highest score that
/// beats the best so far (a tie goes to the earlier one), and no later candidate can beat a score
/// of 0.
fn best_candidate(
    cands: Span<(i32, u8)>, ov: Span<Overlap>, has_prev: bool, prev_pitch: u32,
) -> u8 {
    let mut best_pitch: u8 = 0;
    let mut limit = 0xFFFFFFFF_u32; // the first candidate always beats this
    for (base, pitch) in cands {
        let Some(mut left) = limit.checked_sub((*base).try_into().unwrap()) else {
            continue;
        };
        let p: u32 = (*pitch).into();
        if has_prev
            && (match p.checked_sub(prev_pitch) {
                Some(up) => up,
                None => prev_pitch - p,
            }) > 9 {
            let Some(rest) = left.checked_sub(12) else {
                continue;
            };
            left = rest;
        }
        let pc = p % 12;
        let mut beaten = false;
        for o in ov {
            match left.checked_sub(overlap_points(*o, p, pc, prev_pitch)) {
                Some(rest) => left = rest,
                None => {
                    beaten = true;
                    break;
                },
            }
        }
        if !beaten {
            let score = limit - left;
            best_pitch = *pitch;
            if score == 0 {
                break;
            }
            limit = score - 1;
        }
    }
    best_pitch
}

/// The candidate (base score, pitch) with the lowest score against everything placed so far in the
/// section; the first wins a tie. Scores in quarter points.
///
/// The notes sounding with the new one are read off the grid (each voice's cells across the new
/// note), and so is "the note before" (what that voice played when this voice played `prev`, for
/// the parallel-5ths check), together with that pair's interval: all once per call, not per
/// candidate.
/// The score is a sum, so this gives exactly the scores of checking every placed note per
/// candidate.
fn choose_pitch(
    cands: Span<(i32, u8)>,
    time: u32,
    duration: u32,
    placed: Span<NoteEvent>,
    ref grid: Felt252Dict<u32>,
    voices: u32,
    self_voice: u32,
    prev: Option<NoteEvent>,
) -> u8 {
    let (has_prev, prev_pitch, prev_cell): (bool, u32, u32) = match prev {
        Option::Some(ps) => (true, ps.pitch.into(), ps.time / CELL),
        Option::None => (false, 0, 0),
    };
    let ov = overlaps(
        placed, ref grid, voices, self_voice, time, duration, has_prev, prev_pitch, prev_cell,
    );
    best_candidate(cands, ov.span(), has_prev, prev_pitch)
}

/// How a voice maps a theme degree: the canon offset, or the mirror for an inverted second voice.
#[derive(Copy, Drop)]
struct VoiceMap {
    invert: bool,
    off: i32,
}

fn map_degree(m: VoiceMap, d: i32) -> i32 {
    if m.invert {
        4 - d
    } else {
        d + m.off
    }
}

#[derive(Copy, Drop)]
struct Realizer {
    shift: i32,
    /// Where degree 0 is in `table` (a felt, see `realize`).
    zero: felt252,
    tonic: u8,
    /// The mode's scale (`mode_scale`), looked up once per section: for the composer's diatonic
    /// modes `realize_degree(7, ..)` is exactly `degree_to_keynum` with it.
    scale: Span<u8>,
    /// `degree_to_keynum(d + shift, ..)` for the degrees it covers (TABLE_OCT_LO), computed once
    /// per section; none where that would panic (computed directly instead, so it still panics
    /// there).
    table: Span<Option<u8>>,
}

/// The table holds the octaves [TABLE_OCT_LO, TABLE_OCT_HI) of `degree_to_keynum`'s 7 biased
/// degrees: the shifted degrees [-21, 21), around the [-20, 15] the Genesis Tracks reach. A degree
/// outside it realizes the same pitch directly, only slower.
const TABLE_OCT_LO: u32 = 7;
const TABLE_OCT_HI: u32 = 13;
/// Where shifted degree 0 is in the table: 70 (`degree_to_keynum`'s bias) less the first octave's
/// 49 biased degrees.
const TABLE_ZERO: i32 = 21;

fn realizer(shift: i32, tonic: u8, scale: Span<u8>) -> Realizer {
    // Only the first seven degrees count, as in `degree_to_keynum`: a shorter scale panics here
    // with the same 'Index out of bounds'.
    let scale = scale.slice(0, 7);
    let mut table: Array<Option<u8>> = array![];
    let mut oct = TABLE_OCT_LO;
    while oct < TABLE_OCT_HI {
        let root: u32 = tonic.into() + 12 * oct;
        for semis in scale {
            // `degree_to_keynum`'s `total - 120` as a u8, where it neither underflows nor overflows
            let total = root + (*semis).into();
            table.append(if total >= 120 {
                (total - 120).try_into()
            } else {
                Option::None
            });
        }
        oct += 1;
    }
    Realizer { shift, zero: (shift + TABLE_ZERO).into(), tonic, scale, table: table.span() }
}

fn realize(r: Realizer, d: i32) -> u8 {
    // The index is in felts: below the table it wraps to a huge one that `try_into` rejects.
    match tabled(r.table, d.into() + r.zero) {
        Option::Some(pitch) => pitch,
        Option::None => degree_to_keynum(d + r.shift, r.tonic, r.scale),
    }
}

/// The table's pitch at `i`, if `i` is in the table and `degree_to_keynum` does not panic there.
fn tabled(table: Span<Option<u8>>, i: felt252) -> Option<u8> {
    *table.get(i.try_into()?)?.unbox()
}

/// The pitches at `base` and a step or two either side of it (`up` is the step: 1, or -1 mirrored),
/// scored by distance.
fn around(r: Realizer, base: i32, up: i32) -> Array<(i32, u8)> {
    let (above, below) = (base + up, base - up);
    array![
        (0, realize(r, base)), (6, realize(r, above)), (6, realize(r, below)),
        (12, realize(r, above + up)), (12, realize(r, below - up)),
    ]
}

/// Candidates a step or two around a degree (mapped by the voice), scored by distance.
fn near(r: Realizer, m: VoiceMap, deg: i32) -> Array<(i32, u8)> {
    around(r, map_degree(m, deg), if m.invert {
        -1
    } else {
        1
    })
}

fn place(
    ref out: Array<NoteEvent>,
    ref grid: Felt252Dict<u32>,
    voices: u32,
    ref prev: Option<NoteEvent>,
    time: u32,
    duration: u32,
    cands: Span<(i32, u8)>,
    voice: u32,
) {
    let pitch = choose_pitch(cands, time, duration, out.span(), ref grid, voices, voice, prev);
    let e = NoteEvent { time, duration, pitch, velocity: 90, voice_id: voice };
    put(ref out, ref grid, e);
    prev = Option::Some(e);
}

/// `pcs[i]`, or 12, which no pitch class equals, past the end.
fn class_at(pcs: Span<u8>, i: u32) -> u32 {
    match pcs.get(i) {
        Option::Some(pc) => (*pc.unbox()).into(),
        Option::None => 12,
    }
}

/// Whether `pc` is one of `pcs`.
fn has_class(pcs: Span<u8>, pc: u32) -> bool {
    for x in pcs {
        if (*x).into() == pc {
            return true;
        }
    }
    false
}

/// Pitches within 9 semitones of `from` whose pitch class is in `pcs`, scored by distance.
///
/// Walks the window upwards in u32, counting the pitch class `pc` along (a signed `%` and a scan
/// of `pcs` for every pitch cost most). A pitch is compared with the first three classes of
/// `pcs` (a chord has one or three), and only a longer `pcs` is searched.
fn dominant(from: u8, pcs: Span<u8>) -> Array<(i32, u8)> {
    let mut c: Array<(i32, u8)> = array![];
    let f: u32 = from.into();
    // from f - 9 (or 0, as no pitch is negative) to f + 9
    let mut m = if f > 9 {
        f - 9
    } else {
        0
    };
    let end = f + 10;
    let mut pc = m % 12;
    let (first, second, third) = (class_at(pcs, 0), class_at(pcs, 1), class_at(pcs, 2));
    let more = pcs.len() > 3;
    while m != end {
        if pc == first || pc == second || pc == third || (more && has_class(pcs, pc)) {
            let distance = if m > f {
                m - f
            } else {
                f - m
            };
            c.append(((3 * distance).try_into().unwrap(), m.try_into().unwrap()));
        }
        pc = if pc == 11 {
            0
        } else {
            pc + 1
        };
        m += 1;
    }
    if c.len() == 0 {
        c.append((0, from));
    }
    c
}

/// From the end of a voice's line to the section end: fill to the barline stepping toward the
/// sequence, then sequence bars of the head motif, then a half cadence on the next key's dominant.
fn episode(
    ref out: Array<NoteEvent>,
    ref grid: Felt252Dict<u32>,
    voices: u32,
    voice: u32,
    m: VoiceMap,
    last: NoteEvent,
    head: Span<Slot>,
    dir: i32,
    end: u32,
    offset: u32,
    r: Realizer,
    pcs: Span<u8>,
) {
    let mut prev: Option<NoteEvent> = Option::Some(last);
    let mut t = last.time + last.duration;
    if t + 240 > end {
        return;
    }
    let head0 = head.at(0).degree;
    let next_bar = offset + ((t - offset + BAR - 1) / BAR) * BAR;
    let full_bars = if end >= next_bar {
        (end - next_bar) / BAR
    } else {
        0
    };
    let seq_bars = if full_bars > 0 {
        full_bars - 1
    } else {
        0
    };
    // 1. up to the barline: quarters (or one shorter note) leading to the sequence's first note
    let target1 = head0 + dir;
    let stop = if next_bar < end {
        next_bar
    } else {
        end
    };
    while t < stop && full_bars > 0 {
        let to_beat = TU - (t - offset) % TU;
        let d = if to_beat < next_bar - t {
            to_beat
        } else {
            next_bar - t
        };
        let beats_left: u32 = (next_bar - t + TU - 1) / TU;
        let back: i32 = if beats_left > 0 {
            (beats_left - 1).try_into().unwrap()
        } else {
            0
        };
        place(
            ref out,
            ref grid,
            voices,
            ref prev,
            t,
            d,
            near(r, m, target1 - dir * back).span(),
            voice,
        );
        t += d;
    }
    // 2. sequence: the head motif, a step further each bar
    let mut k: u32 = 1;
    while k <= seq_bars {
        let shift = dir * k.try_into().unwrap();
        for h in head {
            place(
                ref out,
                ref grid,
                voices,
                ref prev,
                t + h.time,
                h.duration,
                near(r, m, h.degree + shift).span(),
                voice,
            );
        }
        t += BAR;
        k += 1;
    }
    // 3. half cadence into the next section: two steps, then the next key's dominant chord tone
    if t >= end {
        return;
    }
    let left = end - t;
    let sb: i32 = (seq_bars + 1).try_into().unwrap();
    if left >= BAR {
        place(
            ref out, ref grid, voices, ref prev, t, TU, near(r, m, head0 + dir * sb).span(), voice,
        );
        place(
            ref out,
            ref grid,
            voices,
            ref prev,
            t + TU,
            TU,
            near(r, m, head0 + dir * sb - dir).span(),
            voice,
        );
        let from = prev.unwrap().pitch;
        place(
            ref out,
            ref grid,
            voices,
            ref prev,
            t + 2 * TU,
            left - 2 * TU,
            dominant(from, pcs).span(),
            voice,
        );
    } else {
        let from = prev.unwrap().pitch;
        place(ref out, ref grid, voices, ref prev, t, left, dominant(from, pcs).span(), voice);
    }
}

fn build_section(
    p: @BeastCompositionParams,
    theme: Span<i32>,
    slots_in: Span<Slot>,
    s: u32,
    offset: u32,
    cs_seed: felt252,
    section_ticks: u32,
    plan: Span<i32>,
    tr: Trajectory,
    scale_override: Option<Span<u8>>,
) -> Array<NoteEvent> {
    // development: sections after the first follow the Beast's dominant history
    let dev = if s > 0 {
        tr.development
    } else {
        DEV_SEQUENCE
    };
    let lag: u32 = if s > 0 && dev == DEV_STRETTO {
        if p.stretto_lag > 2 {
            p.stretto_lag - 1
        } else {
            1
        }
    } else {
        p.stretto_lag
    };
    let mut slots: Array<Slot> = array![];
    if s > 0 && dev == DEV_STRETTO {
        // faster: long notes split, the second half a step up
        for sl in slots_in {
            let sl = *sl;
            if sl.duration >= 960 {
                let half = sl.duration / 2;
                slots.append(Slot { duration: half, ..sl });
                slots
                    .append(
                        Slot { time: sl.time + half, duration: half, degree: sl.degree + 1, ..sl },
                    );
            } else {
                slots.append(sl);
            }
        }
    } else if s > 0 && dev == DEV_INVERSION {
        // mirrored around the first degree, passing notes absorbed: calmer; still ends on the tonic
        let d0 = slots_in.at(0).degree;
        let mut kept: Array<Slot> = array![];
        for sl in slots_in {
            if sl.src != SRC_PASSING && sl.src != SRC_TRILL {
                kept.append(*sl);
            }
        }
        let n = kept.len();
        let mut i: u32 = 0;
        while i < n {
            let sl = *kept.at(i);
            let end = if i + 1 < n {
                kept.at(i + 1).time
            } else {
                sl.time + sl.duration
            };
            let degree = if i == n - 1 {
                0
            } else {
                2 * d0 - sl.degree
            };
            slots.append(Slot { degree, duration: end - sl.time, ..sl });
            i += 1;
        }
    } else {
        for sl in slots_in {
            slots.append(*sl);
        }
    }
    let slots = slots.span();
    let offs = offsets(tr.spacing);
    let sc: u32 = p.section_count.into();
    let next = if s + 1 < sc {
        s + 1
    } else {
        0
    };
    let mode = canonical_to_melodic_mode(p.mode_id);
    let home = transposed_tonic(p.tonic_keynum, 0);
    let scale = match scale_override {
        Option::Some(sc) => sc,
        Option::None => mode_scale(mode),
    };
    let r = realizer(*plan.at(s % plan.len()), home, scale);
    let next_shift = *plan.at(next % plan.len());
    let mut out: Array<NoteEvent> = array![];
    let mut grid: Felt252Dict<u32> = Default::default();
    // canon voices, then the countersubject's voice id
    let voices = p.voice_count + if p.use_countersubject {
        1
    } else {
        0
    };
    // per voice: its map, offset and last note (the countersubject last, with offset 99)
    let mut maps: Array<VoiceMap> = array![];
    let mut offs_used: Array<i32> = array![];
    let mut lasts: Array<NoteEvent> = array![];
    let mut v: u32 = 0;
    while v < p.voice_count {
        let entry = v * lag * TU;
        let off = if v < 4 {
            *offs.at(v)
        } else {
            *offs.at(3)
        };
        let m = VoiceMap { invert: p.use_inversion && v == 1, off };
        let mut prev: Option<NoteEvent> = Option::None;
        for sl in slots {
            let base = map_degree(m, sl.degree);
            let time = offset + entry + sl.time;
            let pitch = if v == 0 {
                realize(r, base)
            } else {
                let cands = around(r, base, 1);
                choose_pitch(cands.span(), time, sl.duration, out.span(), ref grid, voices, v, prev)
            };
            let e = NoteEvent { time, duration: sl.duration, pitch, velocity: 90, voice_id: v };
            put(ref out, ref grid, e);
            prev = Option::Some(e);
        }
        maps.append(m);
        offs_used.append(off);
        lasts.append(prev.unwrap());
        v += 1;
    }
    let mut cs_head: Array<Slot> = array![];
    if p.use_countersubject {
        // v1's countersubject in steady quarters against the rhythmic subject, voice-checked
        let cs = generate_countersubject(
            theme, @default_countersubject_config(), cs_seed, 7, mode, home, TU,
        );
        let mut prev: Option<NoteEvent> = Option::None;
        let mut i: u32 = 0;
        let ident = VoiceMap { invert: false, off: 0 };
        for d in cs.degrees.span() {
            let time = offset + i * TU;
            let cands = near(r, ident, *d);
            let pitch = choose_pitch(
                cands.span(), time, TU, out.span(), ref grid, voices, p.voice_count, prev,
            );
            let e = NoteEvent { time, duration: TU, pitch, velocity: 90, voice_id: p.voice_count };
            put(ref out, ref grid, e);
            prev = Option::Some(e);
            if i < 4 {
                cs_head.append(Slot { time: i * TU, duration: TU, src: 0, group: 0, degree: *d });
            }
            i += 1;
        }
        maps.append(ident);
        offs_used.append(99);
        lasts.append(prev.unwrap());
    }
    // episodes: every voice fills from the end of its line to the next section
    let section_end = offset + section_ticks;
    let dir: i32 = if tr.direction != 0 {
        tr.direction
    } else if s % 2 == 1 {
        -1
    } else {
        1
    };
    let mut bass: i32 = 99;
    for o in offs_used.span() {
        if *o < bass {
            bass = *o;
        }
    }
    let mut head: Array<Slot> = array![];
    for sl in slots {
        if sl.group == 0 {
            head.append(*sl);
        }
    }
    // the half cadence's target: the next section's dominant chord (bass: its 5th)
    let fifth = degree_to_keynum(4 + next_shift, home, scale) % 12;
    let dom_bass: Array<u8> = array![fifth];
    let dom_chord: Array<u8> = array![
        fifth, degree_to_keynum(6 + next_shift, home, scale) % 12,
        degree_to_keynum(1 + next_shift, home, scale) % 12,
    ];
    let nvo = lasts.len();
    let mut x: u32 = 0;
    while x < nvo {
        let is_cs = p.use_countersubject && x == nvo - 1;
        let h = if is_cs {
            cs_head.span()
        } else {
            head.span()
        };
        let pcs = if *offs_used.at(x) == bass {
            dom_bass.span()
        } else {
            dom_chord.span()
        };
        episode(
            ref out,
            ref grid,
            voices,
            x,
            *maps.at(x),
            *lasts.at(x),
            h,
            dir,
            section_end,
            offset,
            r,
            pcs,
        );
        x += 1;
    }
    out
}

fn trajectory(
    beast: PackableBeastV3,
    params: @BeastCompositionParams,
    swapped: BeastV3LiveState,
    structural: BeastV3LiveState,
    real: BeastV3LiveState,
) -> Trajectory {
    let k = swapped.adventurers_killed;
    let d = swapped.scars;
    let st = v3_music_state(structural);
    let rs = v3_music_state(real);
    let kb = st.kill_bucket;
    let db = st.defeat_bucket;
    let _ = params;
    Trajectory {
        direction: if k > d {
            1
        } else if k < d {
            -1
        } else {
            0
        },
        development: if kb >= db + 2 {
            DEV_STRETTO
        } else if db >= 1 && db >= kb {
            DEV_INVERSION
        } else {
            DEV_SEQUENCE
        },
        spacing: if beast.level >= 100 || beast.health >= 500 {
            0
        } else if beast.level < 20 && beast.health < 120 {
            2
        } else {
            1
        },
        prominence: if rs.is_crown {
            3
        } else if rs.rank_tier <= 1 {
            2
        } else if rs.rank_tier == 2 {
            1
        } else {
            0
        },
        trill: if is_genesis(beast) {
            false
        } else {
            prefix2_ornament_policy(beast.suffix - 1).allow_trill
        },
    }
}

/// Consecutive events of one voice in one section, with their pitch range. `key` identifies the
/// voice and section in `shape`'s dictionary, `start` is the tick the section starts at.
#[derive(Copy, Drop)]
struct Stretch {
    voice: u32,
    key: felt252,
    start: u32,
    len: u32,
    lo: u8,
    hi: u8,
}

/// The stretch at the front of `events`, which are not empty.
fn stretch_at(events: Span<NoteEvent>, section_ticks: u32) -> Stretch {
    let first = events.at(0);
    let section = first.time / section_ticks;
    let start = section * section_ticks;
    let key: felt252 = (first.voice_id * 4096 + section).into();
    let mut stretch = Stretch { voice: first.voice_id, key, start, len: 0, lo: 255, hi: 0 };
    for e in events {
        if e.voice_id != stretch.voice || e.time < start || e.time - start >= section_ticks {
            break;
        }
        stretch.len += 1;
        if e.pitch < stretch.lo {
            stretch.lo = e.pitch;
        }
        if e.pitch > stretch.hi {
            stretch.hi = e.pitch;
        }
    }
    stretch
}

/// Phrase arc per voice and section, accents on bar downbeats (the first bar of each pair harder),
/// the lead's prominence, articulation by profile, under the velocity ceiling.
///
/// The events come in a few long stretches (a voice's line, then its episode, in each section), so
/// the pitch range of a voice and section is looked up once per stretch, and what depends only on
/// the stretch is worked out once, not once per event.
fn shape(
    ref events: Array<NoteEvent>, p: @BeastCompositionParams, section_ticks: u32, prominence: u32,
) {
    let ceil: u32 = if p.velocity_ceiling == 0 {
        127
    } else {
        p.velocity_ceiling.into()
    };
    let profile = p.articulation_profile;
    let all = events.span();
    // pass 1: the stretches, and the pitch range of each voice and section over its stretches
    // (0 until seen, then 1 + lo + 256 * hi)
    let mut ranges: Felt252Dict<u32> = Default::default();
    let mut stretches: Array<Stretch> = array![];
    let mut at = 0;
    while at < all.len() {
        let s = stretch_at(all.slice(at, all.len() - at), section_ticks);
        let (entry, packed) = ranges.entry(s.key);
        let mut lo: u32 = s.lo.into();
        let mut hi: u32 = s.hi.into();
        if packed != 0 {
            let (h, l) = DivRem::div_rem(packed - 1, 256);
            if l < lo {
                lo = l;
            }
            if h > hi {
                hi = h;
            }
        }
        ranges = entry.finalize(1 + lo + 256 * hi);
        stretches.append(s);
        at += s.len;
    }
    // pass 2: the velocity and duration of each event
    let mut out: Array<NoteEvent> = array![];
    let mut at = 0;
    for s in stretches {
        let (h, l) = DivRem::div_rem(ranges.get(s.key) - 1, 256);
        let lead = s.voice == 0;
        let base: u32 = if lead {
            80 + 4 * prominence
        } else {
            70 - 2 * prominence
        };
        // the arc divides by twice the spread; a single pitch sits at the middle
        let spread = h - l;
        let arc_den: Option<NonZero<u32>> = (2 * spread).try_into();
        for e in all.slice(at, s.len) {
            let e = *e;
            let arc: u32 = match arc_den {
                Option::Some(den) => {
                    let (arc, _) = DivRem::div_rem(32 * (e.pitch.into() - l) + spread, den);
                    arc
                },
                Option::None => 8,
            };
            let mut v: u32 = base + arc;
            if e.time % BAR == 0 {
                v += if ((e.time - s.start) / BAR) % 2 == 0 {
                    12
                } else {
                    4
                };
                if lead {
                    v += 2 * prominence;
                }
            }
            let vel: u8 = (if v > ceil {
                ceil
            } else if v < 1 {
                1
            } else {
                v
            }).try_into().unwrap();
            let duration = if profile == 1 {
                let x = e.duration / 2;
                if x > 60 {
                    x
                } else {
                    60
                }
            } else if profile == 5 {
                let x = e.duration * 3 / 4;
                if x > 60 {
                    x
                } else {
                    60
                }
            } else {
                e.duration
            };
            out.append(NoteEvent { velocity: vel, duration, ..e });
        }
        at += s.len;
    }
    events = out;
}

/// The v1.1 score for a Beast and its live state.
pub fn build_v11_score(beast: PackableBeastV3, live: BeastV3LiveState) -> V11Score {
    build_v11_score_with(beast, live, no_override())
}

/// The v1.1 score with overrides on the mapped parameters (engine_v11.js `render` with `override`).
pub fn build_v11_score_with(
    beast: PackableBeastV3, live: BeastV3LiveState, ov: V11Override,
) -> V11Score {
    // Boxed for CASM size: the body's panic exits then write 2 felts, not the whole value.
    build_v11_score_with_boxed(beast, live, ov).unbox()
}

#[inline(never)]
fn build_v11_score_with_boxed(
    beast: PackableBeastV3, live: BeastV3LiveState, ov: V11Override,
) -> Box<V11Score> {
    // history: kills and defeats swapped; the structure is composed with a neutral rank (the real
    // rank sets only prominence)
    let swapped = BeastV3LiveState {
        adventurers_killed: live.scars, scars: live.adventurers_killed, ..live,
    };
    let sc = live.species_count;
    let structural = BeastV3LiveState {
        rank: if sc > 2 {
            sc
        } else {
            2
        }, species_count: if sc == 0 {
            1
        } else {
            sc
        }, ..swapped,
    };
    let p0 = map_v3_beast_to_composition_params(beast, structural);
    let seeds = derive_beast_sound_seeds(beast_sound_seed(beast.id, beast.prefix, beast.suffix));
    let theme_v1 = build_beast_theme(p0, seeds.motif_seed);
    let theme = cadence_theme(theme_v1.degrees.span());
    let mut tr = trajectory(beast, @p0, swapped, structural, live);
    if let Option::Some(t) = ov.trill {
        tr.trill = t;
    }
    if let Option::Some(x) = ov.development {
        tr.development = x;
    }
    if let Option::Some(x) = ov.direction {
        tr.direction = x;
    }
    if let Option::Some(x) = ov.spacing {
        tr.spacing = x;
    }
    let p = apply_override(p0, ov);
    let rhythm_seed = match ov.rhythm_seed {
        Option::Some(x) => x,
        Option::None => seeds.motif_seed,
    };
    let mut slots = theme_rhythm(@p, theme.span(), rhythm_seed);
    if tr.trill {
        // a trill (upper neighbour and back) replaces each passing note of an eighth or longer
        let mut out: Array<Slot> = array![];
        let n = slots.len();
        let mut i: u32 = 0;
        while i < n {
            let sl = *slots.at(i);
            if sl.src == SRC_PASSING && sl.duration >= 240 {
                let half = sl.duration / 2;
                let before = slots.at(i - 1).degree;
                out.append(Slot { src: SRC_TRILL, duration: half, degree: before + 1, ..sl });
                out
                    .append(
                        Slot {
                            src: SRC_TRILL,
                            time: sl.time + half,
                            duration: half,
                            degree: before,
                            ..sl,
                        },
                    );
            } else {
                out.append(sl);
            }
            i += 1;
        }
        slots = out;
    }
    // even: the canon's end plus an episode of 1 or 2 bars, whichever makes the section even
    let mut theme_end: u32 = 0;
    for sl in slots.span() {
        if sl.time + sl.duration > theme_end {
            theme_end = sl.time + sl.duration;
        }
    }
    let canon_end = theme_end + (p.voice_count - 1) * p.stretto_lag * TU;
    let base = (canon_end + BAR - 1) / BAR;
    let section_ticks = (if (base + 1) % 2 == 0 {
        base + 1
    } else {
        base + 2
    }) * BAR;
    let cs_seed = core::poseidon::poseidon_hash_span(
        array![p.name_variant_id.into(), p.species_id.into()].span(),
    );
    let plan = degree_plan(@p, ov.flip_side == Option::Some(true));
    let mut events: Array<NoteEvent> = array![];
    let sc8: u32 = p.section_count.into();
    let mut s: u32 = 0;
    while s < sc8 {
        let sec = build_section(
            @p,
            theme.span(),
            slots.span(),
            s,
            s * section_ticks,
            cs_seed,
            section_ticks,
            plan.span(),
            tr,
            ov.scale,
        );
        events.append_span(sec.span());
        s += 1;
    }
    shape(ref events, @p, section_ticks, tr.prominence);
    BoxTrait::new(V11Score { events, section_ticks, params: p })
}

/// The v1.1 score as a form for the MIDI writers (no score hash: the self-contained writer does not
/// use it).
pub fn v11_form(score: @V11Score) -> BeastForm {
    let sc = score.params.section_count;
    let mut events: Array<NoteEvent> = array![];
    events.append_span(score.events.span());
    BeastForm {
        events, score_hash: 0, section_count: sc, length_ticks: sc.into() * score.section_ticks,
    }
}

/// The v1.1 score as the self-contained file for onchain-midi-player (programs, pan, drums:
/// crate::composition::full_midi) with the instruments by Beast, and the mega arrangement when the
/// Beast is mega (shiny):
/// what BeastMidiProvider.get_midi returns. Byte-identical to `beastSoundMidi` in
/// offchain/beast-sound/src/full_midi.js.
pub fn v11_score_full_smf_bytes(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<u8> {
    let score = build_v11_score(beast, live);
    let form = v11_form(@score);
    crate::composition::full_midi::beast_form_to_full_smf_bytes(
        @form,
        score.params.tempo_us,
        score.params.tier,
        Option::Some(
            crate::composition::full_midi::Voicing {
                beast_type: beast.beast_type,
                species_id: score.params.species_id,
                name_variant_id: score.params.name_variant_id,
                voice_count: score.params.voice_count,
                use_countersubject: score.params.use_countersubject,
            },
        ),
        beast.shiny == 1,
        crate::composition::full_midi::mega_lead_pick(
            score.params.species_id, score.params.name_variant_id,
        ),
    )
}

/// The same, packed 31 bytes per felt after the byte length.
pub fn v11_score_full_midi(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252> {
    midi::pack::to_felt252_array(v11_score_full_smf_bytes(beast, live).span())
}

#[cfg(test)]
mod realizer_tests {
    use crate::composition::genesis::named_mode_scale;
    use crate::composition::melodic_canon::{degree_to_keynum, mode_scale};
    use super::{
        TABLE_OCT_HI, TABLE_OCT_LO, TABLE_ZERO, VoiceMap, around, map_degree, near, realize,
        realizer, tabled,
    };

    /// Every scale the composer realizes with: the modes `canonical_to_melodic_mode` gives (Dorian,
    /// Phrygian, Aeolian) and `genesis::named_mode_scale`'s.
    fn scales() -> Array<Span<u8>> {
        let mut scales: Array<Span<u8>> = array![];
        for mode in array![1_u8, 2, 5] {
            scales.append(mode_scale(mode));
        }
        for id in array![4_u8, 5, 6, 7, 8, 26] {
            scales.append(named_mode_scale(id).unwrap());
        }
        scales
    }

    /// `degree_to_keynum`'s pitch, none where it panics: the same steps, checked.
    fn keynum(degree: i32, tonic: u8, scale: Span<u8>) -> Option<u8> {
        let du: u32 = (degree + 70).try_into()?;
        let total: u32 = tonic.into() + 12 * (du / 7) + (*scale.at(du % 7)).into();
        if total >= 120 {
            (total - 120).try_into()
        } else {
            Option::None
        }
    }

    #[test]
    fn table_covers_the_octaves_it_says() {
        let r = realizer(0, 60, mode_scale(5));
        assert!(r.table.len() == 7 * (TABLE_OCT_HI - TABLE_OCT_LO));
        assert!(TABLE_ZERO == 70 - 7 * TABLE_OCT_LO.try_into().unwrap());
    }

    /// Over every scale, tonic (`transposed_tonic`'s 24..=96) and shift (`degree_plan`'s -3..=3),
    /// and the degrees well past the table on both sides: the table holds exactly the pitches
    /// `degree_to_keynum` returns without panicking, and `realize` returns them.
    #[test]
    #[available_gas(100000000000)]
    fn realize_is_degree_to_keynum() {
        for scale in scales().span() {
            let mut tonic: u8 = 24;
            while tonic <= 96 {
                let mut shift: i32 = -3;
                while shift <= 3 {
                    let r = realizer(shift, tonic, *scale);
                    let mut d: i32 = -28;
                    while d < 28 {
                        let want = keynum(d + shift, tonic, *scale);
                        let in_table = d + shift >= -TABLE_ZERO && d + shift < TABLE_ZERO;
                        let tabled = tabled(r.table, d.into() + r.zero);
                        assert!(tabled == if in_table {
                            want
                        } else {
                            Option::None
                        });
                        if let Option::Some(pitch) = want {
                            assert!(degree_to_keynum(d + shift, tonic, *scale) == pitch);
                            assert!(realize(r, d) == pitch);
                        }
                        d += 1;
                    }
                    shift += 1;
                }
                tonic += 1;
            }
        }
    }

    #[test]
    #[should_panic(expected: ('Index out of bounds',))]
    fn a_scale_of_six_degrees_panics() {
        realizer(0, 60, mode_scale(7));
    }

    #[test]
    #[should_panic(expected: ('u32_sub Overflow',))]
    fn a_pitch_below_zero_panics() {
        // 24 less two octaves and a bit: tabled as none, then `degree_to_keynum`'s subtraction
        realize(realizer(0, 24, mode_scale(5)), -21);
    }

    #[test]
    #[should_panic(expected: ('Option::unwrap failed.',))]
    fn a_pitch_above_255_panics() {
        let loud = array![255_u8, 255, 255, 255, 255, 255, 255];
        realize(realizer(0, 96, loud.span()), 0);
    }

    #[test]
    #[should_panic(expected: ('Option::unwrap failed.',))]
    fn a_degree_below_the_bias_panics() {
        realize(realizer(0, 60, mode_scale(5)), -100);
    }

    /// The candidates of a degree, in the order `choose_pitch` breaks ties by: each mapped
    /// separately (the original `near`), and around an already mapped degree.
    #[test]
    fn candidates_keep_their_order() {
        let r = realizer(2, 60, mode_scale(5));
        let mut off: i32 = -11;
        while off <= 7 {
            let mut deg: i32 = -12;
            while deg <= 12 {
                for invert in array![false, true] {
                    let m = VoiceMap { invert, off };
                    let want = array![
                        (0, realize(r, map_degree(m, deg))),
                        (6, realize(r, map_degree(m, deg + 1))),
                        (6, realize(r, map_degree(m, deg - 1))),
                        (12, realize(r, map_degree(m, deg + 2))),
                        (12, realize(r, map_degree(m, deg - 2))),
                    ];
                    assert!(near(r, m, deg).span() == want.span());
                }
                let want = array![
                    (0, realize(r, deg)), (6, realize(r, deg + 1)), (6, realize(r, deg - 1)),
                    (12, realize(r, deg + 2)), (12, realize(r, deg - 2)),
                ];
                assert!(around(r, deg, 1).span() == want.span());
                deg += 1;
            }
            off += 1;
        }
    }
}

/// `choose_pitch`'s scoring against the original one: every candidate's score added up in i32, the
/// interval class from `ic32` and a 12-entry table of kinds.
#[cfg(test)]
mod scoring_tests {
    use super::{Overlap, best_candidate, ic32, overlap, overlap_points};

    /// What an overlapping note added to a candidate's score in the original.
    fn reference_points(p: u32, qp: u32, strong: bool, before_ic: u32, prev_pitch: u32) -> i32 {
        let kinds = array![2, 1, 1, 0, 0, 0, 1, 3, 0, 0, 1, 1].span();
        let ic = ic32(p, qp);
        let kind = *kinds.at(ic);
        let mut score: i32 = 0;
        if kind == 1 {
            score += if strong {
                40
            } else {
                8
            };
        } else if kind == 2 {
            score += if p == qp {
                24
            } else {
                16
            };
            if before_ic == ic && prev_pitch != p {
                score += 32;
            }
        } else if kind == 3 {
            score += 2;
            if before_ic == ic && prev_pitch != p {
                score += 32;
            }
        }
        score
    }

    /// The original candidate loop: every score in full, the first lowest wins.
    fn reference_best(
        cands: Span<(i32, u8)>, ov: Span<(u32, bool, u32)>, has_prev: bool, prev_pitch: u32,
    ) -> u8 {
        let mut best_pitch: u8 = 0;
        let mut best_score: i32 = 0;
        let mut first = true;
        for (base, pitch) in cands {
            let p: u32 = (*pitch).into();
            let mut score = *base;
            for item in ov {
                let (qp, strong, before_ic) = *item;
                score += reference_points(p, qp, strong, before_ic, prev_pitch);
            }
            if has_prev && (if p > prev_pitch {
                p - prev_pitch
            } else {
                prev_pitch - p
            }) > 9 {
                score += 12;
            }
            if first || score < best_score {
                best_score = score;
                best_pitch = *pitch;
                first = false;
            }
        }
        best_pitch
    }

    /// Every pair of pitches in `lo..=hi`, with the voice's previous pitch repeated or not, against
    /// the `before_ic` values that matter (none, unison/octave, fifth, other) and both beats.
    fn check_points(lo: u32, hi: u32) {
        let before_ics = array![0, 7, 12, 3].span();
        let mut p = lo;
        while p <= hi {
            let prev_pitches = array![p, if p > 0 {
                p - 1
            } else {
                1
            }];
            let mut qp = lo;
            while qp <= hi {
                for before_ic in before_ics {
                    for prev_pitch in prev_pitches.span() {
                        for strong in array![false, true].span() {
                            let o = overlap(qp.try_into().unwrap(), *strong, *before_ic);
                            let expected: u32 = reference_points(
                                p, qp, *strong, *before_ic, *prev_pitch,
                            )
                                .try_into()
                                .unwrap();
                            assert(
                                overlap_points(o, p, p % 12, *prev_pitch) == expected,
                                'points differ',
                            );
                        }
                    }
                }
                qp += 1;
            }
            p += 1;
        }
    }

    /// All octave and note-order combinations of the 12 pitch classes.
    #[test]
    fn overlap_points_match_original_low() {
        check_points(0, 36);
    }

    /// The top of the u8 pitch range, which nothing but the types bounds.
    #[test]
    fn overlap_points_match_original_high() {
        check_points(219, 255);
    }

    fn next(ref state: u64) -> u32 {
        state = (state * 1103515245 + 12345) % 2147483648;
        (state / 65536).try_into().unwrap()
    }

    /// Random candidates (the bases of `near` and `dominant`), overlaps and previous pitches: the
    /// same pitch is chosen, ties included.
    #[test]
    fn best_candidate_matches_original() {
        let mut state: u64 = 20260101;
        let before_ics = array![0, 7, 12, 3, 5, 0, 7, 12].span();
        let mut trial: u32 = 0;
        while trial < 1500 {
            let centre = if trial % 10 == 9 {
                225
            } else {
                36 + next(ref state) % 60
            };
            let mut cands: Array<(i32, u8)> = array![];
            let n_cands = 1 + next(ref state) % 8;
            let mut i: u32 = 0;
            while i < n_cands {
                let base: i32 = if next(ref state) % 2 == 0 {
                    (*array![0, 6, 6, 12, 12].span().at(i % 5))
                } else {
                    (3 * (next(ref state) % 10)).try_into().unwrap()
                };
                let pitch: u8 = (centre + next(ref state) % 25 - 12).try_into().unwrap();
                cands.append((base, pitch));
                i += 1;
            }
            let mut ov: Array<Overlap> = array![];
            let mut ov_ref: Array<(u32, bool, u32)> = array![];
            let n_ov = next(ref state) % 7;
            let mut j: u32 = 0;
            while j < n_ov {
                let qp: u8 = (centre + next(ref state) % 31 - 15).try_into().unwrap();
                let strong = next(ref state) % 2 == 0;
                let before_ic = *before_ics.at(next(ref state) % 8);
                ov.append(overlap(qp, strong, before_ic));
                ov_ref.append((qp.into(), strong, before_ic));
                j += 1;
            }
            let has_prev = next(ref state) % 4 != 0;
            let prev_pitch = if has_prev {
                centre + next(ref state) % 31 - 15
            } else {
                0
            };
            assert(
                best_candidate(
                    cands.span(), ov.span(), has_prev, prev_pitch,
                ) == reference_best(cands.span(), ov_ref.span(), has_prev, prev_pitch),
                'pitch differs',
            );
            trial += 1;
        }
    }
}

/// The grid against the one it replaced: the same notes put into both must give the same
/// overlapping notes for every query.
#[cfg(test)]
mod grid_tests {
    use core::dict::{Felt252Dict, Felt252DictTrait};
    use crate::composition::melodic_canon::NoteEvent;
    use super::{CELL, Overlap, TU, cell_key, ic32, overlap, overlaps, put};

    // The earlier grid: u32 keys, and the first and last tick of each voice's notes, plus 1.
    const OLD_SPAN_START: u32 = 0xFFFFE;
    const OLD_SPAN_END: u32 = 0xFFFFF;

    fn old_key(voice: u32, cell: u32) -> felt252 {
        (voice * 0x100000 + cell).into()
    }

    fn old_put(ref out: Array<NoteEvent>, ref grid: Felt252Dict<u32>, e: NoteEvent) {
        out.append(e);
        let idx = out.len();
        let sk = old_key(e.voice_id, OLD_SPAN_START);
        let ek = old_key(e.voice_id, OLD_SPAN_END);
        let end = grid.get(ek);
        if end == 0 || e.time + 1 < grid.get(sk) {
            grid.insert(sk, e.time + 1);
        }
        if e.time + e.duration + 1 > end {
            grid.insert(ek, e.time + e.duration + 1);
        }
        let mut c = e.time / CELL;
        let last = (e.time + e.duration) / CELL;
        while c < last {
            grid.insert(old_key(e.voice_id, c), idx);
            c += 1;
        }
    }

    fn old_overlaps(
        placed: Span<NoteEvent>,
        ref grid: Felt252Dict<u32>,
        voices: u32,
        self_voice: u32,
        time: u32,
        duration: u32,
        has_prev: bool,
        prev_pitch: u32,
        prev_cell: u32,
    ) -> Array<(u32, bool, u32)> {
        let mut ov: Array<(u32, bool, u32)> = array![];
        let end = time + duration;
        let mut u: u32 = 0;
        while u < voices {
            let s1 = grid.get(old_key(u, OLD_SPAN_END));
            let s0 = grid.get(old_key(u, OLD_SPAN_START));
            let lo = if s0 > 0 && s0 - 1 > time {
                s0 - 1
            } else {
                time
            };
            let hi = if s1 > 0 && s1 - 1 < end {
                s1 - 1
            } else {
                end
            };
            let mut c = lo / CELL;
            let c1 = if u == self_voice || s1 == 0 || lo >= hi {
                0
            } else {
                (hi - 1) / CELL
            };
            if u == self_voice || s1 == 0 || lo >= hi {
                c = 1;
            }
            while c <= c1 {
                let idx = grid.get(old_key(u, c));
                if idx == 0 {
                    c += 1;
                } else {
                    let q = *placed.at(idx - 1);
                    c = (q.time + q.duration) / CELL;
                    let strong = (if time > q.time {
                        time
                    } else {
                        q.time
                    }) % TU == 0;
                    let before_ic: u32 = if has_prev {
                        let b = grid.get(old_key(u, prev_cell));
                        if b != 0 {
                            ic32(prev_pitch, (placed.at(b - 1).pitch).into())
                        } else {
                            12
                        }
                    } else {
                        12
                    };
                    ov.append((q.pitch.into(), strong, before_ic));
                }
            }
            u += 1;
        }
        ov
    }

    fn rand(ref state: u64, n: u32) -> u32 {
        state = (state * 1103515245 + 12345) % 2147483648;
        ((state / 65536) % n.into()).try_into().unwrap()
    }

    /// Notes for a voice that never overlap, gaps of 0 to 3 cells, 1 to 8 cells long.
    fn voice_notes(ref state: u64, voice: u32, count: u32) -> Array<NoteEvent> {
        let mut notes: Array<NoteEvent> = array![];
        let mut cell: u32 = rand(ref state, 6);
        let mut i: u32 = 0;
        while i < count {
            cell += rand(ref state, 4);
            let cells = 1 + rand(ref state, 8);
            let pitch: u8 = (40 + rand(ref state, 60)).try_into().unwrap();
            notes
                .append(
                    NoteEvent {
                        time: cell * CELL,
                        duration: cells * CELL,
                        pitch,
                        velocity: 90,
                        voice_id: voice,
                    },
                );
            cell += cells;
            i += 1;
        }
        notes
    }

    /// The i-th note a voice places: in time order, backwards, or from both ends in, so the
    /// first and last tick of its notes are not always set by the first and last put.
    fn placement(order: u32, i: u32, n: u32) -> u32 {
        if order == 0 {
            i
        } else if order == 1 {
            n - 1 - i
        } else if i % 2 == 0 {
            i / 2
        } else {
            n - 1 - i / 2
        }
    }

    /// The overlaps found against the earlier grid's (pitch, strong beat, interval class).
    fn assert_same(a: Span<(u32, bool, u32)>, b: Span<Overlap>) {
        assert(a.len() == b.len(), 'overlaps: count');
        let mut i: u32 = 0;
        while i < a.len() {
            let (pitch, strong, before_ic) = *a.at(i);
            let want = overlap(pitch.try_into().unwrap(), strong, before_ic);
            let got = *b.at(i);
            assert(
                got.pitch == want.pitch
                    && got.kinds == want.kinds
                    && got.dissonance == want.dissonance
                    && got.before_ic == want.before_ic,
                'overlaps: item',
            );
            i += 1;
        }
    }

    /// One query against both grids, with random voices, previous note and (unaligned) span.
    fn check(
        placed: Span<NoteEvent>,
        ref old_grid: Felt252Dict<u32>,
        ref new_grid: Felt252Dict<u32>,
        voices: u32,
        self_voice: u32,
        time: u32,
        duration: u32,
        ref state: u64,
    ) {
        let has_prev = rand(ref state, 3) != 0;
        let prev_pitch = 40 + rand(ref state, 60);
        let prev_cell = rand(ref state, 80);
        let old = old_overlaps(
            placed,
            ref old_grid,
            voices,
            self_voice,
            time,
            duration,
            has_prev,
            prev_pitch,
            prev_cell,
        );
        let new = overlaps(
            placed,
            ref new_grid,
            voices,
            self_voice,
            time,
            duration,
            has_prev,
            prev_pitch,
            prev_cell,
        );
        assert_same(old.span(), new.span());
    }

    fn replay(seed: u64, voices: u32) {
        let mut state = seed;
        let mut lines: Array<Array<NoteEvent>> = array![];
        let mut v: u32 = 0;
        while v < voices {
            lines.append(voice_notes(ref state, v, 6 + rand(ref state, 8)));
            v += 1;
        }
        let mut old_out: Array<NoteEvent> = array![];
        let mut new_out: Array<NoteEvent> = array![];
        let mut old_grid: Felt252Dict<u32> = Default::default();
        let mut new_grid: Felt252Dict<u32> = Default::default();
        let mut round: u32 = 0;
        while round < 14 {
            let mut v: u32 = 0;
            while v < voices {
                let line = lines.at(v).span();
                if round < line.len() {
                    let e = *line
                        .at(placement((seed.try_into().unwrap() + v) % 3, round, line.len()));
                    // the note itself as the query, then others, on the grid so far
                    let placed = new_out.span();
                    check(
                        placed,
                        ref old_grid,
                        ref new_grid,
                        voices,
                        v,
                        e.time,
                        e.duration,
                        ref state,
                    );
                    let mut k: u32 = 0;
                    while k < 3 {
                        let (qt, qd) = (rand(ref state, 90 * CELL), rand(ref state, 14 * CELL));
                        let qv = rand(ref state, voices + 2);
                        let qn = rand(ref state, voices + 1);
                        check(placed, ref old_grid, ref new_grid, qn, qv, qt, qd, ref state);
                        k += 1;
                    }
                    old_put(ref old_out, ref old_grid, e);
                    put(ref new_out, ref new_grid, e);
                }
                v += 1;
            }
            round += 1;
        }
        // everything placed: a sweep of one-cell and longer queries over the whole range
        let placed = new_out.span();
        let mut t: u32 = 0;
        while t < 100 * CELL {
            let mut qv: u32 = 0;
            while qv < voices {
                check(placed, ref old_grid, ref new_grid, voices, qv, t, CELL, ref state);
                check(placed, ref old_grid, ref new_grid, voices, qv, t, 5 * CELL + 7, ref state);
                qv += 1;
            }
            t += 60;
        }
    }

    #[test]
    fn cell_key_is_the_u32_sum() {
        let voices = array![0, 1, 4, 255, 4095];
        let cells = array![0, 1, 119, 0xFFFFD, 0xFFFFE, 0xFFFFF];
        for voice in voices.span() {
            for cell in cells.span() {
                assert(cell_key(*voice, *cell) == old_key(*voice, *cell), 'cell_key');
            }
        }
    }

    #[test]
    fn overlaps_match_the_earlier_grid_with_two_voices() {
        replay(11, 2);
    }

    #[test]
    fn overlaps_match_the_earlier_grid_with_three_voices() {
        replay(23, 3);
    }

    #[test]
    fn overlaps_match_the_earlier_grid_with_five_voices() {
        replay(5, 5);
        replay(97, 5);
    }

    #[test]
    fn overlaps_match_the_earlier_grid_with_seven_voices() {
        replay(1234, 7);
    }

    #[test]
    fn overlaps_at_the_start_of_a_section() {
        let mut old_out: Array<NoteEvent> = array![];
        let mut new_out: Array<NoteEvent> = array![];
        let mut old_grid: Felt252Dict<u32> = Default::default();
        let mut new_grid: Felt252Dict<u32> = Default::default();
        let mut state = 9;
        // nothing placed yet: no voice has a span to meet
        check(new_out.span(), ref old_grid, ref new_grid, 3, 1, 0, CELL, ref state);
        check(new_out.span(), ref old_grid, ref new_grid, 3, 1, 0, 0, ref state);
        let e = NoteEvent { time: 0, duration: 4 * CELL, pitch: 62, velocity: 90, voice_id: 0 };
        old_put(ref old_out, ref old_grid, e);
        put(ref new_out, ref new_grid, e);
        // a zero-length note overlaps nothing, even at the first tick; a short one meets the note
        check(new_out.span(), ref old_grid, ref new_grid, 3, 1, 0, 0, ref state);
        check(new_out.span(), ref old_grid, ref new_grid, 3, 1, 4 * CELL, 0, ref state);
        check(new_out.span(), ref old_grid, ref new_grid, 3, 1, 0, 1, ref state);
        check(new_out.span(), ref old_grid, ref new_grid, 3, 1, 4 * CELL - 1, 1, ref state);
        check(new_out.span(), ref old_grid, ref new_grid, 3, 1, 4 * CELL, CELL, ref state);
        let found = overlaps(new_out.span(), ref new_grid, 3, 1, 0, 1, false, 0, 0);
        assert(found.len() == 1, 'overlaps: first tick');
        let found = overlaps(new_out.span(), ref new_grid, 3, 0, 0, 1, false, 0, 0);
        assert(found.len() == 0, 'overlaps: own note');
    }

    #[test]
    fn overlaps_of_the_most_voices_the_key_has_room_for() {
        let placed: Array<NoteEvent> = array![];
        let mut old_grid: Felt252Dict<u32> = Default::default();
        let mut new_grid: Felt252Dict<u32> = Default::default();
        let mut state = 3;
        check(placed.span(), ref old_grid, ref new_grid, 0x1000, 7, 480, 240, ref state);
    }

    #[test]
    #[should_panic(expected: ('u32_mul Overflow',))]
    fn overlaps_panic_past_the_most_voices_as_the_u32_key_did() {
        let placed: Array<NoteEvent> = array![];
        let mut grid: Felt252Dict<u32> = Default::default();
        overlaps(placed.span(), ref grid, 0x1001, 7, 480, 240, false, 0, 0);
    }

    #[test]
    #[should_panic(expected: ('u32_mul Overflow',))]
    fn the_earlier_key_panicked_past_the_most_voices() {
        old_key(0x1000, 0);
    }

    #[test]
    #[should_panic(expected: ('v11: off grid',))]
    fn put_rejects_a_time_off_the_grid() {
        let mut out: Array<NoteEvent> = array![];
        let mut grid: Felt252Dict<u32> = Default::default();
        put(
            ref out,
            ref grid,
            NoteEvent { time: 60, duration: 120, pitch: 60, velocity: 90, voice_id: 0 },
        );
    }

    #[test]
    #[should_panic(expected: ('v11: off grid',))]
    fn put_rejects_a_duration_off_the_grid() {
        let mut out: Array<NoteEvent> = array![];
        let mut grid: Felt252Dict<u32> = Default::default();
        put(
            ref out,
            ref grid,
            NoteEvent { time: 120, duration: 100, pitch: 60, velocity: 90, voice_id: 0 },
        );
    }

    #[test]
    #[should_panic(expected: ('v11: off grid',))]
    fn put_rejects_a_zero_duration() {
        let mut out: Array<NoteEvent> = array![];
        let mut grid: Felt252Dict<u32> = Default::default();
        put(
            ref out,
            ref grid,
            NoteEvent { time: 120, duration: 0, pitch: 60, velocity: 90, voice_id: 0 },
        );
    }
}

#[cfg(test)]
mod shape_tests {
    use core::dict::{Felt252Dict, Felt252DictTrait};
    use crate::composition::beast_trait_map::BeastCompositionParams;
    use crate::composition::beast_v3_sound::{BeastV3LiveState, PackableBeastV3};
    use crate::composition::melodic_canon::NoteEvent;
    use super::{BAR, V11Override, V11Score, build_v11_score_with, no_override, shape};

    /// `shape` as first written: lo, hi and seen dictionaries, a key division per pass.
    fn shape_oracle(
        ref events: Array<NoteEvent>,
        p: @BeastCompositionParams,
        section_ticks: u32,
        prominence: u32,
    ) {
        let ceil: u32 = if p.velocity_ceiling == 0 {
            127
        } else {
            p.velocity_ceiling.into()
        };
        let mut lo: Felt252Dict<u8> = Default::default();
        let mut hi: Felt252Dict<u8> = Default::default();
        let mut seen: Felt252Dict<bool> = Default::default();
        for e in events.span() {
            let key: felt252 = (e.voice_id * 4096 + e.time / section_ticks).into();
            if !seen.get(key) {
                seen.insert(key, true);
                lo.insert(key, e.pitch);
                hi.insert(key, e.pitch);
            } else {
                if e.pitch < lo.get(key) {
                    lo.insert(key, e.pitch);
                }
                if e.pitch > hi.get(key) {
                    hi.insert(key, e.pitch);
                }
            }
        }
        let mut out: Array<NoteEvent> = array![];
        for e in events.span() {
            let e = *e;
            let key: felt252 = (e.voice_id * 4096 + e.time / section_ticks).into();
            let l: u32 = lo.get(key).into();
            let h: u32 = hi.get(key).into();
            let lead = e.voice_id == 0;
            let arc: u32 = if h > l {
                (32 * (e.pitch.into() - l) + (h - l)) / (2 * (h - l))
            } else {
                8
            };
            let mut v: u32 = if lead {
                80 + 4 * prominence
            } else {
                70 - 2 * prominence
            } + arc;
            if e.time % BAR == 0 {
                v += if ((e.time % section_ticks) / BAR) % 2 == 0 {
                    12
                } else {
                    4
                };
                if lead {
                    v += 2 * prominence;
                }
            }
            let vel: u8 = (if v > ceil {
                ceil
            } else if v < 1 {
                1
            } else {
                v
            }).try_into().unwrap();
            let duration = if p.articulation_profile == 1 {
                let x = e.duration / 2;
                if x > 60 {
                    x
                } else {
                    60
                }
            } else if p.articulation_profile == 5 {
                let x = e.duration * 3 / 4;
                if x > 60 {
                    x
                } else {
                    60
                }
            } else {
                e.duration
            };
            out.append(NoteEvent { velocity: vel, duration, ..e });
        }
        events = out;
    }

    fn clone_events(events: Span<NoteEvent>) -> Array<NoteEvent> {
        let mut out: Array<NoteEvent> = array![];
        out.append_span(events);
        out
    }

    fn score_of(id: u64) -> V11Score {
        let beast = PackableBeastV3 {
            id,
            prefix: 0,
            suffix: 0,
            level: 50,
            health: 200,
            shiny: 0,
            animated: 0,
            tier: 1,
            beast_type: 1,
        };
        let live = BeastV3LiveState {
            adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1,
        };
        let ov = V11Override {
            voice_count: Option::Some(4),
            section_count: Option::Some(4),
            use_countersubject: Option::Some(true),
            ..no_override(),
        };
        build_v11_score_with(beast, live, ov)
    }

    fn assert_same(a: Span<NoteEvent>, b: Span<NoteEvent>) {
        assert(a.len() == b.len(), 'event count');
        let mut i = 0;
        while i < a.len() {
            let (x, y) = (*a.at(i), *b.at(i));
            assert(x.time == y.time && x.pitch == y.pitch && x.voice_id == y.voice_id, 'identity');
            assert(x.velocity == y.velocity, 'velocity');
            assert(x.duration == y.duration, 'duration');
            i += 1;
        }
    }

    fn check(events: Span<NoteEvent>, p: @BeastCompositionParams, st: u32, prominence: u32) {
        let mut a = clone_events(events);
        let mut b = clone_events(events);
        shape_oracle(ref a, p, st, prominence);
        shape(ref b, p, st, prominence);
        assert_same(a.span(), b.span());
    }

    /// Every profile and ceiling, on the events of real scores.
    #[test]
    #[available_gas(100000000000)]
    fn shape_matches_oracle_on_scores() {
        for id in array![1_u64, 32, 68, 75].span() {
            let score = score_of(*id);
            for profile in array![0_u8, 1, 5, 7].span() {
                for ceiling in array![0_u8, 1, 64, 127, 255].span() {
                    let p = BeastCompositionParams {
                        articulation_profile: *profile, velocity_ceiling: *ceiling, ..score.params,
                    };
                    check(score.events.span(), @p, score.section_ticks, 0);
                    check(score.events.span(), @p, score.section_ticks, 3);
                }
            }
        }
    }

    fn next_random(ref seed: u64) -> u32 {
        seed = (seed * 1664525 + 1013904223) % 0x100000000;
        (seed / 16).try_into().unwrap()
    }

    /// `count` events in stretches of random length: a voice and a section, then another. Sections
    /// 4096 and up make keys collide (voice 0 there is voice 1 in section 0).
    fn random_events(ref seed: u64, kind: u32, section_ticks: u32, count: u32) -> Array<NoteEvent> {
        let mut events: Array<NoteEvent> = array![];
        let mut voice: u32 = 0;
        let mut section: u32 = 0;
        while events.len() < count {
            let r = next_random(ref seed);
            if r % 4 == 0 {
                voice = (r / 4) % 6;
                section =
                    if section_ticks == 7 {
                        *array![0_u32, 1, 4096, 4097].span().at((r / 32) % 4)
                    } else {
                        (r / 32) % 3
                    };
            }
            let r = next_random(ref seed);
            let from = section * section_ticks;
            // a third of the events on a bar line, when the section holds one
            let first_bar = (from + BAR - 1) / BAR * BAR;
            let offset = if r % 3 == 0 && first_bar < from + section_ticks {
                first_bar - from + (r / 4) % ((from + section_ticks - first_bar) / BAR + 1) * BAR
            } else {
                (r / 4) % section_ticks
            };
            let pitch = if kind % 5 == 0 {
                r / 64 % 256
            } else {
                60 + r / 64 % (1 + kind % 5 * 12)
            };
            events
                .append(
                    NoteEvent {
                        time: from + offset,
                        duration: r / 16384 % 3000,
                        pitch: pitch.try_into().unwrap(),
                        velocity: 90,
                        voice_id: voice,
                    },
                );
        }
        events
    }

    /// Events in any order, stretches of a voice interleaved and repeated, keys colliding, pitches
    /// over the whole u8 range, velocity sums past 255 and down to 0.
    #[test]
    #[available_gas(100000000000)]
    fn shape_matches_oracle_on_any_layout() {
        let score = score_of(32);
        let mut seed: u64 = 12345;
        let mut kind: u32 = 0;
        while kind < 16 {
            let section_ticks = *array![BAR * 4, BAR * 3, 2500, 7].span().at(kind % 4);
            let events = random_events(ref seed, kind, section_ticks, 80);
            for profile in array![0_u8, 1, 5].span() {
                for ceiling in array![0_u8, 255].span() {
                    let p = BeastCompositionParams {
                        articulation_profile: *profile, velocity_ceiling: *ceiling, ..score.params,
                    };
                    // 35: the largest prominence whose follower base 70 - 2 * prominence is >= 0
                    for prominence in array![0_u32, 1, 3, 35].span() {
                        check(events.span(), @p, section_ticks, *prominence);
                    }
                }
            }
            kind += 1;
        }
    }

    #[test]
    fn shape_of_no_events_is_empty() {
        let score = score_of(1);
        let mut events: Array<NoteEvent> = array![];
        shape(ref events, @score.params, score.section_ticks, 1);
        assert(events.is_empty(), 'no events');
    }
}

/// `dominant` against the original: the window walked in i32, a pitch class by `%` and a scan of
/// `pcs` for every pitch.
#[cfg(test)]
mod dominant_tests {
    use super::{abs_i32, dominant};

    fn reference(from: u8, pcs: Span<u8>) -> Array<(i32, u8)> {
        let mut c: Array<(i32, u8)> = array![];
        let f: i32 = from.into();
        let mut m = f - 9;
        while m <= f + 9 {
            if m >= 0 {
                let pc: u8 = (m % 12).try_into().unwrap();
                let mut hit = false;
                for x in pcs {
                    if *x == pc {
                        hit = true;
                        break;
                    }
                }
                if hit {
                    c.append((3 * abs_i32(m - f), m.try_into().unwrap()));
                }
            }
            m += 1;
        }
        if c.len() == 0 {
            c.append((0, from));
        }
        c
    }

    /// Chords as the composer builds them (one class, three), and the shapes it does not: none,
    /// two, repeats, classes that are no pitch class, and more than three.
    fn class_sets() -> Array<Array<u8>> {
        array![
            array![], array![7], array![0], array![11], array![7, 11, 2], array![0, 4, 7],
            array![11, 0, 1], array![5, 9], array![5, 5, 9], array![3, 3, 3], array![12],
            array![200, 7], array![255, 3, 3, 3, 4], array![1, 2, 3, 4], array![0, 0, 0, 0, 9],
            array![10, 11, 12, 13, 14, 8], array![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        ]
    }

    /// Whether a pitch above 255 is a hit, which panics.
    fn reaches_past_255(from: u8, pcs: Span<u8>) -> bool {
        let mut m: u32 = 256;
        let mut reaches = false;
        while m <= from.into() + 9 {
            for x in pcs {
                if (*x).into() == m % 12 {
                    reaches = true;
                }
            }
            m += 1;
        }
        reaches
    }

    #[test]
    #[available_gas(100000000000)]
    fn dominant_is_the_original() {
        let sets = class_sets();
        let mut n: u32 = 0;
        while n < 256 {
            let from: u8 = n.try_into().unwrap();
            for pcs in sets.span() {
                if !reaches_past_255(from, pcs.span()) {
                    assert!(dominant(from, pcs.span()) == reference(from, pcs.span()));
                }
            }
            n += 1;
        }
    }

    #[test]
    #[should_panic(expected: ('Option::unwrap failed.',))]
    fn a_pitch_above_255_panics() {
        dominant(255, array![4_u8].span());
    }

    #[test]
    #[should_panic(expected: ('Option::unwrap failed.',))]
    fn the_original_panics_there_too() {
        reference(255, array![4_u8].span());
    }
}

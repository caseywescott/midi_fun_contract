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

use core::dict::{Felt252Dict, Felt252DictTrait};
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
use crate::composition::melodic_canon::{NoteEvent, realize_degree};

const TU: u32 = 480;
const BAR: u32 = 1920;
/// Slot sources: 0-3 a beat of the 4-beat group (that beat's theme degree), then these.
const SRC_PASSING: u8 = 4;
const SRC_TONIC: u8 = 5;
const SRC_TRILL: u8 = 6;
/// Developments for sections after the first.
const DEV_SEQUENCE: u8 = 0;
const DEV_STRETTO: u8 = 1;
const DEV_INVERSION: u8 = 2;

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
    let fam = family(*p.weakness);
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
            if has_passing(n) && (h / 256) % 8 >= (*p.ornament_density).into() + 2 {
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
            let a = *slots.at(i - 1).degree;
            let b = if i + 1 < n {
                *slots.at(i + 1).degree
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
fn degree_plan(p: @BeastCompositionParams) -> Array<i32> {
    let side: i32 = if *p.weakness == 1 {
        -1
    } else {
        1
    };
    let mut out: Array<i32> = array![];
    for f in fifths_plan((*p.section_count).into(), reach(*p.tier)) {
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

fn interval_class(a: u8, b: u8) -> u32 {
    let d: u32 = if a > b {
        (a - b).into()
    } else {
        (b - a).into()
    };
    d % 12
}

fn dissonant(ic: u32) -> bool {
    ic == 1 || ic == 2 || ic == 6 || ic == 10 || ic == 11
}

/// First index in `placed[lo..hi)` (one run: chronological, non-overlapping notes, so end times
/// rise too) whose note ends after `t`.
fn first_ending_after(placed: Span<NoteEvent>, lo: u32, hi: u32, t: u32) -> u32 {
    let mut a = lo;
    let mut b = hi;
    while a < b {
        let mid = (a + b) / 2;
        let e = *placed.at(mid);
        if e.time + e.duration > t {
            b = mid;
        } else {
            a = mid + 1;
        }
    }
    a
}

/// The candidate (base score, pitch) with the lowest score against everything placed so far in the
/// section; the first wins a tie. Scores in quarter points.
///
/// `placed` is a sequence of runs starting at `starts` (a voice's line, the countersubject, a
/// voice's episode), each chronological with no overlaps, so the notes sounding with the new one
/// are found by binary search in each run, and "the note before" (what an overlapping voice played
/// when this voice played `prev`, for the parallel-5ths check) is that voice's one note covering
/// the time, the first in placement order. Both are looked up once per call, not per candidate; the
/// score is a sum, so this gives exactly the scores of checking every placed note per candidate.
fn choose_pitch(
    cands: Span<(i32, u8)>,
    time: u32,
    duration: u32,
    placed: Span<NoteEvent>,
    starts: Span<u32>,
    prev: Option<NoteEvent>,
) -> u8 {
    let n = placed.len();
    let end = time + duration;
    let mut ov: Array<NoteEvent> = array![];
    let mut j: u32 = 0;
    while j < starts.len() {
        let lo = *starts.at(j);
        let hi = if j + 1 < starts.len() {
            *starts.at(j + 1)
        } else {
            n
        };
        let mut i = first_ending_after(placed, lo, hi, time);
        while i < hi && *placed.at(i).time < end {
            ov.append(*placed.at(i));
            i += 1;
        }
        j += 1;
    }
    let ov = ov.span();
    // per overlapping note: 0 not looked up, 1 nothing before, 2 + pitch
    let mut before: Felt252Dict<u16> = Default::default();
    let mut best_pitch: u8 = 0;
    let mut best_score: i32 = 0;
    let mut first = true;
    for (base, pitch) in cands {
        let pitch = *pitch;
        let mut score = *base;
        let mut i: u32 = 0;
        while i < ov.len() {
            let q = *ov.at(i);
            let ic = interval_class(pitch, q.pitch);
            let strong = (if time > q.time {
                time
            } else {
                q.time
            }) % TU == 0;
            if dissonant(ic) {
                score += if strong {
                    40
                } else {
                    8
                };
            } else if ic == 0 {
                score += if pitch == q.pitch {
                    24
                } else {
                    16
                };
            } else if ic == 7 {
                score += 2;
            }
            // parallel 5ths / 8ves against what this voice and that voice had before
            if let Option::Some(ps) = prev {
                if ic == 0 || ic == 7 {
                    let key: felt252 = i.into();
                    let mut st = before.get(key);
                    if st == 0 {
                        st = 1;
                        let mut j: u32 = 0;
                        while j < starts.len() {
                            let lo = *starts.at(j);
                            let hi = if j + 1 < starts.len() {
                                *starts.at(j + 1)
                            } else {
                                n
                            };
                            if lo < hi && *placed.at(lo).voice_id == q.voice_id {
                                let k = first_ending_after(placed, lo, hi, ps.time);
                                if k < hi && *placed.at(k).time <= ps.time {
                                    st = 2 + (*placed.at(k).pitch).into();
                                    break;
                                }
                            }
                            j += 1;
                        }
                        before.insert(key, st);
                    }
                    if st >= 2 {
                        let bp: u8 = (st - 2).try_into().unwrap();
                        if interval_class(ps.pitch, bp) == ic && ps.pitch != pitch {
                            score += 32;
                        }
                    }
                }
            }
            i += 1;
        }
        if let Option::Some(ps) = prev {
            let leap: i32 = abs_i32(pitch.into() - ps.pitch.into());
            if leap > 9 {
                score += 12;
            }
        }
        if first || score < best_score {
            best_score = score;
            best_pitch = pitch;
            first = false;
        }
    }
    best_pitch
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
    tonic: u8,
    mode: u8,
}

fn realize(r: Realizer, d: i32) -> u8 {
    realize_degree(7, d + r.shift, r.tonic, r.mode)
}

/// Candidates a step or two around a degree (mapped by the voice), scored by distance.
fn near(r: Realizer, m: VoiceMap, deg: i32) -> Array<(i32, u8)> {
    array![
        (0, realize(r, map_degree(m, deg))),
        (6, realize(r, map_degree(m, deg + 1))),
        (6, realize(r, map_degree(m, deg - 1))),
        (12, realize(r, map_degree(m, deg + 2))),
        (12, realize(r, map_degree(m, deg - 2))),
    ]
}

fn place(
    ref out: Array<NoteEvent>,
    starts: Span<u32>,
    ref prev: Option<NoteEvent>,
    time: u32,
    duration: u32,
    cands: Span<(i32, u8)>,
    voice: u32,
) {
    let pitch = choose_pitch(cands, time, duration, out.span(), starts, prev);
    let e = NoteEvent { time, duration, pitch, velocity: 90, voice_id: voice };
    out.append(e);
    prev = Option::Some(e);
}

/// Pitches within 9 semitones of `from` whose pitch class is in `pcs`, scored by distance.
fn dominant(from: u8, pcs: Span<u8>) -> Array<(i32, u8)> {
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

/// From the end of a voice's line to the section end: fill to the barline stepping toward the
/// sequence, then sequence bars of the head motif, then a half cadence on the next key's dominant.
fn episode(
    ref out: Array<NoteEvent>,
    starts: Span<u32>,
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
    let head0 = *head.at(0).degree;
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
        place(ref out, starts, ref prev, t, d, near(r, m, target1 - dir * back).span(), voice);
        t += d;
    }
    // 2. sequence: the head motif, a step further each bar
    let mut k: u32 = 1;
    while k <= seq_bars {
        let ki: i32 = k.try_into().unwrap();
        for h in head {
            place(
                ref out,
                starts,
                ref prev,
                t + *h.time,
                *h.duration,
                near(r, m, *h.degree + dir * ki).span(),
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
        place(ref out, starts, ref prev, t, TU, near(r, m, head0 + dir * sb).span(), voice);
        place(
            ref out, starts, ref prev, t + TU, TU, near(r, m, head0 + dir * sb - dir).span(), voice,
        );
        let from = prev.unwrap().pitch;
        place(
            ref out, starts, ref prev, t + 2 * TU, left - 2 * TU, dominant(from, pcs).span(), voice,
        );
    } else {
        let from = prev.unwrap().pitch;
        place(ref out, starts, ref prev, t, left, dominant(from, pcs).span(), voice);
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
) -> Array<NoteEvent> {
    // development: sections after the first follow the Beast's dominant history
    let dev = if s > 0 {
        tr.development
    } else {
        DEV_SEQUENCE
    };
    let lag: u32 = if s > 0 && dev == DEV_STRETTO {
        if *p.stretto_lag > 2 {
            *p.stretto_lag - 1
        } else {
            1
        }
    } else {
        *p.stretto_lag
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
        let d0 = *slots_in.at(0).degree;
        let mut kept: Array<Slot> = array![];
        for sl in slots_in {
            if *sl.src != SRC_PASSING && *sl.src != SRC_TRILL {
                kept.append(*sl);
            }
        }
        let n = kept.len();
        let mut i: u32 = 0;
        while i < n {
            let sl = *kept.at(i);
            let end = if i + 1 < n {
                *kept.at(i + 1).time
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
    let sc: u32 = (*p.section_count).into();
    let next = if s + 1 < sc {
        s + 1
    } else {
        0
    };
    let mode = canonical_to_melodic_mode(*p.mode_id);
    let home = transposed_tonic(*p.tonic_keynum, 0);
    let r = Realizer { shift: *plan.at(s % plan.len()), tonic: home, mode };
    let next_shift = *plan.at(next % plan.len());
    let mut out: Array<NoteEvent> = array![];
    // where each run of `out` starts: every voice line, the countersubject and every episode
    let mut starts: Array<u32> = array![];
    // per voice: its map, offset and last note (the countersubject last, with offset 99)
    let mut maps: Array<VoiceMap> = array![];
    let mut offs_used: Array<i32> = array![];
    let mut lasts: Array<NoteEvent> = array![];
    let mut v: u32 = 0;
    while v < *p.voice_count {
        let entry = v * lag * TU;
        let off = if v < 4 {
            *offs.at(v)
        } else {
            *offs.at(3)
        };
        let m = VoiceMap { invert: *p.use_inversion && v == 1, off };
        starts.append(out.len());
        let mut prev: Option<NoteEvent> = Option::None;
        for sl in slots {
            let base = map_degree(m, *sl.degree);
            let time = offset + entry + *sl.time;
            let pitch = if v == 0 {
                realize(r, base)
            } else {
                let cands = array![
                    (0, realize(r, base)),
                    (6, realize(r, base + 1)),
                    (6, realize(r, base - 1)),
                    (12, realize(r, base + 2)),
                    (12, realize(r, base - 2)),
                ];
                choose_pitch(cands.span(), time, *sl.duration, out.span(), starts.span(), prev)
            };
            let e = NoteEvent { time, duration: *sl.duration, pitch, velocity: 90, voice_id: v };
            out.append(e);
            prev = Option::Some(e);
        }
        maps.append(m);
        offs_used.append(off);
        lasts.append(prev.unwrap());
        v += 1;
    }
    let mut cs_head: Array<Slot> = array![];
    if *p.use_countersubject {
        // v1's countersubject in steady quarters against the rhythmic subject, voice-checked
        let cs = generate_countersubject(
            theme, @default_countersubject_config(), cs_seed, 7, mode, home, TU,
        );
        starts.append(out.len());
        let mut prev: Option<NoteEvent> = Option::None;
        let mut i: u32 = 0;
        let ident = VoiceMap { invert: false, off: 0 };
        for d in cs.degrees.span() {
            let time = offset + i * TU;
            let cands = near(r, ident, *d);
            let pitch = choose_pitch(cands.span(), time, TU, out.span(), starts.span(), prev);
            let e = NoteEvent { time, duration: TU, pitch, velocity: 90, voice_id: *p.voice_count };
            out.append(e);
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
        if *sl.group == 0 {
            head.append(*sl);
        }
    }
    // the half cadence's target: the next section's dominant chord (bass: its 5th)
    let next_r = Realizer { shift: next_shift, tonic: home, mode };
    let dom_bass: Array<u8> = array![realize(next_r, 4) % 12];
    let dom_chord: Array<u8> = array![
        realize(next_r, 4) % 12, realize(next_r, 6) % 12, realize(next_r, 1) % 12,
    ];
    let nvo = lasts.len();
    let mut x: u32 = 0;
    while x < nvo {
        let is_cs = *p.use_countersubject && x == nvo - 1;
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
        starts.append(out.len());
        episode(
            ref out,
            starts.span(),
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

/// Phrase arc per voice and section, accents on bar downbeats (the first bar of each pair harder),
/// the lead's prominence, articulation by profile, under the velocity ceiling.
fn shape(
    ref events: Array<NoteEvent>, p: @BeastCompositionParams, section_ticks: u32, prominence: u32,
) {
    let ceil: u32 = if *p.velocity_ceiling == 0 {
        127
    } else {
        (*p.velocity_ceiling).into()
    };
    let mut lo: Felt252Dict<u8> = Default::default();
    let mut hi: Felt252Dict<u8> = Default::default();
    let mut seen: Felt252Dict<bool> = Default::default();
    for e in events.span() {
        let key: felt252 = ((*e.voice_id) * 4096 + *e.time / section_ticks).into();
        if !seen.get(key) {
            seen.insert(key, true);
            lo.insert(key, *e.pitch);
            hi.insert(key, *e.pitch);
        } else {
            if *e.pitch < lo.get(key) {
                lo.insert(key, *e.pitch);
            }
            if *e.pitch > hi.get(key) {
                hi.insert(key, *e.pitch);
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
        let duration = if *p.articulation_profile == 1 {
            let x = e.duration / 2;
            if x > 60 {
                x
            } else {
                60
            }
        } else if *p.articulation_profile == 5 {
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

/// The v1.1 score for a Beast and its live state.
pub fn build_v11_score(beast: PackableBeastV3, live: BeastV3LiveState) -> V11Score {
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
    let p = map_v3_beast_to_composition_params(beast, structural);
    let seeds = derive_beast_sound_seeds(beast_sound_seed(beast.id, beast.prefix, beast.suffix));
    let theme_v1 = build_beast_theme(p, seeds.motif_seed);
    let theme = cadence_theme(theme_v1.degrees.span());
    let tr = trajectory(beast, @p, swapped, structural, live);
    let mut slots = theme_rhythm(@p, theme.span(), seeds.motif_seed);
    if tr.trill {
        // a trill (upper neighbour and back) replaces each passing note of an eighth or longer
        let mut out: Array<Slot> = array![];
        let n = slots.len();
        let mut i: u32 = 0;
        while i < n {
            let sl = *slots.at(i);
            if sl.src == SRC_PASSING && sl.duration >= 240 {
                let half = sl.duration / 2;
                let before = *slots.at(i - 1).degree;
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
        if *sl.time + *sl.duration > theme_end {
            theme_end = *sl.time + *sl.duration;
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
    let plan = degree_plan(@p);
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
        );
        events.append_span(sec.span());
        s += 1;
    }
    shape(ref events, @p, section_ticks, tr.prominence);
    V11Score { events, section_ticks, params: p }
}

/// The v1.1 score as a form for the MIDI writers (no score hash: the self-contained writer does not
/// use it).
pub fn v11_form(score: @V11Score) -> BeastForm {
    let sc = *score.params.section_count;
    let mut events: Array<NoteEvent> = array![];
    events.append_span(score.events.span());
    BeastForm {
        events, score_hash: 0, section_count: sc, length_ticks: sc.into() * *score.section_ticks,
    }
}

/// The v1.1 score as the self-contained file for onchain-tinysynth (programs, pan, drums:
/// crate::composition::full_midi).
pub fn v11_score_full_smf_bytes(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<u8> {
    let score = build_v11_score(beast, live);
    let form = v11_form(@score);
    crate::composition::full_midi::beast_form_to_full_smf_bytes(
        @form, score.params.tempo_us, score.params.tier,
    )
}

/// The same, packed 31 bytes per felt after the byte length.
pub fn v11_score_full_midi(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252> {
    midi::pack::to_felt252_array(v11_score_full_smf_bytes(beast, live).span())
}

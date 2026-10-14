//! The Yeti special (species 68), on every Yeti track: 16th-note ornaments in the theme's first
//! section placed by the track's own ornament profile, the avalanche (a run down each section's
//! closing chord on its own voice) and the rock groove at 175 BPM. Byte-identical to the lab's
//! `yetiOrnaments(..., varied)`, `yetiAvalanche` and `rockDrums` (offchain/beast-sound/src/lab.js)
//! as `sampleTrackMidi` applies them.

use core::dict::{Felt252Dict, Felt252DictTrait};
use midi::smf::TrackWriterTrait;
use crate::composition::beast_score::transposed_tonic;
use crate::composition::melodic_canon::NoteEvent;

pub const YETI: u64 = 68;
pub const YETI_ROCK_TEMPO_US: u32 = 342857;
/// The avalanche's voice, past the six channels; it plays the Pulse 12.5% Pluck and is never the
/// lead.
pub const YETI_AVALANCHE_VOICE: u32 = 6;
pub const YETI_AVALANCHE_PROGRAM: u8 = 13;

const M32: u64 = 0xffffffff;
const S16: u32 = 120; // a sixteenth

// ── the track's scale: degrees of the key, in the track's real scale
// ─────────────────────────────

#[derive(Copy, Drop)]
pub struct YetiKey {
    home: i32,
    scale: Span<u8>,
}

/// The key the track plays: the tonic (clamped to the composer's range) and the scale (the
/// track's real scale, else the composer's melodic one for the mode).
pub fn yeti_key(tonic_keynum: u8, mode_id: u8, scale: Option<Span<u8>>) -> YetiKey {
    let home: i32 = transposed_tonic(tonic_keynum, 0).into();
    let sc = match scale {
        Option::Some(s) => s,
        Option::None => melodic_scale(mode_id),
    };
    YetiKey { home, scale: sc }
}

fn melodic_scale(mode_id: u8) -> Span<u8> {
    if mode_id == 4 || mode_id == 26 {
        array![0, 2, 3, 5, 7, 9, 10].span()
    } else if mode_id == 5 || mode_id == 6 {
        array![0, 1, 3, 5, 7, 8, 10].span()
    } else {
        array![0, 2, 3, 5, 7, 8, 10].span()
    }
}

fn floor_div7(d: i32) -> i32 {
    if d >= 0 {
        d / 7
    } else {
        -((-d + 6) / 7)
    }
}

fn pitch(k: YetiKey, d: i32) -> i32 {
    let o = floor_div7(d);
    let i: u32 = (d - 7 * o).try_into().unwrap();
    let off: i32 = (*k.scale.at(i)).into();
    k.home + 12 * o + off
}

fn abs(x: i32) -> i32 {
    if x < 0 {
        -x
    } else {
        x
    }
}

/// The nearest degree to a pitch (-28..=42; ties keep the earlier best, starting from 0).
fn degree(k: YetiKey, p: i32) -> i32 {
    let mut best: i32 = 0;
    let mut bd = abs(pitch(k, 0) - p);
    let mut d: i32 = -28;
    while d <= 42 {
        let x = abs(pitch(k, d) - p);
        if x < bd {
            best = d;
            bd = x;
        }
        d += 1;
    }
    best
}

fn clamp_pitch(p: i32) -> u8 {
    if p < 24 {
        24
    } else if p > 108 {
        108
    } else {
        p.try_into().unwrap()
    }
}

// ── the ornament profile
// ─────────────────────────────────────────────────────────────────────────

fn name_hash(prefix: u64, suffix: u64, salt: u64) -> u64 {
    let mut h = (prefix * 131 + suffix * 31 + salt * 977 + 7) & M32;
    h = h ^ ((h * 0x2000) & M32); // << 13
    h = h ^ (h / 0x20000); // >>> 17
    h = h ^ ((h * 0x20) & M32); // << 5
    h
}

/// A hash of the species and the name (the lab's beastHash).
fn beast_hash(id: u64, prefix: u8, suffix: u8, salt: u64) -> u64 {
    name_hash(prefix.into() + id * 70, suffix.into() + id * 19, salt)
}

fn shr(x: u64, n: u32) -> u64 {
    let mut v = x;
    let mut i = 0;
    while i < n {
        v = v / 2;
        i += 1;
    }
    v
}

// placements, in ORNAMENT_PLACEMENTS order
const EVEN: u64 = 0;
const BURSTS: u64 = 1;
const LONG: u64 = 2;
const STRONG: u64 = 3;
const BAR_ENDS: u64 = 4;
// figures, in ORNAMENT_FIGURES order
const MORDENT: u8 = 0;
const UPPER: u8 = 1;
const TURN: u8 = 2;
const RUN: u8 = 3;
const SLIDE: u8 = 4;
const TRILL: u8 = 5;

#[derive(Drop)]
struct Profile {
    placement: u64,
    gap: u32,
    burst: u32,
    figures: Array<u8>,
}

fn profile(id: u64, prefix: u8, suffix: u8) -> Profile {
    let h = beast_hash(id, prefix, suffix, 5);
    let g = beast_hash(id, prefix, suffix, 6);
    let mut pool: Array<u8> = array![MORDENT, UPPER, TURN, RUN, SLIDE, TRILL];
    let mut figures: Array<u8> = array![];
    let mut k: u32 = 0;
    while figures.len() < 3 {
        let at: u32 = (shr(g, (k * 3) % 32) % 6).try_into().unwrap();
        let f = *pool.at(at);
        let mut have = false;
        for x in figures.span() {
            if *x == f {
                have = true;
            }
        }
        if !have {
            figures.append(f);
        } else {
            // move it to the end of the pool
            let mut next: Array<u8> = array![];
            for x in pool.span() {
                if *x != f {
                    next.append(*x);
                }
            }
            next.append(f);
            pool = next;
        }
        k += 1;
    }
    Profile {
        placement: h % 6,
        gap: (2 + shr(h, 4) % 4).try_into().unwrap(),
        burst: (2 + shr(h, 8) % 2).try_into().unwrap(),
        figures,
    }
}

// ── ornaments
// ────────────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop)]
struct Seg {
    pitch: i32,
    len: u32,
    vel: u8,
}

/// The rest of the note: the figure's last note held on when it is the note itself, else the note
/// again.
fn hold(fig: Array<Seg>, p: i32, dur: u32, vel: u8) -> Array<Seg> {
    let mut used: u32 = 0;
    for f in fig.span() {
        used += f.len;
    }
    if used >= dur {
        return fig;
    }
    let rest = dur - used;
    let n = fig.len();
    let last = *fig.at(n - 1);
    let mut out: Array<Seg> = array![];
    let mut i = 0;
    while i < n - 1 {
        out.append(*fig.at(i));
        i += 1;
    }
    if last.pitch == p {
        out.append(Seg { pitch: p, len: last.len + rest, vel: last.vel });
    } else {
        out.append(last);
        out.append(Seg { pitch: p, len: rest, vel });
    }
    out
}

fn note_at(events: Span<NoteEvent>, idx: Span<u32>, j: u32) -> NoteEvent {
    *events.at(*idx.at(j))
}

/// 0..999 from the track's hash, a note index and a salt (32-bit products, as Math.imul).
fn roll(h: u64, j: u32, salt: u64) -> u64 {
    let j64: u64 = j.into();
    let a = ((j64 + 1) * 2654435761) & M32;
    let b = (salt * 40503) & M32;
    (h ^ a ^ b) % 1000
}

/// The theme's first-section notes ornamented by the track's profile (`id`, `prefix`, `suffix`: the
/// species and the track's special name). Every figure starts on its note's beat and adds up to its
/// length, in the key's scale.
pub fn yeti_ornaments(
    events: Span<NoteEvent>,
    section_ticks: u32,
    key: YetiKey,
    ornament_density: u8,
    id: u64,
    prefix: u8,
    suffix: u8,
) -> Array<NoteEvent> {
    // the theme's notes in the first section (event indices, chronological)
    let mut idx: Array<u32> = array![];
    let mut i: u32 = 0;
    while i < events.len() {
        let e = *events.at(i);
        if e.voice_id == 0 && e.time < section_ticks {
            idx.append(i);
        }
        i += 1;
    }
    let n = idx.len();
    let mut out: Array<NoteEvent> = array![];
    if n < 2 {
        for e in events {
            out.append(*e);
        }
        return out;
    }
    let idx = idx.span();
    let pr = profile(id, prefix, suffix);
    let busy = ornament_density >= 4;
    let h = beast_hash(id, prefix, suffix, 7);
    // eligible: a quarter or longer, not the last note
    let mut elig: Array<u32> = array![];
    let mut j: u32 = 0;
    while j < n {
        if note_at(events, idx, j).duration >= 480 && j < n - 1 {
            elig.append(j);
        }
        j += 1;
    }
    let ne = elig.len();
    let gap: u32 = if busy && pr.gap > 1 {
        pr.gap - 1
    } else {
        pr.gap
    };
    let mut pick: Felt252Dict<bool> = Default::default();
    let mut picked: u32 = 0;
    if pr.placement == EVEN {
        let mut k = 0;
        while k < ne {
            if k % gap == 0 {
                pick.insert((*elig.at(k)).into(), true);
                picked += 1;
            }
            k += 1;
        }
    } else if pr.placement == BURSTS {
        let cycle = pr.burst + gap + 2;
        let mut k = 0;
        while k < ne {
            if k % cycle < pr.burst {
                pick.insert((*elig.at(k)).into(), true);
                picked += 1;
            }
            k += 1;
        }
    } else if pr.placement == LONG {
        // the longest notes (ties to the earlier), 35% of them (50% busy), rounded up
        let take = (ne * if busy {
            50
        } else {
            35
        } + 99) / 100;
        let mut taken: Felt252Dict<bool> = Default::default();
        let mut t = 0;
        while t < take {
            let mut best: u32 = 0xffffffff;
            let mut k = 0;
            while k < ne {
                let c = *elig.at(k);
                if !taken.get(c.into())
                    && (best == 0xffffffff
                        || note_at(events, idx, c).duration > note_at(events, idx, best).duration) {
                    best = c;
                }
                k += 1;
            }
            taken.insert(best.into(), true);
            pick.insert(best.into(), true);
            picked += 1;
            t += 1;
        }
    } else if pr.placement == STRONG {
        let every: u32 = if gap > 3 {
            2
        } else {
            1
        };
        let mut k = 0;
        let mut m: u32 = 0;
        while k < ne {
            let c = *elig.at(k);
            if note_at(events, idx, c).time % 960 == 0 {
                if m % every == 0 {
                    pick.insert(c.into(), true);
                    picked += 1;
                }
                m += 1;
            }
            k += 1;
        }
    } else if pr.placement == BAR_ENDS {
        let mut k = 0;
        let mut m: u32 = 0;
        while k < ne {
            let c = *elig.at(k);
            let e = note_at(events, idx, c);
            if e.time % 1920 >= 960 || (e.time + e.duration) % 1920 == 0 {
                if m % 2 == 0 || busy {
                    pick.insert(c.into(), true);
                    picked += 1;
                }
                m += 1;
            }
            k += 1;
        }
    } else {
        // swell: 8%, rising by 75% (busy) or 60% of the way through the section
        let rise: u64 = if busy {
            750
        } else {
            600
        };
        let sec: u64 = section_ticks.into();
        let mut k = 0;
        while k < ne {
            let c = *elig.at(k);
            if roll(h, c, 1) * sec < 80 * sec + rise * note_at(events, idx, c).time.into() {
                pick.insert(c.into(), true);
                picked += 1;
            }
            k += 1;
        }
    }
    if picked == 0 && ne > 0 {
        pick.insert((*elig.at(0)).into(), true);
    }
    // the palette, weighted 3:2:1
    let f0 = *pr.figures.at(0);
    let f1 = *pr.figures.at(1);
    let f2 = *pr.figures.at(2);
    let weighted: Array<u8> = array![f0, f0, f0, f1, f1, f2];
    let first_not_run = if f0 != RUN {
        f0
    } else if f1 != RUN {
        f1
    } else {
        f2
    };

    // the figures, by note index
    let mut figs: Felt252Dict<Nullable<Span<Seg>>> = Default::default();
    let mut j: u32 = 0;
    while j < n {
        if pick.get(j.into()) {
            let e = note_at(events, idx, j);
            let p: i32 = e.pitch.into();
            let d = degree(key, p);
            let up = pitch(key, d + 1);
            let down = pitch(key, d - 1);
            let vel: u8 = if e.velocity > 13 {
                e.velocity - 12
            } else {
                1
            };
            let can_run = if j + 1 < n {
                let nx = note_at(events, idx, j + 1);
                nx.time == e.time + e.duration && abs(degree(key, nx.pitch.into()) - d) >= 2
            } else {
                false
            };
            let mut f = *weighted.at(((roll(h, j, 2) * 6) / 1000).try_into().unwrap());
            if f == RUN && !can_run {
                f = first_not_run;
            }
            if f == TRILL && e.duration < 960 {
                f = UPPER;
            }
            let fig: Array<Seg> = if f == RUN {
                let nd = degree(key, note_at(events, idx, j + 1).pitch.into());
                let dir: i32 = if nd > d {
                    1
                } else {
                    -1
                };
                let g2: u32 = abs(nd - d).try_into().unwrap();
                let mut steps = g2 - 1;
                if 3 < steps {
                    steps = 3;
                }
                if e.duration / S16 - 1 < steps {
                    steps = e.duration / S16 - 1;
                }
                let mut r: Array<Seg> = array![
                    Seg { pitch: p, len: e.duration - steps * S16, vel: e.velocity },
                ];
                let mut s2: u32 = 1;
                while s2 <= steps {
                    let step: i32 = (g2 - steps - 1 + s2).try_into().unwrap();
                    r.append(Seg { pitch: pitch(key, d + dir * step), len: S16, vel });
                    s2 += 1;
                }
                r
            } else if f == TRILL {
                hold(
                    array![
                        Seg { pitch: p, len: S16, vel: e.velocity },
                        Seg { pitch: up, len: S16, vel }, Seg { pitch: p, len: S16, vel },
                        Seg { pitch: up, len: S16, vel },
                    ],
                    p,
                    e.duration,
                    vel,
                )
            } else if f == UPPER {
                hold(
                    array![
                        Seg { pitch: p, len: S16, vel: e.velocity },
                        Seg { pitch: up, len: S16, vel }, Seg { pitch: p, len: S16, vel },
                    ],
                    p,
                    e.duration,
                    vel,
                )
            } else if f == TURN {
                hold(
                    array![
                        Seg { pitch: up, len: S16, vel: e.velocity },
                        Seg { pitch: p, len: S16, vel }, Seg { pitch: down, len: S16, vel },
                        Seg { pitch: p, len: S16, vel },
                    ],
                    p,
                    e.duration,
                    vel,
                )
            } else if f == SLIDE {
                hold(
                    array![
                        Seg { pitch: pitch(key, d - 2), len: S16, vel },
                        Seg { pitch: down, len: S16, vel },
                        Seg { pitch: p, len: S16, vel: e.velocity },
                    ],
                    p,
                    e.duration,
                    vel,
                )
            } else {
                hold(
                    array![
                        Seg { pitch: p, len: S16, vel: e.velocity },
                        Seg { pitch: down, len: S16, vel }, Seg { pitch: p, len: S16, vel },
                    ],
                    p,
                    e.duration,
                    vel,
                )
            };
            figs.insert(j.into(), NullableTrait::new(fig.span()));
        }
        j += 1;
    }
    // the events with each ornamented note replaced by its figure
    let mut at: Felt252Dict<u32> = Default::default(); // event index -> note index + 1
    let mut j: u32 = 0;
    while j < n {
        at.insert((*idx.at(j)).into(), j + 1);
        j += 1;
    }
    let mut i: u32 = 0;
    while i < events.len() {
        let e = *events.at(i);
        let nj = at.get(i.into());
        let fig = if nj > 0 && pick.get((nj - 1).into()) {
            Option::Some(figs.get((nj - 1).into()).deref())
        } else {
            Option::None
        };
        match fig {
            Option::Some(segs) => {
                let mut t = e.time;
                for s in segs {
                    out
                        .append(
                            NoteEvent {
                                time: t,
                                duration: s.len,
                                pitch: clamp_pitch(s.pitch),
                                velocity: s.vel,
                                voice_id: e.voice_id,
                            },
                        );
                    t += s.len;
                }
            },
            Option::None => out.append(e),
        }
        i += 1;
    }
    out
}

// ── the avalanche
// ────────────────────────────────────────────────────────────────────────────────

fn has(xs: Span<u8>, x: u8) -> bool {
    for y in xs {
        if *y == x {
            return true;
        }
    }
    false
}

fn triad(scale: Span<u8>, d: u32) -> (u8, u8, u8) {
    (*scale.at(d % 7), *scale.at((d + 2) % 7), *scale.at((d + 4) % 7))
}

fn cover(scale: Span<u8>, d: u32, set: Span<u8>) -> u32 {
    let (a, b, c) = triad(scale, d);
    let mut k = 0;
    for q in set {
        if *q == a || *q == b || *q == c {
            k += 1;
        }
    }
    k
}

fn perfect(scale: Span<u8>, d: u32) -> u32 {
    let (a, _, c) = triad(scale, d);
    if (c + 12 - a) % 12 == 7 {
        1
    } else {
        0
    }
}

/// Appends the avalanche: in the last half bar of each section, eight or fewer sixteenths (110
/// ticks, velocity 112 falling by 4) down two octaves through the key's triad that holds the most
/// of what sounds at the close, from the root just below the tonic's register two octaves up.
pub fn yeti_avalanche(
    events: Span<NoteEvent>, section_ticks: u32, sections: u32, tonic_keynum: u8, key: YetiKey,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = array![];
    for e in events {
        out.append(*e);
    }
    let ch = YETI_AVALANCHE_VOICE;
    let top: i32 = tonic_keynum.into() + 24;
    let mut scale: Array<u8> = array![];
    let mut d: i32 = 0;
    while d < 7 {
        scale.append((pitch(key, d) % 12).try_into().unwrap());
        d += 1;
    }
    let scale = scale.span();
    let pref: Span<u32> = array![0, 4, 3, 5, 2, 1, 6].span();
    let mut s: u32 = 0;
    while s < sections {
        let end = s * section_ticks + section_ticks;
        let start = end - 960;
        // the pitch classes sounding in the half bar, and at the close (the last beat)
        let mut heard: Array<u8> = array![];
        let mut closing: Array<u8> = array![];
        let mut any = false;
        for e in events {
            let e = *e;
            if e.voice_id < ch && e.time < end && e.time + e.duration > start {
                any = true;
                let pc = e.pitch % 12;
                if !has(heard.span(), pc) {
                    heard.append(pc);
                }
                if e.time + e.duration > end - 480 && !has(closing.span(), pc) {
                    closing.append(pc);
                }
            }
        }
        if any {
            let pcs = if closing.len() > 0 {
                closing.span()
            } else {
                heard.span()
            };
            // the best: most of the close, then most of the half bar, then a perfect fifth, then
            // the preference order
            let mut best = *pref.at(0);
            let mut k = 1;
            while k < 7 {
                let c = *pref.at(k);
                let better = if cover(scale, c, pcs) != cover(scale, best, pcs) {
                    cover(scale, c, pcs) > cover(scale, best, pcs)
                } else if cover(scale, c, heard.span()) != cover(scale, best, heard.span()) {
                    cover(scale, c, heard.span()) > cover(scale, best, heard.span())
                } else {
                    perfect(scale, c) > perfect(scale, best)
                };
                if better {
                    best = c;
                }
                k += 1;
            }
            let (a, b, c) = triad(scale, best);
            let root: i32 = a.into();
            let hi = top - (((top - root) % 12) + 12) % 12;
            let mut run: Array<i32> = array![];
            let mut q = hi;
            while q >= hi - 24 {
                let pc: u8 = (((q % 12) + 12) % 12).try_into().unwrap();
                if pc == a || pc == b || pc == c {
                    run.append(q);
                }
                q -= 1;
            }
            // at most eight: every ceil(n / 8)th note and the last, the last eight of those
            let len = run.len();
            let mut picked: Array<i32> = array![];
            if len <= 8 {
                picked = run;
            } else {
                let stride = (len + 7) / 8;
                let mut all: Array<i32> = array![];
                let mut k = 0;
                while k < len {
                    if k % stride == 0 || k == len - 1 {
                        all.append(*run.at(k));
                    }
                    k += 1;
                }
                let from = if all.len() > 8 {
                    all.len() - 8
                } else {
                    0
                };
                let mut k = from;
                while k < all.len() {
                    picked.append(*all.at(k));
                    k += 1;
                }
            }
            if *picked.at(picked.len() - 1) != hi - 24 {
                picked.append(hi - 24);
            }
            let m = picked.len();
            let from = if m > 8 {
                m - 8
            } else {
                0
            };
            let count = m - from;
            let t0 = end - count * S16;
            let mut k = 0;
            while k < count {
                let vel: u32 = 112 - k * 4;
                out
                    .append(
                        NoteEvent {
                            time: t0 + k * S16,
                            duration: 110,
                            pitch: (*picked.at(from + k)).try_into().unwrap(),
                            velocity: vel.try_into().unwrap(),
                            voice_id: ch,
                        },
                    );
                k += 1;
            }
        }
        s += 1;
    }
    out
}

// ── the rock groove
// ──────────────────────────────────────────────────────────────────────────────

/// The drum track body of the rock groove: kick on 1 and 3 (and the and of 3), snare on 2 and 4,
/// eighth hats, a crash on each section's downbeat and a tom fill in its last beat.
pub fn rock_drum_track(length: u32, sec: u32) -> Array<u8> {
    let toms: Span<u8> = array![50, 48, 47, 45].span();
    let mut track = TrackWriterTrait::with_running_status();
    let mut u: u32 = 0;
    while u < length {
        let rel = u % sec;
        let q = rel % 1920;
        if rel == 0 {
            track.note_on(u, 9, 49, 110);
        }
        if rel >= sec - 480 {
            let i = (rel - (sec - 480)) / 120;
            let k = if i < 4 {
                *toms.at(i)
            } else {
                45
            };
            track.note_on(u, 9, k, (96 + i * 6).try_into().unwrap());
        } else if u % 240 == 0 {
            if q == 0 || q == 960 || q == 1200 {
                track.note_on(u, 9, 36, if q == 1200 {
                    96
                } else {
                    120
                });
            }
            if q == 480 || q == 1440 {
                track.note_on(u, 9, 38, 112);
            }
            track.note_on(u, 9, 42, if q % 480 == 0 {
                84
            } else {
                60
            });
        }
        u += 120;
    }
    track.finish_at(length)
}

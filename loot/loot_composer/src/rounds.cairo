//! Loot Dungeon Rounds: canons over a chord loop, byte-identical to `roundMidi`
//! (offchain/loot-sound/src/loot_rounds.js; read its header for the music). A chord loop in the
//! Beast's mode, one line per canon voice dealt over it, every voice playing the theme a loop after
//! the one before, an episode half way, a second loop, a cadence. Seed 0 is the species' own Round,
//! any other a purchase's; `drift` is a day of Casey Drift (month, week, day knob, age).
//! The tables are in rounds_data.cairo (generated). The readout (`info`) is the lab's only.

use core::num::traits::WrappingMul;
use beast_composer::composition::drift::Drift;
use midi::smf::{TrackWriter, TrackWriterTrait, smf_byte_array, smf_bytes};
use crate::common::{GLISS_CHANNEL, Rng, RngTrait, at32, fold64, gliss_plan, glissando, mix};
use crate::rounds_data::{
    ASSIGN3, ASSIGN4, BASS_AT, BASS_NOTES, CELL_AT, CELL_NOTES, CONTOURS, EPISODES, FAMILY, HEADS,
    LOOPS4, LOOPS8, MODE_BAD, MODE_CAD, MODE_DIM, MODE_IDS, MODE_N4, MODE_N8, MODE_SCALE, PERC_AT,
    PERC_HITS, SHAPES,
};
use crate::species::loot_species;

pub const TPQ: u16 = 480;
const SHIFTS: [u32; 8] = [0, 0, 0, 5, 7, 10, 2, 3];
const BPM0: [u32; 3] = [96, 110, 84];
const ORN_PICK: [u32; 4] = [0, 0, 1, 2];
const ORN_BASE: [u32; 3] = [0, 12, 24];
const SUS_SHARE: [u32; 3] = [35, 55, 75];
/// By meter (4/4, 6/8, 3/4): the slot, the bar, how late a suspension resolves, the time signature.
const SLOT: [u32; 3] = [960, 720, 1440];
const BAR: [u32; 3] = [1920, 1440, 1440];
const LATE: [u32; 3] = [480, 240, 480];
const SIGS: [u8; 12] = [4, 2, 24, 8, 6, 3, 36, 8, 3, 2, 24, 8];
const GLISS_WEIGHTS: [u32; 5] = [0, 1, 3, 3, 2];
const OCTAVE: [i32; 4] = [0, -1, 0, -1];
const PAN: [u8; 6] = [64, 40, 88, 52, 64, 76];
const PROGRAMS: [u8; 18] = [0, 9, 7, 15, 17, 13, 2, 1, 8, 12, 19, 6, 3, 4, 5, 16, 14, 18];
const MEGA_LEADS: [u8; 2] = [50, 65];
const EP_UNITS: u32 = 7;
const EP_SLOTS: u32 = 8;
const BIG: u32 = 0x40000000;

/// A note of a part: start, length, scale degree (from the tonic), whether it starts a chord tone,
/// its ornament (0 none, 1-6) and the degree the ornament leads to.
#[derive(Copy, Drop)]
pub struct Note {
    pub t: u32,
    pub len: u32,
    pub d: i32,
    pub anchor: bool,
    pub grace: u32,
    pub to: i32,
}

/// A sounding note: start, length, MIDI key, velocity.
#[derive(Copy, Drop)]
pub struct Sound {
    pub t: u32,
    pub len: u32,
    pub p: i32,
    pub v: u32,
}

pub use crate::common::opaque;

// ── small arithmetic ──

/// ((d % 7) + 7) % 7.
#[inline(never)]
pub fn mod7(d: i32) -> u32 {
    m7(d.into())
}

/// ((d % 7) + 7) % 7 of a small signed value held in a felt.
#[inline(never)]
pub fn m7(d: felt252) -> u32 {
    let x: u32 = (d + 7000).try_into().unwrap();
    x % 7
}

/// A small signed value held in a felt, as an i32 (the arithmetic before it unchecked: CASM size).
#[inline(never)]
pub fn to_i(x: felt252) -> i32 {
    x.try_into().unwrap()
}

pub fn abs(x: i32) -> i32 {
    if x < 0 {
        to_i(-x.into())
    } else {
        x
    }
}

pub fn sign(x: i32) -> i32 {
    if x > 0 {
        1
    } else if x < 0 {
        -1
    } else {
        0
    }
}

pub fn i(x: u32) -> i32 {
    to_i(x.into())
}

/// The degree of scale-degree class `cls` nearest to `prev`.
#[inline(never)]
pub fn nearest(prev: i32, cls: u32) -> i32 {
    let p: felt252 = prev.into();
    let m = m7(cls.into() - p);
    to_i(p + m.into() - if m > 3 {
        7
    } else {
        0
    })
}

#[inline(never)]
fn passing(a: i32, b: i32) -> i32 {
    let fa: felt252 = a.into();
    let d = to_i(b.into() - fa);
    if d >= 2 || d == 0 {
        to_i(fa + 1)
    } else if d <= -2 {
        to_i(fa - 1)
    } else {
        b
    }
}

fn skip(a: i32, role: u32, up: bool) -> i32 {
    let fa: felt252 = a.into();
    to_i(
        if up {
            fa + if role == 2 {
                3
            } else {
                2
            }
        } else {
            fa - if role == 0 {
                3
            } else {
                2
            }
        },
    )
}

/// |a - b| <= 1, for small signed values held in felts.
fn near1(a: felt252, b: felt252) -> bool {
    let y = a - b + 1;
    y == 0 || y == 1 || y == 2
}

/// `base + 12 * floor(d / 7) + scale[mod7(d)]`.
#[inline(never)]
pub fn pitch_of(base: i32, scale: Span<u32>, d: felt252) -> i32 {
    let x: u32 = (d + 7000).try_into().unwrap();
    let (q, r) = DivRem::div_rem(x, 7);
    let s: felt252 = (*scale.at(r)).into();
    to_i(base.into() + 12 * q.into() - 12000 + s)
}

/// A mode's index in ROUND_MODES.
#[inline(never)]
pub fn mode_index(mode: u32) -> u32 {
    let ids = MODE_IDS.span();
    let mut k: u32 = opaque(0);
    while k != 6 {
        let m: u32 = (*ids.at(k)).into();
        if m == mode {
            break;
        }
        k += 1;
    }
    assert(k < 6, 'round: mode');
    k
}

/// `n` base-`b` digits of `v`, the lowest first.
#[inline(never)]
pub fn unpack(v: u32, b: u32, n: u32) -> Span<u32> {
    let mut out = opaque(array![]);
    let mut x = v;
    let mut k: u32 = opaque(0);
    while k != n {
        out.append(x % b);
        x /= b;
        k += 1;
    }
    out.span()
}

pub fn unpack_i(v: u32, b: u32, n: u32) -> Span<i32> {
    let mut out = opaque(array![]);
    for x in unpack(v, b, n) {
        out.append(i(*x));
    }
    out.span()
}

/// A mode's scale.
#[inline(never)]
pub fn mode_scale(mx: u32) -> Span<u32> {
    unpack(*MODE_SCALE.span().at(mx), 16, 7)
}

/// The cadence root of a mode (by index).
pub fn mode_cad(mx: u32) -> u32 {
    *MODE_CAD.span().at(mx)
}

/// The `idx`-th loop of the mode whose bad degrees are `bad`: roots.
#[inline(never)]
fn pool_loop(eight: bool, bad: u32, idx: u32) -> Span<u32> {
    let (tab, n, place): (Span<felt252>, u32, u32) = if eight {
        (LOOPS8.span(), 8, 0x1000000)
    } else {
        (LOOPS4.span(), 4, 0x1000)
    };
    let mut c: u32 = opaque(0);
    let mut k: u32 = opaque(0);
    loop {
        let v = at32(tab, k);
        if (v / place) & bad == 0 {
            if c == idx {
                break unpack(v % place, 8, n);
            }
            c += 1;
        }
        k += 1;
    }
}

// ── the deals ──
// A deal (which member of the chord, 0 root, 1 third, 2 fifth, each line holds) is a base-3 code:
// line j's member at 3^j.

/// Line j's member in deal `c`.
#[inline(never)]
pub fn dig(c: u32, j: u32) -> u32 {
    if j == 0 {
        c % 3
    } else if j == 1 {
        (c / 3) % 3
    } else if j == 2 {
        (c / 9) % 3
    } else {
        c / 27
    }
}

/// A deal's four members (the fourth 0 for three lines).
fn digits4(c: u32) -> (u32, u32, u32, u32) {
    let (d3, r) = DivRem::div_rem(c, 27);
    let (d2, r) = DivRem::div_rem(r, 9);
    let (d1, d0) = DivRem::div_rem(r, 3);
    (d0, d1, d2, d3)
}

/// The code of a deal given as members.
fn code(d: Span<u32>) -> u32 {
    let mut c: u32 = opaque(0);
    let mut p = 1;
    for x in d {
        c += *x * p;
        p *= 3;
    }
    c
}

/// A deal's own cost: 1 when it doubles the third, 1 for each member of the chord it leaves out.
#[inline(never)]
fn deal_cost(b: u32, k: u32) -> u32 {
    let (b0, b1, b2, b3) = digits4(b);
    let four = k == 4;
    let ones: felt252 = one_if(b0 == 1)
        + one_if(b1 == 1)
        + one_if(b2 == 1)
        + one_if(four && b3 == 1);
    let has0 = b0 == 0 || b1 == 0 || b2 == 0 || (four && b3 == 0);
    let has2 = b0 == 2 || b1 == 2 || b2 == 2 || (four && b3 == 2);
    let c = one_if(!(ones == 0 || ones == 1)) + one_if(!has0) + one_if(ones == 0) + one_if(!has2);
    c.try_into().unwrap()
}

#[inline(always)]
fn one_if(x: bool) -> felt252 {
    if x {
        1
    } else {
        0
    }
}

#[inline(always)]
fn kept(x: u32, y: u32) -> felt252 {
    if x == y && x != 1 {
        8
    } else {
        0
    }
}

#[inline(always)]
fn pair(ax: u32, ay: u32, bx: u32, by: u32, swap: felt252) -> felt252 {
    (if ax == ay && bx == by {
        8
    } else {
        0
    })
        + if ax != 1 && ay != 1 && ax != ay && bx == ay && by == ax {
            swap
        } else {
            0
        }
}

/// loot_rounds.js `dealPenalty(a, b, changed, swap)` for deals of k lines.
#[inline(never)]
fn deal_penalty(a: u32, b: u32, k: u32, changed: bool, swap: u32) -> u32 {
    if !changed {
        return if a == b {
            1
        } else {
            0
        };
    }
    let (a0, a1, a2, a3) = digits4(a);
    let (b0, b1, b2, b3) = digits4(b);
    let swap: felt252 = swap.into();
    let p = kept(a0, b0)
        + kept(a1, b1)
        + kept(a2, b2)
        + pair(a0, a1, b0, b1, swap)
        + pair(a0, a2, b0, b2, swap)
        + pair(a1, a2, b1, b2, swap);
    let p = if k == 4 {
        p
            + kept(a3, b3)
            + pair(a0, a3, b0, b3, swap)
            + pair(a1, a3, b1, b3, swap)
            + pair(a2, a3, b2, b3, swap)
    } else {
        p
    };
    p.try_into().unwrap()
}

/// The deals of K lines (ASSIGN[K]), as codes.
fn assign(k: u32) -> Span<u32> {
    if k == 4 {
        ASSIGN4.span()
    } else {
        ASSIGN3.span()
    }
}

fn shape_want(shape: u32, s: u32, n: u32) -> i32 {
    if shape == 0 {
        -1
    } else if shape == 1 {
        1
    } else if shape == 3 {
        0
    } else if (2 * s <= n) == (shape == 2) {
        1
    } else {
        -1
    }
}

fn shape_restart(shape: u32, s: u32, n: u32) -> bool {
    shape < 2 && n == 8 && s == 4
}

#[inline(never)]
fn shape_delta(want: i32, diff: felt252) -> i32 {
    let u = m7(diff);
    let neg = if want == 0 {
        u > 3
    } else if u == 0 {
        false
    } else if want > 0 {
        u > 4
    } else {
        u >= 3
    };
    to_i(u.into() - if neg {
        7
    } else {
        0
    })
}

#[inline(never)]
fn move_cost(shape: u32, c1: u32, c2: u32, s: u32, n: u32) -> u32 {
    if shape_restart(shape, s, n) {
        return 0;
    }
    let want = shape_want(shape, s, n);
    let d = shape_delta(want, c2.into() - c1.into());
    if want == 0 {
        return if d == 1 || d == -1 {
            0
        } else if d == 3 || d == -3 {
            2
        } else {
            1
        };
    }
    if d == 0 {
        2
    } else if (d > 0) != (want > 0) || d > 2 || d < -2 {
        1
    } else {
        0
    }
}

/// What the lines' moves into slot s cost, by line and members: [j * 9 + a * 3 + b].
#[inline(never)]
fn move_table(shapes: Span<u32>, chords: Span<u32>, s: u32) -> Span<u32> {
    let n = chords.len();
    let c1 = *chords.at(s - 1);
    let c2 = *chords.at(s);
    let mut out = opaque(array![]);
    for shape in shapes {
        let mut a: u32 = opaque(0);
        while a != 3 {
            let mut b: u32 = opaque(0);
            while b != 3 {
                out.append(move_cost(*shape, c1 + 2 * a, c2 + 2 * b, s, n));
                b += 1;
            }
            a += 1;
        }
    }
    out.span()
}

#[inline(never)]
fn moves(mt: Span<u32>, a: u32, b: u32, k: u32) -> u32 {
    let (a0, a1, a2, a3) = digits4(a);
    let (b0, b1, b2, b3) = digits4(b);
    let p: felt252 = (*mt.at(a0 * 3 + b0)).into()
        + (*mt.at(9 + a1 * 3 + b1)).into()
        + (*mt.at(18 + a2 * 3 + b2)).into();
    let p = if k == 4 {
        p + (*mt.at(27 + a3 * 3 + b3)).into()
    } else {
        p
    };
    p.try_into().unwrap()
}

/// loot_rounds.js `dealRoles`: the deal of each slot, as codes. (The look ahead at the slot before the
/// last takes the deals of the last slot in order of what they cost apart from the move into them, and
/// stops where that alone is no cheaper than the best found: the same minimum. A candidate already no
/// cheaper than the best without it is not looked ahead from.)
#[inline(never)]
fn deal_roles(
    ac: Span<u32>, k: u32, chords: Span<u32>, ref h: Rng, forced: u32, shapes: Span<u32>,
) -> Span<u32> {
    let n_s = chords.len();
    let n = ac.len();
    let mut first = opaque(array![]);
    for d in ac {
        if *d % 3 == 0 && deal_cost(*d, k) == 0 {
            first.append(*d);
        }
    }
    let r0 = *first.at(h.int(first.len()));
    // every line moves on to the next: line j takes line j + 1's member
    let mut turn: u32 = opaque(0);
    let mut p3 = 1;
    let mut j: u32 = opaque(0);
    while j != k {
        turn += dig(r0, (j + 1) % k) * p3;
        p3 *= 3;
        j += 1;
    }
    let chg0 = *chords.at(0) != *chords.at(n_s - 1);
    let mt_last = move_table(shapes, chords, n_s - 1);
    let chg_last = *chords.at(n_s - 1) != *chords.at(n_s - 2);
    let mut tails = opaque(array![]);
    let mut ci: u64 = 0;
    for c in ac {
        let tail: u64 = (deal_cost(*c, k) + 16 * deal_penalty(*c, turn, k, chg0, 2)).into();
        tails.append(tail * 64 + ci);
        ci += 1;
    }
    let tails = sort_keys(tails.span());
    let mut roles = array![r0];
    let mut prev = r0;
    let mut s: u32 = opaque(1);
    while s != n_s {
        let start = h.int(n);
        let mt = move_table(shapes, chords, s);
        let chg = *chords.at(s) != *chords.at(s - 1);
        let mut best = prev;
        let mut best_p = BIG;
        let mut kk: u32 = opaque(0);
        while kk != n {
            let b = *ac.at((start + kk) % n);
            if !(s == 1 && b % 3 != forced) {
                let mut p = 16 * deal_penalty(prev, b, k, chg, 2)
                    + deal_cost(b, k)
                    + moves(mt, prev, b, k);
                if s == n_s - 1 {
                    p += 16 * deal_penalty(b, turn, k, chg0, 2);
                }
                if s == n_s - 2 && p < best_p {
                    let mut ahead = BIG;
                    for key in tails {
                        let tail: u32 = (*key / 64).try_into().unwrap();
                        if tail >= ahead {
                            break;
                        }
                        let c = *ac.at((*key % 64).try_into().unwrap());
                        let q = 16 * deal_penalty(b, c, k, chg_last, 2)
                            + moves(mt_last, b, c, k)
                            + tail;
                        if q < ahead {
                            ahead = q;
                        }
                    }
                    p += ahead;
                }
                if p < best_p {
                    best = b;
                    best_p = p;
                }
            }
            kk += 1;
        }
        roles.append(best);
        prev = best;
        s += 1;
    }
    roles.span()
}

/// The cheapest deal between two others (`joinDeal`), as codes of k lines: `next` none for none.
#[inline(never)]
fn join_deal(
    a: Span<u32>,
    k: u32,
    prev: u32,
    changed_prev: bool,
    next: Option<u32>,
    changed_next: bool,
    start: u32,
) -> u32 {
    let n = a.len();
    let mut best = *a.at(0);
    let mut best_p = BIG;
    let mut x: u32 = opaque(0);
    while x != n {
        let b = *a.at((start + x) % n);
        let p = deal_penalty(prev, b, k, changed_prev, 8)
            + match next {
                Option::Some(y) => deal_penalty(b, y, k, changed_next, 8),
                Option::None => 0,
            }
            + deal_cost(b, k);
        if p < best_p {
            best = b;
            best_p = p;
        }
        x += 1;
    }
    best
}

// ── the round ──

#[derive(Copy, Drop)]
struct Ctx {
    k: u32,
    n_s: u32,
    sl: u32,
    late: u32,
    mi: u32,
    hr: u32,
    typ: u32,
    motif: Span<i32>,
    head: Span<u32>,
    centre: Span<i32>,
    shapes: Span<u32>,
    sus_share: u32,
    orn: u32,
    stage: u32,
    orn_seed: u32,
    palette: Span<u32>,
    role_seed: u32,
    cell_seed: u32,
    ac: Span<u32>,
}

#[derive(Copy, Drop)]
struct Rd {
    loop_: Span<u32>,
    chords: Span<u32>,
    /// Each slot's deal (a code).
    roles: Span<u32>,
    /// Line j at level l: [j * 3 + l].
    lines: Span<Span<Note>>,
}

fn note(t: u32, len: u32, d: i32, anchor: bool) -> Note {
    Note { t, len, d, anchor, grace: 0, to: 0 }
}

/// A slot's notes from a cell (`cellNotes`).
#[inline(never)]
fn cell_notes(mi: u32, cell: u32, t0: u32, a: i32, next: i32, role: u32) -> Array<Note> {
    let at = CELL_AT.span();
    let cells = CELL_NOTES.span();
    let mut k = at32(at, mi * 12 + cell);
    let stop = at32(at, mi * 12 + cell + 1);
    let mut out = opaque(array![]);
    let mut p = a;
    while k != stop {
        let x = at32(cells, k);
        let off = x / 65536;
        let len = (x / 8) % 8192;
        let src = x % 8;
        if src != 5 {
            let d = if src == 0 {
                a
            } else if src == 1 {
                passing(p, next)
            } else if src == 2 {
                a + 1
            } else if src == 3 {
                a - 1
            } else {
                skip(a, role, next >= a)
            };
            out.append(note(t0 + off, len, d, off == 0));
            p = d;
        }
        k += 1;
    }
    out
}

/// `ornament(notes, key, after)`, appended to `out`.
#[inline(never)]
fn ornament(ref out: Array<Note>, cb: Box<Ctx>, notes: Span<Note>, key: u32, after: i32) {
    let c = cb.unbox();
    let n = notes.len();
    let orn = c.orn;
    let stage = c.stage;
    let orn_seed = c.orn_seed;
    let pal: Span<u32> = c.palette;
    let min_len = if stage >= 3 {
        240
    } else {
        480
    };
    let mut k: u32 = opaque(0);
    while k != n {
        let x = *notes.at(k);
        if orn == 0 || x.len < min_len || (stage < 1 && !x.anchor) {
            out.append(x);
        } else {
            let h = mix(orn_seed, key * 8 + k);
            if h % 100 < orn {
                let to = if k + 1 < n {
                    notes.at(k + 1).d
                } else {
                    after
                };
                out.append(Note { grace: *pal.at((h / 256) % pal.len()), to, ..x });
            } else {
                out.append(x);
            }
        }
        k += 1;
    }
}

const ACTIVITY: [u32; 12] = [1, 0, 1, 0, 1, 1, 2, 0, 2, 1, 2, 1];

/// The motif's weak note: kept when it moves by step, else a passing note.
#[inline(never)]
fn weak_of(want: felt252, a: i32, next: i32) -> i32 {
    if near1(want, a.into()) || near1(want, next.into()) {
        to_i(want)
    } else {
        passing(a, next)
    }
}

/// Line j at a level (`lineNotes`).
#[inline(never)]
fn line_notes(
    cb: Box<Ctx>,
    chords: Span<u32>,
    roles: Span<u32>,
    theme: Span<i32>,
    sus: Span<bool>,
    j: u32,
    level: u32,
    tag: u32,
    cseed: u32,
) -> Span<Note> {
    let c = cb.unbox();
    let n_s = c.n_s;
    let k = c.k;
    let sl = c.sl;
    let late = c.late;
    let mi = c.mi;
    let fam = at32(FAMILY.span(), c.mi * 9 + c.typ * 3 + *ACTIVITY.span().at(level * 4 + j));
    let h = mix(cseed, j * 8 + level + 1);
    let mut picks = opaque(array![]);
    let mut q: u32 = opaque(0);
    let mut hh = h;
    while q != 5 {
        picks.append(fam / pow16(hh % 4) % 16);
        hh /= 4;
        q += 1;
    }
    let end = if level == 0 {
        (h / 1024) % 2
    } else {
        *picks.at(4)
    };
    let p0 = *picks.at(0);
    let p1 = *picks.at(1);
    let p2 = *picks.at(2);
    let plan = if n_s == 8 {
        array![p0, p1, p0, p2, p0, p1, *picks.at(3), end]
    } else {
        array![p0, p1, p2, end]
    };
    let motif = c.motif;
    let w0: felt252 = (*motif.at(1)).into() - (*motif.at(0)).into();
    let w1: felt252 = (*motif.at(3)).into() - (*motif.at(2)).into();
    let head = c.head;
    let mut out = opaque(array![]);
    let mut s: u32 = opaque(0);
    while s != n_s {
        let a = *theme.at(j * n_s + s);
        let next = if s + 1 < n_s {
            *theme.at(j * n_s + s + 1)
        } else {
            *theme.at(((j + 1) % k) * n_s)
        };
        let okey = tag * 1024 + j * 64 + s * 4 + level;
        let held = s > 0 && *sus.at(j * n_s + s - 1);
        let here = *sus.at(j * n_s + s);
        let notes = if s < 2 {
            let want: felt252 = a.into()
                + if s == 0 {
                    w0
                } else {
                    w1
                };
            let l0 = *head.at(2 * s);
            let l1 = *head.at(2 * s + 1);
            let weak = weak_of(want, a, next);
            array![note(s * sl, l0, a, true), note(s * sl + l0, l1, weak, false)]
        } else if held || here {
            let t = s * sl
                + if held {
                    late
                } else {
                    0
                };
            let len = (if held {
                sl - late
            } else {
                sl
            })
                + if here {
                    late
                } else {
                    0
                };
            array![note(t, len, a, !held)]
        } else {
            cell_notes(mi, *plan.at(s), s * sl, a, next, dig(*roles.at(s), j))
        };
        if s < 2 && j == 0 {
            out.append_span(notes.span());
        } else {
            ornament(ref out, cb, notes.span(), okey, next);
        }
        s += 1;
    }
    out.span()
}

fn pow16(e: u32) -> u32 {
    if e == 0 {
        1
    } else if e == 1 {
        16
    } else if e == 2 {
        256
    } else {
        4096
    }
}

const SHAPE_START: [i32; 5] = [2, -2, -2, 0, 2];

/// A round over a loop (`makeRound`): its deals, its theme and its lines.
#[inline(never)]
fn make_round(cb: Box<Ctx>, loop_: Span<u32>, tag: u32) -> Box<Rd> {
    let c = cb.unbox();
    let sus_share = c.sus_share;
    let hr = c.hr;
    let n_s = c.n_s;
    let k = c.k;
    let mut ch = opaque(array![]);
    for r in loop_ {
        ch.append(*r);
        if hr == 0 {
            ch.append(*r);
        }
    }
    let chords = ch.span();
    let motif = c.motif;
    let m2 = *motif.at(2);
    let c1 = *chords.at(1);
    let mut forced = if c1 == *chords.at(0) {
        0
    } else {
        1
    };
    let mut r = forced;
    while r != 3 {
        let fm2: felt252 = m2.into();
        if abs(to_i(nearest(m2, (c1 + 2 * r) % 7).into() - fm2)) < abs(
            to_i(nearest(m2, (c1 + 2 * forced) % 7).into() - fm2),
        ) {
            forced = r;
        }
        r += 1;
    }
    let mut h = RngTrait::new(mix(c.role_seed, tag));
    let roles = deal_roles(c.ac, k, chords, ref h, forced, c.shapes);
    let cseed = mix(c.cell_seed, tag);
    // the theme's chord tones
    let shapes = c.shapes;
    let centre = c.centre;
    let mut theme = opaque(array![]);
    let mut j: u32 = opaque(0);
    while j != k {
        let shape = *shapes.at(j);
        let cj = *centre.at(j);
        let mut prev: i32 = 0;
        let mut s: u32 = opaque(0);
        while s != n_s {
            let cls = (*chords.at(s) + 2 * dig(*roles.at(s), j)) % 7;
            let d = if j == 0 && s == 0 {
                0
            } else if j == 0 && s == 1 {
                nearest(m2, cls)
            } else if s == 0 || shape_restart(shape, s, n_s) {
                nearest(to_i(cj.into() + (*SHAPE_START.span().at(shape)).into()), cls)
            } else {
                let fp: felt252 = prev.into();
                let x = fp + shape_delta(shape_want(shape, s, n_s), cls.into() - fp).into();
                let dd = to_i(x - cj.into());
                to_i(
                    if dd > 6 {
                        x - 7
                    } else if dd < -6 {
                        x + 7
                    } else {
                        x
                    },
                )
            };
            theme.append(d);
            prev = d;
            s += 1;
        }
        j += 1;
    }
    let theme = theme.span();
    // suspensions
    let mut sus = opaque(array![]);
    let mut j: u32 = opaque(0);
    while j != k {
        let mut s: u32 = opaque(0);
        while s != n_s {
            let a = *theme.at(j * n_s + s);
            let mut v = false;
            if s >= 2 && s + 1 < n_s && *chords.at(s + 1) != *chords.at(s)
                && (*theme.at(j * n_s + s + 1)).into() == a.into() - 1_felt252 {
                let nr = *roles.at(s + 1);
                let mine = dig(nr, j);
                let mut cnt: u32 = opaque(0);
                let mut x: u32 = opaque(0);
                while x != k {
                    if dig(nr, x) == mine {
                        cnt += 1;
                    }
                    x += 1;
                }
                v = cnt == 1 && mix(cseed ^ 0x5355, j * 16 + s) % 100 < sus_share;
            }
            sus.append(v);
            s += 1;
        }
        j += 1;
    }
    let sus = sus.span();
    let mut lines = opaque(array![]);
    let mut j: u32 = opaque(0);
    while j != k {
        let mut level: u32 = opaque(0);
        while level != 3 {
            lines.append(line_notes(cb, chords, roles, theme, sus, j, level, tag, cseed));
            level += 1;
        }
        j += 1;
    }
    BoxTrait::new(Rd { loop_, chords, roles, lines: lines.span() })
}

// ── the file ──

/// A voice's sounding notes (`soundingNotes`), graces written out, appended to `out`.
#[inline(never)]
pub fn sounding(
    ref out: Array<Sound>, part: Span<Note>, base: i32, scale: Span<u32>, art: u32, bar: u32,
) {
    for n in part {
        let n = *n;
        let len = if art == 2 && n.len <= 480 {
            n.len / 2
        } else {
            n.len
                - if art == 1 {
                    5
                } else {
                    20
                }
        };
        let v: u32 = if n.anchor {
            if n.t % bar == 0 {
                96
            } else {
                88
            }
        } else {
            76
        };
        let mut g = n.grace;
        let gap = to_i(n.to.into() - n.d.into());
        let step = if g == 0 {
            0
        } else {
            sign(gap)
        };
        if g == 6 && (n.len < 480 || (gap < 3 && gap > -3)) {
            g = 3;
        }
        if (g == 5 && len < 360) || (g == 4 && len < 300) {
            g = 3;
        }
        if (g == 3 && len < 180) || ((g == 1 || g == 2) && len < 120) {
            g = 0;
        }
        if g == 6 {
            out.append(Sound { t: n.t, len: n.len - 260, p: pitch_of(base, scale, n.d.into()), v });
            out
                .append(
                    Sound {
                        t: n.t + n.len - 240, len: 120, p: pitch_of(base, scale, n.d.into() + step.into()), v: v - 12,
                    },
                );
            out
                .append(
                    Sound {
                        t: n.t + n.len - 120,
                        len: 100,
                        p: pitch_of(base, scale, n.d.into() + 2 * step.into()),
                        v: v - 8,
                    },
                );
        } else {
            // the figure's notes (a grace: one, 80 ticks, quieter; else 32nds, the first at full
            // velocity), then the note itself
            let (ds, unit, v0): (Span<i32>, u32, u32) = if g == 1 {
                (FIG_UP.span(), 80, v - 10)
            } else if g == 2 {
                (FIG_DOWN.span(), 80, v - 10)
            } else if g == 3 {
                (FIG_MORDENT.span(), 60, v)
            } else if g == 4 {
                (FIG_TURN.span(), 60, v)
            } else if g == 5 {
                (if len >= 700 {
                    FIG_TRILL6.span()
                } else {
                    FIG_TRILL4.span()
                }, 60, v)
            } else {
                (FIG_NONE.span(), 60, v)
            };
            let mut k: u32 = opaque(0);
            for x in ds {
                out
                    .append(
                        Sound {
                            t: n.t + k * unit,
                            len: unit,
                            p: pitch_of(base, scale, n.d.into() + (*x).into()),
                            v: if k == 0 {
                                v0
                            } else {
                                v - 10
                            },
                        },
                    );
                k += 1;
            }
            out.append(Sound { t: n.t + k * unit, len: len - k * unit, p: pitch_of(base, scale, n.d.into()), v });
        }
    }
}

const FIG_UP: [i32; 1] = [1];
const FIG_DOWN: [i32; 1] = [-1];
const FIG_MORDENT: [i32; 2] = [0, 1];
const FIG_TURN: [i32; 3] = [1, 0, -1];
const FIG_TRILL4: [i32; 4] = [0, 1, 0, 1];
const FIG_TRILL6: [i32; 6] = [0, 1, 0, 1, 0, 1];
const FIG_NONE: [i32; 0] = [];

/// Sorts distinct keys (a natural merge sort: the runs already in order, then merged pairwise).
#[inline(never)]
pub fn sort_keys(xs: Span<u64>) -> Span<u64> {
    let n = xs.len();
    if n < 2 {
        return xs;
    }
    let mut runs: Array<Span<u64>> = opaque(array![]);
    let mut start: u32 = opaque(0);
    let mut k = 1;
    while k != n {
        if *xs.at(k) < *xs.at(k - 1) {
            runs.append(xs.slice(start, k - start));
            start = k;
        }
        k += 1;
    }
    runs.append(xs.slice(start, n - start));
    while runs.len() > 1 {
        let mut merged: Array<Span<u64>> = opaque(array![]);
        loop {
            match runs.pop_front() {
                Option::Some(a) => match runs.pop_front() {
                    Option::Some(b) => merged.append(merge(a, b)),
                    Option::None => { merged.append(a); },
                },
                Option::None => { break; },
            }
        }
        runs = merged;
    }
    runs.pop_front().unwrap()
}

#[inline(never)]
fn merge(a: Span<u64>, b: Span<u64>) -> Span<u64> {
    let mut out = opaque(array![]);
    let mut a = a;
    let mut b = b;
    let mut x = *a.pop_front().unwrap();
    let mut y = *b.pop_front().unwrap();
    loop {
        if x < y {
            out.append(x);
            match a.pop_front() {
                Option::Some(n) => { x = *n; },
                Option::None => {
                    out.append(y);
                    out.append_span(b);
                    break;
                },
            }
        } else {
            out.append(y);
            match b.pop_front() {
                Option::Some(n) => { y = *n; },
                Option::None => {
                    out.append(x);
                    out.append_span(a);
                    break;
                },
            }
        }
    }
    out.span()
}

/// How the lab plays a file: each pitched channel's program from `band[ch % band.len()]` (as
/// written when empty) and its notes raised `lift` semitones, at most to 127; drums untouched.
/// Written into the tracks directly: the same bytes as `orchestra::orchestrate` on the written file.
#[derive(Copy, Drop)]
pub struct Play {
    pub band: Span<u8>,
    pub lift: u8,
}

/// The file as written.
pub fn as_written() -> Play {
    Play { band: array![].span(), lift: 0 }
}

/// A part's track (`track` in roundMidi, `smfFile`'s parts): program, volume, pan, reverb (none for
/// channel 9), then the notes' on and off events by time, offs before ons at the same tick, in the
/// order the notes come otherwise.
#[inline(never)]
pub fn note_track(
    ch: u8, program: u8, vol: u8, pan: u8, notes: Span<Sound>, end: u32, play: Play,
) -> Array<u8> {
    let mut tw = TrackWriterTrait::new();
    let lift: u8 = if ch != 9 {
        play.lift
    } else {
        0
    };
    if ch != 9 {
        let nb = play.band.len();
        tw.program(0, ch, if nb != 0 {
            *play.band.at(ch.into() % nb)
        } else {
            program
        });
        tw.control(0, ch, 7, vol);
        tw.control(0, ch, 10, pan);
        tw.control(0, ch, 91, 40);
    }
    let mut keys: Array<u64> = opaque(array![]);
    let mut offs: Array<u64> = opaque(array![]);
    let mut idx: u64 = 0;
    for n in notes {
        let n = *n;
        assert(n.p >= 0 && n.p <= 127 && n.len > 0, 'round: note out of range');
        let p: u64 = n.p.try_into().unwrap();
        let t: u64 = n.t.into();
        let off: u64 = (n.t + n.len).into();
        keys.append((((t * 8 + 5) * 0x10000 + idx) * 0x100 + p) * 0x100 + n.v.into());
        offs.append((((off * 8 + 4) * 0x10000 + idx) * 0x100 + p) * 0x100);
        idx += 1;
    }
    keys.append_span(offs.span());
    for key in sort_keys(keys.span()) {
        let key = *key;
        let tv: u32 = (key / 0x100000000).try_into().unwrap();
        let mut p: u8 = ((key / 0x100) % 0x100).try_into().unwrap();
        if lift != 0 {
            p = if p > 127 - lift {
                127
            } else {
                p + lift
            };
        }
        let v: u8 = (key % 0x100).try_into().unwrap();
        let time = tv / 8;
        if tv % 8 == 5 {
            tw.note_on(time, ch, p, v);
        } else {
            tw.note_off(time, ch, p, 0);
        }
    }
    tw.finish_at(end)
}

/// The tempo track: tempo and time signature at 0, closed at `end`.
#[inline(never)]
pub fn tempo_track(us: u32, sig: Span<u8>, end: u32) -> Array<u8> {
    let mut tw: TrackWriter = TrackWriterTrait::new();
    tw.tempo(0, us);
    tw.meta(0, 0x58, sig);
    tw.finish_at(end)
}

/// TinyChip programs (FAMILIES): leads then plucks, by family.
pub fn family_programs(typ: u32) -> Span<u8> {
    PROGRAMS.span().slice(typ * 6, 6)
}

/// The channels' programs: [lead, second lead, pluck, second pluck, bass, mega double].
#[inline(never)]
pub fn programs_of(id: u32, typ: u32, mega: bool) -> Span<u8> {
    let f = family_programs(typ);
    let lead = id % 3;
    let mega_leads = MEGA_LEADS.span();
    let (p0, p5) = if mega {
        (*mega_leads.at(id % 2), *mega_leads.at((id + 1) % 2))
    } else {
        (*f.at(lead), 0)
    };
    array![p0, *f.at((lead + 1) % 3), *f.at(4), *f.at(5), *f.at(3), p5].span()
}

pub fn is_lead(p: u8) -> bool {
    p < 12 || p == 50 || p == 65
}

pub fn low32(x: felt252) -> u32 {
    let w: u256 = x.into();
    (w.low % 0x100000000).try_into().unwrap()
}

/// The Round's tracks: tempo, the canon voices by channel, the bass, the mega double, the harp, the kit.
pub fn round_tracks(
    species: u32, mega: bool, seed: u64, drift: Option<Drift>, play: Play,
) -> Array<Array<u8>> {
    let sp = loot_species(species);
    let id = sp.id;
    let tier: u32 = sp.tier.into();
    let typ: u32 = sp.beast_type.into();
    let mut r = RngTrait::new(fold64(seed) ^ id.wrapping_mul(0x85ebca77) ^ 0x524f554e);
    let k: u32 = if tier <= 2 {
        4
    } else {
        3
    };
    // the purchase's draws, in a fixed order
    let shift = *SHIFTS.span().at(r.int(8));
    let keep_mode = r.int(2);
    let mode_pick = r.int(6);
    let bpm0 = *BPM0.span().at(typ) + r.int(29);
    let loop_draw = r.int(65536);
    let mut hr = r.int(3);
    let mut contour = r.int(4);
    let mut role_seed = r.next();
    let mut cell_seed = r.next();
    let mut bass_fig = r.int(6);
    let mut bass_on = true;
    if tier > 3 {
        bass_on = r.int(100) < 70;
    }
    let mut perc_i = r.int(3);
    let perc_share = if tier <= 2 {
        70
    } else {
        40
    };
    let mut perc_on = r.int(100) < perc_share;
    let mut ep_kind = r.int(6);
    let mut ep_leader = r.int(k);
    let mut orn_i = *ORN_PICK.span().at(r.int(4));
    let orn_seed = r.int(100);
    let orn_kind = r.int(3);
    let mut shape = r.int(4);
    let mut sus_i = r.int(3);
    let loop_draw_b = r.int(65536);
    let gl_draw = r.int(20);
    let gl_seed0 = r.next();
    let meter_draw = r.int(100);
    let mi = if typ == 0 {
        if meter_draw < 50 {
            1
        } else if meter_draw < 75 {
            2
        } else {
            0
        }
    } else if meter_draw < 60 {
        0
    } else if typ == 1 {
        1
    } else {
        2
    };
    let sl = *SLOT.span().at(mi);
    let br = *BAR.span().at(mi);
    let late = *LATE.span().at(mi);
    let cadl = br;
    let own = seed == 0;
    let tonic_pc: u32 = sp.tonic_pc.into();
    let tonic = if own {
        tonic_pc
    } else {
        (tonic_pc + shift) % 12
    };
    let mx = if own || keep_mode == 1 {
        mode_index(sp.mode.into())
    } else {
        mode_pick
    };
    // drift
    let mut rot: u32 = opaque(0);
    let mut level0: u32 = opaque(0);
    let mut reverse = false;
    let mut bpm_delta: i64 = 0;
    let mut art: u32 = opaque(0);
    let mut loop_step: u32 = opaque(0);
    let mut gl_seed = gl_seed0;
    let mut age: u64 = 1;
    if let Option::Some(dr) = drift {
        if let Option::Some(x) = dr.rhythm {
            let m = low32(x);
            loop_step = 1 + m % 5;
            hr = (hr + 1 + (m / 0x100) % 2) % 3;
            role_seed = role_seed ^ m;
            cell_seed = cell_seed ^ m.wrapping_mul(0x9e3779b1);
            shape = (shape + 1 + (m / 0x1000) % 3) % 4;
        }
        if let Option::Some(x) = dr.rotate {
            let w = low32(x);
            rot = 1 + w % (k - 1);
            contour = (contour + 1 + (w / 16) % 3) % 4;
            let part = (w / 0x100) % 3;
            if part == 0 {
                bass_on = !bass_on;
            } else if part == 1 {
                perc_on = !perc_on;
            }
            bass_fig = (bass_fig + 1 + (w / 0x400) % 5) % 6;
            perc_i = (perc_i + 1 + (w / 0x100000) % 2) % 3;
            level0 = (w / 0x1000) % 2;
            orn_i = (w / 0x4000) % 3;
            sus_i = (w / 0x400000) % 3;
            ep_leader = (ep_leader + 1 + (w / 0x40000) % (k - 1)) % k;
            gl_seed = mix(gl_seed0, w);
        }
        let kn = dr.day_knob;
        if kn == 0 {
            ep_kind = (ep_kind + 1) % 6;
        } else if kn == 1 {
            reverse = true;
        } else {
            bpm_delta = dr.delta_bpm;
            art = if kn >= 4 {
                2
            } else {
                1
            };
        }
        age = dr.day;
    }
    // ornaments grow with the track's age
    let stage: u32 = if age < 60 {
        0
    } else if age < 120 {
        1
    } else if age < 180 {
        2
    } else if age < 270 {
        3
    } else {
        4
    };
    let grown_u64 = (age - 1) / 25 * 5;
    let grown: u32 = if grown_u64 > 60 {
        60
    } else {
        grown_u64.try_into().unwrap()
    };
    let orn_raw = *ORN_BASE.span().at(orn_i) + grown;
    let orn = if orn_raw > 85 {
        85
    } else {
        orn_raw
    };
    let mut palette = array![1 + orn_kind];
    let mut g: u32 = opaque(0);
    while g != stage {
        palette.append(3 + g);
        g += 1;
    }
    let scale = mode_scale(mx);
    let bad = *MODE_BAD.span().at(mx);
    let n8 = *MODE_N8.span().at(mx);
    if mi == 2 {
        hr = 1;
    }
    if hr == 2 && n8 == 0 {
        hr = 0;
    }
    let eight = hr == 2;
    let pool_n = if eight {
        n8
    } else {
        *MODE_N4.span().at(mx)
    };
    let loop_i = (loop_draw
        + if loop_step != 0 {
            1 + (loop_step - 1) % (pool_n - 1)
        } else {
            0
        })
        % pool_n;
    let n_s = if hr == 1 {
        4
    } else {
        8
    };
    let cyc = n_s * sl;
    let mut motif = opaque(array![]);
    let d0: felt252 = (*sp.degrees.span().at(0)).into();
    let mut q: u32 = opaque(0);
    while q != 4 {
        let dq: felt252 = (*sp.degrees.span().at(q)).into();
        motif.append(to_i(dq - d0));
        q += 1;
    }
    let motif = motif.span();
    let heads = HEADS.span();
    let h0 = at32(heads, mi * 3 + id % 3);
    let h1 = at32(heads, mi * 3 + (id / 3) % 3);
    let head = array![h0 / 65536, h0 % 65536, h1 / 65536, h1 % 65536].span();
    let kx = if k == 4 {
        4
    } else {
        0
    };
    let centre = unpack_i(*CONTOURS.span().at(kx + contour), 8, k);
    let shapes = unpack(*SHAPES.span().at(kx + shape), 8, k);
    let ac = assign(k);
    let ctx = BoxTrait::new(Ctx {
        k,
        n_s,
        sl,
        late,
        mi,
        hr,
        typ,
        motif,
        head,
        centre,
        shapes,
        sus_share: *SUS_SHARE.span().at(sus_i),
        orn,
        stage,
        orn_seed,
        palette: palette.span(),
        role_seed,
        cell_seed,
        ac,
    });
    let ra = make_round(ctx, pool_loop(eight, bad, loop_i), 1);
    let rb = make_round(
        ctx, pool_loop(eight, bad, (loop_i + 1 + loop_draw_b % (pool_n - 1)) % pool_n), 2,
    );
    // the form
    let ca = if n_s == 8 {
        if k == 4 {
            4
        } else {
            k + 1
        }
    } else if mi == 2 {
        k + 1
    } else {
        2 * k
    };
    let cb = if n_s == 8 {
        3
    } else if mi == 2 {
        k
    } else {
        k + 2
    };
    let ep_start = ca * cyc;
    let b_start = ep_start + EP_SLOTS * sl;
    let cad_start = b_start + cb * cyc;
    let end = cad_start + 2 * cadl;
    let cad = mode_cad(mx);
    let tonic_dim = *MODE_DIM.span().at(mx);
    let e = *EPISODES.span().at(ep_kind);
    let e_motif = e >= 1024;
    let e_step = (e % 1024) % 8;
    let e_cycle = unpack((e % 1024) / 8, 3, 3);
    // the episode leader's line
    let ep_cell = at32(FAMILY.span(), mi * 9 + typ * 3 + 1 + mix(cell_seed, 977) % 2)
        / pow16((mix(cell_seed, 978) / 8) % 4)
        % 16;
    let mut ep_anchors = opaque(array![]);
    let mut ep: i32 = 0;
    let mut u: u32 = opaque(0);
    while u != EP_UNITS {
        let cls = (e_step * u + 2 * *e_cycle.at(u % 3)) % 7;
        ep = if u == 0 {
            nearest(2, cls)
        } else {
            nearest(ep, cls)
        };
        if ep > 9 {
            ep = to_i(ep.into() - 7);
        } else if ep < -5 {
            ep = to_i(ep.into() + 7);
        }
        ep_anchors.append(ep);
        u += 1;
    }
    let ep_anchors = ep_anchors.span();
    // the leader starts the episode on the tonic
    while role_at(ra, rb, ca, k, ep_leader, ca - 1, n_s - 1) == 0 {
        ep_leader = (ep_leader + 1) % k;
    }
    let mut prev_deal = opaque(array![]);
    let mut next_deal = opaque(array![]);
    let mut q: u32 = opaque(0);
    while q != 3 {
        prev_deal.append(*e_cycle.at((EP_UNITS - 1 - q) % 3));
        next_deal.append(role_at(ra, rb, ca, k, (ep_leader + q) % k, ca, 0));
        q += 1;
    }
    let mut triples = opaque(array![]);
    let mut t3: u32 = opaque(0);
    while t3 != 27 {
        triples.append(t3);
        t3 += 1;
    }
    let ep_deal = unpack(
        join_deal(
            triples.span(),
            3,
            code(prev_deal.span()),
            (e_step * (EP_UNITS - 1)) % 7 != cad,
            Option::Some(code(next_deal.span())),
            true,
            mix(role_seed, 31) % 27,
        ),
        3,
        3,
    );
    let mut before = opaque(array![]);
    let mut v: u32 = opaque(0);
    while v != k {
        before.append(role_at(ra, rb, ca, k, v, ca + cb - 1, n_s - 1));
        v += 1;
    }
    let before = code(before.span());
    // the final deals: line 0 on the root, no fifth on a diminished tonic
    let mut finals = opaque(array![]);
    for x in ac {
        if *x % 3 == 0 {
            if tonic_dim {
                let mut f: u32 = opaque(0);
                let mut p3 = 1;
                let mut j: u32 = opaque(0);
                while j != k {
                    let y = dig(*x, j);
                    if y != 2 {
                        f += y * p3;
                    }
                    p3 *= 3;
                    j += 1;
                }
                finals.append(f);
            } else {
                finals.append(*x);
            }
        }
    }
    let finals = finals.span();
    let n_ac = ac.len();
    let cad_from = mix(role_seed, 32) % n_ac;
    let rb_last_changed = *rb.unbox().chords.at(n_s - 1) != cad;
    let mut cad_code: u32 = opaque(0);
    let mut end_code: u32 = opaque(0);
    let mut cad_p = BIG;
    let mut kk: u32 = opaque(0);
    while kk != n_ac {
        let b = *ac.at((cad_from + kk) % n_ac);
        let f = join_deal(finals, k, b, true, Option::None, false, 0);
        let p = deal_penalty(before, b, k, rb_last_changed, 2) + deal_penalty(b, f, k, true, 2);
        if p < cad_p {
            cad_code = b;
            end_code = f;
            cad_p = p;
        }
        kk += 1;
    }
    let cad_deal = unpack(cad_code, 3, k);
    let end_deal = unpack(end_code, 3, k);
    let mut ep_lead = opaque(array![]);
    let mut u: u32 = opaque(0);
    while u != EP_UNITS {
        let a = *ep_anchors.at(u);
        let next = if u + 1 < EP_UNITS {
            *ep_anchors.at(u + 1)
        } else {
            nearest(a, cad % 7)
        };
        let notes = if e_motif {
            let weak = weak_of(a.into() + (*motif.at(1)).into() - (*motif.at(0)).into(), a, next);
            array![
                note(u * sl, *head.at(0), a, true), note(u * sl + *head.at(0), *head.at(1), weak, false),
            ]
        } else {
            cell_notes(mi, ep_cell, u * sl, a, next, *e_cycle.at(u % 3))
        };
        if stage >= 2 {
            ornament(ref ep_lead, ctx, notes.span(), 500 + u, next);
        } else {
            ep_lead.append_span(notes.span());
        }
        u += 1;
    }
    let ep_lead = ep_lead.span();
    // the voices by order of entry
    let mut voices: Array<Span<Note>> = opaque(array![]);
    let mut chans = opaque(array![]);
    let mut vi: u32 = opaque(0);
    while vi != k {
        chans.append(((if reverse {
            k - 1 - vi
        } else {
            vi
        }) + rot) % k);
        let mut notes: Array<Note> = opaque(array![]);
        let mut last: i32 = 0;
        let mut gg = vi;
        while gg != ca + cb {
            let uu = gg - vi;
            let lv = level0
                + if uu < k {
                    0
                } else if uu < k + 2 {
                    1
                } else {
                    2
                };
            let lv = if lv > 2 {
                2
            } else {
                lv
            };
            let (rd, t0) = if gg < ca {
                (ra, gg * cyc)
            } else {
                (rb, b_start + (gg - ca) * cyc)
            };
            for n in *rd.unbox().lines.at((uu % k) * 3 + lv) {
                notes.append(Note { t: t0 + n.t, ..*n });
                last = n.d;
            }
            if gg == ca - 1 {
                let qv = (vi + k - ep_leader) % k;
                if qv < 3 {
                    let tm = (e_step * qv) % 7;
                    let tr: felt252 = tm.into() - if tm > 3 {
                        7
                    } else {
                        0
                    };
                    for n in ep_lead {
                        if n.t + qv * sl < EP_UNITS * sl {
                            let d = to_i(n.d.into() + tr);
                            notes.append(Note { t: ep_start + qv * sl + n.t, d, ..*n });
                            last = d;
                        }
                    }
                    let close = nearest(last, (cad + 2 * *ep_deal.at(qv)) % 7);
                    notes.append(note(ep_start + EP_UNITS * sl, sl, close, true));
                    last = close;
                }
            }
            gg += 1;
        }
        let c1 = nearest(last, (cad + 2 * *cad_deal.at(vi)) % 7);
        notes.append(note(cad_start, cadl, c1, true));
        notes.append(note(cad_start + cadl, cadl, nearest(c1, (2 * *end_deal.at(vi)) % 7), true));
        voices.append(notes.span());
        vi += 1;
    }
    let chans = chans.span();
    // the bass on the roots
    let mut bass: Array<Note> = opaque(array![]);
    if bass_on {
        // [time, root, slots] (0 slots: a held note of `len`)
        let mut spans: Array<(u32, u32, u32, u32)> = opaque(array![]);
        let mut gg: u32 = opaque(0);
        while gg != ca + cb {
            if gg == ca {
                let mut u: u32 = opaque(0);
                while u != EP_UNITS {
                    spans.append((ep_start + u * sl, e_step * u, 1, 0));
                    u += 1;
                }
                spans.append((ep_start + EP_UNITS * sl, cad, 0, sl));
            }
            let (rd, base) = if gg < ca {
                (ra, gg * cyc)
            } else {
                (rb, b_start + (gg - ca) * cyc)
            };
            if hr == 0 {
                let mut b: u32 = opaque(0);
                while b != 4 {
                    spans.append((base + 2 * b * sl, *rd.unbox().loop_.at(b), 2, 0));
                    b += 1;
                }
            } else {
                let mut s: u32 = opaque(0);
                while s != n_s {
                    spans.append((base + s * sl, *rd.unbox().chords.at(s), 1, 0));
                    s += 1;
                }
            }
            gg += 1;
        }
        spans.append((cad_start, cad, 0, cadl));
        spans.append((cad_start + cadl, 0, 0, cadl));
        let spans = spans.span();
        let ns = spans.len();
        let mut x: u32 = opaque(0);
        while x != ns {
            let (t, rr, nn, len) = *spans.at(x);
            let d = root_deg(rr);
            if nn == 0 {
                bass.append(note(t, len, d, true));
            } else {
                let (_, r2, _, _) = *spans.at(x + 1);
                let nd = root_deg(r2);
                let fd: felt252 = d.into();
                let toward: felt252 = if nd > d {
                    nd.into() - 1
                } else if nd < d {
                    nd.into() + 1
                } else {
                    fd
                };
                let fig = (mi * 2 + if nn == 2 {
                    0
                } else {
                    1
                }) * 6
                    + bass_fig;
                let at = BASS_AT.span();
                let mut y = at32(at, fig);
                let stop = at32(at, fig + 1);
                while y != stop {
                    let z = at32(BASS_NOTES.span(), y);
                    let off = z / 65536;
                    let src = z % 8;
                    let dd = if src == 0 {
                        fd
                    } else if src == 1 {
                        fd + 7
                    } else if src == 2 {
                        fd + 2
                    } else if src == 3 {
                        fd + 4
                    } else {
                        toward
                    };
                    bass.append(note(t + off, (z / 8) % 8192, to_i(dd), off == 0));
                    y += 1;
                }
            }
            x += 1;
        }
    }
    // the percussion, from the second voice's entry
    let mut perc: Array<Sound> = opaque(array![]);
    if perc_on {
        let at = PERC_AT.span();
        let from = at32(at, mi * 3 + perc_i);
        let stop = at32(at, mi * 3 + perc_i + 1);
        let mut t = cyc;
        while t < cad_start {
            let mut y = from;
            while y != stop {
                let z = at32(PERC_HITS.span(), y);
                perc.append(Sound { t: t + z / 65536, len: 120, p: i((z / 256) % 256), v: z % 256 });
                y += 1;
            }
            t += br;
        }
        // (the source sorts these by time; an equal sort key keeps the order they come in)
        perc.append(Sound { t: b_start, len: 120, p: 49, v: 84 });
        perc.append(Sound { t: cad_start + cadl, len: 120, p: 49, v: 90 });
        perc.append(Sound { t: cad_start + cadl, len: 120, p: 36, v: 104 });
    }
    // the harp glissando
    let base: i32 = i(if tonic < 6 {
        60 + tonic
    } else {
        48 + tonic
    });
    let mut gliss: Array<Sound> = opaque(array![]);
    if let Option::Some(plan) = gliss_plan(gl_draw, gl_seed, GLISS_WEIGHTS.span()) {
        let at = *array![ep_start, b_start, cad_start, cad_start + cadl].span().at(plan.spot);
        let span = if sl == 1440 {
            960
        } else {
            sl
        };
        for gn in glissando(plan, at, span, gl_seed, at + 480, bpm0) {
            gliss.append(Sound { t: gn.t, len: gn.len, p: pitch_of(base, scale, gn.d.into()), v: (gn.v).into() });
        }
    }
    // the tempo
    let mut us: u32 = (120000000 + bpm0) / (2 * bpm0);
    if bpm_delta != 0 {
        let u64us: i64 = us.into();
        let dd: i64 = 60000000 + bpm_delta * u64us;
        let nu: i64 = (2 * 60000000 * u64us + dd) / (2 * dd);
        us = if nu > 1048575 {
            1048575
        } else {
            nu.try_into().unwrap()
        };
    }
    let programs = programs_of(id, typ, mega);
    let mut tracks = array![tempo_track(us, SIGS.span().slice(mi * 4, 4), end)];
    let octave = OCTAVE.span();
    let pan = PAN.span();
    let mut first_voice = *voices.at(0);
    let mut ch: u32 = opaque(0);
    while ch != k {
        let mut vi: u32 = opaque(0);
        while *chans.at(vi) != ch {
            vi += 1;
        }
        let part = *voices.at(vi);
        if ch == 0 {
            first_voice = part;
        }
        let prog = *programs.at(ch);
        let mut s = opaque(array![]);
        sounding(ref s, part, base + 12 * *octave.at(ch), scale, art, br);
        let chu: u8 = ch.try_into().unwrap();
        tracks
            .append(
                note_track(
                    chu,
                    prog,
                    if is_lead(prog) {
                        72
                    } else {
                        118
                    },
                    *pan.at(ch),
                    s.span(),
                    end,
                    play,
                ),
            );
        ch += 1;
    }
    if bass.len() != 0 {
        let mut s = opaque(array![]);
        sounding(ref s, bass.span(), base - 24, scale, art, br);
        tracks.append(note_track(4, *programs.at(4), 118, 64, s.span(), end, play));
    }
    if mega {
        let mut s = opaque(array![]);
        sounding(ref s, first_voice, base + 12, scale, art, br);
        tracks.append(note_track(5, *programs.at(5), 56, 76, s.span(), end, play));
    }
    if gliss.len() != 0 {
        tracks.append(note_track(GLISS_CHANNEL, *programs.at(2), 100, 100, gliss.span(), end, play));
    }
    if perc.len() != 0 {
        tracks.append(note_track(9, 0, 0, 0, perc.span(), end, play));
    }
    tracks
}

/// A root degree in -3..3.
#[inline(never)]
fn root_deg(r: u32) -> i32 {
    let m = r % 7;
    to_i(m.into() - if m > 3 {
        7
    } else {
        0
    })
}

/// Which member a voice (by entry) holds in round cycle g at slot s.
#[inline(never)]
fn role_at(ra: Box<Rd>, rb: Box<Rd>, ca: u32, k: u32, v: u32, g: u32, s: u32) -> u32 {
    let rd = if g < ca {
        ra
    } else {
        rb
    };
    dig(*rd.unbox().roles.at(s), (g - v) % k)
}

/// The Round of Loot Beast `species` as a format-1 MIDI file (`roundMidi(...).midi`).
pub fn round_smf_bytes(species: u32, mega: bool, seed: u64, drift: Option<Drift>) -> Array<u8> {
    smf_bytes(1, TPQ, round_tracks(species, mega, seed, drift, as_written()).span())
}

/// The same as a ByteArray.
pub fn round_byte_array(species: u32, mega: bool, seed: u64, drift: Option<Drift>) -> ByteArray {
    smf_byte_array(1, TPQ, round_tracks(species, mega, seed, drift, as_written()).span())
}

/// The Round as the lab plays it (`play`), straight into the ByteArray a contract returns.
pub fn round_played_byte_array(
    species: u32, mega: bool, seed: u64, drift: Option<Drift>, play: Play,
) -> ByteArray {
    smf_byte_array(1, TPQ, round_tracks(species, mega, seed, drift, play).span())
}


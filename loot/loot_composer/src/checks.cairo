//! Loot Dungeon Sound Checks: the Beast's band warms up, byte-identical to `soundCheckMidi`
//! (offchain/loot-sound/src/loot_checks.js; read its header for the music). Ten bars of 4/4 in the
//! Beast's key: an opening, three drills of nine without repeats, a close; two leads, two plucks, a
//! bass, the kit, a harp glissando now and then, the mega double on top. Take 0 is the species' own.

use core::num::traits::WrappingMul;
use midi::smf::{smf_byte_array, smf_bytes};
use crate::common::{RngTrait, fold64, gliss_plan, glissando};
use crate::rounds::{
    Sound, TPQ, i, is_lead, mode_cad, mode_index, mode_scale, mod7, note_track, pitch_of,
    programs_of, sign, sort_keys, tempo_track,
};
use crate::checks_data::{OPS, PIECE_AT};
use crate::rounds_data::MODE_DIM;
use crate::species::loot_species;

const BAR: u32 = 1920;
const SEG: u32 = 3840;

/// A pitched note of part `part` (0 lead, 1 second lead, 2 pluck, 3 second pluck, 4 bass, 5 mega
/// double, 6 harp).
#[derive(Copy, Drop)]
struct Put {
    part: u32,
    t: u32,
    len: u32,
    d: i32,
    v: u32,
}

#[derive(Drop)]
struct Band {
    puts: Array<Put>,
    hits: Array<Sound>,
    m: Span<i32>,
    mr: Span<u32>,
    cad: i32,
    colour: i32,
    fifth: i32,
    typ: u32,
}

#[generate_trait]
impl BandImpl of BandTrait {
    #[inline(never)]
    fn put(ref self: Band, part: u32, t: u32, len: u32, d: i32, v: u32) {
        self.puts.append(Put { part, t, len, d, v });
    }

    #[inline(never)]
    fn hit(ref self: Band, t: u32, key: u32, v: u32) {
        self.hits.append(Sound { t, len: 120, p: i(key), v });
    }

    /// The motif in its rhythm from t, each degree d as mul * d + add.
    #[inline(never)]
    fn motif_on(ref self: Band, part: u32, t: u32, mul: i32, add: i32, vel: u32) {
        let m = self.m;
        let mr = self.mr;
        let mut at = t;
        let mut k = 0;
        while k != 6 {
            let l = *mr.at(k);
            self.put(part, at, l - 20, mul * *m.at(k) + add, vel);
            at += l;
            k += 1;
        }
    }

    /// The tonic chord rolled up (0, 2, 4, 7) a 32nd apart.
    #[inline(never)]
    fn roll(ref self: Band, part: u32, t: u32, len: u32, vel: u32) {
        let ds = array![0_i32, 2, 4, 7];
        let mut k = 0;
        for d in ds {
            self.put(part, t + k * 60, len - k * 60, d, vel);
            k += 1;
        }
    }

    /// Several notes of one part, one length and velocity, `step` ticks apart.
    #[inline(never)]
    fn run(ref self: Band, part: u32, t: u32, step: u32, len: u32, ds: Span<i32>, vel: u32) {
        let mut k = 0;
        for d in ds {
            self.put(part, t + k * step, len, *d, vel);
            k += 1;
        }
    }

    /// The fifth above the tonic, or (diminished) the given other.
    fn f4(self: @Band, other: i32) -> i32 {
        if self.fifth == 4 {
            4
        } else {
            other
        }
    }
}

const GROOVE: [u32; 19] = [
    // a bar of the kit by family: offset * 65536 + key * 256 + velocity; family 0 [0, 6), 1 [6, 14),
    // 2 [14, 19)
    0x002464, 0x1E02A3C, 0x2D02A32, 0x3C02654, 0x5A02A3C, 0x6902A32, 0x002464, 0xF02A38,
    0x1E02654, 0x2D02450, 0x3C02460, 0x4B02A38, 0x5A02658, 0x6902A38, 0x00246C, 0x1E02954,
    0x3C02464, 0x4B02454, 0x5A02B58,
];

/// The mode's colour note: circled, leaned on, then a step down to the nearest note of the tonic chord.
#[inline(never)]
fn colour_drill(ref c: Band, t: u32) {
    let x = if c.colour < 3 {
        c.colour + 7
    } else {
        c.colour
    };
    c.run(0, t, 240, 220, array![x - 1, x, x + 1, x].span(), 80);
    c.put(0, t + 960, 940, x, 104);
    let mut home = x - 1;
    loop {
        let h = mod7(home);
        if (h == 0 || h == 2 || h == 4) && !(h == 4 && c.fifth != 4) {
            break;
        }
        home -= 1;
    }
    // the way down from x to home + 1, padded in front to four notes (x + 1 next to it, then x, ...)
    let mut way: Array<i32> = array![];
    let n = x - home;
    let mut pad = if n < 4 {
        4 - n
    } else {
        0
    };
    while pad != 0 {
        way.append(if pad % 2 == 1 {
            x + 1
        } else {
            x
        });
        pad -= 1;
    }
    let mut d = x;
    while d > home {
        way.append(d);
        d -= 1;
    }
    let w = way.span();
    c.run(0, t + BAR, 240, 220, w.slice(w.len() - 4, 4), 84);
    c.put(0, t + BAR + 960, 940, home, 92);
    c.put(1, t, SEG - 20, 0, 62);
    c.put(4, t, SEG - 20, 0, 70);
}

/// The motif and two steps home in eighths, the second lead a beat later an octave below; the second
/// bar a third higher on an odd draw.
#[inline(never)]
fn canon_drill(ref c: Band, t: u32, odd: bool) {
    let m = c.m;
    let x = *m.at(5);
    let a = if x == 0 {
        1
    } else {
        x - sign(x)
    };
    let b = if a == 0 {
        1
    } else {
        a - sign(a)
    };
    let mut line = array![];
    line.append_span(m);
    line.append(a);
    line.append(b);
    let up = if odd {
        2
    } else {
        0
    };
    let mut k = 0;
    for d in line {
        c.put(0, t + k * 240, 220, d, 88);
        c.put(1, t + 480 + k * 240, 220, d, 78);
        c.put(0, t + BAR + k * 240, 220, d + up, 88);
        if k < 6 {
            c.put(1, t + BAR + 480 + k * 240, 220, d + up, 78);
        }
        k += 1;
    }
    c.put(4, t, BAR - 20, 0, 72);
    c.put(4, t + BAR, BAR - 20, 0, 72);
}

/// The drum break's groove (the family's bar, its first half again), and the bass in the motif's rhythm
/// on the root and the fifth.
#[inline(never)]
fn break_drill(ref c: Band, t: u32) {
    let (from, stop) = if c.typ == 0 {
        (0, 6)
    } else if c.typ == 1 {
        (6, 14)
    } else {
        (14, 19)
    };
    let g = GROOVE.span();
    let mut y = from;
    while y != stop {
        let z = *g.at(y);
        let off = z / 65536;
        let key = (z / 256) % 256;
        let vel = z % 256;
        c.hit(t + off, key, vel);
        if off < 960 {
            c.hit(t + BAR + off, key, vel);
        }
        y += 1;
    }
    let mr = c.mr;
    let mut at = t;
    let mut k: u32 = 0;
    for l in mr {
        let d = if k % 2 == 1 && c.fifth == 4 {
            4
        } else {
            0
        };
        c.put(4, at, *l - 20, d, 84);
        at += *l;
        k += 1;
    }
}

/// Plays piece p (0-2 openings, 3-11 drills, 12-14 closes; checks_data.cairo) from tick t with draw v.
#[inline(never)]
fn play(ref c: Band, p: u32, t: u32, v: u32) {
    let at = PIECE_AT.span();
    let ops = OPS.span();
    let mut y = *at.at(p);
    let stop = *at.at(p + 1);
    let odd = v % 2 == 1;
    while y != stop {
        let x = *ops.at(y);
        let (x, a) = DivRem::div_rem(x, 128);
        let (x, dk) = DivRem::div_rem(x, 8);
        let (x, vel) = DivRem::div_rem(x, 128);
        let (x, len) = DivRem::div_rem(x, 4096);
        let (x, off) = DivRem::div_rem(x, 4096);
        let (x, part) = DivRem::div_rem(x, 8);
        let (op, cond) = DivRem::div_rem(x, 4);
        let a: i32 = a.try_into().unwrap();
        let vel: u32 = vel.try_into().unwrap();
        let len: u32 = len.try_into().unwrap();
        let part: u32 = part.try_into().unwrap();
        let tt: u32 = t + off.try_into().unwrap();
        let on = if cond == 0 {
            true
        } else if cond == 1 {
            odd
        } else if cond == 2 {
            !odd
        } else {
            (v / 2) % 2 == 1
        };
        if on {
            if op == 0 {
                let d = if dk == 0 {
                    a - 64
                } else if dk == 1 {
                    c.f4(a - 64)
                } else if dk == 2 {
                    c.fifth
                } else if dk == 3 {
                    (if c.cad > 3 {
                        c.cad - 7
                    } else {
                        c.cad
                    }) + a - 64
                } else if dk == 4 {
                    *c.m.at((a / 16).try_into().unwrap()) + a % 16 - 8
                } else {
                    let d0 = a / 8;
                    (if mod7(d0) == 4 && c.fifth != 4 {
                        d0 + 1
                    } else {
                        d0
                    }) + a % 8 - 4
                };
                c.put(part, tt, len, d, vel);
            } else if op == 1 {
                c.hit(tt, len, vel);
            } else if op == 2 {
                if a >= 8 {
                    c.motif_on(part, tt, -1, a - 8, vel);
                } else {
                    c.motif_on(part, tt, 1, a, vel);
                }
            } else if op == 3 {
                c.roll(part, tt, len, vel);
            } else if op == 4 {
                colour_drill(ref c, tt);
            } else if op == 5 {
                canon_drill(ref c, tt, odd);
            } else {
                break_drill(ref c, tt);
            }
        }
        y += 1;
    }
}

/// Sounds sorted by start, ties in the order they come (the source's stable sort).
fn by_start(xs: Span<Sound>) -> Array<Sound> {
    let mut keys: Array<u64> = array![];
    let mut k: u64 = 0;
    for x in xs {
        let t: u64 = x.t.into();
        keys.append(t * 0x10000 + k);
        k += 1;
    }
    let mut out = array![];
    for key in sort_keys(keys.span()) {
        let at: u32 = (*key % 0x10000).try_into().unwrap();
        out.append(*xs.at(at));
    }
    out
}

/// The Sound Check's tracks: tempo, then each part that plays (by channel), then the kit.
pub fn sound_check_tracks(species: u32, mega: bool, take: u64) -> Array<Array<u8>> {
    let sp = loot_species(species);
    let id = sp.id;
    let typ: u32 = sp.beast_type.into();
    let mut r = RngTrait::new(fold64(take) ^ id.wrapping_mul(0x85ebca77) ^ 0x43484b21);
    let mx = mode_index(sp.mode.into());
    let scale = mode_scale(mx);
    let tonic: u32 = sp.tonic_pc.into();
    let base: i32 = i(if tonic < 6 {
        60 + tonic
    } else {
        48 + tonic
    });
    let bpm = *array![104_u32, 120, 92].span().at(typ) + r.int(21);
    let op = r.int(3);
    let cl = r.int(3);
    // three drills without repeats
    let mut left: Array<u32> = array![0, 1, 2, 3, 4, 5, 6, 7, 8];
    let mut drills = array![];
    let mut q = 0;
    while q != 3 {
        let pick = r.int(left.len());
        let mut rest = array![];
        let mut x = 0;
        for d in left.span() {
            if x == pick {
                drills.append(*d);
            } else {
                rest.append(*d);
            }
            x += 1;
        }
        left = rest;
        q += 1;
    }
    let draws = array![r.int(4), r.int(4), r.int(4)];
    let gl_draw = r.int(20);
    let gl_seed = r.next();
    let d0: i32 = (*sp.degrees.span().at(0)).into();
    let mut m = array![];
    for d in sp.degrees.span() {
        let dd: i32 = (*d).into();
        m.append(dd - d0);
    }
    let mr = if id % 3 == 0 {
        array![240_u32, 240, 240, 240, 480, 480]
    } else if id % 3 == 1 {
        array![360_u32, 120, 360, 120, 480, 480]
    } else {
        array![120_u32, 360, 120, 360, 480, 480]
    };
    let mode: u32 = sp.mode.into();
    let colour = if mode == 4 || mode == 7 {
        5
    } else if mode == 5 {
        1
    } else if mode == 6 {
        4
    } else if mode == 8 {
        6
    } else {
        3
    };
    let mut c = Band {
        puts: array![],
        hits: array![],
        m: m.span(),
        mr: mr.span(),
        cad: i(mode_cad(mx)),
        colour,
        fifth: if *MODE_DIM.span().at(mx) {
            7
        } else {
            4
        },
        typ,
    };
    play(ref c, op, 0, 0);
    let mut q = 0;
    while q != 3 {
        play(ref c, 3 + *drills.at(q), (q + 1) * SEG, *draws.at(q));
        q += 1;
    }
    play(ref c, 12 + cl, 4 * SEG, 0);
    let end = 5 * SEG;
    let puts = c.puts.span();
    let octave = array![0_i32, -1, 0, -1, -2, 1, 0].span();
    let pan = array![64_u8, 40, 88, 52, 64, 76, 100].span();
    let programs = programs_of(id, typ, mega);
    let us = (120000000 + bpm) / (2 * bpm);
    let mut tracks = array![tempo_track(us, array![4_u8, 2, 24, 8].span(), end)];
    let mut ch = 0;
    while ch != 7 {
        let mut part: Array<Sound> = array![];
        if ch == 6 {
            if let Option::Some(plan) = gliss_plan(gl_draw, gl_seed, array![0, 2, 3, 3, 1].span()) {
                let at = *array![960, SEG, 4 * SEG, 4 * SEG + BAR].span().at(plan.spot);
                for g in glissando(plan, at, 960, gl_seed, at + 480) {
                    part.append(Sound { t: g.t, len: g.len, p: pitch_of(base, scale, g.d), v: (g.v).into() });
                }
            }
        } else if ch != 5 || mega {
            let src = if ch == 5 {
                0
            } else {
                ch
            };
            let b = base + 12 * *octave.at(ch);
            for x in puts {
                if x.part == src {
                    let v = if ch == 5 {
                        if x.v < 54 {
                            40
                        } else {
                            x.v - 14
                        }
                    } else {
                        x.v
                    };
                    part.append(Sound { t: x.t, len: x.len, p: pitch_of(b, scale, x.d), v });
                }
            }
        }
        if part.len() != 0 {
            let prog = if ch == 6 {
                *programs.at(2)
            } else {
                *programs.at(ch)
            };
            let vol = if ch == 5 {
                56
            } else if ch == 6 {
                100
            } else if is_lead(prog) {
                72
            } else {
                118
            };
            let sorted = by_start(part.span());
            let chu: u8 = ch.try_into().unwrap();
            tracks.append(note_track(chu, prog, vol, *pan.at(ch), sorted.span(), end));
        }
        ch += 1;
    }
    if c.hits.len() != 0 {
        let sorted = by_start(c.hits.span());
        tracks.append(note_track(9, 0, 0, 0, sorted.span(), end));
    }
    tracks
}

/// The Sound Check of Loot Beast `species` as a format-1 MIDI file (`soundCheckMidi(...).midi`).
pub fn sound_check_smf_bytes(species: u32, mega: bool, take: u64) -> Array<u8> {
    smf_bytes(1, TPQ, sound_check_tracks(species, mega, take).span())
}

/// The same as a ByteArray.
pub fn sound_check_byte_array(species: u32, mega: bool, take: u64) -> ByteArray {
    smf_byte_array(1, TPQ, sound_check_tracks(species, mega, take).span())
}

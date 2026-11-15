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

fn opening(ref c: Band, which: u32, t: u32) {
    if which == 0 {
        // tuning over a drone
        c.put(4, t, SEG - 20, 0, 70);
        c.put(3, t + 480, SEG - 500, c.fifth, 60);
        c.put(0, t + 960, 70, 2, 70);
        c.put(0, t + 1040, 70, 3, 74);
        c.put(0, t + 1120, 780, 4, 88);
        c.run(0, t + 1920, 120, 110, array![5, 4, 3, 4].span(), 80);
        c.put(0, t + 2400, 460, 4, 88);
        c.put(0, t + 2880, 460, 2, 84);
        c.put(0, t + 3360, 460, 0, 92);
        c.put(1, t + 3360, 460, 0, 70);
    } else if which == 1 {
        // a count-in
        c.hit(t, 42, 70);
        c.hit(t + 480, 42, 70);
        c.hit(t + 960, 42, 90);
        c.hit(t + 1440, 42, 90);
        c.hit(t + 1680, 45, 84);
        c.hit(t + 1800, 43, 92);
        c.hit(t + BAR, 36, 104);
        c.hit(t + BAR, 49, 84);
        c.roll(2, t + BAR, 1500, 86);
        c.put(4, t + BAR, 1880, 0, 84);
        let x = c.f4(2);
        c.put(0, t + BAR + 960, 460, x, 72);
        c.put(0, t + BAR + 1440, 460, 7, 80);
    } else {
        // the motif alone, and its echo
        c.motif_on(0, t, 1, 0, 92);
        c.motif_on(1, t + BAR, 1, 0, 62);
    }
}

const GROOVE: [u32; 19] = [
    // offset * 65536 + key * 256 + velocity; family 0 [0, 6), 1 [6, 14), 2 [14, 19)
    0x002464, 0x1E02A3C, 0x2D02A32, 0x3C02654, 0x5A02A3C, 0x6902A32, 0x002464, 0xF02A38,
    0x1E02654, 0x2D02450, 0x3C02460, 0x4B02A38, 0x5A02658, 0x6902A38, 0x00246C, 0x1E02954,
    0x3C02464, 0x4B02454, 0x5A02B58,
];

fn drill(ref c: Band, which: u32, t: u32, v: u32) {
    let odd = v % 2 == 1;
    if which == 0 {
        // the motif called and answered
        c.motif_on(0, t, 1, 0, 92);
        if odd {
            c.motif_on(1, t + BAR, -1, 4, 84);
        } else {
            c.motif_on(1, t + BAR, 1, 2, 84);
        }
        c.put(4, t, BAR - 20, 0, 76);
        c.put(4, t + BAR, BAR - 20, 0, 76);
    } else if which == 1 {
        // the scale in thirds
        let mut k: u32 = 0;
        while k != 7 {
            let ki = i(k);
            c.put(2, t + 2 * k * 240, 220, if odd {
                7 - ki
            } else {
                ki
            }, 84);
            c.put(2, t + (2 * k + 1) * 240, 220, if odd {
                5 - ki
            } else {
                ki + 2
            }, 76);
            k += 1;
        }
        c.put(2, t + 3360, 460, if odd {
            0
        } else {
            7
        }, 92);
        c.put(4, t, BAR - 20, 0, 76);
        c.put(4, t + BAR, BAR - 20, 7, 72);
        if (v / 2) % 2 == 1 {
            let mut k = 0;
            while k != 8 {
                c.hit(t + k * 480, 42, if k % 2 == 1 {
                    46
                } else {
                    58
                });
                k += 1;
            }
        }
    } else if which == 2 {
        // the mode's colour note
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
        // the way down, padded in front to four notes (x + 1, x, ...), its last four
        let mut way: Array<i32> = array![];
        let n = x - home;
        let mut pad = if n < 4 {
            4 - n
        } else {
            0
        };
        // the padding alternates back from the front: ... x, x + 1, then x down to home + 1
        let mut front: Array<i32> = array![];
        while pad != 0 {
            front.append(if pad % 2 == 1 {
                x + 1
            } else {
                x
            });
            pad -= 1;
        }
        way.append_span(front.span());
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
    } else if which == 3 {
        // an arpeggio through the cadence
        let k = if c.cad > 3 {
            c.cad - 7
        } else {
            c.cad
        };
        let a1 = array![0_i32, 2, 4, 7, 9, 11, 14, 11, 9, 7, 4, 2, 0, 2, 4, 7];
        let mut q = 0;
        for d in a1 {
            c.put(2, t + q * 120, 100, d, if q % 4 == 0 {
                88
            } else {
                72
            });
            q += 1;
        }
        let a2 = array![k, k + 2, k + 4, k + 7, k + 4, k + 2, k, k + 2];
        let mut q = 0;
        for d in a2 {
            c.put(2, t + BAR + q * 120, 100, d, if q % 4 == 0 {
                88
            } else {
                72
            });
            q += 1;
        }
        c.roll(2, t + BAR + 960, 900, 90);
        c.put(4, t, BAR - 20, 0, 80);
        c.put(4, t + BAR, 940, k, 80);
        c.put(4, t + BAR + 960, 940, 0, 84);
        if odd {
            let f = c.f4(7);
            c.run(3, t + 480, 0, 200, array![0, 2, f].span(), 66);
            c.run(3, t + 1440, 0, 200, array![0, 2, f].span(), 66);
        }
    } else if which == 4 {
        // a canon a beat apart
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
    } else if which == 5 {
        // leaps with a swell
        let f = c.f4(2);
        let ds = array![0, 7, f, 9, 7, 14, 2, 0];
        let mut k = 0;
        for d in ds {
            c.put(0, t + k * 480, 440, d, if odd {
                108 - 8 * k
            } else {
                52 + 8 * k
            });
            k += 1;
        }
        let f = c.f4(7);
        let mut k = 0;
        while k != 4 {
            c.run(3, t + BAR + 240 + k * 480, 0, 120, array![0, 2, f].span(), 60);
            c.hit(t + BAR + k * 480, 36, 84);
            k += 1;
        }
    } else if which == 6 {
        // a drum break
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
        let keys = array![45_u32, 45, 43, 43, 41, 41, 38, 38];
        let mut k = 0;
        for key in keys {
            c.hit(t + BAR + 960 + k * 120, key, 76 + 5 * k);
            k += 1;
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
        c.put(4, t + BAR, 940, 0, 84);
    } else if which == 7 {
        // trills and graces
        let ds = if odd {
            array![7_i32, 4, 2, 0]
        } else {
            array![0_i32, 2, 4, 7]
        };
        let f = c.f4(7);
        let mut k = 0;
        for d0 in ds {
            let d = if mod7(d0) == 4 && c.fifth != 4 {
                d0 + 1
            } else {
                d0
            };
            let t0 = t + k * 960;
            if k == 3 {
                c.put(0, t0, 70, d + 1, 78);
                c.put(0, t0 + 80, 860, d, 92);
            } else {
                let fig: Span<i32> = if k == 0 {
                    array![0, 1].span()
                } else if k == 1 {
                    array![1, 0, -1].span()
                } else {
                    array![0, 1, 0, 1, 0, 1].span()
                };
                let mut q = 0;
                for x in fig {
                    c.put(0, t0 + q * 60, 55, d + *x, if q == 0 {
                        88
                    } else {
                        78
                    });
                    q += 1;
                }
                c.put(0, t0 + q * 60, 940 - q * 60, d, 88);
            }
            c.run(3, t0, 240, 220, array![0, f, 2, f].span(), 60);
            k += 1;
        }
    } else {
        // the motif handed round the band
        let order = array![0_u32, 2, 1, 3];
        let at: Span<i32> = if odd {
            array![7, 4, 2, 0].span()
        } else {
            array![0, 2, 4, 7].span()
        };
        let m = c.m;
        let mut k = 0;
        for part in order {
            let mut q = 0;
            while q != 4 {
                c.put(part, t + k * 960 + q * 240, if q == 3 {
                    460
                } else {
                    220
                }, *m.at(q) + *at.at(k), 86);
                q += 1;
            }
            k += 1;
        }
        c.put(4, t, SEG - 20, 0, 66);
    }
}

fn close(ref c: Band, which: u32, t: u32) {
    if which == 0 {
        // a run into a stinger
        let k = if c.cad > 3 {
            c.cad - 7
        } else {
            c.cad
        };
        c.put(4, t, 940, k, 84);
        c.hit(t, 36, 96);
        c.hit(t + 480, 36, 88);
        let mut q: u32 = 0;
        while q != 8 {
            c.put(0, t + 960 + q * 120, 110, i(q) - 1, 70 + 5 * q);
            c.hit(t + 960 + q * 120, 38, 60 + 7 * q);
            q += 1;
        }
        c.put(0, t + BAR, 1400, 7, 104);
        let f = c.f4(2);
        c.put(1, t + BAR, 1400, f, 96);
        c.roll(2, t + BAR, 1400, 96);
        c.put(3, t + BAR, 1400, 2, 90);
        c.put(4, t + BAR, 1400, 0, 100);
        c.hit(t + BAR, 36, 110);
        c.hit(t + BAR, 49, 96);
    } else if which == 1 {
        // a scale that settles
        let mut k: u32 = 0;
        while k != 8 {
            c.put(0, t + k * 240, 220, 7 - i(k), 84 - 2 * k);
            if k < 7 {
                c.put(2, t + k * 240, 220, 5 - i(k), 70 - 2 * k);
            }
            k += 1;
        }
        c.put(4, t, BAR - 20, 0, 70);
        c.put(0, t + BAR, 1700, 0, 80);
        c.put(1, t + BAR, 1700, 0, 70);
        c.roll(2, t + BAR, 1700, 76);
        c.put(4, t + BAR, 1700, 0, 76);
        c.hit(t + BAR, 36, 80);
    } else {
        // the motif as a tag
        let m = c.m;
        let mut k: u32 = 0;
        while k != 3 {
            let mut part = 0;
            while part != 5 {
                c.put(part, t + k * 480, 400, *m.at(k), 96);
                part += 1;
            }
            c.hit(t + k * 480, 36, 96);
            k += 1;
        }
        c.hit(t + 1440, 38, 80);
        c.hit(t + 1680, 38, 96);
        c.put(0, t + BAR, 1400, 0, 104);
        c.put(1, t + BAR, 1400, 0, 104);
        c.put(3, t + BAR, 1400, 0, 104);
        c.put(4, t + BAR, 1400, 0, 104);
        c.roll(2, t + BAR, 1400, 100);
        c.hit(t + BAR, 36, 110);
        c.hit(t + BAR, 49, 96);
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
    opening(ref c, op, 0);
    let mut q = 0;
    while q != 3 {
        drill(ref c, *drills.at(q), (q + 1) * SEG, *draws.at(q));
        q += 1;
    }
    close(ref c, cl, 4 * SEG);
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

//! The Loot lab's orchestration (offchain/loot-sound/onchain/loot-lab.mjs `band`, `choose`, `lifted`
//! and its setProgram override), so the file a contract returns plays the instruments the lab plays:
//! - `band`: an edition's eight channels (lead, descant, accompaniment, bass, pad, mega double, harp
//!   glissando, second lead) from the style's pools, by Beast, edition and purchase number; drift
//!   moves the lead and bass monthly, the accompaniment and pad weekly.
//! - `song_band` / `round_band`: Species/Name Songs and Rounds/Sound Checks, each channel from its
//!   kind's pool by species.
//! - `orchestrate`: every program change on a pitched channel set to its band instrument, and every
//!   pitched note lifted by `lift` semitones (the lab plays Name Songs +12, Rounds +7).

use core::num::traits::{WrappingAdd, WrappingMul};
use beast_composer::composition::drift::Drift;
use super::orchestra_data::{
    BELL_A, BELL_B, FLUTE, GLOCK, HARP, POOL_DATA, POOL_OFFS, ROUND_MONTHLY, ROUND_POOL0,
    SONG_MONTHLY, SONG_POOL0,
};

/// The lab's own mix (loot-lab.mjs `mix`, not the editions').
#[inline(never)]
pub fn lab_mix(a: u32, b: u32) -> u32 {
    let x = (a ^ 0x9e3779b9).wrapping_mul(0x85ebca6b)
        ^ b.wrapping_add(0x7f4a7c15).wrapping_mul(0xc2b2ae35);
    let x = x ^ (x / 0x8000);
    let x = x.wrapping_mul(0x2c1b3c6d);
    x ^ (x / 0x1000)
}

#[inline(never)]
fn pool(id: u32) -> Span<u8> {
    let offs = POOL_OFFS.span();
    let a: u32 = (*offs.at(id)).into();
    let b: u32 = (*offs.at(id + 1)).into();
    POOL_DATA.span().slice(a, b - a)
}

/// `moved(pool, i, h, salt)`: another instrument of the pool when its clock has drifted.
#[inline(never)]
fn moved(len: u32, i: u32, h: Option<u32>, salt: u32) -> u32 {
    match h {
        Option::Some(h) => if len < 2 {
            i
        } else {
            (i + 1 + lab_mix(h, salt) % (len - 1)) % len
        },
        Option::None => i,
    }
}

fn low32(x: felt252) -> u32 {
    let w: u256 = x.into();
    (w % 0x100000000).try_into().unwrap()
}

/// `stepOf(drift)`: the month's and the week's drift words, when they drifted.
pub fn drift_steps(drift: Option<Drift>) -> (Option<u32>, Option<u32>) {
    match drift {
        Option::Some(d) => (
            match d.rhythm {
                Option::Some(r) => Option::Some(low32(r)),
                Option::None => Option::None,
            },
            match d.rotate {
                Option::Some(r) => Option::Some(low32(r)),
                Option::None => Option::None,
            },
        ),
        Option::None => (Option::None, Option::None),
    }
}

#[inline(never)]
fn pick(
    style: u32, r: u32, id: u32, e: u32, p: u32, when: Option<u32>, avoid: Option<u8>,
) -> u8 {
    let pl = pool(style * 4 + r);
    let len = pl.len();
    let mut i = moved(len, lab_mix(lab_mix(id, e * 131 + r), p) % len, when, 31 + r);
    let hit = match avoid {
        Option::Some(a) => *pl.at(i) == a,
        Option::None => false,
    };
    if hit && len > 1 {
        i = (i + 1) % len;
    }
    let program = *pl.at(i);
    program
}

/// An edition's band (`band(key, id, e, p, drift)`): style index `style`, species `id`, edition `e`,
/// purchase number `p`; channels 0-7.
pub fn band(style: u32, id: u32, e: u32, p: u32, drift: Option<Drift>) -> Array<u8> {
    let (month, week) = drift_steps(drift);
    let lead = pick(style, 0, id, e, p, month, Option::None);
    let acc = pick(style, 1, id, e, p, week, Option::Some(lead));
    let bass = pick(style, 2, id, e, p, month, Option::Some(lead));
    let pad = pick(style, 3, id, e, p, week, Option::Some(lead));
    let p0 = pool(style * 4);
    let n0 = p0.len();
    let mut at = 0;
    while *p0.at(at) != lead {
        at += 1;
    }
    let span = if n0 > 1 {
        n0 - 1
    } else {
        1
    };
    let second = *p0.at((at + 1 + lab_mix(id, e * 977 + p) % span) % n0);
    let double = if lead == BELL_A || lead == BELL_B {
        FLUTE
    } else {
        GLOCK
    };
    array![lead, lead, acc, bass, pad, double, HARP, second]
}

#[inline(never)]
fn choose(
    pool0: u32, channels: u32, monthly: u32, id: u32, salt: u32, drift: Option<Drift>,
) -> Array<u8> {
    let (month, week) = drift_steps(drift);
    let mut out = array![];
    let mut ch: u32 = 0;
    let mut bit: u32 = 1;
    while ch != channels {
        let pl = pool(pool0 + ch);
        let h = if monthly & bit != 0 {
            month
        } else {
            week
        };
        let i = moved(pl.len(), lab_mix(lab_mix(id, ch * 977 + 13), salt) % pl.len(), h, 57 + ch);
        out.append(*pl.at(i));
        ch += 1;
        bit *= 2;
    }
    out
}

/// A Species or Name Song's band (`choose(songPools[type], songKinds, id, 1, drift)`): 8 channels.
/// The lab drifts the band of a Species Song only (a Name Song keeps its band).
pub fn song_band(beast_type: u8, id: u32, drift: Option<Drift>) -> Array<u8> {
    choose(SONG_POOL0 + beast_type.into() * 8, 8, SONG_MONTHLY, id, 1, drift)
}

/// A Round's or Sound Check's band (`choose(roundPools[type], roundKinds, id, 2, drift)`): 7
/// channels (a Sound Check never drifts).
pub fn round_band(beast_type: u8, id: u32, drift: Option<Drift>) -> Array<u8> {
    choose(ROUND_POOL0 + beast_type.into() * 7, 7, ROUND_MONTHLY, id, 2, drift)
}

#[inline(never)]
fn copy_vlq(smf: Span<u8>, ref i: u32, ref out: Array<u8>) -> u32 {
    let mut l: u32 = 0;
    loop {
        let b = *smf.at(i);
        out.append(b);
        i += 1;
        l = l * 128 + (b & 127).into();
        if b < 128 {
            break;
        }
    }
    l
}

/// The file with each pitched channel's program changes set to `band[ch % band.len()]` and each
/// pitched note (note on/off, poly aftertouch) raised `lift` semitones, at most to 127 (the lab's
/// `lifted` and its setProgram override); channel 10 (drums) untouched.
pub fn orchestrate(smf: Span<u8>, band: Span<u8>, lift: u8) -> Array<u8> {
    let mut out = array![];
    let mut i: u32 = 0;
    while i != 14 {
        out.append(*smf.at(i));
        i += 1;
    }
    let ntr: u32 = (*smf.at(10)).into() * 256 + (*smf.at(11)).into();
    let nb = band.len();
    let mut tr = 0;
    while tr != ntr {
        let mut len: u32 = 0;
        let mut k: u32 = 0;
        while k != 8 {
            let b = *smf.at(i);
            out.append(b);
            if k >= 4 {
                len = len * 256 + b.into();
            }
            i += 1;
            k += 1;
        }
        let stop = i + len;
        let mut run: u8 = 0;
        while i < stop {
            copy_vlq(smf, ref i, ref out);
            let mut s = *smf.at(i);
            if s >= 128 {
                out.append(s);
                i += 1;
            } else {
                s = run;
            }
            if s == 0xff {
                out.append(*smf.at(i));
                i += 1;
                let l = copy_vlq(smf, ref i, ref out);
                let end = i + l;
                while i != end {
                    out.append(*smf.at(i));
                    i += 1;
                }
                continue;
            }
            if s == 0xf0 || s == 0xf7 {
                let l = copy_vlq(smf, ref i, ref out);
                let end = i + l;
                while i != end {
                    out.append(*smf.at(i));
                    i += 1;
                }
                continue;
            }
            run = s;
            let ty = s & 0xf0;
            let ch: u32 = (s & 15).into();
            if ty == 0xc0 || ty == 0xd0 {
                let b = *smf.at(i);
                out.append(if ty == 0xc0 && ch != 9 && nb != 0 {
                    *band.at(ch % nb)
                } else {
                    b
                });
                i += 1;
                continue;
            }
            let b = *smf.at(i);
            if (ty == 0x80 || ty == 0x90 || ty == 0xa0) && ch != 9 {
                let v: u32 = b.into() + lift.into();
                out.append(if v > 127 {
                    127
                } else {
                    v.try_into().unwrap()
                });
            } else {
                out.append(b);
            }
            out.append(*smf.at(i + 1));
            i += 2;
        }
        tr += 1;
    }
    out
}

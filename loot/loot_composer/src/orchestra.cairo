//! The Loot lab's orchestration (offchain/loot-sound/onchain/loot-lab.mjs `band`, `choose`, `lifted`
//! and its setProgram override), so the file a contract returns plays the instruments the lab plays:
//! - `band`: an edition's eight channels (lead, descant, accompaniment, bass, pad, mega double, harp
//!   glissando, second lead) from the style's pools, by Beast, edition and purchase number; drift
//!   moves the lead and bass monthly, the accompaniment and pad weekly.
//! - `song_band` / `round_band`: Species/Name Songs and Rounds/Sound Checks, each channel from its
//!   kind's pool by species.
//! - `orchestrate`: every program change on a pitched channel set to its band instrument, and every
//!   pitched note lifted by `lift` semitones (the lab plays Name Songs +12, Rounds +7).
//! - `vol_factor`, `lead_soft`, `top_soft_smf`: the lab's volume changes on a sample bank (the FM bank is
//!   one): an edition style's MIX times LEAD_SOFT on its lead channels, LEAD_SOFT on a song's channel 0,
//!   and TOP_SOFT on a track's highest voice (loot-lab.mjs `track0()`, `track()`).

use core::dict::Felt252Dict;
use beast_composer::composition::drift::Drift;
use crate::common::{at32, opaque, shr, wadd, wmul};
use crate::species::musical_id;
use super::orchestra_data::{
    BELL_A, BELL_B, EDITION_LEAD_DROP, FLUTE, GLOCK, HARP, LEAD_DROP, LEAD_K, NAME_POOL, POOL_DATA, POOL_OFFS,
    STYLE_LEAD_BOOST,
    ROUND_MONTHLY, ROUND_POOL0, SONG_MELODY, SONG_MONTHLY, SONG_POOL0, VOLS,
};

/// The lab's own mix (loot-lab.mjs `mix`, not the editions').
#[inline(never)]
pub fn lab_mix(a: u32, b: u32) -> u32 {
    let x = wmul(a ^ 0x9e3779b9, 0x85ebca6b) ^ wmul(wadd(b, 0x7f4a7c15), 0xc2b2ae35);
    let x = x ^ shr(x, 0x8000);
    let x = wmul(x, 0x2c1b3c6d);
    x ^ shr(x, 0x1000)
}

#[inline(never)]
fn pool(id: u32) -> Span<u8> {
    let offs = POOL_OFFS.span();
    let mut a = at32(offs, id);
    let b = at32(offs, id + 1);
    let mut out: Array<u8> = opaque(array![]);
    while a != b {
        out.append(at32(POOL_DATA.span(), a).try_into().unwrap());
        a += 1;
    }
    out.span()
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
    crate::rounds::low32(x)
}

/// `stepOf(drift)`: the month's and the week's drift words, when they drifted.
#[inline(never)]
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
    // (Beast `id`'s band is keyed by its musical id, loothero's PR #35)
    let id = musical_id(id);
    let (month, week) = drift_steps(drift);
    let lead = pick(style, 0, id, e, p, month, Option::None);
    let acc = pick(style, 1, id, e, p, week, Option::Some(lead));
    let bass = pick(style, 2, id, e, p, month, Option::Some(lead));
    let pad = pick(style, 3, id, e, p, week, Option::Some(lead));
    let p0 = pool(style * 4);
    let n0 = p0.len();
    let mut at: u32 = opaque(0);
    while *p0.at(at) != lead {
        at += 1;
    }
    let span = if n0 > 1 {
        n0 - 1
    } else {
        1
    };
    let second = *p0.at((at + 1 + lab_mix(id, e * 977 + p) % span) % n0);
    // the descant: never the lead's instrument, another from the lead pool
    let mut others: Array<u8> = opaque(array![]);
    for g in p0 {
        if *g != lead {
            others.append(*g);
        }
    }
    let descant = if others.len() != 0 {
        *others.at(lab_mix(id, e * 389 + p) % others.len())
    } else {
        lead
    };
    let double = if lead == BELL_A || lead == BELL_B {
        FLUTE
    } else {
        GLOCK
    };
    array![lead, descant, acc, bass, pad, double, HARP, second]
}

#[inline(never)]
fn choose(
    pool0: u32,
    channels: u32,
    monthly: u32,
    id: u32,
    salt: u32,
    drift: Option<Drift>,
    lead_pool: u32,
) -> Array<u8> {
    let (month, week) = drift_steps(drift);
    let mut out = opaque(array![]);
    let mut ch: u32 = opaque(0);
    let mut bit: u32 = opaque(1);
    while ch != channels {
        let pl = pool(if ch == 0 {
            lead_pool
        } else {
            pool0 + ch
        });
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

/// `choose(..., song)`: a song's other melody voices (SONG_MELODY) are never the theme's instrument:
/// the next in their pool after the first place it is in that differs, else the first that differs.
fn unlike_theme(band: Array<u8>, pool0: u32) -> Array<u8> {
    let band = band.span();
    let first = *band.at(0);
    let mut out: Array<u8> = array![first];
    let mut ch: u32 = 1;
    let mut bit: u32 = 2;
    while ch != band.len() {
        let mut g = *band.at(ch);
        if SONG_MELODY & bit != 0 && g == first {
            let pl = pool(pool0 + ch);
            let mut at: u32 = 0;
            while *pl.at(at) != g {
                at += 1;
            }
            let mut later: Option<u8> = Option::None;
            let mut any: Option<u8> = Option::None;
            let mut k: u32 = 0;
            while k != pl.len() {
                let x = *pl.at(k);
                if x != first {
                    if any.is_none() {
                        any = Option::Some(x);
                    }
                    if k > at && later.is_none() {
                        later = Option::Some(x);
                    }
                }
                k += 1;
            }
            g = match later {
                Option::Some(x) => x,
                Option::None => match any {
                    Option::Some(x) => x,
                    Option::None => g,
                },
            };
        }
        out.append(g);
        ch += 1;
        bit *= 2;
    }
    out
}

/// A Species Song's band (`choose(songPools[type], songKinds, id, 1, drift, true)`), or with `name`
/// (1..) a Name Song's (its lead from NAME_LEADS, salt 1 + name * 7919): 8 channels. Both drift with
/// the species' clock (the lab, from cc0c9d4).
pub fn song_band(beast_type: u8, id: u32, name: u32, drift: Option<Drift>) -> Array<u8> {
    let pool0 = SONG_POOL0 + beast_type.into() * 8;
    let b = if name == 0 {
        choose(pool0, 8, SONG_MONTHLY, musical_id(id), 1, drift, pool0)
    } else {
        choose(pool0, 8, SONG_MONTHLY, musical_id(id), 1 + name * 7919, drift, NAME_POOL)
    };
    unlike_theme(b, pool0)
}

/// A Round's or Sound Check's band (`choose(roundPools[type], roundKinds, id, 2, drift)`): 7
/// channels (a Sound Check never drifts).
pub fn round_band(beast_type: u8, id: u32, drift: Option<Drift>) -> Array<u8> {
    let pool0 = ROUND_POOL0 + beast_type.into() * 7;
    choose(pool0, 7, ROUND_MONTHLY, musical_id(id), 2, drift, pool0)
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

/// The file with each pitched channel's program changes set to `band[ch % band.len()]`, each pitched
/// note (note on/off, poly aftertouch) raised `lift` semitones, at most to 127, and each CC 7 of a
/// channel with a volume in `vol` (K * 256 + d by channel, 0 none: `song_vols`) scaled (the lab's
/// `lifted` and its setProgram override); channel 10 (drums) untouched but for `kick`: its note ons on
/// keys 35 and 36 that many velocity steps softer, at least 1 (a Name Song's, the lab's `drumSoft`).
pub fn orchestrate(smf: Span<u8>, band: Span<u8>, lift: u8, vol: Span<u64>, kick: u8) -> Array<u8> {
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
            let b2 = *smf.at(i + 1);
            if (ty == 0x80 || ty == 0x90 || ty == 0xa0) && ch != 9 {
                let v: u32 = b.into() + lift.into();
                out.append(if v > 127 {
                    127
                } else {
                    v.try_into().unwrap()
                });
                out.append(b2);
            } else if kick != 0 && ty == 0x90 && ch == 9 && (b == 35 || b == 36) && b2 != 0 {
                out.append(b);
                out.append(if b2 > kick {
                    b2 - kick
                } else {
                    1
                });
            } else if ty == 0xb0 && b == 7 && ch < vol.len() && *vol.at(ch) != 0 {
                out.append(b);
                let x = *vol.at(ch);
                out.append(scaled(b2, x / 256, (x % 256).into()));
            } else {
                out.append(b);
                out.append(b2);
            }
            i += 2;
        }
        tr += 1;
    }
    out
}

/// A VLQ's value, moving `i` past it (no copy).
#[inline(never)]
fn skip_vlq(smf: Span<u8>, ref i: u32) -> u32 {
    let mut l: u32 = opaque(0);
    loop {
        let b = *smf.at(i);
        i += 1;
        l = l * 128 + (b & 127).into();
        if b < 128 {
            break;
        }
    }
    l
}

/// `orchestrate` packed into the `ByteArray` a contract returns. With no lift only the program and CC 7
/// changes differ from the file, so it finds them and packs the untouched runs between them as
/// slices of the input (far fewer steps than copying byte by byte); with a lift it is
/// `orchestrate` then `bytes_to_byte_array`. Same bytes either way.
pub fn orchestrate_byte_array(
    smf: Span<u8>, band: Span<u8>, lift: u8, vol: Span<u64>, kick: u8,
) -> ByteArray {
    if lift != 0 || band.len() == 0 || kick != 0 {
        return midi::pack::bytes_to_byte_array(orchestrate(smf, band, lift, vol, kick).span());
    }
    let nb = band.len();
    let mut chunks: Array<Span<u8>> = array![];
    let mut from: u32 = 0;
    let ntr: u32 = (*smf.at(10)).into() * 256 + (*smf.at(11)).into();
    let mut i: u32 = 14;
    let mut tr = 0;
    while tr != ntr {
        let len: u32 = (*smf.at(i + 4)).into() * 0x1000000
            + (*smf.at(i + 5)).into() * 0x10000
            + (*smf.at(i + 6)).into() * 0x100
            + (*smf.at(i + 7)).into();
        i += 8;
        let stop = i + len;
        let mut run: u8 = 0;
        while i < stop {
            skip_vlq(smf, ref i);
            let mut s = *smf.at(i);
            if s >= 128 {
                i += 1;
            } else {
                s = run;
            }
            if s == 0xff {
                i += 1;
                let l = skip_vlq(smf, ref i);
                i += l;
                continue;
            }
            if s == 0xf0 || s == 0xf7 {
                let l = skip_vlq(smf, ref i);
                i += l;
                continue;
            }
            run = s;
            let ty = s & 0xf0;
            if ty == 0xc0 {
                let ch: u32 = (s & 15).into();
                if ch != 9 {
                    let p = band.slice(ch % nb, 1);
                    if *p.at(0) != *smf.at(i) {
                        chunks.append(smf.slice(from, i - from));
                        chunks.append(p);
                        from = i + 1;
                    }
                }
                i += 1;
                continue;
            }
            if ty == 0xd0 {
                i += 1;
                continue;
            }
            let ch: u32 = (s & 15).into();
            if ty == 0xb0 && *smf.at(i) == 7 && ch < vol.len() && *vol.at(ch) != 0 {
                let x = *vol.at(ch);
                let v = scaled(*smf.at(i + 1), x / 256, (x % 256).into());
                if v != *smf.at(i + 1) {
                    chunks.append(smf.slice(from, i + 1 - from));
                    chunks.append(array![v].span());
                    from = i + 2;
                }
            }
            i += 2;
        }
        tr += 1;
    }
    chunks.append(smf.slice(from, smf.len() - from));
    midi::pack::chunks_to_byte_array(chunks.span())
}

/// A `ByteArray`'s bytes (a file a class returned, to orchestrate): read a word (31 bytes) at a time
/// from its serialized form, far cheaper than `at` byte by byte.
pub fn byte_array_bytes(x: @ByteArray) -> Array<u8> {
    let mut f: Array<felt252> = array![];
    x.serialize(ref f);
    let f = f.span();
    let n: u32 = (*f.at(0)).try_into().unwrap();
    let mut out: Array<u8> = array![];
    let mut i: u32 = 0;
    while i != n {
        push_word(ref out, *f.at(1 + i), 31);
        i += 1;
    }
    push_word(ref out, *f.at(n + 1), (*f.at(n + 2)).try_into().unwrap());
    out
}

/// The `len` low bytes of `w`, most significant first.
#[inline(never)]
fn push_word(ref out: Array<u8>, w: felt252, len: u32) {
    let v: u256 = w.into();
    let mut le: Array<u8> = array![];
    let (mut lo, mut hi) = (v.low, v.high);
    let mut k: u32 = 0;
    while k != len {
        let b = if k < 16 {
            let (q, r) = DivRem::div_rem(lo, 256);
            lo = q;
            r
        } else {
            let (q, r) = DivRem::div_rem(hi, 256);
            hi = q;
            r
        };
        le.append(b.try_into().unwrap());
        k += 1;
    }
    let le = le.span();
    let mut k = len;
    while k != 0 {
        k -= 1;
        out.append(*le.at(k));
    }
}

// ── the lab's volume changes (sample banks) ──

/// A CC 7 value as the lab's `lifted` scales it: max(0, min(127, Math.round(v * f - d))), with `k`
/// the factor in billionths (the generator checks every reachable factor and value against the lab).
#[inline(never)]
pub fn scaled(v: u8, k: u64, d: felt252) -> u8 {
    // (no panic path: CASM size)
    let p: felt252 = v.into() * k.into() + 500000000;
    let p: u128 = match p.try_into() {
        Option::Some(x) => x,
        Option::None => 0,
    };
    let (x, _) = DivRem::div_rem(p, 1000000000);
    let x: felt252 = x.into() - d;
    match x.try_into() {
        Option::Some(y) => if y > 127_u8 {
            127
        } else {
            y
        },
        Option::None => 0,
    }
}

/// A volume change from VOLS: context `ctx` (0 an edition's other channels, 1 its lead channels 0 and
/// 7, 2 a song's channel 0, 3 a Name Song's others, 4 TOP_SOFT), `s` (the edition's style, 1 for a Name
/// Song) and the band instrument: the factor in billionths and the steps taken off after it.
#[inline(never)]
pub fn vol_k(ctx: u32, s: u32, program: u8) -> (u64, felt252) {
    let key: u64 = ((ctx * 16 + s) * 128 + program.into()).into();
    let any: u64 = ((ctx * 16 + 15) * 128 + program.into()).into();
    let mut found: u64 = 0;
    for x in VOLS.span() {
        let kx = *x / 0x100000000;
        if kx == key {
            found = *x % 0x100000000;
            break;
        }
        if kx == any && found == 0 {
            found = *x % 0x100000000;
        }
    }
    let lead = ctx == 1 || ctx == 2;
    if found == 0 {
        found = if lead {
            LEAD_K
        } else {
            1000000000
        };
    }
    let d: felt252 = if ctx == 1 {
        // an edition's leads: EDITION_LEAD_DROP less the style's boost (it may be negative)
        EDITION_LEAD_DROP.into() - (*STYLE_LEAD_BOOST.span().at(s)).into()
    } else if ctx == 2 {
        LEAD_DROP.into()
    } else {
        0
    };
    (found, d)
}

/// A song's volumes by channel (loot-lab.mjs track0's `vol`), for `orchestrate`: K * 256 + d, 0 for
/// none. Channel 0 (the theme) always: LEAD_SOFT x LEAD_ALL (x NAME_SOFT on a Name Song), then
/// LEAD_DROP; a Name Song's other channels NAME_SOFT.
pub fn song_vols(band: Span<u8>, named: bool) -> Array<u64> {
    let mut out: Array<u64> = array![];
    let mut ch: u32 = opaque(0);
    while ch != 8 {
        let (k, d) = if ch == 0 {
            vol_k(2, if named {
                1
            } else {
                0
            }, *band.at(0))
        } else if named {
            vol_k(3, 1, *band.at(ch % band.len()))
        } else {
            (1000000000, 0)
        };
        out.append(if k == 1000000000 && d == 0 {
            0
        } else {
            k * 256 + crate::common::u32_of(d).into()
        });
        ch += 1;
    }
    out
}

/// TOP_SOFT on band instrument `program`, in billionths (0: none).
fn soft_k(program: u8) -> u64 {
    let (k, _) = vol_k(4, 15, program);
    if k == 1000000000 {
        0
    } else {
        k
    }
}

/// A pitched channel's track as the composer wrote it, for TOP_SOFT: the channel, the track's index,
/// the instrument it plays, and the pitch sum and count of the notes the lab's `notesOf` finds.
#[derive(Copy, Drop)]
pub struct Voice {
    pub ch: u32,
    pub at: u32,
    pub program: u8,
    pub sum: felt252,
    pub count: felt252,
}

/// loot-lab.mjs `track()` on the composer's own tracks: of the channels other than 9 and 6, the one
/// whose notes are highest on average (ties: the lowest channel); with its instrument in TOP_SOFT,
/// its CC 7 (byte 6 of its track, after the program change) scaled again, after its other volumes.
#[inline(never)]
pub fn soften_top(tracks: Array<Array<u8>>, voices: Span<Voice>) -> Array<Array<u8>> {
    let mut best: Option<Voice> = Option::None;
    for v in voices {
        let v = *v;
        if v.ch == 6 || v.ch == 9 || v.count == 0 {
            continue;
        }
        best = match best {
            Option::None => Option::Some(v),
            Option::Some(b) => {
                let l: u256 = (v.sum * b.count).into();
                let r: u256 = (b.sum * v.count).into();
                if l > r || (l == r && v.ch < b.ch) {
                    Option::Some(v)
                } else {
                    Option::Some(b)
                }
            },
        };
    }
    let b = match best {
        Option::Some(b) => b,
        Option::None => { return tracks; },
    };
    let k = soft_k(b.program);
    if k == 0 {
        return tracks;
    }
    let mut out: Array<Array<u8>> = array![];
    let mut i: u32 = 0;
    for t in tracks {
        if i == b.at {
            let t = t.span();
            let mut x: Array<u8> = array![];
            x.append_span(t.slice(0, 6));
            x.append(scaled(*t.at(6), k, 0));
            x.append_span(t.slice(7, t.len() - 7));
            out.append(x);
        } else {
            out.append(t);
        }
        i += 1;
    }
    out
}

/// Walks a track body (running status; meta and sysex events skipped). With `ch` 16: adds each note
/// the lab's `notesOf` finds (a note on, velocity > 0, closed by the next note off or zero-velocity
/// note on of its channel and key in this track) to `sums` and `counts` by channel, notes each
/// channel's program (+ 1) in `counts` at 32 + channel, and returns nothing. Otherwise returns where
/// channel `ch`'s CC 7 values are.
#[inline(never)]
fn walk(
    tr: Span<u8>, ch: u32, ref sums: Felt252Dict<u64>, ref counts: Felt252Dict<u64>,
) -> Array<u32> {
    let mut marks: Array<u32> = opaque(array![]);
    let mut on: Felt252Dict<u8> = Default::default();
    let n = tr.len();
    let mut i: u32 = opaque(0);
    let mut run: u8 = opaque(0);
    while i < n {
        skip_vlq(tr, ref i);
        let mut s = *tr.at(i);
        if s >= 128 {
            i += 1;
        } else {
            s = run;
        }
        if s == 0xff {
            i += 1;
            let l = skip_vlq(tr, ref i);
            i += l;
            continue;
        }
        if s == 0xf0 || s == 0xf7 {
            let l = skip_vlq(tr, ref i);
            i += l;
            continue;
        }
        run = s;
        let ty = s & 0xf0;
        let c: u32 = (s & 15).into();
        if ty == 0xc0 || ty == 0xd0 {
            if ty == 0xc0 && ch == 16 {
                // the channel's program (+ 1), at 32 + channel
                let p: u64 = (*tr.at(i)).into();
                counts.insert((32 + c).into(), p + 1);
            }
            i += 1;
            continue;
        }
        let a = *tr.at(i);
        if ch == 16 {
            let k: felt252 = (c * 128 + a.into()).into();
            if ty == 0x90 && *tr.at(i + 1) != 0 {
                on.insert(k, 1);
            } else if (ty == 0x80 || ty == 0x90) && on.get(k) == 1 {
                on.insert(k, 0);
                let kc: felt252 = c.into();
                sums.insert(kc, sums.get(kc) + a.into());
                counts.insert(kc, counts.get(kc) + 1);
            }
        } else if ty == 0xb0 && a == 7 && c == ch {
            marks.append(i + 1);
        }
        i += 2;
    }
    marks
}

/// loot-lab.mjs `track()`: of the channels other than 9 and 6, the one whose notes are highest on
/// average (ties: the lowest channel) over the track bodies; with its instrument in TOP_SOFT, that
/// channel and the percentage. The instrument is `band[ch % band.len()]`, or with `band` empty the
/// channel's program in the file (a played file: the band's, written in place).
fn soft_top(tracks: Span<Span<u8>>, band: Span<u8>) -> Option<(u32, u64)> {
    let mut sums: Felt252Dict<u64> = Default::default();
    let mut counts: Felt252Dict<u64> = Default::default();
    for t in tracks {
        walk(*t, 16, ref sums, ref counts);
    }
    let (mut top, mut bs, mut bc): (u32, u64, u64) = opaque((16, 0, 1));
    let mut c: u32 = opaque(0);
    while c != 16 {
        let k: felt252 = c.into();
        let n = counts.get(k);
        if c != 6 && c != 9 && n != 0 {
            let s = sums.get(k);
            if top == 16 || s * bc > bs * n {
                top = c;
                bs = s;
                bc = n;
            }
        }
        c += 1;
    }
    if top == 16 {
        return Option::None;
    }
    let program: u64 = if band.len() != 0 {
        (*band.at(top % band.len())).into() + 1
    } else {
        counts.get((32 + top).into())
    };
    let p = if program == 0 {
        0
    } else {
        soft_k((program - 1).try_into().unwrap())
    };
    if p == 0 {
        Option::None
    } else {
        Option::Some((top, p))
    }
}

/// A track body with channel `ch`'s CC 7 values scaled by `k` (billionths).
#[inline(never)]
fn soften(tr: Span<u8>, ch: u32, k: u64) -> Array<u8> {
    let mut sums: Felt252Dict<u64> = Default::default();
    let mut counts: Felt252Dict<u64> = Default::default();
    let mut out: Array<u8> = opaque(array![]);
    let mut from: u32 = opaque(0);
    for m in walk(tr, ch, ref sums, ref counts) {
        out.append_span(tr.slice(from, m - from));
        out.append(scaled(*tr.at(m), k, 0));
        from = m + 1;
    }
    out.append_span(tr.slice(from, tr.len() - from));
    out
}

/// Whether any instrument of the band is in TOP_SOFT (else `top_soft_smf` changes nothing).
#[inline(never)]
pub fn has_soft(band: Span<u8>) -> bool {
    for p in band {
        if soft_k(*p) != 0 {
            return true;
        }
    }
    false
}

/// TOP_SOFT (see `soft_top`) on a whole file (a Song's: the Beast composer's, orchestrated; or a played
/// file from the composer class, with `band` empty): the new file, or none when nothing changes.
pub fn top_soft_smf(smf: Span<u8>, band: Span<u8>) -> Option<Array<u8>> {
    let ntr: u32 = (*smf.at(10)).into() * 256 + (*smf.at(11)).into();
    let mut spans: Array<Span<u8>> = array![];
    let mut i: u32 = 14;
    let mut tr = 0;
    while tr != ntr {
        let len: u32 = (*smf.at(i + 4)).into() * 0x1000000
            + (*smf.at(i + 5)).into() * 0x10000
            + (*smf.at(i + 6)).into() * 0x100
            + (*smf.at(i + 7)).into();
        spans.append(smf.slice(i + 8, len));
        i += 8 + len;
        tr += 1;
    }
    let (ch, k) = soft_top(spans.span(), band)?;
    let mut out: Array<u8> = array![];
    out.append_span(smf.slice(0, 14));
    for t in spans {
        midi::smf::push_chunk(ref out, 0x4d54726b, soften(t, ch, k).span());
    }
    Option::Some(out)
}

/// `top_soft_smf`, packed.
pub fn top_soft_byte_array(smf: Span<u8>, band: Span<u8>) -> ByteArray {
    match top_soft_smf(smf, band) {
        Option::Some(x) => midi::pack::bytes_to_byte_array(x.span()),
        Option::None => midi::pack::bytes_to_byte_array(smf),
    }
}

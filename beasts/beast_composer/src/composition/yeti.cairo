//! The Yeti special (species 68), on every Yeti track: 16th-note ornaments in the theme's first
//! section placed by the track's own ornament profile, the avalanche (a run down each section's
//! closing chord on its own voice) and the rock groove at 175 BPM. Byte-identical to the lab's
//! `yetiOrnaments(..., varied)`, `yetiAvalanche` and `rockDrums` (offchain/beast-sound/src/lab.js)
//! as `sampleTrackMidi` applies them.

use core::dict::{Felt252Dict, Felt252DictTrait};
use midi::smf::{TrackWriter, TrackWriterTrait};
use crate::composition::beast_score::transposed_tonic;
use crate::composition::melodic_canon::NoteEvent;
use crate::opaque::opaque;

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
    /// The tonic, within 24..=96.
    home: u8,
    scale: Span<u8>,
}

/// The key the track plays: the tonic (clamped to the composer's range) and the scale (the
/// track's real scale, else the composer's melodic one for the mode).
pub fn yeti_key(tonic_keynum: u8, mode_id: u8, scale: Option<Span<u8>>) -> YetiKey {
    let home = transposed_tonic(tonic_keynum, 0);
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

const SEVEN: NonZero<u32> = 7;

/// The pitch of a degree of the key (0 is the tonic, 7 an octave up), for degrees from -35 (the
/// callers reach -30..=43).
// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
fn pitch(k: YetiKey, d: i32) -> i32 {
    // the degree shifted up five octaves, to be unsigned: its octave is `o - 5`, its scale index
    // `i`
    let (o, i) = DivRem::div_rem((d + 35).try_into().unwrap(), SEVEN);
    let off: u32 = (*k.scale.at(i)).into();
    let shifted: u32 = k.home.into() + 12 * o + off; // the pitch, shifted up five octaves
    shifted.try_into().unwrap() - 60
}

fn abs(x: i32) -> i32 {
    if x < 0 {
        -x
    } else {
        x
    }
}

const TWELVE: NonZero<u32> = 12;

/// The nearest degree to a pitch (-28..=42; ties keep the earlier best, starting from 0).
///
/// `pitch` rises with the degree (the scale rises within its octave), so only the degree at or
/// below the pitch and the one above it can be nearest; beyond either end of the range, the end is.
/// Of a tie the lower wins, unless 0 is in it: the scan this replaced started from 0 and gave way
/// only to a strictly nearer degree.
fn degree(k: YetiKey, p: u8) -> i32 {
    // the pitch above the tonic, shifted up eight octaves to be unsigned (the tonic is at most 96,
    // the pitch at least 0): its octave is `q - 8`, its semitones into the octave `rem`
    let (q, rem) = DivRem::div_rem(p.into() + 96 - k.home.into(), TWELVE);
    // the octave's degrees at or below `rem` (the first, 0, always is), and the semitones of the
    // nearest degree below and above it (the next octave's first, 12, when none follows)
    let mut hi = 7 * q; // the degree above the pitch, shifted up 56
    let mut below: u32 = 0;
    let mut above: u32 = 12;
    for off in k.scale {
        let off: u32 = (*off).into();
        if off > rem {
            above = off;
            break;
        }
        below = off;
        hi += 1;
    }
    if hi < 29 {
        return -28;
    }
    if hi >= 99 {
        return 42;
    }
    let hi: i32 = hi.try_into().unwrap() - 56;
    let (to_lo, to_hi) = (rem - below, above - rem);
    if to_hi < to_lo || to_hi == to_lo && hi == 0 {
        hi
    } else {
        hi - 1
    }
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

#[cfg(test)]
mod degree_tests {
    use crate::composition::genesis::named_mode_scale;
    use super::{YetiKey, abs, degree, melodic_scale, pitch};

    // The scan `degree` and `pitch` replaced, as the oracle.
    fn floor_div7_ref(d: i32) -> i32 {
        if d >= 0 {
            d / 7
        } else {
            -((-d + 6) / 7)
        }
    }

    fn pitch_ref(k: YetiKey, d: i32) -> i32 {
        let o = floor_div7_ref(d);
        let i: u32 = (d - 7 * o).try_into().unwrap();
        let off: i32 = (*k.scale.at(i)).into();
        let home: i32 = k.home.into();
        home + 12 * o + off
    }

    fn degree_ref(k: YetiKey, p: i32) -> i32 {
        let mut best: i32 = 0;
        let mut bd = abs(pitch_ref(k, 0) - p);
        let mut d: i32 = -28;
        while d <= 42 {
            let x = abs(pitch_ref(k, d) - p);
            if x < bd {
                best = d;
                bd = x;
            }
            d += 1;
        }
        best
    }

    /// Every scale a `YetiKey` can hold: `melodic_scale` and `named_mode_scale` for every mode.
    fn scales() -> Array<Span<u8>> {
        let mut all: Array<Span<u8>> = array![];
        let mut mode: u8 = 0;
        loop {
            let mut found = array![melodic_scale(mode)];
            if let Option::Some(named) = named_mode_scale(mode) {
                found.append(named);
            }
            for sc in found {
                let mut known = false;
                for other in all.span() {
                    if *other == sc {
                        known = true;
                    }
                }
                if !known {
                    all.append(sc);
                }
            }
            if mode == 255 {
                break;
            }
            mode += 1;
        }
        all
    }

    #[test]
    #[available_gas(1000000000000)]
    fn scales_rise_within_an_octave() {
        let all = scales();
        // the other tests loop over these: this count flags a scale added to the composer
        assert_eq!(all.len(), 6);
        for sc in all {
            assert_eq!(sc.len(), 7);
            assert_eq!(*sc.at(0), 0);
            assert!(*sc.at(6) < 12);
            let mut i = 1;
            while i < 7 {
                assert!(*sc.at(i - 1) < *sc.at(i));
                i += 1;
            }
        }
    }

    /// The callers' degrees are -28..=42 from `degree`, one or two steps off it.
    #[test]
    #[available_gas(1000000000000)]
    fn pitch_matches_the_original() {
        for sc in scales() {
            let mut home: u8 = 24;
            while home <= 96 {
                let k = YetiKey { home, scale: sc };
                let mut d: i32 = -35;
                while d <= 49 {
                    assert_eq!(pitch(k, d), pitch_ref(k, d));
                    d += 1;
                }
                home += 1;
            }
        }
    }

    /// `degree_ref` shifts with the home (`pitch_ref` is `home` plus a function of the degree), so
    /// its answers at home 0 for the pitches -96..=231 (the u8 pitches at the homes 24..=96) are
    /// its answers at every home: `degree` equals them for every key and every pitch. One scale per
    /// test: a test run keeps what it allocates, and CI runs several at once.
    fn degree_matches_the_scan_at_every_home(scale: usize) {
        let sc = *scales().at(scale);
        let mut want: Array<i32> = array![];
        let mut rel: i32 = -96;
        while rel <= 231 {
            want.append(degree_ref(YetiKey { home: 0, scale: sc }, rel));
            rel += 1;
        }
        let mut home: u8 = 24;
        while home <= 96 {
            let k = YetiKey { home, scale: sc };
            let mut p: u32 = 0;
            while p <= 255 {
                assert_eq!(degree(k, p.try_into().unwrap()), *want.at(p + 96 - home.into()));
                p += 1;
            }
            home += 1;
        }
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_every_home_0() {
        degree_matches_the_scan_at_every_home(0);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_every_home_1() {
        degree_matches_the_scan_at_every_home(1);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_every_home_2() {
        degree_matches_the_scan_at_every_home(2);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_every_home_3() {
        degree_matches_the_scan_at_every_home(3);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_every_home_4() {
        degree_matches_the_scan_at_every_home(4);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_every_home_5() {
        degree_matches_the_scan_at_every_home(5);
    }

    /// The shift above checked directly, at the lowest, highest and a middle home, one scale per
    /// test.
    fn degree_matches_the_scan_at_the_ends_and_middle(scale: usize) {
        let sc = *scales().at(scale);
        for home in array![24, 60, 96] {
            let k = YetiKey { home, scale: sc };
            let mut p: u8 = 0;
            loop {
                assert_eq!(degree(k, p), degree_ref(k, p.into()));
                if p == 255 {
                    break;
                }
                p += 1;
            }
        }
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_the_ends_and_middle_0() {
        degree_matches_the_scan_at_the_ends_and_middle(0);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_the_ends_and_middle_1() {
        degree_matches_the_scan_at_the_ends_and_middle(1);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_the_ends_and_middle_2() {
        degree_matches_the_scan_at_the_ends_and_middle(2);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_the_ends_and_middle_3() {
        degree_matches_the_scan_at_the_ends_and_middle(3);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_the_ends_and_middle_4() {
        degree_matches_the_scan_at_the_ends_and_middle(4);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_at_the_ends_and_middle_5() {
        degree_matches_the_scan_at_the_ends_and_middle(5);
    }

    /// Every home against the scan itself, for one scale (about 40 s): the two tests above,
    /// unshortcut. A run keeps what it allocates, so one test per scale.
    fn degree_matches_the_scan_unshortcut(scale: usize) {
        let sc = *scales().at(scale);
        let mut home: u8 = 24;
        while home <= 96 {
            let k = YetiKey { home, scale: sc };
            let mut p: u8 = 0;
            loop {
                assert_eq!(degree(k, p), degree_ref(k, p.into()));
                if p == 255 {
                    break;
                }
                p += 1;
            }
            home += 1;
        }
    }

    #[test]
    #[ignore]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_unshortcut_0() {
        degree_matches_the_scan_unshortcut(0);
    }

    #[test]
    #[ignore]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_unshortcut_1() {
        degree_matches_the_scan_unshortcut(1);
    }

    #[test]
    #[ignore]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_unshortcut_2() {
        degree_matches_the_scan_unshortcut(2);
    }

    #[test]
    #[ignore]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_unshortcut_3() {
        degree_matches_the_scan_unshortcut(3);
    }

    #[test]
    #[ignore]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_unshortcut_4() {
        degree_matches_the_scan_unshortcut(4);
    }

    #[test]
    #[ignore]
    #[available_gas(1000000000000)]
    fn degree_matches_the_scan_unshortcut_5() {
        degree_matches_the_scan_unshortcut(5);
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

// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
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

// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
fn profile(id: u64, prefix: u8, suffix: u8) -> Profile {
    let h = beast_hash(id, prefix, suffix, 5);
    let g = beast_hash(id, prefix, suffix, 6);
    let (mut pool, mut figures, mut k): (Array<u8>, Array<u8>, u32) = opaque(
        (array![MORDENT, UPPER, TURN, RUN, SLIDE, TRILL], array![], 0),
    );
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
    let mut used: u32 = opaque(0);
    for f in fig.span() {
        used += f.len;
    }
    if used >= dur {
        return fig;
    }
    let rest = dur - used;
    let n = fig.len();
    let last = *fig.at(n - 1);
    let (mut out, mut i): (Array<Seg>, u32) = opaque((array![], 0));
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
    // the theme's notes in the first section (event indices, chronological); `opaque` state, so
    // each loop is compiled once
    let (mut idx, mut i, first, no_best): (Array<u32>, u32, u32, u32) = opaque(
        (array![], 0, 0, 0xffffffff),
    );
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
    let mut j = first;
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
    let mut picked = first;
    if pr.placement == EVEN {
        let mut k = first;
        while k < ne {
            if k % gap == 0 {
                pick.insert((*elig.at(k)).into(), true);
                picked += 1;
            }
            k += 1;
        }
    } else if pr.placement == BURSTS {
        let cycle = pr.burst + gap + 2;
        let mut k = first;
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
        let mut t = first;
        while t < take {
            let mut best = no_best;
            let mut k = first;
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
        let mut k = first;
        let mut m = first;
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
        let mut k = first;
        let mut m = first;
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
        let mut k = first;
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
    let mut j = first;
    while j < n {
        if pick.get(j.into()) {
            let e = note_at(events, idx, j);
            let p: i32 = e.pitch.into();
            let d = degree(key, e.pitch);
            let up = pitch(key, d + 1);
            let down = pitch(key, d - 1);
            let vel: u8 = if e.velocity > 13 {
                e.velocity - 12
            } else {
                1
            };
            let can_run = if j + 1 < n {
                let nx = note_at(events, idx, j + 1);
                nx.time == e.time + e.duration && abs(degree(key, nx.pitch) - d) >= 2
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
                let nd = degree(key, note_at(events, idx, j + 1).pitch);
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
    let mut j = first;
    while j < n {
        at.insert((*idx.at(j)).into(), j + 1);
        j += 1;
    }
    let mut i = first;
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
    let (mut scale, mut d): (Array<u8>, i32) = opaque((array![], 0));
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
                let (mut all, mut k): (Array<i32>, u32) = opaque((array![], 0));
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
            let mut k: u32 = opaque(0);
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
    // One step per 120 ticks; `eighth`: u % 240 == 0, carried instead of divided out of `u`.
    let (toms, mut track, mut u, mut eighth): (Span<u8>, TrackWriter, u32, bool) = opaque(
        (array![50, 48, 47, 45].span(), TrackWriterTrait::with_running_status(), 0, true),
    );
    if length == 0 {
        return track.finish_at(0);
    }
    let fill_start = sec - 480;
    while u < length {
        let rel = u % sec;
        if rel == 0 {
            track.note_on(u, 9, 49, 110);
        }
        if rel >= fill_start {
            let i = (rel - fill_start) / 120;
            let k = if i < 4 {
                *toms.at(i)
            } else {
                45
            };
            track.note_on(u, 9, k, (96 + i * 6).try_into().unwrap());
        } else if eighth {
            let q = rel % 1920;
            // The kick or snare (key 0: none), then the hat, accented where q % 480 == 0: the
            // kicks on 1 and 3 and the snare, not the kick on the and of 3.
            let mut drum_key: u8 = 0;
            let mut drum_vel: u8 = 0;
            let mut hat_vel: u8 = 84;
            if q == 0 || q == 960 {
                drum_key = 36;
                drum_vel = 120;
            } else if q == 480 || q == 1440 {
                drum_key = 38;
                drum_vel = 112;
            } else {
                hat_vel = 60;
                if q == 1200 {
                    drum_key = 36;
                    drum_vel = 96;
                }
            }
            if drum_key != 0 {
                track.note_on(u, 9, drum_key, drum_vel);
            }
            track.note_on(u, 9, 42, hat_vel);
        }
        u += 120;
        eighth = !eighth;
        if !eighth && rel + 120 < fill_start {
            // the sixteenth between two eighths plays nothing before the fill: skip it
            u += 120;
            eighth = true;
        }
    }
    track.finish_at(length)
}

#[cfg(test)]
mod rock_drum_track_tests {
    use midi::smf::TrackWriterTrait;
    use super::rock_drum_track;

    /// `rock_drum_track` as it was when every step divided its position out of `u`: the reference
    /// the carried eighth and the skipped steps must reproduce byte for byte.
    fn divided_rock_drum_track(length: u32, sec: u32) -> Array<u8> {
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

    fn assert_same(length: u32, sec: u32) {
        assert(
            rock_drum_track(length, sec) == divided_rock_drum_track(length, sec),
            'rock drum track differs',
        );
    }

    fn assert_same_for_section(sec: u32) {
        assert_same(1, sec);
        assert_same(119, sec);
        assert_same(120, sec);
        assert_same(121, sec);
        assert_same(sec - 1, sec);
        assert_same(sec, sec);
        assert_same(sec + 1, sec);
        assert_same(2 * sec + 360, sec);
        assert_same(2 * sec + 361, sec);
        assert_same(3 * sec, sec);
    }

    /// What the callers pass: whole bars to a section, whole sections to the form.
    #[test]
    #[available_gas(1000000000000)]
    fn matches_on_whole_sections() {
        let mut bars: u32 = 1;
        while bars <= 4 {
            let sec = bars * 1920;
            assert_same(sec, sec);
            assert_same(2 * sec, sec);
            assert_same(3 * sec, sec);
            bars += 1;
        }
        assert_same(8 * 3840, 3840);
    }

    /// Sections that are not a whole number of bars, of steps or of eighth notes.
    #[test]
    #[available_gas(1000000000000)]
    fn matches_off_the_bar_grid() {
        assert_same_for_section(480);
        assert_same_for_section(481);
        assert_same_for_section(599);
        assert_same_for_section(600);
        assert_same_for_section(719);
        assert_same_for_section(960);
        assert_same_for_section(1000);
        assert_same_for_section(1919);
        assert_same_for_section(1921);
        assert_same_for_section(2160);
    }

    /// No ticks: just End of Track, whatever `sec` is (no `sec - 480` underflow).
    #[test]
    fn end_of_track_only_in_no_ticks() {
        assert(rock_drum_track(0, 3840) == divided_rock_drum_track(0, 3840), 'differs');
        assert(rock_drum_track(0, 0) == divided_rock_drum_track(0, 0), 'differs');
        assert(rock_drum_track(0, 100) == divided_rock_drum_track(0, 100), 'differs');
    }
}

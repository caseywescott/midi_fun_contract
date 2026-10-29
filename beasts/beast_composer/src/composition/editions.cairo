//! Monthly Track Editions: the Cairo port of offchain/beast-sound/src/editions.js (`editionMidi`),
//! byte for byte. An edition is a style engine plus a genome (meter, tempo, harmony,
//! accompaniment, bass, drums, preset palette); curated editions 1-12, procedural ones from 13 on.
//! The Beast carries into every style (species tonic, the opening of its Genesis theme, its type's
//! palette shade, the mega lead when shiny) and the track seed picks the song inside the style.
//! Edition 0 is the seeded canon (`genesis::seeded_track_smf_bytes`), not this engine.
//!
//! The source's floating-point steps have integer forms here: R() < p compares the raw 32-bit
//! draw with a threshold, R.int(n) is (raw * n) >> 32 (exact in a double for every n it is called
//! with), and the melody's sine contour is a table (editions_data.cairo, generated from the
//! source).

use core::dict::{Felt252Dict, Felt252DictTrait};
use core::num::traits::{WrappingAdd, WrappingMul};
use midi::smf::{TrackWriterTrait, smf_bytes};
use super::editions_data::{
    CURATED, ENGINE_COUNT, EngineDef, P012, P030, P050, P066, P090, QUAL_LEN, QUAL_TONES, SCALES,
    SPECIES, cells, contour_bounds, engine_def, grammar_progs, grammar_scale, groove, pool,
};

const TPQ: u32 = 480;
const EIGHTH: u32 = 240;
const TWO32: u64 = 0x100000000;

// engine ids (editions_data ENGINE order)
const E_CHORALE: u8 = 1;
const E_PHASE: u8 = 4;
const E_SONG: u8 = 5;
const E_VARIATIONS: u8 = 6;
const E_BLUES: u8 = 8;
const E_BATTLE: u8 = 11;
// accompaniment kinds
const A_BLOCK: u8 = 0;
const A_STRUM: u8 = 1;
const A_STAB: u8 = 2;
const A_WALTZ: u8 = 3;
const A_OOMPAH: u8 = 4;
const A_ARP16: u8 = 5;
const A_ALBERTI: u8 = 6;
const A_MUSICBOX: u8 = 7;
const A_SHUFFLE: u8 = 8;
const A_BOSSA: u8 = 9;
const A_TOLLING: u8 = 10;
// bass kinds
const B_ROOT: u8 = 0;
const B_ROOTFIFTH: u8 = 1;
const B_WALTZ: u8 = 2;
const B_OCTAVE8: u8 = 3;
const B_BOOGIE: u8 = 4;
const B_PEDAL: u8 = 5;
const B_BOSSA: u8 = 6;
const B_SIXEIGHT: u8 = 7;
const B_DRONE: u8 = 8;
const B_RIFF: u8 = 9;
// grooves
const G_NONE: u8 = 0;
const G_ROCK: u8 = 1;
const G_HALFTIME: u8 = 2;
const G_MARCH: u8 = 5;
const G_WALTZ: u8 = 6;
const G_BATTLE: u8 = 9;
const G_BATTLE16: u8 = 10;
const G_MINIMAL: u8 = 11;
// feels and counters
const F_LYRIC: u8 = 0;
const F_HEROIC: u8 = 1;
const F_VOCAL: u8 = 2;
const F_SLOW: u8 = 4;
const C_LINE: u8 = 1;
const C_THIRDS: u8 = 2;
const C_RESPONSE: u8 = 3;
// section kinds
const K_B: u8 = 1;
const K_C: u8 = 2;
const K_V: u8 = 3;
// channels
const CH_LEAD: u8 = 0;
const CH_COUNTER: u8 = 1;
const CH_ACCOMP: u8 = 2;
const CH_BASS: u8 = 3;
const CH_PAD: u8 = 4;
const CH_TENOR: u8 = 5;
const CH_MEGA: u8 = 6;
const CH_DRUMS: u8 = 9;

const MEGA_LEADS: [u8; 2] = [50, 65];
const POW2: [u32; 12] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048];

// ── randomness
// ──────────────────────────────────────────────────────────────────────────────────

/// The source's `hash32`: FNV-1a over the key's characters, then a murmur-style finish.
pub fn hash32(key: @ByteArray) -> u32 {
    let mut h: u32 = 2166136261;
    let n = key.len();
    let mut i = 0;
    while i < n {
        let b: u32 = key.at(i).unwrap().into();
        h = (h ^ b).wrapping_mul(16777619);
        i += 1;
    }
    h = h ^ (h / 0x2000);
    h = h.wrapping_mul(0x5bd1e995);
    h ^ (h / 0x8000)
}

/// mulberry32, as the source's `rng`.
#[derive(Copy, Drop)]
pub struct Rng {
    a: u32,
}

#[generate_trait]
pub impl RngImpl of RngTrait {
    fn new(seed: u32) -> Rng {
        Rng { a: seed }
    }

    /// The next raw 32-bit draw (the source's R() is this / 2^32).
    fn next(ref self: Rng) -> u32 {
        self.a = self.a.wrapping_add(0x6d2b79f5);
        let t = self.a;
        let t = (t ^ (t / 0x8000)).wrapping_mul(t | 1);
        let t = t ^ t.wrapping_add((t ^ (t / 0x80)).wrapping_mul(t | 61));
        t ^ (t / 0x4000)
    }

    /// floor(R() * n).
    fn int(ref self: Rng, n: u32) -> u32 {
        let x: u64 = self.next().into();
        ((x * n.into()) / TWO32).try_into().unwrap()
    }

    /// R() < p, `threshold` = the raw form of p.
    fn chance(ref self: Rng, threshold: u64) -> bool {
        let x: u64 = self.next().into();
        x < threshold
    }

    fn pick_u8(ref self: Rng, xs: Span<u8>) -> u8 {
        *xs.at(self.int(xs.len()))
    }

    fn pick_i32(ref self: Rng, xs: Span<i32>) -> i32 {
        *xs.at(self.int(xs.len()))
    }
}

fn seeded(key: ByteArray) -> Rng {
    RngTrait::new(hash32(@key))
}

// ── pitch helpers
// ───────────────────────────────────────────────────────────────────────────────

const TWELVE: NonZero<u32> = 12;
const SEVEN: NonZero<u32> = 7;

/// x mod 12 in 0..12, for x >= -1200.
fn md12(x: i32) -> u32 {
    let u: u32 = (x + 1200).try_into().unwrap();
    let (_, r) = DivRem::div_rem(u, TWELVE);
    r
}

fn abs(x: i32) -> i32 {
    if x < 0 {
        -x
    } else {
        x
    }
}

fn max_i(a: i32, b: i32) -> i32 {
    if a > b {
        a
    } else {
        b
    }
}

fn min_i(a: i32, b: i32) -> i32 {
    if a < b {
        a
    } else {
        b
    }
}

fn to_i(x: u32) -> i32 {
    x.try_into().unwrap()
}

fn has(mask: u32, pc: u32) -> bool {
    mask & *POW2.span().at(pc) != 0
}

fn chord_r(ch: u8) -> i32 {
    (ch / 16).into()
}

fn chord_q(ch: u8) -> u32 {
    (ch % 16).into()
}

/// The chord's tones over its root (3 or 4).
fn chord_tones(ch: u8) -> Span<i32> {
    let q = chord_q(ch);
    let t = *QUAL_TONES.span().at(q);
    let all = t.span();
    all.slice(0, *QUAL_LEN.span().at(q))
}

fn scale_of(id: u8) -> Span<i32> {
    let s = *SCALES.span().at(id.into());
    s.span()
}

/// The pitches in [lo, hi] whose pitch class is in `mask`, ascending.
fn list_pitches(mask: u32, lo: i32, hi: i32) -> Array<i32> {
    let mut out: Array<i32> = array![];
    let mut pc = md12(lo);
    let mut p = lo;
    while p <= hi {
        if has(mask, pc) {
            out.append(p);
        }
        p += 1;
        pc += 1;
        if pc == 12 {
            pc = 0;
        }
    }
    out
}

/// The index of the first element nearest to `p` (the list ascends).
fn nearest_idx(list: Span<i32>, p: i32) -> u32 {
    let mut best: u32 = 0;
    let mut bd = abs(*list.at(0) - p);
    let mut i: u32 = 1;
    let n = list.len();
    while i < n {
        let x = *list.at(i);
        let d = abs(x - p);
        if d < bd {
            bd = d;
            best = i;
        } else if x > p {
            break;
        }
        i += 1;
    }
    best
}

fn nearest(list: Span<i32>, p: i32) -> i32 {
    *list.at(nearest_idx(list, p))
}

/// The source's stepIn: k steps from p's place in the list (or its nearest), clamped to the ends.
fn step_in(list: Span<i32>, p: i32, k: i32) -> i32 {
    let i = to_i(nearest_idx(list, p)) + k;
    let last = to_i(list.len()) - 1;
    let j = if i < 0 {
        0
    } else if i > last {
        last
    } else {
        i
    };
    *list.at(j.try_into().unwrap())
}

/// The motif cameo: scale degrees in this key's scale near `center`.
fn motif_pitches(degrees: Span<i32>, tonic: i32, scale: Span<i32>, center: i32) -> Array<i32> {
    let base = center - to_i(md12(center - tonic));
    let mut out: Array<i32> = array![];
    for d in degrees {
        let (o, i) = DivRem::div_rem((*d + 35).try_into().unwrap(), SEVEN);
        out.append(base + *scale.at(i) + 12 * (to_i(o) - 5));
    }
    out
}

// ── species and genome
// ──────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop)]
struct Species {
    id: u32,
    tier: u32,
    kind: u32,
    tonic: i32,
    degrees: Span<i32>,
}

fn species(id: u32) -> Species {
    assert(id >= 1 && id <= 75, 'editions: species');
    let mut v: u64 = *SPECIES.span().at(id - 1);
    let tonic: i32 = (v % 16).try_into().unwrap();
    v /= 16;
    let mut degrees: Array<i32> = array![];
    for _ in 0..8_u32 {
        let d: i32 = (v % 16).try_into().unwrap();
        degrees.append(d - 8);
        v /= 16;
    }
    let k = id - 1;
    Species { id, tier: (k % 25) / 5 + 1, kind: k / 25, tonic, degrees: degrees.span() }
}

#[derive(Copy, Drop)]
pub struct Genome {
    pub engine: u8,
    pub grammar: u8,
    pub form: Span<u8>,
    pub accomp: u8,
    pub bass: u8,
    pub drums: u8,
    pub bpm: u32,
    /// [lead, counter, accomp, bass, pad] x [Magic, Hunter, Brute]
    pub palette: Span<u8>,
}

fn edition_key(e: u32) -> ByteArray {
    format!("EDITION|{}", e)
}

/// The engine of edition `e` (255: the canon). Procedural editions pick one not used in the
/// previous three months, so they are walked from the first procedural one.
pub fn edition_engine(e: u32) -> u8 {
    let curated = CURATED.span();
    if e < curated.len() {
        return *curated.at(e);
    }
    let n = curated.len();
    let (mut r1, mut r2, mut r3) = (*curated.at(n - 1), *curated.at(n - 2), *curated.at(n - 3));
    let mut k = n;
    loop {
        let mut r = seeded(edition_key(k));
        let eng = pick_engine(ref r, r1, r2, r3);
        if k == e {
            break eng;
        }
        r3 = r2;
        r2 = r1;
        r1 = eng;
        k += 1;
    }
}

fn pick_engine(ref r: Rng, r1: u8, r2: u8, r3: u8) -> u8 {
    let mut free: u32 = 0;
    for x in 0..ENGINE_COUNT {
        let x: u8 = x.try_into().unwrap();
        if x != r1 && x != r2 && x != r3 {
            free += 1;
        }
    }
    let mut j = r.int(free);
    let mut out: u8 = 0;
    for x in 0..ENGINE_COUNT {
        let x: u8 = x.try_into().unwrap();
        if x != r1 && x != r2 && x != r3 {
            if j == 0 {
                out = x;
                break;
            }
            j -= 1;
        }
    }
    out
}

fn pick_span(ref r: Rng, xs: Span<Span<u8>>) -> Span<u8> {
    *xs.at(r.int(xs.len()))
}

/// Edition `e`'s genome (the source's editionGenome; not for the canon).
pub fn edition_genome(e: u32) -> Genome {
    let engine = edition_engine(e);
    assert(engine != 255, 'editions: edition 0 is canon');
    let d = engine_def(engine);
    if e < CURATED.span().len() {
        return Genome {
            engine,
            grammar: *d.grammars.at(0),
            form: *d.forms.at(0),
            accomp: *d.accomp.at(0),
            bass: *d.bass.at(0),
            drums: *d.drums.at(0),
            bpm: (d.bpm_lo + d.bpm_hi + 1) / 2,
            palette: d.palette,
        };
    }
    let mut r = seeded(edition_key(e));
    r.next(); // the engine pick
    let grammar = r.pick_u8(d.grammars);
    let form = pick_span(ref r, d.forms);
    let accomp = r.pick_u8(d.accomp);
    let bass = r.pick_u8(d.bass);
    let drums = r.pick_u8(d.drums);
    let bpm = d.bpm_lo + r.int(d.bpm_hi - d.bpm_lo + 1);
    let mut palette: Array<u8> = array![];
    if engine == E_CHORALE {
        let org = r.pick_u8([95, 43, 47, 81, 33].span());
        for _ in 0..12_u32 {
            palette.append(org);
        }
        palette.append_span(d.palette.slice(12, 3));
    } else {
        for role in 0..5_u32 {
            let p = pool(role);
            for _ in 0..3_u32 {
                palette.append(r.pick_u8(p));
            }
        }
    }
    Genome { engine, grammar, form, accomp, bass, drums, bpm, palette: palette.span() }
}

// ── the context
// ─────────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop)]
pub struct Note {
    pub t: u32,
    pub d: u32,
    pub p: u8,
    pub v: u8,
    pub ch: u8,
}

#[derive(Copy, Drop)]
struct MelNote {
    t: u32,
    d: u32,
    p: i32,
}

/// A section's chords: `per` (1 or 2) per bar, bar-major.
#[derive(Copy, Drop)]
struct Chords {
    cells: Span<u8>,
    per: u32,
    bars: u32,
}

#[derive(Destruct)]
struct Ctx {
    r: Rng,
    g: Genome,
    d: EngineDef,
    sp: Species,
    shiny: bool,
    scale: u8,
    tonic: i32,
    num: u32,
    den: u32,
    bar: u32,
    six: bool,
    /// the second strong position in the bar (0: only the downbeat)
    strong2: u32,
    bpm: u32,
    prog_a: Span<u8>,
    prog_b: Span<u8>,
    riff: Span<(u32, i32, i32)>,
    notes: Array<Note>,
    /// (scale, chord) -> chord-scale masks | 1 << 24
    cs_cache: Felt252Dict<u32>,
    /// lead, counter, accomp, bass, pad, mega
    pal: Span<u8>,
}

#[generate_trait]
impl CtxImpl of CtxTrait {
    fn note(ref self: Ctx, ch: u8, t: u32, d: i32, p: i32, v: i32) {
        if d > 0 && p >= 0 && p < 128 {
            let d: u32 = max_i(30, d).try_into().unwrap();
            let v: u8 = max_i(1, min_i(127, v)).try_into().unwrap();
            self.notes.append(Note { t, d, p: p.try_into().unwrap(), v, ch });
        }
    }

    fn notes_at(ref self: Ctx, ch: u8, t: u32, d: i32, ps: Span<i32>, v: i32) {
        for p in ps {
            self.note(ch, t, d, *p, v);
        }
    }

    fn is_strong(self: @Ctx, t: u32) -> bool {
        let pos = t % self.bar;
        pos == 0 || (self.strong2 != 0 && pos == self.strong2)
    }

    /// The source's chordScale as (scale pcs mask, chord tone mask): the scale with each chord
    /// tone replacing the scale note it bends (within a semitone), else added.
    fn chord_scale(ref self: Ctx, chord: u8) -> (u32, u32) {
        let key: felt252 = (self.scale.into() * 256 + chord.into());
        let cached = self.cs_cache.get(key);
        if cached != 0 {
            return (cached % 4096, (cached / 4096) % 4096);
        }
        let scale = scale_of(self.scale);
        let mut pcs: Array<u32> = array![];
        for s in scale {
            pcs.append(md12(self.tonic + *s));
        }
        let r = chord_r(chord);
        let tones = chord_tones(chord);
        let mut ct_mask: u32 = 0;
        for t in tones {
            ct_mask = ct_mask | *POW2.span().at(md12(self.tonic + r + *t));
        }
        for t in tones {
            let c = md12(self.tonic + r + *t);
            let mut present = false;
            for p in pcs.span() {
                if *p == c {
                    present = true;
                    break;
                }
            }
            if present {
                continue;
            }
            let mut best: u32 = 99;
            let mut bd: u32 = 9;
            let mut i: u32 = 0;
            for p in pcs.span() {
                let p = *p;
                let up = (p + 12 - c) % 12;
                let down = (c + 12 - p) % 12;
                let dd = if up < down {
                    up
                } else {
                    down
                };
                if dd < bd && !has(ct_mask, p) {
                    bd = dd;
                    best = i;
                }
                i += 1;
            }
            if best != 99 && bd <= 1 {
                let mut next: Array<u32> = array![];
                let mut j: u32 = 0;
                for p in pcs.span() {
                    next.append(if j == best {
                        c
                    } else {
                        *p
                    });
                    j += 1;
                }
                pcs = next;
            } else {
                pcs.append(c);
            }
        }
        let mut mask: u32 = 0;
        for p in pcs.span() {
            mask = mask | *POW2.span().at(*p);
        }
        self.cs_cache.insert(key, mask + ct_mask * 4096 + 0x1000000);
        (mask, ct_mask)
    }

    fn root_in(self: @Ctx, r: i32, lo: i32) -> i32 {
        lo + to_i(md12(self.tonic + r - lo))
    }

    fn chords_for(self: @Ctx, prog: Span<u8>, bars: u32) -> Chords {
        let per = self.d.per_bar;
        let n = prog.len();
        let mut cells: Array<u8> = array![];
        for b in 0..bars {
            if per == 2 {
                cells.append(*prog.at((b * 2) % n));
                cells.append(*prog.at((b * 2 + 1) % n));
            } else {
                cells.append(*prog.at((b / self.d.chord_bars) % n));
            }
        }
        Chords { cells: cells.span(), per, bars }
    }

    fn chord_at_tick(self: @Ctx, chords: Chords, t: u32) -> u8 {
        let mut b = t / self.bar;
        if b >= chords.bars {
            b = chords.bars - 1;
        }
        if chords.per == 1 {
            *chords.cells.at(b)
        } else if (t % self.bar) < self.bar / 2 {
            *chords.cells.at(2 * b)
        } else {
            *chords.cells.at(2 * b + 1)
        }
    }
}

fn chord_cell(chords: Chords, b: u32, h: u32) -> u8 {
    *chords.cells.at(b * chords.per + h)
}

// ── melody
// ──────────────────────────────────────────────────────────────────────────────────────

/// A melody over `bars` bars: two-bar ideas (the first carrying the motif when given), an
/// antecedent ending on a half cadence and a consequent restating its first two bars and closing
/// on the tonic (`full`) or the chord's fifth.
fn melody(
    ref c: Ctx,
    chords: Chords,
    bars: u32,
    lo: i32,
    hi: i32,
    feel: u8,
    motif: Span<i32>,
    full: bool,
    ref r: Rng,
) -> Array<MelNote> {
    let cs = cells(c.six, feel);
    let slow = cells(c.six, F_SLOW);
    let half = if bars / 2 > 2 {
        bars / 2
    } else {
        2
    };
    let idea0 = *cs.at(r.int(cs.len()));
    let idea1 = *cs.at(r.int(cs.len()));
    let mut plan: Array<Span<i32>> = array![];
    for b in 0..bars {
        let m = b % half;
        plan
            .append(
                if m < 2 {
                    if b % 2 == 0 {
                        idea0
                    } else {
                        idea1
                    }
                } else {
                    *cs.at(r.int(cs.len()))
                },
            );
    }
    let mut out: Array<MelNote> = array![];
    let mut prev = (lo + hi + 1) / 2;
    let mut mi: u32 = 0; // motif notes used
    let bt = c.bar;
    for b in 0..bars {
        let end_half = b == half - 1;
        let end_all = b == bars - 1;
        if b >= half && b < half + 2 && out.len() > 0 {
            let src = out.span();
            let (s0, s1) = ((b - half) * bt, (b - half + 1) * bt);
            for n in src {
                let n = *n;
                if n.t >= s0 && n.t < s1 {
                    let t = n.t + half * bt;
                    let chord = c.chord_at_tick(chords, t);
                    let (pcs, ct) = c.chord_scale(chord);
                    let mut p = nearest(list_pitches(pcs, lo, hi).span(), n.p);
                    if c.is_strong(t) {
                        p = nearest(list_pitches(ct, lo, hi).span(), p);
                    }
                    out.append(MelNote { t, d: n.d, p });
                    prev = p;
                }
            }
            continue;
        }
        let cell = if end_half || end_all {
            *slow.at(r.int(slow.len()))
        } else {
            *plan.at(b)
        };
        // the bar (the source's writeBar)
        let mut last: u32 = 0;
        let mut i: u32 = 0;
        for u in cell {
            if *u > 0 {
                last = i;
            }
            i += 1;
        }
        let end_kind: u8 = if end_all {
            if full {
                1
            } else {
                2
            }
        } else if end_half {
            2
        } else {
            0
        };
        let (bound_up, bound_down) = contour_bounds(lo, half, b % half);
        let mut t = b * bt;
        let mut i: u32 = 0;
        for u in cell {
            let u = *u;
            let dur: u32 = (abs(u) * 240).try_into().unwrap();
            if u > 0 {
                let chord = c.chord_at_tick(chords, t);
                let (pcs, ct) = c.chord_scale(chord);
                let strong = c.is_strong(t);
                let mut p: i32 = 0;
                if mi < motif.len() {
                    p = *motif.at(mi);
                    mi += 1;
                    while p > hi {
                        p -= 12;
                    }
                    while p < lo {
                        p += 12;
                    }
                    if strong && !has(ct, md12(p)) {
                        p = nearest(list_pitches(ct, lo, hi).span(), p);
                    }
                } else {
                    let dir: i32 = if prev < bound_up {
                        1
                    } else if prev > bound_down {
                        -1
                    } else if r.chance(P050) {
                        1
                    } else {
                        -1
                    };
                    let x: u64 = r.next().into();
                    let k = if x < P012 {
                        0
                    } else if x < P066 {
                        dir
                    } else if x < P090 {
                        2 * dir
                    } else if r.chance(P050) {
                        3 * dir
                    } else {
                        -3 * dir
                    };
                    p = step_in(list_pitches(pcs, lo, hi).span(), prev, k);
                    if strong || dur >= 3 * EIGHTH {
                        p = nearest(list_pitches(ct, lo, hi).span(), p);
                    }
                }
                if end_kind != 0 && i == last {
                    let cr = chord_r(chord);
                    let goal = if end_kind == 1 {
                        md12(c.tonic + cr)
                    } else {
                        let tones = chord_tones(chord);
                        md12(c.tonic + cr + *tones.at(2))
                    };
                    p = nearest(list_pitches(*POW2.span().at(goal), lo, hi).span(), prev);
                }
                out.append(MelNote { t, d: dur, p });
                prev = p;
            }
            t += dur;
            i += 1;
        }
    }
    out
}

/// The closest voicing of `chord` in [lo, hi] to `prev` (none: the middle candidate).
fn voicing(
    ref c: Ctx, chord: u8, lo: i32, hi: i32, prev: Option<Span<i32>>, size: u32,
) -> Array<i32> {
    let r = chord_r(chord);
    let tones = chord_tones(chord);
    let mut pcs: Array<u32> = array![];
    let mut mask: u32 = 0;
    for t in tones {
        let pc = md12(c.tonic + r + *t);
        pcs.append(pc);
        mask = mask | *POW2.span().at(pc);
    }
    let pcs = pcs.span();
    let want = if size < pcs.len() {
        size
    } else {
        pcs.len()
    };
    let (p0, p1, p2) = (*pcs.at(0), *pcs.at(1), *pcs.at(2));
    let mut cands: Array<Span<i32>> = array![];
    let mut base = lo;
    let mut bpc = md12(lo);
    while base <= hi {
        if bpc == p0 || bpc == p1 || bpc == p2 {
            let mut v: Array<i32> = array![base];
            let mut vmask = *POW2.span().at(bpc);
            let mut p = base;
            let mut ppc = bpc;
            while v.len() < want {
                p += 1;
                ppc += 1;
                if ppc == 12 {
                    ppc = 0;
                }
                if has(mask, ppc) && !has(vmask, ppc) {
                    v.append(p);
                    vmask = vmask | *POW2.span().at(ppc);
                }
                if p > hi + 12 {
                    break;
                }
            }
            if v.len() == want && *v.at(want - 1) <= hi + 2 {
                cands.append(v.span());
            }
        }
        base += 1;
        bpc += 1;
        if bpc == 12 {
            bpc = 0;
        }
    }
    if cands.len() == 0 {
        // every tone in [lo, lo + 11], ascending
        let mut xs: Array<i32> = array![];
        for pc in pcs {
            xs.append(lo + to_i(md12(to_i(*pc) - lo)));
        }
        return sort_small(xs.span());
    }
    match prev {
        Option::None => {
            let mid = *cands.at(cands.len() / 2);
            let mut out: Array<i32> = array![];
            out.append_span(mid);
            out
        },
        Option::Some(pv) => {
            let mut best = *cands.at(0);
            let mut bc = voicing_cost(best, pv);
            let mut i: u32 = 1;
            while i < cands.len() {
                let v = *cands.at(i);
                let cost = voicing_cost(v, pv);
                if cost < bc {
                    bc = cost;
                    best = v;
                }
                i += 1;
            }
            let mut out: Array<i32> = array![];
            out.append_span(best);
            out
        },
    }
}

fn voicing_cost(v: Span<i32>, prev: Span<i32>) -> i32 {
    let mut s: i32 = 0;
    let mut i: u32 = 0;
    let last = *prev.at(prev.len() - 1);
    for x in v {
        let q = if i < prev.len() {
            *prev.at(i)
        } else {
            last
        };
        s += abs(*x - q);
        i += 1;
    }
    s
}

fn sort_small(xs: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = array![];
    let mut used: u32 = 0;
    let n = xs.len();
    for _ in 0..n {
        let mut bi: u32 = 99;
        let mut bv: i32 = 0;
        let mut i: u32 = 0;
        for x in xs {
            if used & *POW2.span().at(i) == 0 && (bi == 99 || *x < bv) {
                bi = i;
                bv = *x;
            }
            i += 1;
        }
        used = used | *POW2.span().at(bi);
        out.append(bv);
    }
    out
}

// ── accompaniment, bass and drums
// ──────────────────────────────────────────────────────────────

fn accompany(ref c: Ctx, ch: u8, chords: Chords, t0: u32, bars: u32, kind: u8, vel: i32) {
    let mut prev: Option<Span<i32>> = Option::None;
    let beat = 1920 / c.den;
    let bt = c.bar;
    let lo: i32 = if kind == A_MUSICBOX {
        64
    } else if kind == A_ARP16 {
        60
    } else {
        55
    };
    for b in 0..bars {
        for h in 0..chords.per {
            let chord = chord_cell(chords, b, h);
            let len = bt / chords.per;
            let t = t0 + b * bt + h * len;
            let size = if chord_tones(chord).len() > 3 {
                4
            } else {
                3
            };
            let v = voicing(ref c, chord, lo, lo + 14, prev, size).span();
            prev = Option::Some(v);
            let li = to_i(len);
            if kind == A_BLOCK {
                c.notes_at(ch, t, li / 2 - 20, v, vel);
                c.notes_at(ch, t + len / 2, li / 2 - 20, v, vel - 8);
            } else if kind == A_STRUM {
                let mut i: u32 = 0;
                for e in [0_u32, 3, 5, 6].span() {
                    if *e * EIGHTH < len {
                        c.notes_at(ch, t + *e * EIGHTH, 460, v, if i > 0 {
                            vel - 10
                        } else {
                            vel
                        });
                    }
                    i += 1;
                }
            } else if kind == A_STAB {
                for e in [3_u32, 7].span() {
                    if *e * EIGHTH < len {
                        c.notes_at(ch, t + *e * EIGHTH, 100, v, vel + 6);
                    }
                }
                if c.r.chance(P030) {
                    c.notes_at(ch, t + 1320, 60, v, vel - 10);
                }
            } else if kind == A_WALTZ {
                let d = to_i(beat * 3 / 5);
                c.notes_at(ch, t + beat, d, v, vel - 6);
                c.notes_at(ch, t + 2 * beat, d, v, vel - 12);
            } else if kind == A_OOMPAH {
                let mut k: u32 = 1;
                while k * beat < len {
                    c.notes_at(ch, t + k * beat, to_i(beat / 2), v, vel - 4);
                    k += 2;
                }
            } else if kind == A_ARP16 {
                let mut seq: Array<i32> = array![];
                seq.append_span(v);
                seq.append(*v.at(0) + 12);
                seq.append(*v.at(1) + 12);
                let n = v.len();
                // [...v].reverse().map(+12).slice(1), then [...v].reverse().slice(1, -1)
                let mut j = n - 1;
                while j > 0 {
                    j -= 1;
                    seq.append(*v.at(j) + 12);
                }
                let mut j = n - 1;
                while j > 1 {
                    j -= 1;
                    seq.append(*v.at(j));
                }
                let seq = seq.span();
                let mut k: u32 = 0;
                while k * 120 < len {
                    c
                        .note(
                            ch,
                            t + k * 120,
                            110,
                            *seq.at(k % seq.len()),
                            if k % 4 != 0 {
                                vel - 12
                            } else {
                                vel
                            },
                        );
                    k += 1;
                }
            } else if kind == A_ALBERTI {
                let seq = [*v.at(0), *v.at(2), *v.at(1), *v.at(2)].span();
                let mut k: u32 = 0;
                while k * EIGHTH < len {
                    c
                        .note(
                            ch,
                            t + k * EIGHTH,
                            220,
                            *seq.at(k % 4),
                            if k % 2 != 0 {
                                vel - 10
                            } else {
                                vel
                            },
                        );
                    k += 1;
                }
            } else if kind == A_MUSICBOX {
                let seq = [*v.at(0), *v.at(1), *v.at(2), *v.at(0) + 12, *v.at(2), *v.at(1)].span();
                let mut k: u32 = 0;
                while k * EIGHTH < len {
                    c
                        .note(
                            ch,
                            t + k * EIGHTH,
                            384,
                            *seq.at(k % 6),
                            if k % 3 != 0 {
                                vel - 14
                            } else {
                                vel
                            },
                        );
                    k += 1;
                }
            } else if kind == A_SHUFFLE {
                let three = v.slice(0, 3);
                let mut k: u32 = 0;
                while k * beat < len {
                    c.notes_at(ch, t + k * beat, to_i(beat * 11 / 20), three, vel - 6);
                    c
                        .notes_at(
                            ch, t + k * beat + beat * 2 / 3, to_i(beat / 3) - 10, three, vel - 18,
                        );
                    k += 1;
                }
            } else if kind == A_BOSSA {
                for s in [0_u32, 3, 6, 10, 13].span() {
                    if *s * 120 < len {
                        c
                            .notes_at(
                                ch, t + *s * 120, 200, v, if *s % 2 != 0 {
                                    vel - 4
                                } else {
                                    vel
                                },
                            );
                    }
                }
            } else if kind == A_TOLLING {
                let v0 = *v.at(0);
                c.notes_at(ch, t, to_i(len * 9 / 10), [v0, v0 + 12].span(), vel - 10);
            }
        }
    }
}

fn bass_line(ref c: Ctx, ch: u8, chords: Chords, t0: u32, bars: u32, kind: u8, vel: i32) {
    let beat = 1920 / c.den;
    let bi = to_i(beat);
    let bt = c.bar;
    for b in 0..bars {
        for h in 0..chords.per {
            let chord = chord_cell(chords, b, h);
            let len = bt / chords.per;
            let li = to_i(len);
            let t = t0 + b * bt + h * len;
            let root = c.root_in(chord_r(chord), 36);
            let fifth = root + *chord_tones(chord).at(2);
            let low5 = if fifth > 50 {
                fifth - 12
            } else {
                fifth
            };
            if kind == B_ROOT {
                c.note(ch, t, li - 30, root, vel);
            } else if kind == B_ROOTFIFTH {
                let mut k: u32 = 0;
                while k * 2 * beat < len {
                    let odd = k % 2 == 1;
                    c
                        .note(
                            ch,
                            t + k * 2 * beat,
                            bi * 7 / 5,
                            if odd {
                                low5
                            } else {
                                root
                            },
                            if odd {
                                vel - 8
                            } else {
                                vel
                            },
                        );
                    k += 1;
                }
            } else if kind == B_WALTZ {
                c.note(ch, t, bi * 9 / 10, root, vel);
            } else if kind == B_OCTAVE8 {
                let mut k: u32 = 0;
                while k * EIGHTH < len {
                    let odd = k % 2 == 1;
                    c
                        .note(
                            ch,
                            t + k * EIGHTH,
                            210,
                            if odd {
                                root + 12
                            } else {
                                root
                            },
                            if odd {
                                vel - 10
                            } else {
                                vel
                            },
                        );
                    k += 1;
                }
            } else if kind == B_BOOGIE {
                let st = [0_i32, 4, 7, 9, 10, 9, 7, 4].span();
                for k in 0..8_u32 {
                    let odd = k % 2 == 1;
                    let at = t + (k / 2) * beat + if odd {
                        beat * 2 / 3
                    } else {
                        0
                    };
                    let d = if odd {
                        bi / 3 - 10
                    } else {
                        bi * 2 / 3 - 10
                    };
                    c.note(ch, at, d, root + *st.at(k), if odd {
                        vel - 12
                    } else {
                        vel
                    });
                }
            } else if kind == B_PEDAL {
                if b % 2 == 0 && h == 0 {
                    let span = if 2 * bt < (bars - b) * bt {
                        2 * bt
                    } else {
                        (bars - b) * bt
                    };
                    c.note(ch, t, to_i(span) - 40, root, vel - 10);
                }
            } else if kind == B_BOSSA {
                let next = if h + 1 < chords.per {
                    chord_cell(chords, b, h + 1)
                } else if b + 1 < chords.bars {
                    chord_cell(chords, b + 1, 0)
                } else {
                    chord_cell(chords, 0, 0)
                };
                c.note(ch, t, bi * 7 / 5, root, vel);
                c.note(ch, t + beat * 3 / 2, bi / 2 - 20, low5, vel - 12);
                c.note(ch, t + 2 * beat, bi * 7 / 5, low5, vel - 6);
                c.note(ch, t + beat * 7 / 2, bi / 2 - 20, c.root_in(chord_r(next), 36), vel - 12);
            } else if kind == B_SIXEIGHT {
                c.note(ch, t, 690, root, vel - 10);
                c.note(ch, t + 720, 690, low5, vel - 18);
            } else if kind == B_DRONE {
                if h == 0 {
                    let r0 = c.root_in(0, 36);
                    let r7 = c.root_in(7, 36);
                    c.note(ch, t, li - 40, r0, vel - 10);
                    c.note(ch, t, li - 40, if r7 < r0 {
                        r7 + 12
                    } else {
                        r7
                    }, vel - 30);
                }
            } else if kind == B_RIFF {
                for x in c.riff {
                    let (off, d, deg) = *x;
                    if off < len {
                        c
                            .note(
                                ch,
                                t + off,
                                d,
                                root + deg,
                                if off % TPQ != 0 {
                                    vel - 12
                                } else {
                                    vel
                                },
                            );
                    }
                }
            }
        }
    }
}

const TOMS: [i32; 6] = [50, 48, 47, 45, 43, 41];

fn drums(ref c: Ctx, t0: u32, bars: u32, g: u8, fill: bool, crash: bool, quiet: bool) {
    if g == G_NONE {
        return;
    }
    let (steps, hits) = groove(g);
    let bt = c.bar;
    let step = bt / steps;
    let soft: i32 = if quiet {
        24
    } else {
        0
    };
    let start = bt - if c.den == 8 {
        720
    } else {
        960
    };
    for b in 0..bars {
        let t = t0 + b * bt;
        let fill_bar = fill && b == bars - 1 && g != G_WALTZ && g != G_MINIMAL;
        for h in hits {
            let h = *h;
            let at = t + (h % 256) * step;
            let key = (h / 256) % 256;
            // the fill replaces the bar's last beats, kicks kept
            if fill_bar && at >= t + start && key != 36 {
                continue;
            }
            c.note(CH_DRUMS, at, 60, to_i(key), to_i(h / 65536) - soft);
        }
        if crash && b == 0 {
            c.note(CH_DRUMS, t, 200, 49, if quiet {
                70
            } else {
                96
            });
        }
        if fill_bar {
            let n: u32 = if c.den == 8 {
                6
            } else {
                8
            };
            for i in 0..n {
                let key = if i == n - 1 {
                    38
                } else {
                    *TOMS.span().at(i * 6 / n)
                };
                c.note(CH_DRUMS, t + start + i * (bt - start) / n, 60, key, 80 + 3 * to_i(i));
            }
        }
    }
}

// ── sections
// ────────────────────────────────────────────────────────────────────────────────────

fn counter_line(ref c: Ctx, mel: Span<MelNote>, chords: Chords, bars: u32, t0: u32) {
    let (lo, hi, vel) = (52_i32, 64_i32, 70_i32);
    let bt = c.bar;
    let step = if c.num == 3 || c.den == 8 {
        bt
    } else {
        bt / 2
    };
    let mut prev: i32 = 58;
    let mut mi: u32 = 0;
    let mut t: u32 = 0;
    while t < bars * bt {
        let chord = c.chord_at_tick(chords, t);
        let (_, ct) = c.chord_scale(chord);
        let tones = list_pitches(ct, lo, hi).span();
        // the melody note sounding at t (they do not overlap and ascend)
        while mi < mel.len() && mel.at(mi).t + mel.at(mi).d <= t {
            mi += 1;
        }
        let m = if mi < mel.len() && mel.at(mi).t <= t {
            Option::Some(*mel.at(mi))
        } else {
            Option::None
        };
        let mut p = match m {
            Option::Some(n) => if n.p > prev {
                step_in(tones, prev, -1)
            } else {
                step_in(tones, prev, 1)
            },
            Option::None => nearest(tones, prev),
        };
        if let Option::Some(n) = m {
            if abs(n.p - p) < 3 {
                p = step_in(tones, p, -1);
            }
        }
        c.note(CH_COUNTER, t0 + t, to_i(step) - 30, p, vel);
        prev = p;
        t += step;
    }
}

fn thirds_below(ref c: Ctx, mel: Span<MelNote>, chords: Chords, t0: u32, vel: i32) {
    for n in mel {
        let n = *n;
        if n.d < EIGHTH {
            continue;
        }
        let chord = c.chord_at_tick(chords, n.t);
        let (pcs, _) = c.chord_scale(chord);
        let list = list_pitches(pcs, n.p - 12, n.p).span();
        c.note(CH_COUNTER, t0 + n.t, to_i(n.d) - 20, step_in(list, n.p, -2), vel);
    }
}

fn write_section(
    ref c: Ctx,
    kind: u8,
    bars: u32,
    t0: u32,
    idx: u32,
    ref mel_a: Option<Span<MelNote>>,
    ref mel_b: Option<Span<MelNote>>,
) {
    let g = c.g;
    let bt = c.bar;
    let is_b = kind == K_B || kind == K_C;
    let chords = c.chords_for(if is_b {
        c.prog_b
    } else {
        c.prog_a
    }, bars);
    let center: i32 = if is_b {
        74
    } else {
        69
    };
    let (lo, hi) = (center - 8, center + 8);
    let cached = if is_b {
        mel_b
    } else {
        mel_a
    };
    let mel = match cached {
        Option::Some(m) => m,
        Option::None => {
            let motif = if !is_b && idx == 0 {
                let k = if c.six {
                    6
                } else {
                    8
                };
                motif_pitches(c.sp.degrees.slice(0, k), c.tonic, scale_of(c.scale), 69).span()
            } else {
                [].span()
            };
            let seed = c.r.int(1000000000);
            let kch: ByteArray = if kind == K_B {
                "B"
            } else if kind == K_C {
                "C"
            } else if kind == K_V {
                "V"
            } else {
                "A"
            };
            let mut mr = seeded(format!("MEL|{}|{}", seed, kch));
            let feel = if kind == K_V {
                F_VOCAL
            } else {
                c.d.feel
            };
            let m = melody(ref c, chords, bars, lo, hi, feel, motif, !is_b, ref mr).span();
            if is_b {
                mel_b = Option::Some(m);
            } else {
                mel_a = Option::Some(m);
            }
            m
        },
    };
    let quiet = kind == K_V;
    for n in mel {
        let n = *n;
        let (mut t, mut d) = (n.t, n.d);
        if c.d.swing && t % TPQ == EIGHTH {
            t += 80;
            d -= 80;
        } else if c.d.swing && d == EIGHTH {
            d += 80;
        }
        c.note(CH_LEAD, t0 + t, to_i(d) - 20, n.p, if t % bt != 0 {
            90
        } else {
            100
        });
        if c.shiny {
            c.note(CH_MEGA, t0 + t, to_i(d) - 20, n.p + 12, 70);
        }
    }
    if c.d.counter == C_LINE && c.sp.tier <= 3 {
        counter_line(ref c, mel, chords, bars, t0);
    }
    if c.d.counter == C_THIRDS {
        thirds_below(ref c, mel, chords, t0, 76);
    }
    if c.d.counter == C_RESPONSE {
        for n in mel {
            let n = *n;
            if (n.t / (2 * bt)) % 2 == 0 {
                c.note(CH_COUNTER, t0 + n.t + bt, to_i(n.d) - 20, n.p - 12, 72);
            }
        }
    }
    accompany(ref c, CH_ACCOMP, chords, t0, bars, g.accomp, if quiet {
        60
    } else {
        72
    });
    bass_line(ref c, CH_BASS, chords, t0, bars, g.bass, 96);
    if g.drums != G_NONE && !(quiet && g.engine == E_SONG && idx == 0) {
        drums(ref c, t0, bars, if quiet {
            G_MINIMAL
        } else {
            g.drums
        }, true, !quiet, quiet);
    }
    if c.sp.tier <= 2 && g.engine != E_BLUES {
        let mut b: u32 = 0;
        while b < bars {
            let v = voicing(ref c, chord_cell(chords, b, 0), 52, 66, Option::None, 3);
            let span = if bars - b < 2 {
                bars - b
            } else {
                2
            };
            c.notes_at(CH_PAD, t0 + b * bt, to_i(span * bt) - 40, v.span(), 46);
            b += 2;
        }
    }
}

/// pickBelow: the pitch in [lo, top) of a wanted class nearest `prev` (none: top - 5), the lowest
/// of a tie; top - 5 if there is none.
fn pick_below(top: i32, lo: i32, prev: Option<i32>, want: u32) -> i32 {
    let target = match prev {
        Option::Some(p) => p,
        Option::None => top - 5,
    };
    let mut best: i32 = 0;
    let mut bd: i32 = 999;
    let mut p = lo;
    let mut pc = md12(lo);
    while p < top {
        if has(want, pc) {
            let d = abs(p - target);
            if d < bd {
                bd = d;
                best = p;
            }
        }
        p += 1;
        pc += 1;
        if pc == 12 {
            pc = 0;
        }
    }
    if bd == 999 {
        top - 5
    } else {
        best
    }
}

#[derive(Copy, Drop)]
struct Sop {
    t: u32,
    d: u32,
    p: i32,
    chord: u8,
}

fn write_chorale(ref c: Ctx) -> u32 {
    let bt = c.bar;
    let form = c.g.form;
    let mut t0: u32 = 0;
    let mut sop_a: Option<Span<Sop>> = Option::None;
    let mut sop_b: Option<Span<Sop>> = Option::None;
    let bars: u32 = 8;
    let mut idx: u32 = 0;
    for kind in form {
        let is_b = *kind == K_B;
        let chords = c.chords_for(if is_b {
            c.prog_b
        } else {
            c.prog_a
        }, bars);
        let cached = if is_b {
            sop_b
        } else {
            sop_a
        };
        let sop = match cached {
            Option::Some(s) => s,
            Option::None => {
                let mut sop: Array<Sop> = array![];
                let mut prev: i32 = if is_b {
                    74
                } else {
                    71
                };
                let motif = if !is_b && idx == 0 {
                    motif_pitches(c.sp.degrees.slice(0, 4), c.tonic, scale_of(c.scale), 70).span()
                } else {
                    [].span()
                };
                let mut mi: u32 = 0;
                for b in 0..bars {
                    for h in 0..2_u32 {
                        let t = b * bt + h * bt / 2;
                        let chord = chord_cell(chords, b, h % chords.per);
                        let (_, ct) = c.chord_scale(chord);
                        let tones = list_pitches(ct, 64, 79).span();
                        let mut p = if mi < motif.len() {
                            mi += 1;
                            nearest(tones, *motif.at(mi - 1))
                        } else {
                            let k = c.r.pick_i32([-1, 0, 1, 1, -1].span());
                            step_in(tones, nearest(tones, prev), k)
                        };
                        if b == bars - 1 && h == 1 {
                            let pc = md12(c.tonic + chord_r(chord));
                            p = nearest(list_pitches(*POW2.span().at(pc), 64, 79).span(), prev);
                        }
                        sop.append(Sop { t, d: bt / 2, p, chord });
                        prev = p;
                    }
                }
                let s = sop.span();
                if is_b {
                    sop_b = Option::Some(s);
                } else {
                    sop_a = Option::Some(s);
                }
                s
            },
        };
        let mut pa: Option<i32> = Option::None;
        let mut pt: Option<i32> = Option::None;
        for s in sop {
            let s = *s;
            let r = chord_r(s.chord);
            let tones = chord_tones(s.chord);
            let mut pcs: u32 = 0;
            for i in 0..3_u32 {
                pcs = pcs | *POW2.span().at(md12(c.tonic + r + *tones.at(i)));
            }
            let bass = c.root_in(r, 40);
            let sp_bit = *POW2.span().at(md12(s.p));
            let need = pcs & ~sp_bit;
            let alto = pick_below(s.p, max_i(55, s.p - 9), pa, if need != 0 {
                need
            } else {
                pcs
            });
            let not_alto = pcs & ~*POW2.span().at(md12(alto));
            let tenor = pick_below(
                alto, max_i(48, alto - 9), pt, if not_alto != 0 {
                    not_alto
                } else {
                    pcs
                },
            );
            pa = Option::Some(alto);
            pt = Option::Some(tenor);
            let t = t0 + s.t;
            let d = to_i(s.d) - 30;
            c.note(CH_LEAD, t, d, s.p, 92);
            c.note(CH_COUNTER, t, d, alto, 76);
            c.note(CH_TENOR, t, d, tenor, 74);
            c.note(CH_BASS, t, d, bass, 88);
            if c.shiny {
                c.note(CH_MEGA, t, d, s.p + 12, 64);
            }
        }
        if c.sp.tier <= 2 {
            let mut b: u32 = 0;
            while b < bars {
                let root = c.root_in(0, 36);
                c.note(CH_PAD, t0 + b * bt, to_i(4 * bt) - 60, root, 50);
                b += 4;
            }
        }
        t0 += bars * bt;
        idx += 1;
    }
    t0
}

fn write_phase(ref c: Ctx) -> u32 {
    let bt = c.bar;
    let cell_notes = motif_pitches(c.sp.degrees.slice(0, 6), c.tonic, scale_of(c.scale), 72).span();
    let len_a = 6 + c.r.int(2);
    let len_b = len_a + 1 + c.r.int(2);
    let s_step: u32 = 240;
    let form = c.g.form;
    let bars: u32 = 8;
    let mut t0: u32 = 0;
    let mut mel_m: Option<Span<MelNote>> = Option::None;
    let mut idx: u32 = 0;
    for kind in form {
        let is_b = *kind == K_B;
        let chords = c.chords_for(if is_b {
            c.prog_b
        } else {
            c.prog_a
        }, bars);
        let end = bars * bt;
        let mut k: u32 = 0;
        while k * s_step < end {
            let t = k * s_step;
            let chord = c.chord_at_tick(chords, t);
            let (pcs, _) = c.chord_scale(chord);
            let list = list_pitches(pcs, 60, 90).span();
            let a = k % len_a;
            if a < cell_notes.len() {
                c
                    .note(
                        CH_ACCOMP,
                        t0 + t,
                        210,
                        nearest(list, *cell_notes.at(a)),
                        if a == 0 {
                            86
                        } else {
                            70
                        },
                    );
            }
            let bb = k % len_b;
            if bb < cell_notes.len() && (is_b || idx > 0) {
                let p = step_in(list, nearest(list, *cell_notes.at(bb) + 12), 0);
                c.note(CH_COUNTER, t0 + t, 210, p, if bb == 0 {
                    76
                } else {
                    62
                });
            }
            k += 1;
        }
        if is_b || idx == form.len() - 1 {
            let mel = match mel_m {
                Option::Some(m) => m,
                Option::None => {
                    let seed = c.r.int(1000000000);
                    let mut mr = seeded(format!("PH|{}", seed));
                    let m = melody(ref c, chords, bars, 64, 79, F_SLOW, [].span(), true, ref mr)
                        .span();
                    mel_m = Option::Some(m);
                    m
                },
            };
            for n in mel {
                let n = *n;
                c.note(CH_LEAD, t0 + n.t, to_i(n.d) - 20, n.p, 88);
                if c.shiny {
                    c.note(CH_MEGA, t0 + n.t, to_i(n.d) - 20, n.p + 12, 60);
                }
            }
        }
        bass_line(ref c, CH_BASS, chords, t0, bars, B_PEDAL, 96);
        let mut b: u32 = 0;
        while b < bars {
            let v = voicing(ref c, chord_cell(chords, b, 0), 52, 66, Option::None, 3);
            c.notes_at(CH_PAD, t0 + b * bt, to_i(2 * bt) - 40, v.span(), 44);
            b += 2;
        }
        if c.g.drums != G_NONE && idx > 0 {
            drums(ref c, t0, bars, c.g.drums, false, false, true);
        }
        t0 += end;
        idx += 1;
    }
    t0
}

/// The parallel minor of a major-key chord (Var. II): I/IV minor, ii diminished, iii/vi/vii
/// flattened majors; dominants stay.
fn to_minor(ch: u8) -> u8 {
    let r = ch / 16;
    let q = ch % 16;
    if q == 4 || r == 7 {
        return ch;
    }
    let (nr, q0): (u8, u8) = if r == 0 {
        (0, 1)
    } else if r == 2 {
        (2, 2)
    } else if r == 4 {
        (3, 0)
    } else if r == 5 {
        (5, 1)
    } else if r == 9 {
        (8, 0)
    } else if r == 11 {
        (10, 0)
    } else {
        return ch;
    };
    let nq = if chord_tones(ch).len() > 3 && q0 != 2 {
        if q0 == 1 {
            5
        } else {
            6
        }
    } else {
        q0
    };
    nr * 16 + nq
}

fn write_variations(ref c: Ctx) -> u32 {
    let bt = c.bar;
    let bars: u32 = 8;
    let chords_maj = c.chords_for(c.prog_a, bars);
    let motif = motif_pitches(c.sp.degrees.slice(0, 8), c.tonic, scale_of(c.scale), 69).span();
    let seed = c.r.int(1000000000);
    let mut mr = seeded(format!("VAR|{}", seed));
    let theme = melody(ref c, chords_maj, bars, 64, 79, F_LYRIC, motif, true, ref mr).span();
    let mut minor_cells: Array<u8> = array![];
    for ch in chords_maj.cells {
        minor_cells.append(to_minor(*ch));
    }
    let chords_min = Chords { cells: minor_cells.span(), per: chords_maj.per, bars };
    let home = c.scale;
    let mut t0: u32 = 0;
    // Theme, Var. I (sixteenths), Var. II (minor), Var. III (march), Finale
    for s in 0..5_u32 {
        let chords = if s == 2 {
            chords_min
        } else {
            chords_maj
        };
        c.scale = if s == 2 {
            6
        } else {
            home
        };
        for n in theme {
            let n = *n;
            let chord = c.chord_at_tick(chords, n.t);
            let (pcs, _) = c.chord_scale(chord);
            let list = list_pitches(pcs, 55, 91).span();
            let p = nearest(list, n.p);
            if s == 1 && n.d >= TPQ {
                let seq = [p, step_in(list, p, 1), p, step_in(list, p, -1)].span();
                let mut k: u32 = 0;
                while k * 120 < n.d {
                    c
                        .note(
                            CH_LEAD,
                            t0 + n.t + k * 120,
                            110,
                            *seq.at(k % 4),
                            if k % 4 != 0 {
                                82
                            } else {
                                92
                            },
                        );
                    k += 1;
                }
            } else {
                let d = if s == 3 && n.d > EIGHTH {
                    EIGHTH
                } else {
                    n.d
                };
                c.note(CH_LEAD, t0 + n.t, to_i(d) - 20, p, 96);
                if s == 4 || c.shiny {
                    c.note(CH_MEGA, t0 + n.t, to_i(d) - 20, p + 12, 66);
                }
            }
        }
        let accomp = if s == 0 {
            A_BLOCK
        } else if s == 1 {
            A_ALBERTI
        } else if s == 3 {
            A_OOMPAH
        } else {
            A_ARP16
        };
        let bass = if s == 3 {
            B_ROOTFIFTH
        } else if s == 4 {
            B_OCTAVE8
        } else {
            B_ROOT
        };
        accompany(ref c, CH_ACCOMP, chords, t0, bars, accomp, 66);
        bass_line(ref c, CH_BASS, chords, t0, bars, bass, 96);
        if s == 3 {
            drums(ref c, t0, bars, G_MARCH, true, true, false);
        } else if s == 4 {
            drums(ref c, t0, bars, G_ROCK, true, true, false);
        }
        c.scale = home;
        t0 += bars * bt;
    }
    t0
}

const GALLOP: [u32; 6] = [0, 3, 6, 9, 12, 14];

fn riff_bar(ref c: Ctx, t: u32, chord: u8, light: bool, riff_rel: Span<i32>) {
    let root = c.root_in(chord_r(chord), 36);
    let mut a: u32 = 0; // the next gallop step
    for k in 0..16_u32 {
        if a < 6 && *GALLOP.span().at(a) == k {
            c.note(CH_BASS, t + k * 120, 110, root + *riff_rel.at(a % riff_rel.len()), 104);
            a += 1;
        } else if !light || k % 2 == 0 {
            c.note(CH_BASS, t + k * 120, 90, root, 64);
        }
    }
}

fn stabs(ref c: Ctx, t: u32, chord: u8) {
    let v = voicing(ref c, chord, 55, 69, Option::None, 3).span();
    for k in [0_u32, 3, 6, 14].span() {
        c.notes_at(CH_ACCOMP, t + *k * 120, 180, v, if *k != 0 {
            78
        } else {
            92
        });
    }
}

fn write_battle(ref c: Ctx) -> u32 {
    let bt = c.bar;
    let scale = scale_of(c.scale);
    let rel = motif_pitches(c.sp.degrees.slice(0, 6), 0, scale, 0).span();
    let mut riff_rel: Array<i32> = array![];
    for x in rel {
        riff_rel.append(max_i(-5, min_i(12, *x - *rel.at(0))));
    }
    let riff_rel = riff_rel.span();
    let chords_a = c.chords_for(c.prog_a, 8);
    let chords_b = c.chords_for(c.prog_b, 8);
    let mut t0: u32 = 0;
    // Intro: 4 bars of riff and drums
    for b in 0..4_u32 {
        riff_bar(ref c, t0 + b * bt, chord_cell(chords_a, b, 0), false, riff_rel);
    }
    drums(ref c, t0, 4, G_BATTLE, true, true, false);
    t0 += 4 * bt;
    // A
    let ta = t0;
    let before = c.notes.len();
    let motif = motif_pitches(c.sp.degrees.slice(0, 8), c.tonic, scale, 74).span();
    let seed = c.r.int(1000000000);
    let mut mr = seeded(format!("BOSS|{}", seed));
    let mel = melody(ref c, chords_a, 8, 67, 84, F_HEROIC, motif, true, ref mr).span();
    for m in mel {
        let m = *m;
        c.note(CH_LEAD, ta + m.t, to_i(m.d) - 20, m.p, 100);
        if c.shiny {
            c.note(CH_MEGA, ta + m.t, to_i(m.d) - 20, m.p + 12, 64);
        }
    }
    for b in 0..8_u32 {
        let chord = chord_cell(chords_a, b, 0);
        riff_bar(ref c, ta + b * bt, chord, false, riff_rel);
        stabs(ref c, ta + b * bt, chord);
    }
    let a_end = c.notes.len();
    drums(ref c, ta, 8, G_BATTLE, true, true, false);
    t0 += 8 * bt;
    // B: half time, the motif's head sequenced up a step every two bars
    let head = motif_pitches(c.sp.degrees.slice(0, 3), c.tonic, scale, 72).span();
    for b in 0..8_u32 {
        let t = t0 + b * bt;
        let chord = chord_cell(chords_b, b, 0);
        let (pcs, _) = c.chord_scale(chord);
        let list = list_pitches(pcs, 60, 88).span();
        let up = to_i(b / 2);
        let mut frag: Array<i32> = array![];
        for p in head {
            frag.append(step_in(list, nearest(list, *p), up));
        }
        let frag = frag.span();
        c.note(CH_LEAD, t, 450, *frag.at(0), 96);
        c.note(CH_LEAD, t + TPQ, 450, *frag.at(1), 96);
        c.note(CH_LEAD, t + 2 * TPQ, 930, *frag.at(2), 96);
        if c.shiny {
            let mut k: u32 = 0;
            for p in frag {
                c.note(CH_MEGA, t + k * TPQ, 450, *p + 12, 60);
                k += 1;
            }
        }
        riff_bar(ref c, t, chord, true, riff_rel);
    }
    accompany(ref c, CH_ACCOMP, chords_b, t0, 8, A_ARP16, 62);
    drums(ref c, t0, 8, G_HALFTIME, true, true, false);
    c.note(CH_PAD, t0 + 6 * bt, to_i(2 * bt) - 60, 72, 84);
    t0 += 8 * bt;
    // A': phase 2, everything a half step up, the lead doubled an octave above
    let mut i = before;
    while i < a_end {
        let x = *c.notes.at(i);
        let p: i32 = x.p.into();
        c.note(x.ch, x.t - ta + t0, to_i(x.d), p + 1, x.v.into());
        if x.ch == CH_LEAD {
            c.note(CH_COUNTER, x.t - ta + t0, to_i(x.d), p + 13, 70);
        }
        i += 1;
    }
    drums(ref c, t0, 8, if c.shiny {
        G_BATTLE16
    } else {
        G_BATTLE
    }, true, true, false);
    t0 += 8 * bt;
    // stinger: tonic hits, then the last one rings
    let tonic_chord: u8 = 1; // i (minor)
    for kd in [(0_u32, 3_i32), (6, 3), (12, 4), (16, 12)].span() {
        let (k, d) = *kd;
        let t = t0 + k * 120;
        let v = voicing(ref c, tonic_chord, 55, 69, Option::None, 3);
        for p in v.span() {
            c.note(CH_ACCOMP, t, d * 120, *p + 1, 100);
        }
        let rb = c.root_in(0, 36);
        let rl = c.root_in(0, 72);
        c.note(CH_BASS, t, d * 120, rb + 1, 110);
        c.note(CH_LEAD, t, d * 120, rl + 1, 104);
        c.note(CH_DRUMS, t, 60, 36, 120);
        c.note(CH_DRUMS, t, 300, 49, 110);
    }
    t0 + 2 * bt
}

/// The species motif's first five degrees as a 16th-note syncopated bass figure, twice a bar.
fn make_riff(ref c: Ctx) -> Span<(u32, i32, i32)> {
    let rel = motif_pitches(c.sp.degrees.slice(0, 5), 0, scale_of(c.scale), 0).span();
    let base = *rel.at(0);
    let slots = match c.r.int(4) {
        0 => [0_u32, 3, 6, 8, 11],
        1 => [0, 2, 3, 6, 10],
        2 => [0, 3, 4, 7, 10],
        _ => [0, 4, 6, 8, 12],
    }.span();
    let mut first: Array<(u32, i32, i32)> = array![];
    for i in 0..5_u32 {
        let s = *slots.at(i);
        let len = if i < 4 {
            *slots.at(i + 1) - s
        } else {
            4
        };
        first.append((s * 120, to_i(len * 120) - 20, max_i(-5, min_i(12, *rel.at(i) - base))));
    }
    let mut out: Array<(u32, i32, i32)> = array![];
    out.append_span(first.span());
    for x in first.span() {
        let (o, d, deg) = *x;
        out.append((o + 960, d, deg));
    }
    out.span()
}

// ── the track
// ───────────────────────────────────────────────────────────────────────────────────

fn make_ctx(sp: Species, shiny: bool, e: u32, g: Genome, seed: u64) -> Ctx {
    let mut r = seeded(format!("TRACK|{}|{}|seed:{}", e, sp.id, seed));
    let d = engine_def(g.engine);
    let scale = grammar_scale(g.grammar);
    let shift = r.pick_i32([0, 0, 0, 5, 7, -2, 2, 3].span());
    let tonic = to_i(md12(sp.tonic + shift));
    let bar = d.num * (1920 / d.den);
    let kind = sp.kind;
    let mut pal: Array<u8> = array![];
    for role in 0..5_u32 {
        pal.append(*g.palette.at(role * 3 + kind));
    }
    let leads = MEGA_LEADS.span();
    let pal = if shiny {
        let mut p: Array<u8> = array![*leads.at(sp.id % 2)];
        p.append_span(pal.span().slice(1, 4));
        p.append(*leads.at((sp.id + 1) % 2));
        p.span()
    } else {
        pal.append(0);
        pal.span()
    };
    let jitter = r.pick_i32([-4, -2, 0, 0, 2, 4].span());
    let bpm = to_u(to_i(g.bpm) + jitter);
    let progs = grammar_progs(g.grammar);
    let n = progs.len();
    let pa = r.int(n);
    let mut pb = r.int(n);
    if pb == pa {
        pb = (pa + 1) % n;
    }
    let strong2 = if d.den == 8 {
        720
    } else if d.num == 4 {
        960
    } else {
        0
    };
    Ctx {
        r,
        g,
        d,
        sp,
        shiny,
        scale,
        tonic,
        num: d.num,
        den: d.den,
        bar,
        six: bar / EIGHTH == 6,
        strong2,
        bpm,
        prog_a: *progs.at(pa),
        prog_b: *progs.at(pb),
        riff: [].span(),
        notes: array![],
        cs_cache: Default::default(),
        pal,
    }
}

fn to_u(x: i32) -> u32 {
    x.try_into().unwrap()
}

/// The notes, ticks, tempo and programs of edition `e`'s track for a species (1-75), shiny or not,
/// and a track seed (the source's key 'seed:<seed>').
pub fn edition_track(species_id: u32, shiny: bool, e: u32, seed: u64) -> (Span<Note>, u32, Ctx) {
    let g = edition_genome(e);
    let sp = species(species_id);
    let mut c = make_ctx(sp, shiny, e, g, seed);
    c.riff = make_riff(ref c);
    let ticks = if g.engine == E_CHORALE {
        write_chorale(ref c)
    } else if g.engine == E_PHASE {
        write_phase(ref c)
    } else if g.engine == E_VARIATIONS {
        write_variations(ref c)
    } else if g.engine == E_BATTLE {
        write_battle(ref c)
    } else {
        let bars = if g.engine == E_BLUES {
            12
        } else {
            8
        };
        let mut t0: u32 = 0;
        let mut mel_a: Option<Span<MelNote>> = Option::None;
        let mut mel_b: Option<Span<MelNote>> = Option::None;
        let mut idx: u32 = 0;
        for kind in g.form {
            write_section(ref c, *kind, bars, t0, idx, ref mel_a, ref mel_b);
            t0 += bars * c.bar;
            idx += 1;
        }
        t0
    };
    let notes = c.notes.span();
    (notes, ticks, c)
}

/// Edition `e`'s track as a self-contained format-0 Standard MIDI File (the source's
/// `editionMidi(...).midi`).
pub fn edition_smf_bytes(species_id: u32, shiny: bool, e: u32, seed: u64) -> Array<u8> {
    let (notes, ticks, c) = edition_track(species_id, shiny, e, seed);
    to_smf(notes, ticks, @c)
}

// ── SMF
// ─────────────────────────────────────────────────────────────────────────────────────────

const VOL: [u8; 7] = [100, 78, 74, 100, 58, 74, 62];
const PAN: [u8; 7] = [64, 46, 82, 64, 64, 40, 88];
const IDX: u64 = 0x10000;

/// A format-0 file: tempo, meter, programs with volume/pan/reverb, the notes (a note cut where
/// the next one of its channel and pitch starts), End of Track at `ticks`.
fn to_smf(notes: Span<Note>, ticks: u32, c: @Ctx) -> Array<u8> {
    // the notes before the end, stably by start
    let mut keys: Array<u64> = array![];
    let mut i: u32 = 0;
    for n in notes {
        if n.t < ticks {
            keys.append(n.t.into() * IDX + i.into());
        }
        i += 1;
    }
    let order = sort_u64(keys.span());
    let m = order.len();
    // ends: a note sounding when the next one of the same key starts is cut just before it
    let mut next_start: Felt252Dict<u32> = Default::default();
    let mut ends_rev: Array<u32> = array![];
    let mut j = m;
    while j > 0 {
        j -= 1;
        let n = *notes.at(((*order.at(j)) % IDX).try_into().unwrap());
        let key: felt252 = (n.ch.into() * 128 + n.p.into());
        let ns = next_start.get(key);
        let mut d = n.d;
        if ns != 0 && n.t + n.d > ns - 1 {
            let gap = ns - 1 - n.t; // >= 0: sorted by start
            d = if gap < 21 {
                20
            } else {
                gap - 1
            };
        }
        next_start.insert(key, n.t + 1);
        let end = if n.t + d < ticks {
            n.t + d
        } else {
            ticks
        };
        ends_rev.append(end);
    }
    let mut off_keys: Array<u64> = array![];
    let mut j: u32 = 0;
    while j < m {
        off_keys.append((*ends_rev.at(m - 1 - j)).into() * IDX + j.into());
        j += 1;
    }
    let offs = sort_u64(off_keys.span());

    let mut tr = TrackWriterTrait::new();
    let us = (120000000 + c.bpm) / (2 * c.bpm);
    tr.tempo(0, us);
    let den_log: u8 = if c.den == 8 {
        3
    } else {
        2
    };
    tr.meta(0, 0x58, [(c.num).try_into().unwrap(), den_log, 24, 8].span());
    let channels: u8 = if c.shiny {
        7
    } else {
        6
    };
    for ch in 0..channels {
        let prog = if ch == CH_TENOR {
            *c.pal.at(2)
        } else if ch == CH_MEGA {
            *c.pal.at(5)
        } else {
            *c.pal.at(ch.into())
        };
        tr.program(0, ch, prog);
        tr.control(0, ch, 7, *VOL.span().at(ch.into()));
        tr.control(0, ch, 10, *PAN.span().at(ch.into()));
        tr.control(0, ch, 91, 40);
    }
    tr.control(0, 9, 7, 96);
    // merge: at the same tick note offs come before note ons
    let (mut a, mut b) = (0_u32, 0_u32);
    while a < m || b < m {
        let take_off = if b >= m {
            false
        } else if a >= m {
            true
        } else {
            *offs.at(b) / IDX <= *order.at(a) / IDX
        };
        if take_off {
            let pos: u32 = (*offs.at(b) % IDX).try_into().unwrap();
            let n = *notes.at((*order.at(pos) % IDX).try_into().unwrap());
            tr.message((*offs.at(b) / IDX).try_into().unwrap(), 0x80 + n.ch, n.p, 0);
            b += 1;
        } else {
            let n = *notes.at((*order.at(a) % IDX).try_into().unwrap());
            tr.message(n.t, 0x90 + n.ch, n.p, n.v);
            a += 1;
        }
    }
    let body = tr.finish_at(ticks);
    smf_bytes(0, 480, array![body].span())
}

/// Ascending sort of distinct keys: the ascending runs merged pairwise.
fn sort_u64(xs: Span<u64>) -> Span<u64> {
    let n = xs.len();
    if n == 0 {
        return xs;
    }
    let mut runs: Array<Span<u64>> = array![];
    let mut start: u32 = 0;
    let mut i: u32 = 1;
    while i < n {
        if *xs.at(i) < *xs.at(i - 1) {
            runs.append(xs.slice(start, i - start));
            start = i;
        }
        i += 1;
    }
    runs.append(xs.slice(start, n - start));
    while runs.len() > 1 {
        let mut next: Array<Span<u64>> = array![];
        let rs = runs.span();
        let mut k: u32 = 0;
        while k + 1 < rs.len() {
            next.append(merge(*rs.at(k), *rs.at(k + 1)));
            k += 2;
        }
        if k < rs.len() {
            next.append(*rs.at(k));
        }
        runs = next;
    }
    let sorted = *runs.at(0);
    sorted
}

fn merge(mut a: Span<u64>, mut b: Span<u64>) -> Span<u64> {
    let mut out: Array<u64> = array![];
    loop {
        match (a.get(0), b.get(0)) {
            (Option::Some(x), Option::Some(y)) => {
                let (x, y) = (*x.unbox(), *y.unbox());
                if x < y {
                    out.append(x);
                    a = a.slice(1, a.len() - 1);
                } else {
                    out.append(y);
                    b = b.slice(1, b.len() - 1);
                }
            },
            _ => { break; },
        }
    }
    out.append_span(a);
    out.append_span(b);
    out.span()
}

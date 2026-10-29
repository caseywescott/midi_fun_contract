//! Monthly Track Editions: the Cairo port of offchain/beast-sound/src/editions_lite.js
//! (`editionMidi`), byte for byte. Four styles (waltz, chorale, lullaby, dirge) in one
//! data-driven engine small enough to sit beside the Genesis Track in BeastMidiProvider: diatonic
//! triads on scale degrees, pattern tables for the accompaniment and bass (editions_data.cairo,
//! generated from the source), and one track per channel written in time order, so nothing is
//! sorted. No drums or counter line, and root-position chords: that is what fits. Edition 0 is
//! the seeded canon, not this engine.
//!
//! Scale degrees are unsigned here, offset by `O` (70): the source's degree d is d + 70, so 70 is
//! the tonic, 77 the tonic an octave up and 67 the dominant below (CASM size: no signed overflow
//! paths).

use core::num::traits::{WrappingAdd, WrappingMul};
use midi::smf::{TrackWriter, TrackWriterTrait, smf_byte_array, smf_bytes};
use crate::composition::drift::{Drift, nudge_tempo};
use crate::inputs::MAX_TEMPO_US;
use super::editions_data::{SCALES, SPECIES, Style, style};

const SEVEN: NonZero<u32> = 7;
const TWO32: u64 = 0x100000000;
/// The degree offset: degree d of the source is d + O here.
const O: u32 = 70;
const MEGA_LEADS: [u8; 2] = [50, 65];
const VOL: [u8; 6] = [100, 78, 74, 100, 58, 62];
const PAN: [u8; 6] = [64, 46, 82, 64, 64, 88];
/// To the nearest chord tone, by degrees above the chord's root: the source's SNAP + 1.
const SNAP1: [u32; 7] = [1, 0, 1, 0, 1, 0, 2];

/// mulberry32, as the source's `rng`.
#[derive(Copy, Drop)]
pub struct Rng {
    a: u32,
}

#[generate_trait]
pub impl RngImpl of RngTrait {
    #[inline(never)]
    fn next(ref self: Rng) -> u32 {
        self.a = self.a.wrapping_add(0x6d2b79f5);
        let t = self.a;
        let t = (t ^ (t / 0x8000)).wrapping_mul(t | 1);
        let t = t ^ t.wrapping_add((t ^ (t / 0x80)).wrapping_mul(t | 61));
        t ^ (t / 0x4000)
    }

    /// floor(R() * n / 2^32): 0..n.
    #[inline(never)]
    fn int(ref self: Rng, n: u32) -> u32 {
        let x: u64 = self.next().into();
        ((x * n.into()) / TWO32).try_into().unwrap()
    }
}

#[inline(never)]
fn m7(d: u32) -> u32 {
    let (_, r) = DivRem::div_rem(d, SEVEN);
    r
}

/// The pitch of degree `d` (offset) over `base` (the tonic).
#[inline(never)]
fn pitch(base: u32, scale: Span<u32>, d: u32) -> u8 {
    let (o, i) = DivRem::div_rem(d, SEVEN);
    let p: felt252 = base.into() + 12 * o.into() + (*scale.at(i)).into() - 120;
    p.try_into().unwrap()
}

/// `d` moved to the nearest tone of the triad on `c` (0..6).
#[inline(never)]
fn snap(d: u32, c: u32) -> u32 {
    d + *SNAP1.span().at(m7(d + 7 - c)) - 1
}

/// The root of the triad on `c` (0..6) in root position, placed in [lo, lo + 6].
fn triad_root(c: u32, lo: u32) -> u32 {
    lo + m7(c + O + 7 - lo)
}

/// One channel message (out of line: one copy of the writer's code, not one per call).
#[inline(never)]
fn msg(ref tw: TrackWriter, t: u32, status: u8, a: u8, b: u8) {
    tw.message(t, status, a, b);
}

/// Notes sounding together: every note on at `t`, then every note off at `t + d`.
#[inline(never)]
fn block(ref tw: TrackWriter, ch: u8, t: u32, d: u32, ps: Span<u8>, v: u8) {
    for p in ps {
        msg(ref tw, t, 0x90 + ch, *p, v);
    }
    for p in ps {
        msg(ref tw, t + d, 0x80 + ch, *p, 0);
    }
}

/// A channel's track, opened with its program, volume, pan and reverb.
#[inline(never)]
fn channel_track(ch: u8, program: u8) -> TrackWriter {
    let role: u32 = ch.into();
    let mut tw = TrackWriterTrait::new();
    tw.program(0, ch, program);
    msg(ref tw, 0, 0xB0 + ch, 7, *VOL.span().at(role));
    msg(ref tw, 0, 0xB0 + ch, 10, *PAN.span().at(role));
    msg(ref tw, 0, 0xB0 + ch, 91, 40);
    tw
}

/// The track body, closed with End of Track at `ticks`.
#[inline(never)]
fn finish(tw: TrackWriter, ticks: u32) -> Array<u8> {
    tw.finish_at(ticks)
}

#[derive(Copy, Drop)]
struct MelNote {
    t: u32,
    len: u32,
    d: u32,
}

#[inline(never)]
fn is_strong(t: u32, bar: u32, strong2: u32) -> bool {
    let pos = t % bar;
    pos == 0 || (strong2 > 0 && pos == strong2)
}

/// What a melody bar reads, boxed.
#[derive(Copy, Drop)]
struct Mel {
    bar: u32,
    strong2: u32,
    lo: u32,
    motif: Span<u32>,
}

/// One bar of the melody from its rhythm `cell` (eighths, 4 bits each): the motif while it lasts,
/// then steps toward the contour; strong beats and long notes on chord tones; `end` closes the bar
/// on the tonic (1) or the dominant (2).
#[inline(never)]
fn melody_bar(
    m: Box<Mel>,
    ref out: Array<MelNote>,
    ref prev: u32,
    ref mi: u32,
    ref r: Rng,
    cell: u32,
    t0: u32,
    ch: u32,
    target: u32,
    end: u32,
) {
    let m = m.unbox();
    let (lo, motif) = (m.lo, m.motif);
    let hi = lo + 10;
    let mut cell = cell;
    let mut t = t0;
    while cell != 0 {
        let len = (cell % 16) * 240;
        cell /= 16;
        let mut d = if mi < motif.len() {
            // the theme's degrees reach at most an octave below the range
            let d = *motif.at(mi);
            mi += 1;
            if d < lo {
                d + 7
            } else {
                d
            }
        } else {
            // toward the contour (a coin when on it): 0, 1 or 2 steps that way, or 1 back
            let up = if prev + 1 < target {
                true
            } else if prev > target + 1 {
                false
            } else {
                r.int(2) == 1
            };
            let x = r.int(100);
            let (amt, fwd) = if x < 12 {
                (0, true)
            } else if x < 66 {
                (1, true)
            } else if x < 90 {
                (2, true)
            } else {
                (1, false)
            };
            let d = if up == fwd {
                prev + amt
            } else {
                prev - amt
            };
            if d > hi {
                hi
            } else if d < lo {
                lo
            } else {
                d
            }
        };
        if is_strong(t, m.bar, m.strong2) || len >= 720 {
            d = snap(d, ch);
        }
        if cell == 0 && end == 1 {
            d = if prev >= O + 4 {
                O + 7
            } else {
                O
            };
        } else if cell == 0 && end == 2 {
            d = if prev >= O + 1 {
                O + 4
            } else {
                O - 3
            };
        }
        out.append(MelNote { t, len, d });
        prev = d;
        t += len;
    }
}

/// One section's melody (offset degrees) over its eight chords: two-bar ideas, the first opening
/// with the motif when given, an antecedent ending on the dominant and a consequent restating its
/// first two bars, closing on the tonic (`full`) or the dominant.
#[inline(never)]
fn melody(
    cells: Span<u32>, end: Span<u32>, m: Box<Mel>, chords: Span<u32>, full: bool, ref r: Rng,
) -> Span<MelNote> {
    let (bar, strong2, lo) = (m.unbox().bar, m.unbox().strong2, m.unbox().lo);
    // the bars' rhythms: the two-bar idea, a cell and a phrase end, twice
    let idea0 = *cells.at(r.int(cells.len()));
    let idea1 = *cells.at(r.int(cells.len()));
    let c2 = *cells.at(r.int(cells.len()));
    let e3 = *end.at(r.int(end.len()));
    let c6 = *cells.at(r.int(cells.len()));
    let e7 = *end.at(r.int(end.len()));
    let mut out: Array<MelNote> = array![];
    let mut prev = lo + 3;
    let mut mi: u32 = 0;
    let at = |b: u32| -> u32 {
        *chords.at(b)
    };
    melody_bar(m, ref out, ref prev, ref mi, ref r, idea0, 0, at(0), lo + 3, 0);
    melody_bar(m, ref out, ref prev, ref mi, ref r, idea1, bar, at(1), lo + 5, 0);
    let first_two = out.len();
    melody_bar(m, ref out, ref prev, ref mi, ref r, c2, 2 * bar, at(2), lo + 6, 0);
    melody_bar(m, ref out, ref prev, ref mi, ref r, e3, 3 * bar, at(3), lo + 5, 2);
    // the consequent restates the antecedent's first two bars
    for n in out.span().slice(0, first_two) {
        let t = n.t + 4 * bar;
        let d = if is_strong(t, bar, strong2) {
            snap(n.d, at(t / bar))
        } else {
            n.d
        };
        out.append(MelNote { t, len: n.len, d });
        prev = d;
    }
    melody_bar(m, ref out, ref prev, ref mi, ref r, c6, 6 * bar, at(6), lo + 6, 0);
    let last = if full {
        1
    } else {
        2
    };
    melody_bar(m, ref out, ref prev, ref mi, ref r, e7, 7 * bar, at(7), lo + 5, last);
    out.span()
}

/// Edition `e`'s style (index and tables), mode, tempo and form (e >= 1).
#[inline(never)]
pub fn edition_genome(e: u32) -> (u32, Box<Style>, u32, u32, u32) {
    assert(e >= 1, 'editions: 0 is the canon');
    let st = (e - 1) % 4;
    let sb = style(st);
    let s = sb.unbox();
    // each pass of the four styles takes the next mode, a tempo stepping by 7 BPM and the other
    // form
    let pass = (e - 1) / 4;
    let mode = *s.modes.at(pass % s.modes.len());
    let bpm = s.bpm_lo + (pass * 7 + st * 3) % (s.bpm_hi - s.bpm_lo + 1);
    let form = pass % 2;
    (st, sb, mode, bpm, form)
}

fn is_b_section(form: u32, sec: u32) -> bool {
    if form == 0 {
        sec == 2
    } else {
        sec % 2 == 1
    }
}

/// The chords of the form's 32 bars, in order.
#[inline(never)]
fn form_chords(progs: Span<u32>, chord_bars: u32, form: u32, pa: u32, pb: u32) -> Span<u32> {
    let mut out: Array<u32> = array![];
    for b in 0..32_u32 {
        let prog = *progs.at(if is_b_section(form, b / 8) {
            pb
        } else {
            pa
        });
        out.append((prog / *[1_u32, 16, 256, 4096].span().at((b % 8 / chord_bars) % 4)) % 16);
    }
    out.span()
}

/// What the channel writers read, boxed (one felt) rather than copied into every call.
#[derive(Copy, Drop)]
struct Ctx {
    s: Box<Style>,
    scale: Span<u32>,
    base: u32,
    bar: u32,
    tier: u32,
    kind: u32,
    shiny: bool,
    species: u32,
    /// the accompaniment's triads in root position (0) or first or second inversion (the week's
    /// drift)
    rot: u32,
    /// the 32 bars' chords, and the lead's notes over the whole form
    chords: Span<u32>,
    lead: Span<MelNote>,
    ticks: u32,
}

/// The lead (channel 0), or its mega double an octave up (channel 5).
#[inline(never)]
fn lead_track(k: Box<Ctx>, mega: bool) -> Array<u8> {
    let c = k.unbox();
    let leads = MEGA_LEADS.span();
    let (ch, program, up): (u8, u8, u8) = if mega {
        (5, *leads.at((c.species + 1) % 2), 12)
    } else if c.shiny {
        (0, *leads.at(c.species % 2), 0)
    } else {
        (0, *c.s.unbox().palette.at(c.kind), 0)
    };
    let (base, scale, bar) = (c.base, c.scale, c.bar);
    let mut tw = channel_track(ch, program);
    for n in c.lead {
        let vel: u8 = if mega {
            70
        } else if n.t % bar != 0 {
            90
        } else {
            100
        };
        block(ref tw, ch, n.t, n.len - 20, [pitch(base, scale, n.d) + up].span(), vel);
    }
    finish(tw, c.ticks)
}

/// The parts that follow the chords, bar by bar: the accompaniment (channel 2: the style's
/// pattern on the triad), the bass (channel 3: its pattern on the root, two octaves below the
/// tonic) and the pad (channel 4: a held triad every two bars, tiers 1 and 2).
#[inline(never)]
fn chord_track(k: Box<Ctx>, ch: u8) -> Array<u8> {
    let c = k.unbox();
    let s = c.s.unbox();
    let role: u32 = ch.into();
    let mut tw = channel_track(ch, *s.palette.at(role * 3 + c.kind));
    if ch == 4 && c.tier > 2 {
        return finish(tw, c.ticks);
    }
    let (pattern, low, vel0) = if ch == 3 {
        (s.bass, c.base - 24, 64)
    } else {
        (s.accomp, c.base, 40)
    };
    let (scale, bar) = (c.scale, c.bar);
    let mut t: u32 = 0;
    for chord in c.chords {
        let chord = *chord;
        if ch == 4 {
            if (t / bar) % 2 == 0 {
                let r = triad_root(chord, O - 7);
                let ps = [pitch(low, scale, r), pitch(low, scale, r + 2), pitch(low, scale, r + 4)];
                block(ref tw, 4, t, 2 * bar - 40, ps.span(), 46);
            }
        } else {
            let r = triad_root(chord, O - 3);
            // the triad in root position, or with the week's drift in its first or second inversion
            // (the lower tones an octave up)
            let (rot, deg) = (c.rot, [0_u32, 2, 4, 7, 9]);
            let p0 = pitch(low, scale, r + *deg.span().at(rot));
            let (p1, p2) = (
                pitch(low, scale, r + *deg.span().at(rot + 1)),
                pitch(low, scale, r + *deg.span().at(rot + 2)),
            );
            for x in pattern {
                let x = *x;
                let voice = (x / 0x400000) % 16;
                let ps = if ch == 3 {
                    if voice == 4 {
                        [pitch(low, scale, O), pitch(low, scale, O + 4)].span()
                    } else if voice == 1 {
                        [pitch(low, scale, chord + O - 3)].span()
                    } else {
                        [pitch(low, scale, chord + O)].span()
                    }
                } else if voice == 9 {
                    [p0, p1, p2].span()
                } else if voice == 10 {
                    [p0, p0 + 12].span()
                } else if voice == 3 {
                    [p0 + 12].span()
                } else if voice == 0 {
                    [p0].span()
                } else if voice == 1 {
                    [p1].span()
                } else {
                    [p2].span()
                };
                let vel: u8 = (vel0 + x / 0x4000000).try_into().unwrap();
                block(ref tw, ch, t + x % 0x800, (x / 0x800) % 0x800, ps, vel);
            }
        }
        t += bar;
    }
    finish(tw, c.ticks)
}

/// The track bodies of edition `e`'s track for a species (1-75), shiny or not, and a track seed:
/// the tempo track, then lead, accompaniment, bass, pad and the mega double when shiny.
pub fn edition_tracks(species: u32, shiny: bool, e: u32, seed: u64) -> Array<Array<u8>> {
    edition_tracks_on(species, shiny, e, seed, Option::None)
}

/// The same on a day of drift (`drift.cairo` `layered_drift`, the song layers in the style
/// engine's terms): the month's new melodies (their rhythm cells and contour drawn from the
/// month's hash; same key, chords and tempo), the week's accompaniment voicing (its triads in
/// their first or second inversion) and the day's knob (0 the A and B progressions swap, 1 the A
/// and B tunes swap, 2-5 the tempo nudged -4, -2, +2, +4 BPM). No drift (`None`) is the track as
/// written.
#[inline(never)]
pub fn edition_tracks_on(
    species: u32, shiny: bool, e: u32, seed: u64, drift: Option<Drift>,
) -> Array<Array<u8>> {
    let (rhythm, rotate, knob, delta) = match drift {
        Option::Some(d) => (d.rhythm, d.rotate, d.day_knob, d.delta_bpm),
        Option::None => (Option::None, Option::None, 6, 0),
    };
    assert(species >= 1 && species <= 75, 'editions: species');
    let (_, sb, mode, bpm0, form) = edition_genome(e);
    let s = sb.unbox();
    let scale = (*SCALES.span().at(mode)).span();
    // the Beast: tier, type, tonic and the opening of its Genesis theme (degree + 8, 4 bits each)
    let k = species - 1;
    let mut v: u32 = *SPECIES.span().at(k);
    let tonic0 = v % 16;
    let mut motif: Array<u32> = array![];
    for _ in 0..6_u32 {
        v /= 16;
        motif.append(v % 16 + O - 8);
    }
    // the track's draws: transposition, tempo nudge, the A and B progressions, the melodies
    let lo32: u32 = (seed % TWO32).try_into().unwrap();
    let hi32: u32 = (seed / TWO32).try_into().unwrap();
    let mut r = Rng {
        a: lo32 ^ hi32 ^ e.wrapping_mul(0x9e3779b1) ^ species.wrapping_mul(0x85ebca77),
    };
    let tonic = (tonic0 + *[0_u32, 0, 0, 5, 7, 10, 2, 3].span().at(r.int(8))) % 12;
    let bpm = bpm0 + *[0_u32, 2, 4, 4, 6, 8].span().at(r.int(6)) - 4;
    let mut pa = r.int(4);
    let mut pb = r.int(4);
    if pb == pa {
        pb = (pa + 1) % 4;
    }
    if knob == 0 {
        let a = pa;
        pa = pb;
        pb = a;
    }
    let bar = s.num * (1920 / s.den);
    let strong2 = if s.den == 8 {
        720
    } else if s.num == 4 {
        960
    } else {
        0
    };
    let chords = form_chords(s.progs, s.chord_bars, form, pa, pb);
    // A's chords are the first section's, B's the first B section's (the third or the second)
    let b0 = if form == 0 {
        16
    } else {
        8
    };
    let ma = BoxTrait::new(Mel { bar, strong2, lo: O - 1, motif: motif.span() });
    let mb = BoxTrait::new(Mel { bar, strong2, lo: O + 1, motif: [].span() });
    // the month's drift draws the melodies from its own hash, the rest of the track unchanged
    let mut mr = match rhythm {
        Option::Some(h) => Rng { a: low32(h) },
        Option::None => r,
    };
    let mel_a = melody(s.cells, s.end, ma, chords.slice(0, 8), true, ref mr);
    let mel_b = melody(s.cells, s.end, mb, chords.slice(b0, 8), false, ref mr);
    let (mel_a, mel_b) = if knob == 1 {
        (mel_b, mel_a)
    } else {
        (mel_a, mel_b)
    };
    let mut lead: Array<MelNote> = array![];
    for sec in 0..4_u32 {
        let t0 = sec * 8 * bar;
        let mel = if is_b_section(form, sec) {
            mel_b
        } else {
            mel_a
        };
        for n in mel {
            lead.append(MelNote { t: t0 + n.t, len: n.len, d: n.d });
        }
    }
    let ticks = 32 * bar;
    let base = if tonic < 6 {
        60 + tonic
    } else {
        48 + tonic
    };
    let ctx = BoxTrait::new(
        Ctx {
            s: sb,
            scale,
            base,
            bar,
            tier: (k % 25) / 5 + 1,
            rot: match rotate {
                Option::Some(h) => 1 + low32(h) % 2,
                Option::None => 0,
            },
            kind: k / 25,
            shiny,
            species,
            chords,
            lead: lead.span(),
            ticks,
        },
    );
    let mut tempo = TrackWriterTrait::new();
    let tempo_us = (120000000 + bpm) / (2 * bpm);
    tempo
        .tempo(
            0,
            if knob >= 2 && knob <= 5 {
                let t = nudge_tempo(tempo_us, delta);
                if t > MAX_TEMPO_US {
                    MAX_TEMPO_US
                } else {
                    t
                }
            } else {
                tempo_us
            },
        );
    let den_log: u8 = if s.den == 8 {
        3
    } else {
        2
    };
    tempo.meta(0, 0x58, [s.num.try_into().unwrap(), den_log, 24, 8].span());
    let mut tracks: Array<Array<u8>> = array![
        finish(tempo, ticks), lead_track(ctx, false), chord_track(ctx, 2), chord_track(ctx, 3),
        chord_track(ctx, 4),
    ];
    if shiny {
        tracks.append(lead_track(ctx, true));
    }
    tracks
}

/// Edition `e`'s track as a Standard MIDI File (format 1, 480 ticks per quarter note).
pub fn edition_smf_bytes(species: u32, shiny: bool, e: u32, seed: u64) -> Array<u8> {
    smf_bytes(1, 480, edition_tracks(species, shiny, e, seed).span())
}

/// The same as a `ByteArray`, packed from the track bodies without copying them into one array, on
/// a day of drift when `drift` is `Some`.
pub fn edition_byte_array(
    species: u32, shiny: bool, e: u32, seed: u64, drift: Option<Drift>,
) -> ByteArray {
    smf_byte_array(1, 480, edition_tracks_on(species, shiny, e, seed, drift).span())
}

/// The low 32 bits of a hash.
fn low32(x: felt252) -> u32 {
    let w: u256 = x.into();
    (w % 0x100000000).try_into().unwrap()
}

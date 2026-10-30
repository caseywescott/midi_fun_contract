//! Monthly Track Editions: the Cairo port of offchain/beast-sound/src/editions_lite.js
//! (`editionMidi`), byte for byte. Nine styles (waltz, chorale, lullaby, dirge, boss battle, sea
//! shanty, march, dungeon crawl, tango) in one data-driven engine small enough to sit beside the
//! Genesis Track in BeastMidiProvider: diatonic triads on scale degrees, pattern tables for the
//! accompaniment and bass (editions_data.cairo, generated from the source), and one track per
//! channel written in time order, so nothing is sorted. The edition sets the style and tempo; each
//! purchase rolls its key, mode, form, chords, figures and parts (descant, bass, pad, chip
//! percussion). Edition 0 is the seeded canon, not this engine.
//!
//! Scale degrees are unsigned here, offset by `O` (70): the source's degree d is d + 70, so 70 is
//! the tonic, 77 the tonic an octave up and 67 the dominant below (CASM size: no signed overflow
//! paths).

use core::num::traits::{WrappingAdd, WrappingMul};
use midi::smf::{TrackWriter, TrackWriterTrait, smf_byte_array, smf_bytes};
use crate::composition::drift::{Drift, nudge_tempo};
use crate::inputs::MAX_TEMPO_US;
use crate::opaque::opaque;
use super::editions_data::{SCALES, SPECIES, STYLE_COUNT, Style, style};

const SEVEN: NonZero<u32> = 7;
const TWO32: u64 = 0x100000000;
/// The degree offset: degree d of the source is d + O here.
const O: u32 = 70;
const MEGA_LEADS: [u8; 2] = [50, 65];
/// The styles the mix singles out (editions_data.cairo order).
const STYLE_DIRGE: u32 = 3;
const STYLE_OVERWORLD: u32 = 18;
const VOL: [u8; 10] = [100, 64, 74, 100, 58, 62, 70, 0, 0, 70];
const PAN: [u8; 10] = [64, 46, 82, 64, 64, 88, 100, 0, 0, 64];
/// The forms' sections, 2 bits each: AABA, ABAB, AABB, ABAC, AA'BA, ABA'B, AA'BA', ABA'C (tunes A
/// 0, B 1, C 2, A' 3: forms 4-7 carry an A', 3 and 7 a C).
const FORMS: [u32; 8] = [16, 68, 80, 132, 28, 116, 220, 180];
/// The parts beside the lead and accompaniment: descant, bass, pad, percussion (bits 0-3).
const DESCANT: u32 = 1;
const BASS: u32 = 2;
const PAD: u32 = 4;
const PERC: u32 = 8;
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

/// A channel's volume (CC 7) as a mix level (editions_lite.js volOf): TinySynth's gain is volume
/// squared, so 70% loudness is x0.837 and 115% x1.072 (per mille): the Dirge's bass and the
/// Overworld's accompaniment at 70%; on the lead and descant the Noise Channel Lead (72) at 52.5%
/// and the VRC6 Saw Lead (62) at 90%; the PCE Wavetable Pluck (99) at 70% as the accompaniment,
/// the Triangle Pad (33) at 115% as the pad.
fn vol_of(st: u32, ch: u8, program: u8) -> u8 {
    let k: u32 = if (st == STYLE_DIRGE && ch == 3) || (st == STYLE_OVERWORLD && ch == 2) {
        837
    } else if (ch == 0 || ch == 1) && program == 72 {
        725
    } else if (ch == 0 || ch == 1) && program == 62 {
        949
    } else if ch == 2 && program == 99 {
        837
    } else if ch == 4 && program == 33 {
        1072
    } else {
        1000
    };
    let v: u32 = (*VOL.span().at(ch.into())).into();
    ((v * k + 500) / 1000).try_into().unwrap()
}

/// A channel's track, opened with its program, volume (`vol_of` style `st`), pan and reverb.
#[inline(never)]
fn channel_track(ch: u8, program: u8, st: u32) -> TrackWriter {
    let role: u32 = ch.into();
    let mut tw = TrackWriterTrait::new();
    tw.program(0, ch, program);
    msg(ref tw, 0, 0xB0 + ch, 7, vol_of(st, ch, program));
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

/// Edition `e`'s style (index and tables) and tempo (e >= 1): the styles in turn, each pass
/// through them a tempo stepping by 7 BPM.
#[inline(never)]
pub fn edition_genome(e: u32) -> (u32, Box<Style>, u32) {
    assert(e >= 1, 'editions: 0 is the canon');
    let st = (e - 1) % STYLE_COUNT;
    let sb = style(st);
    let s = sb.unbox();
    let pass = (e - 1) / STYLE_COUNT;
    let bpm = s.bpm_lo + (pass * 7 + st * 3) % (s.bpm_hi - s.bpm_lo + 1);
    (st, sb, bpm)
}

/// The tune (0 A, 1 B, 2 C) of section `sec` of form `form`.
fn kind_of(form: u32, sec: u32) -> u32 {
    (form / *[1_u32, 4, 16, 64].span().at(sec)) % 4
}

/// The eight chords of a section on progression `p`.
#[inline(never)]
fn section_chords(progs: Span<u32>, chord_bars: u32, p: u32) -> Span<u32> {
    let prog = *progs.at(p);
    let mut out: Array<u32> = array![];
    for b in 0..8_u32 {
        out.append((prog / *[1_u32, 16, 256, 4096].span().at((b / chord_bars) % 4)) % 16);
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
    kind: u32,
    shiny: bool,
    species: u32,
    /// the accompaniment's triads in root position (0) or first or second inversion (the week's
    /// drift)
    rot: u32,
    /// the purchase's accompaniment, bass and percussion figures
    accomp: Span<u32>,
    bass: Span<u32>,
    perc: Span<u32>,
    /// grace notes: the share of long notes (percent) and the seed placing them; detached phrasing
    orn: u32,
    orn_seed: u32,
    /// the ornament's kind (upper or lower grace, slide, mordent) and the bass's rhythm (as
    /// written, doubled, detached)
    orn_kind: u32,
    /// the style (index), an FM Brass lead's alternative, the pluck accompaniment an octave down
    st: u32,
    lead_alt: bool,
    acc_down: bool,
    bass_mode: u32,
    detached: bool,
    /// the 32 bars' chords, and the lead's notes over the whole form
    chords: Span<u32>,
    lead: Span<MelNote>,
    ticks: u32,
}

/// The lead (channel 0), its mega double an octave up (channel 5, `role` 1), the descant a third
/// above its long notes (channel 1, `role` 2, the lead's preset) or the chip echo (channel 6,
/// `role` 3: the lead 360 ticks later at half velocity on the accompaniment's preset).
#[inline(never)]
fn lead_track(k: Box<Ctx>, role: u32) -> Array<u8> {
    let c = k.unbox();
    let leads = MEGA_LEADS.span();
    let lead_program = if c.shiny {
        *leads.at(c.species % 2)
    } else if c.lead_alt {
        // an FM Brass lead's alternative, the palette's second row
        *c.s.unbox().palette.at(3 + c.kind)
    } else {
        *c.s.unbox().palette.at(c.kind)
    };
    let (ch, program, up): (u8, u8, u8) = if role == 1 {
        (5, *leads.at((c.species + 1) % 2), 12)
    } else if role == 3 {
        (6, *c.s.unbox().palette.at(6 + c.kind), 0)
    } else if role == 2 {
        (1, lead_program, 0)
    } else {
        (0, lead_program, 0)
    };
    let (base, scale, bar) = (c.base, c.scale, c.bar);
    let mut tw = channel_track(ch, program, c.st);
    for n in c.lead {
        let n = *n;
        let len = n.len - if c.detached && n.len <= 240 {
            n.len / 2
        } else {
            20
        };
        if role == 2 {
            if n.len >= 480 {
                block(ref tw, 1, n.t, len, [pitch(base, scale, n.d + 2)].span(), 64);
            }
            continue;
        }
        let vel: u8 = if role == 1 {
            70
        } else if n.t % bar != 0 {
            90
        } else {
            100
        };
        if role == 3 {
            let t = n.t + 360;
            if t < c.ticks {
                let d = if len + t > c.ticks {
                    c.ticks - t
                } else {
                    len
                };
                block(ref tw, 6, t, d, [pitch(base, scale, n.d)].span(), vel / 2);
            }
            continue;
        }
        // an ornament on some long notes, its kind from the ornament seed: an upper or lower grace
        // note, a slide from a third below, or a mordent (the note, a step above, the note)
        let kind = c.orn_kind;
        if c.orn > 0 && n.len >= 480 && ((n.t / 240) * 7 + n.d * 13 + c.orn_seed) % 100 < c.orn {
            let main = pitch(base, scale, n.d) + up;
            // the mordent's note first; then the grace (+1, -1, -2; the mordent's step above) and
            // the note
            let m = kind == 3;
            let (t0, g) = if m {
                block(ref tw, ch, n.t, 60, [main].span(), vel);
                (n.t + 60, n.d + 1)
            } else {
                (n.t, n.d + 1 - (kind * 3 + 1) / 2)
            };
            let gd = if m {
                60
            } else {
                80
            };
            block(ref tw, ch, t0, gd, [pitch(base, scale, g) + up].span(), vel - 10);
            block(ref tw, ch, t0 + gd, n.t + len - t0 - gd, [main].span(), vel);
        } else {
            block(ref tw, ch, n.t, len, [pitch(base, scale, n.d) + up].span(), vel);
        }
    }
    finish(tw, c.ticks)
}

/// The parts that follow the chords, bar by bar: the accompaniment (channel 2: its figure on the
/// triad), the bass (channel 3: its figure on the root, two octaves below the tonic), the pad
/// (channel 4: a held triad every two bars) and the percussion (channel 10: its figure).
#[inline(never)]
fn chord_track(k: Box<Ctx>, ch: u8) -> Array<u8> {
    let c = k.unbox();
    let s = c.s.unbox();
    let role: u32 = ch.into();
    let program = if ch == 9 {
        0
    } else {
        *s.palette.at(role * 3 + c.kind)
    };
    let mut tw = channel_track(ch, program, c.st);
    let (pattern, low, vel0) = if ch == 3 {
        (c.bass, c.base - 24, 64)
    } else if ch == 9 {
        (c.perc, 0, 36)
    } else if ch == 2 && c.acc_down {
        // the PCE Wavetable Pluck accompaniment an octave lower
        (c.accomp, c.base - 12, 40)
    } else {
        (c.accomp, c.base, 40)
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
        } else if ch == 9 {
            for x in pattern {
                let x = *x;
                let note: u8 = ((x / 0x800) % 0x80).try_into().unwrap();
                let vel: u8 = (vel0 + x / 0x40000).try_into().unwrap();
                block(ref tw, 9, t + x % 0x800, 120, [note].span(), vel);
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
                    } else {
                        // the root, the fifth below or above, or the octave
                        [pitch(low, scale, chord + O + *[3_u32, 0, 7, 10].span().at(voice) - 3)]
                            .span()
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
                let (at, d) = (t + x % 0x800, (x / 0x800) % 0x800);
                // the bass doubled (two halves) or detached (half length)
                let bm = if ch == 3 {
                    c.bass_mode
                } else {
                    0
                };
                let len = if bm == 0 {
                    d
                } else if bm == 1 {
                    d / 2 - 10
                } else {
                    d / 2
                };
                block(ref tw, ch, at, len, ps, vel);
                if bm == 1 {
                    block(ref tw, ch, at + d / 2, len, ps, vel);
                }
            }
        }
        t += bar;
    }
    finish(tw, c.ticks)
}

/// The track bodies of edition `e`'s track for a species (1-75), shiny or not, and a track seed:
/// the tempo track, then the lead, the playing parts and the mega double when shiny.
pub fn edition_tracks(species: u32, shiny: bool, e: u32, seed: u64) -> Array<Array<u8>> {
    edition_tracks_on(species, shiny, e, seed, Option::None, false)
}

/// The same on a day of drift (`drift.cairo` `layered_drift`, the song layers in the style
/// engine's terms): the month's new melodies (their rhythm cells and contour drawn from the
/// month's hash; same key, chords and tempo), the week's part swap (one part in, or out when all
/// four play) and accompaniment voicing (its triads in first or second inversion), and the day's
/// knob (0 the A and B progressions swap, 1 the A and B tunes swap, 2-5 the tempo nudged -4, -2,
/// +2, +4 BPM). No drift (`None`) is the track as written.
///
/// The edition sets the style and its tempo; the purchase seed rolls the rest: key, mode, form,
/// the A, B (and C) progressions, the accompaniment, bass and percussion figures, how the A tune
/// opens on the species theme, the grace notes and phrasing, and which parts join the lead and
/// accompaniment (descant, bass, pad, percussion: one to four, one more on tiers 1 and 2).
#[inline(never)]
pub fn edition_tracks_on(
    species: u32, shiny: bool, e: u32, seed: u64, drift: Option<Drift>, echo: bool,
) -> Array<Array<u8>> {
    let (rhythm, rotate, knob, delta, day) = match drift {
        Option::Some(d) => (d.rhythm, d.rotate, d.day_knob, d.delta_bpm, d.day),
        Option::None => (Option::None, Option::None, 6, 0, 0),
    };
    assert(species >= 1 && species <= 75, 'editions: species');
    let (st, sb, bpm0) = edition_genome(e);
    let s = sb.unbox();
    // the Beast: tier, type, tonic and the opening of its Genesis theme (degree + 8, 4 bits each)
    let k = species - 1;
    let mut v: u32 = *SPECIES.span().at(k);
    let tonic0 = v % 16;
    let mut theme: Array<u32> = array![];
    for _ in 0..6_u32 {
        v /= 16;
        theme.append(v % 16 + O - 8);
    }
    // the track's draws
    let lo32: u32 = (seed % TWO32).try_into().unwrap();
    let hi32: u32 = (seed / TWO32).try_into().unwrap();
    let mut r = Rng {
        a: lo32 ^ hi32 ^ e.wrapping_mul(0x9e3779b1) ^ species.wrapping_mul(0x85ebca77),
    };
    let tonic = (tonic0 + *[0_u32, 0, 0, 5, 7, 10, 2, 3].span().at(r.int(8))) % 12;
    let bpm = bpm0 + *[0_u32, 2, 4, 4, 6, 8].span().at(r.int(6)) - 4;
    let mut pa = r.int(16);
    let mut pb = r.int(16);
    if pb == pa {
        pb = (pa + 1) % 16;
    }
    let mut pc = (pa + 1 + r.int(14)) % 16;
    if pc == pb {
        pc = (pc + 1) % 16;
    }
    if knob == 0 {
        let a = pa;
        pa = pb;
        pb = a;
    }
    let modes = s.modes.len();
    let mode_i = r.int(modes);
    let form_id = r.int(8);
    let acc_i = r.int(4);
    let bass = *s.basses.at(r.int(3));
    let perc_i = r.int(2);
    // a new-melody month (the month's hash) also brings another accompaniment figure, the other
    // percussion figure and, one month in three, the style's next mode
    // and another form, and two months in three the key moves to the dominant or subdominant
    let (mode_i, acc_i, perc_i, form_id, tonic) = match rhythm {
        Option::Some(h) => {
            let m = low32(h);
            let km = (m / 256) % 3;
            (
                if (m / 8) % 3 == 0 {
                    (mode_i + 1) % modes
                } else {
                    mode_i
                },
                (acc_i + 1 + m % 3) % 4,
                (perc_i + 1) % 2,
                (form_id + 1 + (m / 64) % 3) % 8,
                if km < 2 {
                    (tonic + *[7_u32, 5].span().at(km)) % 12
                } else {
                    tonic
                },
            )
        },
        Option::None => (mode_i, acc_i, perc_i, form_id, tonic),
    };
    let form = *FORMS.span().at(form_id);
    let scale = (*SCALES.span().at(*s.modes.at(mode_i))).span();
    let accomp = *s.accomps.at(acc_i);
    let perc = *s.percs.at(perc_i);
    let treatment = r.int(4);
    let mut orn = *[0_u32, 0, 15, 30].span().at(r.int(4));
    let orn_seed = r.int(100);
    // the day's tempo knob flips the phrasing
    let detached = (r.int(2) == 1) != (knob >= 2 && knob <= 5);
    // the parts beside the lead and accompaniment: a seeded order, the first `count` play
    let roll = r.int(100);
    let mut count = if roll < 20 {
        1
    } else if roll < 60 {
        2
    } else if roll < 88 {
        3
    } else {
        4
    };
    if k % 25 < 10 && count < 4 {
        count += 1;
    }
    // (opaque: one compiled copy of the loop, CASM size)
    let (mut order, mut i): (Array<u32>, u32) = opaque((array![DESCANT, BASS, PAD, PERC], 3));
    while i > 0 {
        let j = r.int(i + 1);
        let o = order.span();
        let mut next: Array<u32> = array![];
        for x in 0..4_u32 {
            next.append(*o.at(if x == i {
                j
            } else if x == j {
                i
            } else {
                x
            }));
        }
        order = next;
        i -= 1;
    }
    let order = order.span();
    let mut parts: u32 = opaque(0);
    for x in order.slice(0, count) {
        parts += *x;
    }
    // the week's drift swaps one part in (or out, when all four play) and inverts the accompaniment
    let mut orn_kind = orn_seed % 4;
    let mut bass_mode = roll % 3;
    let rot = match rotate {
        Option::Some(h) => {
            let h = low32(h);
            // and turns the ornament, draws its density (up to 30% for the first 180 days, 45%
            // to day 360, then 60%) and moves the bass to its next rhythm
            orn_kind = (orn_kind + 1 + (h / 32) % 3) % 4;
            let ceiling: u32 = if day < 180 {
                2
            } else if day < 360 {
                3
            } else {
                4
            };
            orn = *[0_u32, 15, 30, 45, 60].span().at((h / 128) % (ceiling + 1));
            bass_mode = (bass_mode + 1 + (h / 512) % 2) % 3;
            if count == 4 {
                parts -= *order.at(h % 4);
            } else {
                parts = parts - *order.at(h % count) + *order.at(count + (h / 4) % (4 - count));
            }
            1 + (h / 16) % 2
        },
        Option::None => 0,
    };
    // the theme as the A tune opens with it: as written, inverted, reversed or a third up
    let theme = theme.span();
    let mut motif: Array<u32> = array![];
    for x in 0..6_u32 {
        let d = *theme.at(if treatment == 2 {
            5 - x
        } else {
            x
        });
        motif.append(if treatment == 1 {
            2 * O - d
        } else if treatment == 3 {
            d + 2
        } else {
            d
        });
    }
    let bar = s.num * (1920 / s.den);
    let strong2 = if s.den == 8 {
        720
    } else if s.num == 4 {
        960
    } else {
        0
    };
    let ca = section_chords(s.progs, s.chord_bars, pa);
    let cb = section_chords(s.progs, s.chord_bars, pb);
    let cc = section_chords(s.progs, s.chord_bars, pc);
    let ma = BoxTrait::new(Mel { bar, strong2, lo: O - 1, motif: motif.span() });
    let mb = BoxTrait::new(Mel { bar, strong2, lo: O + 1, motif: [].span() });
    // the tunes, A (with the theme), B and C: the month's drift draws them from its own hash
    let mut mr = match rhythm {
        Option::Some(h) => Rng { a: low32(h) },
        Option::None => r,
    };
    let mel_a = melody(s.cells, s.end, ma, ca, true, ref mr);
    let mel_b = melody(s.cells, s.end, mb, cb, kind_of(form, 3) == 1, ref mr);
    let mel_c = if form_id % 4 == 3 {
        melody(s.cells, s.end, mb, cc, true, ref mr)
    } else {
        [].span()
    };
    // A': A's first four bars and a new answer (a fresh tune's last four), or A decorated (each
    // note of a quarter or longer split, its second half a step toward the next note); the kind
    // from the ornament seed (no draw of its own)
    let mut mel_d: Array<MelNote> = array![];
    if form_id >= 4 {
        let half = 4 * bar;
        if (orn_seed / 4) % 2 == 0 {
            let fresh = melody(s.cells, s.end, ma, ca, true, ref mr);
            for n in mel_a {
                if n.t < half {
                    mel_d.append(*n);
                }
            }
            for n in fresh {
                if n.t >= half {
                    mel_d.append(*n);
                }
            }
        } else {
            let mut i: u32 = 0;
            while i < mel_a.len() {
                let n = *mel_a.at(i);
                if n.len < 480 || i + 1 == mel_a.len() {
                    mel_d.append(n);
                } else {
                    let nd = mel_a.at(i + 1).d;
                    let h = n.len / 2;
                    mel_d.append(MelNote { t: n.t, len: h, d: n.d });
                    mel_d
                        .append(
                            MelNote {
                                t: n.t + h,
                                len: n.len - h,
                                d: if nd < n.d {
                                    n.d - 1
                                } else {
                                    n.d + 1
                                },
                            },
                        );
                }
                i += 1;
            }
        }
    }
    let mel_d = mel_d.span();
    let (mel_a, mel_b) = if knob == 1 {
        (mel_b, mel_a)
    } else {
        (mel_a, mel_b)
    };
    let mut lead: Array<MelNote> = array![];
    let mut chords: Array<u32> = array![];
    for sec in 0..4_u32 {
        let t0 = sec * 8 * bar;
        let kind = kind_of(form, sec);
        let (mel, cs) = if kind == 3 {
            (mel_d, ca)
        } else if kind == 2 {
            (mel_c, cc)
        } else if kind == 1 {
            (mel_b, cb)
        } else {
            (mel_a, ca)
        };
        for n in mel {
            lead.append(MelNote { t: t0 + n.t, len: n.len, d: n.d });
        }
        for x in cs {
            chords.append(*x);
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
            rot,
            kind: k / 25,
            shiny,
            species,
            accomp,
            bass,
            perc,
            orn,
            orn_seed,
            orn_kind,
            st,
            // an FM Brass lead on 1 purchase in 4; the PCE Wavetable Pluck accompaniment an octave
            // lower on 1 in 3 (no draws of their own)
            lead_alt: !shiny && *s.palette.at(k / 25) == 47 && (orn_seed + roll) % 4 != 0,
            acc_down: *s.palette.at(6 + k / 25) == 99 && (orn_seed / 8) % 3 == 0,
            bass_mode,
            detached,
            chords: chords.span(),
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
    let mut tracks: Array<Array<u8>> = array![finish(tempo, ticks), lead_track(ctx, 0)];
    if parts & DESCANT != 0 {
        tracks.append(lead_track(ctx, 2));
    }
    tracks.append(chord_track(ctx, 2));
    if parts & BASS != 0 {
        tracks.append(chord_track(ctx, 3));
    }
    if parts & PAD != 0 {
        tracks.append(chord_track(ctx, 4));
    }
    if parts & PERC != 0 {
        tracks.append(chord_track(ctx, 9));
    }
    if shiny {
        tracks.append(lead_track(ctx, 1));
    }
    if echo {
        tracks.append(lead_track(ctx, 3));
    }
    tracks
}

/// Edition `e`'s track as a Standard MIDI File (format 1, 480 ticks per quarter note).
pub fn edition_smf_bytes(species: u32, shiny: bool, e: u32, seed: u64) -> Array<u8> {
    smf_bytes(1, 480, edition_tracks(species, shiny, e, seed).span())
}

/// The same as a `ByteArray`, packed from the track bodies without copying them into one array, on
/// a day of drift when `drift` is `Some`, with the chip echo when `echo`.
pub fn edition_byte_array(
    species: u32, shiny: bool, e: u32, seed: u64, drift: Option<Drift>, echo: bool,
) -> ByteArray {
    smf_byte_array(1, 480, edition_tracks_on(species, shiny, e, seed, drift, echo).span())
}

/// The low 32 bits of a hash.
fn low32(x: felt252) -> u32 {
    let w: u256 = x.into();
    (w % 0x100000000).try_into().unwrap()
}

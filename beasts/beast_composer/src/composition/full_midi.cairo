//! Self-contained Beast MIDI for a generic player (onchain-midi-player plays a file exactly as
//! written: every play resets each channel to program 0 and adds nothing).
//!
//! On top of the score: a program change and a pan (CC10) on every voice at tick 0, and a drum
//! track on channel 10. Every voice plays `VOICE_PROGRAM`, a TinyChip bank number, so sound
//! settings that install that preset in the same slot are selected by the file. Byte-identical to
//! `beastFullMidi` in offchain/beast-sound/src/full_midi.js.
//!
//! Drums: kick, half-time snare and eighth-note hats phrased in bar pairs, and a fill
//! into every section by tier (A tier 5, B tier 4, C tier 3, D tiers 1-2 with a cymbal on each
//! section's downbeat). Drum hits are note-ons only (one-shots), written with running status.

use midi::smf::{TrackWriter, TrackWriterTrait, smf_bytes};
use crate::composition::beast_score::BeastForm;
use crate::composition::melodic_canon::NoteEvent;
use crate::composition::yeti::rock_drum_track;
use crate::opaque::opaque;

/// The program every voice plays: TinyChip's Triangle Lead (bank 0) for now, until the preset set
/// and its orchestration are chosen.
pub const VOICE_PROGRAM: u8 = 0;

/// A maximal stretch of consecutive events of one voice: `events[start..start + len]` and the sum
/// of their pitches.
#[derive(Copy, Drop)]
pub(crate) struct VoiceRun {
    pub(crate) voice: u32,
    pub(crate) start: u32,
    pub(crate) len: u32,
    pitch_sum: u64,
}

/// The voice runs of `events`, in event order, from one pass. Events may come in any order (the
/// Genesis path voice by voice, v1.1 section by section), so a voice can have several runs; reading
/// a voice's runs in order reads its events in their original order.
pub(crate) fn voice_runs(events: Span<NoteEvent>) -> Array<VoiceRun> {
    // `start`, `end`, `pitch_sum`: felts, so no overflow checks per event, converted once per run
    // (they fit: at most events.len() events, of pitch at most 255)
    let (mut runs, mut voice, mut start, mut end, mut pitch_sum) = opaque((array![], 0, 0, 0, 0));
    for e in events {
        if e.voice_id != voice {
            // the run before it (none yet if the first event is not voice 0)
            if end != start {
                runs.append(voice_run(voice, start, end, pitch_sum));
            }
            voice = e.voice_id;
            start = end;
            pitch_sum = 0;
        }
        pitch_sum += e.pitch.into();
        end += 1;
    }
    if end != start {
        runs.append(voice_run(voice, start, end, pitch_sum));
    }
    runs
}

/// The run of `voice` over the events `start..end`.
fn voice_run(voice: u32, start: felt252, end: felt252, pitch_sum: felt252) -> VoiceRun {
    VoiceRun {
        voice,
        start: start.try_into().unwrap(),
        len: (end - start).try_into().unwrap(),
        pitch_sum: pitch_sum.try_into().unwrap(),
    }
}

/// The highest voice id of the runs (0 when there are none).
fn max_voice_of(runs: Span<VoiceRun>) -> u32 {
    let mut max_voice: u32 = 0;
    for r in runs {
        if r.voice > max_voice {
            max_voice = r.voice;
        }
    }
    max_voice
}

/// The pitch sum and the event count of every voice id 0..=max_voice.
pub(crate) fn voice_stats(runs: Span<VoiceRun>, max_voice: u32) -> (Array<u64>, Array<u64>) {
    let (mut sums, mut counts, mut v, zero): (Array<u64>, Array<u64>, u32, u64) = opaque(
        (array![], array![], 0, 0),
    );
    while v <= max_voice {
        let mut sum = zero;
        let mut n = zero;
        for r in runs {
            if r.voice == v {
                sum += r.pitch_sum;
                n += r.len.into();
            }
        }
        sums.append(sum);
        counts.append(n);
        v += 1;
    }
    (sums, counts)
}

/// `VOICE_PROGRAM` for every voice id 0..=max_voice.
fn plain_programs(max_voice: u32) -> Array<u8> {
    let (mut programs, mut v): (Array<u8>, u32) = opaque((array![], 0));
    while v <= max_voice {
        programs.append(VOICE_PROGRAM);
        v += 1;
    }
    programs
}

/// The pan of every voice id (one per count): the voices with events panned left to right in voice
/// order, the others 64.
fn voice_pans(counts: Span<u64>) -> Array<u8> {
    let mut nv: u32 = 0;
    for n in counts {
        if *n > 0 {
            nv += 1;
        }
    }
    // pan across the present voices in voice order: floor((960 (n-1) + 10880 i) / (100 (n-1)))
    let mut pans: Array<u8> = array![];
    let mut i: u32 = 0;
    for n in counts {
        if *n > 0 {
            let pan: u32 = if nv < 2 {
                64
            } else {
                (960 * (nv - 1) + 10880 * i) / (100 * (nv - 1))
            };
            pans.append(pan.try_into().unwrap());
            i += 1;
        } else {
            pans.append(64);
        }
    }
    pans
}

/// (programs, pans) indexed by voice id 0..=max voice: every voice on `VOICE_PROGRAM`, the present
/// voices panned left to right in voice order (absent voices get 64).
pub fn voice_setup(form: @BeastForm) -> (Array<u8>, Array<u8>) {
    let runs = voice_runs(form.events.span());
    let max_voice = max_voice_of(runs.span());
    let (_, counts) = voice_stats(runs.span(), max_voice);
    (plain_programs(max_voice), voice_pans(counts.span()))
}

/// The fill for a tier: 0 A (tier 5), 1 B (tier 4), 2 C (tier 3), 3 D (tiers 1-2).
fn fill_for(tier: u8) -> u8 {
    if tier >= 5 {
        0
    } else if tier == 4 {
        1
    } else if tier == 3 {
        2
    } else {
        3
    }
}

// fill notes (offset, key, velocity) and length in beats
/// Fills A-D, one after another: fill `f` is FILL_NOTES[FILL_AT[f]..FILL_AT[f + 1]] (a constant
/// array: data, not code).
const FILL_NOTES: [(u32, u8, u8); 22] = [
    (0, 38, 88), (240, 38, 106), (0, 38, 72), (120, 38, 84), (240, 38, 96), (360, 38, 108),
    (0, 36, 100), (0, 38, 80), (240, 38, 88), (480, 38, 92), (600, 38, 100), (720, 38, 108),
    (840, 38, 116), (0, 50, 84), (120, 50, 88), (240, 48, 92), (360, 48, 96), (480, 47, 100),
    (600, 45, 104), (720, 43, 108), (840, 41, 112), (840, 36, 110),
];
const FILL_AT: [u32; 5] = [0, 2, 6, 13, 22];

fn fill_notes(f: u8) -> Span<(u32, u8, u8)> {
    let n: u32 = if f > 3 {
        3
    } else {
        f.into()
    };
    let (a, b) = (*FILL_AT.span().at(n), *FILL_AT.span().at(n + 1));
    FILL_NOTES.span().slice(a, b - a)
}

/// The drum track body (channel 10, running status) for a form of `length` ticks in sections of
/// `sec`, ending with End-of-Track at `length`. Empty when there is nothing to play.
pub fn drum_track(length: u32, sec: u32, tier: u8, mega: bool) -> Array<u8> {
    if length == 0 {
        return array![];
    }
    let f = fill_for(tier);
    let notes = fill_notes(f);
    let region: u32 = if f >= 2 {
        960
    } else {
        480
    };
    let fill_start = sec - region;
    let fill_kick0 = f == 2; // only fill C has a kick at its start
    // a cymbal on each section's downbeat: fill D, and every mega Beast
    let cymbal = mega || f == 3;
    // One step per 120 ticks. Whether it is on an eighth note (`u % 240 == 0`) and, if so, on a
    // quarter note (`u % 480 == 0`) is carried from step to step instead of divided out of `u`.
    let (mut track, mut u, mut eighth, mut quarter): (TrackWriter, u32, bool, bool) = opaque(
        (TrackWriterTrait::with_running_status(), 0, true, true),
    );
    while u < length {
        let rel = u % sec;
        let in_fill = rel >= fill_start;
        if cymbal && rel == 0 {
            track.note_on(u, 9, 49, if mega {
                96
            } else {
                76
            });
        }
        if in_fill {
            let at = rel - fill_start;
            for n in notes {
                let (o, k, vel) = *n;
                if o == at {
                    track.note_on(u, 9, k, vel);
                }
            }
        }
        // The step's kick or snare (key 0: none) and its hat, written after the fill notes in
        // that order. Each branch only sets them: every `note_on` is another copy of its call
        // in the contract, so there is one per hit kind below.
        let mut drum_key: u8 = 0;
        let mut drum_vel: u8 = 0;
        let mut hat_key: u8 = 42;
        let mut hat_vel: u8 = 0;
        if !eighth {
            // mega: sixteenth-note hats
            hat_vel = if in_fill {
                32
            } else {
                44
            };
        } else {
            // `rel / 1920` is odd in the upper half of a bar pair, `rel % 1920` is the position in
            // its bar
            let pair = rel % 3840;
            let second = pair >= 1920;
            let q = if second {
                pair - 1920
            } else {
                pair
            };
            let bar_start = q == 0;
            hat_vel = if bar_start {
                80
            } else if quarter {
                70
            } else {
                52
            };
            if bar_start {
                drum_key = 36;
                drum_vel = if second {
                    104
                } else {
                    122
                };
            } else if q == 960 {
                if !in_fill {
                    drum_key = 38;
                    drum_vel = if second {
                        88
                    } else {
                        94
                    };
                } else if !(fill_kick0 && rel == fill_start) {
                    drum_key = 36;
                    drum_vel = 100;
                }
            } else if !in_fill {
                if second {
                    if q == 1200 {
                        drum_key = 36;
                        drum_vel = 86;
                    } else if q == 1680 {
                        // the open hat
                        hat_key = 46;
                        hat_vel = 64;
                    }
                } else if mega && q == 720 {
                    drum_key = 36;
                    drum_vel = 92; // mega: the and of 2
                }
            }
            if in_fill {
                hat_vel -= 12;
            }
        }
        if drum_key != 0 {
            track.note_on(u, 9, drum_key, drum_vel);
        }
        if eighth || mega {
            track.note_on(u, 9, hat_key, hat_vel);
        }
        u += 120;
        eighth = !eighth;
        if !eighth {
            quarter = !quarter;
            // the sixteenth between two eighths plays nothing before the fill, unless it has the
            // mega Beast's sixteenth-note hat: skip it
            if !mega && rel + 120 < fill_start {
                u += 120;
                eighth = true;
            }
        }
    }
    track.finish_at(length)
}

#[cfg(test)]
mod drum_track_tests {
    use midi::smf::TrackWriterTrait;
    use super::{drum_track, fill_for, fill_notes};

    /// `drum_track` as it was when every step divided its position out of `u` and collected its
    /// hits before writing them: the reference the carried position must reproduce byte for byte.
    fn divided_drum_track(length: u32, sec: u32, tier: u8, mega: bool) -> Array<u8> {
        let f = fill_for(tier);
        let notes = fill_notes(f);
        let region: u32 = if f >= 2 {
            960
        } else {
            480
        };
        let fill_kick0 = f == 2; // only fill C has a kick at its start
        let mut track = TrackWriterTrait::with_running_status();
        let mut u: u32 = 0;
        while u < length {
            let rel = u % sec;
            let fill_start = sec - region;
            let in_fill = rel >= fill_start;
            let mut hits: Array<(u8, u8)> = array![];
            // a cymbal on each section's downbeat (fill D, and every mega Beast)
            if rel == 0 && (mega || f == 3) {
                hits.append((49, if mega {
                    96
                } else {
                    76
                }));
            }
            if in_fill {
                let mut i: u32 = 0;
                while i < notes.len() {
                    let (o, k, vel) = *notes.at(i);
                    if o == rel - fill_start {
                        hits.append((k, vel));
                    }
                    i += 1;
                }
            }
            if mega && u % 240 != 0 {
                // mega: sixteenth-note hats
                hits.append((42, if in_fill {
                    32
                } else {
                    44
                }));
            }
            if u % 240 == 0 {
                let bar = rel / 1920;
                let second = bar % 2 == 1;
                let q = rel % 1920;
                if q == 0 {
                    hits.append((36, if second {
                        104
                    } else {
                        122
                    }));
                }
                if !in_fill && second && q == 1200 {
                    hits.append((36, 86));
                }
                if mega && !in_fill && !second && q == 720 {
                    hits.append((36, 92)); // mega: the and of 2
                }
                if in_fill && q == 960 && !(fill_kick0 && rel == fill_start) {
                    hits.append((36, 100));
                }
                if !in_fill && q == 960 {
                    hits.append((38, if second {
                        88
                    } else {
                        94
                    }));
                }
                let open = !in_fill && second && q == 1680;
                let mut hv: u8 = if q == 0 {
                    80
                } else if u % 480 == 0 {
                    70
                } else {
                    52
                };
                if in_fill {
                    hv -= 12;
                }
                if open {
                    hits.append((46, 64));
                } else {
                    hits.append((42, hv));
                }
            }
            for (k, vel) in hits {
                track.note_on(u, 9, k, vel);
            }
            u += 120;
        }
        if track.is_empty() {
            return array![];
        }
        track.finish_at(length)
    }

    fn assert_same(length: u32, sec: u32, tier: u8, mega: bool) {
        assert(
            drum_track(length, sec, tier, mega) == divided_drum_track(length, sec, tier, mega),
            'drum track differs',
        );
    }

    /// Every fill (tiers 0 to 6 cover each `fill_for` branch) with and without mega, for the
    /// lengths around the section and step boundaries. A fill longer than the section underflows
    /// `sec - region` in both forms, so those are left out.
    fn assert_same_at(length: u32, sec: u32) {
        let mut tier: u8 = 0;
        while tier <= 6 {
            if tier >= 4 || sec >= 960 {
                assert_same(length, sec, tier, false);
                assert_same(length, sec, tier, true);
            }
            tier += 1;
        }
    }

    fn assert_same_for_section(sec: u32) {
        assert_same_at(1, sec);
        assert_same_at(119, sec);
        assert_same_at(120, sec);
        assert_same_at(121, sec);
        assert_same_at(sec - 1, sec);
        assert_same_at(sec, sec);
        assert_same_at(sec + 1, sec);
        assert_same_at(2 * sec + 360, sec);
        assert_same_at(2 * sec + 361, sec);
    }

    /// What the callers pass: whole bars to a section, whole sections to the form.
    #[test]
    #[available_gas(1000000000000)]
    fn matches_on_whole_sections() {
        let mut bars: u32 = 1;
        while bars <= 4 {
            let sec = bars * 1920;
            assert_same_at(sec, sec);
            assert_same_at(2 * sec, sec);
            assert_same_at(3 * sec, sec);
            bars += 1;
        }
        assert_same_at(8 * 3840, 3840);
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

    #[test]
    fn nothing_to_play_in_no_ticks() {
        assert(drum_track(0, 3840, 5, false).len() == 0, 'not empty');
        assert(drum_track(0, 3840, 1, true).len() == 0, 'not empty');
        // no section either: nothing is divided by it
        assert(drum_track(0, 0, 1, true).len() == 0, 'not empty');
    }
}

/// Instruments by Beast: the Beast's type picks a family of three leads and three plucks (the
/// fullest pluck first), each family one wave character: Magic round (triangle, soft pulse), Hunter
/// sharp (narrow pulses), Brute heavy (square, saw). TinyChip bank program numbers. Matches
/// FAMILIES in offchain/beast-sound/src/full_midi.js.
pub fn family_leads(beast_type: u8) -> [u8; 3] {
    if beast_type == 1 {
        [2, 1, 8]
    } else if beast_type == 2 {
        [3, 4, 5]
    } else {
        [0, 9, 7]
    }
}

pub fn family_plucks(beast_type: u8) -> [u8; 3] {
    if beast_type == 1 {
        [12, 19, 6]
    } else if beast_type == 2 {
        [16, 14, 18]
    } else {
        [15, 17, 13]
    }
}

/// What the instruments by Beast need to know about the Beast and its score.
#[derive(Copy, Drop)]
pub struct Voicing {
    pub beast_type: u8,
    pub species_id: u64,
    pub name_variant_id: u32,
    pub voice_count: u32,
    pub use_countersubject: bool,
}

/// The program of every voice id 0..=max_voice by musical role (absent voices keep VOICE_PROGRAM):
/// the theme voice (0) leads with the family lead the species picks; the canon followers take the
/// plucks, the lowest of them (by mean pitch, cross-multiplied, ties to the lower voice id) the
/// fullest and the others rotated by the name; the countersubject (voice id = voice_count) another
/// family lead.
/// Matches beastInstruments in offchain/beast-sound/src/full_midi.js.
pub fn beast_voice_programs(
    events: Span<NoteEvent>, max_voice: u32, voicing: Voicing,
) -> Array<u8> {
    let (sums, counts) = voice_stats(voice_runs(events).span(), max_voice);
    voice_programs(sums.span(), counts.span(), voicing)
}

/// `beast_voice_programs` from the voices' pitch sums and event counts (one per voice id 0..=max).
fn voice_programs(sums: Span<u64>, counts: Span<u64>, voicing: Voicing) -> Array<u8> {
    let max_voice = counts.len() - 1;
    let leads = family_leads(voicing.beast_type).span();
    let plucks = family_plucks(voicing.beast_type).span();
    let lead: u32 = (voicing.species_id % 3).try_into().unwrap();
    let name_odd = voicing.name_variant_id % 2 == 1;
    let cs: u32 = if voicing.use_countersubject {
        voicing.voice_count
    } else {
        0xFFFFFFFF
    };
    // the countersubject takes another family lead, if it has notes
    let cs_pick = (lead + 1 + if name_odd {
        1
    } else {
        0
    }) % 3;
    let has_cs = voicing.use_countersubject && cs <= max_voice && *counts.at(cs) > 0;
    let (mut out, mut v): (Array<u8>, u32) = opaque((array![], 0));
    while v <= max_voice {
        out
            .append(
                if v != 0 && v != cs && *counts.at(v) > 0 {
                    // a follower: its rank among the followers, lowest mean pitch first (the lower
                    // voice id breaks ties)
                    let mut rank: u32 = 0;
                    let mut u: u32 = 1;
                    while u <= max_voice {
                        if u != v && u != cs && *counts.at(u) > 0 {
                            let lhs = *sums.at(u) * *counts.at(v);
                            let rhs = *sums.at(v) * *counts.at(u);
                            if lhs < rhs || (lhs == rhs && u < v) {
                                rank += 1;
                            }
                        }
                        u += 1;
                    }
                    if rank == 0 {
                        *plucks.at(0)
                    } else if (rank == 1) != name_odd {
                        *plucks.at(1)
                    } else {
                        *plucks.at(2)
                    }
                } else if has_cs && v == cs {
                    *leads.at(cs_pick)
                } else if v == 0 {
                    *leads.at(lead)
                } else {
                    VOICE_PROGRAM
                },
            );
        v += 1;
    }
    out
}

/// The mega lead presets: Robot Hero Lead (50) and N163 Brass Wave (65), reserved for mega Beasts.
pub const MEGA_LEADS: [u8; 2] = [50, 65];

/// Which of MEGA_LEADS a mega Beast's lead plays (the octave double plays the other): fixed by its
/// species and name.
pub fn mega_lead_pick(species_id: u64, name_variant_id: u32) -> u32 {
    ((species_id + name_variant_id.into()) % 2).try_into().unwrap()
}

/// How the file is arranged on top of the score (the lab's Genesis Track; full_midi.js
/// `beastFullMidi`
/// options): `top_lead` (the highest voice never plays a pluck: it takes the family's lead no other
/// voice plays), `balanced` (leads at channel volume 64 and plucks at 127, panning halved, the
/// upper plucks softer above the bass), `drums` (the drum track, or none), `rock` (the Yeti's rock
/// groove in place of the groove) and `extra` (a voice on its own program that is never the lead:
/// the Yeti's avalanche, `programs` and `notLead` in the lab) and `programs` (a program per voice
/// id in place of the voicing's: the Sound Check's presets).
#[derive(Copy, Drop)]
pub struct Arrangement {
    pub top_lead: bool,
    pub balanced: bool,
    pub drums: bool,
    pub rock: bool,
    pub extra: Option<(u32, u8)>,
    pub programs: Option<Span<u8>>,
    /// the chip echo (sound_effects 2 and 3): the lead again a dotted eighth later, half as loud,
    /// on the family's first pluck, panned opposite
    pub echo: bool,
    /// the lead's grace notes (`grace_of`): share of its long notes (percent) * 4 + kind; 0 none
    pub grace: u32,
}

/// A song's grace notes from its ornament density (0-7: 0-35% of the lead's and the theme's notes
/// of a quarter or longer) and their kind (0 a tone above, 1 a semitone below, 2 a slide from a
/// minor third below, 3 a mordent).
pub fn grace_of(density: u8, kind: u32) -> u32 {
    let d: u32 = density.into();
    d * 20 + kind
}

/// The upper plucks' volume factor in basis points for a voice averaging MIDI 52 + i (i = 0..12;
/// above, 12): 10000 * 10^(-7 i / 480). Matches PLUCK_ABOVE_BASS_BP in full_midi.js.
const PLUCK_ABOVE_BASS_BP: [u32; 13] = [
    10000, 9670, 9350, 9042, 8743, 8454, 8175, 7905, 7644, 7392, 7148, 6912, 6683,
];

/// One note: on, then off (velocity 64) on channel `ch` (out of line: CASM size).
#[inline(never)]
fn note_on_off(ref track: TrackWriter, ch: u8, t: u32, d: u32, p: u8, v: u8) {
    track.message(t, 0x90 + ch, p, v);
    track.message(t + d, 0x80 + ch, p, 64);
}

/// Each note of `notes` as a note on and a note off (velocity 64) on channel `ch`, with grace notes
/// (`grace`, `grace_of`; 0 none) on some notes of a quarter or longer, placed by time, pitch and
/// `salt`: the grace (80 ticks, 10 softer) then the note, or for a mordent the note (60), the tone
/// above (60), the note.
fn write_notes(ref track: TrackWriter, ch: u8, notes: Span<NoteEvent>, grace: u32, salt: u32) {
    let (share, kind) = (grace / 4, grace % 4);
    for e in notes {
        let (t, p, v, d) = (e.time, e.pitch, e.velocity, e.duration);
        let mut start = t;
        let pp: u32 = p.into();
        if share > 0
            && d >= 480
            && p >= 3
            && p <= 125
            && v > 10
            && ((t / 240) * 7 + pp * 13 + salt) % 100 < share {
            let m = kind == 3;
            if m {
                note_on_off(ref track, ch, t, 60, p, v);
                start = t + 60;
            }
            let (g, gd) = if m {
                (p + 2, 60)
            } else {
                (p + 2 - *[0_u8, 3, 5].span().at(kind), 80)
            };
            note_on_off(ref track, ch, start, gd, g, v - 10);
            start += gd;
        }
        note_on_off(ref track, ch, start, t + d - start, p, v);
    }
}

/// The whole self-contained file: tempo track (End-of-Track at the form length), one track per
/// voice (program and pan at tick 0, then the notes), and the drum track. `mega` (the Beast's shiny
/// flag) adds the mega arrangement: the lead voice (the highest mean pitch, ties to the higher
/// voice id) on MEGA_LEADS[lead_pick], its octave double on its own channel with the other mega
/// lead, panned opposite and three quarters as loud, and the mega drum groove.
pub fn beast_form_to_full_smf_bytes(
    form: @BeastForm, tempo_us: u32, tier: u8, voicing: Option<Voicing>, mega: bool, lead_pick: u32,
) -> Array<u8> {
    beast_form_to_full_smf_bytes_arranged(
        form,
        tempo_us,
        tier,
        voicing,
        mega,
        lead_pick,
        Arrangement {
            top_lead: false,
            balanced: false,
            drums: true,
            rock: false,
            extra: Option::None,
            programs: Option::None,
            echo: false,
            grace: 0,
        },
    )
}

/// The file's `MThd` fields: format 1 (simultaneous tracks), 480 ticks per quarter note.
pub const SMF_FORMAT: u16 = 1;
pub const SMF_DIVISION: u16 = 480;

/// The same with an arrangement (`beast_form_to_full_smf_bytes` is the plain one, drums on).
pub fn beast_form_to_full_smf_bytes_arranged(
    form: @BeastForm,
    tempo_us: u32,
    tier: u8,
    voicing: Option<Voicing>,
    mega: bool,
    lead_pick: u32,
    arr: Arrangement,
) -> Array<u8> {
    let tracks = beast_form_to_full_tracks_arranged(
        form, tempo_us, tier, voicing, mega, lead_pick, arr,
    );
    smf_bytes(SMF_FORMAT, SMF_DIVISION, tracks.span())
}

/// The track bodies of that file: the tempo track, one per voice, the drum track. A caller that
/// wants the file as a `ByteArray` passes them to `midi::smf::smf_byte_array` with `SMF_FORMAT`
/// and `SMF_DIVISION`, which saves copying them into one array first.
// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
pub fn beast_form_to_full_tracks_arranged(
    form: @BeastForm,
    tempo_us: u32,
    tier: u8,
    voicing: Option<Voicing>,
    mega: bool,
    lead_pick: u32,
    arr: Arrangement,
) -> Array<Array<u8>> {
    let events = form.events.span();
    // the per-voice statistics (and where each voice's events are), from one pass over the events
    let runs = voice_runs(events);
    let max_voice = max_voice_of(runs.span());
    let (sums, counts) = voice_stats(runs.span(), max_voice);
    let base_pans = voice_pans(counts.span());
    // instruments by Beast, or VOICE_PROGRAM on every voice
    let mut base_programs = match voicing {
        Option::Some(vc) => voice_programs(sums.span(), counts.span(), vc),
        Option::None => plain_programs(max_voice),
    };
    let extra_voice: u32 = match arr.extra {
        Option::Some((ev, prog)) => {
            let (mut next, mut v): (Array<u8>, u32) = opaque((array![], 0));
            while v <= max_voice {
                next.append(if v == ev {
                    prog
                } else {
                    *base_programs.at(v)
                });
                v += 1;
            }
            base_programs = next;
            ev
        },
        Option::None => 0xFFFFFFFF,
    };
    if let Option::Some(ps) = arr.programs {
        let (mut next, mut v): (Array<u8>, u32) = opaque((array![], 0));
        while v <= max_voice {
            next.append(if v < ps.len() {
                *ps.at(v)
            } else {
                *base_programs.at(v)
            });
            v += 1;
        }
        base_programs = next;
    }
    let length = form.length_ticks;
    let sections: u32 = form.section_count.into();
    let sec = length / sections;

    // the lead: the highest mean pitch (cross-multiplied), ties to the higher voice id; found once
    // `lead_n` (a voice's note count) is not 0
    let (mut lead, mut lead_sum, mut lead_n, mut v): (u32, u64, u64, u32) = opaque((0, 0, 0, 0));
    while v <= max_voice {
        let sum = *sums.at(v);
        let n = *counts.at(v);
        if n > 0 && v != extra_voice && (lead_n == 0 || sum * lead_n >= lead_sum * n) {
            lead = v;
            lead_sum = sum;
            lead_n = n;
        }
        v += 1;
    }
    let found = lead_n != 0;
    // top_lead: when the highest voice drew a pluck, it takes the family's lead no voice plays
    let mut lead_program: u8 = *base_programs.at(lead);
    if arr.top_lead && found {
        if let Option::Some(vc) = voicing {
            let plucks = family_plucks(vc.beast_type).span();
            let leads = family_leads(vc.beast_type).span();
            if lead_program == *plucks.at(0)
                || lead_program == *plucks.at(1)
                || lead_program == *plucks.at(2) {
                let mut pick: Option<u8> = Option::None;
                for l in leads {
                    let (mut used, mut u): (bool, u32) = opaque((false, 0));
                    while u <= max_voice {
                        if *counts.at(u) > 0 && *base_programs.at(u) == *l {
                            used = true;
                        }
                        u += 1;
                    }
                    if !used && pick.is_none() {
                        pick = Option::Some(*l);
                    }
                }
                lead_program = match pick {
                    Option::Some(l) => l,
                    Option::None => *leads.at(((vc.species_id + 1) % 3).try_into().unwrap()),
                };
            }
        }
    }
    let (mut programs, mut pans, mut v): (Array<u8>, Array<u8>, u32) = opaque(
        (array![], array![], 0),
    );
    while v <= max_voice {
        programs
            .append(
                if mega && v == lead {
                    *MEGA_LEADS.span().at(lead_pick)
                } else if v == lead {
                    lead_program
                } else {
                    *base_programs.at(v)
                },
            );
        pans.append(*base_pans.at(v));
        v += 1;
    }
    // mega: the lead an octave up on its own channel; the chip echo (sound effects 2 and 3): the
    // lead 360 ticks later (a dotted eighth) at half velocity, inside the form, on the family's
    // first pluck; both panned opposite the lead
    let dbl = max_voice + 1;
    let mut last_voice = if mega {
        dbl
    } else {
        max_voice
    };
    let ech = last_voice + 1;
    let lp: u32 = (*base_pans.at(lead)).into();
    let opposite: u8 = if 128 - lp > 127 {
        127
    } else {
        (128 - lp).try_into().unwrap()
    };
    if mega {
        programs.append(*MEGA_LEADS.span().at(1 - lead_pick));
        pans.append(opposite);
    }
    if arr.echo {
        let fam = match voicing {
            Option::Some(vc) => vc.beast_type,
            Option::None => 0,
        };
        programs.append(*family_plucks(fam).span().at(0));
        pans.append(opposite);
        last_voice = ech;
    }
    let mut doubled: Array<NoteEvent> = array![];
    let mut echoed: Array<NoteEvent> = array![];
    for r in runs.span() {
        if r.voice != lead {
            continue;
        }
        for e in events.slice(r.start, r.len) {
            if mega && e.pitch + 12 <= 127 {
                let vel: u32 = e.velocity.into() * 3 / 4;
                doubled
                    .append(
                        NoteEvent {
                            time: e.time,
                            duration: e.duration,
                            pitch: e.pitch + 12,
                            velocity: if vel < 1 {
                                1
                            } else {
                                vel.try_into().unwrap()
                            },
                            voice_id: dbl,
                        },
                    );
            }
            let t = e.time + 360;
            if arr.echo && t < length {
                let vel: u32 = e.velocity.into() / 2;
                echoed
                    .append(
                        NoteEvent {
                            time: t,
                            duration: if e.duration + t > length {
                                length - t
                            } else {
                                e.duration
                            },
                            pitch: e.pitch,
                            velocity: if vel < 1 {
                                1
                            } else {
                                vel.try_into().unwrap()
                            },
                            voice_id: ech,
                        },
                    );
            }
        }
    }
    // balanced: leads (theme, countersubject, mega double, any family or mega lead) at 64, plucks
    // at 127; panning halved (64 + (pan - 64) / 2, rounded half up); the upper plucks softer above
    // the bass
    let mut vols: Array<u8> = array![];
    if arr.balanced {
        let (fl, cs) = match voicing {
            Option::Some(vc) => (
                family_leads(vc.beast_type),
                if vc.use_countersubject {
                    vc.voice_count
                } else {
                    0xFFFFFFFF
                },
            ),
            Option::None => (family_leads(0), 0xFFFFFFFF),
        };
        let fl = fl.span();
        let (mut new_pans, mut v): (Array<u8>, u32) = opaque((array![], 0));
        while v <= last_voice {
            let prog = *programs.at(v);
            let is_lead = v == 0
                || v == cs
                || (mega && v == dbl)
                || (arr.echo && v == ech)
                || prog == *fl.at(0)
                || prog == *fl.at(1)
                || prog == *fl.at(2)
                || prog == 50
                || prog == 65;
            let mut vol: u32 = if is_lead {
                64
            } else {
                127
            };
            if (prog == 12 || prog == 16 || prog == 19) && v <= max_voice && *counts.at(v) > 0 {
                let m: u64 = *sums.at(v) / *counts.at(v);
                let i: u32 = if m <= 52 {
                    0
                } else if m >= 64 {
                    12
                } else {
                    (m - 52).try_into().unwrap()
                };
                vol = (vol * *PLUCK_ABOVE_BASS_BP.span().at(i) + 5000) / 10000;
            }
            vols.append(vol.try_into().unwrap());
            let pan: u32 = (*pans.at(v)).into();
            new_pans.append(((pan + 65) / 2).try_into().unwrap());
            v += 1;
        }
        pans = new_pans;
    }

    let mut tempo = TrackWriterTrait::new();
    tempo.tempo(0, tempo_us);
    let mut tracks: Array<Array<u8>> = array![tempo.finish_at(length)];

    let mut v: u32 = opaque(0);
    while v <= last_voice {
        let ch: u8 = (v % 16).try_into().unwrap();
        let mut track = TrackWriterTrait::new();
        track.program(0, ch, *programs.at(v));
        track.control(0, ch, 10, *pans.at(v));
        if arr.balanced {
            track.control(0, ch, 7, *vols.at(v));
        }
        let mut any = false;
        if arr.echo && v == ech {
            any = echoed.len() > 0;
            write_notes(ref track, ch, echoed.span(), 0, 0);
        } else if mega && v == dbl {
            any = doubled.len() > 0;
            write_notes(ref track, ch, doubled.span(), 0, 0);
        } else {
            for r in runs.span() {
                if r.voice == v {
                    any = true;
                    // the lead's and the theme's grace notes
                    let (grace, salt): (u32, u32) = if v == lead || v == 0 {
                        (
                            arr.grace,
                            match voicing {
                                Option::Some(vc) => (vc.species_id % 100).try_into().unwrap(),
                                Option::None => 0,
                            },
                        )
                    } else {
                        (0, 0)
                    };
                    write_notes(ref track, ch, events.slice(r.start, r.len), grace, salt);
                }
            }
        }
        if any {
            tracks.append(track.finish());
        }
        v += 1;
    }
    if arr.drums {
        let drums = if arr.rock {
            rock_drum_track(length, sec)
        } else {
            drum_track(length, sec, tier, mega)
        };
        if drums.len() > 0 {
            tracks.append(drums);
        }
    }

    tracks
}

#[cfg(test)]
mod tests {
    use crate::composition::beast_score::BeastForm;
    use crate::composition::melodic_canon::NoteEvent;
    use super::{
        Arrangement, Voicing, beast_form_to_full_smf_bytes, beast_form_to_full_smf_bytes_arranged,
        beast_voice_programs, voice_setup,
    };

    fn note(voice: u32, k: u32, pitch: u8) -> NoteEvent {
        NoteEvent { time: k * 480, duration: 240, pitch, velocity: 90, voice_id: voice }
    }

    fn form(events: Array<NoteEvent>) -> BeastForm {
        BeastForm { events, score_hash: 0, section_count: 1, length_ticks: 3840 }
    }

    fn voicing(beast_type: u8, species_id: u64, name_variant_id: u32, voice_count: u32) -> Voicing {
        Voicing { beast_type, species_id, name_variant_id, voice_count, use_countersubject: true }
    }

    #[test]
    fn voice_setup_pans_the_present_voices_left_to_right() {
        let (programs, pans) = voice_setup(
            @form(array![note(0, 0, 60), note(2, 0, 50), note(3, 0, 40)]),
        );
        assert_eq!(programs, array![0, 0, 0, 0]);
        assert_eq!(pans, array![9, 64, 64, 118]);
        let (_, pans) = voice_setup(@form(array![note(0, 0, 60), note(1, 0, 50)]));
        assert_eq!(pans, array![9, 118]);
        let (programs, pans) = voice_setup(@form(array![note(1, 0, 50)]));
        assert_eq!(programs, array![0, 0]);
        assert_eq!(pans, array![64, 64]);
        let (programs, pans) = voice_setup(@form(array![]));
        assert_eq!(programs, array![0]);
        assert_eq!(pans, array![64]);
    }

    /// Voice 0 the theme, 1 and 3 followers of mean pitch 60 (tied with different counts: the lower
    /// id first), 2 a follower of 55 (the lowest), 4 the countersubject.
    fn five_voices() -> Array<NoteEvent> {
        array![
            note(0, 0, 70), note(1, 0, 60), note(2, 0, 55), note(3, 0, 58), note(3, 1, 62),
            note(4, 0, 50), note(2, 1, 55),
        ]
    }

    #[test]
    fn programs_by_role() {
        let events = five_voices();
        // family 1 (leads 2, 1, 8; plucks 12, 19, 6), species 4 leads with 1
        let even = beast_voice_programs(events.span(), 4, voicing(1, 4, 0, 4));
        assert_eq!(even, array![1, 19, 12, 6, 8]);
        // an odd name swaps the second and third pluck and the countersubject's lead
        let odd = beast_voice_programs(events.span(), 4, voicing(1, 4, 1, 4));
        assert_eq!(odd, array![1, 6, 12, 19, 2]);
        // without a countersubject voice 4 is a follower, the lowest of all
        let plain = Voicing { use_countersubject: false, ..voicing(1, 4, 0, 4) };
        assert_eq!(beast_voice_programs(events.span(), 4, plain), array![1, 6, 19, 6, 12]);
        // max_voice past the last voice adds absent voices, below it drops the higher ones
        assert_eq!(
            beast_voice_programs(events.span(), 6, voicing(1, 4, 0, 4)),
            array![1, 19, 12, 6, 8, 0, 0],
        );
        assert_eq!(beast_voice_programs(events.span(), 2, voicing(1, 4, 0, 4)), array![1, 19, 12]);
    }

    #[test]
    fn programs_countersubject_edge_cases() {
        let events = array![note(0, 0, 70), note(1, 0, 58)];
        // a countersubject id of 0 is the theme voice: it takes the countersubject's lead
        assert_eq!(beast_voice_programs(events.span(), 1, voicing(2, 0, 0, 0)), array![4, 16]);
        // a countersubject without notes is skipped
        assert_eq!(beast_voice_programs(events.span(), 1, voicing(2, 0, 0, 3)), array![3, 16]);
        // absent voices between keep VOICE_PROGRAM, the countersubject's too if it has no notes
        let gaps = array![note(0, 0, 70), note(2, 0, 58), note(5, 0, 50)];
        assert_eq!(
            beast_voice_programs(gaps.span(), 5, voicing(0, 2, 1, 1)), array![7, 0, 13, 0, 0, 15],
        );
    }

    /// Voices 0, 1 and 3 (2 absent) with four notes each, voice by voice.
    fn grouped() -> Array<NoteEvent> {
        let mut events = array![];
        for v in array![0_u32, 1, 3] {
            for k in 0..4_u32 {
                events.append(note(v, k, (40 + 7 * v + 3 * k).try_into().unwrap()));
            }
        }
        events
    }

    /// The same notes, a note of each voice in turn.
    fn interleaved() -> Array<NoteEvent> {
        let mut events = array![];
        for k in 0..4_u32 {
            for v in array![3_u32, 0, 1] {
                events.append(note(v, k, (40 + 7 * v + 3 * k).try_into().unwrap()));
            }
        }
        events
    }

    #[test]
    fn the_file_does_not_depend_on_the_order_of_the_voices_events() {
        let vc = voicing(1, 4, 1, 3);
        let plain = |
            events,
        | beast_form_to_full_smf_bytes(@form(events), 500000, 3, Option::Some(vc), false, 0);
        assert_eq!(plain(grouped()), plain(interleaved()));
        let mega = |
            events,
        | beast_form_to_full_smf_bytes_arranged(
            @form(events),
            500000,
            3,
            Option::Some(vc),
            true,
            1,
            Arrangement {
                top_lead: true,
                balanced: true,
                drums: true,
                rock: false,
                extra: Option::Some((3, 33)),
                programs: Option::None,
                echo: false,
                grace: 0,
            },
        );
        assert_eq!(mega(grouped()), mega(interleaved()));
    }
}

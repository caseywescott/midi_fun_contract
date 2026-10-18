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

/// The program every voice plays: TinyChip's Triangle Lead (bank 0) for now, until the preset set
/// and its orchestration are chosen.
pub const VOICE_PROGRAM: u8 = 0;

/// A maximal stretch of consecutive events of one voice: `events[start..start + len]` and the sum
/// of their pitches.
#[derive(Copy, Drop)]
struct VoiceRun {
    voice: u32,
    start: u32,
    len: u32,
    pitch_sum: u64,
}

/// The voice runs of `events`, in event order, from one pass. Events may come in any order (the
/// Genesis path voice by voice, v1.1 section by section), so a voice can have several runs; reading
/// a voice's runs in order reads its events in their original order.
fn voice_runs(events: Span<NoteEvent>) -> Array<VoiceRun> {
    let mut runs: Array<VoiceRun> = array![];
    let mut voice: u32 = 0;
    // felts, so no overflow checks per event, converted once per run (they fit: at most
    // events.len() events, of pitch at most 255)
    let mut start: felt252 = 0;
    let mut end: felt252 = 0;
    let mut pitch_sum: felt252 = 0;
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
fn voice_stats(runs: Span<VoiceRun>, max_voice: u32) -> (Array<u64>, Array<u64>) {
    let mut sums: Array<u64> = array![];
    let mut counts: Array<u64> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        let mut sum: u64 = 0;
        let mut n: u64 = 0;
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
    let mut programs: Array<u8> = array![];
    let mut v: u32 = 0;
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
fn fill_notes(f: u8) -> Span<(u32, u8, u8)> {
    if f == 0 {
        array![(0, 38, 88), (240, 38, 106)].span()
    } else if f == 1 {
        array![(0, 38, 72), (120, 38, 84), (240, 38, 96), (360, 38, 108)].span()
    } else if f == 2 {
        array![
            (0, 36, 100), (0, 38, 80), (240, 38, 88), (480, 38, 92), (600, 38, 100), (720, 38, 108),
            (840, 38, 116),
        ]
            .span()
    } else {
        array![
            (0, 50, 84), (120, 50, 88), (240, 48, 92), (360, 48, 96), (480, 47, 100),
            (600, 45, 104), (720, 43, 108), (840, 41, 112), (840, 36, 110),
        ]
            .span()
    }
}

/// The drum track body (channel 10, running status) for a form of `length` ticks in sections of
/// `sec`, ending with End-of-Track at `length`. Empty when there is nothing to play.
pub fn drum_track(length: u32, sec: u32, tier: u8, mega: bool) -> Array<u8> {
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
    let mut out: Array<u8> = array![];
    let mut v: u32 = 0;
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
}

/// The upper plucks' volume factor in basis points for a voice averaging MIDI 52 + i (i = 0..12;
/// above, 12): 10000 * 10^(-7 i / 480). Matches PLUCK_ABOVE_BASS_BP in full_midi.js.
const PLUCK_ABOVE_BASS_BP: [u32; 13] = [
    10000, 9670, 9350, 9042, 8743, 8454, 8175, 7905, 7644, 7392, 7148, 6912, 6683,
];

/// Each note of `notes` as a note on and a note off (velocity 64) on channel `ch`. Written as
/// messages with note_on's and note_off's status bytes: `ch` is below 16, so they need no
/// `channel % 16` per note.
fn write_notes(ref track: TrackWriter, ch: u8, notes: Span<NoteEvent>) {
    for e in notes {
        track.message(e.time, 0x90 + ch, e.pitch, e.velocity);
        track.message(e.time + e.duration, 0x80 + ch, e.pitch, 64);
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
        Option::Some((
            ev, prog,
        )) => {
            let mut next: Array<u8> = array![];
            let mut v: u32 = 0;
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
        let mut next: Array<u8> = array![];
        let mut v: u32 = 0;
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

    // the lead: the highest mean pitch (cross-multiplied), ties to the higher voice id
    let mut lead: u32 = 0;
    let mut lead_sum: u64 = 0;
    let mut lead_n: u64 = 0;
    let mut found = false;
    let mut v: u32 = 0;
    while v <= max_voice {
        let sum = *sums.at(v);
        let n = *counts.at(v);
        if n > 0 && v != extra_voice && (!found || sum * lead_n >= lead_sum * n) {
            lead = v;
            lead_sum = sum;
            lead_n = n;
            found = true;
        }
        v += 1;
    }
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
                    let mut used = false;
                    let mut u: u32 = 0;
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
    let mut programs: Array<u8> = array![];
    let mut pans: Array<u8> = array![];
    let mut v: u32 = 0;
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
    // mega: the lead an octave up on its own channel
    let dbl = max_voice + 1;
    let mut doubled: Array<NoteEvent> = array![];
    if mega {
        programs.append(*MEGA_LEADS.span().at(1 - lead_pick));
        let lp: u32 = (*base_pans.at(lead)).into();
        pans.append(if 128 - lp > 127 {
            127
        } else {
            (128 - lp).try_into().unwrap()
        });
        for r in runs.span() {
            if r.voice != lead {
                continue;
            }
            for e in events.slice(r.start, r.len) {
                if e.pitch + 12 <= 127 {
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
            }
        }
    }
    let last_voice = if mega {
        dbl
    } else {
        max_voice
    };
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
        let mut new_pans: Array<u8> = array![];
        let mut v: u32 = 0;
        while v <= last_voice {
            let prog = *programs.at(v);
            let is_lead = v == 0
                || v == cs
                || (mega && v == dbl)
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

    let mut v: u32 = 0;
    while v <= last_voice {
        let ch: u8 = (v % 16).try_into().unwrap();
        let mut track = TrackWriterTrait::new();
        track.program(0, ch, *programs.at(v));
        track.control(0, ch, 10, *pans.at(v));
        if arr.balanced {
            track.control(0, ch, 7, *vols.at(v));
        }
        let mut any = false;
        if v == dbl {
            any = doubled.len() > 0;
            write_notes(ref track, ch, doubled.span());
        } else {
            for r in runs.span() {
                if r.voice == v {
                    any = true;
                    write_notes(ref track, ch, events.slice(r.start, r.len));
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
            },
        );
        assert_eq!(mega(grouped()), mega(interleaved()));
    }
}

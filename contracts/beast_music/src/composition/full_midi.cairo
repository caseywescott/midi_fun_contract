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

use core::dict::{Felt252Dict, Felt252DictTrait};
use midi::smf::{TrackWriterTrait, smf_bytes};
use crate::composition::beast_score::BeastForm;
use crate::composition::melodic_canon::NoteEvent;

/// The program every voice plays: TinyChip's Triangle Lead (bank 0) for now, until the preset set
/// and its orchestration are chosen.
pub const VOICE_PROGRAM: u8 = 0;

/// (programs, pans) indexed by voice id 0..=max voice: every voice on `VOICE_PROGRAM`, the present
/// voices panned left to right in voice order (absent voices get 64).
pub fn voice_setup(form: @BeastForm) -> (Array<u8>, Array<u8>) {
    let events = form.events.span();
    let mut max_voice: u32 = 0;
    for e in events {
        if e.voice_id > max_voice {
            max_voice = e.voice_id;
        }
    }
    let mut present: Felt252Dict<bool> = Default::default();
    for e in events {
        present.insert(e.voice_id.into(), true);
    }
    let mut ids: Array<u32> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        if present.get(v.into()) {
            ids.append(v);
        }
        v += 1;
    }
    // pan across the present voices in voice order: floor((960 (n-1) + 10880 i) / (100 (n-1)))
    let mut pans: Felt252Dict<u8> = Default::default();
    let nv = ids.len();
    let mut i: u32 = 0;
    while i < nv {
        let pan: u32 = if nv < 2 {
            64
        } else {
            (960 * (nv - 1) + 10880 * i) / (100 * (nv - 1))
        };
        pans.insert((*ids.at(i)).into(), pan.try_into().unwrap());
        i += 1;
    }
    let mut out_p: Array<u8> = array![];
    let mut out_pan: Array<u8> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        out_p.append(VOICE_PROGRAM);
        out_pan.append(if present.get(v.into()) {
            pans.get(v.into())
        } else {
            64
        });
        v += 1;
    }
    (out_p, out_pan)
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
    let leads = family_leads(voicing.beast_type).span();
    let plucks = family_plucks(voicing.beast_type).span();
    let lead: u32 = (voicing.species_id % 3).try_into().unwrap();
    let name_odd = voicing.name_variant_id % 2 == 1;
    let cs: u32 = if voicing.use_countersubject {
        voicing.voice_count
    } else {
        0xFFFFFFFF
    };
    let mut sums: Array<u64> = array![];
    let mut counts: Array<u64> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        let mut sum: u64 = 0;
        let mut n: u64 = 0;
        for e in events {
            if e.voice_id == v {
                sum += e.pitch.into();
                n += 1;
            }
        }
        sums.append(sum);
        counts.append(n);
        v += 1;
    }
    // the followers, lowest mean pitch first (insertion order by voice id breaks ties)
    let mut followers: Array<u32> = array![];
    let mut v: u32 = 1;
    while v <= max_voice {
        if v != cs && *counts.at(v) > 0 {
            followers.append(v);
        }
        v += 1;
    }
    let mut sorted: Array<u32> = array![];
    let mut placed: Felt252Dict<bool> = Default::default();
    let nf = followers.len();
    let mut k: u32 = 0;
    while k < nf {
        let mut best: u32 = 0;
        let mut have = false;
        for f in followers.span() {
            let f = *f;
            if placed.get(f.into()) {
                continue;
            }
            if !have {
                best = f;
                have = true;
            } else {
                let lhs = *sums.at(f) * *counts.at(best);
                let rhs = *sums.at(best) * *counts.at(f);
                if lhs < rhs || (lhs == rhs && f < best) {
                    best = f;
                }
            }
        }
        placed.insert(best.into(), true);
        sorted.append(best);
        k += 1;
    }
    let mut programs: Felt252Dict<u8> = Default::default();
    let mut assigned: Felt252Dict<bool> = Default::default();
    programs.insert(0, *leads.at(lead));
    assigned.insert(0, true);
    if voicing.use_countersubject && cs <= max_voice && *counts.at(cs) > 0 {
        let pick = (lead + 1 + if name_odd {
            1
        } else {
            0
        }) % 3;
        programs.insert(cs.into(), *leads.at(pick));
        assigned.insert(cs.into(), true);
    }
    let mut i: u32 = 0;
    for f in sorted.span() {
        let prog = if i == 0 {
            *plucks.at(0)
        } else if (i == 1) != name_odd {
            *plucks.at(1)
        } else {
            *plucks.at(2)
        };
        programs.insert((*f).into(), prog);
        assigned.insert((*f).into(), true);
        i += 1;
    }
    let mut out: Array<u8> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        out.append(if assigned.get(v.into()) {
            programs.get(v.into())
        } else {
            VOICE_PROGRAM
        });
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
/// upper plucks softer above the bass) and `drums` (the drum track, or none).
#[derive(Copy, Drop)]
pub struct Arrangement {
    pub top_lead: bool,
    pub balanced: bool,
    pub drums: bool,
}

/// The upper plucks' volume factor in basis points for a voice averaging MIDI 52 + i (i = 0..12;
/// above, 12): 10000 * 10^(-7 i / 480). Matches PLUCK_ABOVE_BASS_BP in full_midi.js.
const PLUCK_ABOVE_BASS_BP: [u32; 13] = [
    10000, 9670, 9350, 9042, 8743, 8454, 8175, 7905, 7644, 7392, 7148, 6912, 6683,
];

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
        Arrangement { top_lead: false, balanced: false, drums: true },
    )
}

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
    let events = form.events.span();
    let (placeholder, base_pans) = voice_setup(form);
    let max_voice: u32 = placeholder.len() - 1;
    // instruments by Beast, or VOICE_PROGRAM on every voice
    let base_programs = match voicing {
        Option::Some(vc) => beast_voice_programs(events, max_voice, vc),
        Option::None => placeholder,
    };
    let length = form.length_ticks;
    let sections: u32 = form.section_count.into();
    let sec = length / sections;

    // the lead: the highest mean pitch (cross-multiplied), ties to the higher voice id
    let mut lead: u32 = 0;
    let mut lead_sum: u64 = 0;
    let mut lead_n: u64 = 0;
    let mut found = false;
    let mut sums: Array<u64> = array![];
    let mut counts: Array<u64> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        let mut sum: u64 = 0;
        let mut n: u64 = 0;
        for e in events {
            if e.voice_id == v {
                sum += e.pitch.into();
                n += 1;
            }
        }
        sums.append(sum);
        counts.append(n);
        if n > 0 && (!found || sum * lead_n >= lead_sum * n) {
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
        for e in events {
            if e.voice_id == lead && e.pitch + 12 <= 127 {
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
        let source = if v == dbl {
            doubled.span()
        } else {
            events
        };
        for e in source {
            if e.voice_id == v {
                any = true;
                track.note_on(e.time, ch, e.pitch, e.velocity);
                track.note_off(e.time + e.duration, ch, e.pitch, 64);
            }
        }
        if any {
            tracks.append(track.finish());
        }
        v += 1;
    }
    if arr.drums {
        let drums = drum_track(length, sec, tier, mega);
        if drums.len() > 0 {
            tracks.append(drums);
        }
    }

    smf_bytes(1, 480, tracks.span())
}

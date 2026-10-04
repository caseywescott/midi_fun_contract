//! Self-contained Beast MIDI for a generic player (onchain-tinysynth plays a file exactly as
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

/// The program every voice plays: TinyChip's Triangle Lead (bank 0) for now, until the preset set
/// and its orchestration are chosen.
pub const VOICE_PROGRAM: u8 = 0;

/// (programs, pans) indexed by voice id 0..=max voice: every voice on `VOICE_PROGRAM`, the present
/// voices panned left to right in voice order (absent voices get 64).
pub fn voice_setup(form: @BeastForm) -> (Array<u8>, Array<u8>) {
    let events = form.events.span();
    let mut max_voice: u32 = 0;
    for e in events {
        if *e.voice_id > max_voice {
            max_voice = *e.voice_id;
        }
    }
    let mut present: Felt252Dict<bool> = Default::default();
    for e in events {
        present.insert((*e.voice_id).into(), true);
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
            (0, 36, 100),
            (0, 38, 80),
            (240, 38, 88),
            (480, 38, 92),
            (600, 38, 100),
            (720, 38, 108),
            (840, 38, 116),
        ]
            .span()
    } else {
        array![
            (0, 50, 84),
            (120, 50, 88),
            (240, 48, 92),
            (360, 48, 96),
            (480, 47, 100),
            (600, 45, 104),
            (720, 43, 108),
            (840, 41, 112),
            (840, 36, 110),
        ]
            .span()
    }
}

/// The drum track body (channel 10, running status) for a form of `length` ticks in sections of
/// `sec`, ending with End-of-Track at `length`. Empty when there is nothing to play.
pub fn drum_track(length: u32, sec: u32, tier: u8) -> Array<u8> {
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
        if f == 3 && rel == 0 {
            hits.append((49, 76));
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

/// The whole self-contained file: tempo track (End-of-Track at the form length), one track per
/// voice (program and pan at tick 0, then the notes), and the drum track.
pub fn beast_form_to_full_smf_bytes(form: @BeastForm, tempo_us: u32, tier: u8) -> Array<u8> {
    let events = form.events.span();
    let (programs, pans) = voice_setup(form);
    let max_voice: u32 = programs.len() - 1;
    let length = *form.length_ticks;
    let sections: u32 = (*form.section_count).into();
    let sec = length / sections;

    let mut tempo = TrackWriterTrait::new();
    tempo.tempo(0, tempo_us);
    let mut tracks: Array<Array<u8>> = array![tempo.finish_at(length)];

    let mut v: u32 = 0;
    while v <= max_voice {
        let ch: u8 = (v % 16).try_into().unwrap();
        let mut track = TrackWriterTrait::new();
        track.program(0, ch, *programs.at(v));
        track.control(0, ch, 10, *pans.at(v));
        let mut any = false;
        for e in events {
            if *e.voice_id == v {
                any = true;
                track.note_on(*e.time, ch, *e.pitch, *e.velocity);
                track.note_off(*e.time + *e.duration, ch, *e.pitch, 64);
            }
        }
        if any {
            tracks.append(track.finish());
        }
        v += 1;
    }
    let drums = drum_track(length, sec, tier);
    if drums.len() > 0 {
        tracks.append(drums);
    }

    smf_bytes(1, 480, tracks.span())
}

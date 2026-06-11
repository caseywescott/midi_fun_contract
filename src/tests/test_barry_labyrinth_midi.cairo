//! Barry Harris v2 labyrinth MIDI demos.
//! Export: `./scripts/generate_barry_labyrinth_demo_midis.sh`

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::barry_elevators::{generate_elevator_path, ElevatorDirection};
use koji::composition::barry_harris::{
    initial_harmonic_state, stable_chord_tones, voicelead, ChordFamily, HarmonicState,
};
use koji::composition::barry_labyrinth::{
    generate_barry_labyrinth_phrase, BarryTurnaroundKind, BarryVoicingStyle, VoiceMotionPolicy,
};
use koji::composition::barry_line_cells::realize_line_cell;
use koji::composition::barry_profiles::BarryRuleProfile;
use koji::composition::barry_turnarounds::{
    generate_barry_turnaround, turnaround_step_to_harmonic_state,
};
use koji::composition::barry_v2_types::BarryLineCell;
use koji::composition::barry_voicing_styles::realize_voicing_style;
use koji::composition::melodic_canon::NoteEvent;
use koji::math::Time;
use koji::midi::output::output_midi_object;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

const STEP_US: u64 = 480000;
const GRID: u32 = 4;
const LO: i16 = 48;
const HI: i16 = 72;

fn append_legato(
    ref events: Array<Message>, ch: u8, note: u8, vel: u8, on: Time, off: Time,
) {
    events.append(Message::NOTE_ON(NoteOn { channel: ch, note, velocity: vel, time: on }));
    events.append(Message::NOTE_OFF(NoteOff { channel: ch, note, velocity: 64, time: off }));
}

fn append_notes(ref events: Array<Message>, notes: @Array<NoteEvent>, step_us: u64) -> u32 {
    let mut n: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= notes.len() {
            break;
        }
        let e = notes.at(i);
        let on: Time = (*e.time).into() * step_us;
        let off = on + (*e.duration).into() * step_us;
        append_legato(
            ref events, (*e.voice_id).try_into().unwrap(), *e.pitch, *e.velocity, on, off,
        );
        n += 1;
        i += 1;
    };
    n
}

fn export_midi(notes: @Array<NoteEvent>, min_notes: u32) {
    let mut events = ArrayTrait::<Message>::new();
    events.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
    let n = append_notes(ref events, notes, STEP_US);
    assert(n >= min_notes, 'note count');
    let midi = Midi { events: events.span() };
    export_parser(@midi);
    assert(output_midi_object(@midi).len() >= 22, 'midi bytes');
}

fn export_parser(midi: @Midi) {
    let mut ev = midi.clone().events;
    loop {
        match ev.pop_front() {
            Option::Some(currentevent) => {
                match currentevent {
                    Message::NOTE_ON(NoteOn) => {
                        println!(
                            "Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                            *NoteOn.channel, *NoteOn.note, *NoteOn.velocity, *NoteOn.time,
                        );
                    },
                    Message::NOTE_OFF(NoteOff) => {
                        println!(
                            "Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                            *NoteOff.channel, *NoteOff.note, *NoteOff.velocity, *NoteOff.time,
                        );
                    },
                    Message::SET_TEMPO(SetTempo) => {
                        match *SetTempo.time {
                            Option::Some(t) => {
                                println!(
                                    "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }})",
                                    *SetTempo.tempo, t,
                                );
                            },
                            Option::None(_) => {
                                println!(
                                    "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::None }})",
                                    *SetTempo.tempo,
                                );
                            },
                        };
                    },
                    _ => {},
                }
            },
            Option::None(_) => {
                break;
            },
        }
    }
}

fn clone_i16(src: Span<i16>) -> Array<i16> {
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= src.len() {
            break;
        }
        out.append(*src.at(i));
        i += 1;
    };
    out
}

fn elevator_notes(direction: ElevatorDirection, steps: u8) -> Array<NoteEvent> {
    let start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let path = generate_elevator_path(start, direction, steps);
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut prev: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= path.len() {
            break;
        }
        let st = path.at(i);
        let mut pcs: Array<u8> = ArrayTrait::new();
        let mut pi: usize = 0;
        loop {
            if pi >= st.active_pcs.len() {
                break;
            }
            pcs.append(*st.active_pcs.at(pi));
            pi += 1;
        };
        let voiced = voicelead(prev.span(), pcs.span(), LO, HI, i.try_into().unwrap());
        prev = clone_i16(voiced.span());
        let time: u32 = i.try_into().unwrap() * GRID;
        let mut v: usize = 0;
        loop {
            if v >= voiced.len() {
                break;
            }
            let kn = *voiced.at(v);
            out.append(
                NoteEvent {
                    time,
                    duration: GRID,
                    pitch: kn.try_into().unwrap(),
                    velocity: 80,
                    voice_id: v.try_into().unwrap(),
                },
            );
            v += 1;
        };
        i += 1;
    };
    out
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_01_elevator_up_midi_test() {
    export_midi(@elevator_notes(ElevatorDirection::Up, 9), 9);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_02_elevator_down_midi_test() {
    export_midi(@elevator_notes(ElevatorDirection::Down, 9), 9);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_03_contrary_motion_midi_test() {
    let seed: felt252 = 0xB200_0000_0300_0003;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 24, BarryRuleProfile::BebopLine, LO, HI,
    );
    export_midi(@phrase.note_events, 24);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_04_enclosure_line_midi_test() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let path = realize_line_cell(BarryLineCell::EnclosureUpperLower, 0, state, 1);
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut prev: i16 = 60;
    let mut j: usize = 0;
    loop {
        if j >= path.len() {
            break;
        }
        let pc = *path.at(j);
        let kn = voicelead(array![prev].span(), array![pc].span(), LO, HI, j.try_into().unwrap());
        prev = *kn.at(0);
        out.append(
            NoteEvent {
                time: j.try_into().unwrap(),
                duration: 1,
                pitch: prev.try_into().unwrap(),
                velocity: 80,
                voice_id: 0,
            },
        );
        j += 1;
    };
    export_midi(@out, 3);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_05_neighbor_borrowing_midi_test() {
    let seed: felt252 = 0xB200_0000_0500_0005;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 20, BarryRuleProfile::BebopLine, LO, HI,
    );
    export_midi(@phrase.note_events, 10);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_06_drop_two_block_midi_test() {
    let pcs = array![0_u8, 4, 7, 11];
    let voiced = realize_voicing_style(
        pcs.span(), array![48_i16, 55, 60, 67].span(), LO, HI,
        BarryVoicingStyle::DropTwo, VoiceMotionPolicy::MinimalMotion, 0,
    );
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut v: usize = 0;
    loop {
        if v >= voiced.len() {
            break;
        }
        out.append(
            NoteEvent {
                time: 0,
                duration: GRID,
                pitch: (*voiced.at(v)).try_into().unwrap(),
                velocity: 80,
                voice_id: v.try_into().unwrap(),
            },
        );
        v += 1;
    };
    export_midi(@out, 4);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_07_barry_turnaround_midi_test() {
    let steps = generate_barry_turnaround(0, BarryTurnaroundKind::SixToTwoFive, 16);
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut prev: Array<i16> = ArrayTrait::new();
    let mut t: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        let step = steps.at(i);
        if *step.duration_steps == 0 {
            i += 1;
            continue;
        }
        let hs = turnaround_step_to_harmonic_state(*step, 0);
        let pcs = stable_chord_tones(@hs);
        let voiced = voicelead(prev.span(), pcs.span(), LO, HI, i.try_into().unwrap());
        prev = clone_i16(voiced.span());
        let mut v: usize = 0;
        loop {
            if v >= voiced.len() {
                break;
            }
            out.append(
                NoteEvent {
                    time: t,
                    duration: GRID,
                    pitch: (*voiced.at(v)).try_into().unwrap(),
                    velocity: 80,
                    voice_id: v.try_into().unwrap(),
                },
            );
            v += 1;
        };
        t += (*step.duration_steps).into() * GRID;
        i += 1;
    };
    export_midi(@out, 8);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_08_limitations_only_elevators_midi_test() {
    let seed: felt252 = 0xB200_0000_0800_0008;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 16, BarryRuleProfile::Conservative, LO, HI,
    );
    export_midi(@phrase.note_events, 8);
}

#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_labyrinth_09_limitations_no_leaps_midi_test() {
    let seed: felt252 = 0xB200_0000_0900_0009;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 16, BarryRuleProfile::BebopLine, LO, HI,
    );
    export_midi(@phrase.note_events, 8);
}

#[ignore]
#[test]
#[available_gas(6000000000000)]
fn barry_labyrinth_10_mixed_labyrinth_phrase_midi_test() {
    let seed: felt252 = 0xB200_0000_0A00_00AA;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 32, BarryRuleProfile::BebopLine, LO, HI,
    );
    export_midi(@phrase.note_events, 16);
}

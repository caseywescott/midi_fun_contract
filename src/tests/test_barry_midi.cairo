//! Barry Harris 6th-diminished harmony MIDI demos.
//! Export: `./scripts/generate_barry_harris_demo_midis.sh`

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    barry_phrase_to_note_events, generate_barry_phrase, ChordFamily,
};
use koji::composition::barry_profiles::BarryRuleProfile;
use koji::composition::melodic_canon::NoteEvent;
use koji::math::Time;
use koji::midi::output::output_midi_object;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

const BARRY_STEP_US: u64 = 480000;
const BARRY_GRID_UNIT: u32 = 4;
const BARRY_GAP_US: u64 = 1200000;
const BARRY_REGISTER_LO: i16 = 48;
const BARRY_REGISTER_HI: i16 = 72;
const BARRY_MARKER_CH: u8 = 9;

fn append_legato_note(
    ref eventlist: Array<Message>,
    channel: u8,
    note: u8,
    velocity: u8,
    on_time: Time,
    off_time: Time,
) {
    eventlist.append(Message::NOTE_ON(NoteOn { channel, note, velocity, time: on_time }));
    eventlist.append(Message::NOTE_OFF(NoteOff { channel, note, velocity: 64, time: off_time }));
}

fn append_messages(ref target: Array<Message>, mut src: Array<Message>) {
    loop {
        match src.pop_front() {
            Option::Some(m) => {
                target.append(m);
            },
            Option::None(_) => {
                break;
            },
        }
    }
}

fn assert_valid_demo_midi(midiobj: @Midi, min_note_ons: u32) {
    let mut ev = midiobj.clone().events;
    let mut note_on_count: u32 = 0;
    loop {
        match ev.pop_front() {
            Option::Some(msg) => {
                match msg {
                    Message::NOTE_ON(_) => {
                        note_on_count += 1;
                    },
                    _ => {},
                }
            },
            Option::None(_) => {
                break;
            },
        }
    }
    assert(note_on_count >= min_note_ons, 'note on count');
    let binary = output_midi_object(midiobj);
    assert(binary.len() >= 22, 'MIDI too short');
}

fn generate_parser_format(midiobj: @Midi) {
    let mut ev = midiobj.clone().events;
    loop {
        match ev.pop_front() {
            Option::Some(currentevent) => {
                match currentevent {
                    Message::NOTE_ON(NoteOn) => {
                        println!(
                            "Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                            *NoteOn.channel,
                            *NoteOn.note,
                            *NoteOn.velocity,
                            *NoteOn.time,
                        );
                    },
                    Message::NOTE_OFF(NoteOff) => {
                        println!(
                            "Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                            *NoteOff.channel,
                            *NoteOff.note,
                            *NoteOff.velocity,
                            *NoteOff.time,
                        );
                    },
                    Message::SET_TEMPO(SetTempo) => {
                        match *SetTempo.time {
                            Option::Some(time_val) => {
                                println!(
                                    "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }})",
                                    *SetTempo.tempo,
                                    time_val,
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

fn append_barry_note_events(
    ref eventlist: Array<Message>,
    events: @Array<NoteEvent>,
    time_offset_us: u64,
    step_us: u64,
) -> u32 {
    let mut note_ons: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = events.at(i);
        let on: Time = time_offset_us + (*e.time).into() * step_us;
        let off: Time = on + (*e.duration).into() * step_us;
        let channel: u8 = (*e.voice_id).try_into().unwrap();
        append_legato_note(ref eventlist, channel, *e.pitch, *e.velocity, on, off);
        note_ons += 1;
        i += 1;
    };
    note_ons
}

fn phrase_duration_us(steps: u32, step_us: u64) -> u64 {
    (steps * BARRY_GRID_UNIT).into() * step_us
}

fn export_barry_phrase_midi(
    seed: felt252,
    tonic_pc: u8,
    family: ChordFamily,
    steps: u32,
    profile: BarryRuleProfile,
    step_us: u64,
) -> u32 {
    let phrase = generate_barry_phrase(
        seed,
        tonic_pc,
        family,
        steps,
        profile,
        BARRY_REGISTER_LO,
        BARRY_REGISTER_HI,
    );
    assert(phrase.states.len() == steps, 'phrase steps');
    let events = barry_phrase_to_note_events(@phrase, BARRY_GRID_UNIT);
    assert(events.len() > 0, 'barry events');

    let mut eventlist = ArrayTrait::<Message>::new();
    eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
    let n = append_barry_note_events(ref eventlist, @events, 0, step_us);
    let midiobj = Midi { events: eventlist.span() };
    generate_parser_format(@midiobj);
    assert_valid_demo_midi(@midiobj, n);
    n
}

fn append_marker(ref eventlist: Array<Message>, at_us: u64) {
    append_legato_note(ref eventlist, BARRY_MARKER_CH, 72, 90, at_us, at_us + 80000);
}

/// C major 6th-dim field, conservative profile (32 steps).
/// Export: `scarb test -- --filter barry_harris_conservative_c_major_midi_test`
#[ignore]
#[test]
#[available_gas(4000000000000)]
fn barry_harris_conservative_c_major_midi_test() {
    let n = export_barry_phrase_midi(
        12345,
        0,
        ChordFamily::Major6Dim,
        32,
        BarryRuleProfile::Conservative,
        BARRY_STEP_US,
    );
    assert(n >= 32, 'conservative notes');
}

/// Bebop-line profile with scale steps and chromatic approaches (48 steps).
/// Export: `scarb test -- --filter barry_harris_bebop_line_midi_test`
#[ignore]
#[test]
#[available_gas(6000000000000)]
fn barry_harris_bebop_line_midi_test() {
    let n = export_barry_phrase_midi(
        54321,
        0,
        ChordFamily::Major6Dim,
        48,
        BarryRuleProfile::BebopLine,
        BARRY_STEP_US,
    );
    assert(n >= 48, 'bebop notes');
}

/// Diminished-heavy profile — connector emphasis (40 steps).
/// Export: `scarb test -- --filter barry_harris_diminished_heavy_midi_test`
#[ignore]
#[test]
#[available_gas(5000000000000)]
fn barry_harris_diminished_heavy_midi_test() {
    let n = export_barry_phrase_midi(
        77777,
        0,
        ChordFamily::Major6Dim,
        40,
        BarryRuleProfile::DiminishedHeavy,
        BARRY_STEP_US,
    );
    assert(n >= 40, 'dim heavy notes');
}

/// C minor 6th-dim field (36 steps).
/// Export: `scarb test -- --filter barry_harris_minor_field_midi_test`
#[ignore]
#[test]
#[available_gas(5000000000000)]
fn barry_harris_minor_field_midi_test() {
    let n = export_barry_phrase_midi(
        20260409,
        0,
        ChordFamily::Minor6Dim,
        36,
        BarryRuleProfile::BebopLine,
        BARRY_STEP_US,
    );
    assert(n >= 36, 'minor field notes');
}

/// G dominant 7th-dim field (36 steps).
/// Export: `scarb test -- --filter barry_harris_dominant_field_midi_test`
#[ignore]
#[test]
#[available_gas(5000000000000)]
fn barry_harris_dominant_field_midi_test() {
    let n = export_barry_phrase_midi(
        30303030,
        7,
        ChordFamily::Dominant7Dim,
        36,
        BarryRuleProfile::MediaLoop,
        BARRY_STEP_US,
    );
    assert(n >= 36, 'dominant field notes');
}

/// Five profiles back-to-back on C major — listening tour.
/// Export: `scarb test -- --filter barry_harris_profile_showcase_midi_test`
#[ignore]
#[test]
#[available_gas(12000000000000)]
fn barry_harris_profile_showcase_midi_test() {
    let steps: u32 = 24;
    let mut eventlist = ArrayTrait::<Message>::new();
    eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

    let seeds: Array<felt252> = array![1111, 2222, 3333, 4444, 5555];
    let profiles: Array<BarryRuleProfile> = array![
        BarryRuleProfile::Conservative,
        BarryRuleProfile::BebopLine,
        BarryRuleProfile::DenseBlockChords,
        BarryRuleProfile::DiminishedHeavy,
        BarryRuleProfile::MediaLoop,
    ];

    let mut offset_us: u64 = 0;
    let mut total: u32 = 0;
    let mut si: u32 = 0;
    loop {
        if si >= seeds.len() {
            break;
        }
        let seed = *seeds.at(si);
        let profile = *profiles.at(si);
        let phrase = generate_barry_phrase(
            seed,
            0,
            ChordFamily::Major6Dim,
            steps,
            profile,
            BARRY_REGISTER_LO,
            BARRY_REGISTER_HI,
        );
        let events = barry_phrase_to_note_events(@phrase, BARRY_GRID_UNIT);
        total += append_barry_note_events(ref eventlist, @events, offset_us, BARRY_STEP_US);
        offset_us += phrase_duration_us(steps, BARRY_STEP_US);
        append_marker(ref eventlist, offset_us);
        offset_us += BARRY_GAP_US;
        si += 1;
    };

    let midiobj = Midi { events: eventlist.span() };
    generate_parser_format(@midiobj);
    assert_valid_demo_midi(@midiobj, total);
    assert(total >= steps * 5, 'showcase notes');
}

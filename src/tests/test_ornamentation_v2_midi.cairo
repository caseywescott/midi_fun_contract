//! v2 ornamentation showcase MIDI demos — one example per ornament kind.
//! Export: `./scripts/generate_ornamentation_v2_demo_midis.sh`

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::ornamentation_v2::canon::v2_note_to_legacy;
use koji::composition::ornamentation_v2::showcase::{
    showcase_catalog_events, showcase_events_for_kind, showcase_kind_ids,
};
use koji::composition::ornamentation_v2::types::{
    ORN_ACCIACCATURA_LOWER, ORN_ACCIACCATURA_UPPER, ORN_ANTICIPATION, ORN_APPOGGIATURA_LOWER,
    ORN_APPOGGIATURA_UPPER, ORN_ARPEGGIATION_DOWN, ORN_ARPEGGIATION_UP, ORN_CAMBIATA,
    ORN_CHROMATIC_APPROACH_LOWER, ORN_CHROMATIC_APPROACH_UPPER, ORN_DOUBLE_NEIGHBOR_LF,
    ORN_DOUBLE_NEIGHBOR_UF, ORN_ECHAPPEE_LOWER, ORN_ECHAPPEE_UPPER, ORN_ENCLOSURE_LF,
    ORN_ENCLOSURE_UF, ORN_ESCAPE_LOWER, ORN_ESCAPE_UPPER, ORN_MORDENT_LOWER, ORN_MORDENT_UPPER,
    ORN_NEIGHBOR_LOWER, ORN_NEIGHBOR_UPPER, ORN_PASSING_ASC, ORN_PASSING_DESC, ORN_PEDAL_HOLD,
    ORN_RETARDATION, ORN_SUSPENSION_23_BASS, ORN_SUSPENSION_43, ORN_SUSPENSION_65,
    ORN_SUSPENSION_76, ORN_SUSPENSION_98, ORN_TRILL_LOWER, ORN_TRILL_UPPER, ORN_TURN_LOWER,
    ORN_TURN_UPPER,
};
use koji::math::Time;
use koji::midi::output::output_midi_object;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

const V2_STEP_US: u64 = 250000;
const V2_CATALOG_GAP_TICKS: u32 = 8;

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

fn append_v2_events(
    ref eventlist: Array<Message>, events: Span<koji::composition::ornamentation_v2::types::V2NoteEvent>,
) -> u32 {
    let mut note_ons: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let legacy = v2_note_to_legacy(*events.at(i));
        let on: Time = legacy.time.into() * V2_STEP_US;
        let off: Time = on + legacy.duration.into() * V2_STEP_US;
        let channel: u8 = if legacy.voice_id > 255 {
            0_u8
        } else {
            legacy.voice_id.try_into().unwrap()
        };
        append_legato_note(ref eventlist, channel, legacy.pitch, legacy.velocity, on, off);
        note_ons += 1;
        i += 1;
    };
    note_ons
}

fn run_showcase_midi_test(kind: u8, min_notes: u32) -> u32 {
    let events = showcase_events_for_kind(kind);
    assert(events.len() >= min_notes, 'showcase empty');
    let mut eventlist = ArrayTrait::<Message>::new();
    eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
    let n = append_v2_events(ref eventlist, events.span());
    let midiobj = Midi { events: eventlist.span() };
    generate_parser_format(@midiobj);
    assert_valid_demo_midi(@midiobj, min_notes);
    n
}

#[ignore]
#[test]
#[available_gas(2000000000000)]
fn ornament_v2_catalog_all_kinds_midi_test() {
    let events = showcase_catalog_events(V2_CATALOG_GAP_TICKS);
    assert(events.len() >= 35, 'catalog has events');
    let mut eventlist = ArrayTrait::<Message>::new();
    eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
    let n = append_v2_events(ref eventlist, events.span());
    assert(n >= 35, 'catalog note ons');
    let midiobj = Midi { events: eventlist.span() };
    generate_parser_format(@midiobj);
    assert_valid_demo_midi(@midiobj, 35);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_01_passing_asc_midi_test() {
    run_showcase_midi_test(ORN_PASSING_ASC, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_02_passing_desc_midi_test() {
    run_showcase_midi_test(ORN_PASSING_DESC, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_03_neighbor_upper_midi_test() {
    run_showcase_midi_test(ORN_NEIGHBOR_UPPER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_04_neighbor_lower_midi_test() {
    run_showcase_midi_test(ORN_NEIGHBOR_LOWER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_05_double_neighbor_uf_midi_test() {
    run_showcase_midi_test(ORN_DOUBLE_NEIGHBOR_UF, 4);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_06_double_neighbor_lf_midi_test() {
    run_showcase_midi_test(ORN_DOUBLE_NEIGHBOR_LF, 4);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_07_anticipation_midi_test() {
    run_showcase_midi_test(ORN_ANTICIPATION, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_08_suspension_43_midi_test() {
    run_showcase_midi_test(ORN_SUSPENSION_43, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_09_suspension_76_midi_test() {
    run_showcase_midi_test(ORN_SUSPENSION_76, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_10_suspension_98_midi_test() {
    run_showcase_midi_test(ORN_SUSPENSION_98, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_11_suspension_65_midi_test() {
    run_showcase_midi_test(ORN_SUSPENSION_65, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_12_suspension_23_bass_midi_test() {
    run_showcase_midi_test(ORN_SUSPENSION_23_BASS, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_13_retardation_midi_test() {
    run_showcase_midi_test(ORN_RETARDATION, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_14_appoggiatura_upper_midi_test() {
    run_showcase_midi_test(ORN_APPOGGIATURA_UPPER, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_15_appoggiatura_lower_midi_test() {
    run_showcase_midi_test(ORN_APPOGGIATURA_LOWER, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_16_escape_upper_midi_test() {
    run_showcase_midi_test(ORN_ESCAPE_UPPER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_17_escape_lower_midi_test() {
    run_showcase_midi_test(ORN_ESCAPE_LOWER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_18_echappee_upper_midi_test() {
    run_showcase_midi_test(ORN_ECHAPPEE_UPPER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_19_echappee_lower_midi_test() {
    run_showcase_midi_test(ORN_ECHAPPEE_LOWER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_20_cambiata_midi_test() {
    run_showcase_midi_test(ORN_CAMBIATA, 5);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_21_mordent_upper_midi_test() {
    run_showcase_midi_test(ORN_MORDENT_UPPER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_22_mordent_lower_midi_test() {
    run_showcase_midi_test(ORN_MORDENT_LOWER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_23_turn_upper_midi_test() {
    run_showcase_midi_test(ORN_TURN_UPPER, 4);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_24_turn_lower_midi_test() {
    run_showcase_midi_test(ORN_TURN_LOWER, 4);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_25_trill_upper_midi_test() {
    run_showcase_midi_test(ORN_TRILL_UPPER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_26_trill_lower_midi_test() {
    run_showcase_midi_test(ORN_TRILL_LOWER, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_27_acciaccatura_upper_midi_test() {
    run_showcase_midi_test(ORN_ACCIACCATURA_UPPER, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_28_acciaccatura_lower_midi_test() {
    run_showcase_midi_test(ORN_ACCIACCATURA_LOWER, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_29_chromatic_approach_upper_midi_test() {
    run_showcase_midi_test(ORN_CHROMATIC_APPROACH_UPPER, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_30_chromatic_approach_lower_midi_test() {
    run_showcase_midi_test(ORN_CHROMATIC_APPROACH_LOWER, 2);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_31_enclosure_uf_midi_test() {
    run_showcase_midi_test(ORN_ENCLOSURE_UF, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_32_enclosure_lf_midi_test() {
    run_showcase_midi_test(ORN_ENCLOSURE_LF, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_33_arpeggiation_up_midi_test() {
    run_showcase_midi_test(ORN_ARPEGGIATION_UP, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_34_arpeggiation_down_midi_test() {
    run_showcase_midi_test(ORN_ARPEGGIATION_DOWN, 3);
}

#[ignore]
#[test]
#[available_gas(400000000000)]
fn ornament_v2_35_pedal_hold_midi_test() {
    run_showcase_midi_test(ORN_PEDAL_HOLD, 1);
}

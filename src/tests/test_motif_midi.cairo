//! MIDI demo: theme + seed-driven motif development variations.
//! Export: `./scripts/generate_motif_demo_midis.sh`

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::melodic_canon::{
    NoteEvent, canon_to_ornamented_note_events,
};
use koji::composition::melodic_motion::ORN_FILL_MIN_STEP;
use koji::composition::motif_algebra::{
    apply_program, developed_to_note_events, developed_to_ornamented_note_events,
    generate_developed_line, generate_ornamented_canon_from_developed, grundgestalt_theme,
    long_demo_developed_motif, program_from_seed, DevelopedMotif, MotifProgram,
};
use koji::math::Time;
use koji::midi::output::output_midi_object;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

const DEMO_STEP_US: u64 = 280000;
const DEMO_GAP_US: u64 = 600000;
const DEMO_MARKER_CH: u8 = 9;
const DEMO_THEME_CH: u8 = 0;
const DEMO_VAR_CH: u8 = 1;
const DEMO_TONIC: u8 = 60;
const DEMO_MODE: u8 = 0;

const LONG_STEP_US: u64 = 250000;
const LONG_SECTION_GAP_US: u64 = 800000;
const LONG_CANON_CONFIG: u32 = 0;
const LONG_CANON_LOOPS: u32 = 2;
const LONG_DEMO_SEED: felt252 = 880808;
const LONG_ORNAMENT_SEED: u32 = 42;

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

fn note_events_to_midi(
    events: @Array<NoteEvent>, channel: u8, time_offset_us: u64, step_us: u64,
) -> Array<Message> {
    let mut out: Array<Message> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let ev = events.at(i);
        let on_us = time_offset_us + (*ev.time).into() * step_us;
        let off_us = on_us + (*ev.duration).into() * step_us;
        append_legato_note(
            ref out,
            channel,
            *ev.pitch,
            *ev.velocity,
            on_us,
            off_us,
        );
        i += 1;
    };
    out
}

fn developed_duration_units(m: @DevelopedMotif) -> u32 {
    let mut total: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= m.degrees.len() {
            break;
        }
        total += if m.durations.len() > 0 {
            *m.durations.at(i % m.durations.len())
        } else {
            1
        };
        i += 1;
    };
    total
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

fn append_marker(ref eventlist: Array<Message>, at_us: u64) {
    append_legato_note(
        ref eventlist,
        DEMO_MARKER_CH,
        60,
        100,
        at_us,
        at_us + LONG_SECTION_GAP_US / 4,
    );
}

fn append_note_events(
    ref eventlist: Array<Message>,
    events: @Array<NoteEvent>,
    time_offset_us: u64,
    step_us: u64,
    use_voice_channel: bool,
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
        let channel: u8 = if use_voice_channel {
            (*e.voice_id).try_into().unwrap()
        } else {
            DEMO_THEME_CH
        };
        append_legato_note(ref eventlist, channel, *e.pitch, *e.velocity, on, off);
        note_ons += 1;
        i += 1;
    };
    note_ons
}

fn append_looped_canon(
    ref eventlist: Array<Message>,
    events: @Array<NoteEvent>,
    canon_len: u32,
    num_voices: u32,
    time_unit: u32,
    time_offset_us: u64,
    step_us: u64,
    num_loops: u32,
) -> u32 {
    let n = events.len();
    assert(n > 0, 'canon events');
    let cycle_ticks = (canon_len + num_voices - 1) * time_unit;
    let mut total_note_ons: u32 = 0;
    let mut loop_i: u32 = 0;
    loop {
        if loop_i >= num_loops {
            break;
        }
        let base: Time = time_offset_us + loop_i.into() * cycle_ticks.into() * step_us;
        total_note_ons += append_note_events(
            ref eventlist, events, base, step_us, true,
        );
        loop_i += 1;
    };
    total_note_ons
}

fn cycle_duration_us(canon_len: u32, num_voices: u32, time_unit: u32, step_us: u64) -> u64 {
    let cycle_ticks = (canon_len + num_voices - 1) * time_unit;
    cycle_ticks.into() * step_us
}

#[ignore]
#[test]
#[available_gas(1000000000000)]
fn motif_development_midi_test() {
    let mut eventlist: Array<Message> = ArrayTrait::new();
    eventlist.append(
        Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }),
    );

    let theme = grundgestalt_theme(0);
    let theme_durs = array![4_u32, 4, 4, 4];
    let theme_only = apply_program(
        @theme,
        @theme_durs,
        MotifProgram { ops: ArrayTrait::new() },
    );
    let theme_events = developed_to_note_events(@theme_only, DEMO_TONIC, DEMO_MODE);
    let theme_units = developed_duration_units(@theme_only);

    append_messages(ref eventlist, note_events_to_midi(@theme_events, DEMO_THEME_CH, 0, DEMO_STEP_US));

    append_legato_note(
        ref eventlist,
        DEMO_MARKER_CH,
        60,
        100,
        theme_units.into() * DEMO_STEP_US + DEMO_GAP_US / 2,
        theme_units.into() * DEMO_STEP_US + DEMO_GAP_US,
    );

    let seeds: Array<felt252> = array![111, 2222, 33333, 444444];
    let mut si: u32 = 0;
    let mut section_offset_us: u64 = theme_units.into() * DEMO_STEP_US + DEMO_GAP_US;
    loop {
        if si >= seeds.len() {
            break;
        }
        let seed = *seeds.at(si);
        let program = program_from_seed(seed, 4);
        let developed = apply_program(@theme, @theme_durs, program);
        let events = developed_to_note_events(@developed, DEMO_TONIC, DEMO_MODE);
        let units = developed_duration_units(@developed);
        append_messages(
            ref eventlist,
            note_events_to_midi(@events, DEMO_VAR_CH, section_offset_us, DEMO_STEP_US),
        );
        section_offset_us += units.into() * DEMO_STEP_US + DEMO_GAP_US;
        si += 1;
    };

    let developed_line = generate_developed_line(99999);
    let line_events = developed_to_note_events(@developed_line, DEMO_TONIC, DEMO_MODE);
    append_messages(
        ref eventlist,
        note_events_to_midi(@line_events, DEMO_VAR_CH, section_offset_us, DEMO_STEP_US),
    );

    let midi = Midi { events: eventlist.span() };
    generate_parser_format(@midi);
    assert_valid_demo_midi(@midi, 10);
}

/// Long demo: developed theme → solo ornament → 2-voice ornamented canon (2 loops).
/// Export: `scarb test -- --filter motif_development_long_ornamented_midi_test`
#[ignore]
#[test]
#[available_gas(4000000000000)]
fn motif_development_long_ornamented_midi_test() {
    let developed = long_demo_developed_motif();
    let leader_len = developed.degrees.len();
    assert(leader_len >= 8, 'developed leader len');

    let mut eventlist: Array<Message> = ArrayTrait::new();
    eventlist.append(
        Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }),
    );

    let mut offset_us: u64 = 0;
    let mut total_note_ons: u32 = 0;

    // Section A — plain developed theme (ch 0)
    let theme_events = developed_to_note_events(@developed, DEMO_TONIC, DEMO_MODE);
    let theme_units = developed_duration_units(@developed);
    total_note_ons += append_note_events(
        ref eventlist, @theme_events, offset_us, LONG_STEP_US, false,
    );
    offset_us += theme_units.into() * LONG_STEP_US;
    append_marker(ref eventlist, offset_us);
    offset_us += LONG_SECTION_GAP_US;

    // Section B — solo Montanos ornament (ch 0)
    let solo_events = developed_to_ornamented_note_events(
        @developed, LONG_ORNAMENT_SEED, DEMO_MODE, ORN_FILL_MIN_STEP,
    );
    assert(solo_events.len() > leader_len, 'solo ornamented');
    let solo_span_ticks = theme_units * 4;
    total_note_ons += append_note_events(
        ref eventlist, @solo_events, offset_us, LONG_STEP_US, false,
    );
    offset_us += solo_span_ticks.into() * LONG_STEP_US;
    append_marker(ref eventlist, offset_us);
    offset_us += LONG_SECTION_GAP_US;

    // Section C — 2-voice ornamented canon from the same developed leader
    let (canon, subs) = generate_ornamented_canon_from_developed(
        LONG_DEMO_SEED, LONG_CANON_CONFIG, @developed, DEMO_MODE,
    );
    let canon_events = canon_to_ornamented_note_events(@canon, subs.span());
    let nv = canon.voices.len();
    let unit = canon.time_unit;
    let cycle_us = cycle_duration_us(leader_len, nv, unit, LONG_STEP_US);
    total_note_ons += append_looped_canon(
        ref eventlist,
        @canon_events,
        leader_len,
        nv,
        unit,
        offset_us,
        LONG_STEP_US,
        LONG_CANON_LOOPS,
    );
    offset_us += cycle_us * LONG_CANON_LOOPS.into();

    let midi = Midi { events: eventlist.span() };
    generate_parser_format(@midi);
    assert_valid_demo_midi(@midi, 120);
    assert(total_note_ons >= 120, 'long ornamented note ons');
}

//! MIDI demo: theme + seed-driven motif development variations.
//! Export: `./scripts/generate_motif_demo_midis.sh`

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::melodic_canon::{
    MelodicCanon, NoteEvent, build_canon_for_test, canon_to_note_events,
    canon_to_ornamented_note_events, exact_imitation,
};
use koji::composition::melodic_motion::ORN_FILL_MIN_STEP;
use koji::composition::motif_algebra::{
    apply_program, developed_to_note_events, developed_to_ornamented_note_events,
    generate_developed_line, generate_ornamented_canon_from_developed, grundgestalt_theme,
    long_demo_developed_motif, motif_from_degrees, program_from_seed, DevelopedMotif, Motif,
    MotifProgram,
};
use koji::composition::ornamentation_v2::canon::v2_note_to_legacy;
use koji::composition::ornamentation_v2::engine::{default_config, ornament_canon};
use koji::composition::ornamentation_v2::profiles::{
    profile_baroque_ornament, profile_bebop_movement, profile_common_practice,
    profile_modal_canon,
};
use koji::composition::ornamentation_v2::types::{
    HarmonyEvent, OrnamentStyleProfile, ROLE_STRUCTURAL, V2NoteEvent, WORKFLOW_CANON_FIRST,
    all_enabled_ornaments, ORN_ACCIACCATURA_LOWER, ORN_ACCIACCATURA_UPPER, ORN_ANTICIPATION,
    ORN_APPOGGIATURA_LOWER, ORN_APPOGGIATURA_UPPER, ORN_ARPEGGIATION_DOWN,
    ORN_ARPEGGIATION_UP, ORN_CAMBIATA, ORN_CHROMATIC_APPROACH_LOWER,
    ORN_CHROMATIC_APPROACH_UPPER, ORN_DOUBLE_NEIGHBOR_LF, ORN_DOUBLE_NEIGHBOR_UF,
    ORN_ECHAPPEE_LOWER, ORN_ECHAPPEE_UPPER, ORN_ENCLOSURE_LF, ORN_ENCLOSURE_UF,
    ORN_ESCAPE_LOWER, ORN_ESCAPE_UPPER, ORN_MORDENT_LOWER, ORN_MORDENT_UPPER,
    ORN_NEIGHBOR_LOWER, ORN_NEIGHBOR_UPPER, ORN_PASSING_ASC, ORN_PASSING_DESC,
    ORN_PEDAL_HOLD, ORN_RETARDATION, ORN_SUSPENSION_23_BASS, ORN_SUSPENSION_43,
    ORN_SUSPENSION_65, ORN_SUSPENSION_76, ORN_SUSPENSION_98, ORN_TRILL_LOWER,
    ORN_TRILL_UPPER, ORN_TURN_LOWER, ORN_TURN_UPPER,
};
use koji::composition::period_assembly::{develop_period_grouped, period_section_lengths};
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
const GROUPED_STEP_US: u64 = 180000;
const GROUPED_PASSES: u32 = 8;
const V2_CANON_STEP_US: u64 = 155000;
const V2_CANON_SECTION_GAP_US: u64 = 1200000;

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

fn append_note_events_on_channel(
    ref eventlist: Array<Message>,
    events: @Array<NoteEvent>,
    time_offset_us: u64,
    step_us: u64,
    channel: u8,
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
        append_legato_note(ref eventlist, channel, *e.pitch, *e.velocity, on, off);
        note_ons += 1;
        i += 1;
    };
    note_ons
}

fn note_events_end_tick(events: @Array<NoteEvent>) -> u32 {
    let mut end_tick: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = events.at(i);
        let end = *e.time + *e.duration;
        if end > end_tick {
            end_tick = end;
        }
        i += 1;
    };
    end_tick
}

fn distinct_surface_roles(events: @Array<V2NoteEvent>) -> u32 {
    let mut roles: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let role = (*events.at(i)).role;
        if role != ROLE_STRUCTURAL {
            let mut seen = false;
            let mut ri: u32 = 0;
            loop {
                if ri >= roles.len() {
                    break;
                }
                if *roles.at(ri) == role {
                    seen = true;
                    break;
                }
                ri += 1;
            };
            if !seen {
                roles.append(role);
            }
        }
        i += 1;
    };
    roles.len()
}

fn append_v2_canon_section(
    ref eventlist: Array<Message>,
    canon: @MelodicCanon,
    harmony: @Array<HarmonyEvent>,
    enabled: @Array<u8>,
    style: OrnamentStyleProfile,
    seed: felt252,
    strict_diatonic: bool,
    offset_us: u64,
) -> u32 {
    let mut cfg = default_config(seed);
    cfg.style = style;
    cfg.canon_workflow = WORKFLOW_CANON_FIRST;
    cfg.constraints.strict_diatonic = strict_diatonic;
    let result = ornament_canon(canon, harmony.span(), cfg, enabled.span());
    let events = result.events;
    assert(events.len() > canon.leader_degrees.len() * canon.voices.len(), 'v2 expands canon');
    assert(distinct_surface_roles(@events) >= 2, 'v2 ornament variety');

    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = v2_note_to_legacy(*events.at(i));
        let on: Time = offset_us + e.time.into() * V2_CANON_STEP_US;
        let off: Time = on + e.duration.into() * V2_CANON_STEP_US;
        let channel: u8 = e.voice_id.try_into().unwrap();
        append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
        i += 1;
    };
    events.len()
}

fn v2_canon_harmony(cycle_ticks: u32, tonic_pc: u8) -> Array<HarmonyEvent> {
    let segment = cycle_ticks / 4;
    let mut out: Array<HarmonyEvent> = ArrayTrait::new();
    out.append(
        HarmonyEvent {
            root_pc: tonic_pc,
            bass_pc: tonic_pc,
            start: 0,
            duration: segment,
            function_label: 0,
        },
    );
    out.append(
        HarmonyEvent {
            root_pc: (tonic_pc + 5) % 12,
            bass_pc: (tonic_pc + 5) % 12,
            start: segment,
            duration: segment,
            function_label: 1,
        },
    );
    out.append(
        HarmonyEvent {
            root_pc: (tonic_pc + 7) % 12,
            bass_pc: (tonic_pc + 7) % 12,
            start: segment * 2,
            duration: segment,
            function_label: 2,
        },
    );
    out.append(
        HarmonyEvent {
            root_pc: tonic_pc,
            bass_pc: tonic_pc,
            start: segment * 3,
            duration: cycle_ticks - segment * 3,
            function_label: 0,
        },
    );
    out
}

fn modal_canon_ornaments() -> Array<u8> {
    array![
        ORN_PASSING_ASC,
        ORN_PASSING_DESC,
        ORN_NEIGHBOR_UPPER,
        ORN_NEIGHBOR_LOWER,
        ORN_DOUBLE_NEIGHBOR_UF,
        ORN_DOUBLE_NEIGHBOR_LF,
        ORN_ANTICIPATION,
        ORN_APPOGGIATURA_UPPER,
        ORN_APPOGGIATURA_LOWER,
        ORN_ARPEGGIATION_UP,
        ORN_ARPEGGIATION_DOWN,
        ORN_PEDAL_HOLD,
    ]
}

fn common_practice_canon_ornaments() -> Array<u8> {
    array![
        ORN_PASSING_ASC,
        ORN_PASSING_DESC,
        ORN_NEIGHBOR_UPPER,
        ORN_NEIGHBOR_LOWER,
        ORN_ANTICIPATION,
        ORN_SUSPENSION_43,
        ORN_SUSPENSION_76,
        ORN_SUSPENSION_98,
        ORN_SUSPENSION_65,
        ORN_SUSPENSION_23_BASS,
        ORN_RETARDATION,
        ORN_APPOGGIATURA_UPPER,
        ORN_APPOGGIATURA_LOWER,
    ]
}

fn baroque_canon_ornaments() -> Array<u8> {
    array![
        ORN_APPOGGIATURA_UPPER,
        ORN_APPOGGIATURA_LOWER,
        ORN_MORDENT_UPPER,
        ORN_MORDENT_LOWER,
        ORN_TURN_UPPER,
        ORN_TURN_LOWER,
        ORN_TRILL_UPPER,
        ORN_TRILL_LOWER,
        ORN_ACCIACCATURA_UPPER,
        ORN_ACCIACCATURA_LOWER,
        ORN_SUSPENSION_43,
        ORN_RETARDATION,
    ]
}

fn chromatic_canon_ornaments() -> Array<u8> {
    array![
        ORN_PASSING_ASC,
        ORN_PASSING_DESC,
        ORN_ESCAPE_UPPER,
        ORN_ESCAPE_LOWER,
        ORN_ECHAPPEE_UPPER,
        ORN_ECHAPPEE_LOWER,
        ORN_CAMBIATA,
        ORN_CHROMATIC_APPROACH_UPPER,
        ORN_CHROMATIC_APPROACH_LOWER,
        ORN_ENCLOSURE_UF,
        ORN_ENCLOSURE_LF,
        ORN_ACCIACCATURA_UPPER,
        ORN_ACCIACCATURA_LOWER,
    ]
}

fn run_grouped_motif_long_ornamented_midi(
    theme: @Motif,
    durations: @Array<u32>,
    seed: felt252,
    mode_id: u8,
    ornament_seed: u32,
) {
    let period = develop_period_grouped(theme, durations, seed, 2);
    let (a_len, b_len) = period_section_lengths(theme, durations, seed, 2);
    assert(period.degrees.len() == a_len * 3 + b_len, 'grouped AABA length');
    assert(period.degrees.len() >= 8, 'grouped melody len');

    let mut eventlist: Array<Message> = ArrayTrait::new();
    eventlist.append(
        Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }),
    );

    let mut offset_us: u64 = 0;
    let mut total_note_ons: u32 = 0;

    // Plain statement makes the contour-derived AABA structure audible first.
    let plain = developed_to_note_events(@period, 65, mode_id);
    total_note_ons += append_note_events_on_channel(
        ref eventlist, @plain, offset_us, GROUPED_STEP_US, 0,
    );
    offset_us += note_events_end_tick(@plain).into() * GROUPED_STEP_US;
    append_marker(ref eventlist, offset_us);
    offset_us += LONG_SECTION_GAP_US;

    // Eight increasingly reseeded ornamented passes keep the same grouped form.
    let mut pass: u32 = 0;
    let mut ornamented_note_ons: u32 = 0;
    loop {
        if pass >= GROUPED_PASSES {
            break;
        }
        let events = developed_to_ornamented_note_events(
            @period, ornament_seed + pass * 37, mode_id, ORN_FILL_MIN_STEP,
        );
        let channel: u8 = (pass % 4 + 1).try_into().unwrap();
        ornamented_note_ons += append_note_events_on_channel(
            ref eventlist, @events, offset_us, GROUPED_STEP_US, channel,
        );
        offset_us += note_events_end_tick(@events).into() * GROUPED_STEP_US;
        append_marker(ref eventlist, offset_us);
        offset_us += LONG_SECTION_GAP_US / 2;
        pass += 1;
    };
    total_note_ons += ornamented_note_ons;

    assert(ornamented_note_ons > period.degrees.len() * GROUPED_PASSES, 'ornaments expand');
    let midi = Midi { events: eventlist.span() };
    generate_parser_format(@midi);
    assert_valid_demo_midi(@midi, 100);
    assert(total_note_ons >= 100, 'grouped long note ons');
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

/// Grouped AABA showcase: sequence statement answered by inversion.
/// Export: `./scripts/generate_midi_from_test.sh grouped_motif_sequence_inversion_long_ornamented_midi_test demos/motif/03_grouped_sequence_inversion_long_ornamented.mid`
#[ignore]
#[test]
#[available_gas(8000000000000)]
fn grouped_motif_sequence_inversion_long_ornamented_midi_test() {
    let theme = motif_from_degrees(array![0_i32, 2, 4, 3, 7, 5, 9, 7], 7, 0);
    let durations = array![2_u32, 1, 1, 1, 4, 1, 1, 2];
    run_grouped_motif_long_ornamented_midi(@theme, @durations, 50470912, 3, 41);
}

/// Grouped AABA showcase: stuttered statement answered by retrograde.
/// Export: `./scripts/generate_midi_from_test.sh grouped_motif_stutter_retrograde_long_ornamented_midi_test demos/motif/04_grouped_stutter_retrograde_long_ornamented.mid`
#[ignore]
#[test]
#[available_gas(8000000000000)]
fn grouped_motif_stutter_retrograde_long_ornamented_midi_test() {
    let theme = motif_from_degrees(array![0_i32, 2, 1, 4, 3, 6, 4, 7, 5, 2], 7, 0);
    let durations = array![1_u32, 1, 3, 1, 1, 4, 1, 1, 2, 1];
    run_grouped_motif_long_ornamented_midi(@theme, @durations, 117510144, 1, 83);
}

/// Grouped AABA showcase: interpolated leaps answered by retrograde-inversion.
/// Export: `./scripts/generate_midi_from_test.sh grouped_motif_interpolate_retroinvert_long_ornamented_midi_test demos/motif/05_grouped_interpolate_retroinvert_long_ornamented.mid`
#[ignore]
#[test]
#[available_gas(8000000000000)]
fn grouped_motif_interpolate_retroinvert_long_ornamented_midi_test() {
    let theme = motif_from_degrees(array![0_i32, 4, 1, 7, 3, 8, 2, 6, 1, 5], 7, 0);
    let durations = array![1_u32, 1, 1, 4, 1, 1, 1, 3, 1, 2];
    run_grouped_motif_long_ornamented_midi(@theme, @durations, 167779072, 5, 127);
}

/// Long three-part canon over a grouped motif period, moving through five ornamentation-v2 palettes.
/// Export: `./scripts/generate_midi_from_test.sh motif_v2_three_part_canon_long_midi_test demos/motif/06_v2_three_part_canon_long.mid`
#[ignore]
#[test]
#[available_gas(16000000000000)]
fn motif_v2_three_part_canon_long_midi_test() {
    let theme = motif_from_degrees(array![0_i32, 4, 1, 7, 3, 8, 2, 6, 1, 5], 7, 0);
    let durations = array![1_u32, 1, 1, 4, 1, 1, 1, 3, 1, 2];
    let period = develop_period_grouped(@theme, @durations, 167779072, 2);
    assert(period.degrees.len() >= 48, 'long motif canon leader');

    let offsets = array![0_i32, -4, 3];
    let canon = build_canon_for_test(
        4, 'motif_v2_3part', offsets.span(), period.degrees.span(), 5,
    );
    assert(canon.voices.len() == 3, 'three canon voices');
    assert(exact_imitation(@canon), 'motif canon imitation');
    let cycle_ticks = (canon.leader_degrees.len() + canon.voices.len() - 1) * canon.time_unit;
    let cycle_us: u64 = cycle_ticks.into() * V2_CANON_STEP_US;
    let harmony = v2_canon_harmony(cycle_ticks, canon.tonic_keynum % 12);

    let mut eventlist: Array<Message> = ArrayTrait::new();
    eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
    let mut total_note_ons: u32 = 0;
    let mut offset_us: u64 = 0;

    // Plain exposition establishes the grouped AABA motif and its three imitative entries.
    let structural = canon_to_note_events(@canon);
    total_note_ons += append_note_events(
        ref eventlist, @structural, offset_us, V2_CANON_STEP_US, true,
    );
    offset_us += cycle_us;
    append_marker(ref eventlist, offset_us);
    offset_us += V2_CANON_SECTION_GAP_US;

    let modal = modal_canon_ornaments();
    total_note_ons += append_v2_canon_section(
        ref eventlist,
        @canon,
        @harmony,
        @modal,
        profile_modal_canon(),
        41,
        true,
        offset_us,
    );
    offset_us += cycle_us;
    append_marker(ref eventlist, offset_us);
    offset_us += V2_CANON_SECTION_GAP_US;

    let common = common_practice_canon_ornaments();
    total_note_ons += append_v2_canon_section(
        ref eventlist,
        @canon,
        @harmony,
        @common,
        profile_common_practice(),
        83,
        true,
        offset_us,
    );
    offset_us += cycle_us;
    append_marker(ref eventlist, offset_us);
    offset_us += V2_CANON_SECTION_GAP_US;

    let baroque = baroque_canon_ornaments();
    total_note_ons += append_v2_canon_section(
        ref eventlist,
        @canon,
        @harmony,
        @baroque,
        profile_baroque_ornament(),
        127,
        true,
        offset_us,
    );
    offset_us += cycle_us;
    append_marker(ref eventlist, offset_us);
    offset_us += V2_CANON_SECTION_GAP_US;

    let chromatic = chromatic_canon_ornaments();
    total_note_ons += append_v2_canon_section(
        ref eventlist,
        @canon,
        @harmony,
        @chromatic,
        profile_bebop_movement(),
        169,
        false,
        offset_us,
    );
    offset_us += cycle_us;
    append_marker(ref eventlist, offset_us);
    offset_us += V2_CANON_SECTION_GAP_US;

    let all = all_enabled_ornaments();
    total_note_ons += append_v2_canon_section(
        ref eventlist,
        @canon,
        @harmony,
        @all,
        profile_baroque_ornament(),
        211,
        false,
        offset_us,
    );

    let midi = Midi { events: eventlist.span() };
    generate_parser_format(@midi);
    assert_valid_demo_midi(@midi, 900);
    assert(total_note_ons >= 900, 'long v2 canon note ons');
}

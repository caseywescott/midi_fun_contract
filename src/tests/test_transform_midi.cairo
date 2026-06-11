//! MIDI demos for the transformation combinator library.
//!
//! Each section: **source** on channel 0, **transformed** on channel 1, marker ping on ch 9.
//! Export: `./scripts/generate_transform_demo_midis.sh`

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::transform::{
    ambitus_i32, apply_to_object, assemble, augment_u32, concat_i32, diminish_u32, divide_i32,
    filter_where_i32, flatten_i32, gen_permute, gen_rotate, interleave_i32, interval_invert_i32,
    invert_i32, map_add_i32, map_scale_i32, map_where_i32, palindrome_i32, permute_i32, repeat_i32,
    reverse_i32, rotate_i32, span_i32, take_i32, drop_i32, transpose_i32, trim_i32, MusicalObject, Pipeline,
    PlaneId, PlaneOp, Selector,
};
use koji::math::Time;
use koji::midi::output::output_midi_object;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

const DEMO_STEP_US: u64 = 300000;
const DEMO_GAP_US: u64 = 700000;
const DEMO_SECTION_GAP_US: u64 = 1000000;
const DEMO_MARKER_CH: u8 = 9;
const DEMO_SOURCE_CH: u8 = 0;
const DEMO_RESULT_CH: u8 = 1;
const DEMO_TONIC: u8 = 60;
const DEMO_MODE: u8 = 0;

#[derive(Drop)]
struct DemoSection {
    source: MusicalObject,
    result: MusicalObject,
}

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
            Option::None(_) => { break; },
        };
    }
}

fn assert_valid_demo_midi(midiobj: @Midi, expected_note_ons: u32) {
    let mut ev = midiobj.clone().events;
    let mut note_on_count: u32 = 0;
    let mut note_off_count: u32 = 0;
    loop {
        match ev.pop_front() {
            Option::Some(msg) => {
                match msg {
                    Message::NOTE_ON(_) => { note_on_count += 1; },
                    Message::NOTE_OFF(_) => { note_off_count += 1; },
                    _ => {},
                }
            },
            Option::None(_) => { break; },
        }
    }
    assert(note_on_count == expected_note_ons, 'note on count');
    assert(note_on_count == note_off_count, 'on off balance');
    let binary = output_midi_object(midiobj);
    assert(binary.len() >= 22, 'MIDI too short');
}

fn demo_source() -> MusicalObject {
    MusicalObject {
        pitches: array![0_i32, 2, 4, 5, 7],
        lengths: array![3_u32, 3, 3, 3, 3],
        velocities: array![96_u8],
        articulations: array![0_u8],
        octave: 7,
    }
}

fn with_pitches(base: MusicalObject, pitches: Array<i32>) -> MusicalObject {
    MusicalObject {
        pitches,
        lengths: base.lengths,
        velocities: base.velocities,
        articulations: base.articulations,
        octave: base.octave,
    }
}

fn with_lengths(base: MusicalObject, lengths: Array<u32>) -> MusicalObject {
    MusicalObject {
        pitches: base.pitches,
        lengths,
        velocities: base.velocities,
        articulations: base.articulations,
        octave: base.octave,
    }
}

fn count_note_ons(obj: @MusicalObject) -> u32 {
    assemble(obj, 0, DEMO_TONIC, DEMO_MODE).len()
}

fn append_note_events(
    ref eventlist: Array<Message>,
    events: Span<NoteEvent>,
    channel: u8,
    base_us: u64,
    step_us: u64,
) -> u64 {
    let mut end_us = base_us;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        let on: Time = base_us + e.time.into() * step_us;
        let off: Time = on + e.duration.into() * step_us;
        append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
        end_us = off;
        i += 1;
    };
    end_us
}

fn append_object(
    ref eventlist: Array<Message>,
    obj: @MusicalObject,
    channel: u8,
    base_us: u64,
    step_us: u64,
) -> u64 {
    let events = assemble(obj, 0, DEMO_TONIC, DEMO_MODE);
    append_note_events(ref eventlist, events.span(), channel, base_us, step_us)
}

fn append_section_marker(ref eventlist: Array<Message>, at_us: u64) {
    append_legato_note(ref eventlist, DEMO_MARKER_CH, 36, 45, at_us, at_us + 120000);
}

fn append_ab_demo(
    ref eventlist: Array<Message>,
    sec: DemoSection,
    ref cursor: u64,
    ref note_ons: u32,
) {
    append_section_marker(ref eventlist, cursor);
    note_ons += 1;

    let src_end = append_object(ref eventlist, @sec.source, DEMO_SOURCE_CH, cursor, DEMO_STEP_US);
    note_ons += count_note_ons(@sec.source);

    cursor = src_end + DEMO_GAP_US;

    let res_end = append_object(ref eventlist, @sec.result, DEMO_RESULT_CH, cursor, DEMO_STEP_US);
    note_ons += count_note_ons(@sec.result);

    cursor = res_end + DEMO_SECTION_GAP_US;
}

fn extend_sections(ref dst: Array<DemoSection>, mut src: Array<DemoSection>) {
    loop {
        match src.pop_front() {
            Option::Some(sec) => { dst.append(sec); },
            Option::None(_) => { break; },
        };
    }
}

fn export_showcase_midi(mut sections: Array<DemoSection>) -> u32 {
    let mut eventlist = ArrayTrait::<Message>::new();
    eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

    let mut cursor: u64 = 0;
    let mut note_ons: u32 = 0;
    loop {
        match sections.pop_front() {
            Option::Some(sec) => {
                append_ab_demo(ref eventlist, sec, ref cursor, ref note_ons);
            },
            Option::None(_) => { break; },
        };
    };

    let midiobj = Midi { events: eventlist.span() };
    generate_parser_format(@midiobj);
    assert_valid_demo_midi(@midiobj, note_ons);
    note_ons
}

fn pair_pitch(source: MusicalObject, pitches: Array<i32>) -> DemoSection {
    DemoSection { source, result: with_pitches(demo_source(), pitches) }
}

fn pair_lengths(source: MusicalObject, lengths: Array<u32>) -> DemoSection {
    DemoSection { source, result: with_lengths(demo_source(), lengths) }
}

fn pair_object(source: MusicalObject, result: MusicalObject) -> DemoSection {
    DemoSection { source, result }
}

fn build_order_sections() -> Array<DemoSection> {
    let mut sections: Array<DemoSection> = ArrayTrait::new();

    let src = demo_source();
    sections.append(pair_pitch(src, rotate_i32(demo_source().pitches.span(), 2)));

    let src2 = demo_source();
    sections.append(pair_pitch(src2, reverse_i32(demo_source().pitches.span())));

    let src3 = demo_source();
    sections.append(pair_pitch(src3, palindrome_i32(demo_source().pitches.span(), false)));

    let src4 = demo_source();
    sections.append(
        pair_pitch(
            src4,
            permute_i32(demo_source().pitches.span(), array![2_u32, 0, 1, 3, 4].span()),
        ),
    );

    let src5 = demo_source();
    sections.append(pair_pitch(src5, gen_rotate(4242, demo_source().pitches.span())));

    let src6 = demo_source();
    sections.append(pair_pitch(src6, gen_permute(99001, demo_source().pitches.span())));

    sections
}

fn build_pitch_sections() -> Array<DemoSection> {
    let mut sections: Array<DemoSection> = ArrayTrait::new();

    let src = demo_source();
    sections.append(pair_pitch(src, transpose_i32(demo_source().pitches.span(), 2)));

    let src2 = demo_source();
    sections.append(pair_pitch(src2, invert_i32(demo_source().pitches.span(), 4)));

    let src3 = demo_source();
    sections.append(pair_pitch(src3, interval_invert_i32(demo_source().pitches.span())));

    let wide_p = array![0_i32, 2, 4, 5, 7, 12, 14];
    let wide_lens = array![3_u32, 3, 3, 3, 3, 3, 3];
    let wide_src = with_lengths(with_pitches(demo_source(), wide_p), wide_lens);
    let folded = ambitus_i32(wide_src.pitches.span(), 0, 4, 7);
    let wide_result = MusicalObject {
        pitches: folded,
        lengths: array![3_u32, 3, 3, 3, 3, 3, 3],
        velocities: array![96_u8],
        articulations: array![0_u8],
        octave: 7,
    };
    sections.append(DemoSection { source: wide_src, result: wide_result });

    sections
}

fn build_select_map_sections() -> Array<DemoSection> {
    let mut sections: Array<DemoSection> = ArrayTrait::new();
    let ref_pitches = demo_source().pitches.span();

    let src = demo_source();
    sections.append(pair_pitch(src, take_i32(ref_pitches, 3)));

    let src2 = demo_source();
    sections.append(pair_pitch(src2, drop_i32(ref_pitches, 2)));

    let src3 = demo_source();
    sections.append(pair_pitch(src3, span_i32(ref_pitches, 1, 4)));

    let src4 = demo_source();
    sections.append(pair_pitch(src4, filter_where_i32(ref_pitches, Selector::EveryNth(2))));

    let src5 = demo_source();
    let op = PlaneOp::Transpose(1);
    sections.append(
        pair_pitch(src5, map_where_i32(ref_pitches, Selector::EveryNth(2), @op)),
    );

    let src6 = demo_source();
    sections.append(
        pair_pitch(src6, map_add_i32(ref_pitches, array![0_i32, 0, 1, 0, 2].span())),
    );

    let src7 = demo_source();
    sections.append(pair_pitch(src7, map_scale_i32(ref_pitches, 3, 2)));

    let src8 = demo_source();
    let mut vel_ops: Array<PlaneOp> = ArrayTrait::new();
    let mut vel_table: Array<i32> = ArrayTrait::new();
    vel_table.append(40);
    vel_table.append(127);
    vel_table.append(40);
    vel_table.append(127);
    vel_table.append(127);
    vel_ops.append(PlaneOp::MapByPosition(vel_table));
    let vel_pipe = Pipeline { ops: vel_ops };
    let vel_result = apply_to_object(demo_source(), PlaneId::Velocity, @vel_pipe);
    sections.append(pair_object(src8, vel_result));

    sections
}

fn build_rhythm_combine_sections() -> Array<DemoSection> {
    let mut sections: Array<DemoSection> = ArrayTrait::new();
    let ref_src = demo_source();

    let src = demo_source();
    sections.append(pair_lengths(src, augment_u32(ref_src.lengths.span(), 2)));

    let src2 = demo_source();
    let even = with_lengths(demo_source(), array![4_u32, 4, 4, 4, 4]);
    sections.append(pair_lengths(src2, diminish_u32(even.lengths.span(), 2)));

    let src3 = demo_source();
    let retro = reverse_i32(ref_src.pitches.span());
    sections.append(pair_pitch(src3, interleave_i32(ref_src.pitches.span(), retro.span())));

    let src4 = demo_source();
    sections.append(
        pair_pitch(src4, concat_i32(ref_src.pitches.span(), take_i32(ref_src.pitches.span(), 2).span())),
    );

    let src5 = demo_source();
    sections.append(pair_pitch(src5, repeat_i32(ref_src.pitches.span(), 2)));

    let src6 = demo_source();
    let rep = repeat_i32(ref_src.pitches.span(), 2);
    sections.append(pair_pitch(src6, trim_i32(rep.span(), 3)));

    let src7 = demo_source();
    let groups = divide_i32(ref_src.pitches.span(), 2);
    sections.append(pair_pitch(src7, flatten_i32(@groups)));

    sections
}

fn build_pipeline_section() -> DemoSection {
    let source = demo_source();

    let mut pitch_ops: Array<PlaneOp> = ArrayTrait::new();
    pitch_ops.append(PlaneOp::Invert(4));
    pitch_ops.append(PlaneOp::Rotate(2));
    let pitch_pipe = Pipeline { ops: pitch_ops };

    let mut len_ops: Array<PlaneOp> = ArrayTrait::new();
    len_ops.append(PlaneOp::Rotate(1));
    len_ops.append(PlaneOp::Augment(2));
    let len_pipe = Pipeline { ops: len_ops };

    let mut vel_table: Array<i32> = ArrayTrait::new();
    vel_table.append(110);
    vel_table.append(70);
    vel_table.append(70);
    vel_table.append(90);
    let mut vel_ops: Array<PlaneOp> = ArrayTrait::new();
    vel_ops.append(PlaneOp::MapByPosition(vel_table));
    let vel_pipe = Pipeline { ops: vel_ops };

    let mut result = apply_to_object(demo_source(), PlaneId::Pitch, @pitch_pipe);
    result = apply_to_object(result, PlaneId::Length, @len_pipe);
    result = apply_to_object(result, PlaneId::Velocity, @vel_pipe);

    DemoSection { source, result }
}

#[ignore]
#[test]
#[available_gas(8000000000)]
fn transform_showcase_order_midi_test() {
    let n = export_showcase_midi(build_order_sections());
    assert(n >= 12, 'order demo notes');
}

#[ignore]
#[test]
#[available_gas(12000000000)]
fn transform_showcase_pitch_midi_test() {
    let n = export_showcase_midi(build_pitch_sections());
    assert(n >= 8, 'pitch demo notes');
}

#[ignore]
#[test]
#[available_gas(8000000000)]
fn transform_showcase_select_map_midi_test() {
    let n = export_showcase_midi(build_select_map_sections());
    assert(n >= 16, 'select map notes');
}

#[ignore]
#[test]
#[available_gas(8000000000)]
fn transform_showcase_rhythm_combine_midi_test() {
    let n = export_showcase_midi(build_rhythm_combine_sections());
    assert(n >= 16, 'rhythm combine notes');
}

#[ignore]
#[test]
#[available_gas(2000000000)]
fn transform_showcase_pipeline_midi_test() {
    let mut sections: Array<DemoSection> = ArrayTrait::new();
    sections.append(build_pipeline_section());
    let n = export_showcase_midi(sections);
    assert(n >= 2, 'pipeline demo notes');
}

#[ignore]
#[test]
#[available_gas(40000000000)]
fn transform_showcase_all_midi_test() {
    let mut all: Array<DemoSection> = ArrayTrait::new();
    extend_sections(ref all, build_order_sections());
    extend_sections(ref all, build_pitch_sections());
    extend_sections(ref all, build_select_map_sections());
    extend_sections(ref all, build_rhythm_combine_sections());
    all.append(build_pipeline_section());
    let n = export_showcase_midi(all);
    assert(n >= 50, 'full showcase notes');
}

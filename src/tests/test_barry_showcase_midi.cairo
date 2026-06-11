//! Barry Harris v2 — audible showcase MIDI demos.
//!
//! Each test renders a focused, decent-length musical example that demonstrates
//! one (or a combination) of the v2 techniques: elevators, idiomatic voicing
//! styles, voice-motion policies, turnarounds, line cells, neighbor borrowing,
//! limitation profiles, and a motif/ornamentation-driven melody played over a
//! Barry comp.
//!
//! These are `#[ignore]`d so the normal test run stays light. Render them one at
//! a time (keeps memory bounded) via:
//!     ./scripts/generate_barry_showcase_demo_midis.sh
//! or individually:
//!     scarb test -- --include-ignored --filter <test_name>

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::barry_borrowing::{BarryBorrowKind, borrow_neighbor_state};
use koji::composition::barry_elevators::{
    ElevatorDirection, generate_elevator_bounce_path, generate_elevator_path,
};
use koji::composition::barry_harmonization::{
    BarryHarmonicMotionStep, harmonization_motion_from_states, harmonize_barry_block_chords,
    harmonize_barry_block_chords_with_motion, regular_downbeat_plan, rhythmic_comping_plan,
    with_harmonization_voicing_style,
};
use koji::composition::barry_harris::{
    ChordFamily, HarmonicState, initial_harmonic_state, stable_chord_tones_for, voicelead,
};
use koji::composition::barry_labyrinth::generate_barry_labyrinth_phrase;
use koji::composition::barry_line_cells::realize_line_cell;
use koji::composition::barry_profiles::BarryRuleProfile;
use koji::composition::barry_turnarounds::generate_barry_turnaround;
use koji::composition::barry_v2_types::{
    BarryLineCell, BarryTurnaroundKind, BarryVoicingStyle, VoiceMotionPolicy,
};
use koji::composition::barry_voicing_styles::realize_voicing_style;
use koji::composition::melodic_canon::{
    NoteEvent, canon_to_ornamented_note_events, generate_ornamented_canon,
};
use koji::composition::melodic_motion::ORN_FILL_MIN_STEP;
use koji::composition::motif_algebra::{developed_to_ornamented_note_events, motif_from_degrees};
use koji::composition::period_assembly::develop_period_grouped;
use koji::composition::timeline_rhythm::TimelineRhythm;
use koji::math::Time;
use koji::midi::output::output_midi_object;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

const TICK_US: u64 = 150000;
const LO: i16 = 48;
const HI: i16 = 76;
const MELODY_CH: u8 = 4;
const MARKER_CH: u8 = 9;

// ──────────────────────────────────────────────────────────
// A single chord in a progression: a Barry 6th-diminished family rooted on a pc.
// ──────────────────────────────────────────────────────────
#[derive(Copy, Drop)]
struct ChordStep {
    tonic_pc: u8,
    family: ChordFamily,
    dur: u32,
}

fn chord(tonic_pc: u8, family: ChordFamily, dur: u32) -> ChordStep {
    ChordStep { tonic_pc, family, dur }
}

/// ii–V–I–VI in C using Barry families: Dm6 · G7 · C6 · A7.
fn two_five_one_six(beat: u32) -> Array<ChordStep> {
    array![
        chord(2, ChordFamily::Minor6Dim, beat),
        chord(7, ChordFamily::Dominant7Dim, beat),
        chord(0, ChordFamily::Major6Dim, beat),
        chord(9, ChordFamily::Dominant7Dim, beat),
    ]
}

// ──────────────────────────────────────────────────────────
// MIDI plumbing
// ──────────────────────────────────────────────────────────
fn clone_i16(src: Span<i16>) -> Array<i16> {
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= src.len() {
            break;
        }
        out.append(*src.at(i));
        i += 1;
    }
    out
}

fn append_harmonic_motion(
    ref out: Array<BarryHarmonicMotionStep>, motion: Span<BarryHarmonicMotionStep>,
) {
    let mut i: usize = 0;
    loop {
        if i >= motion.len() {
            break;
        }
        out.append(*motion.at(i));
        i += 1;
    }
}

fn append_legato(ref events: Array<Message>, ch: u8, note: u8, vel: u8, on: Time, off: Time) {
    events.append(Message::NOTE_ON(NoteOn { channel: ch, note, velocity: vel, time: on }));
    events.append(Message::NOTE_OFF(NoteOff { channel: ch, note, velocity: 64, time: off }));
}

/// Emit note events using each event's `voice_id` as the MIDI channel.
fn emit_voiced(ref events: Array<Message>, notes: @Array<NoteEvent>, start_us: u64) -> u32 {
    let mut n: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= notes.len() {
            break;
        }
        let e = notes.at(i);
        let on: Time = start_us + (*e.time).into() * TICK_US;
        let off: Time = on + (*e.duration).into() * TICK_US;
        append_legato(
            ref events, (*e.voice_id).try_into().unwrap(), *e.pitch, *e.velocity, on, off,
        );
        n += 1;
        i += 1;
    }
    n
}

fn emit_voiced_at_step(
    ref events: Array<Message>, notes: @Array<NoteEvent>, start_us: u64, step_us: u64,
) -> u32 {
    let mut n: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= notes.len() {
            break;
        }
        let e = notes.at(i);
        let on: Time = start_us + (*e.time).into() * step_us;
        let off: Time = on + (*e.duration).into() * step_us;
        append_legato(
            ref events, (*e.voice_id).try_into().unwrap(), *e.pitch, *e.velocity, on, off,
        );
        n += 1;
        i += 1;
    }
    n
}

/// Emit note events on a fixed channel, optionally shifting pitch by `octave`.
fn emit_channel(
    ref events: Array<Message>, notes: @Array<NoteEvent>, ch: u8, start_us: u64, octave: i16,
) -> u32 {
    let mut n: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= notes.len() {
            break;
        }
        let e = notes.at(i);
        let on: Time = start_us + (*e.time).into() * TICK_US;
        let off: Time = on + (*e.duration).into() * TICK_US;
        let shifted: i16 = (*e.pitch).into() + octave * 12;
        let pitch: u8 = if shifted < 0 {
            0
        } else if shifted > 127 {
            127
        } else {
            shifted.try_into().unwrap()
        };
        append_legato(ref events, ch, pitch, *e.velocity, on, off);
        n += 1;
        i += 1;
    }
    n
}

fn append_marker(ref events: Array<Message>, at_us: u64) {
    append_legato(ref events, MARKER_CH, 56, 100, at_us, at_us + TICK_US);
}

fn end_tick(notes: @Array<NoteEvent>) -> u32 {
    let mut e: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= notes.len() {
            break;
        }
        let ev = notes.at(i);
        let t = *ev.time + *ev.duration;
        if t > e {
            e = t;
        }
        i += 1;
    }
    e
}

/// Render a chord progression through one voicing style + voice-motion policy.
/// Returns note events whose `voice_id` already encodes the target channel.
fn render_comp(
    steps: Span<ChordStep>,
    style: BarryVoicingStyle,
    policy: VoiceMotionPolicy,
    base_ch: u8,
    start_tick: u32,
    vel: u8,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut prev: Array<i16> = ArrayTrait::new();
    let mut t: u32 = start_tick;
    let mut i: usize = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        let s = *steps.at(i);
        let pcs = stable_chord_tones_for(s.tonic_pc, s.family);
        let voiced = realize_voicing_style(
            pcs.span(), prev.span(), LO, HI, style, policy, i.try_into().unwrap(),
        );
        let mut v: usize = 0;
        loop {
            if v >= voiced.len() {
                break;
            }
            let kn = *voiced.at(v);
            let pitch: u8 = if kn >= 0 {
                kn.try_into().unwrap()
            } else {
                0
            };
            let vid: u32 = base_ch.into() + v.try_into().unwrap();
            out.append(NoteEvent { time: t, duration: s.dur, pitch, velocity: vel, voice_id: vid });
            v += 1;
        }
        prev = clone_i16(voiced.span());
        t += s.dur;
        i += 1;
    }
    out
}

/// Render a chord sequence given as harmonic states (used by elevators/turnarounds).
fn render_states(
    states: Span<HarmonicState>, base_ch: u8, beat: u32, start_tick: u32, vel: u8,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut prev: Array<i16> = ArrayTrait::new();
    let mut t: u32 = start_tick;
    let mut i: usize = 0;
    loop {
        if i >= states.len() {
            break;
        }
        let st = states.at(i);
        let mut pcs: Array<u8> = ArrayTrait::new();
        let mut pi: usize = 0;
        loop {
            if pi >= st.active_pcs.len() {
                break;
            }
            pcs.append(*st.active_pcs.at(pi));
            pi += 1;
        }
        let voiced = voicelead(prev.span(), pcs.span(), LO, HI, i.try_into().unwrap());
        let mut v: usize = 0;
        loop {
            if v >= voiced.len() {
                break;
            }
            let vid: u32 = base_ch.into() + v.try_into().unwrap();
            out
                .append(
                    NoteEvent {
                        time: t,
                        duration: beat,
                        pitch: (*voiced.at(v)).try_into().unwrap(),
                        velocity: vel,
                        voice_id: vid,
                    },
                );
            v += 1;
        }
        prev = clone_i16(voiced.span());
        t += beat;
        i += 1;
    }
    out
}

/// Append a monophonic pitch-class path as a legato single-voice line.
fn append_mono_pcs(
    ref out: Array<NoteEvent>, path: Span<u8>, ref prev_kn: i16, ref t: u32, ch: u8, vel: u8,
) {
    let mut j: usize = 0;
    loop {
        if j >= path.len() {
            break;
        }
        let pc = *path.at(j);
        let kn = voicelead(
            array![prev_kn].span(), array![pc].span(), LO, HI, t.try_into().unwrap(),
        );
        prev_kn = *kn.at(0);
        out
            .append(
                NoteEvent {
                    time: t,
                    duration: 1,
                    pitch: prev_kn.try_into().unwrap(),
                    velocity: vel,
                    voice_id: ch.into(),
                },
            );
        t += 1;
        j += 1;
    };
}

fn export(ref events: Array<Message>, min_notes: u32) {
    let midi = Midi { events: events.span() };
    generate_parser_format(@midi);
    assert(output_midi_object(@midi).len() >= 22, 'midi bytes');
    let _ = min_notes;
}

fn new_events() -> Array<Message> {
    let mut events: Array<Message> = ArrayTrait::new();
    events.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
    events
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
                            Option::Some(t) => {
                                println!(
                                    "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }})",
                                    *SetTempo.tempo,
                                    t,
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
        }
    }
}

// ──────────────────────────────────────────────────────────
// 01 — Elevator block etude: 6th-diminished elevator up, then a bounce,
//      rendered as 4-voice closed blocks. You hear the stable→diminished
//      alternation rising through the field.
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(8000000000000)]
fn barry_showcase_01_elevator_block_etude_midi_test() {
    let mut events = new_events();
    let up_start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let up = generate_elevator_path(up_start, ElevatorDirection::Up, 12);
    let n1 = render_states(up.span(), 0, 4, 0, 84);
    let mut total = emit_voiced(ref events, @n1, 0);
    let mut at = end_tick(@n1).into() * TICK_US;
    append_marker(ref events, at);
    at += TICK_US * 2;

    let bounce_start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let bounce = generate_elevator_bounce_path(bounce_start, 16);
    let n2 = render_states(bounce.span(), 0, 4, 0, 84);
    total += emit_voiced(ref events, @n2, at);

    assert(total >= 24, 'elevator notes');
    export(ref events, 24);
}

// ──────────────────────────────────────────────────────────
// 02 — Voicing-styles tour: the same ii–V–I–VI played five times, once per
//      idiomatic voicing style (closed, drop-2, drop-3, rootless shell,
//      two-hand block), separated by markers so the textures are A/B-able.
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(12000000000000)]
fn barry_showcase_02_voicing_styles_tour_midi_test() {
    let mut events = new_events();
    let styles = array![
        BarryVoicingStyle::ClosedPosition,
        BarryVoicingStyle::DropTwo,
        BarryVoicingStyle::DropThree,
        BarryVoicingStyle::RootlessShell,
        BarryVoicingStyle::TwoHandBlock,
    ];
    let mut at: u64 = 0;
    let mut total: u32 = 0;
    let mut si: usize = 0;
    loop {
        if si >= styles.len() {
            break;
        }
        let prog = two_five_one_six(8);
        let notes = render_comp(
            prog.span(), *styles.at(si), VoiceMotionPolicy::MinimalMotion, 0, 0, 82,
        );
        total += emit_voiced(ref events, @notes, at);
        at += end_tick(@notes).into() * TICK_US;
        append_marker(ref events, at);
        at += TICK_US * 2;
        si += 1;
    }
    assert(total >= 40, 'styles notes');
    export(ref events, 40);
}

// ──────────────────────────────────────────────────────────
// 03 — Voice-motion tour: the same progression under five motion policies
//      (minimal, parallel, contrary outer, oblique top, oblique bass).
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(12000000000000)]
fn barry_showcase_03_voice_motion_tour_midi_test() {
    let mut events = new_events();
    let policies = array![
        VoiceMotionPolicy::MinimalMotion,
        VoiceMotionPolicy::Parallel,
        VoiceMotionPolicy::ContraryOuterVoices,
        VoiceMotionPolicy::ObliqueTopVoice,
        VoiceMotionPolicy::ObliqueBass,
    ];
    let mut at: u64 = 0;
    let mut total: u32 = 0;
    let mut pi: usize = 0;
    loop {
        if pi >= policies.len() {
            break;
        }
        let prog = two_five_one_six(8);
        let notes = render_comp(
            prog.span(), BarryVoicingStyle::FourWayClose, *policies.at(pi), 0, 0, 82,
        );
        total += emit_voiced(ref events, @notes, at);
        at += end_tick(@notes).into() * TICK_US;
        append_marker(ref events, at);
        at += TICK_US * 2;
        pi += 1;
    }
    assert(total >= 40, 'motion notes');
    export(ref events, 40);
}

// ──────────────────────────────────────────────────────────
// 04 — Turnaround suite: five Barry turnaround grammars in C, back to back,
//      block-voiced (6-2-5, 1-6-2-5, tritone chain, diminished passing,
//      backdoor 6th-dim).
// ──────────────────────────────────────────────────────────
fn render_turnaround(kind: BarryTurnaroundKind, beat: u32, start_tick: u32) -> Array<NoteEvent> {
    let steps = generate_barry_turnaround(0, kind, 16);
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut prev: Array<i16> = ArrayTrait::new();
    let mut t: u32 = start_tick;
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
        let pcs = stable_chord_tones_for(*step.tonic_pc, *step.family);
        let voiced = voicelead(prev.span(), pcs.span(), LO, HI, i.try_into().unwrap());
        let dur: u32 = (*step.duration_steps).into() * beat;
        let mut v: usize = 0;
        loop {
            if v >= voiced.len() {
                break;
            }
            out
                .append(
                    NoteEvent {
                        time: t,
                        duration: dur,
                        pitch: (*voiced.at(v)).try_into().unwrap(),
                        velocity: 80,
                        voice_id: v.try_into().unwrap(),
                    },
                );
            v += 1;
        }
        prev = clone_i16(voiced.span());
        t += dur;
        i += 1;
    }
    out
}

#[ignore]
#[test]
#[available_gas(12000000000000)]
fn barry_showcase_04_turnaround_suite_midi_test() {
    let mut events = new_events();
    let kinds = array![
        BarryTurnaroundKind::SixToTwoFive,
        BarryTurnaroundKind::OneSixTwoFive,
        BarryTurnaroundKind::TritoneDominantChain,
        BarryTurnaroundKind::DiminishedPassingTurnaround,
        BarryTurnaroundKind::BackdoorSixDim,
    ];
    let mut at: u64 = 0;
    let mut total: u32 = 0;
    let mut ki: usize = 0;
    loop {
        if ki >= kinds.len() {
            break;
        }
        let notes = render_turnaround(*kinds.at(ki), 2, 0);
        total += emit_voiced(ref events, @notes, at);
        at += end_tick(@notes).into() * TICK_US;
        append_marker(ref events, at);
        at += TICK_US * 2;
        ki += 1;
    }
    assert(total >= 40, 'turnaround notes');
    export(ref events, 40);
}

// ──────────────────────────────────────────────────────────
// 05 — Bebop line-cell melody: a single-voice line stitched from explicit
//      Barry line cells (approaches, enclosures, double-chromatic, diminished
//      arpeggio, scale run, turnback) landing on C-major-6 chord tones.
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(8000000000000)]
fn barry_showcase_05_bebop_line_cells_midi_test() {
    let mut events = new_events();
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    // (cell, target_pc) — targets are C6 chord tones C E G A.
    let cells = array![
        (BarryLineCell::HalfStepApproachBelow, 0_u8),
        (BarryLineCell::EnclosureUpperLower, 4),
        (BarryLineCell::DoubleChromaticBelow, 7),
        (BarryLineCell::DiminishedArpeggio, 9),
        (BarryLineCell::ScaleRun4, 4),
        (BarryLineCell::EnclosureLowerUpper, 0),
        (BarryLineCell::DiatonicUpperNeighbor, 7),
        (BarryLineCell::TurnbackCell, 0),
    ];
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut prev_kn: i16 = 64;
    let mut t: u32 = 0;
    let mut pass: u32 = 0;
    loop {
        if pass >= 3 {
            break;
        }
        let mut i: usize = 0;
        loop {
            if i >= cells.len() {
                break;
            }
            let (cell, target) = *cells.at(i);
            let fresh = initial_harmonic_state(0, ChordFamily::Major6Dim);
            // Alternate ascending/descending run direction each pass for variety.
            let dir: i8 = if pass % 2 == 0 {
                1
            } else {
                -1
            };
            let path = realize_line_cell(cell, target, fresh, dir);
            append_mono_pcs(ref out, path.span(), ref prev_kn, ref t, 0, 88);
            i += 1;
        }
        pass += 1;
    }
    let _ = state;
    let total = emit_channel(ref events, @out, 0, 0, 0);
    assert(total >= 16, 'line cell notes');
    export(ref events, 16);
}

// ──────────────────────────────────────────────────────────
// 06 — Motif/ornamentation melody over a Barry comp.
//      Lower voices: a looped ii–V–I–VI drop-two block under contrary outer
//      motion. Top voice: a motif developed into an AABA period and then run
//      through the ornamentation engine, transposed an octave up.
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(20000000000000)]
fn barry_showcase_06_motif_ornamented_over_comp_midi_test() {
    let mut events = new_events();
    let mode_id: u8 = 0;

    // Comp: two passes of the progression for length.
    let mut comp_at: u64 = 0;
    let mut total: u32 = 0;
    let mut pass: u32 = 0;
    loop {
        if pass >= 2 {
            break;
        }
        let prog = two_five_one_six(8);
        let comp = render_comp(
            prog.span(),
            BarryVoicingStyle::DropTwo,
            VoiceMotionPolicy::ContraryOuterVoices,
            0,
            0,
            70,
        );
        total += emit_voiced(ref events, @comp, comp_at);
        comp_at += end_tick(@comp).into() * TICK_US;
        pass += 1;
    }

    // Melody: develop a motif into an AABA period, then ornament it.
    let theme = motif_from_degrees(array![0_i32, 2, 4, 3, 7, 5, 9, 7], 7, 0);
    let durations = array![2_u32, 1, 1, 1, 4, 1, 1, 2];
    let period = develop_period_grouped(@theme, @durations, 50470912, 2);
    let melody = developed_to_ornamented_note_events(@period, 41, mode_id, ORN_FILL_MIN_STEP);
    total += emit_channel(ref events, @melody, MELODY_CH, 0, 1);

    assert(total >= 60, 'combo notes');
    export(ref events, 60);
}

// ──────────────────────────────────────────────────────────
// 07 — Neighbor borrowing + limitation, full labyrinth planner.
//      A longer seed-driven phrase that exercises the planner end to end
//      (texture, limitation, line cells, borrowing, voicing).
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(20000000000000)]
fn barry_showcase_07_labyrinth_borrowing_limitation_midi_test() {
    let mut events = new_events();
    let seed: felt252 = 0xB200_0000_0700_0BEE;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 48, BarryRuleProfile::BebopLine, LO, HI,
    );
    let total = emit_voiced(ref events, @phrase.note_events, 0);
    assert(total >= 24, 'labyrinth notes');
    export(ref events, 24);
}

// ──────────────────────────────────────────────────────────
// 08 — Harmonized bebop line (Barry Harris block-chord movement).
//
//      A bebop line built from Barry line cells (like demo 05) is harmonized
//      with sparse rhythmic comping. At each selected comping onset, the
//      sounding melody note becomes the TOP of a 4-note block chord.
//        - melody note is a C6 chord tone (C E G A) -> voiced as the C6 chord
//        - any other note (diatonic passing OR chromatic approach) -> voiced as
//          the diminished-7th chord that contains that note
//      This is Barry's 6th-diminished harmonization: chord tones get the 6th
//      chord, everything in between gets a diminished chord. The chords move
//      only on the comping rhythm, leaving the line room to breathe.
//      Melody: channel 0 (top voice). Block lower voices: channels 1..3.
// ──────────────────────────────────────────────────────────

#[ignore]
#[test]
#[available_gas(20000000000000)]
fn barry_showcase_08_bebop_line_harmonized_midi_test() {
    let mut events = new_events();
    // A bebop-flavoured cell vocabulary: chromatic approaches and enclosures are
    // welcome now, because each note is harmonized with a chord that contains it.
    let cells = array![
        BarryLineCell::HalfStepApproachBelow,
        BarryLineCell::EnclosureUpperLower,
        BarryLineCell::DoubleChromaticBelow,
        BarryLineCell::ScaleRun4,
        BarryLineCell::DiatonicUpperNeighbor,
        BarryLineCell::EnclosureLowerUpper,
        BarryLineCell::HalfStepApproachAbove,
        BarryLineCell::ScaleRun3,
    ];
    let targets = array![0_u8, 4, 7, 9]; // land on C6 chord tones

    let mut melody: Array<NoteEvent> = ArrayTrait::new();
    let mut prev_kn: i16 = 72;
    let mut t: u32 = 0;
    let mut step: u32 = 0;
    loop {
        if step >= 24 {
            break;
        }
        let ci: usize = (step % 8).try_into().unwrap();
        let cell = *cells.at(ci);
        let target = *targets.at((step % 4).try_into().unwrap());
        // Sweep up for the first half of each pass, back down for the second.
        let dir: i8 = if (step / 4) % 2 == 0 {
            1
        } else {
            -1
        };
        let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
        let path = realize_line_cell(cell, target, state, dir);

        let mut j: usize = 0;
        loop {
            if j >= path.len() {
                break;
            }
            let pc = *path.at(j);
            let kn = voicelead(
                array![prev_kn].span(), array![pc].span(), 64, 84, t.try_into().unwrap(),
            );
            let mkn = *kn.at(0);
            prev_kn = mkn;
            melody
                .append(
                    NoteEvent {
                        time: t,
                        duration: 1,
                        pitch: mkn.try_into().unwrap(),
                        velocity: 96,
                        voice_id: 0,
                    },
                );
            t += 1;
            j += 1;
        }
        step += 1;
    }

    // Three short hits per eight-note cycle: enough harmonic definition without
    // turning every melodic passing tone into a block-chord attack.
    let comp_rhythm = TimelineRhythm {
        n: 8,
        onset_mask: 0x49_u32,
        onset_count: 3,
        family_id: 0,
        variant_id: 0,
        rotation: 0,
        preset_id: 0,
        source_kind: 2,
    };
    let comp_plan = rhythmic_comping_plan(comp_rhythm, 1, 0, 64, 1);
    let comp = harmonize_barry_block_chords(melody.span(), @comp_plan);

    let mut total = emit_voiced(ref events, @comp, 0);
    total += emit_voiced(ref events, @melody, 0);
    assert(total >= 40, 'harmonized notes');
    export(ref events, 40);
}

// ──────────────────────────────────────────────────────────
// 09 — Renaissance ornamented-canon leader with sparse Barry harmony.
//
//      Uses the exact seed/config/length/loop count of
//      `renaissance_canon_long_3voice_ornamented_midi_test`, but discards both
//      follower voices. Barry block chords attack only on structural downbeats
//      and sustain beneath the leader's Montanos-style passing divisions.
// ──────────────────────────────────────────────────────────
fn renaissance_ornamented_leader_two_loops() -> (Array<NoteEvent>, u32, u8) {
    let (canon, subdivisions) = generate_ornamented_canon(4343, 4, 36);
    let canon_events = canon_to_ornamented_note_events(@canon, subdivisions.span());
    let cycle_ticks = (canon.leader_degrees.len() + canon.voices.len() - 1) * canon.time_unit;
    let mut leader: Array<NoteEvent> = ArrayTrait::new();
    let mut loop_i: u32 = 0;
    loop {
        if loop_i >= 2 {
            break;
        }
        let offset = loop_i * cycle_ticks;
        let mut i: u32 = 0;
        loop {
            if i >= canon_events.len() {
                break;
            }
            let event = canon_events.at(i);
            if *event.voice_id == 0 {
                leader
                    .append(
                        NoteEvent {
                            time: offset + *event.time,
                            duration: *event.duration,
                            pitch: *event.pitch,
                            velocity: *event.velocity,
                            voice_id: 0,
                        },
                    );
            }
            i += 1;
        }
        loop_i += 1;
    }
    (leader, canon.time_unit, canon.tonic_keynum % 12)
}

#[ignore]
#[test]
#[available_gas(20000000000000)]
fn barry_showcase_09_renaissance_leader_sparse_harmony_midi_test() {
    let mut events = new_events();
    let (leader, time_unit, tonic_pc) = renaissance_ornamented_leader_two_loops();
    let plan = regular_downbeat_plan(time_unit, tonic_pc, 58, 1);
    let comp = harmonize_barry_block_chords(leader.span(), @plan);

    assert(leader.len() > 72, 'ornamented leader');
    assert(comp.len() < leader.len() * 3, 'sparse harmony');

    let renaissance_step_us: u64 = 250000;
    let mut total = emit_voiced_at_step(ref events, @comp, 0, renaissance_step_us);
    total += emit_voiced_at_step(ref events, @leader, 0, renaissance_step_us);
    export(ref events, total);
}

// ──────────────────────────────────────────────────────────
// 10 — Same Renaissance leader and harmonic rhythm as demo 09, drop-two voiced.
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(20000000000000)]
fn barry_showcase_10_renaissance_leader_sparse_drop_two_midi_test() {
    let mut events = new_events();
    let (leader, time_unit, tonic_pc) = renaissance_ornamented_leader_two_loops();
    let close_plan = regular_downbeat_plan(time_unit, tonic_pc, 58, 1);
    let drop_two_plan = with_harmonization_voicing_style(close_plan, BarryVoicingStyle::DropTwo);
    let comp = harmonize_barry_block_chords(leader.span(), @drop_two_plan);

    assert(leader.len() > 72, 'ornamented leader');
    assert(comp.len() < leader.len() * 3, 'sparse drop two');

    let renaissance_step_us: u64 = 250000;
    let mut total = emit_voiced_at_step(ref events, @comp, 0, renaissance_step_us);
    total += emit_voiced_at_step(ref events, @leader, 0, renaissance_step_us);
    export(ref events, total);
}

// ──────────────────────────────────────────────────────────
// 11 — Same Renaissance leader and sparse downbeats, with evolving Barry motion.
//
//      The harmonic-motion cycle combines a home-key upward elevator, an
//      upper-neighbor borrowed-key elevator bounce, a lower-neighbor downward
//      elevator, and a final home-key bounce. Each state chooses stable or
//      diminished treatment while preserving the sounding melody as chord top.
// ──────────────────────────────────────────────────────────
#[ignore]
#[test]
#[available_gas(20000000000000)]
fn barry_showcase_11_renaissance_leader_elevators_neighbor_keys_midi_test() {
    let mut events = new_events();
    let (leader, time_unit, tonic_pc) = renaissance_ornamented_leader_two_loops();
    let mut motion: Array<BarryHarmonicMotionStep> = ArrayTrait::new();

    let home_up = generate_elevator_path(
        initial_harmonic_state(tonic_pc, ChordFamily::Major6Dim), ElevatorDirection::Up, 8,
    );
    append_harmonic_motion(ref motion, harmonization_motion_from_states(home_up.span()).span());

    let upper_borrow = borrow_neighbor_state(
        initial_harmonic_state(tonic_pc, ChordFamily::Major6Dim),
        BarryBorrowKind::BorrowUpperNeighbor,
        8,
    );
    let upper_bounce = generate_elevator_bounce_path(upper_borrow.harmonic_state, 8);
    append_harmonic_motion(
        ref motion, harmonization_motion_from_states(upper_bounce.span()).span(),
    );

    let lower_borrow = borrow_neighbor_state(
        initial_harmonic_state(tonic_pc, ChordFamily::Major6Dim),
        BarryBorrowKind::BorrowLowerNeighbor,
        8,
    );
    let lower_down = generate_elevator_path(
        lower_borrow.harmonic_state, ElevatorDirection::Down, 8,
    );
    append_harmonic_motion(ref motion, harmonization_motion_from_states(lower_down.span()).span());

    let home_bounce = generate_elevator_bounce_path(
        initial_harmonic_state(tonic_pc, ChordFamily::Major6Dim), 8,
    );
    append_harmonic_motion(ref motion, harmonization_motion_from_states(home_bounce.span()).span());

    let close_plan = regular_downbeat_plan(time_unit, tonic_pc, 58, 1);
    let drop_two_plan = with_harmonization_voicing_style(close_plan, BarryVoicingStyle::DropTwo);
    let comp = harmonize_barry_block_chords_with_motion(
        leader.span(), @drop_two_plan, motion.span(),
    );

    assert(motion.len() == 32, 'motion cycle');
    assert(leader.len() > 72, 'ornamented leader');
    assert(comp.len() < leader.len() * 3, 'sparse moving harmony');

    let renaissance_step_us: u64 = 250000;
    let mut total = emit_voiced_at_step(ref events, @comp, 0, renaissance_step_us);
    total += emit_voiced_at_step(ref events, @leader, 0, renaissance_step_us);
    export(ref events, total);
}

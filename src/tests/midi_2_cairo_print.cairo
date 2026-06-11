#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use koji::math::Time;
    use koji::lcg::{LCG, LCGImpl, RNGTrait};
    use koji::midi::euclidean::euclidean;
    use koji::midi::modes::mode_steps;
    use koji::midi::output::output_midi_object;
    use koji::midi::pitch::{
        get_notes_of_key, keynum_to_pc, modal_transposition, pc_to_keynum,
    };
    use koji::midi::modes::dorian_steps;
    use koji::midi::types::{Direction, Message, Midi, Modes, NoteOff, NoteOn, PitchClass, SetTempo};
    use koji::sine_wave::{
        contour_to_duration_symmetric_us, long_sequence_timing_wave_freq, modal_contour_wave,
        MODAL_CONTOUR_LEN, MODAL_CONTOUR_MAX, MODAL_CONTOUR_MIN, textured_span_ticks,
    };
    use koji::composition::envelope::{TimePoint, PitchRangeEnvelope, range_at};
    use koji::composition::tendency_mask::pick_pitch_in_range;
    use koji::composition::rhythmic_tiling::{
        generate_rhythmic_canon, generate_rhythmic_canon_for_cycle,
        generate_rhythmic_canon_for_cycle_min_voices, canon_to_events, RhythmicVoice,
    };
    use koji::composition::known_timeline_rhythms::all_preset_ids;
    use koji::composition::phase_rhythm::{phase_orbit_length, render_phase_plan, PhaseRhythmPlan};
    use koji::composition::timeline_rhythm::{
        PRESET_SON, SYMMETRY_ANY, SYMMETRY_WEAK, TimelineRhythm, TimelineSelectionProfile,
        generate_profiled_son_family_timeline, generate_son_family_timeline, known_timeline,
        next_known_morph, son_family_candidate_at_index, timeline_accent, timeline_to_events,
    };
    use koji::composition::symmetry_engine::{
        add_pitch, generate_world_chord, generate_world_motif, get_pitch_at_index, get_world_by_id,
        transpose_world, world_pc_to_midi,
    };
    use koji::composition::messiaen_modes::{
        chord_pcs_to_midi, generate_chord, generate_diminished_symmetry_chord,
        generate_melody_pitch_classes, mode_pc_to_midi,
    };
    use koji::composition::counterpoint::{
        CounterpointParams, VoicePlacement, generate_counterpoint, motion_bias_balanced,
        motion_bias_contrary, motion_bias_parallel, violates_forbidden_interval,
    };
    use koji::composition::counterpoint::REST_PITCH;
    use koji::composition::counterpoint_canon::{
        CanonHarmonyPlan, harmony_plan_is_rest, lydian_pitch_world_mask,
        pitch_from_harmony_plan, plan_canon_harmony, plan_lydian_canon_harmony,
        uniform_mode_timeline, count_tiling_voices,
    };
    use koji::composition::symmetry_engine::has_pitch;
    use koji::composition::melodic_motion::{ORN_FILL_MATERIAL, ORN_FILL_MIN_STEP};
    use koji::composition::jazz_harmony::{
        turnaround_has_tritone_sub, turnaround_plan_from_canon_seed,
    };
use koji::composition::melodic_canon::{
    generate_melodic_canon, generate_melodic_canon_with_params, generate_ornamented_canon,
    generate_profiled_ornamented_canon,
    generate_jazz_improv_ornamented_canon, generate_jazz_improv_ornamented_canon_light,
    generate_jazz_improv_harmonic_walk_ornamented_canon,
    generate_pentatonic_smooth_ornamented_canon,
        generate_ligeti_banded_canon, canon_to_note_events,
        canon_to_ornamented_note_events, canon_to_ornamented_note_events_with_fill,
        remap_events_with_timing_wave, NoteEvent,
    };
    use koji::composition::ornamentation_v2::canon::v2_note_to_legacy;
    use koji::composition::ornamentation_v2::engine::{default_config, ornament_canon};
    use koji::composition::ornamentation_v2::profiles::profile_common_practice;
    use koji::composition::ornamentation_v2::types::{
        all_enabled_ornaments, HarmonyEvent, WORKFLOW_CANON_FIRST,
    };
    use koji::composition::canon_entry_rules::{
        EntryLagCanonConfig, config_three_voice_5b_8va_lag2,
    };
    use koji::composition::entry_lag_canon::{
        generate_entry_lag_ornamented_canon, canon_texture_span,
    };
    use koji::composition::baroque_improvisation::{
        generate_baroque_cadential_improvisation,
        generate_baroque_cadential_improvisation_with_transforms,
        baroque_to_note_events, validate_baroque_realization,
        MODULE_CADENCE_FRENCH_LONG5, MODULE_CADENCE_DESC_3451,
        MODULE_CADENZA_DOPPIA, MODULE_FAUXBOURDON_76, MODULE_ROMANESCA,
    };
    use koji::composition::parsimonious_progression::{
        generate_parsimonious_progression, generate_ornamented_parsimonious_progression,
        voice_leading_smooth, no_minor_ninth_in_chords,
    };
    use koji::composition::voice_leading::{
        generate_ornamented_min_motion_progression, ornamented_min_motion_cycle_ticks,
    };
    use koji::composition::harmonic_walk::{
        generate_ornamented_harmonic_walk_progression, harmonic_walk_progression_cycle_ticks,
        harmonic_walk_demo_seed, jazz_canon_walk_demo_seed,
    };
    use koji::composition::transform::{
        apply_to_object, assemble, MusicalObject, Pipeline, PlaneId, PlaneOp, U32Pair,
    };
    use koji::rng::{LCGRandomSource, RandomSource};

    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn midi_to_cairo_file_test() {
        // q1q -> {
        // q2q -> }
        // q3q -> ;
        // q4q -> _
        println!("use koji::math::Time;");
        println!(
            "use koji::midi::types::{{Midi, Message, NoteOn, NoteOff, SetTempo, TimeSignature, ControlChange, PitchWheel, AfterTouch, PolyTouch, Modes}};",
        );
        println!("fn midi() -> Midi {{");
        println!("Midi {{");
        println!("events: array![");

        let mut eventlist = ArrayTrait::<Message>::new();

        let newtempo = SetTempo { tempo: 0, time: Option::Some(33242) };

        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 100 };

        let notetwotime: Time = 1000;

        let newnoteon2 = NoteOn { channel: 0, note: 71, velocity: 100, time: notetwotime };

        let newnoteon3 = NoteOn { channel: 0, note: 88, velocity: 100, time: 2000 };

        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };

        let newnoteoff2 = NoteOff { channel: 0, note: 71, velocity: 100, time: 4000 };

        let newnoteoff3 = NoteOff { channel: 0, note: 88, velocity: 100, time: 5000 };
        let tempomessage = Message::SET_TEMPO((newtempo));

        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        eventlist.append(tempomessage);

        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);

        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };

        midi_2_cairo_print(@midiobj);
        // put midi messages here
        println!("].span()");
        println!("   }}");
        println!("}}");
    }

    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn midi_to_cairo_file_output_test() {
        // This test generates clean Cairo code output
        let mut eventlist = ArrayTrait::<Message>::new();

        let newtempo = SetTempo { tempo: 251046, time: Option::Some(0) };
        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 100 };
        let newnoteon2 = NoteOn { channel: 0, note: 71, velocity: 100, time: 1000 };
        let newnoteon3 = NoteOn { channel: 0, note: 88, velocity: 100, time: 2000 };
        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };
        let newnoteoff2 = NoteOff { channel: 0, note: 71, velocity: 100, time: 4000 };
        let newnoteoff3 = NoteOff { channel: 0, note: 88, velocity: 100, time: 5000 };

        let tempomessage = Message::SET_TEMPO((newtempo));
        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));
        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        eventlist.append(tempomessage);
        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);
        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };

        // Generate clean Cairo code output
        generate_cairo_code(@midiobj);
    }

    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn midi_to_parser_format_test() {
        // This test generates individual MIDI event lines for the TypeScript parser
        let mut eventlist = ArrayTrait::<Message>::new();

        let newtempo = SetTempo { tempo: 251046, time: Option::Some(0) };
        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 100 };
        let newnoteon2 = NoteOn { channel: 0, note: 71, velocity: 100, time: 1000 };
        let newnoteon3 = NoteOn { channel: 0, note: 88, velocity: 100, time: 2000 };
        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };
        let newnoteoff2 = NoteOff { channel: 0, note: 71, velocity: 100, time: 4000 };
        let newnoteoff3 = NoteOff { channel: 0, note: 88, velocity: 100, time: 5000 };

        let tempomessage = Message::SET_TEMPO((newtempo));
        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));
        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        eventlist.append(tempomessage);
        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);
        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };

        // Generate individual MIDI event lines for parser
        generate_parser_format(@midiobj);
    }

    fn midi_2_cairo_print(self: @Midi) -> Midi { //Symbol mapping for Printout and reformatting    
        // q1q -> {
        // q2q -> }
        // q3q -> ;
        // q4q -> _

        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(NoteOn) => {
                            let note = *NoteOn.note;
                            let channel = *NoteOn.channel;
                            let velocity = *NoteOn.velocity;
                            let time = *NoteOn.time;
                            println!(
                                "Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                                channel,
                                note,
                                velocity,
                                time,
                            );
                        },
                        Message::NOTE_OFF(NoteOff) => {
                            let note = *NoteOff.note;
                            let channel = *NoteOff.channel;
                            let velocity = *NoteOff.velocity;
                            let time = *NoteOff.time;
                            println!(
                                "Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                                channel,
                                note,
                                velocity,
                                time,
                            );
                        },
                        Message::SET_TEMPO(_SetTempo) => {
                            println!(
                                "Message::SET_TEMPO(SetTempo {{ tempo: 251046, time: Option::Some(0) }}),",
                            );
                        },
                        Message::TIME_SIGNATURE(_TimeSignature) => {},
                        Message::CONTROL_CHANGE(_ControlChange) => {},
                        Message::PITCH_WHEEL(_PitchWheel) => {},
                        Message::AFTER_TOUCH(_AfterTouch) => {},
                        Message::POLY_TOUCH(_PolyTouch) => {},
                        Message::PROGRAM_CHANGE(_ProgramChange) => {},
                        Message::SYSTEM_EXCLUSIVE(_SystemExclusive) => {},
                    }
                },
                Option::None(_) => { break; },
            };
        }

        // Create a new Midi object with the modified event list
        Midi { events: eventlist.span() }
    }

    fn generate_cairo_code(self: @Midi) {
        // Generate clean Cairo code without test output
        println!("use koji::math::Time;");
        println!(
            "use koji::midi::types::{{Midi, Message, NoteOn, NoteOff, SetTempo, TimeSignature, ControlChange, PitchWheel, AfterTouch, PolyTouch, Modes}};",
        );
        println!("");
        println!("fn midi() -> Midi {{");
        println!("    Midi {{");
        println!("        events: array![");

        let mut ev = self.clone().events;

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(NoteOn) => {
                            let note = *NoteOn.note;
                            let channel = *NoteOn.channel;
                            let velocity = *NoteOn.velocity;
                            let time = *NoteOn.time;
                            println!(
                                "            Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                                channel,
                                note,
                                velocity,
                                time,
                            );
                        },
                        Message::NOTE_OFF(NoteOff) => {
                            let note = *NoteOff.note;
                            let channel = *NoteOff.channel;
                            let velocity = *NoteOff.velocity;
                            let time = *NoteOff.time;
                            println!(
                                "            Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                                channel,
                                note,
                                velocity,
                                time,
                            );
                        },
                        Message::SET_TEMPO(SetTempo) => {
                            let tempo = *SetTempo.tempo;
                            match *SetTempo.time {
                                Option::Some(time_val) => {
                                    println!(
                                        "            Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }}),",
                                        tempo,
                                        time_val,
                                    );
                                },
                                Option::None(_) => {
                                    println!(
                                        "            Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::None }}),",
                                        tempo,
                                    );
                                },
                            };
                        },
                        Message::TIME_SIGNATURE(_TimeSignature) => {},
                        Message::CONTROL_CHANGE(_ControlChange) => {},
                        Message::PITCH_WHEEL(_PitchWheel) => {},
                        Message::AFTER_TOUCH(_AfterTouch) => {},
                        Message::POLY_TOUCH(_PolyTouch) => {},
                        Message::PROGRAM_CHANGE(_ProgramChange) => {},
                        Message::SYSTEM_EXCLUSIVE(_SystemExclusive) => {},
                    }
                },
                Option::None(_) => { break; },
            };
        }

        println!("        ].span()");
        println!("    }}");
        println!("}}");
    }

    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn voicing_chords_10s_test() {
        // 10 chords × 2s = 20s total. Key: C Lydian (C D E F# G A B).
        // Chord roots are selected pseudo-randomly by LCG, mapped to Lydian scale degrees.
        //
        // C Lydian scale array (A3..E5), 12 tones:
        // Idx: 0   1   2   3   4   5   6   7   8   9   10  11
        //      A3  B3  C4  D4  E4  F#4 G4  A4  B4  C5  D5  E5
        //      57  59  60  62  64  66  67  69  71  72  74  76
        //
        // LCG: state=13, mult=5, inc=1, mod=8 → sequence [2,3,0,1,6,7,4,5,2,3]
        // root_index = val % 5 + 1  →  scale positions 1..5  (B3..F#4)
        // Roots: D4, E4, B3, C4, C4, D4, F#4, B3, D4, E4
        //
        // Chord  Voicing                         Notes (computed)
        //   0    seventh_and_third   [1↓,r,2↑]  C4 D4 F#4    60,62,66
        //   1    triad_root_position [r,2↑,4↑]  E4 G4 B4     64,67,71
        //   2    triad_first_inv     [r,2↑,5↑]  B3 D4 G4     59,62,67
        //   3    triad_second_inv    [r,3↑,5↑]  C4 F#4 A4    60,66,69
        //   4    maj_7_no_root_3rd   [1↓,r,2↑,4↑] B3 C4 E4 G4  59,60,64,67
        //   5    seventh_and_third   [1↓,r,2↑]  C4 D4 F#4    60,62,66
        //   6    maj_9_no_root_add6  [1↓,r,1↑,2↑,5↑] E4 F#4 G4 A4 D5  64,66,67,69,74
        //   7    plus_four_7_2       [r,2↑,3↑,6↑]  B3 D4 E4 A4  59,62,64,69
        //   8    plus_four_7         [1↓,r,2↑,3↑,5↑] C4 D4 F#4 G4 B4  60,62,66,67,71
        //   9    maj_7_no_root_add6  [1↓,r,2↑,5↑]  D4 E4 G4 C5  62,64,67,72
        //
        // Total: 37 NoteOn + 37 NoteOff = 74 note events + 1 SetTempo = 75 events

        // C Lydian scale, A3..E5
        let scale: Array<u8> = array![57, 59, 60, 62, 64, 66, 67, 69, 71, 72, 74, 76];
        let s = scale.span();

        // LCG: deterministic pseudo-random root selection
        // Formula: val = (mult * state + inc) % mod
        // Sequence: [2, 3, 0, 1, 6, 7, 4, 5, 2, 3]
        let lcg_init = LCG { state: 13, multiplier: 5, increment: 1, modulus: 8 };
        let raw = lcg_init.getlist(10);

        // Verify LCG is deterministic
        assert!(*raw.at(0) == 2, "LCG[0] should be 2");
        assert!(*raw.at(1) == 3, "LCG[1] should be 3");
        assert!(*raw.at(2) == 0, "LCG[2] should be 0");
        assert!(*raw.at(3) == 1, "LCG[3] should be 1");

        // root index ri = val % 5 + 1  →  always in 1..5, leaving room for -1 step
        let ri0: usize = (*raw.at(0) % 5 + 1).into(); // 3 → D4
        let ri1: usize = (*raw.at(1) % 5 + 1).into(); // 4 → E4
        let ri2: usize = (*raw.at(2) % 5 + 1).into(); // 1 → B3
        let ri3: usize = (*raw.at(3) % 5 + 1).into(); // 2 → C4
        let ri4: usize = (*raw.at(4) % 5 + 1).into(); // 2 → C4
        let ri5: usize = (*raw.at(5) % 5 + 1).into(); // 3 → D4
        let ri6: usize = (*raw.at(6) % 5 + 1).into(); // 5 → F#4
        let ri7: usize = (*raw.at(7) % 5 + 1).into(); // 1 → B3
        let ri8: usize = (*raw.at(8) % 5 + 1).into(); // 3 → D4
        let ri9: usize = (*raw.at(9) % 5 + 1).into(); // 4 → E4

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        // Chord 0 (t=0..2s): root=D4, seventh_and_third [1↓, root, 2↑] → C4 D4 F#4
        let (n00, n01, n02) = (*s.at(ri0 - 1), *s.at(ri0), *s.at(ri0 + 2));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n00, velocity: 100, time: 0 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n01, velocity: 100, time: 0 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n02, velocity: 100, time: 0 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n00, velocity: 64, time: 2000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n01, velocity: 64, time: 2000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n02, velocity: 64, time: 2000000 }));

        // Chord 1 (t=2..4s): root=E4, triad_root_position [root, 2↑, 4↑] → E4 G4 B4
        let (n10, n11, n12) = (*s.at(ri1), *s.at(ri1 + 2), *s.at(ri1 + 4));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n10, velocity: 100, time: 2000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n11, velocity: 100, time: 2000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n12, velocity: 100, time: 2000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n10, velocity: 64, time: 4000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n11, velocity: 64, time: 4000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n12, velocity: 64, time: 4000000 }));

        // Chord 2 (t=4..6s): root=B3, triad_first_inversion [root, 2↑, 5↑] → B3 D4 G4
        let (n20, n21, n22) = (*s.at(ri2), *s.at(ri2 + 2), *s.at(ri2 + 5));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n20, velocity: 100, time: 4000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n21, velocity: 100, time: 4000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n22, velocity: 100, time: 4000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n20, velocity: 64, time: 6000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n21, velocity: 64, time: 6000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n22, velocity: 64, time: 6000000 }));

        // Chord 3 (t=6..8s): root=C4, triad_second_inversion [root, 3↑, 5↑] → C4 F#4 A4
        let (n30, n31, n32) = (*s.at(ri3), *s.at(ri3 + 3), *s.at(ri3 + 5));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n30, velocity: 100, time: 6000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n31, velocity: 100, time: 6000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n32, velocity: 100, time: 6000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n30, velocity: 64, time: 8000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n31, velocity: 64, time: 8000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n32, velocity: 64, time: 8000000 }));

        // Chord 4 (t=8..10s): root=C4, maj_7_no_root_3rd_inv [1↓, root, 2↑, 4↑] → B3 C4 E4 G4
        let (n40, n41, n42, n43) = (*s.at(ri4 - 1), *s.at(ri4), *s.at(ri4 + 2), *s.at(ri4 + 4));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n40, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n41, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n42, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n43, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n40, velocity: 64, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n41, velocity: 64, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n42, velocity: 64, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n43, velocity: 64, time: 10000000 }));

        // Chord 5 (t=10..12s): root=D4, seventh_and_third [1↓, root, 2↑] → C4 D4 F#4
        let (n50, n51, n52) = (*s.at(ri5 - 1), *s.at(ri5), *s.at(ri5 + 2));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n50, velocity: 100, time: 10000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n51, velocity: 100, time: 10000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n52, velocity: 100, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n50, velocity: 64, time: 12000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n51, velocity: 64, time: 12000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n52, velocity: 64, time: 12000000 }));

        // Chord 6 (t=12..14s): root=F#4, maj_9_no_root_add6 [1↓, root, 1↑, 2↑, 5↑] → E4 F#4 G4 A4 D5
        let (n60, n61, n62, n63, n64) = (
            *s.at(ri6 - 1), *s.at(ri6), *s.at(ri6 + 1), *s.at(ri6 + 2), *s.at(ri6 + 5),
        );
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n60, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n61, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n62, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n63, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n64, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n60, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n61, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n62, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n63, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n64, velocity: 64, time: 14000000 }));

        // Chord 7 (t=14..16s): root=B3, plus_four_7_2 [root, 2↑, 3↑, 6↑] → B3 D4 E4 A4
        let (n70, n71, n72, n73) = (*s.at(ri7), *s.at(ri7 + 2), *s.at(ri7 + 3), *s.at(ri7 + 6));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n70, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n71, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n72, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n73, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n70, velocity: 64, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n71, velocity: 64, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n72, velocity: 64, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n73, velocity: 64, time: 16000000 }));

        // Chord 8 (t=16..18s): root=D4, plus_four_7 [1↓, root, 2↑, 3↑, 5↑] → C4 D4 F#4 G4 B4
        let (n80, n81, n82, n83, n84) = (
            *s.at(ri8 - 1), *s.at(ri8), *s.at(ri8 + 2), *s.at(ri8 + 3), *s.at(ri8 + 5),
        );
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n80, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n81, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n82, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n83, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n84, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n80, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n81, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n82, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n83, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n84, velocity: 64, time: 18000000 }));

        // Chord 9 (t=18..20s): root=E4, maj_7_no_root_add6 [1↓, root, 2↑, 5↑] → D4 E4 G4 C5
        let (n90, n91, n92, n93) = (*s.at(ri9 - 1), *s.at(ri9), *s.at(ri9 + 2), *s.at(ri9 + 5));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n90, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n91, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n92, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n93, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n90, velocity: 64, time: 20000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n91, velocity: 64, time: 20000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n92, velocity: 64, time: 20000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n93, velocity: 64, time: 20000000 }));

        let midiobj = Midi { events: eventlist.span() };

        // Print the MIDI structure as Cairo code for human verification
        generate_cairo_code(@midiobj);

        // Verify event counts: 37 NoteOn + 37 NoteOff
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count == 37, "Expected 37 NoteOn events");
        assert!(note_off_count == 37, "Expected 37 NoteOff events");

        // Verify binary MIDI output begins with a valid MThd header
        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be 'M'");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be 'T'");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be 'h'");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be 'd'");
    }

    /// Builds on voicing_chords_10s_test: same 10 Lydian chords on channel 0, plus a new
    /// sine-contoured melody on channel 1 in C Lydian mode. The sine wave maps to Lydian
    /// scale indices for pitch and scales note durations.
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn voicing_chords_with_lydian_melody_test() {
        // ── Chord layer (channel 0) ──────────────────────────────────────────────────────
        // Identical to voicing_chords_10s_test: 10 chords × 2 s = 20 s, C Lydian.
        let scale: Array<u8> = array![57, 59, 60, 62, 64, 66, 67, 69, 71, 72, 74, 76];
        let s = scale.span();

        let lcg_init = LCG { state: 13, multiplier: 5, increment: 1, modulus: 8 };
        let raw = lcg_init.getlist(10);

        let ri0: usize = (*raw.at(0) % 5 + 1).into();
        let ri1: usize = (*raw.at(1) % 5 + 1).into();
        let ri2: usize = (*raw.at(2) % 5 + 1).into();
        let ri3: usize = (*raw.at(3) % 5 + 1).into();
        let ri4: usize = (*raw.at(4) % 5 + 1).into();
        let ri5: usize = (*raw.at(5) % 5 + 1).into();
        let ri6: usize = (*raw.at(6) % 5 + 1).into();
        let ri7: usize = (*raw.at(7) % 5 + 1).into();
        let ri8: usize = (*raw.at(8) % 5 + 1).into();
        let ri9: usize = (*raw.at(9) % 5 + 1).into();

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        // Chord 0 (0–2 s): seventh_and_third [1↓, root, 2↑]
        let (n00, n01, n02) = (*s.at(ri0 - 1), *s.at(ri0), *s.at(ri0 + 2));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n00, velocity: 100, time: 0 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n01, velocity: 100, time: 0 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n02, velocity: 100, time: 0 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n00, velocity: 64, time: 2000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n01, velocity: 64, time: 2000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n02, velocity: 64, time: 2000000 }));

        // Chord 1 (2–4 s): triad_root_position [root, 2↑, 4↑]
        let (n10, n11, n12) = (*s.at(ri1), *s.at(ri1 + 2), *s.at(ri1 + 4));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n10, velocity: 100, time: 2000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n11, velocity: 100, time: 2000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n12, velocity: 100, time: 2000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n10, velocity: 64, time: 4000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n11, velocity: 64, time: 4000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n12, velocity: 64, time: 4000000 }));

        // Chord 2 (4–6 s): triad_first_inversion [root, 2↑, 5↑]
        let (n20, n21, n22) = (*s.at(ri2), *s.at(ri2 + 2), *s.at(ri2 + 5));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n20, velocity: 100, time: 4000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n21, velocity: 100, time: 4000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n22, velocity: 100, time: 4000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n20, velocity: 64, time: 6000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n21, velocity: 64, time: 6000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n22, velocity: 64, time: 6000000 }));

        // Chord 3 (6–8 s): triad_second_inversion [root, 3↑, 5↑]
        let (n30, n31, n32) = (*s.at(ri3), *s.at(ri3 + 3), *s.at(ri3 + 5));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n30, velocity: 100, time: 6000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n31, velocity: 100, time: 6000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n32, velocity: 100, time: 6000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n30, velocity: 64, time: 8000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n31, velocity: 64, time: 8000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n32, velocity: 64, time: 8000000 }));

        // Chord 4 (8–10 s): maj_7_no_root_3rd_inv [1↓, root, 2↑, 4↑]
        let (n40, n41, n42, n43) = (*s.at(ri4 - 1), *s.at(ri4), *s.at(ri4 + 2), *s.at(ri4 + 4));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n40, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n41, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n42, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n43, velocity: 100, time: 8000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n40, velocity: 64, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n41, velocity: 64, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n42, velocity: 64, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n43, velocity: 64, time: 10000000 }));

        // Chord 5 (10–12 s): seventh_and_third [1↓, root, 2↑]
        let (n50, n51, n52) = (*s.at(ri5 - 1), *s.at(ri5), *s.at(ri5 + 2));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n50, velocity: 100, time: 10000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n51, velocity: 100, time: 10000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n52, velocity: 100, time: 10000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n50, velocity: 64, time: 12000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n51, velocity: 64, time: 12000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n52, velocity: 64, time: 12000000 }));

        // Chord 6 (12–14 s): maj_9_no_root_add6 [1↓, root, 1↑, 2↑, 5↑]
        let (n60, n61, n62, n63, n64) = (
            *s.at(ri6 - 1), *s.at(ri6), *s.at(ri6 + 1), *s.at(ri6 + 2), *s.at(ri6 + 5),
        );
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n60, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n61, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n62, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n63, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n64, velocity: 100, time: 12000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n60, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n61, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n62, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n63, velocity: 64, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n64, velocity: 64, time: 14000000 }));

        // Chord 7 (14–16 s): plus_four_7_2 [root, 2↑, 3↑, 6↑]
        let (n70, n71, n72, n73) = (*s.at(ri7), *s.at(ri7 + 2), *s.at(ri7 + 3), *s.at(ri7 + 6));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n70, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n71, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n72, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n73, velocity: 100, time: 14000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n70, velocity: 64, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n71, velocity: 64, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n72, velocity: 64, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n73, velocity: 64, time: 16000000 }));

        // Chord 8 (16–18 s): plus_four_7 [1↓, root, 2↑, 3↑, 5↑]
        let (n80, n81, n82, n83, n84) = (
            *s.at(ri8 - 1), *s.at(ri8), *s.at(ri8 + 2), *s.at(ri8 + 3), *s.at(ri8 + 5),
        );
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n80, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n81, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n82, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n83, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n84, velocity: 100, time: 16000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n80, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n81, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n82, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n83, velocity: 64, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n84, velocity: 64, time: 18000000 }));

        // Chord 9 (18–20 s): maj_7_no_root_add6 [1↓, root, 2↑, 5↑]
        let (n90, n91, n92, n93) = (*s.at(ri9 - 1), *s.at(ri9), *s.at(ri9 + 2), *s.at(ri9 + 5));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n90, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n91, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n92, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_ON(NoteOn { channel: 0, note: n93, velocity: 100, time: 18000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n90, velocity: 64, time: 20000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n91, velocity: 64, time: 20000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n92, velocity: 64, time: 20000000 }));
        eventlist.append(Message::NOTE_OFF(NoteOff { channel: 0, note: n93, velocity: 64, time: 20000000 }));

        // ── Melody layer (channel 1) ─────────────────────────────────────────────────────
        // C Lydian, one octave: C4 D4 E4 F#4 G4 A4 B4 C5 (indices 0–7).
        //
        // Pitch uses a triangular wave with period=16 so each step moves exactly ±1 scale
        // degree — no skipping. Two full arcs over 32 notes:
        //   cycle_pos 0–7  (ascending) : scale_idx = cycle_pos       → 0,1,2,3,4,5,6,7
        //   cycle_pos 8–15 (descending): scale_idx = 15 - cycle_pos  → 7,6,5,4,3,2,1,0
        //
        // Duration scales with the same index: low note 300 ms, high note 1000 ms.
        //   dur = 300 000 + scale_idx × 100 000 µs
        //   Total: 2 × (5200 + 5200) ms = 20 800 ms ≈ 20 s
        let melody_scale: Array<u8> = array![60_u8, 62_u8, 64_u8, 66_u8, 67_u8, 69_u8, 71_u8, 72_u8];

        let melody_length = 32_u32;
        let mut current_time: u64 = 0_u64;
        let mut mi = 0_u32;
        loop {
            if mi >= melody_length {
                break;
            }

            // Triangular wave: period 16, two cycles over 32 notes
            let cycle_pos = mi % 16_u32;
            let scale_idx: u32 = if cycle_pos < 8_u32 {
                cycle_pos // ascending: 0,1,2,3,4,5,6,7
            } else {
                15_u32 - cycle_pos // descending: 7,6,5,4,3,2,1,0
            };

            let mel_note = *melody_scale.at(scale_idx.try_into().unwrap());
            // Duration mirrors pitch height: 300 ms (lowest) → 1000 ms (highest)
            let dur: u64 = 300000_u64 + scale_idx.into() * 100000_u64;

            eventlist
                .append(
                    Message::NOTE_ON(
                        NoteOn { channel: 1, note: mel_note, velocity: 80, time: current_time },
                    ),
                );
            eventlist
                .append(
                    Message::NOTE_OFF(
                        NoteOff {
                            channel: 1, note: mel_note, velocity: 64, time: current_time + dur,
                        },
                    ),
                );

            current_time += dur;
            mi += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        // Print as Cairo code (pipe this output through the TypeScript converter for a .mid file)
        generate_cairo_code(@midiobj);

        // Verify event counts: 37 chord NoteOn + 20 melody NoteOn = 57 total NoteOn
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count == 69, "Expected 69 NoteOn events (37 chords + 32 melody)");
        assert!(note_off_count == 69, "Expected 69 NoteOff events (37 chords + 32 melody)");

        // Verify binary MIDI output starts with a valid MThd header
        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be 'M'");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be 'T'");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be 'h'");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be 'd'");
    }

    /// Euclidean-rhythm melody with LCG note selection, repeated 4 times.
    ///
    /// Rhythm : euclidean(n=16, k=9)
    ///   → pattern [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,1]
    ///   → 9 onsets at steps 0,2,4,6,8,10,12,14,15
    ///
    /// Notes  : LCG { state:7, mult:5, inc:3, mod:16 } → getlist(16)
    ///   → raw values  [6, 1, 8,11,10, 5,12,15,14, 9, 0, 3, 2,13, 4, 7]
    ///   → scale index (val%7) [6,1,1, 4, 3, 5, 5, 1, 0, 2, 0, 3, 2, 6, 4, 0]
    ///
    /// Scale  : C Lydian (C4 D4 E4 F#4 G4 A4 B4) = [60,62,64,66,67,69,71]
    ///
    /// Onset notes per cycle: B4 D4 F#4 A4 C4 C4 E4 G4 C4  (steps 0,2,4,6,8,10,12,14,15)
    ///
    /// Timing : step = 125 000 µs (1/16 note @ 120 BPM), note_dur = 110 000 µs
    ///          1 cycle = 16 × 125 000 = 2 000 000 µs (2 s)
    ///          4 cycles = 8 000 000 µs (8 s)
    ///
    /// Events : 4 × 9 = 36 NoteOn + 36 NoteOff + 1 SetTempo = 73 total
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn euclidean_lcg_melody_test() {
        // ── Euclidean rhythm ─────────────────────────────────────────────────────────────
        // E(16,9): distribute 9 pulses across 16 steps as evenly as possible.
        let n: u32 = 16;
        let k: u32 = 9;
        let rhythm = euclidean(n, k);
        assert!(rhythm.len() == n, "euclidean length should equal n");

        // ── Note pool: C Lydian one octave ───────────────────────────────────────────────
        let scale: Array<u8> = array![60_u8, 62_u8, 64_u8, 66_u8, 67_u8, 69_u8, 71_u8];
        let scale_size: u32 = 7;

        // ── LCG: n=16 values, modulus=16, map to scale via val % scale_size ─────────────
        // Full-period LCG (Hull-Dobell satisfied): mult=5, inc=3, mod=16.
        // Produces raw [6,1,8,11,10,5,12,15,14,9,0,3,2,13,4,7] – all 16 values distinct.
        let lcg = LCG { state: 7, multiplier: 5, increment: 3, modulus: 16 };
        let lcg_notes = lcg.getlist(n);

        // Verify LCG determinism
        assert!(*lcg_notes.at(0) == 6, "LCG[0] should be 6");
        assert!(*lcg_notes.at(1) == 1, "LCG[1] should be 1");
        assert!(*lcg_notes.at(8) == 14, "LCG[8] should be 14");

        // ── Build event list ─────────────────────────────────────────────────────────────
        let step_dur: u64 = 125000_u64; // 1/16 note at 120 BPM
        let note_dur: u64 = 110000_u64; // slight articulation gap

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        // 4 repetitions of the same 16-step euclidean + LCG pattern
        let mut current_time: u64 = 0_u64;
        let mut rep: u32 = 0;
        loop {
            if rep >= 4_u32 {
                break;
            }
            let mut step: u32 = 0;
            loop {
                if step >= n {
                    break;
                }
                // Only play on euclidean onsets (value == 1)
                if *rhythm.at(step) == 1_u32 {
                    let lcg_val: u32 = *lcg_notes.at(step);
                    let note_idx: usize = (lcg_val % scale_size).try_into().unwrap();
                    let note: u8 = *scale.at(note_idx);
                    eventlist
                        .append(
                            Message::NOTE_ON(
                                NoteOn { channel: 0, note: note, velocity: 90, time: current_time },
                            ),
                        );
                    eventlist
                        .append(
                            Message::NOTE_OFF(
                                NoteOff {
                                    channel: 0,
                                    note: note,
                                    velocity: 64,
                                    time: current_time + note_dur,
                                },
                            ),
                        );
                }
                current_time += step_dur;
                step += 1;
            };
            rep += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        // Print as Cairo code (pipe through TypeScript converter for .mid file)
        generate_cairo_code(@midiobj);

        // ── Verify event counts ──────────────────────────────────────────────────────────
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        // 4 reps × 9 onsets = 36 of each
        assert!(note_on_count == 36, "Expected 36 NoteOn events (4 reps x 9 onsets)");
        assert!(note_off_count == 36, "Expected 36 NoteOff events (4 reps x 9 onsets)");

        // Verify binary MIDI header
        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be 'M'");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be 'T'");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be 'h'");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be 'd'");
    }

    /// Two-voice polyrhythm: LCG note selection + euclidean rhythms + modal-transposition harmony.
    ///
    /// Structure
    /// ─────────
    /// Section 1 (0..8 s)   : main melody alone × 4 cycles  (channel 0)
    /// Section 2 (8..16 s)  : main + harmony together × 4 main-cycles (channels 0 & 1)
    ///
    /// Main   : euclidean(n=16, k=9)  →  [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,1]
    ///          LCG { state:7, mult:5, inc:3, mod:16 } → notes B4 D4 F#4 A4 C4 C4 E4 G4 C4
    ///
    /// Harmony: euclidean(n=12, k=5)  →  [1,0,0,1,0,0,1,0,1,0,1,0]  (clave-like)
    ///          Note = modal_transposition(last_main_note, C_Lydian, +2 steps) → diatonic 3rd above
    ///          Steps 0,3,6,8,10 per 12-step cycle
    ///
    /// Polyrhythm: main cycles every 16 steps, harmony every 12 steps, both at 125 ms/step.
    ///             LCM(16,12)=48 steps = 6 s per super-cycle.
    ///
    /// Timing : step = 125 000 µs, note_dur = 110 000 µs
    ///          Section 1 = 4 × 16 × 125 000 = 8 000 000 µs
    ///          Section 2 = 4 × 16 × 125 000 = 8 000 000 µs
    ///
    /// Events (NoteOn = NoteOff):
    ///   Section 1 : 4 × 9 = 36
    ///   Section 2 main    : 4 × 9 = 36
    ///   Section 2 harmony : 5 full 12-cycles × 5 + 2 partial = 27
    ///   Total             : 99 NoteOn + 99 NoteOff + 1 SetTempo
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn lcg_euclidean_harmony_test() {
        // ── Shared scale & mode ──────────────────────────────────────────────────────────
        let scale: Array<u8> = array![60_u8, 62_u8, 64_u8, 66_u8, 67_u8, 69_u8, 71_u8];
        let scale_size: u32 = 7;

        let tonic = PitchClass { note: 0_u8, octave: 4_u8 }; // C4
        let lyd_steps = mode_steps(Modes::Lydian(()));

        // ── Main rhythm & notes (same as euclidean_lcg_melody_test) ─────────────────────
        let n_main: u32 = 16;
        let k_main: u32 = 9;
        let main_rhythm = euclidean(n_main, k_main);
        let main_lcg = LCG { state: 7, multiplier: 5, increment: 3, modulus: 16 };
        let main_lcg_notes = main_lcg.getlist(n_main);

        // ── Harmony rhythm: E(12,5) clave pattern ───────────────────────────────────────
        // [1,0,0,1,0,0,1,0,1,0,1,0] – onsets at steps 0,3,6,8,10
        // Notes are diatonic 3rds (2 Lydian steps up) above the last main onset.
        let n_harm: u32 = 12;
        let k_harm: u32 = 5;
        let harm_rhythm = euclidean(n_harm, k_harm);
        assert!(harm_rhythm.len() == n_harm, "harm rhythm length should equal n_harm");

        let step_dur: u64 = 125000_u64;
        let note_dur: u64 = 110000_u64;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        // ── Section 1: main melody alone, 4 cycles ──────────────────────────────────────
        let mut current_time: u64 = 0_u64;
        let mut rep: u32 = 0;
        loop {
            if rep >= 4_u32 {
                break;
            }
            let mut step: u32 = 0;
            loop {
                if step >= n_main {
                    break;
                }
                if *main_rhythm.at(step) == 1_u32 {
                    let note_idx: usize = (*main_lcg_notes.at(step) % scale_size)
                        .try_into()
                        .unwrap();
                    let note: u8 = *scale.at(note_idx);
                    eventlist
                        .append(
                            Message::NOTE_ON(
                                NoteOn { channel: 0, note: note, velocity: 90, time: current_time },
                            ),
                        );
                    eventlist
                        .append(
                            Message::NOTE_OFF(
                                NoteOff {
                                    channel: 0,
                                    note: note,
                                    velocity: 64,
                                    time: current_time + note_dur,
                                },
                            ),
                        );
                }
                current_time += step_dur;
                step += 1;
            };
            rep += 1;
        };

        // ── Section 2: main + harmony together, 4 main-cycles ───────────────────────────
        // Both share the same absolute time cursor. Main cycles mod 16, harmony mod 12.
        // `last_main_note` starts at C4 and is updated on every main onset.
        // Harmony fires its diatonic 3rd at each of its own onset steps.
        let total_s2_steps: u32 = 4_u32 * n_main; // 64 steps = 8 s
        let mut last_main_note: u8 = 60_u8; // C4 — initialised to tonic

        let mut s2_step: u32 = 0;
        loop {
            if s2_step >= total_s2_steps {
                break;
            }

            let main_step = s2_step % n_main;
            let harm_step = s2_step % n_harm;

            // Main note: update last_main_note so harmony always sees the freshest value
            if *main_rhythm.at(main_step) == 1_u32 {
                let note_idx: usize = (*main_lcg_notes.at(main_step) % scale_size)
                    .try_into()
                    .unwrap();
                let note: u8 = *scale.at(note_idx);
                last_main_note = note;
                eventlist
                    .append(
                        Message::NOTE_ON(
                            NoteOn { channel: 0, note: note, velocity: 90, time: current_time },
                        ),
                    );
                eventlist
                    .append(
                        Message::NOTE_OFF(
                            NoteOff {
                                channel: 0,
                                note: note,
                                velocity: 64,
                                time: current_time + note_dur,
                            },
                        ),
                    );
            }

            // Harmony: modal transposition of last main note up a diatonic 3rd
            if *harm_rhythm.at(harm_step) == 1_u32 {
                let main_pc = keynum_to_pc(last_main_note);
                let harm_keynum = modal_transposition(
                    main_pc, tonic, lyd_steps, 2, Direction::Up(()),
                );
                eventlist
                    .append(
                        Message::NOTE_ON(
                            NoteOn {
                                channel: 1, note: harm_keynum, velocity: 75, time: current_time,
                            },
                        ),
                    );
                eventlist
                    .append(
                        Message::NOTE_OFF(
                            NoteOff {
                                channel: 1,
                                note: harm_keynum,
                                velocity: 64,
                                time: current_time + note_dur,
                            },
                        ),
                    );
            }

            current_time += step_dur;
            s2_step += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_cairo_code(@midiobj);

        // ── Verify event counts ──────────────────────────────────────────────────────────
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        // S1: 36  +  S2 main: 36  +  S2 harmony: 27  =  99
        assert!(note_on_count == 99, "Expected 99 NoteOn events");
        assert!(note_off_count == 99, "Expected 99 NoteOff events");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Tendency-mask swarm: pinhole C4 → 4-octave explosion → 1-octave high cloud.
    ///
    /// Timeline (6 seconds total, C major throughout, root = 0):
    ///
    ///   Phase 1 (0–4 s, 40 steps × 100 ms):
    ///     lo envelope: C4 (60) → C2 (36)   [opens downward]
    ///     hi envelope: C4 (60) → C6 (84)   [opens upward]
    ///     → starts as a single C4, spreads to a 4-octave (48 semitone) cloud.
    ///
    ///   Phase 2 (4–6 s, 40 steps × 50 ms — twice as dense):
    ///     lo envelope: C2 (36) → C5 (72)   [floor rises into high register]
    ///     hi envelope: stays C6 (84)
    ///     → swarm contracts to 1-octave bright cloud (C5–C6), with double the note rate.
    ///
    /// Scale  : C major C2–C6, absolute MIDI numbers as degrees from root 0 (29 pitches).
    /// LCG    : state=17, mult=5, inc=3, mod=256  (5×255+3=1278 — no u32 overflow).
    /// Events : 80 NoteOn + 80 NoteOff + 1 SetTempo = 161 total.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tendency_mask_swarm_test() {
        // ── Pitch-range envelope ──────────────────────────────────────────────────────────
        let lo_pts = array![
            TimePoint { x: 0, y: 60 },        // pinhole: C4
            TimePoint { x: 4000000, y: 36 },   // bottom of spread: C2
            TimePoint { x: 6000000, y: 72 },   // high floor: C5
        ];
        let hi_pts = array![
            TimePoint { x: 0, y: 60 },        // pinhole: C4
            TimePoint { x: 4000000, y: 84 },   // ceiling: C6
            TimePoint { x: 6000000, y: 84 },   // ceiling stays: C6
        ];
        let env = PitchRangeEnvelope { lo: lo_pts.span(), hi: hi_pts.span() };

        // ── Scale: C major C2–C6 as absolute MIDI numbers (root=0 so midi = 0 + degree) ──
        let scale: Array<u8> = array![
            36_u8, 38, 40, 41, 43, 45, 47, // C2–B2
            48, 50, 52, 53, 55, 57, 59,     // C3–B3
            60, 62, 64, 65, 67, 69, 71,     // C4–B4
            72, 74, 76, 77, 79, 81, 83,     // C5–B5
            84,                              // C6
        ];
        let scale_span = scale.span();

        // ── LCG ──────────────────────────────────────────────────────────────────────────
        let mut lcg = LCG { state: 17, multiplier: 5, increment: 3, modulus: 256 };

        // ── Event list ────────────────────────────────────────────────────────────────────
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut current_time: u64 = 0_u64;
        let mut step: u32 = 0;

        loop {
            if step >= 80_u32 {
                break;
            }

            // Phase 1: 100 ms steps (sparse). Phase 2: 50 ms steps (2× density).
            let step_dur: u64 = if step < 40_u32 { 100000_u64 } else { 50000_u64 };
            let note_dur: u64 = if step < 40_u32 { 88000_u64 } else { 44000_u64 };

            // Envelope lookup (max t = 5 950 000 µs, fits in u32)
            let t: u32 = current_time.try_into().unwrap();
            let (lo, hi) = range_at(@env, t);

            let (raw, new_lcg) = LCGRandomSource::draw(@lcg);
            lcg = new_lcg;

            // root=0 so each scale degree IS the absolute MIDI note number
            let pitch = pick_pitch_in_range(scale_span, 0_u8, lo, hi, raw);

            eventlist
                .append(
                    Message::NOTE_ON(
                        NoteOn { channel: 0, note: pitch, velocity: 90, time: current_time },
                    ),
                );
            eventlist
                .append(
                    Message::NOTE_OFF(
                        NoteOff {
                            channel: 0, note: pitch, velocity: 64, time: current_time + note_dur,
                        },
                    ),
                );

            current_time += step_dur;
            step += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        // Print as Cairo code — pipe through TypeScript converter for .mid file
        generate_cairo_code(@midiobj);

        // ── Verify event counts ───────────────────────────────────────────────────────────
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count == 80, "Expected 80 NoteOn events");
        assert!(note_off_count == 80, "Expected 80 NoteOff events");

        // ── Verify binary MIDI header ─────────────────────────────────────────────────────
        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Walk `contour` diatonic steps from tonic — monotonic in contour, no modulo wrap jumps.
    fn contour_to_dorian_keynum(
        contour_value: u32, tonic: PitchClass, mode_steps: Span<u8>,
    ) -> u8 {
        let steps: u8 = contour_value.try_into().unwrap();
        let keynum = modal_transposition(tonic, tonic, mode_steps, steps, Direction::Up(()));
        if keynum > 127_u8 {
            127_u8
        } else {
            keynum
        }
    }

    fn transpose_keynum_diatonic(
        keynum: u8, offset: i32, tonic: PitchClass, steps: Span<u8>,
    ) -> u8 {
        let pc = keynum_to_pc(keynum);
        if offset >= 0 {
            let n: u8 = offset.try_into().unwrap();
            modal_transposition(pc, tonic, steps, n, Direction::Up(()))
        } else {
            let n: u8 = (-offset).try_into().unwrap();
            modal_transposition(pc, tonic, steps, n, Direction::Down(()))
        }
    }

    /// Cumulative onsets (µs); timing is symmetric — slowest at peak/trough, fastest at mid-crossing.
    fn build_modal_run_schedule(
        contour: Span<u32>, min_us: u64, max_us: u64, total_slots: u32,
    ) -> Array<u64> {
        let mut starts: Array<u64> = ArrayTrait::new();
        let mut t: u64 = 0;
        let mut i: u32 = 0;
        loop {
            if i >= total_slots {
                break;
            }
            starts.append(t);
            let cv = *contour.at(i % contour.len());
            t += contour_to_duration_symmetric_us(
                cv, MODAL_CONTOUR_MIN, MODAL_CONTOUR_MAX, min_us, max_us,
            );
            i += 1;
        };
        starts
    }

    /// One voice of a sin modal run: pitch follows contour; timing is symmetric around mid-contour.
    fn append_modal_run_voice(
        ref eventlist: Array<Message>,
        channel: u8,
        contour: Span<u32>,
        schedule: Span<u64>,
        start_slot: u32,
        tonic: PitchClass,
        mode_steps: Span<u8>,
        diatonic_offset: i32,
        min_us: u64,
        max_us: u64,
    ) -> u32 {
        let n = contour.len();
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let cv = *contour.at(i);
            let keynum = contour_to_dorian_keynum(cv, tonic, mode_steps);
            let pitch = transpose_keynum_diatonic(keynum, diatonic_offset, tonic, mode_steps);
            let on = *schedule.at(start_slot + i);
            let dur = contour_to_duration_symmetric_us(
                cv, MODAL_CONTOUR_MIN, MODAL_CONTOUR_MAX, min_us, max_us,
            );
            append_legato_note(ref eventlist, channel, pitch, 90, on, on + dur);
            i += 1;
        };
        n
    }

    /// Append a legato note pair (NOTE_ON + NOTE_OFF) at absolute microsecond times.
    fn append_legato_note(
        ref eventlist: Array<Message>,
        channel: u8,
        note: u8,
        velocity: u8,
        on_time: Time,
        off_time: Time,
    ) {
        eventlist
            .append(
                Message::NOTE_ON(NoteOn { channel, note, velocity, time: on_time }),
            );
        eventlist
            .append(
                Message::NOTE_OFF(NoteOff { channel, note, velocity: 64, time: off_time }),
            );
    }

    /// Map voice + legato length to pitch. Duration tiers follow the n=12, k=3 tile
    /// [2, 2, 8]: pickup on the fifth, middle on the third, long on the root.
    fn pitch_for_canon_event(voice_id: u32, duration: u32) -> u8 {
        let base: u8 = if voice_id == 0 {
            60 // C4
        } else if voice_id == 1 {
            72 // C5
        } else if voice_id == 2 {
            63 // Eb4
        } else {
            75 // Eb5
        };
        if duration <= 2 {
            base + 7
        } else if duration <= 4 {
            base + 4
        } else {
            base
        }
    }

    /// Syncopated four-voice rhythmic tiling canon → MIDI.
    ///
    /// Seed 17 → n=12, R={0,2,4}, S={0,1,6,7} (class-2 hocket, 4 voices): each voice
    /// plays short–short–long [2,2,8] legato groups while the four entry offsets interlock
    /// across the cycle. Loops three times (~7.2 s at 120 BPM, 200 ms per grid step).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn rhythmic_canon_midi_test() {
        // 120 BPM; 200 ms per grid step → 12 × 200 ms = 2.4 s/cycle × 3 loops ≈ 7.2 s.
        let tempo_us: u32 = 500000;
        let step_us: u64 = 200000;
        let num_loops: u32 = 3;

        // n=12, k=3, d=2 → R={0,2,4}, S={0,1,6,7} (4 voices, syncopated class-2).
        let canon = generate_rhythmic_canon(17);
        assert!(canon.n == 12, "expected n=12");
        assert!(canon.translations.len() == 4, "expected 4 voices");
        assert!(canon.rhythm_tile.len() == 3, "expected 3 onsets per voice");

        let onset_events = canon_to_events(@canon);
        assert!(onset_events.len() == canon.n, "one onset per cycle position");

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let n = canon.n;
        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let cycle_start: Time = (loop_i * n).into() * step_us;

            let mut ei: u32 = 0;
            loop {
                if ei >= onset_events.len() {
                    break;
                }
                let e = *onset_events.at(ei);
                let on_time: Time = cycle_start + e.time.into() * step_us;
                let off_time: Time = on_time + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                let pitch = pitch_for_canon_event(e.voice_id, e.duration);
                append_legato_note(
                    ref eventlist, channel, pitch, e.velocity, on_time, off_time,
                );
                ei += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        // 3 loops × 12 onsets = 36 NoteOn + 36 NoteOff
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count == 36, "expected 36 NoteOn");
        assert!(note_off_count == 36, "expected 36 NoteOff");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Pitch for a voice at a given tile index: voice 0 carries the LCG melody; each later
    /// voice is a diatonic 3rd (two Lydian steps) above the previous voice at the same tile.
    fn pitch_for_canon_voice(
        voice_id: u32,
        tile_idx: u32,
        leader0: u8,
        leader1: u8,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
    ) -> u8 {
        let leaders = array![leader0, leader1];
        pitch_for_canon_voice_at_tile(voice_id, tile_idx, leaders.span(), tonic, lyd_steps)
    }

    /// Generalized leader lookup for tiles with any number of onsets per voice.
    fn pitch_for_canon_voice_at_tile(
        voice_id: u32,
        tile_idx: u32,
        leaders: Span<u8>,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
    ) -> u8 {
        let leader = *leaders.at(tile_idx);
        if voice_id == 0 {
            return leader;
        }
        let v1 = modal_transposition(
            keynum_to_pc(leader), tonic, lyd_steps, 2, Direction::Up(()),
        );
        if voice_id == 1 {
            return v1;
        }
        let v2 = modal_transposition(
            keynum_to_pc(v1), tonic, lyd_steps, 2, Direction::Up(()),
        );
        if voice_id == 2 {
            return v2;
        }
        modal_transposition(keynum_to_pc(v2), tonic, lyd_steps, 2, Direction::Up(()))
    }

    /// Accent sixteenth pickups; soften the long tail and upper voices.
    fn velocity_for_canon_voice_tile(voice_id: u32, tile_idx: u32, dur: u32) -> u8 {
        let base = velocity_for_canon_voice(voice_id);
        if dur <= 1 {
            if base > 85 {
                base
            } else {
                base + 10
            }
        } else if tile_idx >= 3 {
            base - 8
        } else {
            base
        }
    }

    /// Softer dynamics on upper harmonic voices.
    fn velocity_for_canon_voice(voice_id: u32) -> u8 {
        if voice_id == 0 {
            92
        } else if voice_id == 1 {
            78
        } else if voice_id == 2 {
            72
        } else {
            66
        }
    }

    /// Syncopated four-voice tiling canon with modal-transposition harmony.
    ///
    /// Seed 0 → n=8, R={0,2}, S={0,1,4,5} (class-2 hocket): each voice alternates a 2-step
    /// pickup with a 6-step sustain — not straight eighths. Voice 0 carries an LCG melody in
    /// C Lydian; voices 1–3 each add a diatonic 3rd above the previous voice at the same tile
    /// position (stacked 3rds within the mode). Loops four times (~7.2 s at 120 BPM).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn rhythmic_canon_modal_harmony_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 225000; // 8 × 225 ms = 1.8 s/cycle
        let num_loops: u32 = 4;

        // n=8, k=2, d=2 → R={0,2}, S={0,1,4,5}; legato [2, 6].
        let canon = generate_rhythmic_canon(0);
        assert!(canon.n == 8, "expected n=8");
        assert!(canon.translations.len() == 4, "expected 4 voices");
        assert!(canon.rhythm_tile.len() == 2, "expected 2 onsets per voice");

        let lyd_steps = mode_steps(Modes::Lydian(()));
        let tonic = PitchClass { note: 0_u8, octave: 4_u8 };
        let scale: Array<u8> = array![60_u8, 62, 64, 66, 67, 69, 71]; // C Lydian, C4..B4

        // Leader melody: one Lydian pitch per tile onset (held across loops).
        let melody_lcg = LCG { state: 91, multiplier: 5, increment: 3, modulus: 16 };
        let raw = melody_lcg.getlist(2);
        let idx0: usize = (*raw.at(0) % scale.len()).try_into().unwrap();
        let idx1: usize = (*raw.at(1) % scale.len()).try_into().unwrap();
        let leader0: u8 = *scale.at(idx0);
        let leader1: u8 = *scale.at(idx1);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let n = canon.n;
        let tile = canon.rhythm_tile;
        let durs = canon.durations;
        let voices = canon.voices;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let cycle_start: Time = (loop_i * n).into() * step_us;

            let mut vi: u32 = 0;
            loop {
                if vi >= voices.len() {
                    break;
                }
                let voice = *voices.at(vi);
                if !voice.tiling_participant {
                    vi += 1;
                    continue;
                }

                let mut ti: u32 = 0;
                loop {
                    if ti >= tile.len() {
                        break;
                    }
                    let r = *tile.at(ti);
                    let grid_time = (r + voice.translation) % n;
                    let on_time: Time = cycle_start + grid_time.into() * step_us;
                    let dur: u64 = (*durs.at(ti)).into();
                    let off_time: Time = on_time + dur * step_us;
                    let pitch = pitch_for_canon_voice(
                        voice.voice_id, ti, leader0, leader1, tonic, lyd_steps,
                    );
                    let vel = velocity_for_canon_voice(voice.voice_id);
                    append_legato_note(
                        ref eventlist,
                        voice.voice_id.try_into().unwrap(),
                        pitch,
                        vel,
                        on_time,
                        off_time,
                    );
                    ti += 1;
                };
                vi += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        // 4 loops × 4 voices × 2 onsets = 32 NoteOn + 32 NoteOff
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count == 32, "expected 32 NoteOn");
        assert!(note_off_count == 32, "expected 32 NoteOff");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Dense sixteenth-note tiling canon with modal-transposition harmony.
    ///
    /// Seed 274 → n=16, R={0,1,2,3}, S={0,4,8,12} (4 voices): each voice opens with a
    /// four-sixteenth pickup [1,1,1,13] then a long sustain — 16 attacks per bar, not straight
    /// eighths. Voice 0 carries an LCG melody in C Lydian (one pitch per tile onset); voices
    /// 1–3 stack diatonic 3rds above the previous voice. Four bars at 120 BPM (125 ms/step).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn rhythmic_canon_modal_16ths_midi_test() {
        // 120 BPM; 125 ms per 16th → 16 steps = one 4/4 bar (2 s) × 4 bars = 8 s.
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let num_loops: u32 = 4;

        // n=16, k=4, d=1 → R={0,1,2,3}, S={0,4,8,12}; legato [1, 1, 1, 13].
        let canon = generate_rhythmic_canon(274);
        assert!(canon.n == 16, "expected n=16");
        assert!(canon.translations.len() == 4, "expected 4 voices");
        assert!(canon.rhythm_tile.len() == 4, "expected 4 onsets per voice");

        let lyd_steps = mode_steps(Modes::Lydian(()));
        let tonic = PitchClass { note: 0_u8, octave: 4_u8 };
        let scale: Array<u8> = array![60_u8, 62, 64, 66, 67, 69, 71];

        let melody_lcg = LCG { state: 37, multiplier: 5, increment: 3, modulus: 16 };
        let raw = melody_lcg.getlist(4);
        let mut leaders: Array<u8> = ArrayTrait::new();
        let mut li: u32 = 0;
        loop {
            if li >= 4 {
                break;
            }
            let idx: usize = (*raw.at(li) % scale.len()).try_into().unwrap();
            leaders.append(*scale.at(idx));
            li += 1;
        };
        let leaders_span = leaders.span();

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let n = canon.n;
        let tile = canon.rhythm_tile;
        let durs = canon.durations;
        let voices = canon.voices;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let cycle_start: Time = (loop_i * n).into() * step_us;

            let mut vi: u32 = 0;
            loop {
                if vi >= voices.len() {
                    break;
                }
                let voice = *voices.at(vi);
                if !voice.tiling_participant {
                    vi += 1;
                    continue;
                }

                let mut ti: u32 = 0;
                loop {
                    if ti >= tile.len() {
                        break;
                    }
                    let r = *tile.at(ti);
                    let grid_time = (r + voice.translation) % n;
                    let on_time: Time = cycle_start + grid_time.into() * step_us;
                    let dur: u64 = (*durs.at(ti)).into();
                    let off_time: Time = on_time + dur * step_us;
                    let pitch = pitch_for_canon_voice_at_tile(
                        voice.voice_id, ti, leaders_span, tonic, lyd_steps,
                    );
                    let vel = velocity_for_canon_voice_tile(
                        voice.voice_id, ti, *durs.at(ti),
                    );
                    append_legato_note(
                        ref eventlist,
                        voice.voice_id.try_into().unwrap(),
                        pitch,
                        vel,
                        on_time,
                        off_time,
                    );
                    ti += 1;
                };
                vi += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        // 4 bars × 16 grid onsets = 64 NoteOn + 64 NoteOff
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count == 64, "expected 64 NoteOn");
        assert!(note_off_count == 64, "expected 64 NoteOff");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Build one-octave MIDI keynums for a mode at the given tonic.
    fn build_scale_keynums(tonic: PitchClass, mode: Modes) -> Array<u8> {
        let steps = mode_steps(mode);
        let pcs = get_notes_of_key(tonic, steps);
        let mut out: Array<u8> = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= pcs.len() {
                break;
            }
            let pc_n = *pcs.at(i);
            out.append(pc_to_keynum(PitchClass { note: pc_n, octave: tonic.octave }));
            i += 1;
        };
        out
    }

    /// LCG leader pitches — one per tile onset — drawn from the section scale.
    fn build_section_leaders(
        lcg_state: u32,
        k: u32,
        tonic: PitchClass,
        mode: Modes,
    ) -> Array<u8> {
        let lcg = LCG { state: lcg_state, multiplier: 5, increment: 3, modulus: 16 };
        let scale = build_scale_keynums(tonic, mode);
        let raw = lcg.getlist(k);
        let mut leaders: Array<u8> = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= k {
                break;
            }
            let idx: usize = (*raw.at(i) % scale.len()).try_into().unwrap();
            leaders.append(*scale.at(idx));
            i += 1;
        };
        leaders
    }

    fn section_tonic(section: u32) -> PitchClass {
        if section == 0 {
            PitchClass { note: 0_u8, octave: 4_u8 } // C — I
        } else if section == 1 {
            PitchClass { note: 5_u8, octave: 4_u8 } // F — IV
        } else if section == 2 {
            PitchClass { note: 7_u8, octave: 4_u8 } // G — V
        } else {
            PitchClass { note: 9_u8, octave: 4_u8 } // A — vi
        }
    }

    fn section_mode(section: u32) -> Modes {
        if section == 0 {
            Modes::Lydian(())
        } else if section == 1 {
            Modes::Lydian(())
        } else if section == 2 {
            Modes::Mixolydian(())
        } else {
            Modes::Aeolian(())
        }
    }

    /// Four-section modal canon progression with dense sixteenth/eighth pickup tiling.
    ///
    /// Seed 35 → n=24, R={0,2,4,6,8,10}, S={0,1,12,13} (4 voices, 6 onsets/voice,
    /// legato [2,2,2,2,2,14]). Sixteen cycles = 4 sections × 4 bars each (~38 s):
    ///   §1 C Lydian (I) → §2 F Lydian (IV) → §3 G Mixolydian (V) → §4 A Aeolian (vi).
    /// Voice 0 LCG melody per section; voices 1–3 stack diatonic 3rds above the previous.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn rhythmic_canon_modal_progression_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 100000; // 100 ms/step → 24 steps = 2.4 s/cycle
        let loops_per_section: u32 = 4;
        let num_sections: u32 = 4;
        let num_loops: u32 = loops_per_section * num_sections;

        // n=24, k=6, d=2 → six short pickups + long tail per voice.
        let canon = generate_rhythmic_canon(35);
        assert!(canon.n == 24, "expected n=24");
        assert!(canon.translations.len() == 4, "expected 4 voices");
        assert!(canon.rhythm_tile.len() == 6, "expected 6 onsets per voice");

        let k = canon.rhythm_tile.len();

        // Precompute leader pitches for each harmonic section (I–IV–V–vi).
        let leaders0 = build_section_leaders(37, k, section_tonic(0), section_mode(0));
        let leaders1 = build_section_leaders(53, k, section_tonic(1), section_mode(1));
        let leaders2 = build_section_leaders(71, k, section_tonic(2), section_mode(2));
        let leaders3 = build_section_leaders(89, k, section_tonic(3), section_mode(3));

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let n = canon.n;
        let tile = canon.rhythm_tile;
        let durs = canon.durations;
        let voices = canon.voices;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let section = loop_i / loops_per_section;
            let tonic = section_tonic(section);
            let steps = mode_steps(section_mode(section));
            let leaders_span = if section == 0 {
                leaders0.span()
            } else if section == 1 {
                leaders1.span()
            } else if section == 2 {
                leaders2.span()
            } else {
                leaders3.span()
            };

            let cycle_start: Time = (loop_i * n).into() * step_us;

            let mut vi: u32 = 0;
            loop {
                if vi >= voices.len() {
                    break;
                }
                let voice = *voices.at(vi);
                if !voice.tiling_participant {
                    vi += 1;
                    continue;
                }

                let mut ti: u32 = 0;
                loop {
                    if ti >= tile.len() {
                        break;
                    }
                    let r = *tile.at(ti);
                    let grid_time = (r + voice.translation) % n;
                    let on_time: Time = cycle_start + grid_time.into() * step_us;
                    let dur_steps = *durs.at(ti);
                    let dur: u64 = dur_steps.into();
                    let off_time: Time = on_time + dur * step_us;
                    let pitch = pitch_for_canon_voice_at_tile(
                        voice.voice_id, ti, leaders_span, tonic, steps,
                    );
                    let vel = velocity_for_canon_voice_tile(
                        voice.voice_id, ti, dur_steps,
                    );
                    append_legato_note(
                        ref eventlist,
                        voice.voice_id.try_into().unwrap(),
                        pitch,
                        vel,
                        on_time,
                        off_time,
                    );
                    ti += 1;
                };
                vi += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        // 16 cycles × 24 grid onsets = 384 NoteOn + 384 NoteOff
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count == 384, "expected 384 NoteOn");
        assert!(note_off_count == 384, "expected 384 NoteOff");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    // ── Symmetry-engine canon helpers ────────────────────────────────────────────────

    fn symmetry_section_world_id(section: u32) -> u16 {
        if section == 0 {
            6 // Messiaen Mode 2
        } else if section == 1 {
            7 // Messiaen Mode 3
        } else if section == 2 {
            12 // Octatonic Variant B
        } else if section == 3 {
            10 // Messiaen Mode 6
        } else if section == 4 {
            14 // Hexatonic Augmented
        } else {
            11 // Messiaen Mode 7
        }
    }

    fn symmetry_section_transposition(section: u32) -> u8 {
        if section == 0 {
            0
        } else if section == 1 {
            1
        } else if section == 2 {
            0
        } else if section == 3 {
            2
        } else if section == 4 {
            0
        } else {
            1
        }
    }

    fn symmetry_section_chord_start(section: u32, chord_variant: u32) -> u8 {
        let base = if section == 0 {
            0
        } else if section == 1 {
            2
        } else if section == 2 {
            1
        } else if section == 3 {
            0
        } else if section == 4 {
            0
        } else {
            3
        };
        base + chord_variant.try_into().unwrap()
    }

    fn symmetry_section_chord_skip(section: u32) -> u8 {
        if section == 0 {
            2
        } else if section == 1 {
            1
        } else if section == 2 {
            3
        } else if section == 3 {
            2
        } else if section == 4 {
            1
        } else {
            2
        }
    }

    fn symmetry_section_chord_size(section: u32) -> u8 {
        if section == 0 {
            4
        } else if section == 1 {
            5
        } else if section == 2 {
            4
        } else if section == 3 {
            6
        } else if section == 4 {
            3
        } else {
            5
        }
    }

    fn symmetry_section_motif_seed(section: u32) -> felt252 {
        if section == 0 {
            0x1001
        } else if section == 1 {
            0x2002
        } else if section == 2 {
            0x3003
        } else if section == 3 {
            0x4004
        } else if section == 4 {
            0x5005
        } else {
            0x6006
        }
    }

    /// One MIDI leader pitch per tile onset, drawn from a symmetry-world motif.
    fn build_symmetry_section_leaders(
        section: u32, k: u32,
    ) -> Array<u8> {
        let world_id = symmetry_section_world_id(section);
        let transposition = symmetry_section_transposition(section);
        let world = transpose_world(get_world_by_id(world_id), transposition);
        let seed = symmetry_section_motif_seed(section);
        let motif = generate_world_motif(seed, world.mask, k.try_into().unwrap());
        let mut leaders: Array<u8> = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= k {
                break;
            }
            let pc = *motif.at(i.try_into().unwrap());
            let oct: u8 = if i % 3 == 0 {
                4
            } else if i % 3 == 1 {
                5
            } else {
                4
            };
            leaders.append(world_pc_to_midi(pc, oct));
            i += 1;
        };
        leaders
    }

    fn pitch_for_symmetry_canon_voice(
        voice_id: u32,
        tile_idx: u32,
        leaders: Span<u8>,
        mask: u16,
        chord_skip: u8,
    ) -> u8 {
        if voice_id == 0 {
            return *leaders.at(tile_idx);
        }
        let idx_u32: u32 = tile_idx + voice_id * chord_skip.into();
        let idx: u8 = idx_u32.try_into().unwrap();
        let pc = get_pitch_at_index(mask, idx);
        let oct: u8 = if voice_id == 1 {
            4
        } else if voice_id == 2 {
            5
        } else {
            5
        };
        world_pc_to_midi(pc, oct)
    }

    fn append_symmetry_harmony_chord(
        ref eventlist: Array<Message>,
        mask: u16,
        start_index: u8,
        skip: u8,
        chord_size: u8,
        on_time: Time,
        off_time: Time,
    ) {
        let chord = generate_world_chord(mask, start_index, skip, chord_size, false);
        let notes = chord_pcs_to_midi(chord.span());
        let mut i: usize = 0;
        loop {
            if i >= notes.len() {
                break;
            }
            let note = *notes.at(i);
            append_legato_note(ref eventlist, 4, note, 68, on_time, off_time);
            i += 1;
        };
    }

    /// Six-section symmetry-world tiling canon with evolving harmony.
    ///
    /// n=24 canon (seed 35): six short pickups + long tail, four interlocking voices.
    /// Six harmonic sections (5 loops each = 30 cycles, ~72 s at 120 BPM):
    ///   §1 Mode 2 → §2 Mode 3 → §3 Octatonic B → §4 Mode 6 → §5 Hex Aug → §6 Mode 7.
    /// Voice 0: symmetry-world LCG motif per section; voices 1–3 arpeggiate the active
    /// world with section-specific skip spacing. Channel 4 carries block chords that
    /// change at every section boundary and alternate voicings every two loops.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn symmetry_canon_multivoice_harmony_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 100000; // 100 ms/step → 2.4 s/cycle
        let loops_per_section: u32 = 5;
        let num_sections: u32 = 6;
        let num_loops: u32 = loops_per_section * num_sections;

        let canon = generate_rhythmic_canon_for_cycle(35, 24);
        assert!(canon.n == 24, "expected n=24");
        assert!(canon.translations.len() == 4, "expected 4 voices");
        assert!(canon.rhythm_tile.len() == 6, "expected 6 onsets per voice");

        let k = canon.rhythm_tile.len();

        let leaders0 = build_symmetry_section_leaders(0, k);
        let leaders1 = build_symmetry_section_leaders(1, k);
        let leaders2 = build_symmetry_section_leaders(2, k);
        let leaders3 = build_symmetry_section_leaders(3, k);
        let leaders4 = build_symmetry_section_leaders(4, k);
        let leaders5 = build_symmetry_section_leaders(5, k);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let n = canon.n;
        let tile = canon.rhythm_tile;
        let durs = canon.durations;
        let voices = canon.voices;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let section = loop_i / loops_per_section;
            let loop_in_section = loop_i % loops_per_section;
            let world_id = symmetry_section_world_id(section);
            let transposition = symmetry_section_transposition(section);
            let world = transpose_world(get_world_by_id(world_id), transposition);
            let chord_skip = symmetry_section_chord_skip(section);
            let chord_size = symmetry_section_chord_size(section);
            let chord_variant = loop_in_section / 2;
            let chord_start = symmetry_section_chord_start(section, chord_variant);

            let leaders_span = if section == 0 {
                leaders0.span()
            } else if section == 1 {
                leaders1.span()
            } else if section == 2 {
                leaders2.span()
            } else if section == 3 {
                leaders3.span()
            } else if section == 4 {
                leaders4.span()
            } else {
                leaders5.span()
            };

            let cycle_start: Time = (loop_i * n).into() * step_us;

            // Section-opening and mid-section harmony (channel 4)
            if loop_in_section == 0 || loop_in_section == 2 {
                let harm_on = cycle_start;
                let harm_off: Time = cycle_start + (n.into() * step_us) / 2;
                append_symmetry_harmony_chord(
                    ref eventlist,
                    world.mask,
                    chord_start,
                    chord_skip,
                    chord_size,
                    harm_on,
                    harm_off,
                );
            }

            let mut vi: u32 = 0;
            loop {
                if vi >= voices.len() {
                    break;
                }
                let voice = *voices.at(vi);
                if !voice.tiling_participant {
                    vi += 1;
                    continue;
                }

                let mut ti: u32 = 0;
                loop {
                    if ti >= tile.len() {
                        break;
                    }
                    let r = *tile.at(ti);
                    let grid_time = (r + voice.translation) % n;
                    let on_time: Time = cycle_start + grid_time.into() * step_us;
                    let dur_steps = *durs.at(ti);
                    let dur: u64 = dur_steps.into();
                    let off_time: Time = on_time + dur * step_us;
                    let pitch = pitch_for_symmetry_canon_voice(
                        voice.voice_id, ti, leaders_span, world.mask, chord_skip,
                    );
                    let vel = velocity_for_canon_voice_tile(
                        voice.voice_id, ti, dur_steps,
                    );
                    append_legato_note(
                        ref eventlist,
                        voice.voice_id.try_into().unwrap(),
                        pitch,
                        vel,
                        on_time,
                        off_time,
                    );
                    ti += 1;
                };
                vi += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        // 30 cycles × 24 grid onsets = 720 canon NoteOn + harmony chords
        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count >= 720, "expected at least 720 NoteOn");
        assert!(note_off_count >= 720, "expected at least 720 NoteOff");
        assert!(note_on_count == note_off_count, "on/off balance");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    // ── Lydian + symmetry-engine canon ───────────────────────────────────────────────

    fn lydian_section_tonic(section: u32) -> PitchClass {
        if section == 0 {
            PitchClass { note: 0_u8, octave: 4_u8 } // C Lydian
        } else if section == 1 {
            PitchClass { note: 5_u8, octave: 4_u8 } // F Lydian
        } else if section == 2 {
            PitchClass { note: 7_u8, octave: 4_u8 } // G Lydian
        } else if section == 3 {
            PitchClass { note: 2_u8, octave: 4_u8 } // D Lydian
        } else if section == 4 {
            PitchClass { note: 9_u8, octave: 4_u8 } // A Lydian
        } else {
            PitchClass { note: 4_u8, octave: 4_u8 } // E Lydian
        }
    }

    fn lydian_mask_for_tonic(tonic: PitchClass) -> u16 {
        let steps = mode_steps(Modes::Lydian(()));
        let pcs = get_notes_of_key(tonic, steps);
        let mut mask: u16 = 0;
        let mut i: u32 = 0;
        loop {
            if i >= pcs.len() {
                break;
            }
            mask = add_pitch(mask, *pcs.at(i));
            i += 1;
        };
        mask
    }

    fn lydian_keynum_from_scale_pc(pc: u8, octave: u8) -> u8 {
        pc_to_keynum(PitchClass { note: pc % 12, octave })
    }

    /// Chord skip tuned for a 7-note Lydian scale (not octatonic symmetry spacing).
    fn lydian_section_chord_skip(section: u32) -> u8 {
        if section == 0 || section == 3 {
            2 // diatonic third spacing → e.g. C E G B in C Lydian
        } else if section == 1 || section == 4 {
            1 // stepwise scale tones
        } else {
            2
        }
    }

    fn lydian_section_chord_size(section: u32) -> u8 {
        if section == 1 || section == 5 {
            5
        } else if section == 3 {
            6
        } else {
            4
        }
    }

    fn lydian_section_chord_start(section: u32, chord_variant: u32) -> u8 {
        let base = if section == 0 {
            0
        } else if section == 1 {
            1
        } else if section == 2 {
            0
        } else if section == 3 {
            2
        } else if section == 4 {
            1
        } else {
            0
        };
        base + chord_variant.try_into().unwrap()
    }

    /// Motif leaders drawn directly from the section Lydian pitch-world (7-note mask).
    fn build_lydian_leaders_for_block_loop(
        section: u32, k: u32, tonic: PitchClass, rhythm_block: u32, loop_i: u32,
    ) -> Array<u8> {
        let lydian = lydian_mask_for_tonic(tonic);
        let base = symmetry_section_motif_seed(section);
        let block_felt: felt252 = rhythm_block.into();
        let loop_felt: felt252 = loop_i.into();
        let seed = base + block_felt + loop_felt;
        let motif = generate_world_motif(seed, lydian, k.try_into().unwrap());
        let mut leaders: Array<u8> = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= k {
                break;
            }
            let pc = *motif.at(i.try_into().unwrap());
            let oct: u8 = if i % 3 == 0 {
                4
            } else if i % 3 == 1 {
                5
            } else {
                4
            };
            leaders.append(lydian_keynum_from_scale_pc(pc, oct));
            i += 1;
        };
        leaders
    }

    fn build_lydian_leaders_for_block(
        section: u32, k: u32, tonic: PitchClass, rhythm_block: u32,
    ) -> Array<u8> {
        build_lydian_leaders_for_block_loop(section, k, tonic, rhythm_block, 0)
    }

    fn build_lydian_symmetry_section_leaders(
        section: u32, k: u32, tonic: PitchClass,
    ) -> Array<u8> {
        build_lydian_leaders_for_block(section, k, tonic, 0)
    }

    /// Deterministic n=24 canon seed per harmonic/rhythm block (section × block).
    fn rhythm_block_seed(section: u32, rhythm_block: u32) -> felt252 {
        let idx = section * 3 + rhythm_block;
        if idx % 7 == 0 {
            35
        } else if idx % 7 == 1 {
            42
        } else if idx % 7 == 2 {
            17
        } else if idx % 7 == 3 {
            100
        } else if idx % 7 == 4 {
            555
        } else if idx % 7 == 5 {
            888
        } else {
            1234
        }
    }

    const NO_PRIOR_PITCH: u8 = 255;
    const PITCH_MEMORY_CHANNELS: u32 = 5;

    #[derive(Copy, Drop)]
    struct ChannelPitchMemory {
        ch0_pitch: u8,
        ch0_time: Time,
        ch1_pitch: u8,
        ch1_time: Time,
        ch2_pitch: u8,
        ch2_time: Time,
        ch3_pitch: u8,
        ch3_time: Time,
        ch4_pitch: u8,
        ch4_time: Time,
    }

    fn channel_pitch_memory_new() -> ChannelPitchMemory {
        ChannelPitchMemory {
            ch0_pitch: NO_PRIOR_PITCH,
            ch0_time: 0,
            ch1_pitch: NO_PRIOR_PITCH,
            ch1_time: 0,
            ch2_pitch: NO_PRIOR_PITCH,
            ch2_time: 0,
            ch3_pitch: NO_PRIOR_PITCH,
            ch3_time: 0,
            ch4_pitch: NO_PRIOR_PITCH,
            ch4_time: 0,
        }
    }

    fn memory_get_last(mem: @ChannelPitchMemory, channel: u8) -> (u8, Time) {
        if channel == 0 {
            (*mem.ch0_pitch, *mem.ch0_time)
        } else if channel == 1 {
            (*mem.ch1_pitch, *mem.ch1_time)
        } else if channel == 2 {
            (*mem.ch2_pitch, *mem.ch2_time)
        } else if channel == 3 {
            (*mem.ch3_pitch, *mem.ch3_time)
        } else {
            (*mem.ch4_pitch, *mem.ch4_time)
        }
    }

    fn memory_set_last(ref mem: ChannelPitchMemory, channel: u8, pitch: u8, on_time: Time) {
        if channel == 0 {
            mem.ch0_pitch = pitch;
            mem.ch0_time = on_time;
        } else if channel == 1 {
            mem.ch1_pitch = pitch;
            mem.ch1_time = on_time;
        } else if channel == 2 {
            mem.ch2_pitch = pitch;
            mem.ch2_time = on_time;
        } else if channel == 3 {
            mem.ch3_pitch = pitch;
            mem.ch3_time = on_time;
        } else {
            mem.ch4_pitch = pitch;
            mem.ch4_time = on_time;
        }
    }

    /// If the same channel re-attacks the same pitch within min_gap, step up in Lydian.
    fn lydian_pitch_avoid_channel_repeat(
        candidate: u8,
        channel: u8,
        on_time: Time,
        min_gap: Time,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
        mem: @ChannelPitchMemory,
    ) -> u8 {
        let (last_pitch, last_time) = memory_get_last(mem, channel);
        if last_pitch == NO_PRIOR_PITCH {
            return candidate;
        }
        if candidate != last_pitch {
            return candidate;
        }
        if on_time > last_time + min_gap {
            return candidate;
        }
        let mut out = candidate;
        let mut tries: u8 = 0;
        loop {
            if tries >= 5 {
                break;
            }
            out = modal_transposition(
                keynum_to_pc(out), tonic, lyd_steps, 1, Direction::Up(()),
            );
            if out != last_pitch {
                break;
            }
            tries += 1;
        };
        out
    }

    fn pitch_for_lydian_canon_voice_varied(
        voice_id: u32,
        tile_idx: u32,
        loop_i: u32,
        leaders: Span<u8>,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
    ) -> u8 {
        let k: u32 = leaders.len();
        if k == 0 {
            return 60;
        }
        let rot: u32 = (tile_idx + voice_id + loop_i) % k;
        pitch_for_canon_voice_at_tile(voice_id, rot, leaders, tonic, lyd_steps)
    }

    fn append_lydian_canon_cycle_smooth(
        ref eventlist: Array<Message>,
        ref mem: ChannelPitchMemory,
        cycle_start: Time,
        step_us: u64,
        min_gap: Time,
        loop_i: u32,
        n: u32,
        tile: Span<u32>,
        durs: Span<u32>,
        voices: Span<RhythmicVoice>,
        leaders: Span<u8>,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
    ) {
        let mut vi: u32 = 0;
        loop {
            if vi >= voices.len() {
                break;
            }
            let voice = *voices.at(vi);
            if !voice.tiling_participant {
                vi += 1;
                continue;
            }

            let channel: u8 = voice.voice_id.try_into().unwrap();
            let mut ti: u32 = 0;
            loop {
                if ti >= tile.len() {
                    break;
                }
                let r = *tile.at(ti);
                let grid_time = (r + voice.translation) % n;
                let on_time: Time = cycle_start + grid_time.into() * step_us;
                let dur_steps = *durs.at(ti);
                let dur: u64 = dur_steps.into();
                let off_time: Time = on_time + dur * step_us;
                let candidate = pitch_for_lydian_canon_voice_varied(
                    voice.voice_id, ti, loop_i, leaders, tonic, lyd_steps,
                );
                let pitch = lydian_pitch_avoid_channel_repeat(
                    candidate, channel, on_time, min_gap, tonic, lyd_steps, @mem,
                );
                memory_set_last(ref mem, channel, pitch, on_time);
                let vel = velocity_for_canon_voice_tile(voice.voice_id, ti, dur_steps);
                append_legato_note(
                    ref eventlist, channel, pitch, vel, on_time, off_time,
                );
                ti += 1;
            };
            vi += 1;
        };
    }

    fn append_lydian_symmetry_harmony_chord_smooth(
        ref eventlist: Array<Message>,
        ref mem: ChannelPitchMemory,
        lydian: u16,
        start_index: u8,
        skip: u8,
        chord_size: u8,
        on_time: Time,
        off_time: Time,
        min_gap: Time,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
    ) {
        let chord = generate_world_chord(lydian, start_index, skip, chord_size, false);
        let mut i: usize = 0;
        loop {
            if i >= chord.len() {
                break;
            }
            let pc = *chord.at(i);
            let oct: u8 = if i == 0 {
                3
            } else if i <= 2 {
                4
            } else {
                4
            };
            let candidate = lydian_keynum_from_scale_pc(pc, oct);
            let pitch = lydian_pitch_avoid_channel_repeat(
                candidate, 4, on_time, min_gap, tonic, lyd_steps, @mem,
            );
            memory_set_last(ref mem, 4, pitch, on_time);
            append_legato_note(ref eventlist, 4, pitch, 70, on_time, off_time);
            i += 1;
        };
    }

    fn append_lydian_canon_cycle(
        ref eventlist: Array<Message>,
        cycle_start: Time,
        step_us: u64,
        n: u32,
        tile: Span<u32>,
        durs: Span<u32>,
        voices: Span<RhythmicVoice>,
        leaders: Span<u8>,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
    ) {
        let mut vi: u32 = 0;
        loop {
            if vi >= voices.len() {
                break;
            }
            let voice = *voices.at(vi);
            if !voice.tiling_participant {
                vi += 1;
                continue;
            }

            let mut ti: u32 = 0;
            loop {
                if ti >= tile.len() {
                    break;
                }
                let r = *tile.at(ti);
                let grid_time = (r + voice.translation) % n;
                let on_time: Time = cycle_start + grid_time.into() * step_us;
                let dur_steps = *durs.at(ti);
                let dur: u64 = dur_steps.into();
                let off_time: Time = on_time + dur * step_us;
                let pitch = pitch_for_lydian_symmetry_canon_voice(
                    voice.voice_id, ti, leaders, tonic, lyd_steps,
                );
                let vel = velocity_for_canon_voice_tile(voice.voice_id, ti, dur_steps);
                append_legato_note(
                    ref eventlist,
                    voice.voice_id.try_into().unwrap(),
                    pitch,
                    vel,
                    on_time,
                    off_time,
                );
                ti += 1;
            };
            vi += 1;
        };
    }

    /// Thin cantus motif: hocket rests on a section/block-dependent grid (keeps first/last onsets).
    fn inject_sparse_rests(leaders: Span<u8>, section: u32, rhythm_block: u32) -> Array<u8> {
        let len = leaders.len();
        let gap: u32 = 2 + (section % 2);
        let phase: u32 = (section + rhythm_block) % gap;
        let last: u32 = if len == 0 {
            0
        } else {
            (len - 1).try_into().unwrap()
        };
        let mut out: Array<u8> = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= len.try_into().unwrap() {
                break;
            }
            let idx: usize = i.try_into().unwrap();
            if i == 0 || i == last {
                out.append(*leaders.at(idx));
            } else if (i + phase) % gap == 0 {
                out.append(REST_PITCH);
            } else {
                out.append(*leaders.at(idx));
            }
            i += 1;
        };
        out
    }

    /// Render one canon cycle from a precomputed pairwise counterpoint harmony plan.
    fn append_counterpoint_canon_cycle(
        ref eventlist: Array<Message>,
        cycle_start: Time,
        step_us: u64,
        n: u32,
        tile: Span<u32>,
        durs: Span<u32>,
        voices: Span<RhythmicVoice>,
        plan: @CanonHarmonyPlan,
    ) {
        let mut vi: u32 = 0;
        loop {
            if vi >= voices.len() {
                break;
            }
            let voice = *voices.at(vi);
            if !voice.tiling_participant {
                vi += 1;
                continue;
            }

            let mut ti: u32 = 0;
            loop {
                if ti >= tile.len() {
                    break;
                }
                if harmony_plan_is_rest(plan, voice.voice_id, ti) {
                    ti += 1;
                    continue;
                }
                let r = *tile.at(ti);
                let grid_time = (r + voice.translation) % n;
                let on_time: Time = cycle_start + grid_time.into() * step_us;
                let dur_steps = *durs.at(ti);
                let off_time: Time = on_time + dur_steps.into() * step_us;
                let pitch = pitch_from_harmony_plan(plan, voice.voice_id, ti);
                let vel = velocity_for_canon_voice_tile(voice.voice_id, ti, dur_steps);
                append_legato_note(
                    ref eventlist,
                    voice.voice_id.try_into().unwrap(),
                    pitch,
                    vel,
                    on_time,
                    off_time,
                );
                ti += 1;
            };
            vi += 1;
        };
    }

    fn pitch_for_lydian_symmetry_canon_voice(
        voice_id: u32,
        tile_idx: u32,
        leaders: Span<u8>,
        tonic: PitchClass,
        lyd_steps: Span<u8>,
    ) -> u8 {
        pitch_for_canon_voice_at_tile(voice_id, tile_idx, leaders, tonic, lyd_steps)
    }

    fn append_lydian_symmetry_harmony_chord(
        ref eventlist: Array<Message>,
        lydian: u16,
        start_index: u8,
        skip: u8,
        chord_size: u8,
        on_time: Time,
        off_time: Time,
    ) {
        let chord = generate_world_chord(lydian, start_index, skip, chord_size, false);
        let mut i: usize = 0;
        loop {
            if i >= chord.len() {
                break;
            }
            let pc = *chord.at(i);
            let oct: u8 = if i == 0 {
                3
            } else if i <= 2 {
                4
            } else {
                4
            };
            let note = lydian_keynum_from_scale_pc(pc, oct);
            append_legato_note(ref eventlist, 4, note, 70, on_time, off_time);
            i += 1;
        };
    }

    /// Lydian multivoice symmetry canon — same architecture as the octatonic version,
    /// but all pitch material lives in the active section Lydian collection.
    ///
    /// n=24 (seed 42), 6 sections × 5 loops (~72 s). Each section modulates Lydian center:
    ///   C → F → G → D → A → E. Motifs and block chords are generated from each section's
    ///   7-note Lydian mask (not octatonic symmetry worlds). §1 opening chord: C–E–G–B
    ///   (C Lydian maj7). Canon voices 0–3 stack diatonic 3rds via modal_transposition.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn symmetry_canon_lydian_multivoice_harmony_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 100000;
        let loops_per_section: u32 = 5;
        let num_sections: u32 = 6;
        let num_loops: u32 = loops_per_section * num_sections;

        let canon = generate_rhythmic_canon_for_cycle(42, 24);
        assert!(canon.n == 24, "expected n=24");
        assert!(canon.translations.len() == 4, "expected 4 voices");

        let k = canon.rhythm_tile.len();
        let lyd_steps = mode_steps(Modes::Lydian(()));

        // §1 opening voicing must be C Lydian maj7: C E G B (pcs 0,4,7,11).
        let c_lydian = lydian_mask_for_tonic(lydian_section_tonic(0));
        let opening = generate_world_chord(c_lydian, 0, 2, 4, false);
        assert!(opening.len() == 4, "opening chord len");
        assert!(*opening.at(0) == 0, "C root");
        assert!(*opening.at(1) == 4, "E third");
        assert!(*opening.at(2) == 7, "G fifth");
        assert!(*opening.at(3) == 11, "B lyd seventh");

        let leaders0 = build_lydian_symmetry_section_leaders(0, k, lydian_section_tonic(0));
        let leaders1 = build_lydian_symmetry_section_leaders(1, k, lydian_section_tonic(1));
        let leaders2 = build_lydian_symmetry_section_leaders(2, k, lydian_section_tonic(2));
        let leaders3 = build_lydian_symmetry_section_leaders(3, k, lydian_section_tonic(3));
        let leaders4 = build_lydian_symmetry_section_leaders(4, k, lydian_section_tonic(4));
        let leaders5 = build_lydian_symmetry_section_leaders(5, k, lydian_section_tonic(5));

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let n = canon.n;
        let tile = canon.rhythm_tile;
        let durs = canon.durations;
        let voices = canon.voices;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let section = loop_i / loops_per_section;
            let loop_in_section = loop_i % loops_per_section;
            let tonic = lydian_section_tonic(section);
            let lydian = lydian_mask_for_tonic(tonic);
            let chord_skip = lydian_section_chord_skip(section);
            let chord_size = lydian_section_chord_size(section);
            let chord_variant = loop_in_section / 2;
            let chord_start = lydian_section_chord_start(section, chord_variant);

            let leaders_span = if section == 0 {
                leaders0.span()
            } else if section == 1 {
                leaders1.span()
            } else if section == 2 {
                leaders2.span()
            } else if section == 3 {
                leaders3.span()
            } else if section == 4 {
                leaders4.span()
            } else {
                leaders5.span()
            };

            let cycle_start: Time = (loop_i * n).into() * step_us;

            if loop_in_section == 0 || loop_in_section == 2 || loop_in_section == 4 {
                let harm_on = cycle_start;
                let harm_off: Time = cycle_start + (n.into() * step_us) / 2;
                append_lydian_symmetry_harmony_chord(
                    ref eventlist,
                    lydian,
                    chord_start,
                    chord_skip,
                    chord_size,
                    harm_on,
                    harm_off,
                );
            }

            let mut vi: u32 = 0;
            loop {
                if vi >= voices.len() {
                    break;
                }
                let voice = *voices.at(vi);
                if !voice.tiling_participant {
                    vi += 1;
                    continue;
                }

                let mut ti: u32 = 0;
                loop {
                    if ti >= tile.len() {
                        break;
                    }
                    let r = *tile.at(ti);
                    let grid_time = (r + voice.translation) % n;
                    let on_time: Time = cycle_start + grid_time.into() * step_us;
                    let dur_steps = *durs.at(ti);
                    let dur: u64 = dur_steps.into();
                    let off_time: Time = on_time + dur * step_us;
                    let pitch = pitch_for_lydian_symmetry_canon_voice(
                        voice.voice_id, ti, leaders_span, tonic, lyd_steps,
                    );
                    let vel = velocity_for_canon_voice_tile(
                        voice.voice_id, ti, dur_steps,
                    );
                    append_legato_note(
                        ref eventlist,
                        voice.voice_id.try_into().unwrap(),
                        pitch,
                        vel,
                        on_time,
                        off_time,
                    );
                    ti += 1;
                };
                vi += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count >= 720, "expected at least 720 NoteOn");
        assert!(note_off_count >= 720, "expected at least 720 NoteOff");
        assert!(note_on_count == note_off_count, "on/off balance");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Lydian canon with **rhythm pattern rotating on every chord change** (every 2 loops).
    ///
    /// Same harmonic plan as `symmetry_canon_lydian_multivoice_harmony_midi_test`, but each
    /// chord variant (loops 0/2/4 within a section) selects a fresh n=24 tiling template
    /// and matching tile-length motif leaders. Loops 1 and 3 repeat the prior block's rhythm.
    #[ignore]
    #[test]
    #[available_gas(3000000000000)]
    fn symmetry_canon_lydian_varied_rhythm_harmony_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 100000;
        let loops_per_section: u32 = 5;
        let num_sections: u32 = 6;
        let num_loops: u32 = loops_per_section * num_sections;
        let cycle_n: u32 = 24;

        let lyd_steps = mode_steps(Modes::Lydian(()));

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let section = loop_i / loops_per_section;
            let loop_in_section = loop_i % loops_per_section;
            let rhythm_block = loop_in_section / 2;
            let chord_variant = rhythm_block;
            let tonic = lydian_section_tonic(section);
            let lydian = lydian_mask_for_tonic(tonic);

            let rhythm_seed = rhythm_block_seed(section, rhythm_block);
            let canon = generate_rhythmic_canon_for_cycle(rhythm_seed, cycle_n);
            assert!(canon.n == cycle_n, "expected n=24");
            let k = canon.rhythm_tile.len();
            let leaders = build_lydian_leaders_for_block(section, k, tonic, rhythm_block);

            let chord_skip = lydian_section_chord_skip(section);
            let chord_size = lydian_section_chord_size(section);
            let chord_start = lydian_section_chord_start(section, chord_variant);

            let cycle_start: Time = (loop_i * cycle_n).into() * step_us;

            if loop_in_section % 2 == 0 {
                let harm_on = cycle_start;
                let harm_off: Time = cycle_start + (cycle_n.into() * step_us) / 2;
                append_lydian_symmetry_harmony_chord(
                    ref eventlist,
                    lydian,
                    chord_start,
                    chord_skip,
                    chord_size,
                    harm_on,
                    harm_off,
                );
            }

            append_lydian_canon_cycle(
                ref eventlist,
                cycle_start,
                step_us,
                cycle_n,
                canon.rhythm_tile,
                canon.durations,
                canon.voices,
                leaders.span(),
                tonic,
                lyd_steps,
            );
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count >= 720, "expected at least 720 NoteOn");
        assert!(note_off_count >= 720, "expected at least 720 NoteOff");
        assert!(note_on_count == note_off_count, "on/off balance");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Varied-rhythm Lydian canon with anti-repetition: per-loop motif rotation plus modal
    /// step-up when a channel re-attacks the same pitch within one grid step.
    #[ignore]
    #[test]
    #[available_gas(3500000000000)]
    fn symmetry_canon_lydian_varied_rhythm_smooth_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 100000;
        let min_gap: Time = step_us;
        let loops_per_section: u32 = 5;
        let num_sections: u32 = 6;
        let num_loops: u32 = loops_per_section * num_sections;
        let cycle_n: u32 = 24;

        let lyd_steps = mode_steps(Modes::Lydian(()));
        let mut pitch_mem = channel_pitch_memory_new();

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let section = loop_i / loops_per_section;
            let loop_in_section = loop_i % loops_per_section;
            let rhythm_block = loop_in_section / 2;
            let chord_variant = rhythm_block;
            let tonic = lydian_section_tonic(section);
            let lydian = lydian_mask_for_tonic(tonic);

            let rhythm_seed = rhythm_block_seed(section, rhythm_block);
            let canon = generate_rhythmic_canon_for_cycle(rhythm_seed, cycle_n);
            assert!(canon.n == cycle_n, "expected n=24");
            let k = canon.rhythm_tile.len();
            let leaders = build_lydian_leaders_for_block_loop(
                section, k, tonic, rhythm_block, loop_i,
            );

            let chord_skip = lydian_section_chord_skip(section);
            let chord_size = lydian_section_chord_size(section);
            let chord_start = lydian_section_chord_start(section, chord_variant);

            let cycle_start: Time = (loop_i * cycle_n).into() * step_us;

            if loop_in_section % 2 == 0 {
                let harm_on = cycle_start;
                let harm_off: Time = cycle_start + (cycle_n.into() * step_us) / 2;
                append_lydian_symmetry_harmony_chord_smooth(
                    ref eventlist,
                    ref pitch_mem,
                    lydian,
                    chord_start,
                    chord_skip,
                    chord_size,
                    harm_on,
                    harm_off,
                    min_gap,
                    tonic,
                    lyd_steps,
                );
            }

            append_lydian_canon_cycle_smooth(
                ref eventlist,
                ref pitch_mem,
                cycle_start,
                step_us,
                min_gap,
                loop_i,
                cycle_n,
                canon.rhythm_tile,
                canon.durations,
                canon.voices,
                leaders.span(),
                tonic,
                lyd_steps,
            );
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count >= 720, "expected at least 720 NoteOn");
        assert!(note_off_count >= 720, "expected at least 720 NoteOff");
        assert!(note_on_count == note_off_count, "on/off balance");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    fn generate_parser_format(self: @Midi) {
        // Generate individual MIDI event lines for the TypeScript parser
        let mut ev = self.clone().events;

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(NoteOn) => {
                            let note = *NoteOn.note;
                            let channel = *NoteOn.channel;
                            let velocity = *NoteOn.velocity;
                            let time = *NoteOn.time;
                            println!(
                                "Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                                channel,
                                note,
                                velocity,
                                time,
                            );
                        },
                        Message::NOTE_OFF(NoteOff) => {
                            let note = *NoteOff.note;
                            let channel = *NoteOff.channel;
                            let velocity = *NoteOff.velocity;
                            let time = *NoteOff.time;
                            println!(
                                "Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                                channel,
                                note,
                                velocity,
                                time,
                            );
                        },
                        Message::SET_TEMPO(SetTempo) => {
                            let tempo = *SetTempo.tempo;
                            match *SetTempo.time {
                                Option::Some(time_val) => {
                                    println!(
                                        "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }})",
                                        tempo,
                                        time_val,
                                    );
                                },
                                Option::None(_) => {
                                    println!(
                                        "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::None }})",
                                        tempo,
                                    );
                                },
                            };
                        },
                        Message::TIME_SIGNATURE(_TimeSignature) => {},
                        Message::CONTROL_CHANGE(_ControlChange) => {},
                        Message::PITCH_WHEEL(_PitchWheel) => {},
                        Message::AFTER_TOUCH(_AfterTouch) => {},
                        Message::POLY_TOUCH(_PolyTouch) => {},
                        Message::PROGRAM_CHANGE(_ProgramChange) => {},
                        Message::SYSTEM_EXCLUSIVE(_SystemExclusive) => {},
                    }
                },
                Option::None(_) => { break; },
            };
        }
    }

    /// Long LCG melody in Messiaen Mode 2 (octatonic), harmonized with modal chords, 3 repetitions.
    ///
    /// Mode   : 2 — [0,1,3,4,6,7,9,10], transposition 0
    /// Melody : LCG { state:91, mult:5, inc:3, mod:64 } → 32 pitch classes per cycle
    /// Harmony: diminished symmetry chord (skip=2, size=4) every 8 melody steps
    ///          + dense color chord (skip=1, size=6) at cycle start
    ///
    /// Timing : step = 125 000 µs (1/16 @ 120 BPM), note_dur = 100 000 µs
    ///          1 cycle = 32 × 125 000 = 4 000 000 µs (4 s)
    ///          3 cycles = 12 000 000 µs (12 s)
    ///
    /// Events : 3 × (32 melody + 4 block + 4 block) NoteOn/Off + SetTempo
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn messiaen_lcg_melody_harmony_test() {
        let mode_id: u8 = 2;
        let transposition: u8 = 0;
        let n_steps: u32 = 32;
        let n_reps: u32 = 3;

        let melody_pcs = generate_melody_pitch_classes(mode_id, transposition, n_steps, 91);
        assert!(melody_pcs.len() == n_steps, "melody length");

        let color_chord = generate_chord(mode_id, transposition, 1, 1, 6);
        let color_midi = chord_pcs_to_midi(color_chord.span());

        let step_dur: u64 = 125000_u64;
        let note_dur: u64 = 100000_u64;
        let chord_dur: u64 = 350000_u64;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut current_time: u64 = 0_u64;
        let mut rep: u32 = 0;
        loop {
            if rep >= n_reps {
                break;
            }

            // Cycle-opening color chord (channel 1)
            let mut ci: usize = 0;
            loop {
                if ci >= color_midi.len() {
                    break;
                }
                let note = *color_midi.at(ci);
                eventlist
                    .append(
                        Message::NOTE_ON(
                            NoteOn { channel: 1, note: note, velocity: 72, time: current_time },
                        ),
                    );
                eventlist
                    .append(
                        Message::NOTE_OFF(
                            NoteOff {
                                channel: 1,
                                note: note,
                                velocity: 64,
                                time: current_time + chord_dur,
                            },
                        ),
                    );
                ci += 1;
            };

            let mut step: u32 = 0;
            loop {
                if step >= n_steps {
                    break;
                }

                // Melody: LCG mode index → MIDI (octave 4–5 by step)
                let pc = *melody_pcs.at(step.try_into().unwrap());
                let oct: u8 = if step % 2 == 0 { 4 } else { 5 };
                let mel_note = mode_pc_to_midi(pc, oct);
                eventlist
                    .append(
                        Message::NOTE_ON(
                            NoteOn { channel: 0, note: mel_note, velocity: 88, time: current_time },
                        ),
                    );
                eventlist
                    .append(
                        Message::NOTE_OFF(
                            NoteOff {
                                channel: 0,
                                note: mel_note,
                                velocity: 64,
                                time: current_time + note_dur,
                            },
                        ),
                    );

                // Every 8 steps: diminished block chord rooted at current melody pc
                if step % 8 == 4 {
                    let start_idx: u8 = (step % 8).try_into().unwrap();
                    let harm = generate_diminished_symmetry_chord(transposition, start_idx);
                    let harm_midi = chord_pcs_to_midi(harm.span());
                    let mut hi: usize = 0;
                    loop {
                        if hi >= harm_midi.len() {
                            break;
                        }
                        let hnote = *harm_midi.at(hi);
                        eventlist
                            .append(
                                Message::NOTE_ON(
                                    NoteOn {
                                        channel: 1,
                                        note: hnote,
                                        velocity: 70,
                                        time: current_time,
                                    },
                                ),
                            );
                        eventlist
                            .append(
                                Message::NOTE_OFF(
                                    NoteOff {
                                        channel: 1,
                                        note: hnote,
                                        velocity: 64,
                                        time: current_time + chord_dur,
                                    },
                                ),
                            );
                        hi += 1;
                    };
                }

                current_time += step_dur;
                step += 1;
            };
            rep += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        // 3 reps × (32 melody + 6 color + 4×4 block at steps 4,12,20,28) = 3×54 = 162 each
        assert!(note_on_count == 162, "Expected 162 NoteOn");
        assert!(note_off_count == 162, "Expected 162 NoteOff");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    /// Lydian canon with counterpoint-generated harmony voices (replaces fixed diatonic 3rds).
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn symmetry_canon_lydian_counterpoint_harmony_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 100000;
        let num_loops: u32 = 2;

        let canon = generate_rhythmic_canon_for_cycle(42, 24);
        assert!(canon.n == 24, "expected n=24");
        let k = canon.rhythm_tile.len();
        let tonic = lydian_section_tonic(0);
        let leaders = build_lydian_symmetry_section_leaders(0, k, tonic);
        let num_voices = count_tiling_voices(@canon);
        let plan = plan_lydian_canon_harmony(4242, leaders.span(), tonic, 0, num_voices);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let n = canon.n;
        let tile = canon.rhythm_tile;
        let durs = canon.durations;
        let voices = canon.voices;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let cycle_start: Time = (loop_i * n).into() * step_us;

            let mut vi: u32 = 0;
            loop {
                if vi >= voices.len() {
                    break;
                }
                let voice = *voices.at(vi);
                if !voice.tiling_participant {
                    vi += 1;
                    continue;
                }

                let mut ti: u32 = 0;
                loop {
                    if ti >= tile.len() {
                        break;
                    }
                    let r = *tile.at(ti);
                    let grid_time = (r + voice.translation) % n;
                    let on_time: Time = cycle_start + grid_time.into() * step_us;
                    let dur_steps = *durs.at(ti);
                    let off_time: Time = on_time + dur_steps.into() * step_us;
                    let pitch = pitch_from_harmony_plan(@plan, voice.voice_id, ti);
                    if harmony_plan_is_rest(@plan, voice.voice_id, ti) {
                        ti += 1;
                        continue;
                    }
                    let vel = velocity_for_canon_voice_tile(
                        voice.voice_id, ti, dur_steps,
                    );
                    append_legato_note(
                        ref eventlist,
                        voice.voice_id.try_into().unwrap(),
                        pitch,
                        vel,
                        on_time,
                        off_time,
                    );
                    ti += 1;
                };
                vi += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };

        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count >= 32, "expected counterpoint canon notes");
        assert!(note_on_count == note_off_count, "on/off balance");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
    }

    /// Full integration: varied n=24 rhythmic templates, sparse cantus rests, and
    /// pairwise N-voice counterpoint harmony on every tiling voice.
    ///
    /// **C Lydian throughout** (tonic C4, F# scale) — counterpoint candidates are
    /// constrained to the same 7-note Lydian pitch-world as the leader motifs.
    #[ignore]
    #[test]
    #[available_gas(5000000000000)]
    fn rhythmic_canon_counterpoint_varied_sparse_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 100000;
        let loops_per_section: u32 = 5;
        let num_sections: u32 = 6;
        let num_loops: u32 = loops_per_section * num_sections;
        let cycle_n: u32 = 24;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut max_tile_onsets: u32 = 0;
        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let section = loop_i / loops_per_section;
            let loop_in_section = loop_i % loops_per_section;
            let rhythm_block = loop_in_section / 2;
            let chord_variant = rhythm_block;
            let tonic = PitchClass { note: 0_u8, octave: 4_u8 };
            let lydian = lydian_mask_for_tonic(tonic);
            let c_lydian_world = lydian;

            let rhythm_seed = rhythm_block_seed(section, rhythm_block);
            let canon = generate_rhythmic_canon_for_cycle_min_voices(rhythm_seed, cycle_n, 8);
            assert!(canon.n == cycle_n, "expected n=24");
            let k = canon.rhythm_tile.len();
            if k > max_tile_onsets {
                max_tile_onsets = k;
            }

            let num_voices = count_tiling_voices(@canon);
            assert!(num_voices == 8, "expected 8-voice canon");

            let leaders_dense = build_lydian_leaders_for_block_loop(
                0, k, tonic, rhythm_block, loop_in_section,
            );
            let leaders = inject_sparse_rests(leaders_dense.span(), section, rhythm_block);

            let cp_seed: felt252 = 7700 + section.into() + rhythm_block.into() + loop_i.into();
            let plan = plan_lydian_canon_harmony(
                cp_seed, leaders.span(), tonic, 0, num_voices,
            );
            assert!(plan.voices.len() == num_voices, "plan voice count");
            assert!(plan.onset_mask.len() == k, "onset mask len");

            let mut vcheck: u32 = 0;
            loop {
                if vcheck >= num_voices {
                    break;
                }
                let voice = plan.voices.at(vcheck);
                let mut ti: u32 = 0;
                loop {
                    if ti >= voice.len() {
                        break;
                    }
                    if !harmony_plan_is_rest(@plan, vcheck, ti) {
                        let p = pitch_from_harmony_plan(@plan, vcheck, ti);
                        assert!(
                            has_pitch(c_lydian_world, p % 12),
                            "pitch must stay in C Lydian",
                        );
                    }
                    ti += 1;
                };
                vcheck += 1;
            };

            let cycle_start: Time = (loop_i * cycle_n).into() * step_us;

            if loop_in_section % 2 == 0 {
                let harm_on = cycle_start;
                let harm_off: Time = cycle_start + (cycle_n.into() * step_us) / 2;
                append_lydian_symmetry_harmony_chord(
                    ref eventlist,
                    lydian,
                    lydian_section_chord_start(0, chord_variant),
                    lydian_section_chord_skip(0),
                    lydian_section_chord_size(0),
                    harm_on,
                    harm_off,
                );
            }

            append_counterpoint_canon_cycle(
                ref eventlist,
                cycle_start,
                step_us,
                cycle_n,
                canon.rhythm_tile,
                canon.durations,
                canon.voices,
                @plan,
            );
            loop_i += 1;
        };

        assert!(max_tile_onsets >= 3, "expected varied tile sizes");

        let midiobj = Midi { events: eventlist.span() };

        generate_cairo_code(@midiobj);
        generate_parser_format(@midiobj);

        let mut ev = midiobj.events;
        let mut note_on_count: u32 = 0;
        let mut note_off_count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { note_on_count += 1; },
                        Message::NOTE_OFF(_) => { note_off_count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
        assert!(note_on_count >= 400, "expected dense counterpoint canon");
        assert!(note_on_count == note_off_count, "on/off balance");

        let binary = output_midi_object(@midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "byte 0 should be M");
        assert!(*binary.get(1).unwrap().unbox() == 0x54, "byte 1 should be T");
        assert!(*binary.get(2).unwrap().unbox() == 0x68, "byte 2 should be h");
        assert!(*binary.get(3).unwrap().unbox() == 0x64, "byte 3 should be d");
    }

    // ── Counterpoint tooling demos (simple MIDI examples) ─────────────────────────

    fn c_lydian_demo_tonic() -> PitchClass {
        PitchClass { note: 0_u8, octave: 4_u8 }
    }

    /// C Lydian counterpoint params with explicit motion bias (for demos).
    fn c_lydian_counterpoint_demo_params(
        seed: felt252,
        tile_len: u32,
        motion_bias: koji::composition::counterpoint::MotionBias,
    ) -> CounterpointParams {
        c_lydian_counterpoint_demo_params_placed(
            seed, tile_len, motion_bias, VoicePlacement::BelowCantus(()),
        )
    }

    fn c_lydian_counterpoint_demo_params_placed(
        seed: felt252,
        tile_len: u32,
        motion_bias: koji::composition::counterpoint::MotionBias,
        placement: VoicePlacement,
    ) -> CounterpointParams {
        let tonic = c_lydian_demo_tonic();
        let mode_spec = uniform_mode_timeline(
            tile_len, Modes::Lydian(()), lydian_pitch_world_mask(tonic), tonic,
        );
        CounterpointParams {
            seed,
            tonic,
            mode_spec,
            register_lo: 48,
            register_hi: 84,
            max_melodic_leap: 12,
            motion_bias,
            voice_placement: placement,
            forbid_parallel_perfects: true,
            forbid_similar_perfects: true,
        }
    }

    /// Render cantus + counter as two aligned monophonic lines (no rhythmic canon).
    fn append_two_voice_counterpoint_demo(
        ref eventlist: Array<Message>,
        cantus: Span<u8>,
        counter: Span<u8>,
        step_us: u64,
        note_dur_us: u64,
    ) {
        assert!(cantus.len() == counter.len(), "line length mismatch");
        let len: u32 = cantus.len().try_into().unwrap();
        let mut i: u32 = 0;
        loop {
            if i >= len {
                break;
            }
            let idx: usize = i.try_into().unwrap();
            let on: Time = i.into() * step_us;
            let off: Time = on + note_dur_us;
            append_legato_note(ref eventlist, 0, *cantus.at(idx), 92, on, off);
            append_legato_note(ref eventlist, 1, *counter.at(idx), 78, on, off);
            i += 1;
        };
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
        assert!(note_on_count == expected_note_ons, "note on count");
        assert!(note_on_count == note_off_count, "on off balance");
        let binary = output_midi_object(midiobj);
        assert!(binary.len() >= 22, "MIDI output too short");
        assert!(*binary.get(0).unwrap().unbox() == 0x4D, "MThd");
    }

    /// Stepwise C Lydian cantus (C5→C4) with harmony generated **below**, biased to
    /// contrary motion. Two channels, quarter notes (~8 s @ 120 BPM).
    ///
    /// Export: `scarb test -- --filter counterpoint_contrary_two_voice_midi_test`
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn counterpoint_contrary_two_voice_midi_test() {
        let cantus = array![60_u8, 64, 67, 72, 67, 64, 60, 55];
        let strong_contrary = koji::composition::counterpoint::MotionBias {
            parallel: 5, contrary: 95, oblique: 15,
        };
        let params = c_lydian_counterpoint_demo_params_placed(
            101,
            cantus.len().try_into().unwrap(),
            strong_contrary,
            VoicePlacement::AboveCantus(()),
        );
        let result = generate_counterpoint(cantus.span(), params);
        assert!(result.contrary_count + result.oblique_count >= 3, "motion variety");
        assert!(result.contrary_count >= result.parallel_count, "contrary favored");
        let mut vi: usize = 0;
        loop {
            if vi >= cantus.len() {
                break;
            }
            assert(
                !violates_forbidden_interval(*result.counter.at(vi), *cantus.at(vi)),
                'no seconds',
            );
            vi += 1;
        };

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        append_two_voice_counterpoint_demo(
            ref eventlist, cantus.span(), result.counter.span(), 500000, 450000,
        );

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, 16);
    }

    /// Append a long ornamented melodic canon (Montanos "divided" style) to a MIDI event list.
    fn pow2_u256(p: u32) -> u256 {
        let mut r: u256 = 1;
        let mut i: u32 = 0;
        loop {
            if i >= p {
                break;
            }
            r *= 2;
            i += 1;
        };
        r
    }

    fn extract_seed_bits(s: u256, shift: u32, width: u32) -> u32 {
        let v = (s / pow2_u256(shift)) % pow2_u256(width);
        v.try_into().unwrap()
    }

    /// Ornament RNG sub-seed — same bit layout as `plan_ornament_subdivisions` in
    /// `generate_ornamented_canon`, so v1 and v2 demos share comparable entropy from one seed.
    fn v2_ornament_seed_from_canon_seed(seed: felt252) -> felt252 {
        let s: u256 = seed.into();
        let mut orn = extract_seed_bits(s, 51, 8) % 256;
        if orn == 0 {
            orn = 19;
        }
        orn.into()
    }

    /// Long canon with v2 typed-ornament engine (canon-first, per-voice elaboration).
    /// Structural frame matches `generate_melodic_canon_with_params`; surface comes from
    /// `ornamentation_v2` rule selection instead of Montanos subdivisions.
    fn append_long_v2_ornamented_canon(
        ref eventlist: Array<Message>,
        seed: felt252,
        config_id: u32,
        length: u32,
        step_us: u64,
        num_loops: u32,
    ) -> u32 {
        let canon = generate_melodic_canon_with_params(seed, config_id, length);
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut harmony: Array<HarmonyEvent> = ArrayTrait::new();
        let tonic_pc = canon.tonic_keynum % 12;
        harmony
            .append(
                HarmonyEvent {
                    root_pc: tonic_pc,
                    bass_pc: tonic_pc,
                    start: 0,
                    duration: cycle_ticks * num_loops * unit,
                    function_label: 0,
                },
            );

        let mut cfg = default_config(v2_ornament_seed_from_canon_seed(seed));
        cfg.style = profile_common_practice();
        cfg.canon_workflow = WORKFLOW_CANON_FIRST;
        let enabled = all_enabled_ornaments();
        let result = ornament_canon(@canon, harmony.span(), cfg, enabled.span());
        let events = result.events;
        let n = events.len();
        assert!(n > 0, "v2 ornamented canon events");

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let legacy = v2_note_to_legacy(*events.at(i));
                let on: Time = base + legacy.time.into() * step_us;
                let off: Time = on + legacy.duration.into() * step_us;
                let channel: u8 = legacy.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, legacy.pitch, legacy.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        n * num_loops
    }

    fn append_long_ornamented_canon(
        ref eventlist: Array<Message>,
        seed: felt252,
        config_id: u32,
        length: u32,
        step_us: u64,
        num_loops: u32,
    ) -> u32 {
        let (canon, subs) = generate_ornamented_canon(seed, config_id, length);
        let events = canon_to_ornamented_note_events(@canon, subs.span());
        let n = events.len();
        assert!(n > 0, "ornamented canon events");
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        n * num_loops
    }

    /// Append a long ornamented entry-lag canon (custom follower entry delays).
    fn append_long_entry_lag_ornamented_canon(
        ref eventlist: Array<Message>,
        seed: felt252,
        config: EntryLagCanonConfig,
        length: u32,
        step_us: u64,
        num_loops: u32,
    ) -> u32 {
        let (canon, subs) = generate_entry_lag_ornamented_canon(seed, config, length);
        let events = canon_to_ornamented_note_events(@canon, subs.span());
        let n = events.len();
        assert!(n > 0, "entry-lag ornamented events");
        let unit = canon.time_unit;
        let cycle_ticks = canon_texture_span(@canon) * unit;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        n * num_loops
    }

    /// Long ornamented canon with offset-sine tempo rubato: leader structural beats define the
    /// wave; followers inherit the same scale factor at each imitated position.
    fn append_long_ornamented_canon_with_sine_tempo(
        ref eventlist: Array<Message>,
        seed: felt252,
        config_id: u32,
        length: u32,
        step_us: u64,
        num_loops: u32,
        wave_frequency: u32,
    ) -> u32 {
        let (canon, subs) = generate_ornamented_canon(seed, config_id, length);
        let events = canon_to_ornamented_note_events(@canon, subs.span());
        let n = events.len();
        assert!(n > 0, "ornamented canon events");
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let span = len + nv - 1;
        let wave = long_sequence_timing_wave_freq(span, wave_frequency);
        let scaled_events = remap_events_with_timing_wave(
            events.span(), wave.span(), unit, canon.voices,
        );
        let scaled_n = scaled_events.len();
        assert!(scaled_n > 0, "scaled ornamented events");
        let cycle_ticks = textured_span_ticks(wave.span(), unit, span);

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= scaled_n {
                    break;
                }
                let e = *scaled_events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        scaled_n * num_loops
    }

    /// Renaissance improvised canon (Schubert / Cumming): a seeded melodic canon rendered to
    /// MIDI. Each voice on its own channel; the leader is steered to a cadence on the modal final.
    /// Config index in the seed's low nibble selects the canon type (1 = fifth below).
    ///
    /// Export: `scarb test -- --filter renaissance_canon_fifth_below_midi_test`
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn renaissance_canon_fifth_below_midi_test() {
        let seed: felt252 = 0x80000 + 1; // config 1 = fifth below
        let canon = generate_melodic_canon(seed);
        let events = canon_to_note_events(@canon);
        let n = events.len();
        assert!(n > 0, "canon produced events");

        let step_us: u64 = 400000;
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n);
    }

    /// Three-voice improvised canon (leader, fifth below, octave above that) rendered to MIDI.
    ///
    /// Export: `scarb test -- --filter renaissance_canon_three_voice_midi_test`
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn renaissance_canon_three_voice_midi_test() {
        let seed: felt252 = 0x80000 + 4; // config 4 = three-voice (5th below + octave)
        let canon = generate_melodic_canon(seed);
        assert!(canon.voices.len() == 3, "three voices");
        let events = canon_to_note_events(@canon);
        let n = events.len();

        let step_us: u64 = 400000;
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n);
    }

    fn render_baroque_seed_midi(seed: felt252, step_us: u64) -> u32 {
        let real = generate_baroque_cadential_improvisation(seed);
        assert!(validate_baroque_realization(@real), "baroque valid");
        let events = baroque_to_note_events(@real);
        let n = events.len();
        assert!(n > 0, "baroque produced events");

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n);
        n
    }

    fn baroque_soft_velocity(v: u8) -> u8 {
        let vu: u32 = v.into();
        if vu > 14 {
            (vu - 12).try_into().unwrap()
        } else {
            v
        }
    }

    fn baroque_neighbor_pitch(pitch: u8, index: u32) -> u8 {
        let p: u32 = pitch.into();
        if index % 4 == 0 && p < 104 {
            (p + 2).try_into().unwrap()
        } else if p > 36 {
            (p - 1).try_into().unwrap()
        } else {
            pitch
        }
    }

    fn append_baroque_demo_event(
        ref eventlist: Array<Message>,
        e: NoteEvent,
        section_base: Time,
        step_us: u64,
        ornament_rate: u32,
        event_index: u32,
    ) -> u32 {
        let on: Time = section_base + e.time.into() * step_us;
        let dur_us: Time = e.duration.into() * step_us;
        let off: Time = on + dur_us;
        let channel: u8 = e.voice_id.try_into().unwrap();

        if e.voice_id == 0 && e.duration >= 4 && ornament_rate > 0
            && event_index % ornament_rate == 0 {
            let mid: Time = on + dur_us / 2;
            let orn = baroque_neighbor_pitch(e.pitch, event_index);
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, mid);
            append_legato_note(
                ref eventlist, channel, orn, baroque_soft_velocity(e.velocity), mid, off,
            );
            2
        } else {
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
            1
        }
    }

    fn append_baroque_seed_section_with_transforms(
        ref eventlist: Array<Message>,
        seed: felt252,
        ref section_base: Time,
        step_us: u64,
        ornament_rate: u32,
    ) -> u32 {
        let real = generate_baroque_cadential_improvisation_with_transforms(seed);
        assert!(validate_baroque_realization(@real), "baroque transforms valid");
        let events = baroque_to_note_events(@real);
        let n = events.len();
        assert!(n > 0, "baroque transform events");

        let mut emitted: u32 = 0;
        let mut max_tick: u32 = 0;
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let event_end = e.time + e.duration;
            if event_end > max_tick {
                max_tick = event_end;
            }
            emitted += append_baroque_demo_event(
                ref eventlist, e, section_base, step_us, ornament_rate, i,
            );
            i += 1;
        };

        section_base += (max_tick.into() + 2) * step_us;
        emitted
    }

    fn append_baroque_seed_section(
        ref eventlist: Array<Message>,
        seed: felt252,
        ref section_base: Time,
        step_us: u64,
        ornament_rate: u32,
    ) -> u32 {
        let real = generate_baroque_cadential_improvisation(seed);
        assert!(validate_baroque_realization(@real), "baroque valid");
        let events = baroque_to_note_events(@real);
        let n = events.len();
        assert!(n > 0, "baroque events");

        let mut emitted: u32 = 0;
        let mut max_tick: u32 = 0;
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let event_end = e.time + e.duration;
            if event_end > max_tick {
                max_tick = event_end;
            }
            emitted += append_baroque_demo_event(
                ref eventlist, e, section_base, step_us, ornament_rate, i,
            );
            i += 1;
        };

        section_base += (max_tick.into() + 2) * step_us;
        emitted
    }

    fn render_long_baroque_suite(seeds: Span<felt252>, step_us: u64, ornament_rate: u32) -> u32 {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut note_ons: u32 = 0;
        let mut section_base: Time = 0;
        let mut i: u32 = 0;
        loop {
            if i >= seeds.len() {
                break;
            }
            note_ons += append_baroque_seed_section(
                ref eventlist, *seeds.at(i), ref section_base, step_us, ornament_rate,
            );
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
        note_ons
    }

    /// Seeded Baroque cadential improvisation: schema melody, Romanesca, cadenza doppia, and
    /// French long-five closure rendered through the same NoteEvent -> MIDI path as the canons.
    ///
    /// Export: `scarb test -- --filter baroque_cadential_improvisation_midi_test`
    #[ignore]
    #[test]
    #[available_gas(3000000000000)]
    fn baroque_cadential_improvisation_midi_test() {
        let n = render_baroque_seed_midi(2, 260000); // modular etude family
        assert!(n > 20, "baroque full etude");
    }

    /// Compact French/brise realization of the 3-4-5-1 cadence family.
    ///
    /// Export: `scarb test -- --filter baroque_cadence_3451_brise_midi_test`
    #[ignore]
    #[test]
    #[available_gas(3000000000000)]
    fn baroque_cadence_3451_brise_midi_test() {
        let real = generate_baroque_cadential_improvisation(32); // family 0, French long-five
        assert!(*real.plan.modules.at(0) == MODULE_CADENCE_FRENCH_LONG5, "french module");
        let n = render_baroque_seed_midi(32, 280000);
        assert!(n > real.bass.len(), "brise additions");
    }

    /// Fauxbourdon 7-6 suspension chain into a French long-five close.
    ///
    /// Export: `scarb test -- --filter baroque_fauxbourdon_76_long5_midi_test`
    #[ignore]
    #[test]
    #[available_gas(3000000000000)]
    fn baroque_fauxbourdon_76_long5_midi_test() {
        let real = generate_baroque_cadential_improvisation(1); // family 1, fauxbourdon
        assert!(*real.plan.modules.at(0) == MODULE_FAUXBOURDON_76, "fauxbourdon module");
        assert!(*real.plan.modules.at(1) == MODULE_CADENCE_FRENCH_LONG5, "long five close");
        let n = render_baroque_seed_midi(1, 260000);
        assert!(n > 20, "fauxbourdon events");
    }

    /// Romanesca chain, cadenza doppia modulation to V, transposed repeat, and closing cadence.
    ///
    /// Export: `scarb test -- --filter baroque_romanesca_cadenza_doppia_midi_test`
    #[ignore]
    #[test]
    #[available_gas(3000000000000)]
    fn baroque_romanesca_cadenza_doppia_midi_test() {
        let real = generate_baroque_cadential_improvisation(2); // modular etude
        assert!(*real.plan.modules.at(0) == MODULE_ROMANESCA, "romanesca module");
        assert!(*real.plan.modules.at(1) == MODULE_CADENZA_DOPPIA, "doppia module");
        let n = render_baroque_seed_midi(2, 260000);
        assert!(n > 40, "romanesca doppia events");
    }

    /// Natural-minor and harmonic-minor scalar closures over the descending 3-4-5-1 cadence.
    ///
    /// Export: `scarb test -- --filter baroque_descending_scales_minor_midi_test`
    #[ignore]
    #[test]
    #[available_gas(3000000000000)]
    fn baroque_descending_scales_minor_midi_test() {
        let natural = generate_baroque_cadential_improvisation(48); // natural minor, desc 3451
        let harmonic = generate_baroque_cadential_improvisation(1072); // harmonic minor, desc 3451
        assert!(*natural.plan.modules.at(0) == MODULE_CADENCE_DESC_3451, "natural desc");
        assert!(*harmonic.plan.modules.at(0) == MODULE_CADENCE_DESC_3451, "harmonic desc");
        let n1 = render_baroque_seed_midi(48, 300000);
        let n2 = render_baroque_seed_midi(1072, 300000);
        assert!(n1 > 0 && n2 > 0, "minor scalar events");
    }

    /// Mixed module tour with transform-developed scaffold passing tones + moderate ornaments.
    /// Cadence modules unchanged; upper voice gets stepwise filler from `develop_scaffold_melody`.
    ///
    /// Export: `scarb test -- --filter baroque_melody_transform_cadence_tour_midi_test`
    #[ignore]
    #[test]
    #[available_gas(9000000000000)]
    fn baroque_melody_transform_cadence_tour_midi_test() {
        let seeds = array![32, 1, 17, 49, 48, 1072, 2, 33, 64, 16, 1, 2];
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut note_ons: u32 = 0;
        let mut section_base: Time = 0;
        let mut i: u32 = 0;
        loop {
            if i >= seeds.len() {
                break;
            }
            note_ons += append_baroque_seed_section_with_transforms(
                ref eventlist, *seeds.at(i), ref section_base, 240000, 3,
            );
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
        assert!(note_ons > 280, "melody transform tour");
    }

    /// Long mixed Baroque module tour, moderately ornamented:
    /// French/brise cadence, fauxbourdon 7-6, circle/ascending fifths, scalar minor cadences,
    /// Romanesca, and cadenza doppia. Around a minute at 120 BPM.
    ///
    /// Export: `scarb test -- --filter baroque_long_moderate_ornament_showcase_midi_test`
    #[ignore]
    #[test]
    #[available_gas(9000000000000)]
    fn baroque_long_moderate_ornament_showcase_midi_test() {
        let seeds = array![32, 1, 17, 49, 48, 1072, 2, 33, 64, 16, 1, 2];
        let n = render_long_baroque_suite(seeds.span(), 240000, 3);
        assert!(n > 260, "long baroque showcase");
    }

    /// Long sequence/modulation study: chains fauxbourdon, circle-of-fifths, ascending fifths,
    /// Romanesca, and multiple cadenza doppia phrases to feature the new local-key handling.
    ///
    /// Export: `scarb test -- --filter baroque_long_sequence_modulation_midi_test`
    #[ignore]
    #[test]
    #[available_gas(9000000000000)]
    fn baroque_long_sequence_modulation_midi_test() {
        let seeds = array![1, 17, 33, 49, 2, 33, 2, 49, 17, 1, 2, 32];
        let n = render_long_baroque_suite(seeds.span(), 230000, 4);
        assert!(n > 300, "long sequence modulation");
    }

    /// Long minor scalar cadence suite: alternates natural/harmonic minor and 3-4-5-1 /
    /// 4-2-5-1 scalar descents with moderate upper-line diminutions (~2 min @ 120 BPM).
    ///
    /// Export: `scarb test -- --filter baroque_long_minor_scalar_cadences_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn baroque_long_minor_scalar_cadences_midi_test() {
        let seeds = array![
            48, 1072, 64, 1088, 16, 1040, 48, 1072, 64, 1088, 32, 0, 48, 1072, 64, 1088, 16,
            1040, 48, 1072, 64, 1088, 32, 0, 48, 1072, 64, 1088, 16, 1040, 48, 1072, 64, 1088,
            32, 0,
        ];
        let n = render_long_baroque_suite(seeds.span(), 240000, 3);
        assert!(n > 500, "long minor scalar cadences");
    }

    /// Long cadential study: 4-3, 3-4-5-1 brise, French long-five, and scalar descents
    /// with moderate neighbor-tone diminutions on the upper voice.
    ///
    /// Export: `scarb test -- --filter baroque_long_cadential_brise_midi_test`
    #[ignore]
    #[test]
    #[available_gas(9000000000000)]
    fn baroque_long_cadential_brise_midi_test() {
        let seeds = array![
            0, 16, 32, 48, 64, 0, 16, 32, 48, 64, 32, 16, 0, 32, 0, 16, 32, 48, 64, 32, 16, 0,
            16, 32, 48, 64, 0, 16, 32,
        ];
        let n = render_long_baroque_suite(seeds.span(), 240000, 3);
        assert!(n > 300, "long cadential brise");
    }

    /// Long two-voice canon at the fifth below with passing-tone / division ornamentation.
    /// 40 structural notes × 2 loops ≈ 80 s @ 120 BPM.
    ///
    /// Export: `scarb test -- --filter renaissance_canon_long_2voice_ornamented_midi_test`
    #[ignore]
    #[test]
    #[available_gas(4000000000000)]
    fn renaissance_canon_long_2voice_ornamented_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_ornamented_canon(
            ref eventlist, 4242, 1, 40, 250000, 2,
        );
        assert!(note_ons >= 120, "long 2-voice ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// Long three-voice canon (5th below + octave stack) with ornamentation, 2 loops.
    ///
    /// Export: `scarb test -- --filter renaissance_canon_long_3voice_ornamented_midi_test`
    #[ignore]
    #[test]
    #[available_gas(4000000000000)]
    fn renaissance_canon_long_3voice_ornamented_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_ornamented_canon(
            ref eventlist, 4343, 4, 36, 250000, 2,
        );
        assert!(note_ons >= 180, "long 3-voice ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// Same structural canon as `renaissance_canon_long_3voice_ornamented_midi_test` (seed 4343,
    /// config 4 = three-voice 5th-below + octave stack, length 36, 2 loops) but surface
    /// elaboration uses the v2 typed-ornament engine (passing, neighbors, suspensions, turns,
    /// etc.) with common-practice weighting instead of Montanos subdivision plans.
    ///
    /// Export: `scarb test -f renaissance_canon_long_3voice_v2_ornamented_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn renaissance_canon_long_3voice_v2_ornamented_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_v2_ornamented_canon(
            ref eventlist, 4343, 4, 36, 250000, 2,
        );
        assert!(note_ons >= 180, "long 3-voice v2 ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// Same canon as `renaissance_canon_long_3voice_ornamented_midi_test` with offset-sine tempo
    /// rubato at **4 cycles** over the structural span (leader scale propagated to followers).
    ///
    /// Export: `scarb test -f renaissance_canon_long_3voice_ornamented_sine_tempo_midi_test`
    #[ignore]
    #[test]
    #[available_gas(5000000000000)]
    fn renaissance_canon_long_3voice_ornamented_sine_tempo_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_ornamented_canon_with_sine_tempo(
            ref eventlist, 4343, 4, 36, 250000, 2, 4,
        );
        assert!(note_ons >= 180, "long 3-voice ornamented sine tempo");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// Long three-voice canon (5th below + octave stack) with two-note entry spacing between
    /// voices and Montanos-style ornamentation, 2 loops.
    ///
    /// Export: `scarb test -- --filter renaissance_canon_long_3voice_lag2_ornamented_midi_test`
    #[ignore]
    #[test]
    #[available_gas(4000000000000)]
    fn renaissance_canon_long_3voice_lag2_ornamented_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_entry_lag_ornamented_canon(
            ref eventlist,
            4343,
            config_three_voice_5b_8va_lag2(),
            36,
            250000,
            2,
        );
        assert!(note_ons >= 180, "long 3-voice lag2 ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// Sin modal run — single voice. Pitch follows offset sin; timing is symmetric at extrema.
    ///
    /// Export: `scarb test -f modal_run_sine_contour_midi_test`
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn modal_run_sine_contour_midi_test() {
        let contour = modal_contour_wave();
        let tonic = PitchClass { note: 0_u8, octave: 4_u8 };
        let steps = dorian_steps();
        let min_us: u64 = 150_000;
        let max_us: u64 = 450_000;
        let schedule = build_modal_run_schedule(contour.span(), min_us, max_us, MODAL_CONTOUR_LEN);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let n = append_modal_run_voice(
            ref eventlist,
            0,
            contour.span(),
            schedule.span(),
            0,
            tonic,
            steps,
            0,
            min_us,
            max_us,
        );
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n);
    }

    /// Three-voice canon of the sin modal run: same contour on every voice, staggered entries.
    ///
    /// Export: `scarb test -f renaissance_canon_modal_run_sine_contour_midi_test`
    #[ignore]
    #[test]
    #[available_gas(4000000000000)]
    fn renaissance_canon_modal_run_sine_contour_midi_test() {
        let contour = modal_contour_wave();
        let n = contour.len();
        let entry_gap: u32 = 10;
        let num_voices: u32 = 3;
        let total_slots = (num_voices - 1) * entry_gap + n;
        let tonic = PitchClass { note: 0_u8, octave: 4_u8 };
        let steps = dorian_steps();
        let min_us: u64 = 150_000;
        let max_us: u64 = 450_000;
        let schedule = build_modal_run_schedule(contour.span(), min_us, max_us, total_slots);

        let mut offsets: Array<i32> = ArrayTrait::new();
        offsets.append(0);
        offsets.append(-4);
        offsets.append(3);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut vi: u32 = 0;
        let mut note_ons: u32 = 0;
        loop {
            if vi >= num_voices {
                break;
            }
            let start_slot = vi * entry_gap;
            note_ons += append_modal_run_voice(
                ref eventlist,
                vi.try_into().unwrap(),
                contour.span(),
                schedule.span(),
                start_slot,
                tonic,
                steps,
                *offsets.at(vi),
                min_us,
                max_us,
            );
            vi += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// Long four-voice stacked-fifth-below canon with ornamentation, 2 loops.
    ///
    /// Export: `scarb test -- --filter renaissance_canon_long_4voice_ornamented_midi_test`
    #[ignore]
    #[test]
    #[available_gas(5000000000000)]
    fn renaissance_canon_long_4voice_ornamented_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_ornamented_canon(
            ref eventlist, 4444, 6, 32, 250000, 2,
        );
        assert!(note_ons >= 200, "long 4-voice ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    // ──────────────────────────────────────────────────────────
    // Extended-harmony aesthetic profiles — long, heavily-ornamented 4-voice canons.
    // See docs/extended_harmony_canon_spec.md. Each is correct (clash-free) by construction under
    // its profile; renders to MIDI exactly like the Renaissance long-canon demos.
    // ──────────────────────────────────────────────────────────

    /// Append a long ornamented canon under any *profiled* config (jazz / quartal / planing /
    /// Hindemith). Mirrors `append_long_ornamented_canon` but routes through the profile-aware
    /// generator so chromatic (mod-12) realization and per-profile alphabets are used.
    fn append_long_profiled_canon(
        ref eventlist: Array<Message>,
        seed: felt252,
        config_id: u32,
        length: u32,
        step_us: u64,
        num_loops: u32,
    ) -> u32 {
        let (canon, subs) = generate_profiled_ornamented_canon(seed, config_id, length);
        let events = canon_to_ornamented_note_events(@canon, subs.span());
        let n = events.len();
        assert!(n > 0, "profiled canon events");
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        n * num_loops
    }

    /// Quantize MIDI pitch to nearest pitch in a 7-note mode (pc set), preferring downward ties.
    fn quantize_to_mode_pitch(pitch: u8, mode_pcs: Span<u8>) -> u8 {
        let p: i32 = pitch.into();
        let pc: i32 = (p % 12 + 12) % 12;
        let mut best: i32 = p;
        let mut best_dist: i32 = 127;
        let mut i: u32 = 0;
        loop {
            if i >= mode_pcs.len() {
                break;
            }
            let tgt: i32 = (*mode_pcs.at(i)).into();
            let mut diff = tgt - pc;
            if diff > 6 {
                diff -= 12;
            } else if diff < -6 {
                diff += 12;
            }
            let adiff = if diff < 0 { -diff } else { diff };
            if adiff < best_dist || (adiff == best_dist && diff <= 0) {
                best_dist = adiff;
                best = p + diff;
            }
            i += 1;
        };
        if best < 0 {
            0
        } else if best > 127 {
            127
        } else {
            best.try_into().unwrap()
        }
    }

    /// Append a long ornamented profiled canon, then modal-quantize pitches so the melody is less
    /// chromatic while preserving the dense subdivision rhythm and voice layout.
    fn append_long_profiled_canon_modal(
        ref eventlist: Array<Message>,
        seed: felt252,
        config_id: u32,
        length: u32,
        step_us: u64,
        num_loops: u32,
        mode_pcs: Span<u8>,
    ) -> u32 {
        let (canon, subs) = generate_profiled_ornamented_canon(seed, config_id, length);
        let events = canon_to_ornamented_note_events(@canon, subs.span());
        let n = events.len();
        assert!(n > 0, "profiled modal canon events");
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                let qp = quantize_to_mode_pitch(e.pitch, mode_pcs);
                append_legato_note(ref eventlist, channel, qp, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        n * num_loops
    }

    /// JAZZ — four-voice stacked real canon spelling a moving **major-seventh chord** ([0,4,7,11]
    /// semitones), heavily ornamented. Major 7ths sound as color; no m2/m9 clash by construction.
    ///
    /// Export: `scarb test -- --filter extended_canon_jazz_maj7_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(6000000000000)]
    fn extended_canon_jazz_maj7_long_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_profiled_canon(ref eventlist, 70077, 7, 32, 250000, 2);
        assert!(note_ons >= 200, "long jazz maj7 ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// QUARTAL (Persichetti) — four-voice stacked-fourths canon ([0,5,10,15] semitones), heavily
    /// ornamented. P4/P5 are the stable intervals; parallels are idiomatic.
    ///
    /// Export: `scarb test -- --filter extended_canon_quartal_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(6000000000000)]
    fn extended_canon_quartal_long_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_profiled_canon(ref eventlist, 110011, 11, 32, 250000, 2);
        assert!(note_ons >= 200, "long quartal ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// QUARTAL MODAL — another four-voice quartal canon with dense ornamentation, but pitches are
    /// snapped to Dorian pcs (0,2,3,5,7,9,10) to reduce chromatic surface motion.
    ///
    /// Export: `scarb test -- --filter extended_canon_quartal_modal_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(7000000000000)]
    fn extended_canon_quartal_modal_long_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let dorian_pcs = array![0_u8, 2, 3, 5, 7, 9, 10];
        let note_ons = append_long_profiled_canon_modal(
            ref eventlist, 220221, 11, 36, 250000, 2, dorian_pcs.span(),
        );
        assert!(note_ons >= 220, "long quartal modal ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// PLANING (Debussy / Ravel) — four-voice **dominant-seventh** shape moved in parallel
    /// ([0,4,7,10] semitones), heavily ornamented. Parallel perfects are the idiom here.
    ///
    /// Export: `scarb test -- --filter extended_canon_planing_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(6000000000000)]
    fn extended_canon_planing_long_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_profiled_canon(ref eventlist, 90099, 9, 32, 250000, 2);
        assert!(note_ons >= 200, "long planing ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// HINDEMITH — four-voice mixed-interval tension stack ([0,5,7,11] semitones: P4 + P5 + M7),
    /// heavily ornamented. Dissonance is graded (Series 2) but the half-step collision is gated.
    ///
    /// Export: `scarb test -- --filter extended_canon_hindemith_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(6000000000000)]
    fn extended_canon_hindemith_long_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_profiled_canon(ref eventlist, 120012, 12, 32, 250000, 2);
        assert!(note_ons >= 200, "long hindemith ornamented");
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
    }

    /// PARSIMONIOUS (Neo-Riemannian) — a long four-voice **seventh-chord progression** in which
    /// every voice moves by at most a whole step. Not a stretto canon (the progression engine), so
    /// the "ornamentation" here is the dense chord-to-chord parsimonious motion itself.
    ///
    /// Export: `scarb test -- --filter extended_parsimonious_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(6000000000000)]
    fn extended_parsimonious_long_midi_test() {
        let nchords: u32 = 48;
        let events = generate_parsimonious_progression(303033, nchords);
        assert!(voice_leading_smooth(events.span(), 2), "every voice moves <= 2 semitones");
        assert!(no_minor_ninth_in_chords(events.span()), "no m2/m9 within any chord");
        let n = events.len();
        assert!(n == nchords * 4, "four voices per chord");

        let step_us: u64 = 500000;
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
            i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n);
    }

    // ── LCG parsimonious chord-progression showcase (`generate_parsimonious_progression`) ──

    /// Export raw LCG-walked seventh-chord progression to MIDI (block voicings, 4 parts).
    fn export_lcg_parsimonious_chord_passage_midi(
        seed: felt252,
        nchords: u32,
        num_loops: u32,
        step_us: u64,
        ornamented: bool,
    ) -> u32 {
        let events = if ornamented {
            generate_ornamented_parsimonious_progression(seed, nchords)
        } else {
            generate_parsimonious_progression(seed, nchords)
        };
        if !ornamented {
            assert(voice_leading_smooth(events.span(), 2), 'lcg voice smooth');
            assert(no_minor_ninth_in_chords(events.span()), 'lcg no m9');
            assert(events.len() == nchords * 4, 'lcg four voices');
        }
        let n = events.len();
        assert(n > 0, 'lcg chord events');
        let cycle_ticks: u64 = (nchords * 4).into() * step_us;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut total: u32 = 0;
        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                total += 1;
                i += 1;
            };
            loop_i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, total);
        total
    }

    /// Single uninterrupted LCG chord walk — 256 parsimonious seventh chords (~14 min).
    ///
    /// Export: `scarb test -- --filter lcg_parsimonious_chord_passage_raw_epic_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn lcg_parsimonious_chord_passage_raw_epic_midi_test() {
        let n = export_lcg_parsimonious_chord_passage_midi(20260209, 256, 1, 650000, false);
        assert(n == 256 * 4, 'lcg epic raw notes');
    }

    /// Two full cycles of the same seed — hear the deterministic LCG period return.
    ///
    /// Export: `scarb test -- --filter lcg_parsimonious_chord_passage_raw_double_cycle_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn lcg_parsimonious_chord_passage_raw_double_cycle_midi_test() {
        let n = export_lcg_parsimonious_chord_passage_midi(424242, 128, 2, 600000, false);
        assert(n == 128 * 4 * 2, 'lcg double cycle');
    }

    /// Five consecutive LCG streams (different seeds) — raw capability tour.
    ///
    /// Export: `scarb test -- --filter lcg_parsimonious_chord_showcase_multi_seed_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn lcg_parsimonious_chord_showcase_multi_seed_midi_test() {
        let nchords: u32 = 72;
        let step_us: u64 = 550000;
        let section_gap_us: u64 = 800000;
        let cycle_ticks: u64 = (nchords * 4).into() * step_us;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut cursor: Time = 0;
        let mut total: u32 = 0;
        let mut section: u32 = 0;
        loop {
            if section >= 5 {
                break;
            }
            let seed: felt252 = if section == 0 {
                42
            } else if section == 1 {
                137
            } else if section == 2 {
                2026
            } else if section == 3 {
                90909
            } else {
                420420
            };
            let events = generate_parsimonious_progression(seed, nchords);
            assert(voice_leading_smooth(events.span(), 2), 'suite smooth');
            let n = events.len();
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = cursor + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                total += 1;
                i += 1;
            };
            cursor = cursor + cycle_ticks + section_gap_us;
            section += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, total);
        assert(total == 5 * nchords * 4, 'lcg suite notes');
    }

    /// Ornamented LCG chord walk — structural progression unchanged, dense passing/neighbor motion.
    ///
    /// Export: `scarb test -- --filter lcg_parsimonious_chord_passage_ornate_epic_midi_test`
    #[ignore]
    #[test]
    #[available_gas(14000000000000)]
    fn lcg_parsimonious_chord_passage_ornate_epic_midi_test() {
        let n = export_lcg_parsimonious_chord_passage_midi(717171, 160, 2, 480000, true);
        assert(n > 160 * 4 * 2, 'lcg ornate epic');
    }

    /// MIN-MOTION PLR, ORNAMENTED — seeded PLR random-walk harmony + conjunct pinned soprano,
    /// minimal-motion inner voices, stepwise ornaments and variable beat lengths (3–5 ticks).
    ///
    /// Export: `scarb test -- --filter min_motion_plr_ornamented_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn min_motion_plr_ornamented_long_midi_test() {
        let seed: felt252 = 808080;
        let nbeats: u32 = 56;
        let num_loops: u32 = 2;
        let events = generate_ornamented_min_motion_progression(seed, nbeats);
        let n = events.len();
        assert!(n > nbeats * 2, "ornamented adds subdivisions");

        let step_us: u64 = 500000;
        let cycle_ticks: u64 = ornamented_min_motion_cycle_ticks(seed, nbeats).into() * step_us;
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut total_notes: u32 = 0;
        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                total_notes += 1;
                i += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, total_notes);
    }

    /// PARSIMONIOUS, ORNAMENTED — same parsimonious seventh-chord engine as
    /// `extended_parsimonious_long`, but a different seed and each chord tone **subdivided** into
    /// 2–4 decorated notes per voice (neighbor / passing ornamentation). Dense, lots of motion;
    /// the strong-beat reduction is still the smooth ≤2-semitone progression.
    ///
    /// Export: `scarb test -- --filter extended_parsimonious_ornamented_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn extended_parsimonious_ornamented_long_midi_test() {
        let nchords: u32 = 48;
        let events = generate_ornamented_parsimonious_progression(717171, nchords);
        let n = events.len();
        assert!(n > nchords * 4, "ornamented adds subdivisions");

        let step_us: u64 = 500000;
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
            i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n);
    }

    /// Same cantus as the contrary demo but with parallel motion bias (for A/B comparison).
    ///
    /// Export: `scarb test -- --filter counterpoint_parallel_two_voice_midi_test`
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn counterpoint_parallel_two_voice_midi_test() {
        let cantus = array![60_u8, 64, 67, 72, 67, 64, 60, 55];
        let strong_parallel = koji::composition::counterpoint::MotionBias {
            parallel: 95, contrary: 5, oblique: 15,
        };
        let params = c_lydian_counterpoint_demo_params_placed(
            202,
            cantus.len().try_into().unwrap(),
            strong_parallel,
            VoicePlacement::BelowCantus(()),
        );
        let result = generate_counterpoint(cantus.span(), params);
        assert!(result.parallel_count + result.oblique_count >= 3, "motion variety");
        assert!(result.parallel_count >= result.contrary_count, "parallel favored");

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        append_two_voice_counterpoint_demo(
            ref eventlist, cantus.span(), result.counter.span(), 500000, 450000,
        );

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, 16);
    }

    /// Balanced motion bias on a 4-voice hocket canon (seed 0, n=8) — cantus + 3
    /// counterpoint voices with pairwise scoring.
    ///
    /// Export: `scarb test -- --filter counterpoint_balanced_canon_demo_midi_test`
    #[ignore]
    #[test]
    #[available_gas(1500000000000)]
    fn counterpoint_balanced_canon_demo_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 225000;
        let num_loops: u32 = 4;
        let canon = generate_rhythmic_canon(0);
        let k = canon.rhythm_tile.len();
        let leaders = array![72_u8, 60_u8];
        let num_voices = count_tiling_voices(@canon);
        let params = c_lydian_counterpoint_demo_params(303, k, motion_bias_balanced());
        let plan = plan_canon_harmony(leaders.span(), @params, num_voices);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }));

        let n = canon.n;
        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            append_counterpoint_canon_cycle(
                ref eventlist,
                (loop_i * n).into() * step_us,
                step_us,
                n,
                canon.rhythm_tile,
                canon.durations,
                canon.voices,
                @plan,
            );
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, 32);
    }

    /// Four-voice syncopated canon (n=8 hocket) with **contrary-motion** counterpoint
    /// on voices 1–3 below/above the cantus leader.
    ///
    /// Export: `scarb test -- --filter counterpoint_contrary_canon_demo_midi_test`
    #[ignore]
    #[test]
    #[available_gas(1500000000000)]
    fn counterpoint_contrary_canon_demo_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 225000;
        let num_loops: u32 = 4;
        let canon = generate_rhythmic_canon(0);
        assert!(canon.n == 8, "n=8 hocket");
        assert!(canon.translations.len() == 4, "4 voices");
        let k = canon.rhythm_tile.len();
        let leaders = array![72_u8, 60_u8];
        let num_voices = count_tiling_voices(@canon);
        let params = c_lydian_counterpoint_demo_params(404, k, motion_bias_contrary());
        let plan = plan_canon_harmony(leaders.span(), @params, num_voices);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }));

        let n = canon.n;
        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            append_counterpoint_canon_cycle(
                ref eventlist,
                (loop_i * n).into() * step_us,
                step_us,
                n,
                canon.rhythm_tile,
                canon.durations,
                canon.voices,
                @plan,
            );
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, 32);
    }

    /// Long Ligeti-style banded canon MIDI export.
    ///
    /// Export: `scarb test -- --filter ligeti_banded_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(7000000000000)]
    fn ligeti_banded_long_midi_test() {
        let step_us: u64 = 150000;
        let num_loops: u32 = 10;
        let canon = generate_ligeti_banded_canon(20260602, 36);
        let events = canon_to_note_events(@canon);
        let n = events.len();
        assert!(n >= 120, "ligeti canon has enough events");

        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n * num_loops);
    }

    // ──────────────────────────────────────────────────────────
    // Complementary aesthetic profiles — long ornamented 3- and 4-voice canons.
    // Export each with:
    //   SCARB_UI_VERBOSITY=quiet scarb test -- --filter <test_name> 2>&1 \
    //     | grep -v "running\|test\|gas usage\|test result" > <name>_parser.cairo
    //   npx ts-node typescript/src/simpleMidiConverter.ts <name>_parser.cairo <name>.mid
    // ──────────────────────────────────────────────────────────

    fn export_long_profiled_canon_midi(
        seed: felt252,
        config_id: u32,
        length: u32,
        num_voices: u32,
        num_loops: u32,
        step_us: u64,
    ) -> u32 {
        let (canon, _) = generate_profiled_ornamented_canon(seed, config_id, length);
        assert(canon.voices.len() == num_voices, 'voices');
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let note_ons = append_long_profiled_canon(
            ref eventlist, seed, config_id, length, step_us, num_loops,
        );
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, note_ons);
        note_ons
    }

    /// Default long demo: 48 structural degrees, 4 looped cycles, ornamented leader.
    fn export_long_profiled_canon_midi_default(
        seed: felt252, config_id: u32, num_voices: u32,
    ) -> u32 {
        export_long_profiled_canon_midi(seed, config_id, 48, num_voices, 4, 220000)
    }

    /// Export: `scarb test -- --filter complementary_impr_add6_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_impr_add6_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(270617, 27, 4);
        assert!(n >= 400, "long impr add6 4v");
    }

    /// Export: `scarb test -- --filter complementary_impr_add6_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_impr_add6_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(270618, 32, 3);
        assert!(n >= 360, "long impr add6 3v");
    }

    /// Export: `scarb test -- --filter complementary_bitonal_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_bitonal_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(280628, 28, 4);
        assert!(n >= 400, "long bitonal 4v");
    }

    /// Export: `scarb test -- --filter complementary_bitonal_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_bitonal_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(280629, 33, 3);
        assert!(n >= 360, "long bitonal 3v");
    }

    /// Export: `scarb test -- --filter complementary_phrygian_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_phrygian_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(290639, 29, 4);
        assert!(n >= 400, "long phrygian 4v");
    }

    /// Export: `scarb test -- --filter complementary_phrygian_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_phrygian_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(290640, 34, 3);
        assert!(n >= 360, "long phrygian 3v");
    }

    /// Export: `scarb test -- --filter complementary_pentatonic_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_pentatonic_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(300640, 30, 4);
        assert!(n >= 400, "long pentatonic 4v");
    }

    /// Export: `scarb test -- --filter complementary_pentatonic_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_pentatonic_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(300641, 35, 3);
        assert!(n >= 360, "long pentatonic 3v");
    }

    /// Export: `scarb test -- --filter complementary_neo_riem_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_neo_riem_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(310631, 31, 3);
        assert!(n >= 360, "long neo riem 3v");
    }

    /// Export: `scarb test -- --filter complementary_neo_riem_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_neo_riem_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(310632, 36, 4);
        assert!(n >= 400, "long neo riem 4v");
    }

    /// Export: `scarb test -- --filter complementary_impr_smooth_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_impr_smooth_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(370637, 37, 4);
        assert!(n >= 200, "long impr smooth 4v");
    }

    /// Export: `scarb test -- --filter complementary_impr_smooth_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_impr_smooth_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(370638, 38, 3);
        assert!(n >= 180, "long impr smooth 3v");
    }

    /// Export: `scarb test -- --filter complementary_penta_smooth_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_penta_smooth_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(390639, 39, 4);
        assert!(n >= 200, "long penta smooth 4v");
    }

    /// Export: `scarb test -- --filter complementary_penta_smooth_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn complementary_penta_smooth_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(390640, 40, 3);
        assert!(n >= 180, "long penta smooth 3v");
    }

    /// Export: `scarb test -- --filter jazz_improv_long_4v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn jazz_improv_long_4v_midi_test() {
        let n = export_long_profiled_canon_midi_default(410641, 41, 4);
        assert!(n >= 200, "long jazz improv 4v");
    }

    /// Export: `scarb test -- --filter jazz_improv_long_3v_midi_test`
    #[ignore]
    #[test]
    #[available_gas(8000000000000)]
    fn jazz_improv_long_3v_midi_test() {
        let n = export_long_profiled_canon_midi_default(410642, 42, 3);
        assert!(n >= 180, "long jazz improv 3v");
    }

    // ── Alternate seeds (second demo per profile family) — 6 loops, denser ornament rhythm ──

    /// Export: `scarb test -- --filter profile_demo_impr_add6_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_impr_add6_alt_midi_test() {
        let n = export_long_profiled_canon_midi(171717, 27, 48, 4, 6, 180000);
        assert!(n >= 500, "impr add6 alt");
    }

    /// Export: `scarb test -- --filter profile_demo_bitonal_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_bitonal_alt_midi_test() {
        let n = export_long_profiled_canon_midi(181818, 28, 48, 4, 6, 180000);
        assert!(n >= 500, "bitonal alt");
    }

    /// Export: `scarb test -- --filter profile_demo_phrygian_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_phrygian_alt_midi_test() {
        let n = export_long_profiled_canon_midi(191919, 29, 48, 4, 6, 180000);
        assert!(n >= 500, "phrygian alt");
    }

    /// Export: `scarb test -- --filter profile_demo_pentatonic_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_pentatonic_alt_midi_test() {
        let n = export_long_profiled_canon_midi(202020, 30, 48, 4, 6, 180000);
        assert!(n >= 500, "pentatonic alt");
    }

    /// Export: `scarb test -- --filter profile_demo_neo_riem_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_neo_riem_alt_midi_test() {
        let n = export_long_profiled_canon_midi(212121, 31, 48, 3, 6, 180000);
        assert!(n >= 450, "neo riem alt 3v");
    }

    /// Export: `scarb test -- --filter profile_demo_impr_smooth_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_impr_smooth_alt_midi_test() {
        let n = export_long_profiled_canon_midi(232323, 37, 48, 4, 6, 200000);
        assert!(n >= 250, "impr smooth alt");
    }

    /// Export: `scarb test -- --filter profile_demo_penta_smooth_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_penta_smooth_alt_midi_test() {
        let n = export_long_profiled_canon_midi(242424, 39, 48, 4, 6, 200000);
        assert!(n >= 250, "penta smooth alt");
    }

    /// Export: `scarb test -- --filter profile_demo_jazz_improv_alt_midi_test`
    #[ignore]
    #[test]
    #[available_gas(10000000000000)]
    fn profile_demo_jazz_improv_alt_midi_test() {
        let n = export_long_profiled_canon_midi(252525, 41, 48, 4, 6, 200000);
        assert!(n >= 250, "jazz improv alt");
    }

    // ── Dense subdivision showcase (32 steps, fast pulse, 8 loops) ──

    /// Export: `scarb test -- --filter profile_demo_ornament_dense_impr_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn profile_demo_ornament_dense_impr_midi_test() {
        let n = export_long_profiled_canon_midi(333333, 27, 32, 4, 8, 120000);
        assert!(n >= 600, "dense impr");
    }

    /// Export: `scarb test -- --filter profile_demo_ornament_dense_phrygian_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn profile_demo_ornament_dense_phrygian_midi_test() {
        let n = export_long_profiled_canon_midi(444444, 29, 32, 4, 8, 120000);
        assert!(n >= 600, "dense phrygian");
    }

    /// Export: `scarb test -- --filter profile_demo_ornament_dense_bitonal_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn profile_demo_ornament_dense_bitonal_midi_test() {
        let n = export_long_profiled_canon_midi(555555, 28, 32, 4, 8, 120000);
        assert!(n >= 600, "dense bitonal");
    }

    /// Export: `scarb test -- --filter profile_demo_ornament_dense_jazz_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn profile_demo_ornament_dense_jazz_midi_test() {
        let n = export_long_profiled_canon_midi(666666, 41, 32, 4, 8, 120000);
        assert!(n >= 300, "dense jazz");
    }

    /// Long jazz-improv canon: turnaround harmony, no semitone structural steps, dense
    /// subdivisions with min-step ornament fill (not chromatic ±1 chains).
    ///
    /// Export: `scarb test -- --filter jazz_improv_ornamented_long_midi_test`
    fn export_jazz_improv_ornamented_long_midi(
        seed: felt252, config_id: u32, length: u32, num_voices: u32, num_loops: u32, step_us: u64,
    ) -> u32 {
        let (canon, subs) = generate_jazz_improv_ornamented_canon(seed, config_id, length);
        assert(canon.voices.len() == num_voices, 'voices');
        let events = canon_to_ornamented_note_events_with_fill(@canon, subs.span(), ORN_FILL_MIN_STEP);
        let n = events.len();
        assert(n > 0, 'jazz improv events');
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n * num_loops);
        n * num_loops
    }

    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn jazz_improv_ornamented_long_midi_test() {
        let n = export_jazz_improv_ornamented_long_midi(770707, 41, 48, 4, 6, 180000);
        assert(n >= 500, 'long jazz improv orn 4v');
    }

    /// Long jazz-improv with tritone-sub turnaround (harmony bits 27..30 ≡ 0 mod 5), light
    /// ornament subdivisions, min-step fill. Seed 770707 → Db7 region 3.
    ///
    /// Export: `scarb cairo-test -f jazz_improv_tritone_sub_light_long_midi_test`
    fn export_jazz_improv_tritone_sub_light_long_midi(
        seed: felt252, config_id: u32, length: u32, num_voices: u32, num_loops: u32, step_us: u64,
    ) -> u32 {
        let plan = turnaround_plan_from_canon_seed(seed);
        assert(turnaround_has_tritone_sub(plan), 'tritone sub plan');
        let (canon, subs) = generate_jazz_improv_ornamented_canon_light(seed, config_id, length);
        assert(canon.voices.len() == num_voices, 'voices');
        let events = canon_to_ornamented_note_events_with_fill(@canon, subs.span(), ORN_FILL_MIN_STEP);
        let n = events.len();
        assert(n > 0, 'jazz tritone events');
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n * num_loops);
        n * num_loops
    }

    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn jazz_improv_tritone_sub_light_long_midi_test() {
        // harmony_seed = extract_bits(770707, 27, 4) == 0 → Db7 tritone sub on region 3
        let n = export_jazz_improv_tritone_sub_light_long_midi(770707, 41, 48, 4, 6, 200000);
        assert(n >= 350, 'jazz tritone sub light long');
    }

    /// Harmonic-walk block harmony: minimal-motion allocation + dense beat ornaments, 3 loops.
    ///
    /// Export: `scarb test -- --filter harmonic_walk_min_motion_ornate_long_midi_test`
    fn export_harmonic_walk_min_motion_ornate_long_midi(
        seed: felt252, num_loops: u32, step_us: u64,
    ) -> u32 {
        let events = generate_ornamented_harmonic_walk_progression(seed);
        let n = events.len();
        assert(n > 0, 'hw events');
        let cycle_ticks = harmonic_walk_progression_cycle_ticks(seed);
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
        let mut total: u32 = 0;
        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                total += 1;
                i += 1;
            };
            loop_i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, total);
        total
    }

    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn harmonic_walk_min_motion_ornate_long_midi_test() {
        // sk=1 blues @16, rewrite_budget=6 @20, continuation_depth=2 @24, tag 4242 @0
        let seed: felt252 = 39915666;
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 12, 400000);
        assert(n >= 850, 'hw min motion ornate');
    }

    /// Blues-12 skeleton with rewrite budget 8 — substitution chain demo.
    ///
    /// Export: `scarb test -- --filter harmonic_walk_blues_rewrite_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn harmonic_walk_blues_rewrite_long_midi_test() {
        // sk=1 blues @16, rewrite_budget=8 @20, tag 5555 @0
        let seed: felt252 = 8459699;
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 12, 450000);
        assert(n >= 1000, 'hw blues rewrite');
    }

    /// Rhythm-changes skeleton + high surprise bias continuation overlay.
    ///
    /// Export: `scarb test -- --filter harmonic_walk_surprise_continuation_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn harmonic_walk_surprise_continuation_long_midi_test() {
        // sk=2 rhythm changes @16, depth=2 @24, surprise_bias=255 @28, tag 6666 @0
        let seed: felt252 = 68484733450;
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 18, 420000);
        assert(n >= 700, 'hw surprise cont');
    }

    /// Profile-24 jazz canon with harmonic-walk material gates, dense subdivisions, min-step fill.
    ///
    /// Export: `scarb test -- --filter jazz_improv_harmonic_walk_ornate_long_4v_midi_test`
    fn export_jazz_improv_harmonic_walk_ornamented_long_midi(
        seed: felt252, config_id: u32, length: u32, num_voices: u32, num_loops: u32, step_us: u64,
    ) -> u32 {
        let (canon, subs) = generate_jazz_improv_harmonic_walk_ornamented_canon(
            seed, config_id, length,
        );
        assert(canon.voices.len() == num_voices, 'voices');
        let events = canon_to_ornamented_note_events_with_fill(@canon, subs.span(), ORN_FILL_MIN_STEP);
        let n = events.len();
        assert(n > 0, 'jazz walk events');
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n * num_loops);
        n * num_loops
    }

    #[ignore]
    #[test]
    #[available_gas(16000000000000)]
    fn jazz_improv_harmonic_walk_ornate_long_4v_midi_test() {
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            881881, 41, 64, 4, 8, 160000,
        );
        assert(n >= 1200, 'jazz walk 4v ornate long');
    }

    #[ignore]
    #[test]
    #[available_gas(14000000000000)]
    fn jazz_improv_harmonic_walk_ornate_long_3v_midi_test() {
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            882882, 42, 64, 3, 8, 160000,
        );
        assert(n >= 900, 'jazz walk 3v ornate long');
    }

    #[ignore]
    #[test]
    #[available_gas(16000000000000)]
    fn jazz_improv_harmonic_walk_dense_ornate_midi_test() {
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            883883, 41, 48, 4, 10, 120000,
        );
        assert(n >= 1500, 'jazz walk dense ornate');
    }

    // ── Batch 2 — curated harmonic / melodic showcases (improved listening set) ──

    /// Export: `scarb test -- --filter hw_batch2_two_five_one_rewrite_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn hw_batch2_two_five_one_rewrite_midi_test() {
        let seed = harmonic_walk_demo_seed(3, 5, 1, 0, 2101);
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 32, 580000);
        assert(n >= 600, 'batch2 251 rewrite');
    }

    /// Export: `scarb test -- --filter hw_batch2_rhythm_changes_reharm_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn hw_batch2_rhythm_changes_reharm_midi_test() {
        let seed = harmonic_walk_demo_seed(2, 8, 0, 0, 2202);
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 14, 520000);
        assert(n >= 600, 'batch2 rc reharm');
    }

    /// Export: `scarb test -- --filter hw_batch2_turnaround_surprise_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn hw_batch2_turnaround_surprise_midi_test() {
        let seed = harmonic_walk_demo_seed(0, 2, 3, 200, 2303);
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 40, 560000);
        assert(n >= 700, 'batch2 turn surprise');
    }

    /// Export: `scarb test -- --filter hw_batch2_blues_surprise_colors_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn hw_batch2_blues_surprise_colors_midi_test() {
        let seed = harmonic_walk_demo_seed(1, 6, 2, 128, 2404);
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 14, 500000);
        assert(n >= 1000, 'batch2 blues surprise');
    }

    /// Export: `scarb test -- --filter hw_batch2_two_five_one_max_surprise_midi_test`
    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn hw_batch2_two_five_one_max_surprise_midi_test() {
        let seed = harmonic_walk_demo_seed(3, 1, 3, 255, 2505);
        let n = export_harmonic_walk_min_motion_ornate_long_midi(seed, 36, 540000);
        assert(n >= 800, 'batch2 251 max S');
    }

    /// Export: `scarb test -- --filter hw_batch2_jazz_canon_251_long_midi_test`
    #[ignore]
    #[test]
    #[available_gas(16000000000000)]
    fn hw_batch2_jazz_canon_251_long_midi_test() {
        // Short 251 timeline (3 slots): keep structural length moderate so the walk gate stays satisfiable.
        let seed = jazz_canon_walk_demo_seed(3, 3, 0, 20, 771001);
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            seed, 41, 40, 4, 16, 150000,
        );
        assert(n >= 1400, 'batch2 canon 251');
    }

    /// Export: `scarb test -- --filter hw_batch2_jazz_canon_rhythm_changes_midi_test`
    #[ignore]
    #[test]
    #[available_gas(18000000000000)]
    fn hw_batch2_jazz_canon_rhythm_changes_midi_test() {
        let seed = jazz_canon_walk_demo_seed(2, 5, 1, 60, 772002);
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            seed, 41, 72, 4, 10, 150000,
        );
        assert(n >= 1800, 'batch2 canon rc');
    }

    /// Export: `scarb test -- --filter hw_batch2_jazz_canon_blues_gospel_midi_test`
    #[ignore]
    #[test]
    #[available_gas(20000000000000)]
    fn hw_batch2_jazz_canon_blues_gospel_midi_test() {
        let seed = jazz_canon_walk_demo_seed(1, 5, 2, 90, 773003);
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            seed, 42, 80, 3, 10, 140000,
        );
        assert(n >= 2000, 'batch2 canon blues');
    }

    /// Export: `scarb test -- --filter hw_batch2_jazz_canon_turnaround_surprise_midi_test`
    #[ignore]
    #[test]
    #[available_gas(18000000000000)]
    fn hw_batch2_jazz_canon_turnaround_surprise_midi_test() {
        // Rhythm-changes timeline + surprise continuations (turnaround axiom is too coarse for long canon gates).
        let seed = jazz_canon_walk_demo_seed(2, 4, 2, 180, 774004);
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            seed, 41, 56, 4, 12, 130000,
        );
        assert(n >= 1800, 'batch2 canon rc surprise');
    }

    /// Export: `scarb test -- --filter hw_batch2_jazz_canon_hybrid_epic_midi_test`
    #[ignore]
    #[test]
    #[available_gas(22000000000000)]
    fn hw_batch2_jazz_canon_hybrid_epic_midi_test() {
        let seed = jazz_canon_walk_demo_seed(2, 6, 2, 100, 775005);
        let n = export_jazz_improv_harmonic_walk_ornamented_long_midi(
            seed, 41, 96, 4, 8, 135000,
        );
        assert(n >= 2400, 'batch2 canon epic');
    }

    /// Long pentatonic-smooth 4-voice canon: dense subdivisions + pentatonic material fill (not
    /// chromatic). Same stack as `penta_smooth_4v_long` (config 39) but rhythmically active.
    ///
    /// Export: `scarb test -f penta_smooth_ornamented_long_4v_midi_test`
    fn export_penta_smooth_ornamented_long_midi(
        seed: felt252, config_id: u32, length: u32, num_voices: u32, num_loops: u32, step_us: u64,
    ) -> u32 {
        let (canon, subs) = generate_pentatonic_smooth_ornamented_canon(seed, config_id, length);
        assert(canon.voices.len() == num_voices, 'voices');
        let events = canon_to_ornamented_note_events_with_fill(
            @canon, subs.span(), ORN_FILL_MATERIAL,
        );
        let n = events.len();
        assert(n > 0, 'penta smooth orn events');
        let len = canon.leader_degrees.len();
        let nv = canon.voices.len();
        let unit = canon.time_unit;
        let cycle_ticks = (len + nv - 1) * unit;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut loop_i: u32 = 0;
        loop {
            if loop_i >= num_loops {
                break;
            }
            let base: Time = loop_i.into() * cycle_ticks.into() * step_us;
            let mut i: u32 = 0;
            loop {
                if i >= n {
                    break;
                }
                let e = *events.at(i);
                let on: Time = base + e.time.into() * step_us;
                let off: Time = on + e.duration.into() * step_us;
                let channel: u8 = e.voice_id.try_into().unwrap();
                append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
                i += 1;
            };
            loop_i += 1;
        };
        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n * num_loops);
        n * num_loops
    }

    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn transform_pipeline_midi_test() {
        let mut pitch_ops = ArrayTrait::<PlaneOp>::new();
        pitch_ops.append(PlaneOp::Invert(4));
        pitch_ops.append(PlaneOp::Rotate(2));
        pitch_ops.append(PlaneOp::Repeat(2));
        let pitch_pipe = Pipeline { ops: pitch_ops };

        let mut len_ops = ArrayTrait::<PlaneOp>::new();
        len_ops.append(PlaneOp::Rotate(1));
        len_ops.append(PlaneOp::Augment(2));
        let len_pipe = Pipeline { ops: len_ops };

        let mut vel_table = ArrayTrait::<i32>::new();
        vel_table.append(110);
        vel_table.append(70);
        vel_table.append(70);
        vel_table.append(90);
        let mut vel_ops = ArrayTrait::<PlaneOp>::new();
        vel_ops.append(PlaneOp::MapByPosition(vel_table));
        let vel_pipe = Pipeline { ops: vel_ops };

        let obj = MusicalObject {
            pitches: array![0_i32, 2, 4, 5, 7],
            lengths: array![4_u32, 4, 2, 2, 4],
            velocities: array![100_u8, 80],
            articulations: array![0_u8],
            octave: 7,
        };

        let mut transformed = apply_to_object(obj, PlaneId::Pitch, @pitch_pipe);
        transformed = apply_to_object(transformed, PlaneId::Length, @len_pipe);
        transformed = apply_to_object(transformed, PlaneId::Velocity, @vel_pipe);
        let events = assemble(@transformed, 0, 60, 0);
        let n = events.len();
        assert!(n > 0, "transform pipeline events");

        let step_us: u64 = 400000;
        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));

        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            append_legato_note(ref eventlist, channel, e.pitch, e.velocity, on, off);
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert_valid_demo_midi(@midiobj, n);
    }

    #[ignore]
    #[test]
    #[available_gas(12000000000000)]
    fn penta_smooth_ornamented_long_4v_midi_test() {
        let n = export_penta_smooth_ornamented_long_midi(482639, 39, 48, 4, 6, 180000);
        assert(n >= 500, 'penta smooth orn 4v long');
    }

    /// Neutral percussion pitch per reference preset (verification artifact, not cultural claim).
    fn pitch_for_timeline_preset(preset_id: u8) -> u8 {
        48 + preset_id
    }

    fn append_timeline_section(
        ref eventlist: Array<Message>,
        rhythm: @TimelineRhythm,
        cycles: u32,
        channel: u8,
        pitch: u8,
        step_us: u64,
        ref cursor: Time,
    ) {
        let events = timeline_to_events(rhythm, cycles, channel.into(), 100);
        let mut i: u32 = 0;
        loop {
            if i >= events.len() {
                break;
            }
            let e = *events.at(i);
            let on: Time = cursor + e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            append_legato_note(ref eventlist, channel, pitch, e.velocity, on, off);
            i += 1;
        };
        cursor = cursor + (cycles * (*rhythm.n)).into() * step_us;
    }

    fn append_phrasing_accent_grid(
        ref eventlist: Array<Message>,
        rhythm: @TimelineRhythm,
        cycles: u32,
        channel: u8,
        pitch: u8,
        step_us: u64,
        ref cursor: Time,
    ) {
        let total_steps = cycles * (*rhythm.n);
        let mut t: u32 = 0;
        loop {
            if t >= total_steps {
                break;
            }
            let vel = timeline_accent(rhythm, t, 100, 38);
            let on: Time = cursor + t.into() * step_us;
            let off: Time = on + step_us - 1000;
            append_legato_note(ref eventlist, channel, pitch, vel, on, off);
            t += 1;
        };
        cursor = cursor + total_steps.into() * step_us;
    }

    fn count_note_ons(midiobj: @Midi) -> u32 {
        let mut ev = midiobj.clone().events;
        let mut count: u32 = 0;
        loop {
            match ev.pop_front() {
                Option::Some(event) => {
                    match event {
                        Message::NOTE_ON(_) => { count += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        };
        count
    }

    /// Six Toussaint reference presets, four cycles each on distinct channels.
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_reference_presets_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let section_gap: u64 = 500000;
        let cycles: u32 = 4;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut cursor: Time = 0;
        let ids = all_preset_ids();
        let mut i: u32 = 0;
        loop {
            if i >= ids.len() {
                break;
            }
            let preset_id = *ids.at(i);
            let rhythm = known_timeline(preset_id).unwrap();
            let channel: u8 = i.try_into().unwrap();
            let pitch = pitch_for_timeline_preset(preset_id);
            append_timeline_section(
                ref eventlist, @rhythm, cycles, channel, pitch, step_us, ref cursor,
            );
            cursor = cursor + section_gap;
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(count_note_ons(@midiobj) == 120, 'preset120');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }

    /// Seeded displacement-one morph walk starting from Son (four cycles per section).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_morph_walk_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let section_gap: u64 = 500000;
        let cycles: u32 = 4;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut cursor: Time = 0;
        let mut current = known_timeline(PRESET_SON).unwrap();
        let mut seed: felt252 = 9001;
        let mut sections: u32 = 0;

        loop {
            if sections >= 8 {
                break;
            }
            let channel: u8 = 0;
            let pitch = pitch_for_timeline_preset(current.preset_id);
            append_timeline_section(
                ref eventlist, @current, cycles, channel, pitch, step_us, ref cursor,
            );
            cursor = cursor + section_gap;
            sections += 1;

            match next_known_morph(seed, current.preset_id, 1) {
                Option::Some(next) => {
                    current = next;
                    seed += 1;
                },
                Option::None => { break; },
            };
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(sections >= 2, 'morphsect');
        assert(count_note_ons(@midiobj) == sections * cycles * 5, 'morphnotes');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }

    /// Son phase orbit: static voice 0 + rotating voice 1 shifting one step per phase (full orbit).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_son_phase_orbit_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let son = known_timeline(PRESET_SON).unwrap();
        let plan = PhaseRhythmPlan {
            base: son,
            repeats_per_shift: 2,
            shift_step: 1,
            phase_count: 0,
            static_voice_id: 0,
            rotating_voice_id: 1,
            static_velocity: 100,
            rotating_velocity: 80,
        };
        let orbit = phase_orbit_length(16, 1).unwrap();
        let onset_events = render_phase_plan(@plan);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut i: u32 = 0;
        loop {
            if i >= onset_events.len() {
                break;
            }
            let e = *onset_events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            let pitch = if e.voice_id == 0 {
                60_u8
            } else {
                72_u8
            };
            append_legato_note(ref eventlist, channel, pitch, e.velocity, on, off);
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(count_note_ons(@midiobj) == orbit * 2 * 5 * 2, 'phase120');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }

    /// Six canonical Son-family interval-class variants at rotation 0 (four cycles each).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_son_family_variants_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let section_gap: u64 = 500000;
        let cycles: u32 = 4;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut cursor: Time = 0;
        let mut v: u32 = 0;
        loop {
            if v >= 6 {
                break;
            }
            let index = v * 16;
            let rhythm = son_family_candidate_at_index(index);
            let channel: u8 = v.try_into().unwrap();
            let pitch: u8 = (48 + v).try_into().unwrap();
            append_timeline_section(
                ref eventlist, @rhythm, cycles, channel, pitch, step_us, ref cursor,
            );
            cursor = cursor + section_gap;
            v += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(count_note_ons(@midiobj) == 120, 'variants120');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }

    /// Eight seeded Son-family generations (variant + rotation from seed bits).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_son_family_seed_tour_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let section_gap: u64 = 400000;
        let cycles: u32 = 4;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut cursor: Time = 0;
        let mut i: u32 = 0;
        loop {
            if i >= 8 {
                break;
            }
            let seed: felt252 = (101 + i * 111).into();
            let rhythm = generate_son_family_timeline(seed);
            let channel: u8 = 0;
            let pitch: u8 = (48 + i).try_into().unwrap();
            append_timeline_section(
                ref eventlist, @rhythm, cycles, channel, pitch, step_us, ref cursor,
            );
            cursor = cursor + section_gap;
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(count_note_ons(@midiobj) == 160, 'seedtour160');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }

    /// Three profile-guided Son-family selections (metric, distance, symmetry targets).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_profiled_selection_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let section_gap: u64 = 600000;
        let cycles: u32 = 4;

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut cursor: Time = 0;

        let low_metric = TimelineSelectionProfile {
            target_metric_complexity: 4,
            metric_weight: 3,
            target_son_distance_sq: 0,
            distance_weight: 1,
            preferred_symmetry: SYMMETRY_ANY,
            symmetry_penalty: 0,
        };
        let far_from_son = TimelineSelectionProfile {
            target_metric_complexity: 8,
            metric_weight: 1,
            target_son_distance_sq: 12,
            distance_weight: 4,
            preferred_symmetry: SYMMETRY_ANY,
            symmetry_penalty: 0,
        };
        let weak_symmetry = TimelineSelectionProfile {
            target_metric_complexity: 6,
            metric_weight: 1,
            target_son_distance_sq: 4,
            distance_weight: 1,
            preferred_symmetry: SYMMETRY_WEAK,
            symmetry_penalty: 80,
        };

        let rhythm0 = generate_profiled_son_family_timeline(11, low_metric);
        append_timeline_section(
            ref eventlist, @rhythm0, cycles, 0, 48, step_us, ref cursor,
        );
        cursor = cursor + section_gap;

        let rhythm1 = generate_profiled_son_family_timeline(22, far_from_son);
        append_timeline_section(
            ref eventlist, @rhythm1, cycles, 1, 52, step_us, ref cursor,
        );
        cursor = cursor + section_gap;

        let rhythm2 = generate_profiled_son_family_timeline(33, weak_symmetry);
        append_timeline_section(
            ref eventlist, @rhythm2, cycles, 2, 56, step_us, ref cursor,
        );

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(count_note_ons(@midiobj) == 60, 'profiled60');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }

    /// Continuous 16th grid with timeline_accent velocities on Son (onsets loud, rests soft).
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_phrasing_accent_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let son = known_timeline(PRESET_SON).unwrap();

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut cursor: Time = 0;
        append_phrasing_accent_grid(ref eventlist, @son, 8, 0, 60, step_us, ref cursor);

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(count_note_ons(@midiobj) == 128, 'accent128');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }

    /// Phase orbit with shift_step=2 (8 phases): clave vs rotated counter-line.
    #[ignore]
    #[test]
    #[available_gas(1000000000000)]
    fn timeline_rhythm_phase_shift2_midi_test() {
        let tempo_us: u32 = 500000;
        let step_us: u64 = 125000;
        let son = known_timeline(PRESET_SON).unwrap();
        let plan = PhaseRhythmPlan {
            base: son,
            repeats_per_shift: 2,
            shift_step: 2,
            phase_count: 0,
            static_voice_id: 0,
            rotating_voice_id: 1,
            static_velocity: 100,
            rotating_velocity: 72,
        };
        let orbit = phase_orbit_length(16, 2).unwrap();
        let onset_events = render_phase_plan(@plan);

        let mut eventlist = ArrayTrait::<Message>::new();
        eventlist
            .append(
                Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }),
            );

        let mut i: u32 = 0;
        loop {
            if i >= onset_events.len() {
                break;
            }
            let e = *onset_events.at(i);
            let on: Time = e.time.into() * step_us;
            let off: Time = on + e.duration.into() * step_us;
            let channel: u8 = e.voice_id.try_into().unwrap();
            let pitch = if e.voice_id == 0 {
                60_u8
            } else {
                67_u8
            };
            append_legato_note(ref eventlist, channel, pitch, e.velocity, on, off);
            i += 1;
        };

        let midiobj = Midi { events: eventlist.span() };
        generate_parser_format(@midiobj);
        assert(count_note_ons(@midiobj) == orbit * 2 * 5 * 2, 'phase2orb');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midishort');
    }
}

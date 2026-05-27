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
    use koji::midi::pitch::{get_notes_of_key, keynum_to_pc, modal_transposition, pc_to_keynum};
    use koji::midi::types::{Direction, Message, Midi, Modes, NoteOff, NoteOn, PitchClass, SetTempo};
    use koji::sine_wave::{SineWaveParams, sinusoidal_timing_wave_squared};

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
}

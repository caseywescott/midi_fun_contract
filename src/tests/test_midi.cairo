#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use koji::midi::core::MidiTrait;
    use koji::midi::types::{
        Message, Midi, Modes, NoteOff, NoteOn, PitchClass, ProgramChange, SetTempo,
    };

    #[test]
    #[available_gas(10000000)]
    fn extract_notes_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        let newtempo = SetTempo { tempo: 0, time: Option::Some(0) };

        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };

        let newnoteon2 = NoteOn { channel: 0, note: 21, velocity: 100, time: 1000 };

        let newnoteon3 = NoteOn { channel: 0, note: 90, velocity: 100, time: 1500 };

        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };

        let newnoteoff2 = NoteOff { channel: 0, note: 21, velocity: 100, time: 1500 };

        let newnoteoff3 = NoteOff { channel: 0, note: 90, velocity: 100, time: 5000 };

        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        let tempomessage = Message::SET_TEMPO((newtempo));

        eventlist.append(tempomessage);

        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);

        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };

        let midiobjnotesup = midiobj.extract_notes(20);

        // Assert the correctness of the modified Midi object
        // test to ensure correct positive note transpositions

        let mut ev = midiobjnotesup.clone().events;
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(NoteOn) => {
                            //find test notes and assert that notes are within range
                            assert(*NoteOn.note <= 80, 'result > 80');
                            assert(*NoteOn.note >= 40, 'result < 40');
                        },
                        Message::NOTE_OFF(NoteOff) => {
                            //find test notes and assert that notes are within range
                            assert(*NoteOff.note <= 80, 'result > 80');
                            assert(*NoteOff.note >= 40, 'result < 40');
                        },
                        Message::SET_TEMPO(_SetTempo) => { assert(1 == 2, 'MIDI has Tempo MSG'); },
                        Message::TIME_SIGNATURE(_TimeSignature) => {
                            assert(1 == 2, 'MIDI has TimeSig MSG');
                        },
                        Message::CONTROL_CHANGE(_ControlChange) => {
                            assert(1 == 2, 'MIDI has CC MSG');
                        },
                        Message::PITCH_WHEEL(_PitchWheel) => {
                            assert(1 == 2, 'MIDI has PitchWheel MSG');
                        },
                        Message::AFTER_TOUCH(_AfterTouch) => {
                            assert(1 == 2, 'MIDI has AfterTouch MSG');
                        },
                        Message::POLY_TOUCH(_PolyTouch) => {
                            assert(1 == 2, 'MIDI has PolyTouch MSG');
                        },
                        Message::PROGRAM_CHANGE(_ProgramChange) => {
                            assert(1 == 2, 'MIDI has PolyTouch MSG');
                        },
                        Message::SYSTEM_EXCLUSIVE(_SystemExclusive) => {
                            assert(1 == 2, 'MIDI has PolyTouch MSG');
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        };
    }

    #[test]
    #[available_gas(100000000000)]
    fn quantize_notes_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        let newtempo = SetTempo { tempo: 0, time: Option::Some(0) };

        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 1 };

        let newnoteon2 = NoteOn { channel: 0, note: 71, velocity: 100, time: 1001 };

        let newnoteon3 = NoteOn { channel: 0, note: 90, velocity: 100, time: 1500 };

        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };

        let newnoteoff2 = NoteOff { channel: 0, note: 71, velocity: 100, time: 1500 };

        let newnoteoff3 = NoteOff { channel: 0, note: 90, velocity: 100, time: 5000 };

        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        let tempomessage = Message::SET_TEMPO((newtempo));

        eventlist.append(tempomessage);

        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);

        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };

        let midiobjnotesup = midiobj.quantize_notes(1000);

        // Assert the correctness of the modified Midi object
        // test to ensure correct positive time quantizations

        let mut ev = midiobjnotesup.clone().events;
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(NoteOn) => {
                            //find test notes and assert that times are quantized correctly

                            if *NoteOn.note == 60 {
                                let time_val: u64 = (*NoteOn.time).try_into().unwrap();
                                assert(time_val == 0, '1 should quantize to 0');
                            } else if *NoteOn.note == 71 {
                                let time_val: u64 = (*NoteOn.time).try_into().unwrap();
                                assert(time_val == 1000, '1001 should quantize to 1000');
                            } else if *NoteOn.note == 90 {
                                let time_val: u64 = (*NoteOn.time).try_into().unwrap();
                                assert(time_val == 2000, '1500 should quantize to 2000');
                            }
                        },
                        Message::NOTE_OFF(_NoteOff) => {},
                        Message::SET_TEMPO(_SetTempo) => {},
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
        };
    }

    #[test]
    #[available_gas(100000000000)]
    fn change_tempo_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };

        let newnoteon2 = NoteOn { channel: 0, note: 71, velocity: 100, time: 1000 };

        let newnoteon3 = NoteOn { channel: 0, note: 90, velocity: 100, time: 1500 };

        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };

        let newnoteoff2 = NoteOff { channel: 0, note: 71, velocity: 100, time: 1500 };

        let newnoteoff3 = NoteOff { channel: 0, note: 90, velocity: 100, time: 5000 };

        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        //Set Tempo
        let tempo = SetTempo { tempo: 121, time: Option::Some(1500) };
        let tempomessage = Message::SET_TEMPO((tempo));

        eventlist.append(tempomessage);

        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);

        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };

        let midiobjnotes = midiobj.change_tempo(120);

        // Assert the correctness of the modified Midi object
        // test to ensure correct tempo changes

        let mut ev = midiobjnotes.clone().events;
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(_NoteOn) => {},
                        Message::NOTE_OFF(_NoteOff) => {},
                        Message::SET_TEMPO(SetTempo) => {
                            assert(*SetTempo.tempo == 120, 'Tempo should be 120');
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
        };
    }

    #[test]
    #[available_gas(10000000)]
    fn reverse_notes_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        let newtempo = SetTempo { tempo: 0, time: Option::Some(0) };

        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };

        let newnoteon2 = NoteOn { channel: 0, note: 21, velocity: 100, time: 1000 };

        let newnoteon3 = NoteOn { channel: 0, note: 90, velocity: 100, time: 1500 };

        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };

        let newnoteoff2 = NoteOff { channel: 0, note: 21, velocity: 100, time: 1500 };

        let newnoteoff3 = NoteOff { channel: 0, note: 90, velocity: 100, time: 5000 };

        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        let tempomessage = Message::SET_TEMPO((newtempo));

        eventlist.append(tempomessage);

        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);

        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };
        let midiobjnotes = midiobj.reverse_notes();
        let mut ev = midiobjnotes.clone().events;

        // NOTE: reverse_notes converts NOTE_ON to NOTE_OFF and vice versa
        // So we count NOTE_OFF events as they were originally NOTE_ON
        let mut note_off_count = 0;
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(_NoteOn) => { // After reverse, original NOTE_OFF became NOTE_ON
                        },
                        Message::NOTE_OFF(_NoteOff) => {
                            // After reverse, original NOTE_ON became NOTE_OFF
                            note_off_count += 1;
                        },
                        Message::SET_TEMPO(_SetTempo) => {},
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

        assert(note_off_count == 3, 'Should have 3 notes');
    }

    #[test]
    #[available_gas(100000000000)]
    fn remap_instruments_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };

        let newnoteon2 = NoteOn { channel: 0, note: 71, velocity: 100, time: 1000 };

        let newnoteon3 = NoteOn { channel: 0, note: 90, velocity: 100, time: 1500 };

        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };

        let newnoteoff2 = NoteOff { channel: 0, note: 71, velocity: 100, time: 1500 };

        let newnoteoff3 = NoteOff { channel: 0, note: 90, velocity: 100, time: 5000 };

        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        // Set Instruments
        let outpc = ProgramChange { channel: 0, program: 7, time: 6000 };

        let outpc2 = ProgramChange { channel: 0, program: 1, time: 6100 };

        let outpc3 = ProgramChange { channel: 0, program: 8, time: 6200 };
        let outpc4 = ProgramChange { channel: 0, program: 126, time: 6300 };
        let outpc5 = ProgramChange { channel: 0, program: 126, time: 6300 };

        let pcmessage = Message::PROGRAM_CHANGE((outpc));
        let pcmessage2 = Message::PROGRAM_CHANGE((outpc2));
        let pcmessage3 = Message::PROGRAM_CHANGE((outpc3));
        let pcmessage4 = Message::PROGRAM_CHANGE((outpc4));
        let pcmessage5 = Message::PROGRAM_CHANGE((outpc5));

        //Set Tempo
        let tempo = SetTempo { tempo: 121, time: Option::Some(1500) };
        let tempomessage = Message::SET_TEMPO((tempo));

        eventlist.append(tempomessage);

        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);

        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        eventlist.append(pcmessage);
        eventlist.append(pcmessage2);
        eventlist.append(pcmessage3);
        eventlist.append(pcmessage4);
        eventlist.append(pcmessage5);

        let midiobj = Midi { events: eventlist.span() };

        let midiobjnotes = midiobj.remap_instruments(2);

        // Assert the correctness of the modified Midi object
        // test to ensure correct instrument remappings occur for ProgramChange msgs

        let mut ev = midiobjnotes.clone().events;
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(_NoteOn) => {},
                        Message::NOTE_OFF(_NoteOff) => {},
                        Message::SET_TEMPO(_SetTempo) => {},
                        Message::TIME_SIGNATURE(_TimeSignature) => {},
                        Message::CONTROL_CHANGE(_ControlChange) => {},
                        Message::PITCH_WHEEL(_PitchWheel) => {},
                        Message::AFTER_TOUCH(_AfterTouch) => {},
                        Message::POLY_TOUCH(_PolyTouch) => {},
                        Message::PROGRAM_CHANGE(ProgramChange) => {
                            let pc = *ProgramChange.program;
                            let time_val: u64 = (*ProgramChange.time).try_into().unwrap();

                            if time_val == 6000 {
                                assert(pc == 8, 'instruments improperly mapped');
                            } else if time_val == 6100 {
                                assert(pc == 2, 'instruments improperly mapped');
                            } else if time_val == 6200 {
                                assert(pc == 9, 'instruments improperly mapped');
                            } else if time_val == 6300 {
                                assert(pc == 127, 'instruments improperly mapped');
                            }
                        },
                        Message::SYSTEM_EXCLUSIVE(_SystemExclusive) => {},
                    }
                },
                Option::None(_) => { break; },
            };
        };
    }

    #[test]
    #[available_gas(10000000)]
    fn invert_notes_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Create test notes - using middle C (60) as pivot
        let newnoteon1 = NoteOn {
            channel: 0, note: 48, velocity: 100, time: 0,
        }; // C3 - should become C5 (72)

        let newnoteon2 = NoteOn {
            channel: 0, note: 67, velocity: 100, time: 1000,
        }; // G4 - should become Db4 (53)

        let newnoteon3 = NoteOn {
            channel: 0, note: 60, velocity: 100, time: 1500,
        }; // C4 (pivot) - should stay C4 (60)

        let newnoteoff1 = NoteOff { channel: 0, note: 48, velocity: 100, time: 2000 };
        let newnoteoff2 = NoteOff { channel: 0, note: 67, velocity: 100, time: 1500 };
        let newnoteoff3 = NoteOff { channel: 0, note: 60, velocity: 100, time: 5000 };

        // Create messages
        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        // Add tempo message
        let newtempo = SetTempo { tempo: 120, time: Option::Some(0) };
        let tempomessage = Message::SET_TEMPO((newtempo));

        // Build event list
        eventlist.append(tempomessage);
        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);
        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let midiobj = Midi { events: eventlist.span() };

        // Invert around middle C (60)
        let midiobjnotes = midiobj.invert_notes(60);

        // Test the inverted notes
        let mut ev = midiobjnotes.clone().events;
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            if *note_on.time == 0 {
                                // Original note 48 should become 72 (60 + (60-48) = 72)
                                assert!(*note_on.note == 72, "First note should be inverted to 72");
                            } else if *note_on.time == 1000 {
                                // Original note 67 should become 53 (60 - (67-60) = 53)
                                assert!(
                                    *note_on.note == 53, "Second note should be inverted to 53",
                                );
                            } else if *note_on.time == 1500 {
                                // Original note 60 should stay 60 (pivot point)
                                assert!(*note_on.note == 60, "Pivot note should remain 60");
                            }
                        },
                        Message::NOTE_OFF(note_off) => {
                            if *note_off.time == 2000 {
                                // Original note 48 should become 72
                                assert!(
                                    *note_off.note == 72, "First note off should be inverted to 72",
                                );
                            } else if *note_off.time == 1500 {
                                // Original note 67 should become 53
                                assert!(
                                    *note_off.note == 53,
                                    "Second note off should be inverted to 53",
                                );
                            } else if *note_off.time == 5000 {
                                // Original note 60 should stay 60
                                assert!(*note_off.note == 60, "Pivot note off should remain 60");
                            }
                        },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            };
        }
    }

    #[test]
    #[available_gas(100000000)]
    fn generate_harmony_combined_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        let note_on1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };
        let note_off1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 1000 };

        let note_on2 = NoteOn { channel: 0, note: 64, velocity: 100, time: 500 };
        let note_off2 = NoteOff { channel: 0, note: 64, velocity: 100, time: 1500 };

        eventlist.append(Message::NOTE_ON(note_on1));
        eventlist.append(Message::NOTE_OFF(note_off1));
        eventlist.append(Message::NOTE_ON(note_on2));
        eventlist.append(Message::NOTE_OFF(note_off2));

        let midi = Midi { events: eventlist.span() };

        let tonic = PitchClass { note: 0, octave: 4 };
        let mode = Modes::Major;

        // Test with single step first (using existing function)
        let harmonized_midi = midi.generate_harmony(4, tonic, mode);

        let mut events = harmonized_midi.events;
        let mut note_on_count = 0;
        let mut note_off_count = 0;

        loop {
            match events.pop_front() {
                Option::Some(current_event) => match current_event {
                    Message::NOTE_ON(note_on) => {
                        note_on_count += 1;
                        // Should have both original and harmony notes
                        assert!(
                            *note_on.note >= 48 && *note_on.note <= 84,
                            "Generated NOTE_ON out of range",
                        );
                    },
                    Message::NOTE_OFF(note_off) => {
                        note_off_count += 1;
                        // Should have both original and harmony notes
                        assert!(
                            *note_off.note >= 48 && *note_off.note <= 84,
                            "Generated NOTE_OFF out of range",
                        );
                    },
                    _ => {},
                },
                Option::None(_) => { break; },
            }
        }

        // Should have doubled the notes (original + harmony)
        assert!(note_on_count == 4, "Should have 4 note on events");
        assert!(note_off_count == 4, "Should have 4 note off events");
    }

    #[test]
    #[available_gas(100000000000)]
    fn detect_chords_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Create three notes that should form a chord (even closer in time)
        let chord_note1 = NoteOn { channel: 0, note: 60, // Middle C
        velocity: 100, time: 1000 };

        let chord_note2 = NoteOn {
            channel: 0, note: 64, // E
            velocity: 100, time: 1005 // Reduced time difference
        };

        let chord_note3 = NoteOn {
            channel: 0, note: 67, // G
            velocity: 100, time: 1010 // Reduced time difference
        };

        // Create corresponding note-off events (closer together)
        let chord_note1_off = NoteOff { channel: 0, note: 60, velocity: 100, time: 1200 };
        let chord_note2_off = NoteOff { channel: 0, note: 64, velocity: 100, time: 1205 };
        let chord_note3_off = NoteOff { channel: 0, note: 67, velocity: 100, time: 1210 };

        // Convert notes to messages
        let msg1_on = Message::NOTE_ON((chord_note1));
        let msg2_on = Message::NOTE_ON((chord_note2));
        let msg3_on = Message::NOTE_ON((chord_note3));

        let msg1_off = Message::NOTE_OFF((chord_note1_off));
        let msg2_off = Message::NOTE_OFF((chord_note2_off));
        let msg3_off = Message::NOTE_OFF((chord_note3_off));

        // Add messages to event list in chronological order
        eventlist.append(msg1_on);
        eventlist.append(msg2_on);
        eventlist.append(msg3_on);
        eventlist.append(msg1_off);
        eventlist.append(msg2_off);
        eventlist.append(msg3_off);

        let midiobj = Midi { events: eventlist.span() };

        // Detect chords with a window size of 20 ticks and minimum 3 notes
        let chords = midiobj.detect_chords(20, 3);

        // Verify the results
        let mut ev = chords.events;
        let mut chord_count = 0;
        let mut notes_in_chord = 0;

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            // Verify the notes are part of our expected chord (C major: 60, 64, 67)
                            assert!(
                                *note_on.note == 60 || *note_on.note == 64 || *note_on.note == 67,
                                "Unexpected note in chord",
                            );
                            notes_in_chord += 1;
                        },
                        Message::NOTE_OFF(_note_off) => {
                            // Count note-offs to verify we have the right number
                            chord_count += 1;
                        },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }

        // Verify we found exactly one chord with three notes
        assert!(notes_in_chord == 3, "Should find exactly 3 notes");
        assert!(chord_count == 3, "Should find exactly 3 note-offs");
    }

    #[test]
    #[available_gas(10000000)]
    fn output_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Create a simple MIDI sequence
        let note_on1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };
        let note_off1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 1000 };
        let note_on2 = NoteOn { channel: 0, note: 64, velocity: 100, time: 500 };
        let note_off2 = NoteOff { channel: 0, note: 64, velocity: 100, time: 1500 };

        // Add tempo
        let tempo = SetTempo { tempo: 120, time: Option::Some(0) };

        eventlist.append(Message::SET_TEMPO(tempo));
        eventlist.append(Message::NOTE_ON(note_on1));
        eventlist.append(Message::NOTE_ON(note_on2));
        eventlist.append(Message::NOTE_OFF(note_off1));
        eventlist.append(Message::NOTE_OFF(note_off2));

        let midi = Midi { events: eventlist.span() };

        // Test MIDI binary output
        let binary_output = koji::midi::output::output_midi_object(@midi);

        // Verify we got some output
        assert!(binary_output.len() > 0, "MIDI output should not be empty");

        // Check that it starts with MIDI header "MThd"
        assert!(*binary_output.get(0).unwrap().unbox() == 0x4D, "Should start with 'M'");
        assert!(*binary_output.get(1).unwrap().unbox() == 0x54, "Should have 'T'");
        assert!(*binary_output.get(2).unwrap().unbox() == 0x68, "Should have 'h'");
        assert!(*binary_output.get(3).unwrap().unbox() == 0x64, "Should have 'd'");

        // Check that we have at least the minimum expected size (header + track header + some data)
        assert!(binary_output.len() >= 22, "Should have at least header + track data");
    }
}

#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use koji::midi::core::MidiTrait;
    use koji::midi::types::{Message, Midi, NoteOff, NoteOn, ProgramChange, SetTempo};

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
    #[available_gas(100000000000)]
    fn invert_notes_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Create test notes - using middle C (60) as pivot
        let newnoteon1 = NoteOn {
            channel: 0, note: 48, velocity: 100, time: FP32x32 { mag: 0, sign: false }
        }; // C3 - should become C5 (72)

        let newnoteon2 = NoteOn {
            channel: 0, note: 67, velocity: 100, time: FP32x32 { mag: 1000, sign: false }
        }; // G4 - should become Db4 (53)

        let newnoteon3 = NoteOn {
            channel: 0, note: 60, velocity: 100, time: FP32x32 { mag: 1500, sign: false }
        }; // C4 (pivot) - should stay C4 (60)

        let newnoteoff1 = NoteOff {
            channel: 0, note: 48, velocity: 100, time: FP32x32 { mag: 2000, sign: false }
        };

        let newnoteoff2 = NoteOff {
            channel: 0, note: 67, velocity: 100, time: FP32x32 { mag: 1500, sign: false }
        };

        let newnoteoff3 = NoteOff {
            channel: 0, note: 60, velocity: 100, time: FP32x32 { mag: 5000, sign: false }
        };

        // Create messages
        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));

        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        // Add tempo message
        let newtempo = SetTempo { tempo: 120, time: Option::Some(FP32x32 { mag: 0, sign: false }) };
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
                        Message::NOTE_ON(NoteOn) => {
                            if *NoteOn.time.mag == 0 {
                                // First note (C3 -> C5)
                                assert(*NoteOn.note == 72, 'C3 should invert to C5');
                            } else if *NoteOn.time.mag == 1000 {
                                // Second note (G4 -> Db4)
                                assert(*NoteOn.note == 53, 'G4 should invert to Db4');
                            } else if *NoteOn.time.mag == 1500 {
                                // Third note (pivot note)
                                assert(*NoteOn.note == 60, 'Pivot note should not change');
                            }
                        },
                        Message::NOTE_OFF(NoteOff) => {
                            if *NoteOff.time.mag == 2000 {
                                assert(*NoteOff.note == 72, 'C3 OFF should invert to C5');
                            } else if *NoteOff.time.mag == 1500 {
                                assert(*NoteOff.note == 53, 'G4 OFF should invert to Db4');
                            } else if *NoteOff.time.mag == 5000 {
                                assert(*NoteOff.note == 60, 'Pivot OFF should not change');
                            }
                        },
                        Message::SET_TEMPO(_) => {},
                        Message::TIME_SIGNATURE(_) => {},
                        Message::CONTROL_CHANGE(_) => {},
                        Message::PITCH_WHEEL(_) => {},
                        Message::AFTER_TOUCH(_) => {},
                        Message::POLY_TOUCH(_) => {},
                        Message::PROGRAM_CHANGE(_) => {},
                        Message::SYSTEM_EXCLUSIVE(_) => {},
                    }
                },
                Option::None(_) => { break; }
            };
        };
    }
}

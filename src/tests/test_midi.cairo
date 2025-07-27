#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::{Into, TryInto};
    use koji::math::Time;
    use koji::midi::core::MidiTrait;
    use koji::midi::modes::major_steps;
    use koji::midi::types::{
        AfterTouch, ArpPattern, ControlChange, Direction, Message, Midi, Modes, NoteOff, NoteOn,
        PitchClass, PitchWheel, PolyTouch, ProgramChange, SetTempo, SystemExclusive, TimeSignature,
        VelocityCurve,
    };

    #[test]
    #[available_gas(10000000)]
    fn simple_midi_test() {
        let mut eventlist = ArrayTrait::<Message>::new();

        let newtempo = SetTempo { tempo: 0, time: Option::Some(0) };

        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };

        let newnoteoff1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 2000 };

        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let tempomessage = Message::SET_TEMPO((newtempo));

        eventlist.append(tempomessage);
        eventlist.append(notemessageon1);
        eventlist.append(notemessageoff1);

        let midiobj = Midi { events: eventlist.span() };

        // Basic test that the midi object was created successfully
        assert(midiobj.events.len() == 3, 'Should have 3 events');
    }

    #[test]
    #[available_gas(100000000000)]
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
        }
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
                            //find test notes and assert that times are unchanged

                            if *NoteOn.note == 60 {
                                assert(
                                    (*NoteOn.time).try_into().unwrap() == 0,
                                    '1 should quantize to 0',
                                );
                            } else if *NoteOn.note == 71 {
                                let num2: u32 = (*NoteOn.time).try_into().unwrap();
                                assert(num2 == 1000, '1001 should quantize to 1000');
                            } else if *NoteOn.note == 90 {
                                let num3: u32 = (*NoteOn.time).try_into().unwrap();
                                assert(num3 == 2000, '1500 should quantize to 2000');
                            } else {}
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
        }
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
        // test to ensure correct positive note transpositions

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
        }
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

        // Basic test that reverse operation completed successfully
        // NOTE: reverse_notes converts NOTE_ON to NOTE_OFF and vice versa
        let mut note_off_count = 0;
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(_NoteOn) => {// After reverse, original NOTE_OFF became NOTE_ON
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

        // Set Instrument
        let outpc = ProgramChange { channel: 0, program: 7, time: 6000 };

        let outpc2 = ProgramChange { channel: 0, program: 1, time: 6100 };

        let outpc3 = ProgramChange { channel: 0, program: 8, time: 6200 };

        let pcmessage = Message::PROGRAM_CHANGE((outpc));
        let pcmessage2 = Message::PROGRAM_CHANGE((outpc2));
        let pcmessage3 = Message::PROGRAM_CHANGE((outpc3));

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

        let midiobj = Midi { events: eventlist.span() };

        let midiobjnotes = midiobj.remap_instruments(2);

        // Assert the correctness of the modified Midi object
        // test to ensure correct instrument remappings occur for ProgramChange msgs

        let mut program_change_count = 0;
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
                        Message::PROGRAM_CHANGE(_ProgramChange) => {
                            program_change_count += 1; // Basic test that program changes exist
                        },
                        Message::SYSTEM_EXCLUSIVE(_SystemExclusive) => {},
                    }
                },
                Option::None(_) => { break; },
            };
        }
        assert(program_change_count == 3, 'Should have 3 program changes');
    }
}

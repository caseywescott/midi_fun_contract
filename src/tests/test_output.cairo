use koji::midi::core::MidiTrait;
use koji::midi::output::output_midi_object;
use koji::midi::types::{ControlChange, Message, Midi, NoteOff, NoteOn, ProgramChange, SetTempo};

#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use super::*;

    #[test]
    #[available_gas(10000000)]
    fn test_basic_midi_output() {
        let midi = MidiTrait::new();
        let output = output_midi_object(@midi);

        // Check MIDI header "MThd"
        assert!(*output.get(0).unwrap().unbox() == 0x4D, "Invalid header M");
        assert!(*output.get(1).unwrap().unbox() == 0x54, "Invalid header T");
        assert!(*output.get(2).unwrap().unbox() == 0x68, "Invalid header h");
        assert!(*output.get(3).unwrap().unbox() == 0x64, "Invalid header d");

        // Check header length (6 bytes)
        assert!(*output.get(4).unwrap().unbox() == 0x00, "Invalid header length 1");
        assert!(*output.get(5).unwrap().unbox() == 0x00, "Invalid header length 2");
        assert!(*output.get(6).unwrap().unbox() == 0x00, "Invalid header length 3");
        assert!(*output.get(7).unwrap().unbox() == 0x06, "Invalid header length 4");

        // Check format type (0)
        assert!(*output.get(8).unwrap().unbox() == 0x00, "Invalid format type 1");
        assert!(*output.get(9).unwrap().unbox() == 0x00, "Invalid format type 2");

        // Check track count (1)
        assert!(*output.get(10).unwrap().unbox() == 0x00, "Invalid track count 1");
        assert!(*output.get(11).unwrap().unbox() == 0x01, "Invalid track count 2");

        // Check division (480 PPQN = 0x01E0)
        assert!(*output.get(12).unwrap().unbox() == 0x01, "Invalid division 1");
        assert!(*output.get(13).unwrap().unbox() == 0xE0, "Invalid division 2");

        // Check track header "MTrk"
        assert!(*output.get(14).unwrap().unbox() == 0x4D, "Invalid track header M");
        assert!(*output.get(15).unwrap().unbox() == 0x54, "Invalid track header T");
        assert!(*output.get(16).unwrap().unbox() == 0x72, "Invalid track header r");
        assert!(*output.get(17).unwrap().unbox() == 0x6B, "Invalid track header k");
    }

    #[test]
    #[available_gas(10000000)]
    fn test_note_events() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Add a note on event
        let note_on = NoteOn { channel: 0, note: 60, // Middle C
        velocity: 100, time: 0 };
        eventlist.append(Message::NOTE_ON(note_on));

        // Add corresponding note off
        let note_off = NoteOff {
            channel: 0, note: 60, velocity: 100, time: 480 // Quarter note later
        };
        eventlist.append(Message::NOTE_OFF(note_off));

        let midi = Midi { events: eventlist.span() };
        let output = output_midi_object(@midi);

        // Should be larger than basic output due to note events
        assert!(output.len() > 30, "Output should contain note events");

        // Look for note events after track header (starting at byte 22 after track length)
        let mut found_note_on = false;
        let mut found_note_off = false;
        let mut i = 22;

        loop {
            if i >= output.len() - 2 {
                break;
            }

            match output.get(i) {
                Option::Some(byte) => {
                    let val = *byte.unbox();
                    // Look for Note On (0x90) and Note Off (0x80) status bytes
                    if val == 0x90 {
                        found_note_on = true;
                        // Check note number and velocity
                        match output.get(i + 1) {
                            Option::Some(note_byte) => {
                                assert!(*note_byte.unbox() == 60, "Invalid note number");
                            },
                            Option::None => {},
                        }
                        match output.get(i + 2) {
                            Option::Some(vel_byte) => {
                                assert!(*vel_byte.unbox() == 100, "Invalid velocity");
                            },
                            Option::None => {},
                        }
                    } else if val == 0x80 {
                        found_note_off = true;
                    }
                },
                Option::None => {},
            }
            i += 1;
        }

        assert!(found_note_on, "Should find Note On event");
        assert!(found_note_off, "Should find Note Off event");
    }

    #[test]
    #[available_gas(10000000)]
    fn test_program_change() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Add a program change event
        let prog_change = ProgramChange { channel: 0, program: 1, // Acoustic Grand Piano
        time: 0 };
        eventlist.append(Message::PROGRAM_CHANGE(prog_change));

        let midi = Midi { events: eventlist.span() };
        let output = output_midi_object(@midi);

        // Look for program change event (0xC0)
        let mut found_prog_change = false;
        let mut i = 22;

        loop {
            if i >= output.len() - 1 {
                break;
            }

            match output.get(i) {
                Option::Some(byte) => {
                    let val = *byte.unbox();
                    if val == 0xC0 { // Program Change on channel 0
                        found_prog_change = true;
                        // Check program number
                        match output.get(i + 1) {
                            Option::Some(prog_byte) => {
                                assert!(*prog_byte.unbox() == 1, "Invalid program number");
                            },
                            Option::None => {},
                        }
                    }
                },
                Option::None => {},
            }
            i += 1;
        }

        assert!(found_prog_change, "Should find Program Change event");
    }

    #[test]
    #[available_gas(10000000)]
    fn test_control_change() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Add a control change event (Volume)
        let cc = ControlChange {
            channel: 0, control: 7, // Volume
            value: 127, // Max volume
            time: 0,
        };
        eventlist.append(Message::CONTROL_CHANGE(cc));

        let midi = Midi { events: eventlist.span() };
        let output = output_midi_object(@midi);

        // Look for control change event (0xB0)
        let mut found_cc = false;
        let mut i = 22;

        loop {
            if i >= output.len() - 2 {
                break;
            }

            match output.get(i) {
                Option::Some(byte) => {
                    let val = *byte.unbox();
                    if val == 0xB0 { // Control Change on channel 0
                        found_cc = true;
                        // Check controller and value
                        match output.get(i + 1) {
                            Option::Some(ctrl_byte) => {
                                assert!(*ctrl_byte.unbox() == 7, "Invalid controller number");
                            },
                            Option::None => {},
                        }
                        match output.get(i + 2) {
                            Option::Some(val_byte) => {
                                assert!(*val_byte.unbox() == 127, "Invalid control value");
                            },
                            Option::None => {},
                        }
                    }
                },
                Option::None => {},
            }
            i += 1;
        }

        assert!(found_cc, "Should find Control Change event");
    }

    #[test]
    #[available_gas(10000000)]
    fn test_tempo_event() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Add a tempo event
        let tempo = SetTempo { tempo: 120, // 120 BPM
        time: Option::Some(0) };
        eventlist.append(Message::SET_TEMPO(tempo));

        let midi = Midi { events: eventlist.span() };
        let output = output_midi_object(@midi);

        // Look for tempo meta event (0xFF 0x51 0x03)
        let mut found_tempo = false;
        let mut i = 22;

        loop {
            if i >= output.len() - 3 {
                break;
            }

            match (output.get(i), output.get(i + 1), output.get(i + 2)) {
                (
                    Option::Some(b1), Option::Some(b2), Option::Some(b3),
                ) => {
                    if *b1.unbox() == 0xFF && *b2.unbox() == 0x51 && *b3.unbox() == 0x03 {
                        found_tempo = true;
                        break;
                    }
                },
                _ => {},
            }
            i += 1;
        }

        assert!(found_tempo, "Should find Tempo meta event");
    }

    #[test]
    #[available_gas(20000000)]
    fn test_complex_sequence() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Create a complex MIDI sequence
        let tempo = SetTempo { tempo: 120, time: Option::Some(0) };
        let prog_change = ProgramChange { channel: 0, program: 1, time: 0 };
        let note_on1 = NoteOn { channel: 0, note: 60, velocity: 100, time: 0 };
        let note_on2 = NoteOn { channel: 0, note: 64, velocity: 100, time: 240 };
        let note_off1 = NoteOff { channel: 0, note: 60, velocity: 100, time: 480 };
        let note_off2 = NoteOff { channel: 0, note: 64, velocity: 100, time: 720 };
        let cc = ControlChange { channel: 0, control: 7, value: 100, time: 960 };

        eventlist.append(Message::SET_TEMPO(tempo));
        eventlist.append(Message::PROGRAM_CHANGE(prog_change));
        eventlist.append(Message::NOTE_ON(note_on1));
        eventlist.append(Message::NOTE_ON(note_on2));
        eventlist.append(Message::NOTE_OFF(note_off1));
        eventlist.append(Message::NOTE_OFF(note_off2));
        eventlist.append(Message::CONTROL_CHANGE(cc));

        let midi = Midi { events: eventlist.span() };
        let output = output_midi_object(@midi);

        // Verify we have a substantial output
        assert!(output.len() > 50, "Complex sequence should produce substantial output");

        // Verify it ends with End of Track (0xFF 0x2F 0x00)
        let len = output.len();
        assert!(*output.get(len - 3).unwrap().unbox() == 0xFF, "Should end with meta event");
        assert!(*output.get(len - 2).unwrap().unbox() == 0x2F, "Should end with End of Track");
        assert!(*output.get(len - 1).unwrap().unbox() == 0x00, "Should end with zero length");
    }
}

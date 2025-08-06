#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use koji::math::Time;
    use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

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
}

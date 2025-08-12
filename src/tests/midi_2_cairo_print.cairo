#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use koji::lcg::{LCG, RNGTrait};
    use koji::math::Time;
    use koji::midi::modes::dorian_steps;
    use koji::midi::pitch::PitchClassTrait;
    use koji::midi::types::{Direction, Message, Midi, NoteOff, NoteOn, PitchClass, SetTempo};
    use koji::midi::voicings::{
        fourths_1, maj_7_no_root_3rd_inversion, maj_7_no_root_3rd_inversion2,
        maj_7_no_root_3rd_inversion_add6, maj_9_no_root_3rd_inversion_add6, plus_four_7,
        plus_four_7_2, seventh_and_third, triad_first_inversion, triad_root_position,
        triad_second_inversion,
    };

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
        // This test generates clean Cairo code output with random voicings in D dorian
        let mut eventlist = ArrayTrait::<Message>::new();

        // Set tempo to 120 BPM (500000 microseconds per beat)
        let tempo = SetTempo { tempo: 500000, time: Option::Some(0) };
        eventlist.append(Message::SET_TEMPO(tempo));

        // Initialize LCG with seed for reproducible randomness
        let mut lcg = LCG {
            state: 42, // Seed for reproducible results
            multiplier: 13,
            increment: 7,
            modulus: 100 // Very small modulus to avoid overflow
        };

        // D dorian key (D = note 2, octave 4)
        let tonic = PitchClass { note: 2, octave: 4 }; // D4

        // Generate 8 voicings (8 seconds of music) using delta times
        let voicing_duration: Time = 1000; // 1 second per voicing
        let note_duration: Time = 950; // 950ms note duration (50ms gap between voicings)

        let mut i: u32 = 0;
        loop {
            if i == 8 {
                break;
            }

            // Randomly select a scale degree (1-7 for dorian mode)
            let scale_degree = (lcg.value() % 7) + 1; // 1-7
            lcg = lcg.next();

            // Calculate the root note for this scale degree using D dorian scale
            // D dorian scale: D(2), E(4), F(5), G(7), A(9), B(11), C(0)
            let dorian_scale_notes = array![2, 4, 5, 7, 9, 11, 0].span();
            let scale_degree_index = (scale_degree - 1) % 7; // 0-6 for 7 scale degrees
            let root_note_value = *dorian_scale_notes.at(scale_degree_index);
            let root_pitch_class = PitchClass { note: root_note_value, octave: tonic.octave };
            let root_keynum = root_pitch_class.keynum();

            // Generate notes for a simple triad voicing using only dorian scale notes
            let mut voicing_notes = ArrayTrait::<u8>::new();
            voicing_notes.append(root_keynum); // Add root note

            // Add third (next note in dorian scale)
            let third_scale_index = (scale_degree_index + 2) % 7; // Skip one note
            let third_note_value = *dorian_scale_notes.at(third_scale_index);
            let third_pitch_class = PitchClass { note: third_note_value, octave: tonic.octave };
            let third_keynum = third_pitch_class.keynum();
            voicing_notes.append(third_keynum);

            // Add fifth (skip two notes in dorian scale)
            let fifth_scale_index = (scale_degree_index + 4) % 7; // Skip two notes
            let fifth_note_value = *dorian_scale_notes.at(fifth_scale_index);
            let fifth_pitch_class = PitchClass { note: fifth_note_value, octave: tonic.octave };
            let fifth_keynum = fifth_pitch_class.keynum();
            voicing_notes.append(fifth_keynum);

            // Calculate timing for this voicing
            let voicing_start_delta = if i == 0 {
                0
            } else {
                50
            }; // 50ms gap between voicings
            let voicing_notes_span = voicing_notes.span();
            let num_notes = voicing_notes_span.len();

            // Add all NoteOn events for this voicing with proper delta timing
            let mut k = 0;
            loop {
                if k >= num_notes {
                    break;
                }
                let note = *voicing_notes_span.at(k);
                let note_on_delta = if k == 0 {
                    voicing_start_delta
                } else {
                    0
                };
                let note_on = NoteOn { channel: 0, note: note, velocity: 80, time: note_on_delta };
                eventlist.append(Message::NOTE_ON(note_on));
                k += 1;
            }

            // Add all NoteOff events for this voicing with proper delta timing
            let mut l = 0;
            loop {
                if l >= num_notes {
                    break;
                }
                let note = *voicing_notes_span.at(l);
                let note_off_delta = if l == 0 {
                    note_duration
                } else {
                    0
                };
                let note_off = NoteOff {
                    channel: 0, note: note, velocity: 0, time: note_off_delta,
                };
                eventlist.append(Message::NOTE_OFF(note_off));
                l += 1;
            }

            i += 1;
        }

        let midiobj = Midi { events: eventlist.span() };

        // Generate clean Cairo code output
        generate_cairo_code(@midiobj);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn midi_to_parser_format_test() {
        // This test generates individual MIDI event lines for the TypeScript parser with random
        // voicings in D dorian
        let mut eventlist = ArrayTrait::<Message>::new();

        // Set tempo to 120 BPM (500000 microseconds per beat)
        let tempo = SetTempo { tempo: 500000, time: Option::Some(0) };
        eventlist.append(Message::SET_TEMPO(tempo));

        // Initialize LCG with seed for reproducible randomness
        let mut lcg = LCG {
            state: 42, // Seed for reproducible results
            multiplier: 13,
            increment: 7,
            modulus: 100 // Very small modulus to avoid overflow
        };

        // D dorian key (D = note 2, octave 4)
        let tonic = PitchClass { note: 2, octave: 4 }; // D4

        // Generate 8 voicings (8 seconds of music) using delta times
        let voicing_duration: Time = 1000; // 1 second per voicing
        let note_duration: Time = 950; // 950ms note duration (50ms gap between voicings)

        let mut i: u32 = 0;
        loop {
            if i == 8 {
                break;
            }

            // Randomly select a scale degree (1-7 for dorian mode)
            let scale_degree = (lcg.value() % 7) + 1; // 1-7
            lcg = lcg.next();

            // Calculate the root note for this scale degree using D dorian scale
            // D dorian scale: D(2), E(4), F(5), G(7), A(9), B(11), C(0)
            let dorian_scale_notes = array![2, 4, 5, 7, 9, 11, 0].span();
            let scale_degree_index = (scale_degree - 1) % 7; // 0-6 for 7 scale degrees
            let root_note_value = *dorian_scale_notes.at(scale_degree_index);
            let root_pitch_class = PitchClass { note: root_note_value, octave: tonic.octave };
            let root_keynum = root_pitch_class.keynum();

            // Generate notes for a simple triad voicing using only dorian scale notes
            let mut voicing_notes = ArrayTrait::<u8>::new();
            voicing_notes.append(root_keynum); // Add root note

            // Add third (next note in dorian scale)
            let third_scale_index = (scale_degree_index + 2) % 7; // Skip one note
            let third_note_value = *dorian_scale_notes.at(third_scale_index);
            let third_pitch_class = PitchClass { note: third_note_value, octave: tonic.octave };
            let third_keynum = third_pitch_class.keynum();
            voicing_notes.append(third_keynum);

            // Add fifth (skip two notes in dorian scale)
            let fifth_scale_index = (scale_degree_index + 4) % 7; // Skip two notes
            let fifth_note_value = *dorian_scale_notes.at(fifth_scale_index);
            let fifth_pitch_class = PitchClass { note: fifth_note_value, octave: tonic.octave };
            let fifth_keynum = fifth_pitch_class.keynum();
            voicing_notes.append(fifth_keynum);

            // Calculate timing for this voicing
            let voicing_start_delta = if i == 0 {
                0
            } else {
                50
            }; // 50ms gap between voicings
            let voicing_notes_span = voicing_notes.span();
            let num_notes = voicing_notes_span.len();

            // Add all NoteOn events for this voicing with proper delta timing
            let mut k = 0;
            loop {
                if k >= num_notes {
                    break;
                }
                let note = *voicing_notes_span.at(k);
                let note_on_delta = if k == 0 {
                    voicing_start_delta
                } else {
                    0
                };
                let note_on = NoteOn { channel: 0, note: note, velocity: 80, time: note_on_delta };
                eventlist.append(Message::NOTE_ON(note_on));
                k += 1;
            }

            // Add all NoteOff events for this voicing with proper delta timing
            let mut l = 0;
            loop {
                if l >= num_notes {
                    break;
                }
                let note = *voicing_notes_span.at(l);
                let note_off_delta = if l == 0 {
                    note_duration
                } else {
                    0
                };
                let note_off = NoteOff {
                    channel: 0, note: note, velocity: 0, time: note_off_delta,
                };
                eventlist.append(Message::NOTE_OFF(note_off));
                l += 1;
            }

            i += 1;
        }

        let midiobj = Midi { events: eventlist.span() };

        // Generate individual MIDI event lines for parser
        generate_parser_format(@midiobj);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn random_voicings_d_dorian_test() {
        // Create a MIDI file with random voicings in D dorian
        // Each voicing changes every second (1000 time units)

        let mut eventlist = ArrayTrait::<Message>::new();

        // Set tempo to 120 BPM (500000 microseconds per beat)
        let tempo = SetTempo { tempo: 500000, time: Option::Some(0) };
        eventlist.append(Message::SET_TEMPO(tempo));

        // Initialize LCG with seed for reproducible randomness
        let mut lcg = LCG {
            state: 42, // Seed for reproducible results
            multiplier: 13,
            increment: 7,
            modulus: 100 // Very small modulus to avoid overflow
        };

        // D dorian key (D = note 2, octave 4)
        let tonic = PitchClass { note: 2, octave: 4 }; // D4
        let dorian_steps = dorian_steps(); // [2,1,2,2,2,1,2]

        // Simple voicing patterns (since voicings module is not available)
        // Each pattern is an array of intervals to add to the root note
        let mut voicing_patterns = ArrayTrait::<Array<u8>>::new();

        // Triad root position: root, third, fifth
        let mut triad_root = ArrayTrait::<u8>::new();
        triad_root.append(4); // major third
        triad_root.append(7); // perfect fifth
        voicing_patterns.append(triad_root);

        // Triad first inversion: root, third, sixth
        let mut triad_first = ArrayTrait::<u8>::new();
        triad_first.append(4); // major third
        triad_first.append(9); // major sixth
        voicing_patterns.append(triad_first);

        // Triad second inversion: root, fourth, sixth
        let mut triad_second = ArrayTrait::<u8>::new();
        triad_second.append(5); // perfect fourth
        triad_second.append(9); // major sixth
        voicing_patterns.append(triad_second);

        // Seventh chord: root, third, fifth, seventh
        let mut seventh = ArrayTrait::<u8>::new();
        seventh.append(4); // major third
        seventh.append(7); // perfect fifth
        seventh.append(10); // minor seventh
        voicing_patterns.append(seventh);

        // Quartal voicing: root, fourth, seventh
        let mut quartal = ArrayTrait::<u8>::new();
        quartal.append(5); // perfect fourth
        quartal.append(10); // minor seventh
        voicing_patterns.append(quartal);

        let voicing_patterns_span = voicing_patterns.span();
        let num_voicings = voicing_patterns_span.len();

        // Generate 8 voicings (8 seconds of music)
        let mut current_time: Time = 0;
        let voicing_duration: Time = 1000; // 1 second per voicing

        let mut i: u32 = 0;
        loop {
            if i == 8 {
                break;
            }

            // Randomly select a voicing pattern
            let voicing_index = lcg.value() % num_voicings;
            let selected_pattern = voicing_patterns_span.at(voicing_index);
            lcg = lcg.next();

            // Randomly select a scale degree (1-7 for dorian mode)
            let scale_degree = (lcg.value() % 7) + 1; // 1-7
            lcg = lcg.next();

            // Calculate the root note for this scale degree
            let root_note = tonic
                .modal_transposition(
                    tonic, dorian_steps, (scale_degree - 1).try_into().unwrap(), Direction::Up(()),
                );

            // Generate notes for the voicing
            let mut voicing_notes = ArrayTrait::<u8>::new();
            voicing_notes.append(root_note); // Add root note

            // Add intervals from the voicing pattern
            let pattern_intervals = selected_pattern;
            let pattern_len = pattern_intervals.len();
            let mut j = 0;
            loop {
                if j >= pattern_len {
                    break;
                }
                let interval = *pattern_intervals.at(j);
                let next_note = root_note + interval;
                voicing_notes.append(next_note);
                j += 1;
            }

            // Create NoteOn events for all notes in the voicing
            let voicing_notes_span = voicing_notes.span();
            let mut j = 0;
            loop {
                if j >= voicing_notes_span.len() {
                    break;
                }

                let note = *voicing_notes_span.at(j);
                let note_on = NoteOn { channel: 0, note: note, velocity: 80, time: current_time };
                eventlist.append(Message::NOTE_ON(note_on));
                j += 1;
            }

            // Create NoteOff events for all notes (slightly before next voicing)
            let mut j = 0;
            loop {
                if j >= voicing_notes_span.len() {
                    break;
                }

                let note = *voicing_notes_span.at(j);
                let note_off = NoteOff {
                    channel: 0,
                    note: note,
                    velocity: 0,
                    time: current_time + voicing_duration - 50 // Slightly before next voicing
                };
                eventlist.append(Message::NOTE_OFF(note_off));
                j += 1;
            }

            current_time += voicing_duration;
            i += 1;
        }

        let midiobj = Midi { events: eventlist.span() };

        // Generate clean Cairo code output
        generate_cairo_code(@midiobj);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn random_voicings_d_dorian_parser_test() {
        // Create a MIDI file with random voicings in D dorian for parser output
        // Each voicing changes every second (1000 time units)

        let mut eventlist = ArrayTrait::<Message>::new();

        // Set tempo to 120 BPM (500000 microseconds per beat)
        let tempo = SetTempo { tempo: 500000, time: Option::Some(0) };
        eventlist.append(Message::SET_TEMPO(tempo));

        // Initialize LCG with seed for reproducible randomness
        let mut lcg = LCG {
            state: 42, // Seed for reproducible results
            multiplier: 13,
            increment: 7,
            modulus: 100 // Very small modulus to avoid overflow
        };

        // D dorian key (D = note 2, octave 4)
        let tonic = PitchClass { note: 2, octave: 4 }; // D4
        let dorian_steps = dorian_steps(); // [2,1,2,2,2,1,2]

        // Simple voicing patterns (since voicings module is not available)
        // Each pattern is an array of intervals to add to the root note
        let mut voicing_patterns = ArrayTrait::<Array<u8>>::new();

        // Triad root position: root, third, fifth
        let mut triad_root = ArrayTrait::<u8>::new();
        triad_root.append(4); // major third
        triad_root.append(7); // perfect fifth
        voicing_patterns.append(triad_root);

        // Triad first inversion: root, third, sixth
        let mut triad_first = ArrayTrait::<u8>::new();
        triad_first.append(4); // major third
        triad_first.append(9); // major sixth
        voicing_patterns.append(triad_first);

        // Triad second inversion: root, fourth, sixth
        let mut triad_second = ArrayTrait::<u8>::new();
        triad_second.append(5); // perfect fourth
        triad_second.append(9); // major sixth
        voicing_patterns.append(triad_second);

        // Seventh chord: root, third, fifth, seventh
        let mut seventh = ArrayTrait::<u8>::new();
        seventh.append(4); // major third
        seventh.append(7); // perfect fifth
        seventh.append(10); // minor seventh
        voicing_patterns.append(seventh);

        // Quartal voicing: root, fourth, seventh
        let mut quartal = ArrayTrait::<u8>::new();
        quartal.append(5); // perfect fourth
        quartal.append(10); // minor seventh
        voicing_patterns.append(quartal);

        let voicing_patterns_span = voicing_patterns.span();
        let num_voicings = voicing_patterns_span.len();

        // Generate 8 voicings (8 seconds of music)
        let mut current_time: Time = 0;
        let voicing_duration: Time = 1000; // 1 second per voicing

        let mut i: u32 = 0;
        loop {
            if i == 8 {
                break;
            }

            // Randomly select a voicing pattern
            let voicing_index = lcg.value() % num_voicings;
            let selected_pattern = voicing_patterns_span.at(voicing_index);
            lcg = lcg.next();

            // Randomly select a scale degree (1-7 for dorian mode)
            let scale_degree = (lcg.value() % 7) + 1; // 1-7
            lcg = lcg.next();

            // Calculate the root note for this scale degree
            let root_note = tonic
                .modal_transposition(
                    tonic, dorian_steps, (scale_degree - 1).try_into().unwrap(), Direction::Up(()),
                );

            // Generate notes for the voicing
            let mut voicing_notes = ArrayTrait::<u8>::new();
            voicing_notes.append(root_note); // Add root note

            // Add intervals from the voicing pattern
            let pattern_intervals = selected_pattern;
            let pattern_len = pattern_intervals.len();
            let mut j = 0;
            loop {
                if j >= pattern_len {
                    break;
                }
                let interval = *pattern_intervals.at(j);
                let next_note = root_note + interval;
                voicing_notes.append(next_note);
                j += 1;
            }

            // Create NoteOn events for all notes in the voicing
            let voicing_notes_span = voicing_notes.span();
            let mut j = 0;
            loop {
                if j >= voicing_notes_span.len() {
                    break;
                }

                let note = *voicing_notes_span.at(j);
                let note_on = NoteOn { channel: 0, note: note, velocity: 80, time: current_time };
                eventlist.append(Message::NOTE_ON(note_on));
                j += 1;
            }

            // Create NoteOff events for all notes (slightly before next voicing)
            let mut j = 0;
            loop {
                if j >= voicing_notes_span.len() {
                    break;
                }

                let note = *voicing_notes_span.at(j);
                let note_off = NoteOff {
                    channel: 0,
                    note: note,
                    velocity: 0,
                    time: current_time + voicing_duration - 50 // Slightly before next voicing
                };
                eventlist.append(Message::NOTE_OFF(note_off));
                j += 1;
            }

            current_time += voicing_duration;
            i += 1;
        }

        let midiobj = Midi { events: eventlist.span() };

        // Generate parser format output
        generate_parser_format(@midiobj);
    }

    #[test]
    #[available_gas(1000000000000)]
    fn random_voicings_d_dorian_updated_test() {
        // Create a MIDI file with random voicings in D dorian using patterns from voicings.cairo
        // Each voicing changes every second (1000 time units)

        let mut eventlist = ArrayTrait::<Message>::new();

        // Set tempo to 120 BPM (500000 microseconds per beat)
        let tempo = SetTempo { tempo: 500000, time: Option::Some(0) };
        eventlist.append(Message::SET_TEMPO(tempo));

        // Initialize LCG with seed for reproducible randomness
        let mut lcg = LCG {
            state: 42, // Seed for reproducible results
            multiplier: 13,
            increment: 7,
            modulus: 100 // Very small modulus to avoid overflow
        };

        // D dorian key (D = note 2, octave 4)
        let tonic = PitchClass { note: 2, octave: 4 }; // D4
        let dorian_steps = dorian_steps(); // [2,1,2,2,2,1,2]

        // Use the actual voicing functions from src/midi/voicings.cairo
        let mut voicing_functions = ArrayTrait::<Span<koji::midi::types::PitchInterval>>::new();

        // Add all the voicing functions
        voicing_functions.append(triad_root_position());
        voicing_functions.append(triad_first_inversion());
        voicing_functions.append(triad_second_inversion());
        voicing_functions.append(maj_7_no_root_3rd_inversion());
        voicing_functions.append(maj_7_no_root_3rd_inversion2());
        voicing_functions.append(maj_7_no_root_3rd_inversion_add6());
        voicing_functions.append(maj_9_no_root_3rd_inversion_add6());
        voicing_functions.append(fourths_1());
        voicing_functions.append(plus_four_7());
        voicing_functions.append(plus_four_7_2());
        voicing_functions.append(seventh_and_third());

        let voicing_functions_span = voicing_functions.span();
        let num_voicings = voicing_functions_span.len();

        // Generate 8 voicings (8 seconds of music)
        let mut current_time: Time = 0;
        let voicing_duration: Time = 1000; // 1 second per voicing

        let mut i: u32 = 0;
        loop {
            if i == 8 {
                break;
            }

            // Randomly select a voicing pattern
            let voicing_index = lcg.value() % num_voicings;
            let selected_voicing = voicing_functions_span.at(voicing_index);
            lcg = lcg.next();

            // Randomly select a scale degree (1-7 for dorian mode)
            let scale_degree = (lcg.value() % 7) + 1; // 1-7
            lcg = lcg.next();

            // Calculate the root note for this scale degree
            let root_note = tonic
                .modal_transposition(
                    tonic, dorian_steps, (scale_degree - 1).try_into().unwrap(), Direction::Up(()),
                );

            // Generate notes for the voicing
            let mut voicing_notes = ArrayTrait::<u8>::new();
            voicing_notes.append(root_note); // Add root note

            // Add intervals from the voicing pattern using PitchInterval structs
            let pattern_intervals = selected_voicing;
            let pattern_len = pattern_intervals.len();
            let mut j = 0;
            loop {
                if j >= pattern_len {
                    break;
                }
                let pitch_interval = *pattern_intervals.at(j);
                let interval_size = pitch_interval.size;
                let interval_direction = pitch_interval.direction;

                // Calculate the next note based on the interval direction
                let next_note = match interval_direction {
                    Direction::Up(()) => root_note + interval_size,
                    Direction::Down(()) => root_note - interval_size,
                    Direction::Oblique(()) => root_note + interval_size // Default to up for oblique
                };
                voicing_notes.append(next_note);
                j += 1;
            }

            // Create NoteOn events for all notes in the voicing
            let voicing_notes_span = voicing_notes.span();
            let mut j = 0;
            loop {
                if j >= voicing_notes_span.len() {
                    break;
                }

                let note = *voicing_notes_span.at(j);
                let note_on = NoteOn { channel: 0, note: note, velocity: 80, time: current_time };
                eventlist.append(Message::NOTE_ON(note_on));
                j += 1;
            }

            // Create NoteOff events for all notes (slightly before next voicing)
            let mut j = 0;
            loop {
                if j >= voicing_notes_span.len() {
                    break;
                }

                let note = *voicing_notes_span.at(j);
                let note_off = NoteOff {
                    channel: 0,
                    note: note,
                    velocity: 0,
                    time: current_time + voicing_duration - 50 // Slightly before next voicing
                };
                eventlist.append(Message::NOTE_OFF(note_off));
                j += 1;
            }

            current_time += voicing_duration;
            i += 1;
        }

        let midiobj = Midi { events: eventlist.span() };

        // Generate clean Cairo code output
        generate_cairo_code(@midiobj);
    }

    // Helper function to add a voicing with proper timing using delta times
    fn add_voicing_with_delta_timing(
        eventlist: Array<Message>,
        voicing_notes: Array<u8>,
        note_on_delta: Time,
        note_off_delta: Time,
    ) -> Array<Message> {
        let mut events = eventlist;
        let voicing_notes_span = voicing_notes.span();
        let num_notes = voicing_notes_span.len();

        // Add all NoteOn events with the same delta time
        let mut k = 0;
        loop {
            if k >= num_notes {
                break;
            }
            let note = *voicing_notes_span.at(k);
            let note_on = NoteOn { channel: 0, note: note, velocity: 80, time: note_on_delta };
            events.append(Message::NOTE_ON(note_on));
            k += 1;
        }

        // Add all NoteOff events with the same delta time
        let mut l = 0;
        loop {
            if l >= num_notes {
                break;
            }
            let note = *voicing_notes_span.at(l);
            let note_off = NoteOff { channel: 0, note: note, velocity: 0, time: note_off_delta };
            events.append(Message::NOTE_OFF(note_off));
            l += 1;
        }

        events
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

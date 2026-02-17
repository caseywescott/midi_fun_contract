#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use koji::midi::note_abstraction::{
        NoteCollectionBuilderTrait, NoteCollectionTrait, NoteTrait, TimingUtilsImpl,
        create_chord_midi,
    };
    use koji::midi::types::{Message, Midi, SetTempo};

    #[test]
    #[available_gas(1000000000000)]
    fn test_note_creation() {
        let note = NoteTrait::new(60, 100, 200, 80, 0);
        assert(note.keynum == 60, 'Wrong keynum');
        assert(note.start_time == 100, 'Wrong start_time');
        assert(note.duration == 200, 'Wrong duration');
        assert(note.velocity == 80, 'Wrong velocity');
        assert(note.channel == 0, 'Wrong channel');
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_note_end_time() {
        let note = NoteTrait::new(60, 100, 200, 80, 0);
        assert(note.end_time() == 300, 'Wrong end time');
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_note_to_midi_events() {
        let note = NoteTrait::new(60, 100, 200, 80, 0);
        let (note_on, note_off) = note.to_midi_events();

        // Check NoteOn event
        assert(note_on.channel == 0, 'Wrong NoteOn channel');
        assert(note_on.note == 60, 'Wrong NoteOn note');
        assert(note_on.velocity == 80, 'Wrong NoteOn velocity');
        assert(note_on.time == 100, 'Wrong NoteOn time');

        // Check NoteOff event
        assert(note_off.channel == 0, 'Wrong NoteOff channel');
        assert(note_off.note == 60, 'Wrong NoteOff note');
        assert(note_off.velocity == 0, 'Wrong NoteOff velocity');
        assert(note_off.time == 200, 'Wrong NoteOff time');
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_create_chord_midi() {
        // Create a C major triad (C4, E4, G4)
        let mut chord_notes = ArrayTrait::<u8>::new();
        chord_notes.append(60); // C4
        chord_notes.append(64); // E4
        chord_notes.append(67); // G4

        let events = create_chord_midi(chord_notes.span(), 10, 100, 80, 0);
        let events_span = events.span();

        // Check number of events
        assert(events_span.len() == 6, 'Wrong number of events'); // 3 NoteOn + 3 NoteOff

        // Check NoteOn events
        let mut i = 0;
        let mut first_note = true;
        while i != 3 { // Check all NoteOn events
            match *events_span.at(i) {
                Message::NOTE_ON(note_on) => {
                    if first_note {
                        assert(note_on.time == 10, 'Wrong first NoteOn time');
                        first_note = false;
                    } else {
                        assert(note_on.time == 0, 'Wrong subsequent NoteOn time');
                    }
                },
                _ => { assert(false, 'Expected NoteOn event'); },
            }
            i += 1;
        }

        // Check NoteOff events
        let mut first_note_off = true;
        while i != 6 { // Check all NoteOff events
            match *events_span.at(i) {
                Message::NOTE_OFF(note_off) => {
                    if first_note_off {
                        assert(note_off.time == 100, 'Wrong first NoteOff time');
                        first_note_off = false;
                    } else {
                        assert(note_off.time == 0, 'Wrong subsequent NoteOff time');
                    }
                },
                _ => { assert(false, 'Expected NoteOff event'); },
            }
            i += 1;
        }
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_note_collection() {
        // Create a sequence of notes
        let mut notes = ArrayTrait::new();
        notes.append(NoteTrait::new(60, 0, 100, 80, 0)); // C4
        notes.append(NoteTrait::new(64, 100, 100, 80, 0)); // E4
        notes.append(NoteTrait::new(67, 200, 100, 80, 0)); // G4

        let collection = NoteCollectionTrait::new(notes.span());
        let midi = collection.to_midi(500000); // 120 BPM

        // Check MIDI events
        let events = midi.events;
        assert(events.len() == 7, 'Wrong number of events'); // 1 tempo + 3 NoteOn + 3 NoteOff

        // Check tempo event
        match *events.at(0) {
            Message::SET_TEMPO(tempo) => {
                assert(tempo.tempo == 500000, 'Wrong tempo');
                assert(tempo.time == Option::Some(0), 'Wrong tempo time');
            },
            _ => { assert(false, 'Expected tempo event'); },
        }

        // Check note events
        let mut i = 1;
        while i < 7 {
            match *events.at(i) {
                Message::NOTE_ON(note_on) => {
                    assert(note_on.velocity == 80, 'Wrong velocity');
                    assert(note_on.channel == 0, 'Wrong channel');
                },
                Message::NOTE_OFF(note_off) => {
                    assert(note_off.velocity == 0, 'Wrong velocity');
                    assert(note_off.channel == 0, 'Wrong channel');
                },
                _ => { assert(false, 'Expected note event'); },
            }
            i += 1;
        }
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_note_collection_builder() {
        let mut builder = NoteCollectionBuilderTrait::new();

        // Add individual notes
        let note1 = NoteTrait::new(60, 0, 100, 80, 0); // C4
        let note2 = NoteTrait::new(64, 100, 100, 80, 0); // E4
        builder.add_note(note1);
        builder.add_note(note2);

        // Add a chord
        let mut chord_notes = ArrayTrait::new();
        chord_notes.append(67); // G4
        chord_notes.append(71); // B4
        builder.add_chord(chord_notes.span(), 200, 100, 80, 0);

        // Build and check the collection
        let collection = builder.build();
        let notes = collection.notes;

        assert(notes.len() == 4, 'Wrong number of notes');

        // Check first note (C4)
        let first = *notes.at(0);
        assert(first.keynum == 60, 'Wrong first note keynum');
        assert(first.start_time == 0, 'Wrong first note start');
        assert(first.duration == 100, 'Wrong first note duration');

        // Check second note (E4)
        let second = *notes.at(1);
        assert(second.keynum == 64, 'Wrong second note keynum');
        assert(second.start_time == 100, 'Wrong second note start');
        assert(second.duration == 100, 'Wrong second note duration');

        // Check chord notes (G4, B4)
        let third = *notes.at(2);
        let fourth = *notes.at(3);
        assert(third.keynum == 67, 'Wrong third note keynum');
        assert(fourth.keynum == 71, 'Wrong fourth note keynum');
        assert(third.start_time == 200, 'Wrong chord start time');
        assert(fourth.start_time == 200, 'Wrong chord start time');
        assert(third.duration == 100, 'Wrong chord duration');
        assert(fourth.duration == 100, 'Wrong chord duration');
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_timing_utils() {
        let mut notes = ArrayTrait::new();
        notes.append(NoteTrait::new(60, 200, 100, 80, 0)); // C4 at t=200
        notes.append(NoteTrait::new(64, 0, 100, 80, 0)); // E4 at t=0
        notes.append(NoteTrait::new(67, 0, 100, 80, 0)); // G4 at t=0
        notes.append(NoteTrait::new(71, 200, 100, 80, 0)); // B4 at t=200

        let note_groups = TimingUtilsImpl::sort_and_group_notes(notes.span());
        assert(note_groups.len() == 2, 'Wrong number of groups');

        // Check first group (t=0)
        let group1 = note_groups.at(0);
        assert(group1.len() == 2, 'Wrong group1 size');
        let note1 = *group1.at(0);
        let note2 = *group1.at(1);
        assert(note1.start_time == 0, 'Wrong group1 start time');
        assert(note2.start_time == 0, 'Wrong group1 start time');
        assert(note1.keynum == 64 || note1.keynum == 67, 'Wrong group1 note1');
        assert(note2.keynum == 64 || note2.keynum == 67, 'Wrong group1 note2');
        assert(note1.keynum != note2.keynum, 'Duplicate notes in group1');

        // Check second group (t=200)
        let group2 = note_groups.at(1);
        assert(group2.len() == 2, 'Wrong group2 size');
        let note1 = *group2.at(0);
        let note2 = *group2.at(1);
        assert(note1.start_time == 200, 'Wrong group2 start time');
        assert(note2.start_time == 200, 'Wrong group2 start time');
        assert(note1.keynum == 60 || note1.keynum == 71, 'Wrong group2 note1');
        assert(note2.keynum == 60 || note2.keynum == 71, 'Wrong group2 note2');
        assert(note1.keynum != note2.keynum, 'Duplicate notes in group2');

        // Test delta time calculation
        let delta1 = TimingUtilsImpl::calculate_delta_time(0, 100);
        let delta2 = TimingUtilsImpl::calculate_delta_time(100, 200);
        let delta3 = TimingUtilsImpl::calculate_delta_time(200, 100);
        assert(delta1 == 100, 'Wrong delta time 1');
        assert(delta2 == 100, 'Wrong delta time 2');
        assert(delta3 == 0, 'Wrong delta time 3');
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_note_collection_with_delta_times() {
        let mut notes = ArrayTrait::new();
        notes.append(NoteTrait::new(60, 0, 100, 80, 0)); // C4 at t=0
        notes.append(NoteTrait::new(64, 0, 100, 80, 0)); // E4 at t=0
        notes.append(NoteTrait::new(67, 200, 100, 80, 0)); // G4 at t=200
        notes.append(NoteTrait::new(71, 200, 100, 80, 0)); // B4 at t=200

        let collection = NoteCollectionTrait::new(notes.span());
        let midi = collection.to_midi_with_delta_times(500000);
        let events = midi.events;

        // Check number of events
        assert(events.len() == 9, 'Wrong number of events'); // 1 tempo + 4 NoteOn + 4 NoteOff

        // Check tempo event
        match *events.at(0) {
            Message::SET_TEMPO(tempo) => {
                assert(tempo.tempo == 500000, 'Wrong tempo');
                assert(tempo.time == Option::Some(0), 'Wrong tempo time');
            },
            _ => { assert(false, 'Expected tempo event'); },
        }

        // Check first chord (t=0)
        match *events.at(1) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong first chord time'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }
        match *events.at(2) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong first chord time'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }

        // Check second chord (t=200)
        match *events.at(5) {
            Message::NOTE_ON(note_on) => {
                assert(note_on.time == 100, 'Wrong second chord time');
            },
            _ => { assert(false, 'Expected NoteOn event'); },
        }
        match *events.at(6) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong second chord time'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_multiple_chords_timing() {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Add tempo event
        let tempo = SetTempo { tempo: 60, time: Option::Some(0) };
        eventlist.append(Message::SET_TEMPO(tempo));

        // First chord: C major (C4, E4, G4) at t=0
        let mut chord1 = ArrayTrait::<u8>::new();
        chord1.append(60);
        chord1.append(64);
        chord1.append(67);
        let chord1_events = create_chord_midi(chord1.span(), 0, 10, 80, 0);
        let mut chord1_events_span = chord1_events.span();
        while let Option::Some(event) = chord1_events_span.pop_front() {
            eventlist.append(*event);
        }

        // Second chord: F major (F4, A4, C5) at t=1000
        let mut chord2 = ArrayTrait::<u8>::new();
        chord2.append(65);
        chord2.append(69);
        chord2.append(72);
        let chord2_events = create_chord_midi(chord2.span(), 10, 10, 80, 0);
        let mut chord2_events_span = chord2_events.span();
        while let Option::Some(event) = chord2_events_span.pop_front() {
            eventlist.append(*event);
        }

        let midiobj = Midi { events: eventlist.span() };
        let events = midiobj.events;

        // Check number of events
        // Order: tempo, chord1 (3 NoteOn + 3 NoteOff), chord2 (3 NoteOn + 3 NoteOff)
        assert(events.len() == 13, 'Wrong number of events');

        // Chord 1 NoteOn at indices 1-3 (first has time 0, rest 0)
        match *events.at(1) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong first chord first NoteOn'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }
        match *events.at(2) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong chord1 NoteOn'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }
        match *events.at(3) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong chord1 NoteOn'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }

        // Chord 1 NoteOff at indices 4-6 (first has time 10, rest 0)
        match *events.at(4) {
            Message::NOTE_OFF(note_off) => { assert(note_off.time == 10, 'Wrong first chord first NoteOff'); },
            _ => { assert(false, 'Expected NoteOff event'); },
        }
        match *events.at(5) {
            Message::NOTE_OFF(note_off) => { assert(note_off.time == 0, 'Wrong chord1 NoteOff'); },
            _ => { assert(false, 'Expected NoteOff event'); },
        }
        match *events.at(6) {
            Message::NOTE_OFF(note_off) => { assert(note_off.time == 0, 'Wrong chord1 NoteOff'); },
            _ => { assert(false, 'Expected NoteOff event'); },
        }

        // Chord 2 NoteOn at indices 7-9 (first has time 10, rest 0)
        match *events.at(7) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 10, 'Wrong second chord first NoteOn'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }
        match *events.at(8) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong chord2 NoteOn'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }
        match *events.at(9) {
            Message::NOTE_ON(note_on) => { assert(note_on.time == 0, 'Wrong chord2 NoteOn'); },
            _ => { assert(false, 'Expected NoteOn event'); },
        }

        // Chord 2 NoteOff at indices 10-12 (first has time 10, rest 0)
        match *events.at(10) {
            Message::NOTE_OFF(note_off) => { assert(note_off.time == 10, 'Wrong chord2 first NoteOff'); },
            _ => { assert(false, 'Expected NoteOff event'); },
        }
        match *events.at(11) {
            Message::NOTE_OFF(note_off) => { assert(note_off.time == 0, 'Wrong chord2 NoteOff'); },
            _ => { assert(false, 'Expected NoteOff event'); },
        }
        match *events.at(12) {
            Message::NOTE_OFF(note_off) => { assert(note_off.time == 0, 'Wrong chord2 NoteOff'); },
            _ => { assert(false, 'Expected NoteOff event'); },
        }
    }
}

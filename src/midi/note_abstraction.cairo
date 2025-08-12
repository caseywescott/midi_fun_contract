use core::array::{ArrayTrait, SpanTrait};
use koji::math::Time;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

/// Represents a single musical note with timing and MIDI properties
#[derive(Copy, Drop, Clone)]
pub struct Note {
    pub keynum: u8, // MIDI note number (0-127)
    pub start_time: Time, // When the note starts (in microseconds)
    pub duration: Time, // How long the note lasts (in microseconds)
    pub velocity: u8, // Note velocity (0-127)
    pub channel: u8 // MIDI channel (0-15)
}

/// Trait for Note operations
pub trait NoteTrait {
    /// Creates a new Note instance
    fn new(keynum: u8, start_time: Time, duration: Time, velocity: u8, channel: u8) -> Note;

    /// Converts the note to MIDI NoteOn and NoteOff events
    fn to_midi_events(self: Note) -> (NoteOn, NoteOff);

    /// Gets the end time of the note (start_time + duration)
    fn end_time(self: Note) -> Time;
}

impl NoteImpl of NoteTrait {
    fn new(keynum: u8, start_time: Time, duration: Time, velocity: u8, channel: u8) -> Note {
        Note { keynum, start_time, duration, velocity, channel }
    }

    fn to_midi_events(self: Note) -> (NoteOn, NoteOff) {
        let note_on = NoteOn {
            channel: self.channel,
            note: self.keynum,
            velocity: self.velocity,
            time: self.start_time,
        };

        let note_off = NoteOff {
            channel: self.channel, note: self.keynum, velocity: 0, time: self.duration,
        };

        (note_on, note_off)
    }

    fn end_time(self: Note) -> Time {
        self.start_time + self.duration
    }
}

/// A collection of notes that can be converted to MIDI events
#[derive(Drop)]
pub struct NoteCollection {
    pub notes: Span<Note>,
}

/// Trait for NoteCollection operations
pub trait NoteCollectionTrait {
    /// Creates a new NoteCollection from a span of notes
    fn new(notes: Span<Note>) -> NoteCollection;

    /// Converts the note collection to MIDI events with absolute timing
    fn to_midi(self: NoteCollection, tempo: u32) -> Midi;

    /// Converts the note collection to MIDI events with proper delta timing
    fn to_midi_with_delta_times(self: NoteCollection, tempo: u32) -> Midi;
}

/// Utility functions for sorting and timing calculations
pub trait TimingUtilsTrait {
    /// Sorts notes by start time and groups them into chords
    fn sort_and_group_notes(notes: Span<Note>) -> Span<Span<Note>>;

    /// Calculates delta time between two absolute times
    fn calculate_delta_time(current_time: Time, next_time: Time) -> Time;
}

#[derive(Copy, Drop)]
pub struct TimingUtils {}

pub impl TimingUtilsImpl of TimingUtilsTrait {
    fn sort_and_group_notes(notes: Span<Note>) -> Span<Span<Note>> {
        let mut result: Array<Array<Note>> = ArrayTrait::new();
        let mut current_group: Array<Note> = ArrayTrait::new();
        let mut first_note = true;

        // Find earliest note
        let mut earliest_time = 0;
        let mut i = 0;
        while i < notes.len() {
            let note = *notes.at(i);
            if first_note || note.start_time < earliest_time {
                earliest_time = note.start_time;
                first_note = false;
            }
            i += 1;
        }

        // Group notes by start time
        let mut current_time = earliest_time;
        let mut all_notes_processed = false;

        while !all_notes_processed {
            all_notes_processed = true;
            let mut i = 0;
            while i < notes.len() {
                let note = *notes.at(i);
                if note.start_time == current_time {
                    current_group.append(note);
                } else if note.start_time > current_time {
                    all_notes_processed = false;
                }
                i += 1;
            }

            if current_group.len() > 0 {
                let group_copy = current_group;
                result.append(group_copy);
                current_group = ArrayTrait::new();

                // Find next start time
                let mut next_time = 0;
                let mut first = true;
                let mut i = 0;
                while i < notes.len() {
                    let note = *notes.at(i);
                    if note.start_time > current_time {
                        if first || note.start_time < next_time {
                            next_time = note.start_time;
                            first = false;
                        }
                    }
                    i += 1;
                }
                current_time = next_time;
            } else {
                // No notes found at current time, find next time
                let mut next_time = 0;
                let mut first = true;
                let mut i = 0;
                while i < notes.len() {
                    let note = *notes.at(i);
                    if note.start_time > current_time {
                        if first || note.start_time < next_time {
                            next_time = note.start_time;
                            first = false;
                        }
                    }
                    i += 1;
                }
                current_time = next_time;
            }
        }

        // Convert result to spans
        let mut span_result: Array<Span<Note>> = ArrayTrait::new();
        let mut i = 0;
        while i < result.len() {
            let group = result.at(i);
            span_result.append(group.span());
            i += 1;
        }

        span_result.span()
    }

    fn calculate_delta_time(current_time: Time, next_time: Time) -> Time {
        if next_time > current_time {
            next_time - current_time
        } else {
            0
        }
    }
}

impl NoteCollectionImpl of NoteCollectionTrait {
    fn new(notes: Span<Note>) -> NoteCollection {
        NoteCollection { notes }
    }

    fn to_midi(self: NoteCollection, tempo: u32) -> Midi {
        let mut events: Array<Message> = ArrayTrait::new();

        // Add tempo event
        let tempo_event = SetTempo { tempo, time: Option::Some(0) };
        events.append(Message::SET_TEMPO(tempo_event));

        // Add note events with absolute timing
        let mut i = 0;
        while i < self.notes.len() {
            let note = *self.notes.at(i);
            let (note_on, note_off) = note.to_midi_events();
            events.append(Message::NOTE_ON(note_on));
            events.append(Message::NOTE_OFF(note_off));
            i += 1;
        }

        Midi { events: events.span() }
    }

    fn to_midi_with_delta_times(self: NoteCollection, tempo: u32) -> Midi {
        let mut events: Array<Message> = ArrayTrait::new();

        // Add tempo event
        let tempo_event = SetTempo { tempo, time: Option::Some(0) };
        events.append(Message::SET_TEMPO(tempo_event));

        // Sort and group notes into chords
        let note_groups = TimingUtilsImpl::sort_and_group_notes(self.notes);

        // Process each group (chord)
        let mut current_time = 0;
        let mut i = 0;
        while i < note_groups.len() {
            let group = *note_groups.at(i);
            let first_note = *group.at(0);
            let delta_time = TimingUtilsImpl::calculate_delta_time(
                current_time, first_note.start_time,
            );

            // Add NoteOn events for the chord - all notes start together
            let mut j = 0;
            while j < group.len() {
                let note = *group.at(j);
                let mut note_on = NoteOn {
                    channel: note.channel,
                    note: note.keynum,
                    velocity: note.velocity,
                    time: if j == 0 {
                        delta_time
                    } else {
                        0
                    },
                };
                events.append(Message::NOTE_ON(note_on));
                j += 1;
            }

            // Add NoteOff events for the chord - all notes end together
            let mut j = 0;
            while j < group.len() {
                let note = *group.at(j);
                let mut note_off = NoteOff {
                    channel: note.channel,
                    note: note.keynum,
                    velocity: 0,
                    time: if j == 0 {
                        note.duration
                    } else {
                        0
                    },
                };
                events.append(Message::NOTE_OFF(note_off));
                j += 1;
            }

            current_time = first_note.start_time + first_note.duration;
            i += 1;
        }

        Midi { events: events.span() }
    }
}

/// A builder for creating note collections
#[derive(Drop)]
pub struct NoteCollectionBuilder {
    pub notes: Array<Note>,
}

/// Trait for NoteCollectionBuilder operations
pub trait NoteCollectionBuilderTrait {
    /// Creates a new empty NoteCollectionBuilder
    fn new() -> NoteCollectionBuilder;

    /// Adds a single note to the collection
    fn add_note(ref self: NoteCollectionBuilder, note: Note);

    /// Adds a chord (multiple notes with same start time and duration)
    fn add_chord(
        ref self: NoteCollectionBuilder,
        keynums: Span<u8>,
        start_time: Time,
        duration: Time,
        velocity: u8,
        channel: u8,
    );

    /// Builds and returns a NoteCollection
    fn build(self: NoteCollectionBuilder) -> NoteCollection;
}

impl NoteCollectionBuilderImpl of NoteCollectionBuilderTrait {
    fn new() -> NoteCollectionBuilder {
        NoteCollectionBuilder { notes: ArrayTrait::new() }
    }

    fn add_note(ref self: NoteCollectionBuilder, note: Note) {
        self.notes.append(note);
    }

    fn add_chord(
        ref self: NoteCollectionBuilder,
        keynums: Span<u8>,
        start_time: Time,
        duration: Time,
        velocity: u8,
        channel: u8,
    ) {
        let mut i = 0;
        while i < keynums.len() {
            let keynum = *keynums.at(i);
            let note = NoteTrait::new(keynum, start_time, duration, velocity, channel);
            self.notes.append(note);
            i += 1;
        }
    }

    fn build(self: NoteCollectionBuilder) -> NoteCollection {
        NoteCollection { notes: self.notes.span() }
    }
}

/// Creates a MIDI sequence with perfect chordal timing
pub fn create_chord_midi(
    keynums: Span<u8>, start_time: Time, duration: Time, velocity: u8, channel: u8,
) -> Array<Message> {
    let mut events: Array<Message> = ArrayTrait::new();

    // Add NoteOn events for all notes in the chord (perfect chordal timing)
    let mut first_note = true;
    let mut i = 0;
    while i < keynums.len() {
        let keynum = *keynums.at(i);
        let note_on = NoteOn {
            channel: channel,
            note: keynum,
            velocity: velocity,
            time: if first_note {
                start_time
            } else {
                0
            },
        };
        ArrayTrait::append(ref events, Message::NOTE_ON(note_on));
        first_note = false;
        i += 1;
    }

    // Add NoteOff events for all notes in the chord (perfect chordal timing)
    let mut first_note_off = true;
    let mut i = 0;
    while i < keynums.len() {
        let keynum = *keynums.at(i);
        let note_off = NoteOff {
            channel: channel,
            note: keynum,
            velocity: 0,
            time: if first_note_off {
                duration
            } else {
                0
            },
        };
        ArrayTrait::append(ref events, Message::NOTE_OFF(note_off));
        first_note_off = false;
        i += 1;
    }

    events
}

use core::array::{ArrayTrait, SpanTrait};
use core::clone::Clone;
use core::option::OptionTrait;
use core::traits::Into;

use koji::math::Time;
use koji::midi::types::{Midi, Message, NoteOn, NoteOff, SetTempo};

/// =========================================
/// ============ NOTE ABSTRACTION ===========
/// =========================================

/// Represents a musical note with keynum, start time, and duration
#[derive(Copy, Drop, Serde)]
pub struct Note {
    pub keynum: u8,
    pub start_time: Time,
    pub duration: Time,
    pub velocity: u8,
    pub channel: u8,
}

/// Collection of notes that can be converted to MIDI events
#[derive(Copy, Drop, Serde)]
pub struct NoteCollection {
    pub notes: Span<Note>,
}

/// Builder for creating note collections
#[derive(Copy, Drop, Serde)]
pub struct NoteCollectionBuilder {
    pub notes: Array<Note>,
}

/// =========================================
/// ============ IMPLEMENTATIONS ============
/// =========================================

impl NoteImpl of NoteTrait {
    fn new(keynum: u8, start_time: Time, duration: Time, velocity: u8, channel: u8) -> Note {
        Note { keynum, start_time, duration, velocity, channel }
    }

    fn to_midi_events(self: @Note) -> (NoteOn, NoteOff) {
        let note = *self;
        let note_on = NoteOn {
            channel: note.channel,
            note: note.keynum,
            velocity: note.velocity,
            time: note.start_time,
        };
        let note_off = NoteOff {
            channel: note.channel,
            note: note.keynum,
            velocity: 0,
            time: note.duration,
        };
        (note_on, note_off)
    }
}

impl NoteCollectionBuilderImpl of NoteCollectionBuilderTrait {
    fn new() -> NoteCollectionBuilder {
        NoteCollectionBuilder { notes: ArrayTrait::new() }
    }

    fn add_note(ref self: NoteCollectionBuilder, note: Note) {
        ArrayTrait::append(ref self.notes, note);
    }

    fn add_chord(
        ref self: NoteCollectionBuilder, keynums: Span<u8>, start_time: Time, duration: Time, velocity: u8, channel: u8
    ) {
        let mut keynums_span = keynums.clone();
        loop {
            match keynums_span.pop_front() {
                Option::Some(keynum) => {
                    let note = Note::new(*keynum, start_time, duration, velocity, channel);
                    ArrayTrait::append(ref self.notes, note);
                },
                Option::None => { break; },
            };
        }
    }

    fn build(self: NoteCollectionBuilder) -> NoteCollection {
        NoteCollection { notes: self.notes.span() }
    }
}

impl NoteCollectionImpl of NoteCollectionTrait {
    fn to_midi(self: @NoteCollection, tempo: u32) -> Midi {
        let collection = *self;
        let mut events: Array<Message> = ArrayTrait::new();
        
        // Add tempo event
        let tempo_event = Message::SET_TEMPO(SetTempo { tempo, time: Option::Some(0) });
        ArrayTrait::append(ref events, tempo_event);
        
        // Convert all notes to MIDI events
        let mut notes_span = collection.notes.clone();
        loop {
            match notes_span.pop_front() {
                Option::Some(note) => {
                    let (note_on, note_off) = note.to_midi_events();
                    ArrayTrait::append(ref events, Message::NOTE_ON(note_on));
                    ArrayTrait::append(ref events, Message::NOTE_OFF(note_off));
                },
                Option::None => { break; },
            };
        }
        
        Midi { events: events.span() }
    }

    fn to_midi_with_delta_times(self: @NoteCollection, tempo: u32) -> Midi {
        let collection = *self;
        let mut events: Array<Message> = ArrayTrait::new();
        
        // Add tempo event
        let tempo_event = Message::SET_TEMPO(SetTempo { tempo, time: Option::Some(0) });
        ArrayTrait::append(ref events, tempo_event);
        
        // Sort notes by start time for proper delta time calculation
        let mut sorted_notes = sort_notes_by_start_time(collection.notes);
        let mut current_time: Time = 0;
        
        // Group notes by start time to handle chords
        let mut i = 0;
        let notes_len = sorted_notes.len();
        
        loop {
            if i >= notes_len {
                break;
            }
            
            let current_note = *sorted_notes.at(i);
            let chord_start_time = current_note.start_time;
            
            // Calculate delta time from current time to chord start time
            let delta_to_chord = chord_start_time - current_time;
            
            // Collect all notes that start at the same time (chord)
            let mut chord_notes: Array<Note> = ArrayTrait::new();
            let mut j = i;
            
            loop {
                if j >= notes_len {
                    break;
                }
                
                let note = *sorted_notes.at(j);
                if note.start_time == chord_start_time {
                    ArrayTrait::append(ref chord_notes, note);
                    j += 1;
                } else {
                    break;
                }
            }
            
            // Add all NoteOn events for the chord
            let mut chord_notes_span = chord_notes.span();
            let first_note = *chord_notes_span.at(0);
            let first_note_on = NoteOn {
                channel: first_note.channel,
                note: first_note.keynum,
                velocity: first_note.velocity,
                time: delta_to_chord,
            };
            ArrayTrait::append(ref events, Message::NOTE_ON(first_note_on));
            
            // Add remaining NoteOn events with delta time 0
            let mut k = 1;
            loop {
                if k >= chord_notes_span.len() {
                    break;
                }
                let note = *chord_notes_span.at(k);
                let note_on = NoteOn {
                    channel: note.channel,
                    note: note.keynum,
                    velocity: note.velocity,
                    time: 0,
                };
                ArrayTrait::append(ref events, Message::NOTE_ON(note_on));
                k += 1;
            }
            
            // Add all NoteOff events for the chord
            let mut chord_notes_span_off = chord_notes.span();
            let first_note_off = NoteOff {
                channel: first_note.channel,
                note: first_note.keynum,
                velocity: 0,
                time: first_note.duration,
            };
            ArrayTrait::append(ref events, Message::NOTE_OFF(first_note_off));
            
            // Add remaining NoteOff events with delta time 0
            let mut k = 1;
            loop {
                if k >= chord_notes_span_off.len() {
                    break;
                }
                let note = *chord_notes_span_off.at(k);
                let note_off = NoteOff {
                    channel: note.channel,
                    note: note.keynum,
                    velocity: 0,
                    time: 0,
                };
                ArrayTrait::append(ref events, Message::NOTE_OFF(note_off));
                k += 1;
            }
            
            current_time = chord_start_time + first_note.duration;
            i = j;
        }
        
        Midi { events: events.span() }
    }
}

/// =========================================
/// ============== TRAITS ===================
/// =========================================

pub trait NoteTrait {
    fn new(keynum: u8, start_time: Time, duration: Time, velocity: u8, channel: u8) -> Note;
    fn to_midi_events(self: @Note) -> (NoteOn, NoteOff);
}

pub trait NoteCollectionBuilderTrait {
    fn new() -> NoteCollectionBuilder;
    fn add_note(ref self: NoteCollectionBuilder, note: Note);
    fn add_chord(
        ref self: NoteCollectionBuilder, keynums: Span<u8>, start_time: Time, duration: Time, velocity: u8, channel: u8
    );
    fn build(self: NoteCollectionBuilder) -> NoteCollection;
}

pub trait NoteCollectionTrait {
    fn to_midi(self: @NoteCollection, tempo: u32) -> Midi;
    fn to_midi_with_delta_times(self: @NoteCollection, tempo: u32) -> Midi;
}

/// =========================================
/// ============ HELPER FUNCTIONS ===========
/// =========================================

/// Sort notes by start time (simple bubble sort for small collections)
fn sort_notes_by_start_time(notes: Span<Note>) -> Array<Note> {
    let mut sorted: Array<Note> = ArrayTrait::new();
    let mut notes_span = notes.clone();
    
    // Copy notes to array
    loop {
        match notes_span.pop_front() {
            Option::Some(note) => {
                ArrayTrait::append(ref sorted, *note);
            },
            Option::None => { break; },
        };
    }
    
    // Simple bubble sort by start time
    let len = sorted.len();
    let mut i = 0;
    loop {
        if i >= len {
            break;
        }
        let mut j = 0;
        loop {
            if j >= len - i - 1 {
                break;
            }
            let note1 = *sorted.at(j);
            let note2 = *sorted.at(j + 1);
            if note1.start_time > note2.start_time {
                // Swap notes
                let temp = note1;
                sorted.set(j, note2);
                sorted.set(j + 1, temp);
            }
            j += 1;
        }
        i += 1;
    }
    
    sorted
}

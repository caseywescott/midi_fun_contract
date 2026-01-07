# Note Abstraction System

## Overview

The Note Abstraction System provides a clean, type-safe way to represent musical notes and convert them to MIDI events. It separates musical content (notes with keynum, start time, and duration) from the MIDI representation, making it easier to create complex musical pieces with proper timing.

## Core Concepts

### Note Struct

The `Note` struct represents a single musical note with the following properties:

```cairo
pub struct Note {
    pub keynum: u8,        // MIDI note number (0-127)
    pub start_time: Time,  // When the note starts (in microseconds)
    pub duration: Time,    // How long the note lasts (in microseconds)
    pub velocity: u8,      // Note velocity (0-127)
    pub channel: u8,       // MIDI channel (0-15)
}
```

### NoteCollection

A `NoteCollection` stores multiple notes that can be converted to MIDI events:

```cairo
pub struct NoteCollection {
    pub notes: Span<Note>,
}
```

### NoteCollectionBuilder

A builder pattern for easily creating note collections:

```cairo
pub struct NoteCollectionBuilder {
    pub notes: Array<Note>,
}
```

## Key Features

### 1. Perfect Chordal Timing

The system ensures that all notes in a chord start and end simultaneously:

```cairo
// All notes in a chord have the same start_time and duration
Note { keynum: 60, start_time: 0, duration: 1000, velocity: 80, channel: 0 },  // C
Note { keynum: 64, start_time: 0, duration: 1000, velocity: 80, channel: 0 },  // E
Note { keynum: 67, start_time: 0, duration: 1000, velocity: 80, channel: 0 },  // G
```

### 2. Automatic Delta Time Calculation

The system automatically calculates proper delta times for MIDI events:

- First NoteOn in a chord: delta time from previous event
- Subsequent NoteOn events in same chord: delta time 0
- First NoteOff in a chord: delta time from last NoteOn
- Subsequent NoteOff events in same chord: delta time 0

### 3. Type Safety

All components are strongly typed, providing compile-time guarantees about musical structure.

## Usage Examples

### Creating a Simple Chord

```cairo
use koji::midi::note_abstraction::{
    Note, NoteTrait, NoteCollection, NoteCollectionTrait, 
    NoteCollectionBuilder, NoteCollectionBuilderTrait
};

// Create a C major chord
let mut builder = NoteCollectionBuilder::new();

let chord_keynums = array![60, 64, 67].span(); // C, E, G
builder.add_chord(chord_keynums, 0, 1000, 80, 0);

let collection = builder.build();
let midi = collection.to_midi_with_delta_times(500000); // 120 BPM
```

### Creating a Musical Progression

```cairo
// Create a I-IV-V progression
let mut builder = NoteCollectionBuilder::new();

// C major chord (I)
let c_major = array![60, 64, 67].span();
builder.add_chord(c_major, 0, 1000, 80, 0);

// F major chord (IV)
let f_major = array![65, 69, 72].span();
builder.add_chord(f_major, 1000, 1000, 80, 0);

// G major chord (V)
let g_major = array![67, 71, 74].span();
builder.add_chord(g_major, 2000, 1000, 80, 0);

let collection = builder.build();
let midi = collection.to_midi_with_delta_times(500000);
```

### Individual Notes

```cairo
// Add individual notes
let note1 = Note::new(60, 0, 500, 80, 0);      // C, 0.5 seconds
let note2 = Note::new(64, 500, 500, 80, 0);    // E, 0.5 seconds
let note3 = Note::new(67, 1000, 500, 80, 0);   // G, 0.5 seconds

let mut builder = NoteCollectionBuilder::new();
builder.add_note(note1);
builder.add_note(note2);
builder.add_note(note3);

let collection = builder.build();
let midi = collection.to_midi_with_delta_times(500000);
```

## MIDI Output

The system provides two methods for converting to MIDI:

### `to_midi(tempo: u32) -> Midi`

Converts notes to MIDI events with absolute timing. Each note's start_time and duration are used directly.

### `to_midi_with_delta_times(tempo: u32) -> Midi`

Converts notes to MIDI events with proper delta timing. This method:

1. Sorts notes by start time
2. Groups notes that start at the same time (chords)
3. Calculates proper delta times for MIDI events
4. Ensures perfect chordal timing

## Benefits

### 1. Clean Separation of Concerns

- Musical content (notes) is separate from MIDI representation
- Easy to modify musical structure without worrying about MIDI timing
- Clear, readable code that expresses musical intent

### 2. Type Safety

- Compile-time guarantees about note structure
- Prevents invalid MIDI note numbers, velocities, or channels
- Structured approach to musical composition

### 3. Reusability

- Note collections can be combined and modified
- Builder pattern makes complex structures easy to create
- Components can be reused across different musical pieces

### 4. Perfect Timing

- Automatic handling of chordal timing
- Proper delta time calculation
- No more manual timing calculations

## Integration with Existing MIDI System

The note abstraction system integrates seamlessly with the existing MIDI types:

```cairo
use koji::midi::types::{Midi, Message, NoteOn, NoteOff, SetTempo};
use koji::midi::note_abstraction::{Note, NoteTrait};

// Convert individual notes to MIDI events
let note = Note::new(60, 0, 1000, 80, 0);
let (note_on, note_off) = note.to_midi_events();

// Use with existing MIDI structures
let mut events = array![
    Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }),
    Message::NOTE_ON(note_on),
    Message::NOTE_OFF(note_off),
];

let midi = Midi { events: events.span() };
```

## Future Enhancements

The note abstraction system can be extended with:

1. **Musical Patterns**: Predefined chord progressions, scales, and arpeggios
2. **Rhythm Support**: Time signatures, beats, and rhythmic patterns
3. **Harmony Generation**: Automatic chord generation from melodies
4. **Performance Optimization**: Efficient algorithms for large note collections
5. **Musical Analysis**: Tools for analyzing note collections and patterns

## Conclusion

The Note Abstraction System provides a powerful, type-safe foundation for musical composition in Cairo. It bridges the gap between musical concepts and MIDI representation, making it easier to create complex musical pieces with proper timing and structure.

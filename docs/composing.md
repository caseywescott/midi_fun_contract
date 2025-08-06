# Cairo Music Composition Workflow Guide

This guide explains how to compose music using Cairo and the Koji MIDI utilities without needing to deploy contracts. You can develop, test, and generate MIDI files directly from your Cairo code using Scarb's testing framework.

## 🎵 Overview: Why Compose in Cairo?

Cairo provides a unique approach to music composition where you can:

- **Write music as code** with precise control over every aspect
- **Test your compositions** using Scarb's testing framework
- **Generate MIDI files** directly from your Cairo code
- **Use Koji utilities** for advanced MIDI manipulation
- **Version control your music** alongside your code
- **Create reproducible compositions** with deterministic algorithms

## 🚀 Quick Start: Your First Cairo Composition

### 1. Create a Basic MIDI Structure

```cairo
use koji::midi::types::{Midi, Message, NoteOn, NoteOff, SetTempo};
use core::array::ArrayTrait;

#[test]
#[available_gas(1000000000000)]
fn my_first_composition() {
    let mut events = ArrayTrait::new();

    // Set tempo (BPM = 60000000 / microseconds_per_beat)
    let tempo = SetTempo { tempo: 500000, time: Option::Some(0) }; // 120 BPM
    events.append(Message::SET_TEMPO(tempo));

    // Add a C major scale
    let notes = array![60, 62, 64, 65, 67, 69, 71, 72]; // C, D, E, F, G, A, B, C
    let mut time = 0;

    for note in notes.span() {
        // Note On
        let note_on = NoteOn { channel: 0, note: *note, velocity: 100, time };
        events.append(Message::NOTE_ON(note_on));

        // Note Off (after 500 ticks)
        let note_off = NoteOff { channel: 0, note: *note, velocity: 100, time: time + 500 };
        events.append(Message::NOTE_OFF(note_off));

        time += 1000; // Move to next note
    }

    let midi = Midi { events: events.span() };

    // Print the MIDI structure for conversion
    println!("use koji::midi::types::{{Midi, Message, NoteOn, NoteOff, SetTempo}};");
    println!("fn midi() -> Midi {{");
    println!("    Midi {{");
    println!("        events: array![");

    let mut ev = midi.events;
    loop {
        match ev.pop_front() {
            Option::Some(event) => {
                match event {
                    Message::NOTE_ON(note) => {
                        println!("            Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                            *note.channel, *note.note, *note.velocity, *note.time);
                    },
                    Message::NOTE_OFF(note) => {
                        println!("            Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                            *note.channel, *note.note, *note.velocity, *note.time);
                    },
                    Message::SET_TEMPO(tempo) => {
                        println!("            Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }}),",
                            *tempo.tempo, match *tempo.time { Option::Some(t) => t, Option::None(_) => 0 });
                    },
                    _ => {}
                }
            },
            Option::None(_) => { break; }
        }
    }

    println!("        ].span()");
    println!("    }}");
    println!("}}");
}
```

### 2. Test Your Composition

```bash
# Run your composition test
SCARB_UI_VERBOSITY=quiet scarb test -- --filter my_first_composition
```

### 3. Generate MIDI File

```bash
# Generate Cairo code and convert to MIDI
./scripts/generate_cairo_and_midi.sh --cairo-only
```

## 🎼 Advanced Composition Techniques

### Using Koji MIDI Utilities

The Koji library provides powerful utilities for music composition:

#### Euclidean Rhythms

```cairo
use koji::midi::euclidean::generate_euclidean_pattern;

#[test]
#[available_gas(1000000000000)]
fn euclidean_composition() {
    let pattern = generate_euclidean_pattern(8, 3); // 8 steps, 3 hits
    // pattern = [1, 0, 1, 0, 1, 0, 0, 0]

    // Use pattern to create rhythmic composition
    let mut events = ArrayTrait::new();
    let mut time = 0;

    for (i, hit) in pattern.span().iter().enumerate() {
        if *hit == 1 {
            let note_on = NoteOn { channel: 0, note: 60, velocity: 100, time };
            events.append(Message::NOTE_ON(note_on));

            let note_off = NoteOff { channel: 0, note: 60, velocity: 100, time: time + 200 };
            events.append(Message::NOTE_OFF(note_off));
        }
        time += 500;
    }

    // Generate output...
}
```

#### Chord Detection and Harmony

```cairo
use koji::midi::core::detect_chords;

#[test]
#[available_gas(1000000000000)]
fn harmony_composition() {
    let mut events = ArrayTrait::new();

    // Create a chord progression
    let chords = array![
        array![60, 64, 67], // C major
        array![62, 65, 69], // D minor
        array![64, 67, 71], // E minor
        array![65, 69, 72]  // F major
    ];

    let mut time = 0;
    for chord in chords.span() {
        // Add all notes in the chord
        for note in chord.span() {
            let note_on = NoteOn { channel: 0, note: *note, velocity: 80, time };
            events.append(Message::NOTE_ON(note_on));
        }

        // Remove all notes after 1000 ticks
        for note in chord.span() {
            let note_off = NoteOff { channel: 0, note: *note, velocity: 80, time: time + 1000 };
            events.append(Message::NOTE_OFF(note_off));
        }

        time += 2000;
    }

    // Generate output...
}
```

#### Random Composition with LCG

```cairo
use koji::lcg::{LCG, RNGTrait, LCGImpl};

#[test]
#[available_gas(1000000000000)]
fn random_composition() {
    let lcg = LCG { state: 42, multiplier: 1664525, increment: 1013904223, modulus: 1000000 };
    let random_values = lcg.getlist(16);

    let mut events = ArrayTrait::new();
    let mut time = 0;

    for value in random_values.span() {
        let note = 60 + (*value % 12); // Random note in one octave
        let velocity = 60 + (*value % 40); // Random velocity

        let note_on = NoteOn { channel: 0, note, velocity, time };
        events.append(Message::NOTE_ON(note_on));

        let note_off = NoteOff { channel: 0, note, velocity, time: time + 500 };
        events.append(Message::NOTE_OFF(note_off));

        time += 1000;
    }

    // Generate output...
}
```

## 🔧 Development Workflow

### Environment Setup

Set up quiet mode for clean output:

```bash
# Per command (recommended)
SCARB_UI_VERBOSITY=quiet scarb test -- --filter your_test_name

# Session-wide
export SCARB_UI_VERBOSITY=quiet

# Permanent (add to ~/.zshrc)
echo 'export SCARB_UI_VERBOSITY=quiet' >> ~/.zshrc
source ~/.zshrc
```

### Testing Your Compositions

```bash
# Run a specific composition
SCARB_UI_VERBOSITY=quiet scarb test -- --filter my_composition_test

# Run all MIDI-related tests
SCARB_UI_VERBOSITY=quiet scarb test -- --filter test_midi

# Run all tests (before committing)
scarb test
```

### Generating MIDI Files

#### Option 1: Full Pipeline (Recommended)

```bash
# Generate both Cairo code and MIDI file
./scripts/generate_cairo_and_midi.sh

# Generate only Cairo code
./scripts/generate_cairo_and_midi.sh --cairo-only

# Generate only MIDI from existing Cairo file
./scripts/generate_cairo_and_midi.sh --midi-only

# Use custom filenames
./scripts/generate_cairo_and_midi.sh --cairo-output my_music.cairo --midi-output my_music.mid
```

#### Option 2: Manual Generation

```bash
# Generate Cairo code
SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_cairo_file_output_test 2>&1 | \
grep -v "running\|test\|gas usage\|test result" > my_composition.cairo

# Convert to MIDI using TypeScript
npx ts-node typescript/src/simpleMidiConverter.ts my_composition.cairo my_composition.mid
```

## 📁 Project Structure for Compositions

Organize your compositions in the test files:

```
src/tests/
├── test_midi.cairo          # Core MIDI functionality tests
├── test_euclidean.cairo     # Euclidean rhythm compositions
├── test_lcg.cairo          # Random/algorithmic compositions
├── midi_2_cairo_print.cairo # Code generation tests
└── your_compositions.cairo  # Your custom compositions
```

## 🎯 Composition Patterns

### Pattern 1: Melodic Composition

```cairo
#[test]
#[available_gas(1000000000000)]
fn melodic_composition() {
    let melody = array![60, 62, 64, 65, 67, 69, 71, 72]; // C major scale
    let mut events = ArrayTrait::new();
    let mut time = 0;

    for note in melody.span() {
        // Add note with varying velocity for expression
        let velocity = 80 + (*note % 20);

        let note_on = NoteOn { channel: 0, note: *note, velocity, time };
        events.append(Message::NOTE_ON(note_on));

        let note_off = NoteOff { channel: 0, note: *note, velocity, time: time + 800 };
        events.append(Message::NOTE_OFF(note_off));

        time += 1000;
    }

    // Generate output...
}
```

### Pattern 2: Rhythmic Composition

```cairo
#[test]
#[available_gas(1000000000000)]
fn rhythmic_composition() {
    let rhythm = array![1, 0, 1, 0, 1, 0, 0, 1]; // Kick pattern
    let mut events = ArrayTrait::new();
    let mut time = 0;

    for hit in rhythm.span() {
        if *hit == 1 {
            let note_on = NoteOn { channel: 9, note: 36, velocity: 100, time }; // Kick drum
            events.append(Message::NOTE_ON(note_on));

            let note_off = NoteOff { channel: 9, note: 36, velocity: 100, time: time + 200 };
            events.append(Message::NOTE_OFF(note_off));
        }
        time += 500;
    }

    // Generate output...
}
```

### Pattern 3: Harmonic Composition

```cairo
#[test]
#[available_gas(1000000000000)]
fn harmonic_composition() {
    let chord_progression = array![
        array![60, 64, 67], // C major
        array![62, 65, 69], // D minor
        array![64, 67, 71], // E minor
        array![65, 69, 72]  // F major
    ];

    let mut events = ArrayTrait::new();
    let mut time = 0;

    for chord in chord_progression.span() {
        // Add all notes in chord simultaneously
        for note in chord.span() {
            let note_on = NoteOn { channel: 0, note: *note, velocity: 70, time };
            events.append(Message::NOTE_ON(note_on));
        }

        // Remove all notes after chord duration
        for note in chord.span() {
            let note_off = NoteOff { channel: 0, note: *note, velocity: 70, time: time + 2000 };
            events.append(Message::NOTE_OFF(note_off));
        }

        time += 2000;
    }

    // Generate output...
}
```

## 🎨 Creative Techniques

### 1. Algorithmic Composition

Use mathematical patterns, fractals, or algorithms to generate music:

```cairo
#[test]
#[available_gas(1000000000000)]
fn fibonacci_composition() {
    let mut events = ArrayTrait::new();
    let mut time = 0;

    // Generate Fibonacci sequence for note selection
    let mut a = 1;
    let mut b = 1;

    for _ in 0..16 {
        let note = 60 + (a % 12); // Use Fibonacci mod 12 for notes
        let duration = 100 + (b % 400); // Use Fibonacci mod 400 for duration

        let note_on = NoteOn { channel: 0, note, velocity: 80, time };
        events.append(Message::NOTE_ON(note_on));

        let note_off = NoteOff { channel: 0, note, velocity: 80, time: time + duration };
        events.append(Message::NOTE_OFF(note_off));

        time += duration + 100;

        let temp = a;
        a = b;
        b = temp + b;
    }

    // Generate output...
}
```

### 2. Data-Driven Composition

Use external data to influence your compositions:

```cairo
#[test]
#[available_gas(1000000000000)]
fn data_driven_composition() {
    // Simulate data from external source
    let data_points = array![23, 45, 67, 89, 12, 34, 56, 78];
    let mut events = ArrayTrait::new();
    let mut time = 0;

    for value in data_points.span() {
        let note = 60 + (*value % 24); // Map data to note range
        let velocity = 40 + (*value % 60); // Map data to velocity

        let note_on = NoteOn { channel: 0, note, velocity, time };
        events.append(Message::NOTE_ON(note_on));

        let note_off = NoteOff { channel: 0, note, velocity, time: time + 500 };
        events.append(Message::NOTE_OFF(note_off));

        time += 1000;
    }

    // Generate output...
}
```

## 🔍 Debugging and Troubleshooting

### Common Issues

1. **Test not found**: Check test name spelling and ensure it's in the correct module
2. **Compilation errors**: Run with verbose output to see details
3. **MIDI file issues**: Verify the generated Cairo code format

### Debugging Commands

```bash
# See compilation details
SCARB_UI_VERBOSITY=verbose scarb test -- --filter your_test

# Check generated Cairo code
SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_cairo_file_output_test

# Validate MIDI file
file your_composition.mid
```

## 📚 Best Practices

1. **Use descriptive test names** for easy filtering
2. **Keep compositions modular** - separate melody, rhythm, and harmony
3. **Test frequently** during composition development
4. **Version control your compositions** alongside your code
5. **Document your algorithms** and musical decisions
6. **Use consistent naming conventions** for variables and functions

## 🎵 Example Complete Workflow

Here's a complete example of composing a piece:

```cairo
// src/tests/my_composition.cairo
use koji::midi::types::{Midi, Message, NoteOn, NoteOff, SetTempo};
use core::array::ArrayTrait;

#[test]
#[available_gas(1000000000000)]
fn my_complete_composition() {
    let mut events = ArrayTrait::new();

    // Set tempo to 120 BPM
    let tempo = SetTempo { tempo: 500000, time: Option::Some(0) };
    events.append(Message::SET_TEMPO(tempo));

    // Create a simple melody with harmony
    let melody = array![60, 62, 64, 65, 67, 69, 71, 72];
    let harmony = array![array![60, 64, 67], array![62, 65, 69], array![64, 67, 71], array![65, 69, 72]];

    let mut time = 0;

    // Add melody
    for (i, note) in melody.span().iter().enumerate() {
        let note_on = NoteOn { channel: 0, note: *note, velocity: 100, time };
        events.append(Message::NOTE_ON(note_on));

        let note_off = NoteOff { channel: 0, note: *note, velocity: 100, time: time + 500 };
        events.append(Message::NOTE_OFF(note_off));

        // Add harmony every 2 notes
        if i % 2 == 0 {
            let chord = harmony.span()[i / 2];
            for harmony_note in chord.span() {
                let h_note_on = NoteOn { channel: 1, note: *harmony_note, velocity: 60, time };
                events.append(Message::NOTE_ON(h_note_on));

                let h_note_off = NoteOff { channel: 1, note: *harmony_note, velocity: 60, time: time + 1000 };
                events.append(Message::NOTE_OFF(h_note_off));
            }
        }

        time += 1000;
    }

    // Generate the output
    println!("use koji::midi::types::{{Midi, Message, NoteOn, NoteOff, SetTempo}};");
    println!("fn midi() -> Midi {{");
    println!("    Midi {{");
    println!("        events: array![");

    let midi = Midi { events: events.span() };
    let mut ev = midi.events;
    loop {
        match ev.pop_front() {
            Option::Some(event) => {
                match event {
                    Message::NOTE_ON(note) => {
                        println!("            Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                            *note.channel, *note.note, *note.velocity, *note.time);
                    },
                    Message::NOTE_OFF(note) => {
                        println!("            Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }}),",
                            *note.channel, *note.note, *note.velocity, *note.time);
                    },
                    Message::SET_TEMPO(tempo) => {
                        println!("            Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }}),",
                            *tempo.tempo, match *tempo.time { Option::Some(t) => t, Option::None(_) => 0 });
                    },
                    _ => {}
                }
            },
            Option::None(_) => { break; }
        }
    }

    println!("        ].span()");
    println!("    }}");
    println!("}}");
}
```

### Workflow Steps:

1. **Write your composition** in Cairo
2. **Test it**: `SCARB_UI_VERBOSITY=quiet scarb test -- --filter my_complete_composition`
3. **Generate MIDI**: `./scripts/generate_cairo_and_midi.sh --cairo-output my_composition.cairo --midi-output my_composition.mid`
4. **Listen to your music** in any MIDI player
5. **Iterate and refine** your composition

This workflow gives you the power of Cairo's type safety and Koji's MIDI utilities while keeping your compositions as code that can be version controlled, tested, and easily modified! 🎵✨

# Koji: A Cairo library for Autonomous Music

Autonomous Music library based on previous [work](https://github.com/caseywescott/MusicTools-StarkNet) made by Casey Wescott.

# Midi Conversion
Convert Midi to JSON format:
```bash
make convert-json MIDI_FILE="path/to/midi/file.mid" OUTPUT_FILE="path/to/output"
```

Convert to Cairo format:

```bash
make convert-cairo MIDI_FILE="path/to/midi/file.mid" OUTPUT_FILE="path/to/output"
```

# MIDI Fun Contract

A comprehensive Cairo contract for MIDI music processing, featuring advanced algorithms for Euclidean rhythms, velocity curves, and musical transformations.

## Features

- **Euclidean Rhythm Generation**: Generate musical patterns using Bjorklund's algorithm
- **Velocity Curve Processing**: Apply dynamic velocity transformations to MIDI events
- **MIDI Event Handling**: Full support for NoteOn, NoteOff, SetTempo, and other MIDI messages
- **Cairo Code Generation**: Generate clean Cairo code from MIDI data structures
- **Python Integration**: Convert MIDI files to Cairo structs and JSON formats
- **TypeScript Parser**: Parse Cairo MIDI events back to standard MIDI format

## Quick Start

### Cairo Code Generation

Generate clean Cairo code from MIDI data:

```bash
# Using the automated script (recommended)
./scripts/generate_cairo_output.sh

# Or manually with redirection
SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_cairo_file_output_test 2>&1 | \
grep -v "running\|test\|gas usage\|test result" > my_midi.cairo
```

### Running Tests

```bash
# Run all tests
scarb test

# Run specific test
scarb test -- --filter midi_to_cairo_file_output_test

# Run with quiet output
SCARB_UI_VERBOSITY=quiet scarb test
```

### Python MIDI Conversion

```bash
# Convert MIDI to Cairo struct
python3 python/cli.py input.mid output.cairo --format cairo

# Convert MIDI to JSON
python3 python/cli.py input.mid output.json --format json
```

## Project Structure

```
midi_fun_contract/
├── src/
│   ├── midi/           # Core MIDI functionality
│   │   ├── core.cairo      # Main MIDI processing
│   │   ├── euclidean.cairo # Euclidean rhythm generation
│   │   ├── instruments.cairo # Instrument handling
│   │   ├── modes.cairo     # Musical modes
│   │   ├── output.cairo    # Output formatting
│   │   ├── pitch.cairo     # Pitch calculations
│   │   ├── time.cairo      # Time quantization
│   │   ├── types.cairo     # MIDI type definitions
│   │   ├── velocitycurve.cairo # Velocity processing
│   │   └── voicings.cairo  # Chord voicings
│   └── tests/
│       └── midi_2_cairo_print.cairo # Cairo code generation tests
├── python/             # Python MIDI conversion tools
├── typescript/         # TypeScript MIDI parsing
├── scripts/
│   └── generate_cairo_output.sh # Automated Cairo code generation
└── docs/               # Documentation
```

## Documentation

- [Print Formatting Guide](docs/print.md) - Cairo printing and code generation
- [Scarb Commands](docs/scarb_commands.md) - Scarb usage and configuration
- [Testing Guide](docs/scarb_testing_guide.md) - Testing strategies and best practices
- [Composing Guide](docs/composing.md) - Musical composition with the contract

## Development

### Prerequisites

- Scarb (Cairo package manager)
- Python 3.7+
- Node.js (for TypeScript tools)

### Setup

```bash
# Install Scarb dependencies
scarb build

# Install Python dependencies
cd python && pip install -r requirements.txt

# Install TypeScript dependencies
cd typescript && npm install
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

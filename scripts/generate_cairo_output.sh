#!/bin/bash

# Script to generate clean Cairo code output from MIDI test
# Usage: ./scripts/generate_cairo_output.sh [output_file]

OUTPUT_FILE=${1:-"generated_midi.cairo"}

echo "Generating Cairo code output..."
echo "Output will be saved to: $OUTPUT_FILE"

# Run the test and capture clean output
SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_cairo_file_output_test 2>&1 | \
grep -v "running\|test\|gas usage\|test result" > "$OUTPUT_FILE"

echo "✅ Cairo code generated successfully!"
echo "📁 File: $OUTPUT_FILE"
echo ""
echo "Preview of generated code:"
echo "=========================="
head -20 "$OUTPUT_FILE" 
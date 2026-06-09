#!/bin/bash
# Long Baroque cadential-improvisation MIDI showcases.
# Run from midi_fun_contract/: ./scripts/generate_baroque_demo_midis.sh

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "typescript/node_modules" ]; then
  echo "Installing TypeScript dependencies..."
  (cd typescript && npm install)
fi

MESSAGE_FILTER='grep "^Message::"'

generate_one() {
  local test_name="$1"
  local base_name="$2"
  echo "=== ${base_name} (${test_name}) ==="
  scarb test -- --filter "${test_name}" 2>&1 \
    | eval "${MESSAGE_FILTER}" > "${base_name}_parser.cairo"
  npx ts-node typescript/src/simpleMidiConverter.ts \
    "${base_name}_parser.cairo" "${base_name}.mid"
  echo "Wrote ${base_name}.mid"
}

mkdir -p demos/baroque

echo "Generating long Baroque cadential-improvisation MIDIs..."
echo ""
echo "Listen guide:"
echo "  Channel 0 = ornamented upper line / brise figures"
echo "  Channel 1 = bassizans / bass schema"
echo "  Channel 2 = alto fill"
echo "  Channel 3 = tenor fill"
echo ""

generate_one baroque_melody_transform_cadence_tour_midi_test demos/baroque/05_melody_transform_cadence_tour
generate_one baroque_long_moderate_ornament_showcase_midi_test demos/baroque/01_mixed_module_tour
generate_one baroque_long_sequence_modulation_midi_test demos/baroque/02_sequence_modulation_etude
generate_one baroque_long_minor_scalar_cadences_midi_test demos/baroque/03_minor_scalar_cadences
generate_one baroque_long_cadential_brise_midi_test demos/baroque/04_cadential_brise_study

echo ""
echo "Done. Files in $(pwd)/demos/baroque/"
ls -1 demos/baroque/*.mid

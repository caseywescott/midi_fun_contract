#!/bin/bash
# Barry Harris v2 labyrinth MIDI demos.
# Run from midi_fun_contract/: ./scripts/generate_barry_labyrinth_demo_midis.sh

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "typescript/node_modules" ]; then
  echo "Installing TypeScript dependencies..."
  (cd typescript && npm install)
fi

GREP_FILTER='grep -v "running\|test\|gas usage\|test result\|warn:"'

generate_one() {
  local test_name="$1"
  local base_name="$2"
  echo "=== ${base_name} (${test_name}) ==="
  SCARB_UI_VERBOSITY=quiet scarb test -- --include-ignored --filter "${test_name}" 2>&1 \
    | eval "${GREP_FILTER}" > "${base_name}_parser.cairo"
  npx ts-node typescript/src/simpleMidiConverter.ts \
    "${base_name}_parser.cairo" "${base_name}.mid"
  echo "Wrote ${base_name}.mid"
}

mkdir -p demos/barry_labyrinth

echo "Generating Barry Harris v2 labyrinth showcase MIDIs..."
echo ""

generate_one barry_labyrinth_01_elevator_up_midi_test demos/barry_labyrinth/01_elevator_up
generate_one barry_labyrinth_02_elevator_down_midi_test demos/barry_labyrinth/02_elevator_down
generate_one barry_labyrinth_03_contrary_motion_midi_test demos/barry_labyrinth/03_contrary_motion
generate_one barry_labyrinth_04_enclosure_line_midi_test demos/barry_labyrinth/04_enclosure_line
generate_one barry_labyrinth_05_neighbor_borrowing_midi_test demos/barry_labyrinth/05_neighbor_borrowing
generate_one barry_labyrinth_06_drop_two_block_midi_test demos/barry_labyrinth/06_drop_two_block
generate_one barry_labyrinth_07_barry_turnaround_midi_test demos/barry_labyrinth/07_barry_turnaround
generate_one barry_labyrinth_08_limitations_only_elevators_midi_test demos/barry_labyrinth/08_limitations_only_elevators
generate_one barry_labyrinth_09_limitations_no_leaps_midi_test demos/barry_labyrinth/09_limitations_no_leaps
generate_one barry_labyrinth_10_mixed_labyrinth_phrase_midi_test demos/barry_labyrinth/10_mixed_labyrinth_phrase

echo ""
echo "Done. Files in $(pwd)/demos/barry_labyrinth/"
ls -lh demos/barry_labyrinth/*.mid

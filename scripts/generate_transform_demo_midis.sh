#!/bin/bash
# Transformation library MIDI showcases (A/B source vs result per section).
# Run from midi_fun_contract/: ./scripts/generate_transform_demo_midis.sh

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
  SCARB_UI_VERBOSITY=quiet scarb test -- --filter "${test_name}" 2>&1 \
    | eval "${GREP_FILTER}" > "${base_name}_parser.cairo"
  npx ts-node typescript/src/simpleMidiConverter.ts \
    "${base_name}_parser.cairo" "${base_name}.mid"
  echo "Wrote ${base_name}.mid"
}

mkdir -p demos/transforms

echo "Generating transformation library showcase MIDIs..."
echo ""
echo "Listen guide:"
echo "  Channel 0  = source cell (C-D-E-G-A pentatonic)"
echo "  Channel 1  = transformed result"
echo "  Channel 9  = low marker ping at each section start"
echo ""

generate_one transform_showcase_order_midi_test demos/transforms/01_order
generate_one transform_showcase_pitch_midi_test demos/transforms/02_pitch
generate_one transform_showcase_select_map_midi_test demos/transforms/03_select_map
generate_one transform_showcase_rhythm_combine_midi_test demos/transforms/04_rhythm_combine
generate_one transform_showcase_pipeline_midi_test demos/transforms/05_pipeline
generate_one transform_showcase_all_midi_test demos/transforms/00_all_transforms

echo ""
echo "Done. Files in $(pwd)/demos/transforms/"
ls -1 demos/transforms/*.mid

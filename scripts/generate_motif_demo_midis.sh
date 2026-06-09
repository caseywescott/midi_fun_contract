#!/bin/bash
# Motif development algebra MIDI demos (theme, variations, long ornamented canon).
# Run from midi_fun_contract/: ./scripts/generate_motif_demo_midis.sh

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

mkdir -p demos/motif

echo "Generating motif development algebra showcase MIDIs..."
echo ""
echo "Listen guide:"
echo "  Channel 0  = solo developed theme / ornamented line"
echo "  Channel 0–1 = canon voices (long demo, section C)"
echo "  Channel 9  = section marker pings"
echo ""

generate_one motif_development_midi_test demos/motif/01_short_showcase
generate_one motif_development_long_ornamented_midi_test demos/motif/02_long_ornamented

echo ""
echo "Done. Files in $(pwd)/demos/motif/"
ls -1 demos/motif/*.mid

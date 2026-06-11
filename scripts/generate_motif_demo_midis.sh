#!/bin/bash
# Motif development MIDI demos (weighted development, grouping, and ornamented AABA form).
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
  SCARB_UI_VERBOSITY=quiet scarb test -- --include-ignored --filter "${test_name}" 2>&1 \
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
echo "  Channels 1–4 = ornamented grouped-period passes"
echo "  Channels 0–2 = ornamentation-v2 three-part motif canon"
echo "  Channel 9  = section marker pings"
echo ""

generate_one motif_development_midi_test demos/motif/01_short_showcase
generate_one motif_development_long_ornamented_midi_test demos/motif/02_long_ornamented
generate_one grouped_motif_sequence_inversion_long_ornamented_midi_test demos/motif/03_grouped_sequence_inversion_long_ornamented
generate_one grouped_motif_stutter_retrograde_long_ornamented_midi_test demos/motif/04_grouped_stutter_retrograde_long_ornamented
generate_one grouped_motif_interpolate_retroinvert_long_ornamented_midi_test demos/motif/05_grouped_interpolate_retroinvert_long_ornamented
generate_one motif_v2_three_part_canon_long_midi_test demos/motif/06_v2_three_part_canon_long

echo ""
echo "Done. Files in $(pwd)/demos/motif/"
ls -1 demos/motif/*.mid

#!/bin/bash
# Generate MIDI examples for all nine transformational-counterpoint texture types.
#
# Each demo shares a 20-note C-Ionian arch motif at 120 BPM and loops 3 times,
# matching the scale and feel of renaissance_canon_long_3voice_ornamented.mid.
#
# Run from midi_fun_contract/:
#   ./scripts/generate_transformational_counterpoint_midis.sh

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
  echo "=== ${base_name##*/} (${test_name}) ==="
  SCARB_UI_VERBOSITY=quiet scarb test -- --include-ignored --filter "${test_name}" 2>&1 \
    | eval "${GREP_FILTER}" > "${base_name}_parser.cairo"
  npx ts-node typescript/src/simpleMidiConverter.ts \
    "${base_name}_parser.cairo" "${base_name}.mid"
  echo "Wrote ${base_name}.mid"
}

mkdir -p demos/transformational_counterpoint

echo "Generating transformational counterpoint MIDI demos..."
echo ""
echo "Motif: 20-note C-Ionian arch (C-D-E-D-F-E-G-F-A-G-A-B-A-G-F-A-G-F-E-C)"
echo "Tempo: 120 BPM, step 125ms, 3 loops per demo"
echo ""

generate_one tc_exact_canon_midi_test \
  demos/transformational_counterpoint/01_exact_canon

generate_one tc_mirror_canon_midi_test \
  demos/transformational_counterpoint/02_mirror_canon

generate_one tc_crab_canon_midi_test \
  demos/transformational_counterpoint/03_crab_canon

generate_one tc_augmentation_canon_midi_test \
  demos/transformational_counterpoint/04_augmentation_canon

generate_one tc_diminution_canon_midi_test \
  demos/transformational_counterpoint/05_diminution_canon

generate_one tc_retrograde_inversion_canon_midi_test \
  demos/transformational_counterpoint/06_retrograde_inversion

generate_one tc_voice_exchange_midi_test \
  demos/transformational_counterpoint/07_voice_exchange

generate_one tc_hocket_midi_test \
  demos/transformational_counterpoint/08_hocket

generate_one tc_isorhythm_midi_test \
  demos/transformational_counterpoint/09_isorhythm

echo ""
echo "Done. Files in $(pwd)/demos/transformational_counterpoint/"
ls -1 demos/transformational_counterpoint/*.mid

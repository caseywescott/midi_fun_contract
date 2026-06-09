#!/bin/bash
# Barry Harris 6th-diminished harmony MIDI demos.
# Run from midi_fun_contract/: ./scripts/generate_barry_harris_demo_midis.sh

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

mkdir -p demos/barry_harris

echo "Generating Barry Harris harmony showcase MIDIs..."
echo ""
echo "Listen guide:"
echo "  Channels 0–3 = four-voice block chords (voice-led from active_pcs)"
echo "  Channel 9    = section markers (profile showcase only)"
echo "  ~125 BPM     = quarter-note grid (480ms per harmonic step)"
echo ""

generate_one barry_harris_conservative_c_major_midi_test demos/barry_harris/01_conservative_c_major
generate_one barry_harris_bebop_line_midi_test demos/barry_harris/02_bebop_line_c_major
generate_one barry_harris_diminished_heavy_midi_test demos/barry_harris/03_diminished_heavy_c_major
generate_one barry_harris_minor_field_midi_test demos/barry_harris/04_minor_field_c
generate_one barry_harris_dominant_field_midi_test demos/barry_harris/05_dominant_field_g
generate_one barry_harris_profile_showcase_midi_test demos/barry_harris/06_profile_showcase

echo ""
echo "Done. Files in $(pwd)/demos/barry_harris/"
ls -lh demos/barry_harris/*.mid

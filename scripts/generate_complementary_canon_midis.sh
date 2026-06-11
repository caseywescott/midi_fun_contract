#!/bin/bash
# Generate long ornamented MIDI demos (profiles 17–24). Prefer:
#   ./scripts/generate_new_profile_demo_midis.sh
# This script remains as a thin alias for the primary 14 complementary/smooth exports.
# Run from midi_fun_contract/: ./scripts/generate_complementary_canon_midis.sh

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

generate_one complementary_impr_add6_long_4v_midi_test impressionist_added6_long_4v
generate_one complementary_impr_add6_long_3v_midi_test impressionist_added6_long_3v
generate_one complementary_bitonal_long_4v_midi_test bitonal_split_long_4v
generate_one complementary_bitonal_long_3v_midi_test bitonal_split_long_3v
generate_one complementary_phrygian_long_4v_midi_test phrygian_cadential_long_4v
generate_one complementary_phrygian_long_3v_midi_test phrygian_cadential_long_3v
generate_one complementary_pentatonic_long_4v_midi_test pentatonic_open_long_4v
generate_one complementary_pentatonic_long_3v_midi_test pentatonic_open_long_3v
generate_one complementary_neo_riem_long_3v_midi_test neo_riemannian_long_3v
generate_one complementary_neo_riem_long_4v_midi_test neo_riemannian_long_4v
generate_one complementary_impr_smooth_long_4v_midi_test impressionist_added6_smooth_long_4v
generate_one complementary_impr_smooth_long_3v_midi_test impressionist_added6_smooth_long_3v
generate_one complementary_penta_smooth_long_4v_midi_test pentatonic_open_smooth_long_4v
generate_one complementary_penta_smooth_long_3v_midi_test pentatonic_open_smooth_long_3v
generate_one jazz_improv_long_4v_midi_test jazz_improv_long_4v
generate_one jazz_improv_long_3v_midi_test jazz_improv_long_3v

echo ""
echo "Done. MIDI files in $(pwd):"
echo "For full demo set (alt seeds + dense ornament): ./scripts/generate_new_profile_demo_midis.sh"

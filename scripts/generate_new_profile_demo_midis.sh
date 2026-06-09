#!/bin/bash
# Long ornamented MIDI demos for profiles 17–24 (complementary, smooth, jazz improv).
# Run from midi_fun_contract/: ./scripts/generate_new_profile_demo_midis.sh

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

mkdir -p demos

echo "Generating primary long demos (48 steps, 4 loops, ornamented)..."

generate_one complementary_impr_add6_long_4v_midi_test demos/impr_add6_4v_long
generate_one complementary_impr_add6_long_3v_midi_test demos/impr_add6_3v_long
generate_one complementary_bitonal_long_4v_midi_test demos/bitonal_4v_long
generate_one complementary_bitonal_long_3v_midi_test demos/bitonal_3v_long
generate_one complementary_phrygian_long_4v_midi_test demos/phrygian_4v_long
generate_one complementary_phrygian_long_3v_midi_test demos/phrygian_3v_long
generate_one complementary_pentatonic_long_4v_midi_test demos/pentatonic_4v_long
generate_one complementary_pentatonic_long_3v_midi_test demos/pentatonic_3v_long
generate_one complementary_neo_riem_long_4v_midi_test demos/neo_riem_4v_long
generate_one complementary_neo_riem_long_3v_midi_test demos/neo_riem_3v_long
generate_one complementary_impr_smooth_long_4v_midi_test demos/impr_smooth_4v_long
generate_one complementary_impr_smooth_long_3v_midi_test demos/impr_smooth_3v_long
generate_one complementary_penta_smooth_long_4v_midi_test demos/penta_smooth_4v_long
generate_one penta_smooth_ornamented_long_4v_midi_test demos/penta_smooth_4v_ornate_long
generate_one complementary_penta_smooth_long_3v_midi_test demos/penta_smooth_3v_long
generate_one jazz_improv_long_4v_midi_test demos/jazz_improv_4v_long
generate_one jazz_improv_long_3v_midi_test demos/jazz_improv_3v_long

echo ""
echo "Generating alternate-seed variants (48 steps, 6 loops)..."

generate_one profile_demo_impr_add6_alt_midi_test demos/impr_add6_4v_alt
generate_one profile_demo_bitonal_alt_midi_test demos/bitonal_4v_alt
generate_one profile_demo_phrygian_alt_midi_test demos/phrygian_4v_alt
generate_one profile_demo_pentatonic_alt_midi_test demos/pentatonic_4v_alt
generate_one profile_demo_neo_riem_alt_midi_test demos/neo_riem_3v_alt
generate_one profile_demo_impr_smooth_alt_midi_test demos/impr_smooth_4v_alt
generate_one profile_demo_penta_smooth_alt_midi_test demos/penta_smooth_4v_alt
generate_one profile_demo_jazz_improv_alt_midi_test demos/jazz_improv_4v_alt

echo ""
echo "Generating dense-ornament showcases (32 steps, 8 loops, faster pulse)..."

generate_one profile_demo_ornament_dense_impr_midi_test demos/impr_add6_dense
generate_one profile_demo_ornament_dense_phrygian_midi_test demos/phrygian_dense
generate_one profile_demo_ornament_dense_bitonal_midi_test demos/bitonal_dense
generate_one profile_demo_ornament_dense_jazz_midi_test demos/jazz_improv_dense

echo ""
echo "Done. $(ls -1 demos/*.mid 2>/dev/null | wc -l | tr -d ' ') MIDI files in $(pwd)/demos/"

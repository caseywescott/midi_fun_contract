#!/bin/bash
# v2 ornamentation showcase MIDI demos — one file per ornament kind + full catalog.
# Run from midi_fun_contract/: ./scripts/generate_ornamentation_v2_demo_midis.sh
#
# Throttling (prevents laptop thermal/RAM spikes):
#   SCARB_TEST_SLEEP=5 ./scripts/generate_ornamentation_v2_demo_midis.sh
#   CATALOG_ONLY=1 ./scripts/generate_ornamentation_v2_demo_midis.sh   # catalog MIDI only
#   BATCH=1 BATCH_SIZE=10 ./scripts/generate_ornamentation_v2_demo_midis.sh  # items 1-10
#   BATCH=2 BATCH_SIZE=10 ./scripts/generate_ornamentation_v2_demo_midis.sh  # items 11-20

set -euo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/lib/scarb_throttle.sh"

SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-3}"
CATALOG_ONLY="${CATALOG_ONLY:-0}"
BATCH="${BATCH:-0}"
BATCH_SIZE="${BATCH_SIZE:-10}"

if [ ! -d "typescript/node_modules" ]; then
  echo "Installing TypeScript dependencies..."
  (cd typescript && npm install)
fi

GREP_FILTER='grep "^Message::"'

scarb_build_once

generate_one() {
  local test_name="$1"
  local base_name="$2"
  echo "=== ${base_name} (${test_name}) ==="
  scarb_test_filtered "${test_name}" 1 2>&1 \
    | eval "${GREP_FILTER}" > "${base_name}_parser.cairo"
  npx ts-node typescript/src/simpleMidiConverter.ts \
    "${base_name}_parser.cairo" "${base_name}.mid"
  echo "Wrote ${base_name}.mid"
  throttle_sleep
}

mkdir -p demos/ornamentation_v2

echo "Generating v2 ornamentation showcase MIDIs..."
echo ""
echo "Listen guide:"
echo "  Channel 0 = single-voice ornament examples (C Ionian, tonic C4)"
echo "  ~120 BPM    = quarter-note grid (250ms per tick)"
echo "  00_catalog  = all 35 kinds in sequence with gaps"
echo ""

if [ "${CATALOG_ONLY}" = "1" ]; then
  generate_one ornament_v2_catalog_all_kinds_midi_test demos/ornamentation_v2/00_catalog_all_kinds
  echo "Catalog only. Done."
  exit 0
fi

# Skip catalog when running a numbered batch (use BATCH=0 or RUN_CATALOG=1 for full run).
if [ "${BATCH}" -eq 0 ] 2>/dev/null || [ "${RUN_CATALOG:-0}" = "1" ]; then
  generate_one ornament_v2_catalog_all_kinds_midi_test demos/ornamentation_v2/00_catalog_all_kinds
fi

TESTS=(
  "01_passing_asc:ornament_v2_01_passing_asc_midi_test"
  "02_passing_desc:ornament_v2_02_passing_desc_midi_test"
  "03_neighbor_upper:ornament_v2_03_neighbor_upper_midi_test"
  "04_neighbor_lower:ornament_v2_04_neighbor_lower_midi_test"
  "05_double_neighbor_uf:ornament_v2_05_double_neighbor_uf_midi_test"
  "06_double_neighbor_lf:ornament_v2_06_double_neighbor_lf_midi_test"
  "07_anticipation:ornament_v2_07_anticipation_midi_test"
  "08_suspension_43:ornament_v2_08_suspension_43_midi_test"
  "09_suspension_76:ornament_v2_09_suspension_76_midi_test"
  "10_suspension_98:ornament_v2_10_suspension_98_midi_test"
  "11_suspension_65:ornament_v2_11_suspension_65_midi_test"
  "12_suspension_23_bass:ornament_v2_12_suspension_23_bass_midi_test"
  "13_retardation:ornament_v2_13_retardation_midi_test"
  "14_appoggiatura_upper:ornament_v2_14_appoggiatura_upper_midi_test"
  "15_appoggiatura_lower:ornament_v2_15_appoggiatura_lower_midi_test"
  "16_escape_upper:ornament_v2_16_escape_upper_midi_test"
  "17_escape_lower:ornament_v2_17_escape_lower_midi_test"
  "18_echappee_upper:ornament_v2_18_echappee_upper_midi_test"
  "19_echappee_lower:ornament_v2_19_echappee_lower_midi_test"
  "20_cambiata:ornament_v2_20_cambiata_midi_test"
  "21_mordent_upper:ornament_v2_21_mordent_upper_midi_test"
  "22_mordent_lower:ornament_v2_22_mordent_lower_midi_test"
  "23_turn_upper:ornament_v2_23_turn_upper_midi_test"
  "24_turn_lower:ornament_v2_24_turn_lower_midi_test"
  "25_trill_upper:ornament_v2_25_trill_upper_midi_test"
  "26_trill_lower:ornament_v2_26_trill_lower_midi_test"
  "27_acciaccatura_upper:ornament_v2_27_acciaccatura_upper_midi_test"
  "28_acciaccatura_lower:ornament_v2_28_acciaccatura_lower_midi_test"
  "29_chromatic_approach_upper:ornament_v2_29_chromatic_approach_upper_midi_test"
  "30_chromatic_approach_lower:ornament_v2_30_chromatic_approach_lower_midi_test"
  "31_enclosure_uf:ornament_v2_31_enclosure_uf_midi_test"
  "32_enclosure_lf:ornament_v2_32_enclosure_lf_midi_test"
  "33_arpeggiation_up:ornament_v2_33_arpeggiation_up_midi_test"
  "34_arpeggiation_down:ornament_v2_34_arpeggiation_down_midi_test"
  "35_pedal_hold:ornament_v2_35_pedal_hold_midi_test"
)

total=${#TESTS[@]}
start=0
end=$((total - 1))
if [ "${BATCH}" -gt 0 ] 2>/dev/null; then
  start=$(( (BATCH - 1) * BATCH_SIZE ))
  end=$(( start + BATCH_SIZE - 1 ))
  if [ "${end}" -ge "${total}" ]; then
    end=$((total - 1))
  fi
  echo "Batch ${BATCH}: items $((start + 1))-$((end + 1)) of ${total}"
fi

idx=0
for entry in "${TESTS[@]}"; do
  if [ "${idx}" -lt "${start}" ] || [ "${idx}" -gt "${end}" ]; then
    idx=$((idx + 1))
    continue
  fi
  slug="${entry%%:*}"
  test_name="${entry##*:}"
  generate_one "${test_name}" "demos/ornamentation_v2/${slug}"
  idx=$((idx + 1))
done

echo ""
echo "Done. Files in $(pwd)/demos/ornamentation_v2/"
ls -lh demos/ornamentation_v2/*.mid

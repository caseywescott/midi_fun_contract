#!/bin/bash
# Generate the complete V2 ornament-family tour in the long three-voice Renaissance canon frame.
#
# Run from midi_fun_contract/:
#   SCARB_TEST_SLEEP=3 ./scripts/generate_renaissance_v2_ornament_families.sh

set -euo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/lib/scarb_throttle.sh"

OUT_DIR="demos/renaissance_v2_ornament_families"
TS_NODE="typescript/node_modules/.bin/ts-node"
mkdir -p "${OUT_DIR}"

if [ ! -x "${TS_NODE}" ]; then
  echo "Installing TypeScript dependencies..."
  (cd typescript && npm install)
fi

generate_one() {
  local test_name="$1"
  local slug="$2"
  local output="${OUT_DIR}/${slug}.mid"
  local parser="${OUT_DIR}/${slug}_parser.cairo"

  if [ -s "${output}" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "${output} already exists; skipping."
    return
  fi

  echo "${test_name} -> ${output}"
  scarb_test_filtered "${test_name}" 1 2>&1 | grep "^Message::" > "${parser}"
  "${TS_NODE}" typescript/src/simpleMidiConverter.ts "${parser}" "${output}"
  throttle_sleep
}

echo "Building the Renaissance V2 ornament-family MIDI batch..."
scarb_build_once

generate_one renaissance_v2_family_01_passing_midi_test              01_passing
generate_one renaissance_v2_family_02_neighbors_midi_test            02_neighbors
generate_one renaissance_v2_family_03_anticipation_midi_test         03_anticipation
generate_one renaissance_v2_family_04_suspensions_midi_test          04_suspensions
generate_one renaissance_v2_family_05_appoggiaturas_midi_test        05_appoggiaturas
generate_one renaissance_v2_family_06_escape_echappee_midi_test      06_escape_echappee
generate_one renaissance_v2_family_07_cambiata_midi_test             07_cambiata
generate_one renaissance_v2_family_08_baroque_rapid_midi_test        08_baroque_rapid
generate_one renaissance_v2_family_09_acciaccaturas_midi_test        09_acciaccaturas
generate_one renaissance_v2_family_10_chromatic_enclosures_midi_test 10_chromatic_enclosures
generate_one renaissance_v2_family_11_arpeggiation_midi_test         11_arpeggiation
generate_one renaissance_v2_family_12_pedal_hold_midi_test           12_pedal_hold

echo "Done. Files in $(pwd)/${OUT_DIR}/"

#!/bin/bash
# Barry Harris v2 audible showcase MIDIs.
#
# Renders ONE ignored test per `scarb test` invocation so peak memory stays
# bounded (safe for laptops). Run from midi_fun_contract/:
#   ./scripts/generate_barry_showcase_demo_midis.sh
# Optionally pass a single base name to render just one, e.g.:
#   ./scripts/generate_barry_showcase_demo_midis.sh 06_motif_ornamented_over_comp

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "typescript/node_modules" ]; then
  echo "Installing TypeScript dependencies..."
  (cd typescript && npm install)
fi

generate_one() {
  local test_name="$1"
  local base_name="$2"
  echo "=== ${base_name} (${test_name}) ==="
  scarb test -- --include-ignored --filter "${test_name}" 2>&1 \
    | grep '^Message::' > "${base_name}_parser.cairo"
  npx ts-node typescript/src/simpleMidiConverter.ts \
    "${base_name}_parser.cairo" "${base_name}.mid"
  echo "Wrote ${base_name}.mid"
}

mkdir -p demos/barry_showcase

# name -> test mapping
declare -a NAMES=(
  "01_elevator_block_etude"
  "02_voicing_styles_tour"
  "03_voice_motion_tour"
  "04_turnaround_suite"
  "05_bebop_line_cells"
  "06_motif_ornamented_over_comp"
  "07_labyrinth_borrowing_limitation"
  "08_bebop_line_harmonized"
  "09_renaissance_leader_sparse_harmony"
  "10_renaissance_leader_sparse_drop_two"
  "11_renaissance_leader_elevators_neighbor_keys"
)
declare -a TESTS=(
  "barry_showcase_01_elevator_block_etude_midi_test"
  "barry_showcase_02_voicing_styles_tour_midi_test"
  "barry_showcase_03_voice_motion_tour_midi_test"
  "barry_showcase_04_turnaround_suite_midi_test"
  "barry_showcase_05_bebop_line_cells_midi_test"
  "barry_showcase_06_motif_ornamented_over_comp_midi_test"
  "barry_showcase_07_labyrinth_borrowing_limitation_midi_test"
  "barry_showcase_08_bebop_line_harmonized_midi_test"
  "barry_showcase_09_renaissance_leader_sparse_harmony_midi_test"
  "barry_showcase_10_renaissance_leader_sparse_drop_two_midi_test"
  "barry_showcase_11_renaissance_leader_elevators_neighbor_keys_midi_test"
)

ONLY="${1:-}"

echo "Generating Barry Harris v2 showcase MIDIs..."
echo ""

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  test="${TESTS[$i]}"
  if [ -n "${ONLY}" ] && [ "${ONLY}" != "${name}" ]; then
    continue
  fi
  generate_one "${test}" "demos/barry_showcase/${name}"
done

echo ""
echo "Done. Files in $(pwd)/demos/barry_showcase/"
ls -lh demos/barry_showcase/*.mid

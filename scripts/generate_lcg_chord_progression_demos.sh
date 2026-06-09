#!/bin/bash
# LCG-driven parsimonious seventh-chord progression showcase.
# Engine: generate_parsimonious_progression(seed, nchords) in parsimonious_progression.cairo
# Run from midi_fun_contract/: ./scripts/generate_lcg_chord_progression_demos.sh

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "typescript/node_modules" ]; then
  echo "Installing TypeScript dependencies..."
  (cd typescript && npm install)
fi

GREP_FILTER='grep -v "running\|test\|gas usage\|test result\|warn:"'

generate_one() {
  local test_name="$1"
  local out_path="$2"
  local parser_path="${out_path%.mid}_parser.cairo"
  echo "=== ${out_path} (${test_name}) ==="
  SCARB_UI_VERBOSITY=quiet scarb test -- --filter "${test_name}" 2>&1 \
    | eval "${GREP_FILTER}" > "${parser_path}"
  npx ts-node typescript/src/simpleMidiConverter.ts "${parser_path}" "${out_path}"
  echo "Wrote ${out_path}"
}

mkdir -p demos/lcg_chord_progression

echo "Generating LCG parsimonious chord-progression demos..."
echo ""

generate_one lcg_parsimonious_chord_passage_raw_epic_midi_test \
  demos/lcg_chord_progression/01_lcg_chord_passage_raw_256chords.mid
generate_one lcg_parsimonious_chord_passage_raw_double_cycle_midi_test \
  demos/lcg_chord_progression/02_lcg_chord_passage_raw_128x2.mid
generate_one lcg_parsimonious_chord_showcase_multi_seed_midi_test \
  demos/lcg_chord_progression/03_lcg_chord_showcase_five_seeds.mid
generate_one lcg_parsimonious_chord_passage_ornate_epic_midi_test \
  demos/lcg_chord_progression/04_lcg_chord_passage_ornate_160x2.mid

echo ""
echo "Done. Files in $(pwd)/demos/lcg_chord_progression/"
ls -1 demos/lcg_chord_progression/*.mid

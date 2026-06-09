#!/bin/bash
# Clave timeline rhythm MIDI showcase suite.
# Run from midi_fun_contract/: ./scripts/generate_timeline_demo_midis.sh

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

mkdir -p demos/timeline_rhythm

echo "Generating clave timeline rhythm showcase MIDIs..."
echo ""

generate_one timeline_rhythm_reference_presets_midi_test demos/timeline_rhythm/01_reference_presets.mid
generate_one timeline_rhythm_son_family_variants_midi_test demos/timeline_rhythm/02_son_family_variants.mid
generate_one timeline_rhythm_son_family_seed_tour_midi_test demos/timeline_rhythm/03_son_family_seed_tour.mid
generate_one timeline_rhythm_profiled_selection_midi_test demos/timeline_rhythm/04_profiled_selection.mid
generate_one timeline_rhythm_morph_walk_midi_test demos/timeline_rhythm/05_son_family_morph_walk.mid
generate_one timeline_rhythm_phrasing_accent_midi_test demos/timeline_rhythm/06_phrasing_accent_grid.mid
generate_one timeline_rhythm_son_phase_orbit_midi_test demos/timeline_rhythm/07_son_phase_orbit_shift1.mid
generate_one timeline_rhythm_phase_shift2_midi_test demos/timeline_rhythm/08_son_phase_orbit_shift2.mid

echo ""
echo "Done. Files in $(pwd)/demos/timeline_rhythm/"
ls -1 demos/timeline_rhythm/*.mid

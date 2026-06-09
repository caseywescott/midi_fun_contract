#!/bin/bash
# Batch 2 — curated harmonic-walk MIDI demos (stronger melodic/harmonic variety).
# Run from midi_fun_contract/: ./scripts/generate_harmonic_walk_demo_midis_batch2.sh

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

mkdir -p demos/harmonic_walk/batch2

echo "Batch 2 — block harmony (ornamented min-motion, curated skeletons)..."

generate_one hw_batch2_two_five_one_rewrite_midi_test \
  demos/harmonic_walk/batch2/01_two_five_one_substitution_chain.mid
generate_one hw_batch2_rhythm_changes_reharm_midi_test \
  demos/harmonic_walk/batch2/02_rhythm_changes_reharm_cycle.mid
generate_one hw_batch2_turnaround_surprise_midi_test \
  demos/harmonic_walk/batch2/03_turnaround_axiom_surprise_walk.mid
generate_one hw_batch2_blues_surprise_colors_midi_test \
  demos/harmonic_walk/batch2/04_blues_surprise_harmonic_colors.mid
generate_one hw_batch2_two_five_one_max_surprise_midi_test \
  demos/harmonic_walk/batch2/05_two_five_one_max_surprise.mid

echo ""
echo "Batch 2 — profile-24 jazz canon over harmonic-walk timelines..."

generate_one hw_batch2_jazz_canon_251_long_midi_test \
  demos/harmonic_walk/batch2/06_jazz_canon_walk_251_40steps.mid
generate_one hw_batch2_jazz_canon_rhythm_changes_midi_test \
  demos/harmonic_walk/batch2/07_jazz_canon_walk_rhythm_changes.mid
generate_one hw_batch2_jazz_canon_blues_gospel_midi_test \
  demos/harmonic_walk/batch2/08_jazz_canon_walk_blues_gospel_3v.mid
generate_one hw_batch2_jazz_canon_turnaround_surprise_midi_test \
  demos/harmonic_walk/batch2/09_jazz_canon_walk_rhythm_changes_surprise.mid
generate_one hw_batch2_jazz_canon_hybrid_epic_midi_test \
  demos/harmonic_walk/batch2/10_jazz_canon_walk_hybrid_epic_96steps.mid

echo ""
echo "Done. Files in $(pwd)/demos/harmonic_walk/batch2/"
ls -1 demos/harmonic_walk/batch2/*.mid

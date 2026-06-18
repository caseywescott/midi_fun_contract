#!/bin/bash
# Baroque trill subdivision variants: 4-sub (baseline), 8-sub (fast flutter), 12-sub (tremolo).
# Run from midi_fun_contract/: SCARB_TEST_SLEEP=3 ./scripts/generate_baroque_trill_variants.sh

set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p demos/dark_minor/trill_variants

generate_one() {
  local test_name="$1"
  local output="$2"
  echo "=== ${test_name} -> ${output} ==="
  SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-3}" \
    ./scripts/generate_midi_from_test.sh "${test_name}" "${output}"
}

generate_one dark_minor_canon_04_aeolian_midi_test        demos/dark_minor/trill_variants/01_trill_4sub_baseline.mid
generate_one dark_minor_baroque_trill_8sub_midi_test      demos/dark_minor/trill_variants/02_trill_8sub_flutter.mid
generate_one dark_minor_baroque_trill_12sub_midi_test     demos/dark_minor/trill_variants/03_trill_12sub_tremolo.mid

echo ""
echo "Done. Files in $(pwd)/demos/dark_minor/trill_variants/"
ls -1 demos/dark_minor/trill_variants/*.mid

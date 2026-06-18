#!/bin/bash
# Ten dark-minor 3-voice ornamented canons (Aeolian / Phrygian / Dorian).
# Run from midi_fun_contract/: SCARB_TEST_SLEEP=3 ./scripts/generate_dark_minor_canons.sh

set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p demos/dark_minor

generate_one() {
  local test_name="$1"
  local output="$2"
  echo "=== ${test_name} -> ${output} ==="
  SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-3}" \
    ./scripts/generate_midi_from_test.sh "${test_name}" "${output}"
}

generate_one dark_minor_canon_01_aeolian_midi_test   demos/dark_minor/01_aeolian.mid
generate_one dark_minor_canon_02_phrygian_midi_test  demos/dark_minor/02_phrygian.mid
generate_one dark_minor_canon_03_dorian_midi_test    demos/dark_minor/03_dorian.mid
generate_one dark_minor_canon_04_aeolian_midi_test   demos/dark_minor/04_aeolian.mid
generate_one dark_minor_canon_05_phrygian_midi_test  demos/dark_minor/05_phrygian.mid
generate_one dark_minor_canon_06_dorian_midi_test    demos/dark_minor/06_dorian.mid
generate_one dark_minor_canon_07_aeolian_midi_test   demos/dark_minor/07_aeolian.mid
generate_one dark_minor_canon_08_dorian_midi_test    demos/dark_minor/08_dorian.mid
generate_one dark_minor_canon_09_phrygian_midi_test  demos/dark_minor/09_phrygian.mid
generate_one dark_minor_canon_10_aeolian_midi_test   demos/dark_minor/10_aeolian.mid

echo ""
echo "Done. Files in $(pwd)/demos/dark_minor/"
ls -1 demos/dark_minor/*.mid

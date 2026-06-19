#!/bin/bash
# Loot Survivor Beast IC canon MIDI demos.
# Generates baroque-ornamented invertible counterpoint canons with beast trait mapping.
# Run from midi_fun_contract/: SCARB_TEST_SLEEP=3 ./scripts/generate_beast_ic_canon_midi.sh

set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p demos/beasts/ic_canon

generate_one() {
  local test_name="$1"
  local output="$2"
  echo "=== ${test_name} -> ${output} ==="
  SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-3}" \
    ./scripts/generate_midi_from_test.sh "${test_name}" "${output}"
}

generate_one beast_ic_tier1_crown_baroque_midi_test     demos/beasts/ic_canon/01_tier1_crown_baroque.mid
generate_one beast_ic_tier1_low_history_midi_test       demos/beasts/ic_canon/02_tier1_low_history.mid
generate_one beast_ic_tier3_scarred_inversion_midi_test demos/beasts/ic_canon/03_tier3_scarred_inversion.mid
generate_one beast_ic_tier3_high_kills_modal_midi_test  demos/beasts/ic_canon/04_tier3_high_kills_modal.mid
generate_one beast_ic_tier5_low_history_midi_test       demos/beasts/ic_canon/05_tier5_low_history.mid
generate_one beast_ic_tier5_crown_animated_midi_test    demos/beasts/ic_canon/06_tier5_crown_animated.mid
generate_one beast_ic_magic_weakness_midi_test          demos/beasts/ic_canon/07_magic_weakness.mid
generate_one beast_ic_bludgeon_weakness_midi_test       demos/beasts/ic_canon/08_bludgeon_weakness.mid

echo ""
echo "Done. Files in $(pwd)/demos/beasts/ic_canon/"
ls -1 demos/beasts/ic_canon/*.mid

#!/bin/bash
# Loot Survivor Beast sound MIDI demos.
# Run from midi_fun_contract/: SCARB_TEST_SLEEP=3 ./scripts/generate_beast_demo_midis.sh

set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p demos/beasts

generate_one() {
  local test_name="$1"
  local output="$2"
  echo "=== ${test_name} -> ${output} ==="
  SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-3}" \
    ./scripts/generate_midi_from_test.sh "${test_name}" "${output}"
}

generate_one beast_tier5_low_history_midi_test demos/beasts/01_tier5_low_history.mid
generate_one beast_tier5_high_crown_midi_test demos/beasts/02_tier5_high_crown.mid
generate_one beast_tier3_scarred_midi_test demos/beasts/03_tier3_scarred.mid
generate_one beast_tier3_high_kills_midi_test demos/beasts/04_tier3_high_kills.mid
generate_one beast_tier1_bare_dragon_midi_test demos/beasts/05_tier1_bare_dragon.mid
generate_one beast_tier1_crown_midi_test demos/beasts/06_tier1_crown.mid
generate_one beast_magic_weakness_midi_test demos/beasts/07_magic_weakness.mid
generate_one beast_bludgeon_weakness_midi_test demos/beasts/08_bludgeon_weakness.mid

echo ""
echo "Done. Files in $(pwd)/demos/beasts/"
ls -1 demos/beasts/*.mid

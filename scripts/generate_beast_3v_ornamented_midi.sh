#!/bin/bash
# Loot Survivor Beast 3-voice ornamented canon MIDI demos.
# Run from midi_fun_contract/: SCARB_TEST_SLEEP=3 ./scripts/generate_beast_3v_ornamented_midi.sh

set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p demos/beasts/3voice_orn

generate_one() {
  local test_name="$1"
  local output="$2"
  echo "=== ${test_name} -> ${output} ==="
  SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-3}" \
    ./scripts/generate_midi_from_test.sh "${test_name}" "${output}"
}

generate_one beast_3v_orn_tier5_low_midi_test     demos/beasts/3voice_orn/01_tier5_low.mid
generate_one beast_3v_orn_tier5_crown_midi_test   demos/beasts/3voice_orn/02_tier5_crown.mid
generate_one beast_3v_orn_tier3_scarred_midi_test demos/beasts/3voice_orn/03_tier3_scarred.mid
generate_one beast_3v_orn_tier3_high_kills_midi_test demos/beasts/3voice_orn/04_tier3_high_kills.mid
generate_one beast_3v_orn_tier1_bare_dragon_midi_test demos/beasts/3voice_orn/05_tier1_bare_dragon.mid
generate_one beast_3v_orn_tier1_crown_midi_test   demos/beasts/3voice_orn/06_tier1_crown.mid
generate_one beast_3v_orn_magic_weakness_midi_test   demos/beasts/3voice_orn/07_magic_weakness.mid
generate_one beast_3v_orn_bludgeon_weakness_midi_test demos/beasts/3voice_orn/08_bludgeon_weakness.mid

echo ""
echo "Done. Files in $(pwd)/demos/beasts/3voice_orn/"
ls -1 demos/beasts/3voice_orn/*.mid

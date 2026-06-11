#!/bin/bash
# Generate all v2 ornamentation demo MIDIs in small batches with cooldowns.
# Safe for laptops — never runs more than BATCH_SIZE tests before a long pause.
#
# Usage:
#   ./scripts/generate_ornamentation_v2_all_safe.sh
#   SCARB_TEST_SLEEP=8 BATCH_SIZE=5 ./scripts/generate_ornamentation_v2_all_safe.sh

set -euo pipefail
cd "$(dirname "$0")/.."

SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-5}"
BATCH_SIZE="${BATCH_SIZE:-7}"
BATCH_PAUSE="${BATCH_PAUSE:-12}"   # seconds between batches
TOTAL_KINDS=35
NUM_BATCHES=$(( (TOTAL_KINDS + BATCH_SIZE - 1) / BATCH_SIZE ))

echo "Safe ornamentation v2 MIDI generation"
echo "  ${BATCH_SIZE} kinds per batch, ${NUM_BATCHES} batches"
echo "  ${SCARB_TEST_SLEEP}s pause between tests, ${BATCH_PAUSE}s between batches"
echo ""

# Catalog first (all 35 kinds in one file)
SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP}" CATALOG_ONLY=1 ./scripts/generate_ornamentation_v2_demo_midis.sh

for batch in $(seq 1 "${NUM_BATCHES}"); do
  echo ""
  echo "========== Batch ${batch}/${NUM_BATCHES} =========="
  SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP}" BATCH="${batch}" BATCH_SIZE="${BATCH_SIZE}" \
    ./scripts/generate_ornamentation_v2_demo_midis.sh
  if [ "${batch}" -lt "${NUM_BATCHES}" ]; then
    echo "Cooling down ${BATCH_PAUSE}s before next batch..."
    sleep "${BATCH_PAUSE}"
  fi
done

echo ""
echo "All ornamentation v2 MIDIs generated in demos/ornamentation_v2/"
ls -lh demos/ornamentation_v2/*.mid

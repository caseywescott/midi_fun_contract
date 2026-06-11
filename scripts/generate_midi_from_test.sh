#!/bin/bash
# Generate one MIDI file from a single #[ignore] MIDI-export test.
#
# Usage:
#   ./scripts/generate_midi_from_test.sh renaissance_canon_long_3voice_v2_ornamented_midi_test \
#     demos/renaissance/renaissance_canon_long_3voice_v2_ornamented.mid
#
# Throttle: SCARB_TEST_SLEEP=5 ./scripts/generate_midi_from_test.sh ...

set -euo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/lib/scarb_throttle.sh"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <test_filter> <output.mid>"
  exit 1
fi

TEST_FILTER="$1"
OUTPUT_MID="$2"
PARSER="${OUTPUT_MID%.mid}_parser.cairo"

mkdir -p "$(dirname "${OUTPUT_MID}")"

if [ ! -d "typescript/node_modules" ]; then
  echo "Installing TypeScript dependencies..."
  (cd typescript && npm install)
fi

scarb_build_once

echo "=== ${TEST_FILTER} -> ${OUTPUT_MID} ==="
scarb_test_filtered "${TEST_FILTER}" 1 2>&1 | grep "^Message::" > "${PARSER}"
npx ts-node typescript/src/simpleMidiConverter.ts "${PARSER}" "${OUTPUT_MID}"
echo "Wrote ${OUTPUT_MID}"

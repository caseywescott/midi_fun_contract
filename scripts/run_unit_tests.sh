#!/bin/bash
# Run unit tests only — skips heavy MIDI-export modules that dump megabytes to stdout.
# Much safer on laptops than bare `scarb test`.
#
# Usage:
#   ./scripts/run_unit_tests.sh              # all light modules, 3s pause between each
#   SCARB_TEST_SLEEP=5 ./scripts/run_unit_tests.sh
#   ./scripts/run_unit_tests.sh test_ornamentation_v2   # single module

set -euo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/lib/scarb_throttle.sh"

LIGHT_MODULES=(
  test_aesthetic_profiles
  test_jazz_improv
  test_ligeti
  test_canon_rules
  test_counterpoint
  test_voice_leading
  test_melodic_canon
  test_canon_fitter
  test_entry_lag_canon
  test_baroque_improvisation
  test_euclidean
  test_messiaen_modes
  test_lcg
  test_rhythmic_tiling
  test_sine_wave
  test_symmetry_engine
  test_tendency_mask
  test_motif_algebra
  test_transform
  test_timeline_rhythm
  test_phase_rhythm
  test_harmonic_walk
  test_barry_harris
  test_barry_voiceleading
  test_ornamentation_v2
)

run_module() {
  local mod="$1"
  echo ""
  echo "=== ${mod} ==="
  SCARB_UI_VERBOSITY=quiet scarb test -- --filter "${mod}"
  throttle_sleep
}

scarb_build_once

if [ "$#" -gt 0 ]; then
  for mod in "$@"; do
    run_module "${mod}"
  done
else
  echo "Running ${#LIGHT_MODULES[@]} light test modules (${SCARB_TEST_SLEEP}s pause between each)..."
  echo "Skipped (MIDI export — use ./scripts/generate_*_demo_midis.sh):"
  echo "  midi_2_cairo_print, test_*_midi"
  for mod in "${LIGHT_MODULES[@]}"; do
    run_module "${mod}"
  done
fi

echo ""
echo "Light unit tests finished."

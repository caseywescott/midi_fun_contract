# Shared helpers for low-memory / low-thermal scarb test runs.
# Source from other scripts: source "$(dirname "$0")/lib/scarb_throttle.sh"

# Seconds to pause between test invocations (cooldown for CPU/RAM).
# Override: SCARB_TEST_SLEEP=5 ./scripts/...
SCARB_TEST_SLEEP="${SCARB_TEST_SLEEP:-3}"

throttle_sleep() {
  if [ "${SCARB_TEST_SLEEP}" -gt 0 ] 2>/dev/null; then
    sleep "${SCARB_TEST_SLEEP}"
  fi
}

# One-time compile before a batch of filtered runs.
scarb_build_once() {
  echo "Building test binary (once)..."
  SCARB_UI_VERBOSITY=quiet scarb build
}

# Run a single filtered test. MIDI demo tests are #[ignore] — pass include_ignored=1.
# Usage: scarb_test_filtered "ornament_v2_01_passing_asc_midi_test" 1
scarb_test_filtered() {
  local filter="$1"
  local include_ignored="${2:-0}"
  local extra_args=()
  if [ "${include_ignored}" = "1" ]; then
    extra_args+=(--include-ignored)
  fi
  SCARB_UI_VERBOSITY=quiet scarb test -- "${extra_args[@]}" --filter "${filter}"
}

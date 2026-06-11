#!/bin/bash
# Long ornamented MIDI demos for harmonic substitution walk + profile-24 walk canon.
# Run from midi_fun_contract/: ./scripts/generate_harmonic_walk_demo_midis.sh

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
  SCARB_UI_VERBOSITY=quiet scarb test -- --include-ignored --filter "${test_name}" 2>&1 \
    | eval "${GREP_FILTER}" > "${parser_path}"
  npx ts-node typescript/src/simpleMidiConverter.ts "${parser_path}" "${out_path}"
  echo "Wrote ${out_path}"
}

mkdir -p demos/harmonic_walk

echo "Generating harmonic-walk block-harmony demos (ornamented min-motion)..."

generate_one harmonic_walk_min_motion_ornate_long_midi_test \
  demos/harmonic_walk/01_min_motion_walk_ornate_long.mid
generate_one harmonic_walk_blues_rewrite_long_midi_test \
  demos/harmonic_walk/02_blues_rewrite_ornate_long.mid
generate_one harmonic_walk_surprise_continuation_long_midi_test \
  demos/harmonic_walk/03_surprise_continuation_ornate_long.mid

echo ""
echo "Generating profile-24 jazz canon + harmonic-walk material gates..."

generate_one jazz_improv_harmonic_walk_ornate_long_4v_midi_test \
  demos/harmonic_walk/04_jazz_canon_walk_4v_ornate_long.mid
generate_one jazz_improv_harmonic_walk_ornate_long_3v_midi_test \
  demos/harmonic_walk/05_jazz_canon_walk_3v_ornate_long.mid
generate_one jazz_improv_harmonic_walk_dense_ornate_midi_test \
  demos/harmonic_walk/06_jazz_canon_walk_dense_ornate.mid

echo ""
echo "Done. Files in $(pwd)/demos/harmonic_walk/"
ls -1 demos/harmonic_walk/*.mid

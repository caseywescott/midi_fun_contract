#!/bin/sh
# Runs contracts/beast_music's Genesis parity fixture one batch at a time (4 species, normal and shiny;
# each batch is its own Cairo VM run) and writes the GEN lines to $1. FIXTURE=name_parity_fixture_
# runs the name-track fixture instead (its NAME lines; check with scripts/name_parity.mjs), and
# FIXTURE=seeded_parity_fixture_ the bought-track fixture (SEED lines; scripts/seeded_parity.mjs).
# A watchdog stops a batch that grows past $2 MB of resident memory (default 6000).
#   sh scripts/genesis_parity_cairo.sh /tmp/gen.txt && node scripts/genesis_parity.mjs /tmp/gen.txt
out=${1:-/tmp/gen.txt}; limit_mb=${2:-6000}; fixture=${FIXTURE:-genesis_parity_fixture_}
if [ "$fixture" = genesis_parity_fixture_ ]; then tag=GEN; elif [ "$fixture" = seeded_parity_fixture_ ]; then tag=SEED; elif [ "$fixture" = drift_parity_fixture_ ]; then tag=DRIFT; else tag=NAME; fi
cd "$(dirname "$0")/../contracts/beast_music" || exit 2
: > "$out"
scarb build >/dev/null 2>&1 || { echo "build failed"; exit 2; }
for i in $(seq -w 0 18); do
  scarb test -- --include-ignored --filter "$fixture$i" > "${TMPDIR:-/tmp}/genesis_batch_$i.txt" 2>&1 &
  pid=$!
  peak=0
  while kill -0 $pid 2>/dev/null; do
    rss=$(ps -axo rss=,command= | grep "scarb-cairo-test" | grep -v grep | awk '{s+=$1} END {print int(s/1024)}')
    [ "${rss:-0}" -gt "$peak" ] && peak=$rss
    if [ "${rss:-0}" -gt "$limit_mb" ]; then
      pkill -f "scarb-cairo-test" ; kill $pid 2>/dev/null
      echo "batch $i stopped: ${rss} MB > ${limit_mb} MB"; exit 1
    fi
    sleep 1
  done
  wait $pid; code=$?
  grep "^$tag " "${TMPDIR:-/tmp}/genesis_batch_$i.txt" >> "$out"
  n=$(grep -c "^$tag " "${TMPDIR:-/tmp}/genesis_batch_$i.txt")
  echo "batch $i: $n cases, peak ${peak} MB, exit $code"
  [ $code -ne 0 ] && { grep -E "panicked|error" "${TMPDIR:-/tmp}/genesis_batch_$i.txt" | head -3; exit 1; }
done
echo "done: $(grep -c "^$tag " "$out") cases in $out"

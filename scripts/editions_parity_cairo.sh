#!/bin/sh
# Runs beasts/beast_composer's Monthly Track Editions parity fixture one edition at a time (three
# cases each, its own VM run) and writes the ED lines to $1; check them with
# scripts/editions_parity.mjs. $2 $3 = first and last edition (default 1 36). A watchdog stops a
# batch past $4 MB of resident memory (default 6000); it kills every `snforge test` process on the
# machine: run nothing else under snforge meanwhile.
#   sh scripts/editions_parity_cairo.sh /tmp/ed.txt && node scripts/editions_parity.mjs /tmp/ed.txt
out=${1:-/tmp/ed.txt}; first=${2:-1}; last=${3:-36}; limit_mb=${4:-6000}
cd "$(dirname "$0")/../beasts/beast_composer" || exit 2
: > "$out"
scarb build >/dev/null 2>&1 || { echo "build failed"; exit 2; }
for i in $(seq -f %02g "$first" "$last"); do
  log="${TMPDIR:-/tmp}/editions_batch_$i.txt"
  scarb test -- "editions_parity_fixture_$i" --include-ignored > "$log" 2>&1 &
  pid=$!
  peak=0
  while kill -0 $pid 2>/dev/null; do
    rss=$(ps -axo rss=,command= | grep "snforge test" | grep -v grep | awk '{s+=$1} END {print int(s/1024)}')
    [ "${rss:-0}" -gt "$peak" ] && peak=$rss
    if [ "${rss:-0}" -gt "$limit_mb" ]; then
      pkill -f "snforge test" ; kill $pid 2>/dev/null
      echo "batch $i stopped: ${rss} MB > ${limit_mb} MB"; exit 1
    fi
    sleep 1
  done
  wait $pid; code=$?
  grep "^ED " "$log" >> "$out"
  gas=$(grep -o "l2_gas: ~[0-9]*" "$log" | head -1)
  echo "batch $i: $(grep -c "^ED " "$log") cases, peak ${peak} MB, $gas, exit $code"
  [ $code -ne 0 ] && { grep -E "panicked|error|0x" "$log" | head -3; exit 1; }
done
echo "done: $(grep -c "^ED " "$out") cases in $out"

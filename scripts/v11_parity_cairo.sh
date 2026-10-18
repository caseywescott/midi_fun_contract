#!/bin/sh
# Runs beasts/beast_composer's v1.1 parity fixture one batch at a time (each batch is its own Cairo VM
# run: about 3 GB peak; all 75 cases in one run needed about 41 GB) and writes the V11 lines to $1.
# A watchdog stops a batch that grows past $2 MB of resident memory (default 6000).
#   sh scripts/v11_parity_cairo.sh /tmp/v11.txt && node scripts/v11_parity.mjs /tmp/v11.txt
# The watchdog sums and, past the limit, kills every `snforge test` process on the machine (bench
# runs and other worktrees too): run nothing else under snforge meanwhile.
out=${1:-/tmp/v11.txt}; limit_mb=${2:-6000}
cd "$(dirname "$0")/../beasts/beast_composer" || exit 2
: > "$out"
scarb build >/dev/null 2>&1 || { echo "build failed"; exit 2; }
for i in $(seq -w 0 18); do
  scarb test -- "v11_parity_fixture_$i" --include-ignored > "/tmp/v11_batch_$i.txt" 2>&1 &
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
  grep "^V11 " "/tmp/v11_batch_$i.txt" >> "$out"
  n=$(grep -c "^V11 " "/tmp/v11_batch_$i.txt")
  echo "batch $i: $n cases, peak ${peak} MB, exit $code"
  [ $code -ne 0 ] && { grep -E "panicked|error" "/tmp/v11_batch_$i.txt" | head -3; exit 1; }
done
echo "done: $(grep -c '^V11 ' "$out") cases in $out"

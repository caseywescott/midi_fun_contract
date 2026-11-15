#!/bin/sh
# Runs the Rounds parity fixture (loot/loot_composer/src/rounds_parity.cairo) one batch of four cases
# per invocation, each through scripts/cairo_run.sh (the machine-wide lock and memory watchdog), and
# writes the RD lines to $1; check them with scripts/rounds_parity.mjs. $2 $3 = first and last batch.
#   sh scripts/rounds_parity_cairo.sh /tmp/rd.txt && node scripts/rounds_parity.mjs /tmp/rd.txt
# (KIND=checks PREFIX=CK runs the Sound Checks fixture the same way.)
kind=${KIND:-rounds}; prefix=${PREFIX:-RD}
out=${1:-/tmp/rd.txt}; first=${2:-1}; last=${3:-$(grep -c "^fn ${kind}_parity_" "$(dirname "$0")/../loot/loot_composer/src/${kind}_parity.cairo")}
cd "$(dirname "$0")/.." || exit 2
: > "$out"
for i in $(seq -f %02g "$first" "$last"); do
  log="${TMPDIR:-/tmp}/${kind}_batch_$i.txt"
  sh scripts/cairo_run.sh scarb test -p loot_composer -- "${kind}_parity_$i" --include-ignored > "$log" 2>&1
  code=$?
  grep "^$prefix " "$log" >> "$out"
  gas=$(grep -o "l2_gas: ~[0-9]*" "$log" | head -1)
  peak=$(grep -o "peak [0-9]* MB" "$log" | tail -1)
  echo "batch $i: $(grep -c "^$prefix " "$log") cases, $peak, $gas, exit $code"
  [ $code -ne 0 ] && { grep -E "panicked|error|Failure|0x" "$log" | head -5; exit 1; }
done
echo "done: $(grep -c "^$prefix " "$out") cases in $out"

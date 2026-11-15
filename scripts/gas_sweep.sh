#!/bin/sh
# l2 gas of every Round (KIND=rounds) or Sound Check (KIND=checks) parity case, one case per test, ten
# tests per invocation through scripts/cairo_run.sh; prints min / median / max.
#   KIND=rounds sh scripts/gas_sweep.sh
kind=${KIND:-rounds}
cd "$(dirname "$0")/.." || exit 2
n=$(grep -c "^fn ${kind}_gas_" "loot/loot_composer/src/${kind}_parity.cairo")
out="${TMPDIR:-/tmp}/${kind}_gas.txt"; : > "$out"
g=0
while [ $((g * 10)) -lt "$n" ]; do
  sh scripts/cairo_run.sh scarb test -p loot_composer -- "${kind}_gas_$(printf %02d $g)" --include-ignored 2>&1 \
    | grep -o "${kind}_gas_[0-9]* (l1_gas: ~0, l1_data_gas: ~0, l2_gas: ~[0-9]*" | sed 's/ (.*l2_gas: ~/ /' >> "$out"
  g=$((g + 1))
done
sort -k2 -n "$out" | awk '{v[NR]=$2; c[NR]=$1} END {print NR " cases: min " v[1] " (" c[1] "), median " v[int((NR+1)/2)] ", max " v[NR] " (" c[NR] ")"}'

#!/bin/sh
# Runs one Cairo command (scarb build / scarb test ...) at a time across every worktree of this repo
# and every agent: waits for a machine-wide lock, then runs the command with a resident-memory
# watchdog over its own process tree (default 6000 MB, LIMIT_MB=...). The Mac has 16 GB; a heavy
# fixture once grew to 41 GB. Never run scarb/snforge outside this wrapper.
#   sh scripts/cairo_run.sh scarb test -- common
lock=/tmp/loot-cairo.lock; limit=${LIMIT_MB:-6000}
while ! mkdir "$lock" 2>/dev/null; do
  owner=$(cat "$lock/pid" 2>/dev/null)
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then rm -rf "$lock"; continue; fi
  sleep 3
done
echo $$ > "$lock/pid"
trap 'rm -rf "$lock"' EXIT INT TERM
"$@" &
pid=$!
peak=0
tree_rss() { ps -axo pid=,ppid=,rss= | awk -v root="$1" '{p[$1]=$2; r[$1]=$3} END {s=0; for (k in p) {x=k; while (x != "" && x != 0 && x != 1) { if (x == root) { s += r[k]; break } x = p[x] } } print int(s/1024)}'; }
while kill -0 $pid 2>/dev/null; do
  rss=$(tree_rss $pid)
  [ "${rss:-0}" -gt "$peak" ] && peak=$rss
  if [ "${rss:-0}" -gt "$limit" ]; then
    echo "cairo_run: stopped at ${rss} MB > ${limit} MB" >&2
    pkill -TERM -P $pid 2>/dev/null; kill $pid 2>/dev/null; sleep 1; pkill -KILL -P $pid 2>/dev/null
    exit 137
  fi
  sleep 1
done
wait $pid; code=$?
echo "cairo_run: exit $code, peak ${peak} MB" >&2
exit $code

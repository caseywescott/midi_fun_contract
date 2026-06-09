#!/usr/bin/env bash
# 10-minute agent loop for Barry Harris harmony milestones (BH1 → X).
#
# Usage:
#   ./scripts/agent_loop_barry_harris.sh start   # background loop (tick every 10m)
#   ./scripts/agent_loop_barry_harris.sh once    # emit one tick now
#   ./scripts/agent_loop_barry_harris.sh stop    # stop background loop
#   ./scripts/agent_loop_barry_harris.sh status  # show PID + next milestone
#
# Cursor agent: monitor output matching ^AGENT_LOOP_TICK_BARRY_HARRIS
# Chat alternative: /loop 10m Follow midi_fun_contract/.cursor/barry-harris-loop-prompt.md

set -euo pipefail

INTERVAL_SEC="${BARRY_HARRIS_LOOP_INTERVAL_SEC:-600}"
SENTINEL="AGENT_LOOP_TICK_BARRY_HARRIS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PID_FILE="${CONTRACT_DIR}/.cursor/barry-harris-loop.pid"
LOG_FILE="${CONTRACT_DIR}/.cursor/barry-harris-loop.log"

emit_tick() {
  local payload compact
  payload="$(cd "${CONTRACT_DIR}" && python3 scripts/barry_harris_loop_next.py)"
  compact="$(PAYLOAD="${payload}" python3 - <<'PY'
import json, os
d = json.loads(os.environ["PAYLOAD"])
d["prompt_file"] = "midi_fun_contract/.cursor/barry-harris-loop-prompt.md"
d["instruction"] = (
    f"Implement milestone {d.get('next_milestone')} only. "
    "Read prompt_file. Run scarb test. Update spec checkboxes."
)
print(json.dumps(d, separators=(",", ":")))
PY
)"
  echo "${SENTINEL} ${compact}"
  {
    echo "--- $(date -u +"%Y-%m-%dT%H:%M:%SZ") ---"
    echo "${SENTINEL} ${compact}"
  } >> "${LOG_FILE}"
}

start_loop() {
  mkdir -p "${CONTRACT_DIR}/.cursor"
  if [[ -f "${PID_FILE}" ]]; then
    local old_pid
    old_pid="$(cat "${PID_FILE}")"
    if kill -0 "${old_pid}" 2>/dev/null; then
      echo "Loop already running (pid ${old_pid}). Use: $0 stop"
      exit 1
    fi
  fi
  (
    while true; do
      sleep "${INTERVAL_SEC}"
      emit_tick
    done
  ) >> "${LOG_FILE}" 2>&1 &
  echo $! > "${PID_FILE}"
  echo "Started barry-harris loop pid=$(cat "${PID_FILE}") interval=${INTERVAL_SEC}s"
  echo "First automated tick in ${INTERVAL_SEC}s. Log: ${LOG_FILE}"
  echo "Run first milestone now: $0 once"
  cd "${CONTRACT_DIR}" && python3 scripts/barry_harris_loop_next.py
}

stop_loop() {
  if [[ ! -f "${PID_FILE}" ]]; then
    echo "No loop PID file."
    exit 0
  fi
  local pid
  pid="$(cat "${PID_FILE}")"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" || true
    echo "Stopped loop pid=${pid}"
  else
    echo "Loop pid ${pid} not running."
  fi
  rm -f "${PID_FILE}"
}

status_loop() {
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "running pid=$(cat "${PID_FILE}") interval=${INTERVAL_SEC}s"
  else
    echo "not running"
  fi
  cd "${CONTRACT_DIR}" && python3 scripts/barry_harris_loop_next.py
}

cmd="${1:-start}"
case "${cmd}" in
  start) start_loop ;;
  stop) stop_loop ;;
  once) emit_tick ;;
  status) status_loop ;;
  *)
    echo "Usage: $0 {start|stop|once|status}"
    exit 1
    ;;
esac

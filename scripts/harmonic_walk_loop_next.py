#!/usr/bin/env python3
"""
Resolve the next harmonic-walk implementation milestone for the agent loop.

Reads docs/harmonic_substitution_walk_spec.md task checkboxes and optional
.cursor/harmonic-walk-loop-state.json progress.

Usage:
    python3 scripts/harmonic_walk_loop_next.py
    python3 scripts/harmonic_walk_loop_next.py --record-complete H1
    python3 scripts/harmonic_walk_loop_next.py --json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CONTRACT_DIR = SCRIPT_DIR.parent
REPO_ROOT = CONTRACT_DIR.parent
SPEC_PATH = REPO_ROOT / "docs" / "harmonic_substitution_walk_spec.md"
STATE_PATH = CONTRACT_DIR / ".cursor" / "harmonic-walk-loop-state.json"

MILESTONE_ORDER = ["H1", "H2", "H3", "H4", "H5", "H6", "X"]

HEADING_RE = re.compile(r"^### (H[1-6]|X|Cross-cutting) —")
TASK_RE = re.compile(r"^- \[( |x)\] \*\*((?:H\d+\.\d+|X\.\d+))\*\*")


def load_spec() -> str:
    if not SPEC_PATH.is_file():
        raise SystemExit(f"Spec not found: {SPEC_PATH}")
    return SPEC_PATH.read_text(encoding="utf-8")


def parse_milestones(text: str) -> dict[str, dict]:
    """Return {milestone_id: {total, done, open_tasks[]}}."""
    current: str | None = None
    out: dict[str, dict] = {
        mid: {"total": 0, "done": 0, "open_tasks": []} for mid in MILESTONE_ORDER
    }

    for line in text.splitlines():
        heading = HEADING_RE.match(line)
        if heading:
            raw = heading.group(1)
            current = "X" if raw == "Cross-cutting" else raw
            continue
        if current is None:
            continue
        task = TASK_RE.match(line)
        if not task:
            continue
        checked, task_id = task.group(1), task.group(2)
        out[current]["total"] += 1
        if checked == "x":
            out[current]["done"] += 1
        else:
            out[current]["open_tasks"].append(task_id)

    return out


def load_state() -> dict:
    if not STATE_PATH.is_file():
        return {"completed_milestones": [], "history": []}
    return json.loads(STATE_PATH.read_text(encoding="utf-8"))


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def next_milestone(stats: dict[str, dict]) -> str | None:
    for mid in MILESTONE_ORDER:
        info = stats[mid]
        if info["total"] == 0:
            continue
        if info["done"] < info["total"]:
            return mid
    return None


def build_payload(stats: dict[str, dict], state: dict) -> dict:
    nxt = next_milestone(stats)
    remaining = [m for m in MILESTONE_ORDER if stats[m]["done"] < stats[m]["total"]]
    return {
        "spec": str(SPEC_PATH.relative_to(REPO_ROOT)),
        "prompt_file": str(
            (CONTRACT_DIR / ".cursor" / "harmonic-walk-loop-prompt.md").relative_to(REPO_ROOT)
        ),
        "next_milestone": nxt,
        "done": nxt is None,
        "remaining": remaining,
        "milestones": {
            mid: {
                "done": stats[mid]["done"],
                "total": stats[mid]["total"],
                "open_tasks": stats[mid]["open_tasks"],
            }
            for mid in MILESTONE_ORDER
        },
        "completed_milestones": state.get("completed_milestones", []),
    }


def record_complete(milestone: str) -> None:
    if milestone not in MILESTONE_ORDER:
        raise SystemExit(f"Unknown milestone: {milestone}")
    state = load_state()
    completed = state.setdefault("completed_milestones", [])
    if milestone not in completed:
        completed.append(milestone)
    state.setdefault("history", []).append(
        {
            "milestone": milestone,
            "recorded_at": datetime.now(timezone.utc).isoformat(),
        }
    )
    save_state(state)


def main() -> int:
    parser = argparse.ArgumentParser(description="Harmonic walk loop milestone resolver")
    parser.add_argument(
        "--record-complete",
        metavar="MILESTONE",
        help="Record milestone complete in loop state (H1..H6 or X)",
    )
    parser.add_argument("--json", action="store_true", help="Pretty-print JSON (default)")
    args = parser.parse_args()

    if args.record_complete:
        mid = args.record_complete.upper()
        if mid not in MILESTONE_ORDER:
            raise SystemExit(f"Unknown milestone: {args.record_complete} (use H1..H6 or X)")
        record_complete(mid)
        stats = parse_milestones(load_spec())
        payload = build_payload(stats, load_state())
        print(json.dumps(payload, indent=2))
        return 0

    stats = parse_milestones(load_spec())
    state = load_state()
    payload = build_payload(stats, state)
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

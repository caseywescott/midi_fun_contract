"""Verify fixtures via scarb test + Python mirror checks."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict

from .candidates import all_pairs_valid
from .profile_mirror import profile_by_id
from .recognize import sequence_steps_valid

ROOT = Path(__file__).resolve().parents[2]


def verify_fixture(path: Path) -> Dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    catalog = json.loads((ROOT / "fixtures/canon/config_catalog.json").read_text())
    cfg = next(c for c in catalog["configs"] if c["config_id"] == data["config_id"])
    profile = profile_by_id(cfg["profile_id"])
    leader = data["leader_degrees"]
    entries = data.get("entries")
    ok_steps = sequence_steps_valid(leader, cfg, profile, entries)
    ok_pairs = all_pairs_valid(leader, cfg["offsets"], profile, entries)
    edit = sum(abs(leader[i] - data["input_degrees"][i]) for i in range(len(leader)))
    return {
        "fixture": str(path),
        "python_steps_valid": ok_steps,
        "python_pairs_valid": ok_pairs,
        "edit_cost_recomputed": edit,
        "edit_cost_fixture": data["edit_cost"],
    }


def run_scarb_tests() -> int:
    proc = subprocess.run(
        ["scarb", "test", "-f", "test_canon_fitter"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    print(proc.stdout)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
    return proc.returncode

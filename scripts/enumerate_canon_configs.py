#!/usr/bin/env python3
"""Export canon config catalogue for the offline fitter (mirrors canon_rules.cairo)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "fixtures" / "canon" / "config_catalog.json"

# Mirrors profiled_config_by_id / config_by_id tables in src/composition/canon_rules.cairo
CONFIGS: List[Dict[str, Any]] = [
    {"config_id": 0, "name": "fifth_above", "offsets": [0, 4], "octave": 7, "profile_id": 0},
    {"config_id": 1, "name": "fifth_below", "offsets": [0, -4], "octave": 7, "profile_id": 0},
    {"config_id": 2, "name": "octave_above", "offsets": [0, 7], "octave": 7, "profile_id": 0},
    {"config_id": 3, "name": "unison", "offsets": [0, 0], "octave": 7, "profile_id": 0},
    {"config_id": 4, "name": "three_5b_8va", "offsets": [0, -4, 3], "octave": 7, "profile_id": 0},
    {"config_id": 5, "name": "three_5a_8vb", "offsets": [0, 4, -3], "octave": 7, "profile_id": 0},
    {"config_id": 6, "name": "four_5b_stack", "offsets": [0, -4, -8, -12], "octave": 7, "profile_id": 0},
    {"config_id": 7, "name": "maj7_stack", "offsets": [0, 4, 7, 11], "octave": 12, "profile_id": 1},
    {"config_id": 8, "name": "min7_stack", "offsets": [0, 3, 7, 10], "octave": 12, "profile_id": 1},
    {"config_id": 9, "name": "dom7_planing", "offsets": [0, 4, 7, 10], "octave": 12, "profile_id": 3},
    {"config_id": 10, "name": "quartal_stack", "offsets": [0, 5, 10], "octave": 12, "profile_id": 2},
    {"config_id": 11, "name": "quartal4_stack", "offsets": [0, 5, 10, 15], "octave": 12, "profile_id": 2},
    {"config_id": 12, "name": "hindemith4", "offsets": [0, 5, 7, 11], "octave": 12, "profile_id": 4},
    {"config_id": 13, "name": "white_on_white", "offsets": [0, 7], "octave": 7, "profile_id": 5},
    {"config_id": 14, "name": "ligeti_cluster", "offsets": [0, 1, 2, 3], "octave": 7, "profile_id": 5},
    {"config_id": 15, "name": "ligeti_micro", "offsets": [0, 1, 2], "octave": 12, "profile_id": 6},
    {"config_id": 16, "name": "dom9_planing", "offsets": [0, 4, 10, 14], "octave": 12, "profile_id": 3},
    {"config_id": 17, "name": "lydian_maj9", "offsets": [0, 4, 11, 14], "octave": 12, "profile_id": 7},
    {"config_id": 18, "name": "dom_alt_b9", "offsets": [0, 4, 10, 13], "octave": 12, "profile_id": 8},
    {"config_id": 19, "name": "whole_tone", "offsets": [0, 4, 8, 10], "octave": 12, "profile_id": 9},
    {"config_id": 20, "name": "oct_axis", "offsets": [0, 3, 6, 9], "octave": 12, "profile_id": 10},
    {"config_id": 21, "name": "sus_quartal", "offsets": [0, 2, 5, 10], "octave": 12, "profile_id": 11},
    {"config_id": 22, "name": "pandiatonic", "offsets": [0, 1, 4, 6], "octave": 7, "profile_id": 12},
    {"config_id": 23, "name": "spectral", "offsets": [0, 4, 7, 10], "octave": 12, "profile_id": 13},
    {"config_id": 24, "name": "bartok_axis", "offsets": [0, 3, 6, 9], "octave": 12, "profile_id": 14},
    {"config_id": 25, "name": "cluster_soft", "offsets": [0, 1, 3], "octave": 12, "profile_id": 15},
    {"config_id": 26, "name": "per_tonos", "offsets": [0, 4, 7, 11], "octave": 12, "profile_id": 16},
    {"config_id": 27, "name": "impr_add6", "offsets": [0, 4, 9, 14], "octave": 12, "profile_id": 17},
    {"config_id": 28, "name": "bitonal", "offsets": [0, 4, 6, 10], "octave": 12, "profile_id": 18},
    {"config_id": 29, "name": "phrygian", "offsets": [0, 1, 5, 8], "octave": 12, "profile_id": 19},
    {"config_id": 30, "name": "penta_open", "offsets": [0, 7, 14, 21], "octave": 12, "profile_id": 20},
    {"config_id": 31, "name": "neo_riem", "offsets": [0, 4, 7], "octave": 12, "profile_id": 21},
    {"config_id": 32, "name": "impr_add6_3", "offsets": [0, 4, 9], "octave": 12, "profile_id": 17},
    {"config_id": 33, "name": "bitonal_3", "offsets": [0, 4, 6], "octave": 12, "profile_id": 18},
    {"config_id": 34, "name": "phrygian_3", "offsets": [0, 1, 5], "octave": 12, "profile_id": 19},
    {"config_id": 35, "name": "penta_open_3", "offsets": [0, 7, 14], "octave": 12, "profile_id": 20},
    {"config_id": 36, "name": "neo_riem_4", "offsets": [0, 4, 7, 11], "octave": 12, "profile_id": 21},
    {"config_id": 37, "name": "impr_smooth", "offsets": [0, 4, 9, 14], "octave": 12, "profile_id": 23},
    {"config_id": 38, "name": "impr_smooth_3", "offsets": [0, 4, 9], "octave": 12, "profile_id": 23},
    {"config_id": 39, "name": "penta_smooth", "offsets": [0, 7, 14, 21], "octave": 12, "profile_id": 22},
    {"config_id": 40, "name": "penta_smooth_3", "offsets": [0, 7, 14], "octave": 12, "profile_id": 22},
    {"config_id": 41, "name": "jazz_improv", "offsets": [0, 4, 7, 11], "octave": 12, "profile_id": 24},
    {"config_id": 42, "name": "jazz_improv_3", "offsets": [0, 4, 7], "octave": 12, "profile_id": 24},
]

PROFILE_NAMES = {
    0: "renaissance",
    1: "jazz",
    2: "quartal",
    3: "planing",
    4: "hindemith",
    5: "ligeti_white",
    6: "ligeti_micro",
}


def build_catalog() -> Dict[str, Any]:
    rows = []
    for c in CONFIGS:
        pid = c["profile_id"]
        rows.append(
            {
                **c,
                "profile_name": PROFILE_NAMES.get(pid, f"profile_{pid}"),
                "lattice": "diatonic" if c["octave"] == 7 else "chromatic",
                "voice_count": len(c["offsets"]),
            }
        )
    return {"version": 1, "config_count": len(rows), "configs": rows}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Check committed JSON matches")
    args = parser.parse_args()
    catalog = build_catalog()
    if args.verify:
        if not OUT.exists():
            print(f"Missing {OUT}")
            return 1
        on_disk = json.loads(OUT.read_text(encoding="utf-8"))
        if on_disk != catalog:
            print("config_catalog.json is out of date — run without --verify")
            return 1
        print(f"OK: {OUT} matches embedded tables ({catalog['config_count']} configs)")
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT} ({catalog['config_count']} configs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Offline harmonic walk catalog report."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPORT_DIR = ROOT / "fixtures" / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)


def main() -> int:
    subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "extract_harmonic_rules.py")],
        check=True,
    )
    subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "build_harmonic_ngrams.py")],
        check=True,
    )
    report = {
        "module": "harmonic_walk_v1",
        "rewrite_fixture": "fixtures/harmonic_rewrites.json",
        "continuation_fixture": "fixtures/harmonic_continuations.json",
        "skeletons": ["turnaround_axiom_3", "two_five_one_1", "blues_12", "rhythm_changes_32"],
        "tests": "scarb test -f test_harmonic",
    }
    out_json = REPORT_DIR / "harmonic_descriptor_report.json"
    out_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    md = REPORT_DIR / "harmonic_walk_admission.md"
    md.write_text(
        "# Harmonic walk admission\n\n"
        "- Rewrite table embedded in `known_harmonic_rewrites.cairo` (10 rules)\n"
        "- Continuation table embedded in `known_harmonic_continuations.cairo` (16 rows)\n"
        "- Run `scarb test -f test_harmonic` before listening review\n",
        encoding="utf-8",
    )
    print(f"Wrote {out_json} and {md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

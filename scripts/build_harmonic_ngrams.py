#!/usr/bin/env python3
"""Validate harmonic continuation fixture (offline LZ generation deferred)."""

from __future__ import annotations

import json
from pathlib import Path

FIXTURE = Path(__file__).resolve().parent.parent / "fixtures" / "harmonic_continuations.json"


def main() -> None:
    data = json.loads(FIXTURE.read_text(encoding="utf-8"))
    tiers = [c["surprise_tier"] for c in data["continuations"]]
    print(json.dumps({"rows": len(data["continuations"]), "tier_range": [min(tiers), max(tiers)]}, indent=2))


if __name__ == "__main__":
    main()

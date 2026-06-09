#!/usr/bin/env python3
"""Emit harmonic rewrite fixture from embedded Pachet §2.4 rules."""

from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "fixtures" / "harmonic_rewrites.json"


def main() -> None:
    data = json.loads(OUT.read_text(encoding="utf-8"))
    print(json.dumps({"rule_count": len(data["rules"]), "version": data["version"]}, indent=2))


if __name__ == "__main__":
    main()

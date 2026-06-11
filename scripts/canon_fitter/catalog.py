"""Load canon config catalogue."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "fixtures" / "canon" / "config_catalog.json"


def load_catalog(path: Optional[Path] = None) -> Dict[str, Any]:
    p = path or CATALOG_PATH
    return json.loads(p.read_text(encoding="utf-8"))


def configs_for_scope(catalog: Dict[str, Any], profile_scope: str) -> List[Dict[str, Any]]:
    configs = catalog["configs"]
    if profile_scope == "renaissance":
        return [c for c in configs if c["profile_id"] == 0]
    if profile_scope == "extended":
        return [c for c in configs if c["profile_id"] != 0]
    return list(configs)


def filter_configs(
    configs: Sequence[Dict[str, Any]], config_filter: Optional[Sequence[int]]
) -> List[Dict[str, Any]]:
    if not config_filter:
        return list(configs)
    allowed = set(config_filter)
    return [c for c in configs if c["config_id"] in allowed]

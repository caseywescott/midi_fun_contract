"""Write CanonFitResult fixtures."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional


def write_fit_result(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def build_result(
    inp: Dict[str, Any],
    fit: Dict[str, Any],
    fit_phase: str,
    configs_tried: int,
    exact_fit_count: int,
    runner_up: list,
    input_degrees_used: Optional[List[int]] = None,
) -> Dict[str, Any]:
    leader = fit["leader_degrees"]
    input_deg = input_degrees_used if input_degrees_used is not None else inp["input_degrees"]
    entries = fit.get("entries")
    if entries is None:
        nv = len(fit.get("offsets", [])) or 2
        entries = list(range(nv))
    out: Dict[str, Any] = {
        "version": 2,
        "slug": path_stem_slug(inp["source"]),
        "source": inp["source"],
        "fit_phase": fit_phase,
        "config_id": fit["config_id"],
        "config_name": fit["config_name"],
        "profile_id": fit["profile_id"],
        "mode_id": inp["mode_id"],
        "tonic_keynum": inp["tonic_keynum"],
        "octave": inp["octave"],
        "leader_degrees": leader,
        "input_degrees": input_deg,
        "edit_cost": fit.get("pitch_edit_cost", fit.get("edit_cost", 0)),
        "positions_edited": fit.get("positions_edited", []),
        "require_cadence": inp["require_cadence"],
        "entries": entries,
        "entry_mode": fit.get("entry_mode", "stacked"),
        "report": {
            "configs_tried": configs_tried,
            "exact_fit_count": exact_fit_count,
            "runner_up": runner_up,
        },
    }
    if inp.get("source_ticks"):
        out["source_ticks"] = inp["source_ticks"]
    if inp.get("source_pitches"):
        out["source_pitches"] = inp["source_pitches"]
    return out


def path_stem_slug(source: str) -> str:
    return Path(source).stem

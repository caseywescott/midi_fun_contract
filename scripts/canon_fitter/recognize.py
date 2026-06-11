"""Phase A — exact-fit recognition (zero edits)."""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence

from .candidates import all_pairs_valid
from .profile_mirror import profile_by_id
from .rules_mirror import pair_constraints, pair_constraints_from_entries, step_satisfies_constraints_profile


def sequence_steps_valid(
    degrees: Sequence[int],
    config: Dict[str, Any],
    profile,
    entries: Optional[Sequence[int]] = None,
) -> bool:
    if len(degrees) < 2:
        return len(degrees) == 1
    offsets = config["offsets"]
    if entries is None:
        constraints = pair_constraints(offsets)
        entries = list(range(len(offsets)))
    else:
        constraints = pair_constraints_from_entries(offsets, entries)
    steps: List[int] = []
    for i in range(1, len(degrees)):
        m = degrees[i] - degrees[i - 1]
        if not step_satisfies_constraints_profile(constraints, steps, m, profile):
            return False
        steps.append(m)
    return all_pairs_valid(degrees, offsets, profile, entries)


def find_exact_fits(
    input_degrees: Sequence[int],
    configs: Sequence[Dict[str, Any]],
    require_cadence: bool,
) -> List[Dict[str, Any]]:
    hits: List[Dict[str, Any]] = []
    for cfg in configs:
        profile = profile_by_id(cfg["profile_id"])
        entries = cfg.get("entries")
        if require_cadence and input_degrees[-1] != 0:
            continue
        if not sequence_steps_valid(input_degrees, cfg, profile, entries):
            continue
        hits.append(
            {
                "config_id": cfg["config_id"],
                "config_name": cfg["name"],
                "profile_id": cfg["profile_id"],
                "edit_cost": 0,
                "leader_degrees": list(input_degrees),
                "entries": list(entries) if entries else list(range(len(cfg["offsets"]))),
            }
        )
    hits.sort(key=lambda h: (h["edit_cost"], h["profile_id"], h["config_id"]))
    return hits

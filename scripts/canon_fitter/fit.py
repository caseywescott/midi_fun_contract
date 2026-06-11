"""Orchestrate recognize → viterbi → result."""

from __future__ import annotations

from typing import Any, Dict, List, Sequence

from .catalog import configs_for_scope, filter_configs, load_catalog
from .emit import build_result
from .entry_lag import expand_fit_candidates
from .recognize import find_exact_fits
from .viterbi import degrees_for_config, fit_best, fit_config


def run_fit(
    inp: Dict[str, Any],
    profile_scope: str = "renaissance",
    entry_mode: str = "stacked",
    explicit_entries: Sequence[int] | None = None,
) -> Dict[str, Any]:
    catalog = load_catalog()
    configs = configs_for_scope(catalog, profile_scope)
    configs = filter_configs(configs, inp.get("config_filter"))
    ticks = inp.get("source_ticks")
    configs = expand_fit_candidates(configs, ticks, entry_mode, explicit_entries)

    trials: List[Dict[str, Any]] = []
    exact_hits: List[Dict[str, Any]] = []

    require_cadence = inp["require_cadence"]
    for cfg in configs:
        degrees = degrees_for_config(inp, cfg)
        exact_hits.extend(find_exact_fits(degrees, [cfg], require_cadence))
        trial = fit_config(degrees, cfg, require_cadence, inp.get("anchor_start", False))
        if trial and trial["pitch_edit_cost"] <= inp["max_edit_cost"]:
            trials.append(trial)

    if exact_hits:
        exact_hits.sort(key=lambda h: (h["config_id"], h["profile_id"]))
        fit = exact_hits[0]
        inp_deg = degrees_for_config(inp, next(c for c in configs if c["config_id"] == fit["config_id"]))
        return build_result(
            inp, fit, "exact", len(configs), len(exact_hits), exact_hits[1:3],
            input_degrees_used=inp_deg,
        )

    trials.sort(key=lambda t: (t["pitch_edit_cost"], t["profile_id"], t["config_id"]))
    if not trials:
        raise RuntimeError("no fit under max_edit_cost")

    best = trials[0]
    inp_deg = degrees_for_config(inp, next(c for c in configs if c["config_id"] == best["config_id"]))
    runner_up = [
        {"config_id": t["config_id"], "edit_cost": t["pitch_edit_cost"], "config_name": t["config_name"],
         "profile_id": t["profile_id"], "entries": t.get("entries")}
        for t in trials[1:6]
    ]
    return build_result(
        inp, best, "viterbi", len(configs), 0, runner_up,
        input_degrees_used=inp_deg,
    )

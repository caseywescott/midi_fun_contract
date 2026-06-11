"""Phase B — minimal-edit Viterbi fit."""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

from .candidates import all_pairs_valid, candidate_steps, register_bounds
from .profile_mirror import melodic_step_cost, profile_by_id
from .rules_mirror import pair_constraints, pair_constraints_from_entries

W_PITCH = 10
W_STEP = 1

# Upper bound on DP states retained per position. The exact history-aware search is
# exponential in the constraint window depth; keeping the lowest-cost states bounds
# runtime while staying far wider than the old collapse-to-one-per-degree heuristic.
# The final all_pairs_valid() check guarantees soundness regardless of beam width.
MAX_BEAM = 1500

# Maximum steps of melodic history kept in the DP state. Set high enough to check every
# realistic canon window (3-/4-voice configs, entry lags well past 8) exactly online; the
# beam bounds runtime, and all_pairs_valid() is the exact final gate. Windows beyond this
# are deferred to that gate (only relevant for extreme, unused lags).
DEPTH_CAP = 16


def _edit_positions(input_degrees: Sequence[int], fitted: Sequence[int]) -> List[int]:
    return [i for i, (a, b) in enumerate(zip(input_degrees, fitted)) if a != b]


def degrees_for_config(inp: Dict[str, Any], config: Dict[str, Any]) -> List[int]:
    if config.get("octave", 7) == 12 and inp.get("chromatic_degrees"):
        return list(inp["chromatic_degrees"])
    return list(inp["input_degrees"])


def _history_depth(constraints: Sequence, profile) -> int:
    """Steps of history the online constraints actually consult.

    Window constraints read the last (w-1) steps; the parallel-perfect policy reads
    the last 2 steps. Keeping exactly this many steps in the DP state makes the search
    complete and optimal rather than collapsing to one arbitrary path per degree.
    """
    max_w = max((pc.w for pc in constraints), default=1)
    depth = max(max_w - 1, 0)
    if profile.par_policy != 2:  # not PAR_ALLOW → parallel check needs last 2 steps
        depth = max(depth, 2)
    return min(depth, DEPTH_CAP)


def fit_config(
    input_degrees: Sequence[int],
    config: Dict[str, Any],
    require_cadence: bool,
    anchor_start: bool,
) -> Optional[Dict[str, Any]]:
    profile = profile_by_id(config["profile_id"])
    offsets = config["offsets"]
    entries = config.get("entries")
    if entries is None:
        constraints = pair_constraints(offsets)
        entries = list(range(len(offsets)))
    else:
        constraints = pair_constraints_from_entries(offsets, entries)

    n = len(input_degrees)
    if n < 2:
        return None

    start = 0 if anchor_start else input_degrees[0]
    lo, hi = register_bounds(start, profile)
    depth = _history_depth(constraints, profile)

    # State = (current_degree, last `depth` steps). Value = (cost, back_state, step_in).
    State = Tuple[int, Tuple[int, ...]]
    init: State = (start, ())
    dp: List[Dict[State, int]] = [{init: W_PITCH * abs(start - input_degrees[0])}]
    back: List[Dict[State, Tuple[Optional[State], int]]] = [{init: (None, 0)}]

    for t in range(1, n):
        layer: Dict[State, int] = {}
        layer_back: Dict[State, Tuple[Optional[State], int]] = {}
        for (d_prev, hist), cost_prev in dp[t - 1].items():
            prev_steps = list(hist)
            cands = candidate_steps(
                profile, constraints, offsets, prev_steps, d_prev, lo, hi, pos=t
            )
            for m in cands:
                d_cur = d_prev + m
                if require_cadence and t == n - 1 and d_cur != 0:
                    continue
                new_hist = (tuple(prev_steps) + (m,))[-depth:] if depth else ()
                state: State = (d_cur, new_hist)
                cost = (
                    cost_prev
                    + W_PITCH * abs(d_cur - input_degrees[t])
                    + W_STEP * melodic_step_cost(m, profile)
                )
                if state not in layer or cost < layer[state]:
                    layer[state] = cost
                    layer_back[state] = ((d_prev, hist), m)
        if len(layer) > MAX_BEAM:
            kept = sorted(layer.items(), key=lambda kv: kv[1])[:MAX_BEAM]
            layer = dict(kept)
            layer_back = {s: layer_back[s] for s, _ in kept}
        dp.append(layer)
        back.append(layer_back)

    if not dp[n - 1]:
        return None
    best_state = min(dp[n - 1], key=lambda s: dp[n - 1][s])
    fitted = [0] * n
    state: Optional[State] = best_state
    for t in range(n - 1, -1, -1):
        assert state is not None
        fitted[t] = state[0]
        prev_state, _ = back[t][state]
        state = prev_state

    if not all_pairs_valid(fitted, offsets, profile, entries):
        return None

    pitch_cost = sum(abs(fitted[i] - input_degrees[i]) for i in range(n))
    return {
        "config_id": config["config_id"],
        "config_name": config["name"],
        "profile_id": config["profile_id"],
        "edit_cost": dp[n - 1][best_state],
        "pitch_edit_cost": pitch_cost,
        "leader_degrees": fitted,
        "positions_edited": _edit_positions(input_degrees, fitted),
        "entries": list(entries),
        "entry_mode": config.get("entry_mode", "stacked"),
    }


def fit_best(
    input_degrees: Sequence[int],
    configs: Sequence[Dict[str, Any]],
    require_cadence: bool,
    max_edit_cost: int,
    anchor_start: bool = False,
) -> Optional[Dict[str, Any]]:
    best: Optional[Dict[str, Any]] = None
    for cfg in configs:
        result = fit_config(input_degrees, cfg, require_cadence, anchor_start)
        if result is None:
            continue
        if result["pitch_edit_cost"] > max_edit_cost:
            continue
        if best is None or result["pitch_edit_cost"] < best["pitch_edit_cost"]:
            best = result
        elif (
            result["pitch_edit_cost"] == best["pitch_edit_cost"]
            and result["config_id"] < best["config_id"]
        ):
            best = result
    return best

"""Entry-lag canon helpers — entries from MIDI timing + constraint search."""

from __future__ import annotations

from typing import Any, Dict, List, Sequence, Tuple

from .rules_mirror import pair_constraints_from_entries


def validate_entries_vec(offsets: Sequence[int], entries: Sequence[int]) -> bool:
    if len(offsets) != len(entries) or not entries:
        return False
    if entries[0] != 0:
        return False
    for i in range(1, len(entries)):
        if entries[i] < entries[i - 1]:
            return False
    return True


def entries_stacked(n_voices: int) -> List[int]:
    return list(range(n_voices))


def entries_uniform_lag(n_voices: int, lag: int) -> List[int]:
    return [0 if i == 0 else lag for i in range(n_voices)]


def entries_stacked_lag(n_voices: int, lag: int) -> List[int]:
    return [i * lag for i in range(n_voices)]


def infer_uniform_lag_from_iois(iois: Sequence[int]) -> int:
    if not iois:
        return 1
    med = sorted(iois)[len(iois) // 2]
    if med <= 0:
        return 1
    long_gaps = sum(1 for x in iois if x >= int(med * 1.75))
    if long_gaps >= max(2, len(iois) // 6):
        return 2
    return 1


def iois_from_ticks(ticks: Sequence[int]) -> List[int]:
    if len(ticks) < 2:
        return []
    return [ticks[i] - ticks[i - 1] for i in range(1, len(ticks))]


def candidate_entry_vectors(n_voices: int, ticks: Sequence[int], max_lag: int = 4) -> List[List[int]]:
    cands: List[List[int]] = []
    seen = set()
    iois = iois_from_ticks(ticks)
    inferred = infer_uniform_lag_from_iois(iois)

    def add(entries: List[int]) -> None:
        key = tuple(entries)
        if key not in seen:
            seen.add(key)
            cands.append(entries)

    add(entries_stacked(n_voices))
    for lag in range(1, max_lag + 1):
        add(entries_uniform_lag(n_voices, lag))
        if n_voices > 2:
            add(entries_stacked_lag(n_voices, lag))
    add(entries_uniform_lag(n_voices, inferred))
    return cands


def expand_fit_candidates(
    configs: Sequence[Dict[str, Any]],
    ticks: Sequence[int] | None,
    entry_mode: str,
    explicit_entries: Sequence[int] | None = None,
) -> List[Dict[str, Any]]:
    """Attach entry vectors to each config for search.

    When `explicit_entries` is given, only configs whose voice count matches the
    vector length (and which validate) are kept — the user dictates the lags.
    """
    if explicit_entries is not None:
        expanded: List[Dict[str, Any]] = []
        entries = list(explicit_entries)
        if not entries or entries[0] != 0 or any(e < 0 for e in entries):
            raise ValueError(
                f"--entries must start at 0 and be non-negative, got {entries}"
            )
        for cfg in configs:
            if len(cfg["offsets"]) != len(entries):
                continue
            expanded.append({**cfg, "entries": entries, "entry_mode": "explicit"})
        if not expanded:
            voice_counts = sorted({len(c["offsets"]) for c in configs})
            raise ValueError(
                f"no config has {len(entries)} voices; "
                f"available voice counts in scope: {voice_counts}"
            )
        return expanded

    mode = "search" if entry_mode in ("timing", "infer") else entry_mode
    expanded = []
    for cfg in configs:
        nv = len(cfg["offsets"])
        if mode == "stacked" or not ticks:
            entries = entries_stacked(nv)
            expanded.append({**cfg, "entries": entries, "entry_mode": "stacked"})
            continue
        if mode == "uniform":
            lag = infer_uniform_lag_from_iois(iois_from_ticks(ticks))
            entries = entries_uniform_lag(nv, lag)
            expanded.append({**cfg, "entries": entries, "entry_mode": f"uniform_{lag}"})
            continue
        # search / timing / infer — try all candidates
        for entries in candidate_entry_vectors(nv, ticks):
            if validate_entries_vec(cfg["offsets"], entries):
                expanded.append({**cfg, "entries": entries, "entry_mode": "search"})
    return expanded


def structural_durations(ticks: Sequence[int], default: int) -> List[int]:
    if not ticks:
        return []
    durs = []
    for i in range(len(ticks) - 1):
        d = ticks[i + 1] - ticks[i]
        durs.append(d if d > 0 else default)
    durs.append(default)
    return durs

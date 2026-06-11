"""Export fitted canon to multi-voice MIDI (stacked + entry-lag timing)."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

from .catalog import load_catalog
from .entry_lag import structural_durations
from .ingest import MODE_SCALES
from .smf import realize_degree, write_smf


def _register_anchor(
    result: Dict[str, Any],
    degrees: Sequence[int],
    lattice: int,
    tonic: int,
    mode_id: int,
    scale: Sequence[int],
) -> int:
    """Shift all voices into the source melody's octave (uniform — preserves the canon)."""
    source = result.get("source_pitches")
    if not source:
        return 0
    expected = realize_degree(lattice, degrees[0], tonic, mode_id, scale)
    return int(source[0]) - expected


def _leader_timeline(
    result: Dict[str, Any], n: int, division: int
) -> Tuple[List[int], List[int]]:
    """Leader onset starts + durations from MIDI ticks (fallback: uniform grid)."""
    ticks: Sequence[int] | None = result.get("source_ticks")
    if ticks and len(ticks) >= n:
        base = ticks[0]
        starts = [int(t - base) for t in ticks[:n]]
        durs = structural_durations(starts, division)
        return starts, durs
    return [i * division for i in range(n)], [division] * n


def _entry_lag_ticks(entry: int, leader_starts: Sequence[int], division: int) -> int:
    """Fixed time delay for a follower entering `entry` structural notes after the leader."""
    if entry <= 0:
        return 0
    if entry < len(leader_starts):
        return leader_starts[entry] - leader_starts[0]
    # Entry beyond the melody: extend at the trailing average gap.
    span = leader_starts[-1] - leader_starts[0] if len(leader_starts) > 1 else division
    avg = span // max(1, len(leader_starts) - 1) if len(leader_starts) > 1 else division
    return span + (entry - (len(leader_starts) - 1)) * avg


def canon_note_events(result: Dict[str, Any], division: int = 480) -> List[Tuple[int, int, int, int]]:
    """Return [(voice_id, start_tick, pitch, duration_ticks), ...].

    A true canon: every follower reproduces the leader's exact pitch + rhythm contour,
    transposed by its diatonic/chromatic offset and delayed by a fixed entry-lag in ticks.
    """
    catalog = load_catalog()
    cfg = next(c for c in catalog["configs"] if c["config_id"] == result["config_id"])
    offsets = cfg["offsets"]
    entries = result.get("entries", list(range(len(offsets))))
    degrees = result["leader_degrees"]
    tonic = result["tonic_keynum"]
    mode_id = result["mode_id"]
    lattice = cfg["octave"]
    scale = MODE_SCALES[mode_id % 6]
    n = len(degrees)
    anchor = _register_anchor(result, degrees, lattice, tonic, mode_id, scale)
    leader_starts, leader_durs = _leader_timeline(result, n, division)

    events: List[Tuple[int, int, int, int]] = []
    for vi, off in enumerate(offsets):
        entry = entries[vi] if vi < len(entries) else vi
        lag = _entry_lag_ticks(entry, leader_starts, division)
        for p in range(n):
            deg = degrees[p] + off
            start = leader_starts[p] + lag
            dur = leader_durs[p]
            pitch = realize_degree(lattice, deg, tonic, mode_id, scale) + anchor
            events.append((vi, start, pitch, dur))
    return events


def write_canon_midi(result: Dict[str, Any], path: Path, division: int = 480) -> None:
    events = canon_note_events(result, division=division)
    by_voice: Dict[int, List[Tuple[int, int, int]]] = {}
    for voice_id, start, pitch, dur in events:
        by_voice.setdefault(voice_id, []).append((start, pitch, dur))
    tracks = [by_voice[k] for k in sorted(by_voice)]
    write_smf(path, tracks, division=division)

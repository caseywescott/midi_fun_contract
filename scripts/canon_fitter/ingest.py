"""Input parsing — JSON or MIDI melody specs to degree sequences."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

from .smf import extract_monophonic_pitches, read_smf, realize_degree

MODE_SCALES = {
    0: [0, 2, 4, 5, 7, 9, 11],   # Ionian
    1: [0, 2, 3, 5, 7, 9, 10],   # Dorian
    2: [0, 1, 3, 5, 7, 8, 10],   # Phrygian
    3: [0, 2, 4, 6, 7, 9, 11],   # Lydian
    4: [0, 2, 4, 5, 7, 9, 10],   # Mixolydian
    5: [0, 2, 3, 5, 7, 8, 10],   # Aeolian
}

MODE_NAMES = {
    "ionian": 0, "major": 0,
    "dorian": 1,
    "phrygian": 2,
    "lydian": 3,
    "mixolydian": 4,
    "aeolian": 5, "minor": 5, "natural_minor": 5,
}

NOTE_PC = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}

MIN_LEN = 8
MAX_LEN = 24


def parse_tonic(value: Union[str, int], octave: int = 4) -> int:
    if isinstance(value, int):
        return value
    s = value.strip().lower()
    m = re.match(r"^([a-g])([#b]?)(?:-?(\d))?$", s)
    if not m:
        raise ValueError(f"cannot parse tonic: {value}")
    name, acc, oct_s = m.groups()
    pc = NOTE_PC[name]
    if acc == "#":
        pc += 1
    elif acc == "b":
        pc -= 1
    oct_n = int(oct_s) if oct_s else octave
    return (oct_n + 1) * 12 + (pc % 12)


def parse_mode(value: Union[str, int]) -> int:
    if isinstance(value, int):
        return value % 6
    return MODE_NAMES[value.strip().lower()]


def load_input(
    path: Path,
    *,
    tonic: Optional[Union[str, int]] = None,
    mode: Optional[Union[str, int]] = None,
    track: int = 0,
    require_cadence: Optional[bool] = None,
    max_edit_cost: Optional[int] = None,
    anchor_start: Optional[bool] = None,
    octave_lattice: int = 7,
) -> Dict[str, Any]:
    suffix = path.suffix.lower()
    if suffix in (".mid", ".midi"):
        return load_midi(
            path,
            tonic=tonic,
            mode=mode,
            track=track,
            require_cadence=require_cadence,
            max_edit_cost=max_edit_cost,
            anchor_start=anchor_start,
            octave_lattice=octave_lattice,
        )
    return load_json(path)


def load_json(path: Path) -> Dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    tonic = int(data.get("tonic_keynum", 60))
    mode_id = int(data.get("mode_id", 0))
    octave = int(data.get("octave", 7))
    require_cadence = bool(data.get("require_cadence", True))
    max_edit_cost = int(data.get("max_edit_cost", 24))
    config_filter = data.get("config_filter")
    anchor_start = bool(data.get("anchor_start", False))

    if "degrees" in data:
        degrees = [int(x) for x in data["degrees"]]
    elif "pitches" in data:
        degrees = pitches_to_degrees([int(p) for p in data["pitches"]], tonic, mode_id)
    else:
        raise ValueError("input must include 'degrees' or 'pitches'")

    _validate_length(len(degrees))
    return _input_dict(path, tonic, mode_id, octave, degrees, require_cadence, max_edit_cost, config_filter, anchor_start, None, None)


def load_midi(
    path: Path,
    *,
    tonic: Optional[Union[str, int]] = None,
    mode: Optional[Union[str, int]] = None,
    track: int = 0,
    require_cadence: Optional[bool] = None,
    max_edit_cost: Optional[int] = None,
    anchor_start: Optional[bool] = None,
    octave_lattice: int = 7,
) -> Dict[str, Any]:
    if tonic is None:
        raise ValueError("MIDI input requires --tonic (e.g. 62 or D)")
    if mode is None:
        raise ValueError("MIDI input requires --mode (e.g. 3 or lydian)")
    tonic_keynum = parse_tonic(tonic)
    mode_id = parse_mode(mode)
    midi = read_smf(path)
    pitches, ticks = extract_monophonic_pitches(midi, track=track, max_len=MAX_LEN)
    _validate_length(len(pitches))
    degrees = pitches_to_degrees(pitches, tonic_keynum, mode_id)
    chromatic = pitches_to_chromatic_degrees(pitches, tonic_keynum)
    return _input_dict(
        path,
        tonic_keynum,
        mode_id,
        octave_lattice,
        degrees,
        require_cadence if require_cadence is not None else True,
        max_edit_cost if max_edit_cost is not None else 32,
        None,
        anchor_start if anchor_start is not None else False,
        pitches,
        ticks,
        chromatic,
    )


def _validate_length(n: int) -> None:
    if n < MIN_LEN or n > MAX_LEN:
        raise ValueError(f"length must be in [{MIN_LEN}, {MAX_LEN}], got {n}")


def _input_dict(
    path: Path,
    tonic: int,
    mode_id: int,
    octave: int,
    degrees: List[int],
    require_cadence: bool,
    max_edit_cost: int,
    config_filter,
    anchor_start: bool,
    source_pitches: Optional[List[int]],
    source_ticks: Optional[List[int]],
    chromatic_degrees: Optional[List[int]] = None,
) -> Dict[str, Any]:
    return {
        "source": str(path),
        "tonic_keynum": tonic,
        "mode_id": mode_id,
        "octave": octave,
        "input_degrees": degrees,
        "chromatic_degrees": chromatic_degrees,
        "source_pitches": source_pitches,
        "source_ticks": source_ticks,
        "require_cadence": require_cadence,
        "max_edit_cost": max_edit_cost,
        "config_filter": config_filter,
        "anchor_start": anchor_start,
    }


def pitch_to_degree_candidates(pitch: int, tonic: int, mode_id: int, center: int) -> List[int]:
    scale = MODE_SCALES[mode_id % 6]
    tonic_pc = tonic % 12
    pc = pitch % 12
    cands: List[int] = []
    for d in range(center - 14, center + 15):
        idx = d % 7
        if idx < 0:
            idx += 7
        oct_n = d // 7 if d >= 0 else (d - 6) // 7
        note_pc = (tonic_pc + scale[idx] + 12 * oct_n) % 12
        if note_pc == pc:
            cands.append(d)
    return cands


def _pick_degree(
    pitch: int,
    tonic: int,
    mode_id: int,
    center: int,
    *,
    step_from: int | None = None,
) -> int:
    scale = MODE_SCALES[mode_id % 6]
    cands = pitch_to_degree_candidates(pitch, tonic, mode_id, center)
    if not cands:
        cands = pitch_to_degree_candidates(pitch, tonic, mode_id, center + 2)

    def score(d: int) -> tuple:
        realized = realize_degree(7, d, tonic, mode_id, scale)
        pitch_err = abs(realized - pitch)
        if step_from is None:
            return (pitch_err, abs(d), abs(d - 7))
        return (pitch_err, abs(d - step_from), abs(d))

    return min(cands, key=score)


def pitches_to_degrees(pitches: List[int], tonic: int, mode_id: int) -> List[int]:
    """Map pitches to modal degrees via sequential path that round-trips realize_degree."""
    if not pitches:
        return []
    degrees = [_pick_degree(pitches[0], tonic, mode_id, 0)]
    for pitch in pitches[1:]:
        degrees.append(_pick_degree(pitch, tonic, mode_id, degrees[-1], step_from=degrees[-1]))
    return degrees


def pitches_to_chromatic_degrees(pitches: List[int], tonic: int) -> List[int]:
    """Semitone offsets from tonic (mirrors chromatic_degree_to_keynum lattice)."""
    if not pitches:
        return []
    out = [pitches[0] - tonic]
    for p in pitches[1:]:
        d = p - tonic
        while d < out[-1] - 7:
            d += 12
        while d > out[-1] + 7:
            d -= 12
        out.append(d)
    return out


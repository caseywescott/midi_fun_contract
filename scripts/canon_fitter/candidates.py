"""Candidate leader steps + vertical validation (stacked + entry-lag)."""

from __future__ import annotations

from typing import List, Optional, Sequence

from .profile_mirror import AestheticProfile, blocked_by_parallel_policy
from .rules_mirror import PairConstraint, full_step_range, step_satisfies_constraints_profile

REGISTER_BAND_DIATONIC = 7
REGISTER_BAND_CHROMATIC = 12


def candidate_steps(
    profile: AestheticProfile,
    constraints: Sequence[PairConstraint],
    offsets: Sequence[int],
    prev_steps: Sequence[int],
    cur_degree: int,
    lo: int,
    hi: int,
    pos: Optional[int] = None,
) -> List[int]:
    primary_d = offsets[1] if len(offsets) > 1 else 0
    valid: List[int] = []
    for m in full_step_range(profile.octave):
        if profile.forbid_semitone_step and abs(m) == 1:
            continue
        if not step_satisfies_constraints_profile(constraints, prev_steps, m, profile, pos):
            continue
        if blocked_by_parallel_policy(profile, primary_d, prev_steps, m):
            continue
        nxt = cur_degree + m
        if lo <= nxt <= hi:
            valid.append(m)
    if valid:
        return valid
    for m in full_step_range(profile.octave):
        if profile.forbid_semitone_step and abs(m) == 1:
            continue
        if not step_satisfies_constraints_profile(constraints, prev_steps, m, profile, pos):
            continue
        if blocked_by_parallel_policy(profile, primary_d, prev_steps, m):
            continue
        valid.append(m)
    return valid


def register_band(profile: AestheticProfile) -> int:
    return REGISTER_BAND_CHROMATIC if profile.octave == 12 else REGISTER_BAND_DIATONIC


def register_bounds(start_degree: int, profile: AestheticProfile) -> tuple[int, int]:
    band = register_band(profile)
    return start_degree - band, start_degree + band


def all_pairs_valid(
    degrees: Sequence[int],
    offsets: Sequence[int],
    profile: AestheticProfile,
    entries: Optional[Sequence[int]] = None,
) -> bool:
    if entries is None:
        entries = list(range(len(offsets)))
    n = len(degrees)
    span = n + max(entries)
    for t in range(span):
        sounding = []
        for vi, off in enumerate(offsets):
            entry = entries[vi]
            if t >= entry and (t - entry) < n:
                sounding.append(degrees[t - entry] + off)
        for i in range(len(sounding)):
            for j in range(i + 1, len(sounding)):
                from .profile_mirror import vertical_ok

                if not vertical_ok(profile, sounding[i], sounding[j]):
                    return False
    return True

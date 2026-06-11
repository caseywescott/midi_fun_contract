"""Mirrors aesthetic_profile.cairo — all profiles 0–24."""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Sequence

from .rules_mirror import abs_i32, full_step_range, intersect_steps

STABLE, CONSONANT, COLOR, SOFT, CLASH = 0, 1, 2, 3, 4
PAR_FORBID, PAR_LIMIT, PAR_ALLOW = 0, 1, 2
OCT_DIATONIC, OCT_CHROMATIC = 7, 12

# (id, name, octave, table, max_tier, par_policy, forbid_semitone_step)
_PROFILE_DATA = [
    (0, "renaissance", OCT_DIATONIC, (STABLE, CLASH, CONSONANT, CLASH, STABLE, CONSONANT, CLASH), CONSONANT, PAR_FORBID, False),
    (1, "jazz", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, COLOR), SOFT, PAR_LIMIT, False),
    (2, "quartal", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, STABLE, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, SOFT), COLOR, PAR_ALLOW, False),
    (3, "planing", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, COLOR), SOFT, PAR_ALLOW, False),
    (4, "hindemith", OCT_CHROMATIC, (STABLE, CLASH, COLOR, COLOR, CONSONANT, CONSONANT, SOFT, STABLE, CONSONANT, COLOR, COLOR, SOFT), SOFT, PAR_LIMIT, False),
    (5, "ligeti_white", OCT_DIATONIC, (STABLE, COLOR, CONSONANT, SOFT, STABLE, CONSONANT, COLOR), SOFT, PAR_ALLOW, False),
    (6, "ligeti_micro", OCT_CHROMATIC, (STABLE, SOFT, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, SOFT), SOFT, PAR_ALLOW, False),
    (7, "lydian_maj9", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, COLOR), SOFT, PAR_LIMIT, False),
    (8, "dom_alt", OCT_CHROMATIC, (STABLE, COLOR, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, COLOR, COLOR, COLOR), SOFT, PAR_LIMIT, False),
    (9, "whole_tone", OCT_CHROMATIC, (STABLE, CLASH, CONSONANT, CLASH, CONSONANT, CLASH, SOFT, CLASH, CONSONANT, CLASH, COLOR, CLASH), SOFT, PAR_ALLOW, False),
    (10, "octatonic", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, COLOR, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR, COLOR), SOFT, PAR_LIMIT, False),
    (11, "sus_quartal", OCT_CHROMATIC, (STABLE, CLASH, CONSONANT, COLOR, COLOR, STABLE, SOFT, STABLE, COLOR, CONSONANT, COLOR, COLOR), SOFT, PAR_ALLOW, False),
    (12, "pandiatonic", OCT_DIATONIC, (STABLE, COLOR, CONSONANT, COLOR, STABLE, CONSONANT, COLOR), COLOR, PAR_ALLOW, False),
    (13, "spectral", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, STABLE, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR, SOFT), COLOR, PAR_LIMIT, False),
    (14, "bartok_axis", OCT_CHROMATIC, (STABLE, CLASH, COLOR, STABLE, COLOR, COLOR, STABLE, COLOR, COLOR, STABLE, COLOR, COLOR), COLOR, PAR_LIMIT, False),
    (15, "cluster_soft", OCT_CHROMATIC, (STABLE, COLOR, CONSONANT, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, COLOR), COLOR, PAR_LIMIT, False),
    (16, "per_tonos", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, COLOR), SOFT, PAR_LIMIT, False),
    (17, "impr_add6", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR, COLOR), SOFT, PAR_ALLOW, False),
    (18, "bitonal", OCT_CHROMATIC, (STABLE, COLOR, COLOR, CONSONANT, STABLE, COLOR, SOFT, STABLE, CONSONANT, COLOR, COLOR, SOFT), SOFT, PAR_LIMIT, False),
    (19, "phrygian", OCT_CHROMATIC, (STABLE, COLOR, CONSONANT, CONSONANT, COLOR, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR, COLOR), SOFT, PAR_LIMIT, False),
    (20, "penta_open", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, STABLE, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, CLASH), COLOR, PAR_ALLOW, False),
    (21, "neo_riem", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, STABLE, COLOR, SOFT, STABLE, STABLE, CONSONANT, COLOR, COLOR), SOFT, PAR_LIMIT, False),
    (22, "penta_smooth", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, STABLE, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, CLASH), COLOR, PAR_ALLOW, True),
    (23, "impr_smooth", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR, COLOR), SOFT, PAR_ALLOW, True),
    (24, "jazz_improv", OCT_CHROMATIC, (STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT, COLOR, COLOR), SOFT, PAR_LIMIT, True),
]


@dataclass(frozen=True)
class AestheticProfile:
    id: int
    name: str
    octave: int
    table: tuple
    max_tier: int
    par_policy: int = PAR_FORBID
    forbid_semitone_step: bool = False


_PROFILES = {
    row[0]: AestheticProfile(
        id=row[0], name=row[1], octave=row[2], table=row[3],
        max_tier=row[4], par_policy=row[5], forbid_semitone_step=row[6],
    )
    for row in _PROFILE_DATA
}


def profile_by_id(pid: int) -> AestheticProfile:
    return _PROFILES.get(pid, _PROFILES[0])


def vertical_class(profile: AestheticProfile, a: int, b: int) -> int:
    return abs_i32(a - b) % profile.octave


def vertical_tier(profile: AestheticProfile, a: int, b: int) -> int:
    return profile.table[vertical_class(profile, a, b)]


def vertical_ok(profile: AestheticProfile, a: int, b: int) -> bool:
    return vertical_tier(profile, a, b) <= profile.max_tier


def is_perfect_vertical(profile: AestheticProfile, a: int, b: int) -> bool:
    cls = vertical_class(profile, a, b)
    fifth = 4 if profile.octave == OCT_DIATONIC else 7
    return cls == 0 or cls == fifth


def allowed_leader_steps_p(profile: AestheticProfile, t: int) -> List[int]:
    return [m for m in full_step_range(profile.octave) if vertical_ok(profile, t, m)]


def allowed_steps_multivoice_p(profile: AestheticProfile, offsets: Sequence[int]) -> List[int]:
    acc = full_step_range(profile.octave)
    for i in range(len(offsets) - 1):
        rel = offsets[i + 1] - offsets[i]
        acc = intersect_steps(acc, allowed_leader_steps_p(profile, rel))
    return acc


def blocked_by_parallel_policy(
    profile: AestheticProfile, primary_d: int, steps: Sequence[int], m: int
) -> bool:
    if profile.par_policy == PAR_ALLOW or not steps:
        return False
    if not is_perfect_vertical(profile, primary_d, m):
        return False
    prev = steps[-1]
    if m != prev:
        return False
    if profile.par_policy == PAR_LIMIT:
        if len(steps) < 2:
            return False
        return steps[-2] == prev
    return True


def melodic_step_cost(m: int, profile: AestheticProfile) -> int:
    a = abs_i32(m)
    if profile.forbid_semitone_step and a == 1:
        return 20
    if a <= 1 and profile.id == 0:
        return 1
    if a <= 2:
        return 2
    if a <= 4:
        return 4
    return 8

"""Mirrors src/composition/canon_rules.cairo (Renaissance + generalized steps)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Sequence


@dataclass(frozen=True)
class PairConstraint:
    d: int
    w: int


def abs_i32(x: int) -> int:
    return -x if x < 0 else x


def generic_class(a: int, b: int, octave: int = 7) -> int:
    return abs_i32(a - b) % octave


def is_consonant_class(cls: int) -> bool:
    c = cls % 7
    return c in (0, 2, 4, 5)


def is_perfect_class(cls: int, octave: int = 7) -> bool:
    c = cls % octave
    fifth = 4 if octave == 7 else 7
    return c == 0 or c == fifth


def step_is_consonant(t: int, m: int, octave: int = 7) -> bool:
    return is_consonant_class(generic_class(t, m, octave))


def full_step_range(octave: int) -> List[int]:
    return list(range(-octave, octave + 1))


def pair_constraints(offsets: Sequence[int]) -> List[PairConstraint]:
    out: List[PairConstraint] = []
    n = len(offsets)
    for i in range(n):
        for j in range(i + 1, n):
            out.append(PairConstraint(d=offsets[j] - offsets[i], w=j - i))
    return out


def pair_constraints_from_entries(
    offsets: Sequence[int], entries: Sequence[int]
) -> List[PairConstraint]:
    out: List[PairConstraint] = []
    n = len(offsets)
    for i in range(n):
        for j in range(i + 1, n):
            w = entries[j] - entries[i]
            if w > 0:
                out.append(PairConstraint(d=offsets[j] - offsets[i], w=w))
    return out


def intersect_steps(a: Sequence[int], b: Sequence[int]) -> List[int]:
    bs = set(b)
    return [x for x in a if x in bs]


def allowed_leader_steps(t: int, octave: int = 7) -> List[int]:
    return [m for m in full_step_range(octave) if step_is_consonant(t, m, octave)]


def allowed_steps_multivoice(offsets: Sequence[int], octave: int = 7) -> List[int]:
    acc = full_step_range(octave)
    for i in range(len(offsets) - 1):
        rel = offsets[i + 1] - offsets[i]
        acc = intersect_steps(acc, allowed_leader_steps(rel, octave))
    return acc


def step_satisfies_constraints(
    constraints: Sequence[PairConstraint],
    prev_steps: Sequence[int],
    m: int,
    octave: int = 7,
) -> bool:
    pos = len(prev_steps) + 1
    for pc in constraints:
        if pos >= pc.w:
            windowsum = m
            for t in range(pc.w - 1):
                windowsum += prev_steps[len(prev_steps) - 1 - t]
            if not is_consonant_class(generic_class(pc.d, windowsum, octave)):
                return False
    return True


def step_satisfies_constraints_profile(
    constraints: Sequence[PairConstraint],
    prev_steps: Sequence[int],
    m: int,
    profile,
    pos: int | None = None,
) -> bool:
    """Online vertical check for the step `m` landing at position `pos`.

    `prev_steps` may be a truncated tail of the real history (DP beam keeps a bounded
    window). `pos` is the *true* position so the window gate stays correct. Constraints
    whose window reaches further back than the retained tail are deferred to the final
    all_pairs_valid() check, which is exact.
    """
    from .profile_mirror import vertical_ok

    if pos is None:
        pos = len(prev_steps) + 1
    avail = len(prev_steps)
    for pc in constraints:
        if pos < pc.w:
            continue
        if avail < pc.w - 1:
            # Not enough retained history to evaluate this window online; defer.
            continue
        windowsum = m
        for t in range(pc.w - 1):
            windowsum += prev_steps[avail - 1 - t]
        if not vertical_ok(profile, pc.d, windowsum):
            return False
    return True

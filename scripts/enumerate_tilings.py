#!/usr/bin/env python3
"""
Offline Rhythmic Tiling Enumerator (MVP 4).

Enumerates all valid arithmetic-progression tilings for a given cycle length n,
derives each complement S analytically via polynomial division S(x) = T_n(x) / R(x)
over Z[x], scores them for rhythmic interest, classifies their syncopation, and emits
Cairo `TilingTemplate` table rows for `src/composition/known_tilings.cairo`.

This is the source-of-truth generator for the precomputed tables. The runtime Cairo
generator only indexes into the table produced here; it never enumerates at runtime.

Usage:
    python scripts/enumerate_tilings.py            # emit Cairo rows for the default n set
    python scripts/enumerate_tilings.py --n 12     # just n = 12
    python scripts/enumerate_tilings.py --verify    # cross-check the spec/Cairo tables

Mirrors the algorithms in src/composition/rhythmic_tiling.cairo so the two stay in sync.
"""

from __future__ import annotations

import argparse
from typing import List, Optional

# Mirrors the Cairo cardinality bounds.
MAX_VOICES = 8
MIN_TILE_ONSETS = 2

# Cycle lengths with full generation tables in Cairo.
GEN_SUPPORTED_N = [8, 12, 16, 24]


def ap_set(k: int, d: int, n: int) -> Optional[List[int]]:
    """AP(k, d, n) = {0, d, 2d, ..., (k-1)*d} mod n, sorted. None if it self-intersects."""
    positions = [(i * d) % n for i in range(k)]
    distinct = sorted(set(positions))
    if len(distinct) == k:
        return distinct
    return None


def is_direct_sum(n: int, r: List[int], s: List[int]) -> bool:
    """True iff R (+) S = Z_n: every position is hit exactly once."""
    if len(r) * len(s) != n:
        return False
    hits = [0] * n
    for ri in r:
        if ri >= n:
            return False
        for sj in s:
            if sj >= n:
                return False
            pos = (ri + sj) % n
            if hits[pos]:
                return False
            hits[pos] = 1
    return all(hits)


def find_complement(n: int, r: List[int]) -> Optional[List[int]]:
    """Derive S from R via polynomial long division T_n(x) / R(x) over Z[x]."""
    if not r or n == 0:
        return None
    deg_r = max(r)
    if deg_r >= n:
        return None
    deg_t = n - 1
    deg_s = deg_t - deg_r

    rem = [1] * n  # T_n(x) coefficients
    quotient = [0] * n
    for i in range(deg_s, -1, -1):
        coeff = rem[i + deg_r]
        if coeff == 0:
            continue
        quotient[i] = coeff
        for p in r:
            rem[i + p] -= coeff

    if any(rem):
        return None
    if any(c not in (0, 1) for c in quotient):
        return None
    return [i for i, c in enumerate(quotient) if c == 1]


def legato_durations(r: List[int], n: int) -> List[int]:
    """Each onset sustains until that voice's next onset (cyclic). Durations sum to n."""
    k = len(r)
    return [((r[(i + 1) % k] + n - r[i]) % n) for i in range(k)]


def cyclic_gaps(n: int, positions: List[int]) -> List[int]:
    s = sorted(positions)
    k = len(s)
    return [((s[(i + 1) % k] + n - s[i]) % n) for i in range(k)]


def is_arithmetic_progression(s: List[int]) -> bool:
    """Linear (non-wrapping) AP test. Sets of size <= 2 are trivially APs."""
    s = sorted(s)
    if len(s) <= 2:
        return True
    d0 = s[1] - s[0]
    return all(s[i + 1] - s[i] == d0 for i in range(len(s) - 1))


def is_trivial_block_pattern(r: List[int], s: List[int]) -> bool:
    return is_arithmetic_progression(r) and is_arithmetic_progression(s)


def gap_variety(n: int, s: List[int]) -> int:
    return len(set(cyclic_gaps(n, s)))


def score_tiling(n: int, r: List[int], s: List[int]) -> int:
    """Mirror of the Cairo heuristic: penalize trivial blocks, reward varied S structure."""
    score = 0
    if not is_trivial_block_pattern(r, s):
        score += 10
    score += gap_variety(n, r)
    score += gap_variety(n, s) * 2
    return score


def classify(n: int, r: List[int], s: List[int]) -> int:
    """Syncopation class via cyclic-gap APs (matches table data semantics)."""

    def cyclic_ap(positions: List[int]) -> bool:
        gaps = cyclic_gaps(n, positions)
        return all(g == gaps[0] for g in gaps)

    r_ap = cyclic_ap(r)
    s_ap = cyclic_ap(s)
    if r_ap and s_ap:
        return 0
    if r_ap or s_ap:
        return 1
    return 2


def divisors(n: int) -> List[int]:
    return [d for d in range(1, n + 1) if n % d == 0]


def enumerate_valid_ap_tilings(n: int) -> List[dict]:
    """All valid AP tilings for n within the cardinality bounds, scored and classified."""
    results = []
    seen = set()
    for k in divisors(n):
        if k < MIN_TILE_ONSETS or k > n // 2:
            continue
        if n // k > MAX_VOICES:
            continue
        for d in range(1, n):
            r = ap_set(k, d, n)
            if r is None:
                continue
            s = find_complement(n, r)
            if s is None:
                continue
            assert is_direct_sum(n, r, s), f"complement failed direct-sum for n={n} R={r}"
            assert len(s) <= MAX_VOICES
            key = (tuple(r), tuple(s))
            if key in seen:
                continue
            seen.add(key)
            results.append(
                {
                    "n": n,
                    "k": k,
                    "d": d,
                    "r": r,
                    "s": s,
                    "durations": legato_durations(r, n),
                    "class": classify(n, r, s),
                    "score": score_tiling(n, r, s),
                }
            )
    # Higher score first; stable tie-break by (k, d).
    results.sort(key=lambda t: (-t["score"], t["k"], t["d"]))
    return results


def fmt_arr(xs: List[int]) -> str:
    return "array![" + ", ".join(str(x) for x in xs) + "]"


def emit_cairo(n: int) -> str:
    rows = enumerate_valid_ap_tilings(n)
    lines = [f"// n = {n}: {len(rows)} templates"]
    for t in rows:
        lines.append(
            "out.append(t({n}, {k}, {d}, {r}, {s}, {durs}, {cls}, {score}));".format(
                n=t["n"],
                k=t["k"],
                d=t["d"],
                r=fmt_arr(t["r"]),
                s=fmt_arr(t["s"]),
                durs=fmt_arr(t["durations"]),
                cls=t["class"],
                score=t["score"],
            )
        )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Enumerate rhythmic tiling templates.")
    parser.add_argument("--n", type=int, default=None, help="single cycle length to emit")
    parser.add_argument(
        "--verify",
        action="store_true",
        help="self-check: every complement passes is_direct_sum and durations sum to n",
    )
    args = parser.parse_args()

    ns = [args.n] if args.n is not None else GEN_SUPPORTED_N

    if args.verify:
        ok = True
        for n in ns:
            for t in enumerate_valid_ap_tilings(n):
                if not is_direct_sum(n, t["r"], t["s"]):
                    print(f"FAIL direct_sum n={n} R={t['r']}")
                    ok = False
                if sum(t["durations"]) != n:
                    print(f"FAIL durations n={n} R={t['r']}")
                    ok = False
                if find_complement(n, t["r"]) != t["s"]:
                    print(f"FAIL complement n={n} R={t['r']}")
                    ok = False
        print("VERIFY OK" if ok else "VERIFY FAILED")
        return

    for n in ns:
        print(emit_cairo(n))
        print()


if __name__ == "__main__":
    main()

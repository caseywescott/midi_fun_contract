#!/usr/bin/env python3
"""
Offline timeline rhythm catalogue generator.

Enumerates Son/Rumba/Gahu interval permutations, canonicalizes rotations, emits masks
and descriptors, and writes fixtures/timeline_rhythms.json with a stable checksum.

Mirrors algorithms in src/composition/timeline_rhythm.cairo.

Usage:
    python scripts/generate_timeline_catalog.py
    python scripts/generate_timeline_catalog.py --verify
"""

from __future__ import annotations

import argparse
import hashlib
import json
from itertools import permutations
from pathlib import Path
from typing import Dict, List, Optional, Tuple

N = 16
ONSET_COUNT = 5

METRIC_WEIGHTS = [5, 1, 2, 1, 3, 1, 2, 1, 4, 1, 2, 1, 3, 1, 2, 1]

SYMMETRY_NONE = "none"
SYMMETRY_WEAK = "weak"
SYMMETRY_STRONG = "strong"

SON_FAMILY_IOI = [2, 3, 3, 4, 4]

SON_CANONICAL_IOIS: List[List[int]] = [
    [2, 3, 3, 4, 4],
    [2, 3, 4, 3, 4],
    [2, 3, 4, 4, 3],
    [2, 4, 3, 3, 4],
    [2, 4, 3, 4, 3],
    [2, 4, 4, 3, 3],
]

SON_CANONICAL_MASKS = [0x1125, 0x1225, 0x2225, 0x1245, 0x2245, 0x2445]

PRESETS: List[Dict] = [
    {
        "preset_id": 1,
        "name": "Shiko",
        "onsets": [0, 4, 6, 10, 12],
        "mask": 0x1451,
        "ioi": [4, 2, 4, 2, 4],
        "family_id": 1,
        "family": "Shiko",
        "variant_id": 0,
        "rotation": 4,
        "metric_complexity": 2,
        "pressing_x2": 12,
        "symmetry": SYMMETRY_STRONG,
        "source": "preset",
        "attribution": "Toussaint reference preset",
    },
    {
        "preset_id": 2,
        "name": "Son",
        "onsets": [0, 3, 6, 10, 12],
        "mask": 0x1449,
        "ioi": [3, 3, 4, 2, 4],
        "family_id": 2,
        "family": "Son/Rumba/Gahu",
        "variant_id": 3,
        "rotation": 10,
        "metric_complexity": 4,
        "pressing_x2": 29,
        "symmetry": SYMMETRY_WEAK,
        "source": "preset",
        "attribution": "Toussaint reference preset",
    },
    {
        "preset_id": 3,
        "name": "Soukous",
        "onsets": [0, 3, 6, 10, 11],
        "mask": 0x0C49,
        "ioi": [3, 3, 4, 1, 5],
        "family_id": 3,
        "family": "Soukous",
        "variant_id": 0,
        "rotation": 10,
        "metric_complexity": 6,
        "pressing_x2": 30,
        "symmetry": SYMMETRY_NONE,
        "source": "preset",
        "attribution": "Toussaint reference preset",
    },
    {
        "preset_id": 4,
        "name": "Rumba",
        "onsets": [0, 3, 7, 10, 12],
        "mask": 0x1489,
        "ioi": [3, 4, 3, 2, 4],
        "family_id": 2,
        "family": "Son/Rumba/Gahu",
        "variant_id": 4,
        "rotation": 10,
        "metric_complexity": 5,
        "pressing_x2": 34,
        "symmetry": SYMMETRY_NONE,
        "source": "preset",
        "attribution": "Toussaint reference preset",
    },
    {
        "preset_id": 5,
        "name": "Bossa-Nova",
        "onsets": [0, 3, 6, 10, 13],
        "mask": 0x2449,
        "ioi": [3, 3, 4, 3, 3],
        "family_id": 4,
        "family": "Bossa-Nova",
        "variant_id": 0,
        "rotation": 10,
        "metric_complexity": 6,
        "pressing_x2": 44,
        "symmetry": SYMMETRY_STRONG,
        "source": "preset",
        "attribution": "Toussaint reference preset",
    },
    {
        "preset_id": 6,
        "name": "Gahu",
        "onsets": [0, 3, 6, 10, 14],
        "mask": 0x4449,
        "ioi": [3, 3, 4, 4, 2],
        "family_id": 2,
        "family": "Son/Rumba/Gahu",
        "variant_id": 0,
        "rotation": 14,
        "metric_complexity": 5,
        "pressing_x2": 39,
        "symmetry": SYMMETRY_NONE,
        "source": "preset",
        "attribution": "Toussaint reference preset",
    },
]

SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES_OUT = SCRIPT_DIR.parent / "fixtures" / "timeline_rhythms.json"


def mask_to_onsets(n: int, mask: int) -> List[int]:
    return [t for t in range(n) if (mask >> t) & 1]


def onsets_to_mask(n: int, onsets: List[int]) -> int:
    mask = 0
    seen = set()
    for t in onsets:
        if t >= n or t in seen:
            raise ValueError(f"invalid onset {t} for n={n}")
        seen.add(t)
        mask |= 1 << t
    return mask


def mask_to_ioi(n: int, mask: int) -> List[int]:
    onsets = mask_to_onsets(n, mask)
    if not onsets:
        return []
    ioi = []
    for i, cur in enumerate(onsets):
        nxt = onsets[(i + 1) % len(onsets)]
        gap = nxt - cur if i + 1 < len(onsets) else n - cur + nxt
        ioi.append(gap)
    return ioi


def ioi_to_mask(n: int, ioi: List[int]) -> int:
    if not ioi or any(v <= 0 for v in ioi) or sum(ioi) != n:
        raise ValueError(f"invalid ioi {ioi} for n={n}")
    mask = 1
    pos = 0
    for i in range(1, len(ioi)):
        pos = (pos + ioi[i - 1]) % n
        bit = 1 << pos
        if mask & bit:
            raise ValueError(f"ioi collision at step {pos}")
        mask |= bit
    return mask


def rotate_mask(n: int, mask: int, amount: int) -> int:
    a = amount % n
    result = 0
    for t in range(n):
        if (mask >> t) & 1:
            result |= 1 << ((t + a) % n)
    return result


def rotate_ioi(ioi: List[int], amount: int) -> List[int]:
    if not ioi:
        return []
    a = amount % len(ioi)
    return ioi[a:] + ioi[:a]


def canonical_ioi_rotation(ioi: List[int]) -> List[int]:
    if not ioi:
        return []
    best = rotate_ioi(ioi, 0)
    for r in range(1, len(ioi)):
        candidate = rotate_ioi(ioi, r)
        if candidate < best:
            best = candidate
    return best


def metric_complexity(mask: int) -> int:
    metricity = sum(METRIC_WEIGHTS[t] for t in mask_to_onsets(N, mask))
    return 17 - metricity


def reverse_mask(n: int, mask: int) -> int:
    result = 0
    for t in range(n):
        if (mask >> t) & 1:
            rev_t = (n - t) % n
            result |= 1 << rev_t
    return result


def symmetry_class(n: int, mask: int) -> str:
    rev = reverse_mask(n, mask)
    if rev == mask:
        return SYMMETRY_STRONG
    for r in range(n):
        rotated = rotate_mask(n, mask, r)
        if reverse_mask(n, rotated) == rotated:
            return SYMMETRY_WEAK
    return SYMMETRY_NONE


def single_onset_displacement(n: int, from_mask: int, to_mask: int) -> Optional[int]:
    if n == 0:
        return None
    removed = added = None
    for t in range(n):
        in_from = (from_mask >> t) & 1
        in_to = (to_mask >> t) & 1
        if in_from and not in_to:
            if removed is not None:
                return None
            removed = t
        if in_to and not in_from:
            if added is not None:
                return None
            added = t
    if removed is None or added is None:
        return None
    fwd = (added - removed) % n
    rev = (removed - added) % n
    return min(fwd, rev)


def unique_ioi_permutations(multiset: List[int]) -> List[List[int]]:
    seen = set()
    out: List[List[int]] = []
    for perm in permutations(multiset):
        key = tuple(perm)
        if key not in seen:
            seen.add(key)
            out.append(list(perm))
    out.sort()
    return out


def describe_mask(n: int, mask: int, *, source: str, extra: Optional[Dict] = None) -> Dict:
    ioi = mask_to_ioi(n, mask)
    entry = {
        "n": n,
        "onset_count": len(mask_to_onsets(n, mask)),
        "onsets": mask_to_onsets(n, mask),
        "mask": mask,
        "mask_hex": f"0x{mask:04X}",
        "ioi": ioi,
        "canonical_ioi": canonical_ioi_rotation(ioi),
        "metric_complexity": metric_complexity(mask),
        "symmetry": symmetry_class(n, mask),
        "source": source,
    }
    if extra:
        entry.update(extra)
    return entry


def build_catalog() -> Dict:
    linear_perms = unique_ioi_permutations(SON_FAMILY_IOI)
    assert len(linear_perms) == 30

    canonical_variants: List[Dict] = []
    for variant_id, ioi in enumerate(SON_CANONICAL_IOIS):
        mask = SON_CANONICAL_MASKS[variant_id]
        assert ioi_to_mask(N, ioi) == mask
        canonical_variants.append(
            describe_mask(
                N,
                mask,
                source="son_family_canonical",
                extra={
                    "variant_id": variant_id,
                    "family_id": 2,
                    "label": "interval-class rhythm",
                },
            )
        )

    canonical_keys = {tuple(v["canonical_ioi"]) for v in canonical_variants}
    assert len(canonical_keys) == 6

    perm_entries = []
    for ioi in linear_perms:
        mask = ioi_to_mask(N, ioi)
        perm_entries.append(
            describe_mask(
                N,
                mask,
                source="son_family_linear_permutation",
                extra={"label": "interval-class rhythm"},
            )
        )

    oriented_candidates = []
    for variant_id in range(6):
        base_mask = SON_CANONICAL_MASKS[variant_id]
        for rotation in range(N):
            mask = rotate_mask(N, base_mask, rotation)
            oriented_candidates.append(
                describe_mask(
                    N,
                    mask,
                    source="son_family_oriented",
                    extra={
                        "variant_id": variant_id,
                        "rotation": rotation,
                        "family_id": 2,
                        "label": "clave-derived timeline",
                    },
                )
            )

    oriented_candidates.sort(key=lambda e: (e["variant_id"], e["rotation"]))

    presets = []
    for p in PRESETS:
        entry = describe_mask(
            N,
            p["mask"],
            source="preset",
            extra={
                "preset_id": p["preset_id"],
                "name": p["name"],
                "family_id": p["family_id"],
                "family": p["family"],
                "variant_id": p["variant_id"],
                "rotation": p["rotation"],
                "pressing_x2": p["pressing_x2"],
                "attribution": p["attribution"],
            },
        )
        assert entry["metric_complexity"] == p["metric_complexity"]
        assert entry["symmetry"] == p["symmetry"]
        presets.append(entry)

    body = {
        "version": "v1",
        "n": N,
        "onset_count": ONSET_COUNT,
        "reference_presets": presets,
        "son_family": {
            "multiset": SON_FAMILY_IOI,
            "linear_permutation_count": len(linear_perms),
            "canonical_variant_count": len(canonical_variants),
            "oriented_candidate_count": len(oriented_candidates),
            "canonical_variants": canonical_variants,
            "linear_permutations": perm_entries,
            "oriented_candidates": oriented_candidates,
        },
    }
    payload = json.dumps(body, sort_keys=True, separators=(",", ":"))
    body["checksum"] = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    return body


def verify_catalog(catalog: Dict) -> None:
    sf = catalog["son_family"]
    assert len(sf["linear_permutations"]) == 30
    assert len(sf["canonical_variants"]) == 6
    assert len(sf["oriented_candidates"]) == 96
    assert len(catalog["reference_presets"]) == 6

    canonical_set = {tuple(v["canonical_ioi"]) for v in sf["linear_permutations"]}
    assert len(canonical_set) == 6

    for ioi in sf["linear_permutations"]:
        again = canonical_ioi_rotation(ioi["ioi"])
        assert again == ioi["canonical_ioi"]

    for preset in catalog["reference_presets"]:
        assert preset["source"] == "preset"
        assert preset["attribution"] == "Toussaint reference preset"

    body = dict(catalog)
    checksum = body.pop("checksum")
    payload = json.dumps(body, sort_keys=True, separators=(",", ":"))
    assert hashlib.sha256(payload.encode("utf-8")).hexdigest() == checksum


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate timeline rhythm catalogue fixture")
    parser.add_argument("--verify", action="store_true", help="Verify existing fixture only")
    parser.add_argument(
        "--out",
        type=Path,
        default=FIXTURES_OUT,
        help="Output JSON path",
    )
    args = parser.parse_args()

    if args.verify:
        if not args.out.exists():
            raise SystemExit(f"missing fixture: {args.out}")
        catalog = json.loads(args.out.read_text(encoding="utf-8"))
        verify_catalog(catalog)
        print(f"OK: verified {args.out} checksum={catalog['checksum'][:16]}…")
        return

    catalog = build_catalog()
    verify_catalog(catalog)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {args.out} ({len(catalog['son_family']['oriented_candidates'])} oriented candidates)")
    print(f"checksum={catalog['checksum']}")


if __name__ == "__main__":
    main()

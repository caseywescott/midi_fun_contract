#!/usr/bin/env python3
"""Generate fixtures/v1/symmetry_engine.json from registry + RNG mirror."""

from __future__ import annotations

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from enumerate_symmetric_worlds import (  # noqa: E402
    FAMILY_USER_DEFINED,
    build_curated_registry,
    count_pitches,
    enumerate_symmetric_worlds,
    transpose_mask,
)

FIXTURES_OUT = SCRIPT_DIR.parent / "fixtures" / "v1" / "symmetry_engine.json"


def extract_bits(s: int, shift: int, width: int) -> int:
    return (s >> shift) & ((1 << width) - 1)


def seed_u256(seed: int) -> int:
    return seed & ((1 << 256) - 1)


def is_world_musically_useful(pitch_count: int, family_id: int, allow_sparse: bool) -> bool:
    if not allow_sparse and pitch_count < 3:
        return False
    if pitch_count > 10 and family_id != 6:
        return False
    return True


def is_rng_eligible(entry, allow_sparse: bool, allow_color: bool) -> bool:
    mask, fam, dt = entry[0], entry[1], entry[2]
    pc = count_pitches(mask)
    if not allow_color and fam == FAMILY_USER_DEFINED:
        return False
    return is_world_musically_useful(pc, fam, allow_sparse)


def eligible_ids(curated, allow_sparse: bool, allow_color: bool):
    return [i + 1 for i, e in enumerate(curated) if is_rng_eligible(e, allow_sparse, allow_color)]


def rng_choose_world_id(seed: int, curated, allow_sparse=False, allow_color=False) -> int:
    ids = eligible_ids(curated, allow_sparse, allow_color)
    s = seed_u256(seed)
    pick = extract_bits(s, 0, 8) % len(ids)
    return ids[pick]


def rng_choose_motif_length(seed: int) -> int:
    s = seed_u256(seed)
    choice = extract_bits(s, 40, 8) % 4
    return [4, 8, 12, 16][choice]


def main() -> None:
    worlds = enumerate_symmetric_worlds(include_chromatic=True)
    curated = build_curated_registry(worlds)
    fixtures = {
        "version": "v1",
        "registry_size": len(curated),
        "vectors": [],
    }
    for seed in [12345, 42, 777, 0xABCDEF]:
        wid = rng_choose_world_id(seed, curated)
        entry = curated[wid - 1]
        mask, fam, dt, name = entry
        fixtures["vectors"].append(
            {
                "seed": hex(seed),
                "world_id": wid,
                "mask": transpose_mask(mask, dt),
                "family_id": fam,
                "motif_length": rng_choose_motif_length(seed),
                "name": name,
            }
        )
    FIXTURES_OUT.parent.mkdir(parents=True, exist_ok=True)
    FIXTURES_OUT.write_text(json.dumps(fixtures, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {FIXTURES_OUT}")


if __name__ == "__main__":
    main()

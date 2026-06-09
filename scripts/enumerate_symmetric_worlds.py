#!/usr/bin/env python3
"""
Offline Symmetric Pitch World Enumerator.

Enumerates all 4095 non-empty pitch-class sets in Z12, checks transpositional
symmetry under steps +1, +2, +3, +4, +6, and exports a compact JSON table.

Mirrors the algorithms in src/composition/symmetry_engine.cairo.

Usage:
    python scripts/enumerate_symmetric_worlds.py
    python scripts/enumerate_symmetric_worlds.py --output data/symmetric_worlds.json
    python scripts/enumerate_symmetric_worlds.py --include-chromatic
    python scripts/enumerate_symmetric_worlds.py --emit-cairo
    python scripts/enumerate_symmetric_worlds.py --verify
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import List, Tuple

SYMMETRY_STEPS = [1, 2, 3, 4, 6]

FAMILY_MESSIAEN = 1
FAMILY_DIMINISHED = 2
FAMILY_AUGMENTED = 3
FAMILY_WHOLE_TONE = 4
FAMILY_TRITONE = 5
FAMILY_CHROMATIC = 6
FAMILY_GENERATED = 7
FAMILY_USER_DEFINED = 8

SCRIPT_DIR = Path(__file__).resolve().parent
CONTRACT_DIR = SCRIPT_DIR.parent
CAIRO_OUT = CONTRACT_DIR / "src" / "composition" / "known_symmetric_worlds.cairo"

# PRD registry ids 1-16
PRD_REGISTRY: List[Tuple[int, int, int, str]] = [
    (585, FAMILY_DIMINISHED, 0, "Diminished Seventh"),
    (273, FAMILY_AUGMENTED, 0, "Augmented Triad"),
    (1365, FAMILY_WHOLE_TONE, 0, "Whole Tone"),
    (65, FAMILY_TRITONE, 0, "Tritone Pair"),
    (1365, FAMILY_MESSIAEN, 0, "Messiaen Mode 1"),
    (1755, FAMILY_MESSIAEN, 0, "Messiaen Mode 2"),
    (3549, FAMILY_MESSIAEN, 0, "Messiaen Mode 3"),
    (2535, FAMILY_MESSIAEN, 0, "Messiaen Mode 4"),
    (2275, FAMILY_MESSIAEN, 0, "Messiaen Mode 5"),
    (3445, FAMILY_MESSIAEN, 0, "Messiaen Mode 6"),
    (3055, FAMILY_MESSIAEN, 0, "Messiaen Mode 7"),
    (2925, FAMILY_GENERATED, 0, "Octatonic Variant B"),
    (1755, FAMILY_GENERATED, 1, "Octatonic Variant C"),
    (819, FAMILY_AUGMENTED, 0, "Hexatonic Augmented"),
    (195, FAMILY_TRITONE, 0, "Tritone-Expanded"),
    (1749, FAMILY_USER_DEFINED, 0, "Dominant Resonance Set"),
]


def mask_from_pcs(pcs: List[int]) -> int:
    m = 0
    for pc in pcs:
        m |= 1 << (pc % 12)
    return m


def pcs_from_mask(mask: int) -> List[int]:
    return [pc for pc in range(12) if mask & (1 << pc)]


def transpose_mask(mask: int, t: int) -> int:
    out = 0
    for pc in pcs_from_mask(mask):
        out |= 1 << ((pc + t) % 12)
    return out


def count_pitches(mask: int) -> int:
    return bin(mask).count("1")


def find_min_symmetry_step(mask: int) -> int:
    for step in SYMMETRY_STEPS:
        if transpose_mask(mask, step) == mask:
            return step
    return 0


def unique_transposition_count(mask: int) -> int:
    step = find_min_symmetry_step(mask)
    return step if step else 12


def classify_family(mask: int, step: int, pitch_count: int) -> int:
    if step == 1 and pitch_count == 12:
        return FAMILY_CHROMATIC
    if mask == 585:
        return FAMILY_DIMINISHED
    if mask in (273, 819):
        return FAMILY_AUGMENTED
    if mask == 1365:
        return FAMILY_WHOLE_TONE
    if mask in (65, 195):
        return FAMILY_TRITONE
    if mask in (1365, 1755, 3549, 2535, 2275, 3445, 3055):
        return FAMILY_MESSIAEN
    if step == 0:
        return FAMILY_USER_DEFINED
    return FAMILY_GENERATED


def enumerate_symmetric_worlds(
    include_chromatic: bool = False,
    min_pitches: int = 2,
    max_pitches: int = 12,
) -> List[dict]:
    worlds: List[dict] = []
    world_id = 0
    for mask in range(1, 4096):
        pitch_count = count_pitches(mask)
        if pitch_count < min_pitches or pitch_count > max_pitches:
            continue
        step = find_min_symmetry_step(mask)
        if step == 0:
            continue
        if not include_chromatic and mask == 4095:
            continue
        world_id += 1
        worlds.append(
            {
                "id": world_id,
                "mask": mask,
                "pitch_count": pitch_count,
                "symmetry_step": step,
                "unique_transpositions": unique_transposition_count(mask),
                "family_id": classify_family(mask, step, pitch_count),
                "name": f"Symmetric Set {world_id}",
                "pitch_classes": pcs_from_mask(mask),
            }
        )
    return worlds


def build_curated_registry(all_worlds: List[dict]) -> List[Tuple[int, int, int, str]]:
    by_mask = {w["mask"]: w for w in all_worlds}
    curated = list(PRD_REGISTRY)
    seen = {m for m, _, _, _ in curated}

    for w in sorted(all_worlds, key=lambda x: (x["pitch_count"], x["mask"])):
        m = w["mask"]
        if m in seen:
            continue
        if w["pitch_count"] < 3 or w["pitch_count"] > 10:
            continue
        seen.add(m)
        curated.append((m, w["family_id"], 0, w["name"]))
        if len(curated) >= 48:
            break

    curated.append((4095, FAMILY_CHROMATIC, 0, "Chromatic Totality"))
    return curated


def emit_cairo_registry(curated: List[Tuple[int, int, int, str]]) -> str:
    lines = [
        "//! Precomputed symmetric pitch world registry.",
        "//! Generated by scripts/enumerate_symmetric_worlds.py --emit-cairo",
        "",
        "#[derive(Copy, Drop)]",
        "pub struct RegistryEntry {",
        "    pub mask: u16,",
        "    pub family_id: u8,",
        "    pub default_transposition: u8,",
        "}",
        "",
        f"pub const REGISTRY_SIZE: u16 = {len(curated)};",
        "",
        "pub fn registry_entry(world_id: u16) -> RegistryEntry {",
        "    assert(world_id >= 1 && world_id <= REGISTRY_SIZE, 'invalid world_id');",
    ]
    for i, (mask, fam, dt, name) in enumerate(curated, 1):
        kw = "if" if i == 1 else "} else if"
        lines.append(f"    {kw} world_id == {i} {{")
        lines.append(
            f"        RegistryEntry {{ mask: {mask}, family_id: {fam}, "
            f"default_transposition: {dt} }}"
        )
    lines.extend(
        [
            "    } else {",
            "        RegistryEntry { mask: 0, family_id: 0, default_transposition: 0 }",
            "    }",
            "}",
            "",
        ]
    )
    return "\n".join(lines)


def verify_cairo_registry() -> None:
    checks = [
        ("diminished seventh", 585, 3, 4),
        ("augmented triad", 273, 4, 3),
        ("whole tone", 1365, 2, 6),
        ("tritone pair", 65, 6, 2),
        ("messiaen mode 2", 1755, 3, 8),
        ("octatonic B", 2925, 3, 8),
        ("dominant resonance", 1749, 0, 7),
    ]
    for label, mask, expected_step, expected_count in checks:
        step = find_min_symmetry_step(mask)
        count = count_pitches(mask)
        assert step == expected_step, f"{label}: step {step} != {expected_step}"
        assert count == expected_count, f"{label}: count {count} != {expected_count}"
    print("Registry verification passed.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Enumerate symmetric pitch worlds in Z12")
    parser.add_argument(
        "--output",
        default="data/symmetric_worlds.json",
        help="Output JSON path (default: data/symmetric_worlds.json)",
    )
    parser.add_argument(
        "--include-chromatic",
        action="store_true",
        help="Include the full chromatic set",
    )
    parser.add_argument(
        "--emit-cairo",
        action="store_true",
        help="Emit src/composition/known_symmetric_worlds.cairo",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Verify curated registry masks only",
    )
    args = parser.parse_args()

    if args.verify:
        verify_cairo_registry()
        return

    worlds = enumerate_symmetric_worlds(include_chromatic=args.include_chromatic)
    print(f"Found {len(worlds)} symmetric pitch worlds")

    if args.emit_cairo:
        curated = build_curated_registry(worlds)
        CAIRO_OUT.write_text(emit_cairo_registry(curated), encoding="utf-8")
        print(f"Wrote {CAIRO_OUT} ({len(curated)} registry entries)")

    out_path = CONTRACT_DIR / args.output
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(worlds, f, indent=2)
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()

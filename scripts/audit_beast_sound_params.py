#!/usr/bin/env python3
"""Audit Loot Survivor Beast sound parameter space.

This is an offchain sanity audit for the 75 * 1243 immutable Beast identity
tuples. It mirrors the bounded Cairo mapper and writes a compact report. The
onchain source of truth remains the Cairo implementation; this script is a
collection-scale smoke alarm for accidental collapses.
"""

from __future__ import annotations

import hashlib
from pathlib import Path


SPECIES_COUNT = 75
NAME_VARIANT_COUNT = 1243
REPORT = Path("fixtures/reports/beast_sound_audit.md")


def digest(*parts: object) -> str:
    h = hashlib.blake2b(digest_size=16)
    for part in parts:
        h.update(str(part).encode("utf-8"))
        h.update(b"|")
    return h.hexdigest()


def species_row(species_id: int) -> tuple[int, int, int, int, int]:
    if species_id < 5:
        tier = 1
    elif species_id < 15:
        tier = 2
    elif species_id < 35:
        tier = 3
    elif species_id < 55:
        tier = 4
    else:
        tier = 5

    weakness = species_id % 3
    voice_count = 3 if tier <= 2 else 2 if tier == 3 else 1
    if tier == 1:
        canon_config_id = 28 + (species_id % 10)
    elif tier == 2:
        canon_config_id = 17 + (species_id % 11)
    elif tier == 3:
        canon_config_id = 7 + (species_id % 10)
    else:
        canon_config_id = species_id % 7
    profile_id = 17 + (species_id % 8) if tier <= 2 else species_id % 5 if tier == 3 else 0
    return tier, weakness, voice_count, canon_config_id, profile_id


def decode_name_variant(name_variant_id: int) -> tuple[bool, int, int]:
    if name_variant_id == 0:
        return False, 0, 0
    idx = name_variant_id - 1
    return True, idx // 18, idx % 18


def key_cell(species_id: int, name_variant_id: int, tier: int) -> tuple[int, int, int]:
    has_prefixes, prefix1, _prefix2 = decode_name_variant(name_variant_id)
    if not has_prefixes:
        return 5, species_id % 12, 0 if tier <= 2 else 1 if tier <= 4 else 2

    familiar = [7, 5, 4, 8]
    mode_id = familiar[prefix1 % 4]
    if tier <= 2 and prefix1 % 12 == 10:
        mode_id = 6
    elif tier <= 2 and prefix1 % 12 == 11:
        mode_id = 26
    return mode_id, prefix1 % 12, (prefix1 // 12) % 3


def audit() -> str:
    seen_params: dict[str, tuple[int, int]] = {}
    seen_theme: dict[str, tuple[int, int]] = {}
    bounds_errors: list[str] = []
    param_collisions = 0
    theme_collisions = 0

    for species_id in range(SPECIES_COUNT):
        tier, weakness, voice_count, canon_config_id, profile_id = species_row(species_id)
        for name_variant_id in range(NAME_VARIANT_COUNT):
            mode_id, tonic_pc, register = key_cell(species_id, name_variant_id, tier)
            has_prefixes, prefix1, prefix2 = decode_name_variant(name_variant_id)
            ornament_density = 1 if not has_prefixes else 1 + (prefix2 % 5)
            params_key = digest(
                species_id,
                name_variant_id,
                mode_id,
                tonic_pc,
                register,
                tier,
                weakness,
                voice_count,
                canon_config_id,
                profile_id,
                ornament_density,
            )
            theme_key = digest("theme", species_id, name_variant_id, mode_id, tonic_pc, prefix1)

            if not (1 <= tier <= 5):
                bounds_errors.append(f"bad tier: species={species_id}")
            if not (0 <= mode_id <= 30):
                bounds_errors.append(f"bad mode: species={species_id} name={name_variant_id}")
            if not (0 <= tonic_pc < 12):
                bounds_errors.append(f"bad tonic: species={species_id} name={name_variant_id}")
            if not (1 <= voice_count <= 3):
                bounds_errors.append(f"bad voices: species={species_id}")
            if tier >= 4 and mode_id in {6, 12, 26}:
                bounds_errors.append(f"common exotic: species={species_id} name={name_variant_id}")

            if params_key in seen_params:
                param_collisions += 1
            else:
                seen_params[params_key] = (species_id, name_variant_id)

            if theme_key in seen_theme:
                theme_collisions += 1
            else:
                seen_theme[theme_key] = (species_id, name_variant_id)

    total = SPECIES_COUNT * NAME_VARIANT_COUNT
    lines = [
        "# Beast Sound Audit",
        "",
        f"Total immutable tuples: {total}",
        f"Unique parameter fingerprints: {len(seen_params)}",
        f"Parameter fingerprint collisions: {param_collisions}",
        f"Unique theme fingerprints: {len(seen_theme)}",
        f"Theme fingerprint collisions: {theme_collisions}",
        f"Bounds errors: {len(bounds_errors)}",
        "",
    ]
    if bounds_errors:
        lines.append("## Bounds Errors")
        lines.extend(f"- {err}" for err in bounds_errors[:100])
        if len(bounds_errors) > 100:
            lines.append(f"- ... {len(bounds_errors) - 100} more")
    else:
        lines.append("No bounds errors found.")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    text = audit()
    REPORT.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()

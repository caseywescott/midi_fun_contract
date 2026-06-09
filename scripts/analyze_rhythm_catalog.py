#!/usr/bin/env python3
"""
Analyze timeline rhythm catalogue fixtures.

Produces descriptor reports, distance matrices, morph graphs, and family-admission
recommendations. Requires fixtures/timeline_rhythms.json from generate_timeline_catalog.py.

Usage:
    python scripts/analyze_rhythm_catalog.py
    python scripts/analyze_rhythm_catalog.py --fixture fixtures/timeline_rhythms.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from generate_timeline_catalog import (  # noqa: E402
    N,
    PRESETS,
    mask_to_ioi,
    metric_complexity,
    rotate_ioi,
    single_onset_displacement,
    symmetry_class,
)

FIXTURE_DEFAULT = SCRIPT_DIR.parent / "fixtures" / "timeline_rhythms.json"
REPORT_DIR = SCRIPT_DIR.parent / "fixtures" / "reports"
DESCRIPTOR_JSON = REPORT_DIR / "timeline_descriptor_report.json"
ADMISSION_MD = REPORT_DIR / "timeline_family_admission.md"


def cyclic_interval_distance_sq(ioi_a: List[int], ioi_b: List[int]) -> int:
    if len(ioi_a) != len(ioi_b):
        raise ValueError("IOI length mismatch")
    best = None
    for r in range(len(ioi_b)):
        rot = rotate_ioi(ioi_b, r)
        dist = sum((a - b) ** 2 for a, b in zip(ioi_a, rot))
        if best is None or dist < best:
            best = dist
    return best or 0


def entry_label(entry: Dict) -> str:
    if entry.get("source") == "preset":
        return entry["name"]
    if "variant_id" in entry:
        return f"variant_{entry['variant_id']}_rot_{entry.get('rotation', 0)}"
    return entry.get("label", entry.get("source", "unknown"))


def pairwise_distance_matrix(entries: List[Dict]) -> Dict:
    labels = [entry_label(e) for e in entries]
    matrix: List[List[int]] = []
    for a in entries:
        ioi_a = a["ioi"]
        row = [cyclic_interval_distance_sq(ioi_a, b["ioi"]) for b in entries]
        matrix.append(row)
    return {"labels": labels, "distance_sq": matrix}


def preset_morph_graph(max_displacement: int = 1) -> Dict:
    edges = []
    for i, a in enumerate(PRESETS):
        for b in PRESETS[i + 1 :]:
            d = single_onset_displacement(N, a["mask"], b["mask"])
            if d is not None and d <= max_displacement:
                edges.append(
                    {
                        "from": a["name"],
                        "to": b["name"],
                        "displacement": d,
                    }
                )
    return {"max_displacement": max_displacement, "edges": edges}


def son_variant_summary(catalog: Dict) -> List[Dict]:
    rows = []
    for entry in catalog["son_family"]["oriented_candidates"]:
        if entry.get("rotation") != 0:
            continue
        rows.append(
            {
                "variant_id": entry["variant_id"],
                "mask_hex": entry["mask_hex"],
                "ioi": entry["ioi"],
                "metric_complexity": entry["metric_complexity"],
                "symmetry": entry["symmetry"],
                "label": entry.get("label", "interval-class rhythm"),
                "son_distance_sq": cyclic_interval_distance_sq(
                    entry["ioi"], PRESETS[1]["ioi"]
                ),
            }
        )
    rows.sort(key=lambda r: r["variant_id"])
    return rows


def reference_only_families() -> Dict:
    """Summarize non-Son families kept reference-only in v1."""
    son_ioi = PRESETS[1]["ioi"]
    out = {}
    for preset in PRESETS:
        if preset["family_id"] in (1, 3, 4):  # Shiko, Soukous, Bossa-Nova
            out[preset["name"]] = {
                "reference_ioi": preset["ioi"],
                "metric_complexity": preset["metric_complexity"],
                "symmetry": preset["symmetry"],
                "son_distance_sq": cyclic_interval_distance_sq(preset["ioi"], son_ioi),
            }
    return out


def admission_recommendation(report: Dict) -> str:
    son_variants = report["son_family_variants"]
    ref_families = report["reference_only_families"]
    lines = [
        "# Timeline family admission decision (v1)",
        "",
        "Decision date: generated offline by `scripts/analyze_rhythm_catalog.py`.",
        "",
        "## Son/Rumba/Gahu interval family",
        "",
        "**Admitted for bounded generation in v1.** Six canonical cyclic variants and 96",
        "oriented candidates are implemented in Cairo with deterministic seed selection.",
        "",
        "### Canonical variants at rotation 0",
        "",
        "| Variant | IOI | Metric | Symmetry | Distance² from Son |",
        "|---------|-----|--------|----------|-------------------|",
    ]
    for row in son_variants:
        lines.append(
            f"| {row['variant_id']} | `{row['ioi']}` | {row['metric_complexity']} | "
            f"{row['symmetry']} | {row['son_distance_sq']} |"
        )
    lines.extend(
        [
            "",
            "Listening review: use `demos/timeline_rhythm/reference_presets.mid` for named",
            "presets and regenerate Son-family oriented candidates via catalogue fixtures.",
            "Generated variants must remain labelled `clave-derived timeline` /",
            "`interval-class rhythm`, never as traditional clave names.",
            "",
            "## Shiko, Soukous, Bossa-Nova families",
            "",
            "**Not admitted for permutation generation in v1.** Keep as exact reference presets",
            "only until offline descriptor analysis and listening review justify expansion.",
            "",
            "| Family | Reference IOI | Metric | Symmetry | Distance² from Son | Recommendation |",
            "|--------|---------------|--------|----------|-------------------|----------------|",
        ]
    )
    for name, data in ref_families.items():
        lines.append(
            f"| {name} | `{data['reference_ioi']}` | {data['metric_complexity']} | "
            f"{data['symmetry']} | {data['son_distance_sq']} | Defer — reference preset only |"
        )
    lines.extend(
        [
            "",
            "## Rationale",
            "",
            "- Shiko, Soukous, and Bossa-Nova use distinct interval multisets not covered by the",
            "  v1 Son-family generator; admitting them requires separate bounded permutation tables",
            "  and listening validation per spec Milestone 5.",
            "- Descriptor spread shows Soukous and Bossa-Nova are metric/symmetry outliers relative",
            "  to the Son/Rumba/Gahu family; premature admission risks mis-labelling generated",
            "  variants as culturally named patterns.",
            "- Revisit after M5 listening review notes are recorded and optional MIDI previews of",
            "  each family's permutation catalogue are auditioned.",
            "",
        ]
    )
    return "\n".join(lines)


def analyze(catalog: Dict) -> Dict:
    presets = catalog["reference_presets"]
    canonical = catalog["son_family"]["canonical_variants"]
    return {
        "catalog_checksum": catalog.get("checksum"),
        "preset_distance_matrix": pairwise_distance_matrix(presets),
        "son_canonical_distance_matrix": pairwise_distance_matrix(canonical),
        "preset_morph_graph": preset_morph_graph(1),
        "son_family_variants": son_variant_summary(catalog),
        "reference_only_families": reference_only_families(),
        "son_oriented_candidate_count": catalog["son_family"]["oriented_candidate_count"],
        "midi_preview_paths": [
            "demos/timeline_rhythm/reference_presets.mid",
            "demos/timeline_rhythm/son_family_morph_walk.mid",
            "demos/timeline_rhythm/son_phase_orbit.mid",
        ],
        "listening_review_status": (
            "Pending human audition of Son-family canonical variants (rotation 0) and "
            "generated oriented candidates; use MIDI demos above as starting points."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Analyze timeline rhythm catalogue")
    parser.add_argument("--fixture", type=Path, default=FIXTURE_DEFAULT)
    args = parser.parse_args()

    if not args.fixture.exists():
        raise SystemExit(f"missing fixture: {args.fixture} (run generate_timeline_catalog.py first)")

    catalog = json.loads(args.fixture.read_text(encoding="utf-8"))
    report = analyze(catalog)

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    DESCRIPTOR_JSON.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    ADMISSION_MD.write_text(admission_recommendation(report), encoding="utf-8")

    print(f"Wrote {DESCRIPTOR_JSON}")
    print(f"Wrote {ADMISSION_MD}")
    print(f"Son oriented candidates: {report['son_oriented_candidate_count']}")
    print(f"Preset morph edges (d<=1): {len(report['preset_morph_graph']['edges'])}")


if __name__ == "__main__":
    main()

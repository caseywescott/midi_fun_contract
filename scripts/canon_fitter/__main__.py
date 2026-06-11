#!/usr/bin/env python3
"""CLI: python3 -m scripts.canon_fitter fit|verify|batch|ingest"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .emit import write_fit_result
from .export import write_canon_midi
from .fit import run_fit
from .ingest import load_input
from .verify import run_scarb_tests, verify_fixture

ROOT = Path(__file__).resolve().parents[2]


def cmd_fit(args: argparse.Namespace) -> int:
    inp = load_input(
        Path(args.input),
        tonic=args.tonic,
        mode=args.mode,
        track=args.track,
        require_cadence=args.require_cadence,
        max_edit_cost=args.max_edit_cost,
        anchor_start=args.anchor_start,
    )
    explicit_entries = _parse_entries(args.entries)
    result = run_fit(
        inp,
        profile_scope=args.profile_scope,
        entry_mode=args.entry_mode,
        explicit_entries=explicit_entries,
    )
    stem = Path(args.input).stem
    out = Path(args.output) if args.output else ROOT / "fixtures/canon/fit" / f"{stem}.json"
    write_fit_result(out, result)
    print(json.dumps(result, indent=2))
    print(f"\nWrote {out}")
    if args.midi_out:
        write_canon_midi(result, Path(args.midi_out))
        print(f"Wrote canon MIDI {args.midi_out}")
    return 0


def cmd_ingest(args: argparse.Namespace) -> int:
    inp = load_input(
        Path(args.input),
        tonic=args.tonic,
        mode=args.mode,
        track=args.track,
        require_cadence=args.require_cadence,
        max_edit_cost=args.max_edit_cost,
        anchor_start=args.anchor_start,
    )
    preview = {
        "source": inp["source"],
        "tonic_keynum": inp["tonic_keynum"],
        "mode_id": inp["mode_id"],
        "mode_name": ["ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian"][inp["mode_id"]],
        "length": len(inp["input_degrees"]),
        "input_degrees": inp["input_degrees"],
        "source_pitches": inp.get("source_pitches"),
    }
    print(json.dumps(preview, indent=2))
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(preview, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {args.json_out}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    if args.scarb:
        return run_scarb_tests()
    path = Path(args.fixture)
    report = verify_fixture(path)
    print(json.dumps(report, indent=2))
    ok = report["python_steps_valid"] and report["python_pairs_valid"]
    if report["edit_cost_recomputed"] != report["edit_cost_fixture"]:
        print("WARN: edit_cost mismatch", file=sys.stderr)
    return 0 if ok else 1


def cmd_batch(args: argparse.Namespace) -> int:
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    reports = []
    for path in sorted(input_dir.glob("*.json")):
        try:
            inp = load_input(path)
            result = run_fit(inp, profile_scope=args.profile_scope, entry_mode=getattr(args, "entry_mode", "stacked"))
            out = output_dir / f"{path.stem}.json"
            write_fit_result(out, result)
            reports.append(
                {
                    "input": str(path),
                    "output": str(out),
                    "fit_phase": result["fit_phase"],
                    "edit_cost": result["edit_cost"],
                }
            )
        except Exception as exc:  # noqa: BLE001
            reports.append({"input": str(path), "error": str(exc)})
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps({"results": reports}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(reports, indent=2))
    print(f"\nWrote {report_path}")
    return 0


def _parse_entries(value: str | None) -> list[int] | None:
    if not value:
        return None
    try:
        entries = [int(x.strip()) for x in value.split(",") if x.strip() != ""]
    except ValueError as exc:
        raise SystemExit(f"--entries must be comma-separated integers, got {value!r}") from exc
    if not entries:
        raise SystemExit("--entries was empty")
    return entries


def _add_midi_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--tonic", help="MIDI tonic keynum (62) or note (D, F#)")
    p.add_argument("--mode", help="Mode id (3) or name (lydian)")
    p.add_argument("--track", type=int, default=0)
    p.add_argument("--require-cadence", action=argparse.BooleanOptionalAction, default=None)
    p.add_argument("--max-edit-cost", type=int, default=None)
    p.add_argument("--anchor-start", action=argparse.BooleanOptionalAction, default=None)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Offline canon fitter")
    sub = parser.add_subparsers(dest="command", required=True)

    fit_p = sub.add_parser("fit", help="Fit melody JSON or MIDI to a canon")
    fit_p.add_argument("--input", required=True)
    fit_p.add_argument("--output")
    fit_p.add_argument("--midi-out", help="Write multi-voice canon SMF")
    fit_p.add_argument("--profile-scope", default="renaissance", choices=["renaissance", "extended", "all"])
    fit_p.add_argument(
        "--entry-mode",
        default="stacked",
        choices=["stacked", "uniform", "search", "timing", "infer"],
        help="stacked=legacy; search/timing/infer try entry-lag vectors from MIDI IOIs",
    )
    fit_p.add_argument(
        "--entries",
        help="Explicit per-voice entry lags in structural notes, e.g. '0,2,4'. "
        "Voice 0 must be 0. Overrides --entry-mode and selects configs with a matching voice count.",
    )
    _add_midi_args(fit_p)
    fit_p.set_defaults(func=cmd_fit)

    ing_p = sub.add_parser("ingest", help="Preview MIDI/JSON degree extraction")
    ing_p.add_argument("--input", required=True)
    ing_p.add_argument("--json-out")
    _add_midi_args(ing_p)
    ing_p.set_defaults(func=cmd_ingest)

    ver_p = sub.add_parser("verify", help="Verify fixture or run scarb tests")
    ver_p.add_argument("--fixture")
    ver_p.add_argument("--scarb", action="store_true")
    ver_p.set_defaults(func=cmd_verify)

    batch_p = sub.add_parser("batch", help="Fit all JSON in a directory")
    batch_p.add_argument("--input-dir", required=True)
    batch_p.add_argument("--output-dir", required=True)
    batch_p.add_argument("--report", required=True)
    batch_p.add_argument("--profile-scope", default="renaissance")
    batch_p.set_defaults(func=cmd_batch)

    args = parser.parse_args(argv)
    if args.command == "verify" and not args.scarb and not args.fixture:
        return run_scarb_tests()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

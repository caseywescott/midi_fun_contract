# Canon Fitter — Offline Tool Specification

**Status:** Draft  
**Repository:** `midi_fun_contract/` (KOJI)  
**Constraint:** Zero third-party dependencies (Python 3 stdlib only)  
**Relationship to on-chain canon:** Additive only — existing generators unchanged

---

## 1. Purpose

Given a **monophonic input melody** and a **key/mode**, produce a **valid multi-voice melodic canon** that:

1. Minimizes pitch edits to the input (L1 cost on scale degrees / semitones).
2. Satisfies the same validators as seed-driven generation (`exact_imitation`, `all_pairs_consonant`, optional cadence).
3. Reuses existing Cairo canon code for assembly, validation, and MIDI emission.

This is the **inverse** of the current pipeline (`seed → walk_leader → canon`). The fitter runs **offline only**; on-chain behavior is unchanged.

---

## 2. Non-goals

| Item | Reason |
|------|--------|
| On-chain Viterbi / CSP / GA | Violates KOJI determinism + no-search contract |
| Replacing `walk_leader` / `generate_melodic_canon` | Existing seed path must remain bit-for-bit |
| Rhythmic canon fitting (first version) | Rhythm–pitch decoupling; rhythm supplied separately or defaulted |
| Real-time / interactive UI | Batch CLI tool only |
| External packages (`mido`, `numpy`, etc.) | Stdlib-only requirement |

---

## 3. Design principle: Cairo is source of truth

Follow the `enumerate_tilings.py` pattern:

```
Cairo canon_rules + aesthetic_profile + melodic_canon   ← authoritative
        ↑ verify (--verify)                               │
Python mirror (scripts/canon_fitter/*.py)                 │
        ↓ emits fixtures                                  │
Cairo assemble + validators + canon_to_note_events        ← round-trip proof
```

The Python mirror exists **only** to run Viterbi search offline. Every fit result must pass Cairo validators before it is considered accepted.

---

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  INPUT                                                          │
│  • JSON degree sequence  OR  monophonic MIDI (.mid)             │
│  • tonic_keynum (MIDI), mode_id, optional length trim         │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/canon_fitter/ingest.py                                 │
│  melody_to_degrees() — mirrors mode_scale + degree quantize     │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/canon_fitter/catalog.py                                │
│  Load fixtures/canon/config_catalog.json (43 configs)           │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/canon_fitter/recognize.py                              │
│  Phase A: exact-fit scan (zero edits) across all configs        │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/canon_fitter/viterbi.py                                │
│  Phase B: minimal-edit DP per config (if Phase A fails)         │
│  Cost = w_pitch·|Δdegree| + w_step·melodic_step_cost          │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  fixtures/canon/fit/<name>.json  (CanonFitResult)               │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  scarb test -f test_canon_fitter                                │
│  assemble_canon_from_leader() → exact_imitation → consonance    │
│  optional: canon_to_note_events → SMF writer                    │
└─────────────────────────────────────────────────────────────────┘
```

**Existing canon generators** (`generate_melodic_canon`, `walk_leader*`, `build_canon_from_developed`, entry-lag canons) are **not modified**. They continue to be invoked by seeds, tests, and demos exactly as today.

---

## 5. Repository layout (new files)

```
midi_fun_contract/
├── docs/canon_fitter_spec.md              # this document
├── scripts/
│   ├── enumerate_canon_configs.py         # exports config_catalog.json
│   └── canon_fitter/
│       ├── __init__.py
│       ├── __main__.py                    # CLI entry: python -m scripts.canon_fitter
│       ├── ingest.py                      # JSON + stdlib MIDI → degrees
│       ├── smf.py                         # minimal SMF read/write (format 0/1)
│       ├── catalog.py                     # load config + profile metadata
│       ├── rules_mirror.py                # mirrors canon_rules.cairo
│       ├── profile_mirror.py              # mirrors aesthetic_profile vertical logic
│       ├── candidates.py                  # mirrors candidates_at (Phase 1: Renaissance + hard-gate profiles)
│       ├── recognize.py                   # Phase A exact-fit
│       ├── viterbi.py                     # Phase B minimal-edit DP
│       ├── emit.py                        # write CanonFitResult JSON + report
│       └── verify.py                      # subprocess scarb test + diff
├── fixtures/canon/
│   ├── config_catalog.json                # generated by enumerate_canon_configs.py
│   ├── fit/                               # output CanonFitResult fixtures
│   │   └── example_fifth_above.json
│   └── fit_input/                         # optional input fixtures for tests
│       └── grundgestalt_0.json
├── src/composition/melodic_canon.cairo    # + assemble_canon_from_leader (small addition)
└── src/tests/test_canon_fitter.cairo      # fixture-driven Cairo verification
```

All Python modules use **stdlib only**: `argparse`, `json`, `struct`, `subprocess`, `pathlib`, `dataclasses`, `typing`.

---

## 6. Cairo additions (minimal, non-breaking)

### 6.1 `assemble_canon_from_leader`

Add to `melodic_canon.cairo`. Does **not** call `walk_leader`. Wraps existing test helper with production fields and full config lookup.

```cairo
/// Build a validated canon from an external leader degree sequence.
/// Uses profiled_config_by_id (all 43 configs). Asserts imitation + consonance.
pub fn assemble_canon_from_leader(
    config_id: u32,
    mode_id: u8,
    tonic_keynum: u8,
    octave: u32,
    leader_degrees: Span<i32>,
) -> MelodicCanon {
    let config = profiled_config_by_id(config_id);
    let base = build_canon_for_test(
        config.config_id, config.name, config.offsets, leader_degrees, mode_id,
    );
    let canon = MelodicCanon {
        config_id: base.config_id,
        config_name: base.config_name,
        offsets: base.offsets,
        leader_degrees: base.leader_degrees,
        leader_steps: base.leader_steps,
        mode_id: base.mode_id,
        tonic_keynum,
        time_unit: base.time_unit,
        voices: base.voices,
        octave,
        profile_id: config.profile_id,
    };
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_consonant(@canon), 'canon not consonant');
    canon
}
```

**Note:** `build_canon_from_developed` remains for the motif pipeline and still uses `config_by_id` (Renaissance ids 0–6). The fitter uses `assemble_canon_from_leader` for all 43 profiled configs. No change to `build_canon_from_developed`.

### 6.2 `test_canon_fitter.cairo`

For each fixture in `fixtures/canon/fit/*.json`:

1. Parse leader degrees + metadata (hand-embedded arrays in test, or generated const from `enumerate` step).
2. Call `assemble_canon_from_leader`.
3. Assert `exact_imitation`, `all_pairs_consonant`, `cadence_lands_on_final` (when `require_cadence: true`).
4. Assert `edit_cost` matches Python report (stored in fixture for regression).

### 6.3 Optional: MIDI export test

Extend `midi_2_cairo_print.cairo` or add `test_canon_fitter_midi.cairo` that calls `canon_to_note_events` / `canon_to_ornamented_note_events` and prints events for the existing MIDI fixture pipeline. No new MIDI encoder in Cairo.

---

## 7. Config catalogue exporter

### `scripts/enumerate_canon_configs.py`

Mirrors `canon_rules.cairo` tables into JSON. Run after any config change.

```bash
python3 scripts/enumerate_canon_configs.py
python3 scripts/enumerate_canon_configs.py --verify   # diff against committed JSON
```

**Output:** `fixtures/canon/config_catalog.json`

```json
{
  "version": 1,
  "configs": [
    {
      "config_id": 0,
      "name": "fifth_above",
      "offsets": [0, 4],
      "octave": 7,
      "profile_id": 0,
      "profile_name": "renaissance",
      "lattice": "diatonic"
    }
  ]
}
```

Embedded manually in Python (like tiling AP tables) — **not** parsed from Cairo source at runtime. `--verify` runs a Scarb smoke test that spot-checks ids 0, 7, 24 against `profiled_config_by_id`.

---

## 8. Input formats

### 8.1 JSON input (`--input fixtures/canon/fit_input/foo.json`)

```json
{
  "tonic_keynum": 60,
  "mode_id": 0,
  "octave": 7,
  "degrees": [0, 2, 4, 3, 1, 0],
  "durations": [4, 4, 4, 4, 4, 4],
  "require_cadence": true,
  "config_filter": null,
  "max_edit_cost": 12
}
```

Either `degrees` (scale degrees relative to tonic) **or** `pitches` (MIDI keynums) must be present. If `pitches`, ingest quantizes via `melody_to_degrees`.

### 8.2 MIDI input (`--input melody.mid`)

- Monophonic track 0 (or `--track N`).
- Extract note onsets; collapse chords to highest note.
- Quantize onsets to structural grid (`time_unit`, default 4).
- Map each sounding pitch → scale degree via mode-aware quantize (mirror `degree_to_keynum` inverse).

### 8.3 Stdlib SMF (`scripts/canon_fitter/smf.py`)

Implement minimal Standard MIDI File support:

- **Read:** Format 0/1, MTrk chunks, variable-length deltas, note on/off 0x90/0x80.
- **Write:** Format 1, single tempo meta, multi-track (one track per canon voice) for output demos.

No dependency on `mido` or `pretty_midi`.

---

## 9. Fitting algorithm

### 9.1 Degree representation

- Leader lives on profile lattice: mod-7 (diatonic) or mod-12 (chromatic) per `config.octave`.
- Input degrees are **relative to tonic** in `mode_id` (same convention as `MelodicCanon.leader_degrees`).
- Register: optional anchor `start_degree` (default: input first note quantized, or 0 for cadence-required fits).

### 9.2 Phase A — Recognition (exact fit)

For each `config_id` in catalogue (or `config_filter` subset):

1. Build `pair_constraints(offsets)` (mirror).
2. For each position `t`, check `step_satisfies_constraints_p` on input steps.
3. Check all vertical pairs via `vertical_ok(profile, offset_j, window_sum)`.
4. If all pass → `edit_cost = 0`, skip Viterbi for this config.

Return best exact-fit by tie-break: fewer voices → smaller `max_tier_used` → lower config id.

### 9.3 Phase B — Viterbi minimal-edit fit

If no exact fit under `max_edit_cost`:

**State** at position `t`: leader degree `d` (bounded register window).

**Transition** `d_prev → d` with step `m = d - d_prev`:

- `m` must be in `candidates_at(...)` mirror (same filters as `walk_leader_banded`: constraints, parallel-perfect policy, register band, profile material gates).
- **Hard reject** if transition illegal.

**Costs:**

```
pitch_cost   = |d - input_degrees[t]| * W_PITCH
step_cost    = melodic_step_cost(m, profile) * W_STEP
cadence_cost = (t == len-1 && require_cadence && d != 0) ? INF : 0
```

Default weights: `W_PITCH=10`, `W_STEP=1`. `melodic_step_cost` mirrors `melodic_motion` (penalize semitone steps when profile forbids; penalize |m|>4).

**DP:**

```
dp[t][d] = min over legal predecessors d' of dp[t-1][d'] + transition_cost
backptr for reconstruction
```

**Complexity:** `O(len × |degree_range| × |candidates|)` — len ≤ 24, degree_range ≈ 29 (±14), candidates ≤ 15 → trivial offline.

**Output per config:** `fitted_degrees`, `edit_cost`, `max_leap`, `positions_edited`.

Select global best `(config_id, fitted_degrees)` with lowest `edit_cost`; tie-break by smaller total step magnitude, then config id.

### 9.4 Phase 1 profile scope (incremental)

| Tier | Profiles | Mirror completeness |
|------|----------|---------------------|
| P0 | `profile_id == 0` (Renaissance) | Full: `vertical_ok` + `pair_constraints` + parallel-perfect |
| P1 | Profiles without hard jazz/neo material gates | Full alphabet, no turnaround timeline |
| P2 | Jazz (24), Neo-Riemannian (21) | Requires turnaround plan mirror or config_filter exclude |

Ship P0 first; P1/P2 behind `--profile-scope extended`.

---

## 10. Output format (`CanonFitResult`)

Written to `fixtures/canon/fit/<slug>.json`:

```json
{
  "version": 1,
  "slug": "grundgestalt_0_fifth_above",
  "source": "fixtures/canon/fit_input/grundgestalt_0.json",
  "fit_phase": "exact",
  "config_id": 0,
  "config_name": "fifth_above",
  "profile_id": 0,
  "mode_id": 0,
  "tonic_keynum": 60,
  "octave": 7,
  "leader_degrees": [0, 2, 4, 3, 1, 0],
  "input_degrees": [0, 2, 4, 3, 1, 0],
  "edit_cost": 0,
  "positions_edited": [],
  "require_cadence": true,
  "cadence_ok": true,
  "validators": {
    "exact_imitation": true,
    "all_pairs_consonant": true
  },
  "report": {
    "configs_tried": 43,
    "exact_fit_count": 3,
    "runner_up": [
      {"config_id": 1, "edit_cost": 2}
    ]
  }
}
```

---

## 11. CLI

```bash
# Export / verify config catalogue
python3 scripts/enumerate_canon_configs.py
python3 scripts/enumerate_canon_configs.py --verify

# Fit a melody
python3 -m scripts.canon_fitter fit \
  --input fixtures/canon/fit_input/grundgestalt_0.json \
  --output fixtures/canon/fit/grundgestalt_0.json \
  --require-cadence

# Fit from MIDI
python3 -m scripts.canon_fitter fit \
  --input demos/inbox/my_melody.mid \
  --tonic 60 --mode 0 \
  --output fixtures/canon/fit/my_melody.json

# Verify Python ↔ Cairo agreement
python3 -m scripts.canon_fitter verify \
  --fixture fixtures/canon/fit/grundgestalt_0.json

# Batch + report
python3 -m scripts.canon_fitter batch \
  --input-dir fixtures/canon/fit_input \
  --output-dir fixtures/canon/fit \
  --report fixtures/reports/canon_fitter_batch.json
```

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Fit succeeded, validators pass |
| 1 | No fit under `max_edit_cost` |
| 2 | Cairo verification failed (mirror drift) |
| 3 | Invalid input |

---

## 12. Verification workflow

After every fit:

```bash
scarb test -f test_canon_fitter_fixture_grundgestalt_0
```

`verify.py` wraps this and checks:

1. Cairo test passes.
2. Python mirror re-evaluates `exact_imitation` + consonance flags match fixture.
3. `edit_cost` recomputed from `input_degrees` vs `leader_degrees` matches.

**Drift detection:** `python3 -m scripts.canon_fitter verify --all` runs full fit fixture suite. CI gate: `scarb test -f test_canon_fitter`.

---

## 13. Integration with existing pipelines

| Existing entry point | Relationship |
|---------------------|--------------|
| `generate_melodic_canon(seed)` | Unchanged; independent |
| `walk_leader*` | Unchanged; fitter does not call |
| `build_canon_from_developed` | Unchanged; motif demos unchanged |
| `assemble_canon_from_leader` | **New**; fitter + tests only |
| `canon_to_note_events` | Reused for output MIDI |
| `generate_ornamented_canon_from_developed` | Optional post-pass: fit → develop wrapper → ornament |
| `plan_canon_harmony` | Optional layer: fit → harmony on rhythmic grid |
| `generate_symmetry_composition` | Orthogonal; rhythm from tiling, pitch from fit fixture |

**Workflow for composed pieces:**

```
fit melody offline → CanonFitResult JSON
  → assemble_canon_from_leader (verify)
  → attach RhythmicCanon from tiling seed (optional)
  → plan_canon_harmony (optional)
  → canon_to_ornamented_note_events
```

---

## 14. Python mirror sync rules

`rules_mirror.py` and `profile_mirror.py` must stay aligned with:

| Cairo module | Python mirror function |
|--------------|------------------------|
| `canon_rules.cairo` | `generic_class`, `step_is_consonant`, `pair_constraints`, `allowed_leader_steps` |
| `aesthetic_profile.cairo` | `vertical_ok`, `vertical_tier`, `step_satisfies_constraints_p`, `allowed_steps_multivoice_p` |
| `melodic_canon.cairo` | `candidates_at` logic (documented inline in spec §9.3) |
| `melodic_motion.cairo` | `melodic_step_cost` |

On any change to those Cairo files, run:

```bash
python3 -m scripts.canon_fitter verify --all
```

If verify fails, update mirror before merging.

---

## 15. Implementation phases

### Phase 0 — Scaffold (1–2 days)

- [ ] `enumerate_canon_configs.py` + `config_catalog.json`
- [ ] `assemble_canon_from_leader` in Cairo
- [ ] `test_canon_fitter.cairo` with one hand-built fixture
- [ ] `rules_mirror.py` Renaissance only + `--verify`

### Phase 1 — Core fitter (3–5 days)

- [ ] `ingest.py` JSON degrees
- [ ] `recognize.py` exact-fit
- [ ] `viterbi.py` minimal-edit (Renaissance profiles)
- [ ] CLI `fit` + `verify`
- [ ] 5 golden fixtures (exact + edited cases)

### Phase 2 — MIDI I/O (2–3 days)

- [x] `smf.py` read/write
- [x] `melody_to_degrees` from MIDI
- [x] Output multi-voice SMF from fitted canon (incl. `source_ticks` for entry-aligned export)

### Phase 3 — Extended profiles (ongoing)

- [x] Profile mirror for chromatic / jazz / neo configs (profiles 0–24)
- [x] `--profile-scope extended` / `renaissance` / `all`
- [x] Entry-lag canon variant (`entry_lag.py`, `assemble_entry_lag_canon_from_leader`, `--entry-mode search`)
- [ ] Jazz/neo material timeline gates (profiles 21, 24) — vertical-only for now

---

## 16. Test plan

| Test | Type | Asserts |
|------|------|---------|
| `test_canon_fitter_exact_fifth_above` | Cairo | Known degrees, config 0, edit_cost 0 |
| `test_canon_fitter_minimal_edit` | Cairo | Fixture with 2 edits, consonance holds |
| `test_canon_fitter_rejects_bad_fixture` | Cairo | Negative case panics on assemble |
| `test_canon_fitter_cadence_required` | Cairo | Last degree must be 0 |
| `enumerate_canon_configs --verify` | Python | JSON ↔ Cairo id spot-check |
| `canon_fitter verify --all` | Python+Scarb | Full regression |
| Mirror unit tests | Python | `allowed_leader_steps(4)` matches Schubert set |

**Golden melodies for fixtures:**

- `grundgestalt_theme(0)` — exact fit expected on config 0
- `walk_leader(42, fifth_above, 16)` output degrees — round-trip edit_cost 0
- Chromatic fragment — expects non-zero edit_cost on Renaissance, may fit config 7+

---

## 17. Success metrics

| Metric | Target |
|--------|--------|
| Renaissance exact-fit rate on `walk_leader` outputs | 100% (sanity) |
| Cairo validator pass rate on emitted fixtures | 100% |
| Python/Cairo mirror drift | 0 failures on `verify --all` |
| `generate_melodic_canon` regression | Byte-identical MIDI for fixed seeds |
| Max fit time (24 notes, 43 configs) | < 2 s on laptop |

---

## 18. Open questions

1. **Start degree anchoring:** Should the fitter force degree 0 at start (modal final) or preserve input's first pitch class? Default: preserve input, optional `--anchor-final`.
2. **Length:** Trim/pad to `[MIN_LEN, MAX_LEN]` or reject? Default: reject if outside 8–24.
3. **Ornamentation:** Fitter outputs structural degrees only; ornament pass remains seed-driven or user-selected `--ornament-seed`.
4. **Fixture → Cairo embedding:** Generate `test_canon_fitter_fixtures.cairo` from JSON via `enumerate_canon_configs.py --emit-tests` to avoid hand-copying degree arrays.

---

*End of spec. Existing canon generation (`generate_melodic_canon`, `walk_leader`, motif → canon) remains the on-chain and seed-driven path. This tool is a parallel offline ingress that converges on the same `MelodicCanon` type and validators.*

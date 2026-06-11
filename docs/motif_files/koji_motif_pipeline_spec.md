# Motif Development, Form & Grouping — Consolidated Implementation Spec

**Status:** In progress
**Target repo:** Koji generative music library (Cairo / Starknet)
**Scope:** `koji::composition` — extensions above the existing motif development algebra
**Base doc:** `docs/motif_development_algebra_spec.md`
**Base source:** `src/composition/motif_algebra.cairo` (existing; treated as authoritative)

## Implementation status

| Task | Status | Commit |
|------|--------|--------|
| Weighted motif form and flat AABA | Complete | this commit |
| GTTM grouping boundaries | Complete | this commit |
| Grouped period assembly and acceptance coverage | Not started | pending |

Implementation note: this crate names the authoritative base module
`motif_algebra.cairo`; references below to `motif_development.cairo` describe
that same module.

---

## 0. Overview

This document specifies three new modules that build a complete, deterministic
melody-generation pipeline on top of the **existing** motif development algebra.
From a seed and a small *Grundgestalt* theme, the pipeline produces a
hierarchically structured melodic line — integer-only, seed-reproducible, and
sized for on-chain execution.

The full pipeline:

```
theme + seed
  → weighted_program_from_seed      (developing-variation operation order)
  → apply_program                   (existing transformation group)
  → grouping_boundaries             (GTTM local GPR phrase detection)
  → head_phrase                     (contour-cut A material)
  → develop_period_grouped          (AABA assembly, A reused verbatim)
  → developed_to_note_events        (existing → MIDI / canon handoff)
```

### 0.1 Research grounding

| Layer | Theory | Reference | Where realized |
|-------|--------|-----------|----------------|
| Transformation group | Generalized interval / transformation theory | Lewin, *GMIT* (1987) | **Existing** `MotifOp` enum + `op_laws_hold()` |
| Developing variation | Motif → phrase via weighted op order | Schoenberg (Grundgestalt) | New §3 `weighted_program_from_seed` |
| Form layer | Motif → phrase → section (AABA) | MeloForm, ISMIR 2022 (arXiv:2208.14345) | New §3.4 + §5 |
| Phrase boundaries | Grouping Preference Rules (local subset) | Lerdahl & Jackendoff, *GTTM* (1983) | New §4 |

The existing base algebra already implements Lewin's transformation group: the
`MotifOp` enum is the group, and `op_laws_hold()` verifies the axioms
(retrograde and inversion are involutions; transposition composes additively
with `T0` as identity). This spec adds the three layers above it without
modifying the base group.

---

## 1. Module Layout & Dependencies

Three new files under `src/composition/`, joining the existing one:

```
motif_development.cairo    (EXISTING — base algebra; unchanged)
motif_form.cairo           (NEW — weighted op selection + flat AABA)
grouping_boundaries.cairo  (NEW — GTTM local GPR phrase detection)
period_assembly.cairo      (NEW — grouping-driven AABA assembly)
```

Module path convention (verified against base source imports):
`koji::composition::<file_stem>`.

**Dependency graph:**

```
period_assembly
  ├── motif_form          (weighted_program_from_seed)
  ├── grouping_boundaries (group_lengths, segment_into_groups)
  └── motif_development   (DevelopedMotif, Motif, apply_program, motif_from_degrees)

grouping_boundaries
  ├── motif_development   (DevelopedMotif)
  └── canon_rules         (abs_i32)

motif_form
  └── motif_development   (Motif, MotifOp, MotifProgram, DevelopedMotif,
                           apply_program, motif_from_degrees,
                           FragmentOp, SequenceOp, StutterOp, IntervalScaleOp)
```

All three new modules must be registered in the composition module tree
(e.g. `mod motif_form;`, `mod grouping_boundaries;`, `mod period_assembly;` in
`src/composition.cairo` or the crate's module root, matching how
`motif_development` is currently declared).

---

## 2. Integration with the existing base algebra

This section is **verified against the provided `motif_development.cairo`
source**. It is the contract the new modules rely on.

### 2.1 Items already `pub` (import directly — no change needed)

Types: `Motif`, `DevelopedMotif`, `MotifOp`, `MotifProgram`, `FragmentOp`,
`SequenceOp`, `StutterOp`, `IntervalScaleOp`.

Functions: `apply_op_to_developed`, `apply_op`, `apply_program`,
`motif_from_degrees`, `grundgestalt_theme`, `program_from_seed`,
`developed_to_note_events`, and the canon/MIDI handoff functions.

Validators: `op_laws_hold`, `motif_ops_total`.

### 2.2 Items that are PRIVATE in the base module

The following are **not** `pub` and therefore cannot be imported. The new
modules ship **local copies** of them:

- Seed / bit helpers: `seed_u256`, `pow2`, `extract_bits`.
- Array helpers: `clone_i32`, `clone_u32`, and the various `concat_*` / reverse
  / rotate helpers.
- Op-kind decode: `decode_op_kind`.

> **Decision required (one-time):** Either
> **(A — recommended)** widen these to `pub` in `motif_development.cairo` and
> delete the duplicated copies in the new modules, or
> **(B — default in shipped code)** keep the local duplicates.
> The shipped new modules assume **(B)**. If you choose **(A)**, remove the
> `seed_u256` / `pow2` / `extract_bits` copies from `motif_form.cairo` and the
> `concat_*` / `clone` copies from `grouping_boundaries.cairo` and
> `period_assembly.cairo`, and import instead.

### 2.3 Critical type fact: `DevelopedMotif` is not `Copy`

`DevelopedMotif` derives `Drop, Serde` only — **not `Copy`** (it owns
`Array<i32>` / `Array<u32>`). Consequences enforced throughout the new modules:

- You cannot pass a `DevelopedMotif` by value and reuse it. Functions take
  `@DevelopedMotif` (snapshot) and rebuild owned copies when needed.
- `clone_developed` reconstructs via `concat_*_local(m.span(), array![].span())`
  because there is no `Copy`. If base §2.2(A) is adopted, prefer a single public
  `clone_developed` in the base module and import it.
- The verbatim reuse of the A phrase in §5 means cloning `a` three times, not
  moving it.

### 2.4 Representation contract (must match base exactly)

- **Degrees** are signed lattice degrees (`i32`), same representation as
  `MelodicCanon.leader_degrees`. A developed line's degrees may be fed straight
  to `developed_as_canon_leader` / `developed_to_note_events`.
- **Durations** are `u32`, parallel to degrees. The base
  `normalize_durations` falls back to all-ones when lengths mismatch; new code
  must preserve that 1:1 degrees↔durations length invariant after every op so
  the canon/MIDI handoff stays valid.
- **`octave: u32`** and **`world_mask: u16`** are carried through unchanged by
  all new operations (slicing, grouping, assembly).

### 2.5 World-snapping carry-over

Pitch-affecting ops re-snap to the active `world_mask` via the base
`snap_to_world` / `quantize_pitch_to_world`; pure reorderings do not (the base
`op_needs_world_snap` table governs this). World-snapping is a **projection**
that can break the group involutions (`snap∘invert∘snap∘invert ≠ identity` in
general). This is expected and correct.

**Rule for new code:** the grouping and assembly layers operate on already-
developed (already-snapped) lines and must **not** re-snap. They only slice,
measure, and concatenate — operations that preserve world membership because
they neither transpose nor invert. Therefore `motif_in_world` (base validator)
must still hold on the output of `develop_period_grouped` whenever it held on
the A and B inputs.

---

## 3. Module: `motif_form.cairo`

### 3.1 Goal

Replace uniform op selection (`raw % 12` in the base `program_from_seed`) with a
**weighted** selection following developing-variation practice, and add a flat
AABA builder. Per MeloForm and the algorithmic-composition literature, the
musical-quality lever is the *probability distribution over operations*, not the
seed-to-int mapping.

### 3.2 Local helpers (duplicated from base — see §2.2)

`seed_u256`, `pow2`, `extract_bits` — copied verbatim from the base module.
Delete if base §2.2(A) is adopted.

### 3.3 Weighted op distribution

Two-phase cumulative-weight table over the 12 auto-generatable ops (Concat is
excluded — it requires a payload). The program splits in half:

- **Phase 0 (statement / spinning-out):** favour `Transpose`, `Sequence`,
  `Fragment`, `Stutter`.
- **Phase 1 (answer / contrast):** raise `Invert`, `Retrograde`,
  `RetrogradeInvert`.

Reference weights (review-tunable):

| Op (kind index) | Phase 0 | Phase 1 |
|----|--------:|--------:|
| Transpose (0) | 6 | 3 |
| Invert (1) | 1 | 4 |
| Retrograde (2) | 1 | 3 |
| RetrogradeInvert (3) | 1 | 3 |
| Augment (4) | 2 | 2 |
| Diminish (5) | 2 | 2 |
| Fragment (6) | 4 | 2 |
| Sequence (7) | 5 | 2 |
| Rotate (8) | 2 | 2 |
| Stutter (9) | 3 | 1 |
| Interpolate (10) | 2 | 2 |
| IntervalScale (11) | 2 | 2 |

Kind indices match the base `program_from_seed` `if/else if` ladder exactly, so
payload decoding is identical.

**`weighted_kind(raw: u32, phase: u32) -> u32`:**
1. Build the cumulative table for the given phase.
2. `pick = raw % total`.
3. Return the first index whose cumulative bound exceeds `pick`.

### 3.4 `weighted_program_from_seed(seed: felt252, max_ops: u32) -> MotifProgram`

Same windowed-bit decoding as base `program_from_seed` (16-bit windows at
`shift = 8 + i*16`; same payload bit-slices per kind), with two changes:
1. Op **kind** = `weighted_kind(raw, phase)`, `phase = 0` for the first `cap/2`
   ops, `1` after.
2. Concat is never auto-emitted.

`cap` clamping (matches base): `0 → 6`, `>8 → 8`, else `max_ops`.

### 3.5 Flat period: `develop_period(theme, durations, seed, max_ops) -> DevelopedMotif`

A·A·B·A concatenation: A from `weighted_program_from_seed(seed)`, B from
`weighted_program_from_seed(seed + B_SALT)`, A re-run per slot (deterministic).
`B_SALT = 0x9E3779B9`. Superseded by §5 but kept as a fallback / test target.

### 3.6 Tests

- `period_length_consistent(seed)` — period length == 4 × single-A length.

---

## 4. Module: `grouping_boundaries.cairo`

### 4.1 Goal

Decide *where phrases end* from the line's own contour, replacing fixed-length
cuts. Implements the **local subset** of GTTM's Grouping Preference Rules — the
only subset tractable on-chain.

Implemented: **GPR 2 (proximity)** — boundary after a duration spike; **GPR 3
(change)** — boundary at a register leap.

Deliberately omitted (require global optimization): GPR 4 (intensification),
GPR 5 (symmetry), GPR 6 (parallelism), GPR 7 (well-formedness). Parallelism is
handled by construction in §5, not by detection.

### 4.2 Imports

`DevelopedMotif` from `motif_development`; `abs_i32` from `canon_rules` (same
source the base module uses). Local `concat_*` / slicing helpers per §2.2(B).

### 4.3 Tuning constants

```
W_PROXIMITY    = 3   // duration-spike weight (GPR 2)
W_CHANGE       = 2   // register-leap weight  (GPR 3)
PEAK_THRESHOLD = 4   // minimum strength to count as a boundary
MIN_GROUP_LEN  = 2   // minimum notes per group (no slivers)
```

Temporal gaps are slightly stronger cues than registral ones, hence
`W_PROXIMITY > W_CHANGE`. All four review-tunable.

### 4.4 `gap_strength(degrees, durations, i) -> u32`

Strength of the gap **after** note `i`. Returns `0` if `i+1 >= n`.

- **GPR 2 term:** baseline `(dur[i-1] + dur[i+1]) / 2` (edge fallbacks). If
  `dur[i] > base`, add `(dur[i] - base) * W_PROXIMITY`.
- **GPR 3 term:** `leap_here = |deg[i+1] - deg[i]|`; baseline
  `(|deg[i]-deg[i-1]| + |deg[i+2]-deg[i+1]|) / 2` (edge fallbacks to
  `leap_here`). If `leap_here > base`, add `(leap_here - base) * W_CHANGE`.

Both terms are **relative to local context** — GPRs detect local maxima.

### 4.5 `grouping_boundaries(m) -> Array<u32>`

Returns strictly-increasing boundary indices `b` (group ends after note `b`).
Final note is an implicit boundary, not included.

1. If `n < MIN_GROUP_LEN * 2`, return empty.
2. Precompute `strengths[i]`.
3. Accept gap `g` iff: `strengths[g] >= PEAK_THRESHOLD`; local maximum
   (`>=` both neighbours); `g+1 >= last_boundary + MIN_GROUP_LEN`;
   `n - (g+1) >= MIN_GROUP_LEN` (viable tail).

### 4.6 Slicing & segmentation

- `slice_developed(m, start, end_excl)` — copies `[start, end_excl)`, preserves
  `octave` / `world_mask`, keeps durations parallel (fallback `1`).
- `segment_into_groups(m) -> Array<DevelopedMotif>` — lossless partition;
  concatenation reproduces input.
- `group_lengths(m) -> Array<u32>` — note-counts; sum == `m.degrees.len()`.

### 4.7 Tests

- `groups_partition_exact(m)` — lengths sum to original (lossless).
- `groups_respect_min(m)` — every group `>= MIN_GROUP_LEN`.

---

## 5. Module: `period_assembly.cairo`

### 5.1 Goal & key principle

Tie grouping into form so AABA cuts follow contour-derived phrasing.
**Parallelism (A's recurrence) is guaranteed by construction** — reuse the same
A value — **not by detection**, keeping GPR 6 segment-matching off-chain.

### 5.2 Pipeline

```
theme + seed
  ├─ A: weighted_program_from_seed(seed)        → apply_program → a_full
  │     head_phrase(a_full) = first GPR group   → A
  ├─ B: weighted_program_from_seed(seed+B_SALT) → apply_program → b_full
  │     head_phrase(b_full)                      → B
  └─ assemble: A · A · B · A   (A cloned verbatim ⇒ exact parallelism)
```

### 5.3 `head_phrase(m) -> DevelopedMotif`

First complete group from `segment_into_groups(m)`; fall back to the whole line
if no boundary found. Returns an owned clone (see §2.3 — no `Copy`).

### 5.4 `develop_period_grouped(theme, durations, seed, max_ops) -> DevelopedMotif`

1. `a = head_phrase(apply_program(theme, durations, weighted_program_from_seed(seed)))`.
2. `b = head_phrase(apply_program(theme, durations, weighted_program_from_seed(seed + B_SALT)))`.
3. Assemble `A · A · B · A`, cloning `a` for each A slot.

`B_SALT = 0x9E3779B9` — **must equal** the value in §3.5.

### 5.5 Diagnostics

- `period_section_lengths(...) -> (u32, u32)` — `(|A|, |B|)` chosen by grouping,
  for inspection without rendering.

### 5.6 Tests

- `grouped_period_length_consistent(seed)` — length == `3*|A| + |B|`.
- `head_phrase_well_formed(seed)` — non-empty, no longer than source.

---

## 6. Determinism & on-chain constraints

1. **Integer-only.** No floating point. `IntervalScale` uses integer `num/den`
   truncation (matching base `interval_scale_degrees`); weights/thresholds `u32`.
2. **Seed-deterministic.** Identical `(theme, durations, seed, max_ops)` ⇒
   byte-identical output across runs and nodes.
3. **Total functions.** Defined for all inputs (out-of-range fragment starts,
   zero denominators, zero reps, empty/single-note/flat lines). Extends the base
   `motif_ops_total()` pattern.
4. **No global optimization on-chain.** Only the local GPR subset (single pass)
   runs on-chain; parallelism is construction-time.
5. **Length invariant.** degrees.len() == durations.len() after every operation
   (see §2.4), so the canon/MIDI handoff stays valid.
6. **World invariant.** Grouping/assembly never re-snap (§2.5); `motif_in_world`
   holds on output if it held on inputs.

---

## 7. Implementation order

1. **(Optional, recommended)** Adopt §2.2(A): widen base seed/bit + concat
   helpers to `pub`, add a public `clone_developed`. Then drop the duplicated
   helpers from the new modules.
2. `motif_form.cairo`: helpers → `weighted_kind` → `weighted_program_from_seed`
   → `develop_period` → `period_length_consistent`.
3. `grouping_boundaries.cairo`: `gap_strength` → `grouping_boundaries` →
   slicing → `segment_into_groups` / `group_lengths` → partition tests.
4. `period_assembly.cairo`: `head_phrase` → `develop_period_grouped` →
   diagnostics → period tests.
5. Register the three modules in the composition module tree.
6. Wire all `#[test]` functions into the existing composition test suite.

---

## 8. Acceptance criteria

- [ ] All new tests pass deterministically (run twice → identical results).
- [ ] `groups_partition_exact` holds for `grundgestalt_theme(0..3)` developed at
      several seeds.
- [ ] `grouped_period_length_consistent` holds across ≥ 8 distinct seeds.
- [ ] Totality test (analogous to `motif_ops_total()`): no panics on empty /
      single-note / flat / out-of-range inputs.
- [ ] Op-distribution audit: over ≥ 256 seeds, phase-0 op frequencies match the
      §3.3 weight table within tolerance (confirms weighting is applied).
- [ ] **Regression:** existing `op_laws_hold()` and `motif_ops_total()` still
      pass (base algebra intact).
- [ ] **Length-invariant check:** `degrees.len() == durations.len()` on every
      `develop_period_grouped` output.
- [ ] **World check:** `motif_in_world` holds on output when inputs are in-world.

---

## 9. Embedded source

The reference implementations of the three new modules are reproduced below so
this spec is self-contained. They are the implementation target; if they diverge
from the prose above, the prose (and the verified base contract in §2) governs.

### 9.1 `motif_form.cairo`

```cairo
//! Form-level extensions to the motif development algebra.
//!
//! Two additions grounded in the research:
//!   1. `weighted_program_from_seed` — biases op selection toward developing-variation
//!      order (Schoenberg / MeloForm use *musically plausible probabilities*, not uniform).
//!   2. `develop_period` — arranges developed fragments into a hierarchical AABA period,
//!      the structural level MeloForm adds above flat motif-op application.
//!
//! Depends on the existing motif algebra module (Motif, MotifOp, MotifProgram,
//! DevelopedMotif, apply_program, motif_to_developed, concat helpers, seed helpers).

use core::array::ArrayTrait;
use core::option::OptionTrait;

// Pull from your existing module. Adjust the path to wherever the algebra lives.
use koji::composition::motif_development::{
    DevelopedMotif, FragmentOp, Motif, MotifOp, MotifProgram, SequenceOp,
    apply_program, motif_from_degrees,
};

// ──────────────────────────────────────────────────────────
// Local copies of the seed/bit helpers (kept private in the algebra module).
// If you make those `pub`, delete these and import instead.
// ──────────────────────────────────────────────────────────

fn seed_u256(seed: felt252) -> u256 {
    seed.into()
}

fn pow2(p: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= p {
            break;
        }
        r *= 2;
        i += 1;
    };
    r
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

// ──────────────────────────────────────────────────────────
// Weighted op selection
// ──────────────────────────────────────────────────────────

/// Cumulative-weight table over the 13 ops, indexed the same as `decode_op_kind`'s
/// 0..12 space plus Concat at 12 (Concat omitted from auto-generation — it needs a
/// payload). Weights encode developing-variation practice: transposition, sequence,
/// and fragmentation dominate; inversion/retrograde are rarer "answering" gestures.
///
/// Returns (kind, ()) where kind is the chosen op index 0..11.
fn weighted_kind(raw: u32, phase: u32) -> u32 {
    // Two phase profiles. Early phase (phase==0): statement/spinning-out — favor
    // transpose(0), sequence(7), fragment(6), stutter(9). Late phase (phase==1):
    // answering/contrast — raise invert(1), retrograde(2), retrograde-invert(3).
    //
    // Weights are small integers; we build a cumulative table and pick by `raw % total`.
    let w_transpose = if phase == 0 { 6_u32 } else { 3 };
    let w_invert = if phase == 0 { 1_u32 } else { 4 };
    let w_retro = if phase == 0 { 1_u32 } else { 3 };
    let w_retroinv = if phase == 0 { 1_u32 } else { 3 };
    let w_augment = 2_u32;
    let w_diminish = 2_u32;
    let w_fragment = if phase == 0 { 4_u32 } else { 2 };
    let w_sequence = if phase == 0 { 5_u32 } else { 2 };
    let w_rotate = 2_u32;
    let w_stutter = if phase == 0 { 3_u32 } else { 1 };
    let w_interp = 2_u32;
    let w_iscale = 2_u32;

    let mut cum = ArrayTrait::new();
    let mut total: u32 = 0;
    total += w_transpose;
    cum.append(total); // 0
    total += w_invert;
    cum.append(total); // 1
    total += w_retro;
    cum.append(total); // 2
    total += w_retroinv;
    cum.append(total); // 3
    total += w_augment;
    cum.append(total); // 4
    total += w_diminish;
    cum.append(total); // 5
    total += w_fragment;
    cum.append(total); // 6
    total += w_sequence;
    cum.append(total); // 7
    total += w_rotate;
    cum.append(total); // 8
    total += w_stutter;
    cum.append(total); // 9
    total += w_interp;
    cum.append(total); // 10
    total += w_iscale;
    cum.append(total); // 11

    let pick = raw % total;
    let mut k: u32 = 0;
    loop {
        if k >= cum.len() {
            break;
        }
        if pick < *cum.at(k) {
            break;
        }
        k += 1;
    };
    k
}

/// Same windowed-bit decoding as `program_from_seed`, but op KIND is chosen from
/// the weighted table and the first/second halves of the program use early/late
/// phase profiles (statement then answer). Concat is never auto-emitted.
pub fn weighted_program_from_seed(seed: felt252, max_ops: u32) -> MotifProgram {
    let s = seed_u256(seed);
    let mut ops: Array<MotifOp> = ArrayTrait::new();
    let cap = if max_ops == 0 {
        6_u32
    } else if max_ops > 8 {
        8_u32
    } else {
        max_ops
    };
    let half = cap / 2;
    let mut i: u32 = 0;
    loop {
        if i >= cap {
            break;
        }
        let shift = 8 + i * 16;
        let raw = extract_bits(s, shift, 16);
        let phase = if i < half {
            0_u32
        } else {
            1_u32
        };
        let kind = weighted_kind(raw, phase);

        if kind == 0 {
            let n: i32 = (extract_bits(s, shift + 4, 6) % 7).try_into().unwrap();
            let signed = if extract_bits(s, shift + 10, 1) == 0 {
                n
            } else {
                -n
            };
            ops.append(MotifOp::Transpose(signed));
        } else if kind == 1 {
            let axis: i32 = (extract_bits(s, shift + 4, 5)).try_into().unwrap();
            ops.append(MotifOp::Invert(axis));
        } else if kind == 2 {
            ops.append(MotifOp::Retrograde(()));
        } else if kind == 3 {
            let axis: i32 = (extract_bits(s, shift + 4, 5)).try_into().unwrap();
            ops.append(MotifOp::RetrogradeInvert(axis));
        } else if kind == 4 {
            let k = extract_bits(s, shift + 4, 3) + 1;
            ops.append(MotifOp::Augment(k));
        } else if kind == 5 {
            let k = extract_bits(s, shift + 4, 3) + 1;
            ops.append(MotifOp::Diminish(k));
        } else if kind == 6 {
            let start = extract_bits(s, shift + 4, 4);
            let len = extract_bits(s, shift + 8, 4) + 1;
            ops.append(MotifOp::Fragment(FragmentOp { start, len }));
        } else if kind == 7 {
            let step: i32 = (extract_bits(s, shift + 4, 5) % 5).try_into().unwrap();
            let count = extract_bits(s, shift + 9, 3) + 1;
            ops.append(MotifOp::Sequence(SequenceOp { step, count }));
        } else if kind == 8 {
            let r = extract_bits(s, shift + 4, 4) + 1;
            ops.append(MotifOp::Rotate(r));
        } else if kind == 9 {
            let index = extract_bits(s, shift + 4, 4);
            let reps = extract_bits(s, shift + 8, 3) + 1;
            ops.append(MotifOp::Stutter(crate_stutter(index, reps)));
        } else if kind == 10 {
            let min_step = extract_bits(s, shift + 4, 3) + 1;
            ops.append(MotifOp::Interpolate(min_step));
        } else {
            let num: i32 = (extract_bits(s, shift + 4, 4) + 1).try_into().unwrap();
            let den: i32 = (extract_bits(s, shift + 8, 4) + 1).try_into().unwrap();
            ops.append(MotifOp::IntervalScale(crate_iscale(num, den)));
        }
        i += 1;
    };
    MotifProgram { ops }
}

// Tiny constructors so this file doesn't need to import the op-payload structs by
// value in match arms. Replace with direct struct literals if you prefer.
use koji::composition::motif_development::{IntervalScaleOp, StutterOp};

fn crate_stutter(index: u32, reps: u32) -> StutterOp {
    StutterOp { index, reps }
}

fn crate_iscale(num: i32, den: i32) -> IntervalScaleOp {
    IntervalScaleOp { num, den }
}

// ──────────────────────────────────────────────────────────
// Hierarchical form: AABA period
// ──────────────────────────────────────────────────────────

fn concat_i32_local(a: Span<i32>, b: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    i = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

fn concat_u32_local(a: Span<u32>, b: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    i = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

fn append_developed(acc: DevelopedMotif, next: @DevelopedMotif) -> DevelopedMotif {
    DevelopedMotif {
        degrees: concat_i32_local(acc.degrees.span(), next.degrees.span()),
        durations: concat_u32_local(acc.durations.span(), next.durations.span()),
        octave: acc.octave,
        world_mask: acc.world_mask,
    }
}

/// Build an AABA period from one theme. The A sections share an identical
/// development (literal repetition — the structural backbone), and B is a
/// contrasting development driven by a perturbed seed. This is the hierarchical
/// layer MeloForm adds above flat op application: a motif becomes a phrase, and
/// phrases are arranged into a form with repetition + contrast.
///
/// `a_ops` develops the A material; B uses `weighted_program_from_seed(seed ^ salt)`
/// in late-phase-heavy form so it reads as an answer, not a restatement.
pub fn develop_period(
    theme: @Motif, durations: @Array<u32>, seed: felt252, max_ops: u32,
) -> DevelopedMotif {
    // A: statement development.
    let a_program = weighted_program_from_seed(seed, max_ops);
    let a = apply_program(theme, durations, a_program);

    // B: contrasting development from a perturbed seed.
    let b_seed = seed + 0x9E3779B9; // golden-ratio salt; any fixed nonzero offset works
    let b_program = weighted_program_from_seed(b_seed, max_ops);
    let b = apply_program(theme, durations, b_program);

    // Assemble A A B A. Each section is independently developed; the A's are
    // identical (true repetition), B contrasts, final A returns home.
    let a1 = a;
    let a2_src = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    let acc = append_developed(a1, @a2_src);
    let acc = append_developed(acc, @b);

    let a4_src = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    append_developed(acc, @a4_src)
}

// ──────────────────────────────────────────────────────────
// Smoke checks (call from a #[test], or inline-assert during bring-up)
// ──────────────────────────────────────────────────────────

/// Period length must equal 4 × (single-A length) when ops are deterministic per seed.
pub fn period_length_consistent(seed: felt252) -> bool {
    let theme = motif_from_degrees(array![0_i32, 2, 1, 4], 7, 0);
    let durs = array![1_u32, 1, 1, 1];
    let single = apply_program(@theme, @durs, weighted_program_from_seed(seed, 4));
    let period = develop_period(@theme, @durs, seed, 4);
    period.degrees.len() == single.degrees.len() * 4
}
```

### 9.2 `grouping_boundaries.cairo`

```cairo
//! Grouping-boundary detection — the tractable local subset of GTTM's
//! Grouping Preference Rules, computed over a developed line's own contour.
//!
//! Implements GPR 2 (proximity: boundaries at long inter-onset gaps / long
//! durations) and GPR 3 (change: boundaries at large register leaps). These are
//! the two *local* GPRs — a single integer pass, no global optimization — which
//! is the subset that fits on-chain. The expensive rules (parallelism GPR 6,
//! symmetry GPR 5, global well-formedness) are deliberately omitted.
//!
//! Output: a list of boundary indices that partition a DevelopedMotif into
//! groups, replacing fixed-length section cuts with contour-derived ones.

use core::array::ArrayTrait;
use core::option::OptionTrait;

use koji::composition::motif_development::DevelopedMotif;
use koji::composition::canon_rules::abs_i32;

// ──────────────────────────────────────────────────────────
// Tuning constants
// ──────────────────────────────────────────────────────────

/// Weight on a duration spike (GPR 2). Long notes / held onsets cue a boundary.
const W_PROXIMITY: u32 = 3;
/// Weight on a register-leap spike (GPR 3). Large intervals cue a boundary.
const W_CHANGE: u32 = 2;
/// A gap must score at least this much above the local baseline to count as a
/// boundary. Higher = fewer, stronger boundaries.
const PEAK_THRESHOLD: u32 = 4;
/// Minimum notes per group — prevents pathological one-note slivers.
const MIN_GROUP_LEN: u32 = 2;

// ──────────────────────────────────────────────────────────
// Per-gap boundary strength
// ──────────────────────────────────────────────────────────

/// Boundary strength at the gap *after* note i (i.e. between note i and i+1).
///
/// GPR 2 contribution: how much longer note i is than its neighbours — a held
/// note creates a gap. We use the duration of note i relative to the mean of its
/// immediate neighbours.
///
/// GPR 3 contribution: the size of the register leap from note i to note i+1
/// relative to the surrounding leaps.
///
/// Both contributions are "relative to local context" because GPRs detect
/// *local* maxima, not absolute magnitudes.
fn gap_strength(
    degrees: Span<i32>, durations: Span<u32>, i: u32,
) -> u32 {
    let n = degrees.len();
    // Need a note on each side of the gap.
    if i + 1 >= n {
        return 0;
    }

    // ---- GPR 2: proximity (duration spike at note i) ----
    let dur_here = if durations.len() > i {
        *durations.at(i)
    } else {
        1_u32
    };
    let dur_next = if durations.len() > i + 1 {
        *durations.at(i + 1)
    } else {
        1_u32
    };
    // Local baseline = previous duration if it exists, else current.
    let dur_prev = if i > 0 && durations.len() > i - 1 {
        *durations.at(i - 1)
    } else {
        dur_here
    };
    let local_dur_base = (dur_prev + dur_next) / 2;
    let prox = if dur_here > local_dur_base {
        (dur_here - local_dur_base) * W_PROXIMITY
    } else {
        0_u32
    };

    // ---- GPR 3: change (register leap at the gap i -> i+1) ----
    let leap_here: u32 = abs_i32(*degrees.at(i + 1) - *degrees.at(i))
        .try_into()
        .unwrap();
    // Compare to the leaps on either side.
    let leap_prev: u32 = if i > 0 {
        abs_i32(*degrees.at(i) - *degrees.at(i - 1)).try_into().unwrap()
    } else {
        leap_here
    };
    let leap_next: u32 = if i + 2 < n {
        abs_i32(*degrees.at(i + 2) - *degrees.at(i + 1)).try_into().unwrap()
    } else {
        leap_here
    };
    let local_leap_base = (leap_prev + leap_next) / 2;
    let change = if leap_here > local_leap_base {
        (leap_here - local_leap_base) * W_CHANGE
    } else {
        0_u32
    };

    prox + change
}

// ──────────────────────────────────────────────────────────
// Boundary selection
// ──────────────────────────────────────────────────────────

/// Compute boundary indices for a developed line. A returned index `b` means a
/// group ends *after* note b (so the next group starts at b+1). Indices are
/// strictly increasing; the final note is always an implicit boundary and is NOT
/// included (the caller closes the last group at the end of the array).
///
/// Selection: score every gap, then accept a gap as a boundary iff
///   (a) its strength >= PEAK_THRESHOLD, and
///   (b) it is a local maximum (>= both neighbouring gap strengths), and
///   (c) it is at least MIN_GROUP_LEN notes past the previous boundary.
pub fn grouping_boundaries(m: @DevelopedMotif) -> Array<u32> {
    let degrees = m.degrees.span();
    let durations = m.durations.span();
    let n = degrees.len();
    let mut boundaries: Array<u32> = ArrayTrait::new();
    if n < MIN_GROUP_LEN * 2 {
        return boundaries; // too short to split
    }

    // Precompute strengths into an array so we can test local-maximum cheaply.
    let mut strengths: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        strengths.append(gap_strength(degrees, durations, i));
        i += 1;
    };
    let s = strengths.span();

    let mut last_boundary_plus1: u32 = 0; // first allowed group start
    let mut g: u32 = 0;
    loop {
        // Only consider gaps that can have a note on each side and that leave a
        // viable final group.
        if g + 1 >= n {
            break;
        }
        let here = *s.at(g);
        if here >= PEAK_THRESHOLD {
            let left = if g > 0 {
                *s.at(g - 1)
            } else {
                0
            };
            let right = if g + 1 < n {
                *s.at(g + 1)
            } else {
                0
            };
            let is_local_max = here >= left && here >= right;
            let far_enough = g + 1 >= last_boundary_plus1 + MIN_GROUP_LEN;
            // Also ensure the remaining tail can form a full group.
            let tail_ok = (n - (g + 1)) >= MIN_GROUP_LEN;
            if is_local_max && far_enough && tail_ok {
                boundaries.append(g);
                last_boundary_plus1 = g + 1;
            }
        }
        g += 1;
    };
    boundaries
}

// ──────────────────────────────────────────────────────────
// Slicing a developed line at boundaries
// ──────────────────────────────────────────────────────────

fn slice_developed(m: @DevelopedMotif, start: u32, end_excl: u32) -> DevelopedMotif {
    let degrees = m.degrees.span();
    let durations = m.durations.span();
    let mut d: Array<i32> = ArrayTrait::new();
    let mut u: Array<u32> = ArrayTrait::new();
    let mut i = start;
    loop {
        if i >= end_excl {
            break;
        }
        d.append(*degrees.at(i));
        if durations.len() > i {
            u.append(*durations.at(i));
        } else {
            u.append(1);
        }
        i += 1;
    };
    DevelopedMotif {
        degrees: d,
        durations: u,
        octave: *m.octave,
        world_mask: *m.world_mask,
    }
}

/// Partition a developed line into groups at its detected boundaries. Returns the
/// groups in order; concatenating them reproduces the input exactly.
pub fn segment_into_groups(m: @DevelopedMotif) -> Array<DevelopedMotif> {
    let n = m.degrees.len();
    let bounds = grouping_boundaries(m);
    let bspan = bounds.span();
    let mut groups: Array<DevelopedMotif> = ArrayTrait::new();
    if n == 0 {
        return groups;
    }
    let mut start: u32 = 0;
    let mut bi: u32 = 0;
    loop {
        if bi >= bspan.len() {
            break;
        }
        let end_excl = *bspan.at(bi) + 1; // boundary ends the group *after* that note
        groups.append(slice_developed(m, start, end_excl));
        start = end_excl;
        bi += 1;
    };
    // Final group: start .. n
    if start < n {
        groups.append(slice_developed(m, start, n));
    }
    groups
}

// ──────────────────────────────────────────────────────────
// Section-length helper for form builders
// ──────────────────────────────────────────────────────────

/// Return just the group LENGTHS (note counts), which a form builder can use to
/// place A/B section cuts on the line's own grouping structure instead of fixed
/// lengths. Sum of returned lengths == m.degrees.len().
pub fn group_lengths(m: @DevelopedMotif) -> Array<u32> {
    let groups = segment_into_groups(m);
    let mut lens: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= groups.len() {
            break;
        }
        lens.append(groups.at(i).degrees.len());
        i += 1;
    };
    lens
}

// ──────────────────────────────────────────────────────────
// Smoke checks
// ──────────────────────────────────────────────────────────

/// Group lengths must sum to the original length (partition is exact, lossless).
pub fn groups_partition_exact(m: @DevelopedMotif) -> bool {
    let n = m.degrees.len();
    let lens = group_lengths(m);
    let mut total: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= lens.len() {
            break;
        }
        total += *lens.at(i);
        i += 1;
    };
    total == n
}

/// Every group respects the minimum length (no slivers).
pub fn groups_respect_min(m: @DevelopedMotif) -> bool {
    let lens = group_lengths(m);
    if lens.len() == 0 {
        return true;
    }
    let mut i: u32 = 0;
    loop {
        if i >= lens.len() {
            break true;
        }
        if *lens.at(i) < MIN_GROUP_LEN {
            // The very last group can be shorter only if the whole line is short;
            // detector guarantees tail_ok otherwise.
            break false;
        }
        i += 1;
    }
}
```

### 9.3 `period_assembly.cairo`

```cairo
//! Form assembly driven by grouping structure.
//!
//! Ties the local-GPR phrase detector (`grouping_boundaries`) into period
//! construction so section cuts fall on the line's own contour instead of a
//! fixed grid. Parallelism (the recurrence of A) is handled on the *generation*
//! side — we build the A material once and reuse it — so no expensive
//! parallelism detection runs on-chain. The grouping heuristic only places the
//! internal phrase boundaries within each section.
//!
//! Pipeline:
//!   theme + seed
//!     ├─ A statement : weighted_program_from_seed(seed)        -> develop -> A
//!     │                 grouping_boundaries(A) gives A's internal phrasing
//!     ├─ B contrast  : weighted_program_from_seed(seed ^ salt) -> develop -> B
//!     └─ assemble     : A · A · B · A   (A reused verbatim => true parallelism)

use core::array::ArrayTrait;
use core::option::OptionTrait;

use koji::composition::motif_development::{
    DevelopedMotif, Motif, apply_program, motif_from_degrees,
};
use koji::composition::motif_form::weighted_program_from_seed;
use koji::composition::grouping_boundaries::{group_lengths, segment_into_groups};

// ──────────────────────────────────────────────────────────
// Concatenation (local; mirror of the algebra module's helpers)
// ──────────────────────────────────────────────────────────

fn concat_i32_local(a: Span<i32>, b: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    i = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

fn concat_u32_local(a: Span<u32>, b: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    i = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

fn append_developed(acc: DevelopedMotif, next: @DevelopedMotif) -> DevelopedMotif {
    DevelopedMotif {
        degrees: concat_i32_local(acc.degrees.span(), next.degrees.span()),
        durations: concat_u32_local(acc.durations.span(), next.durations.span()),
        octave: acc.octave,
        world_mask: acc.world_mask,
    }
}

fn clone_developed(m: @DevelopedMotif) -> DevelopedMotif {
    DevelopedMotif {
        degrees: concat_i32_local(m.degrees.span(), array![].span()),
        durations: concat_u32_local(m.durations.span(), array![].span()),
        octave: *m.octave,
        world_mask: *m.world_mask,
    }
}

// ──────────────────────────────────────────────────────────
// Phrase selection from grouping structure
// ──────────────────────────────────────────────────────────

/// Pick the "head phrase" of a developed line: the first complete group as
/// detected by the GPR heuristic. This is the A-material — the line's natural
/// opening phrase, ended where its own contour says it ends (a held note or a
/// register leap), not at an arbitrary bar count. Falls back to the whole line
/// if no boundary is found (line too short / too flat to split).
pub fn head_phrase(m: @DevelopedMotif) -> DevelopedMotif {
    let groups = segment_into_groups(m);
    if groups.len() == 0 {
        return clone_developed(m);
    }
    clone_developed(groups.at(0))
}

/// The salt that perturbs the B-section seed. Golden-ratio constant: any fixed
/// nonzero offset produces a deterministic, reproducible contrast.
const B_SALT: felt252 = 0x9E3779B9;

// ──────────────────────────────────────────────────────────
// Grouping-driven AABA period
// ──────────────────────────────────────────────────────────

/// Build an AABA period whose section lengths come from grouping structure.
///
/// 1. Develop A from `seed`, then extract its head phrase via the GPR detector —
///    this is the A-material, cut where the contour phrases it.
/// 2. Develop B from a salted seed and likewise take its head phrase, so B is a
///    self-contained contrasting phrase rather than a same-length restatement.
/// 3. Assemble A · A · B · A. The A phrase is reused verbatim, so the recurrence
///    is exact (parallelism guaranteed by construction, not detected).
///
/// Result reproduces the spirit of MeloForm's form layer but with phrase
/// boundaries derived from L&J grouping rules instead of hardcoded bar counts.
pub fn develop_period_grouped(
    theme: @Motif, durations: @Array<u32>, seed: felt252, max_ops: u32,
) -> DevelopedMotif {
    // A material: develop, then phrase by contour.
    let a_full = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    let a = head_phrase(@a_full);

    // B material: salted seed -> contrasting development -> contour phrase.
    let b_full = apply_program(
        theme, durations, weighted_program_from_seed(seed + B_SALT, max_ops),
    );
    let b = head_phrase(@b_full);

    // Assemble A A B A, reusing the A phrase verbatim each time.
    let acc = clone_developed(@a);
    let acc = append_developed(acc, @a);
    let acc = append_developed(acc, @b);
    append_developed(acc, @a)
}

/// Diagnostic: return the (A_len, B_len) the grouping chose for a given seed, so
/// you can inspect how contour drives section sizing without rendering audio.
pub fn period_section_lengths(
    theme: @Motif, durations: @Array<u32>, seed: felt252, max_ops: u32,
) -> (u32, u32) {
    let a_full = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    let a = head_phrase(@a_full);
    let b_full = apply_program(
        theme, durations, weighted_program_from_seed(seed + B_SALT, max_ops),
    );
    let b = head_phrase(@b_full);
    (a.degrees.len(), b.degrees.len())
}

// ──────────────────────────────────────────────────────────
// Smoke checks
// ──────────────────────────────────────────────────────────

/// The period length must equal 3·|A| + |B| (A appears three times, B once).
pub fn grouped_period_length_consistent(seed: felt252) -> bool {
    let theme = motif_from_degrees(array![0_i32, 2, 1, 4], 7, 0);
    let durs = array![1_u32, 1, 1, 1];
    let (a_len, b_len) = period_section_lengths(@theme, @durs, seed, 6);
    let period = develop_period_grouped(@theme, @durs, seed, 6);
    period.degrees.len() == a_len * 3 + b_len
}

/// The head phrase is never empty for a non-empty input and never longer than
/// the line it came from.
pub fn head_phrase_well_formed(seed: felt252) -> bool {
    let theme = motif_from_degrees(array![0_i32, 2, 4, 7, 4, 2], 7, 0);
    let durs = array![1_u32, 1, 1, 1, 1, 1];
    let full = apply_program(@theme, @durs, weighted_program_from_seed(seed, 6));
    let n = full.degrees.len();
    if n == 0 {
        return true;
    }
    let phrase = head_phrase(@full);
    let pn = phrase.degrees.len();
    pn > 0 && pn <= n
}
```

> The full source of all three new modules is embedded above, so this spec is
> self-contained. The same files also ship as standalone `.cairo` artifacts for
> direct placement under `src/composition/`. If they ever diverge, §2 (the
> verified base contract) and the prose above govern.

---

## 10. Future work (out of scope)

- **Prolongational reduction (GTTM second half).** Would let B's contrast be
  *harmonically derived* from A rather than seed-perturbed. Requires time-span
  reduction; genuinely expensive — recommend off-chain precompute with an
  on-chain committed hash, not native Cairo.
- **GPR 6 parallelism detection.** Only needed to *recover* structure from an
  externally supplied (un-annotated) line. Matching over the transform group is
  costly; defer unless analysis of external input is required.
- **Distribution learning.** The §3.3 weights are hand-set from developing-
  variation practice; could be fit to a corpus offline and shipped as constants.

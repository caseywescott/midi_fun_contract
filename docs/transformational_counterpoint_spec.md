# Transformational Counterpoint Spec

Status: implemented v1

Module: `src/composition/transformational_counterpoint.cairo`

Tests: `src/tests/test_transformational_counterpoint.cairo`

## Purpose

Transformational counterpoint formalizes reusable musical material as:

```text
line -> transform(line) -> validate(overlap/style/invariant)
```

The same transformed line can be used as:

- a canon follower,
- a countersubject or accompaniment,
- a hocket partition,
- an isorhythmic voice,
- a standalone harmonized composition layer.

This module keeps material in signed degree space before realizing it to MIDI keynums. That lets
the engine validate profile legality, consonance, and invertible-counterpoint safety before output.

## Core Representation

```cairo
DegreeEvent {
    degree,
    time,
    duration,
    velocity,
    voice_id,
}
```

`degree` is a diatonic or chromatic lattice position. It is converted to `NoteEvent` only at the
rendering boundary with `degree_events_to_note_events`.

## Implemented Transforms

Pitch and order:

- `transpose_line`
- `invert_line`, using the existing canon convention `degree -> pivot - degree`
- `axis_invert_line`, using `degree -> 2 * axis - degree`
- `retrograde_line`
- `retrograde_keep_durations`
- `retrograde_inversion_line`

Time:

- `delay_line`
- `time_scale_line`
- `augment_line`
- `diminish_line`

Voice placement:

- `voice_exchange_by_index`
- `voice_exchange_material_by_index`
- `assign_voice_id`

Texture constructors:

- `hocket_part`
- `hocket_partition`
- `isorhythm_line`
- `simple_third_harmonized_composition`
- `standalone_harmonized_transform`

Canon constructors:

- `transformed_follower`
- `transformed_canon_texture`

Supported canon transform kinds:

- exact canon
- mirror canon
- crab canon
- augmentation canon
- diminution canon
- retrograde-inversion canon

## Validation

The module provides generic overlap-aware validators:

- `events_overlap`
- `rhythm_valid`
- `overlaps_consonant`
- `overlaps_profile_ok`
- `overlaps_ic_safe`
- `texture_profile_ok`
- `texture_ic_safe`
- `no_same_voice_overlaps`

Identity validators confirm that a generated follower is truly the requested transform:

- `exact_identity_holds`
- `mirror_identity_holds`
- `crab_identity_holds`
- `hocket_reconstructs`

Failure categories are represented by `TransformFailure`:

- `Ok`
- `LengthMismatch`
- `PitchTransformMismatch`
- `RhythmTransformMismatch`
- `VerticalClash`
- `ICSafetyClash`
- `InvalidRatio`
- `InvalidVoiceCount`

## Generation Policy

`seeded_canon_transform_plan` deterministically selects:

- transform family,
- factor,
- pivot,
- transposition,
- entry time,
- follower voice id.

The v1 ratio set is intentionally bounded to integer augmentation and divisor-safe diminution.

Strict and permissive generation are both available:

- `strict_transformed_follower` emits the requested follower and reports whether it validates.
- `permissive_transformed_follower` tries the requested follower, then bounded transposition repair,
  then a conservative third-based fallback.

Descriptor helpers:

- `canon_transform_kind_id`
- `canon_transform_kind_from_id`
- `canon_transform_descriptor`

## Integration Points

The module reuses:

- `melodic_canon::NoteEvent`, `DEFAULT_VELOCITY`, and `realize_degree`
- `aesthetic_profile::vertical_ok`
- `canon_rules::is_consonant_class`
- `invertible_counterpoint::lattice_ic_safe`

The API is intentionally independent from `canon_inversion.cairo` so existing canon behavior stays
stable, while new canonic and non-canonic textures can share the same validation layer.

## Verification

Focused suite:

```bash
scarb test -- --filter transformational_counterpoint
```

Result:

```text
14 passed; 0 failed
```

Full suite:

```bash
scarb test
```

Result:

```text
702 passed; 0 failed; 232 ignored
```

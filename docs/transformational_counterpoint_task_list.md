# Task List: Transformational Counterpoint and Reusable Line Engines

Source idea: formalize augmentation, diminution, retrograde, melodic inversion, mirror canon,
crab canon, voice exchange, hocket, and isorhythm as reusable transformations on finite musical
objects.

Primary intention:

- Use the transforms inside canons as follower strategies.
- Use the same transforms outside canons to generate independent harmonized compositions.
- Share validation logic with invertible counterpoint, aesthetic profiles, rhythmic tiling, and
  motif/parameter-plane transforms.

## Implementation status

Status: implemented in `midi_fun_contract` as a v1 integration.

Completed files:

- `midi_fun_contract/src/composition/transformational_counterpoint.cairo`
- `midi_fun_contract/src/tests/test_transformational_counterpoint.cairo`
- `midi_fun_contract/docs/transformational_counterpoint_spec.md`

Exports added:

- `midi_fun_contract/src/composition.cairo`
- `midi_fun_contract/src/tests.cairo`

Implemented coverage:

- Degree-level event representation and NoteEvent conversion.
- Pure transforms: transpose, inversion, axis inversion, retrograde, retrograde-inversion, delay,
  time-scale, augmentation, diminution.
- Canon followers: exact, mirror, crab, augmented, diminished, retrograde-inversion.
- Standalone composition helpers: third-harmonized transformed companion, explicit subject plus
  companion plans.
- Voice exchange, hocket partition/reconstruction, and isorhythm.
- Overlap-aware validators for consonance, profile legality, invertible-counterpoint safety, rhythm,
  same-voice overlap, and transform identity.
- Seeded transform-plan selection, descriptor labels, strict validation, bounded transposition
  repair, and permissive fallback.

Verification:

- `scarb test -- --filter transformational_counterpoint`: 14 passed, 0 failed.
- `scarb test`: 702 passed, 0 failed, 232 ignored.

## How to use this list

- Mark each task as done with `[x]` when acceptance criteria are met.
- Keep algorithm-level details synchronized with the relevant spec docs.
- If a task changes deterministic output, regenerate demos/fixtures and document the seed/version.
- Prefer pure Cairo functions with deterministic tests before adding demo renderers.

---

## Phase 0: Scope and architecture decisions

- [x] Decide whether the new layer is a new module, for example
      `src/composition/transformational_counterpoint.cairo`, or a split across smaller modules.
- [x] Decide the canonical event representation for transform validation:
      `NoteEvent` streams, degree/time pairs, or parameter-plane `MusicalObject`.
- [x] Define the minimum supported transform set for v1:
      augmentation, diminution, retrograde, inversion, mirror canon, crab canon, voice exchange,
      hocket partition, and isorhythm.
- [x] Decide which transforms are pitch-only, time-only, order-only, voice-assignment-only, or
      compound transforms.
- [x] Decide supported time ratios for Cairo v1:
      integer augmentation factors and divisor-safe diminution factors first.
- [x] Decide whether all validators operate on diatonic lattice classes, chromatic semitone
      classes, or both.
- [x] Decide naming for "follower transform" vs "composition transform" so canon-specific logic
      does not leak into standalone composition APIs.

### Acceptance criteria

- [x] A short design note exists explaining the shared abstraction:
      `line -> transform(line) -> validate(overlap/style/invariant)`.
- [x] The v1 transform list is frozen.
- [x] The implementation target modules and public APIs are named.

---

## Phase 1: Core data model

- [x] Add a reusable struct for degree-level timed material, for example:
      `DegreeEvent { degree, time, duration, velocity, voice_id }`.
- [x] Add a reusable struct for transform plans, for example:
      `LineTransformPlan` or `TransformVoiceSpec`.
- [x] Add transform variants:
      `Delay`, `Transpose`, `Invert`, `Retrograde`, `TimeScale`, `VoiceExchange`,
      `HocketPartition`, `Isorhythm`, and `Composite`.
- [x] Add role metadata for transformed material:
      `CanonFollower`, `Countersubject`, `Accompaniment`, `Bass`, `InnerVoice`, `CompositeLine`.
- [x] Add helpers to convert between:
      degree sequences,
      `MusicalObject` parameter planes,
      `NoteEvent` streams,
      and transformed voice plans.
- [x] Add stable clone/copy utilities for transformed event arrays.

### Acceptance criteria

- [x] Existing `NoteEvent` rendering can consume output from the new transform layer.
- [x] Degree-level transforms can be validated before keynum realization.
- [x] The new types do not duplicate more of `transform.cairo` or `canon_inversion.cairo` than
      necessary.

---

## Phase 2: Pure transform implementations

### 2.1 Pitch/order transforms

- [x] Implement `transpose_line(line, interval)`.
- [x] Implement `invert_line(line, axis)` using `degree -> axis - degree` or `2 * axis - degree`,
      with the chosen convention documented.
- [x] Implement `retrograde_line(line)` with correct reversed pitch order.
- [x] Implement `retrograde_keep_durations(line)` where durations move with notes.
- [ ] Implement `retrograde_preserve_timespan(line)` where the reversed line fits inside the same
      total duration.
- [x] Implement `retrograde_inversion(line, axis)` as a composite helper.

### 2.2 Time transforms

- [x] Implement `augment_line(line, factor)`.
- [x] Implement `diminish_line(line, factor)` with divisibility guards.
- [x] Implement `delay_line(line, entry_time)`.
- [x] Implement `time_scale_line(line, num, den)` for future non-integer ratios, guarded for v1.
- [ ] Implement total-duration helpers for transformed material.

### 2.3 Voice-assignment transforms

- [x] Implement `voice_exchange(a, b, exchange_points)` for local material or pitch-position swaps.
- [x] Implement `hocket_partition(line, mask_or_period)` to split one line across multiple voices.
- [x] Implement `merge_hocket_parts(parts)` to reconstruct the original composite line.
- [x] Implement `assign_voice_ids(line, voice_id)` and `reassign_voice_range(lines, first_voice_id)`.

### 2.4 Cyclic transforms

- [x] Implement `isorhythm(color, talea, repeat_count)` where pitch and rhythm cycles may have
      different lengths.
- [x] Implement `isorhythm_period(color_len, talea_len) = lcm(color_len, talea_len)`.
- [x] Implement `cycle_index(i, len)` helpers for color/talea lookup.
- [x] Add bounded repeat/trim controls so isorhythmic output stays inside Cairo-friendly limits.

### Acceptance criteria

- [x] Every transform is deterministic, pure, and total for valid inputs.
- [x] Empty or single-note inputs have defined behavior.
- [x] The transform layer can produce both canon followers and standalone transformed lines.

---

## Phase 3: Generic validation layer

- [x] Add a pairwise overlap iterator:
      for every pair of events whose time ranges intersect, expose the active degree/pitch pair.
- [x] Add a degree-lattice vertical validator using existing consonance/profile rules.
- [x] Add a keynum/semitone vertical validator using existing IC helpers where needed.
- [x] Add profile-aware validation:
      `vertical_ok(profile, a, b)`,
      `vertical_ok_invertible(policy, a, b)`,
      and transform-specific overrides.
- [ ] Add melodic validators for each single transformed voice:
      register bounds, max leap, repeated-note policy, cadence/tendency checks where available.
- [x] Add a rhythm validator:
      no zero durations, bounded total duration, optional no-overlap-per-voice.
- [x] Add a transform identity validator:
      confirms the follower is actually the requested transform of the leader.
- [x] Add aggregate validators for multi-voice outputs:
      all pairs profile-safe, all pairs IC-safe when requested, and all voices individually valid.

### Acceptance criteria

- [x] A transformed line can fail with a specific reason category:
      pitch transform mismatch, rhythm invalid, vertical clash, IC clash, register failure, or
      unsupported ratio.
- [x] Validators work for both equal-speed and unequal-speed followers.
- [x] Existing invertible-counterpoint tests still pass unchanged.

---

## Phase 4: Canon integration

- [ ] Replace or wrap `FollowerSpec` with a richer transform plan without breaking existing tests.
- [x] Support exact canon as `Delay + Transpose`.
- [x] Support mirror canon as `Delay + Invert`.
- [x] Support crab canon as `Delay + Retrograde`.
- [x] Support augmentation canon as `Delay + TimeScale(factor, 1)`.
- [x] Support diminution canon as `Delay + TimeScale(1, factor)`.
- [x] Support retrograde-inversion canon as `Delay + Retrograde + Invert`.
- [x] Add per-follower transposition on top of all transform types.
- [ ] Add candidate leader-walk gates for transforms that can be checked locally.
- [x] Add post-generation validators for transforms that require full-sequence context.
- [x] Add config IDs for curated canon types:
      exact, mirror, crab, augmented, diminished, mirror-augmented, crab-inverted.

### Acceptance criteria

- [x] Existing transposition and inversion canon behavior remains stable.
- [x] Each new canon type has at least one deterministic smoke test.
- [ ] Each new canon type can render to `NoteEvent` and MIDI demo output.

---

## Phase 5: Standalone harmonized composition integration

- [x] Add a `TransformCompositionPlan` that can generate a primary line plus transformed companion
      lines without requiring canonic entry structure.
- [x] Add material roles:
      subject, countersubject, bass, inner accompaniment, hocket composite, isorhythmic layer.
- [x] Add a harmonizer entry point:
      generate transformed lines first, then validate/harmonize vertical overlaps.
- [ ] Add integration with existing counterpoint generation:
      use transformed subject as cantus,
      generate one or more legal lower/upper voices against it.
- [x] Add integration with aesthetic profiles:
      select profile first, then transform/harmonize under that vertical grammar.
- [ ] Add integration with `harmonic_walk` or known harmonic skeletons where useful:
      transformed line supplies melody,
      harmonic plan supplies chord/vertical context.
- [x] Add a fallback repair pass:
      octave displacement, local transposition, rest insertion, or candidate replacement.
- [x] Add output modes:
      canon texture,
      subject plus countersubject,
      hocket texture,
      isorhythmic motet texture,
      transformed melody plus harmonized accompaniment.

### Acceptance criteria

- [ ] At least three non-canon compositions can be generated from transformed material:
      hocket piece, isorhythmic piece, and transformed subject with harmonized accompaniment.
- [x] Standalone composition outputs pass the same pairwise vertical validators as canons.
- [x] The API makes it clear whether the result is a canon or a freer harmonized composition.

---

## Phase 6: Voice exchange

- [x] Define local voice exchange in degree/time terms:
      two voices swap pitch material, register positions, or named motives at selected times.
- [x] Implement exchange by pitch only.
- [x] Implement exchange by full event material.
- [ ] Implement exchange by register/octave placement for invertible-counterpoint use.
- [x] Add validators that the exchanged texture remains profile-safe.
- [ ] Add an IC-specific validator:
      voice exchange must preserve octave-invertible safety if requested.
- [x] Add tests for two-voice exchange and three-voice partial exchange.

### Acceptance criteria

- [x] Voice exchange works as a local version of invertible counterpoint.
- [x] A generated phrase can exchange soprano/bass material and still validate.

---

## Phase 7: Hocket

- [x] Formalize hocket as partition reusability:
      one logical line distributed across two or more physical voices.
- [x] Implement mask-based hocket:
      bit or periodic pattern selects which voice owns each event.
- [ ] Implement tiling-backed hocket using existing rhythmic tiling outputs where possible.
- [x] Add composite reconstruction validator:
      merging the parts recovers the original line order and timing.
- [x] Add no-collision validator for hocket parts.
- [ ] Add optional harmonized hocket mode:
      non-active voices can sustain legal pedal or harmonic support.

### Acceptance criteria

- [x] Hocket output can be rendered as separate voices.
- [x] The composite line is provably reconstructible.
- [ ] Hocket can be used both as a rhythmic canon layer and as a standalone texture.

---

## Phase 8: Isorhythm

- [x] Formalize talea as a duration/onset cycle.
- [x] Formalize color as a pitch/degree cycle.
- [x] Implement unequal cycle pairing with LCM period.
- [ ] Add optional color transforms per cycle:
      transpose, invert, retrograde, rotate.
- [ ] Add optional talea transforms per cycle:
      augment, diminish, rotate.
- [ ] Add vertical validation for multi-voice isorhythm.
- [ ] Add harmonized isorhythm mode:
      generate a color/talea voice, then harmonize structural onsets.

### Acceptance criteria

- [x] Different color/talea lengths produce the expected LCM-length recombination.
- [x] Isorhythm can generate a standalone composition without canon entry logic.
- [ ] Isorhythm can also be embedded as one voice inside a canon/harmony plan.

---

## Phase 9: Search, repair, and generation policies

- [x] Add deterministic candidate selection for transformed followers:
      seed selects transform family, factor, lag, transposition, pivot, and role.
- [x] Add bounded retry policy for full-sequence transforms like crab canon.
- [x] Add local repair strategies:
      octave shift, transpose follower, adjust entry lag, choose alternate pivot.
- [x] Add strict mode:
      fail if no valid transform exists.
- [x] Add permissive mode:
      repair or fall back to exact canon/harmonization.
- [x] Add descriptor labels for generated outputs:
      `Mirror Canon`, `Crab Canon`, `Augmented Canon`, `Isorhythmic Hocket`, etc.

### Acceptance criteria

- [x] Generation never loops unboundedly.
- [x] Failure paths are deterministic and testable.
- [x] Every generated piece reports which transform family it used.

---

## Phase 10: Tests

- [x] Add algebraic law tests:
      retrograde twice is identity,
      inversion twice is identity,
      augmentation then diminution round-trips when divisible,
      hocket merge reconstructs original,
      isorhythm period equals LCM.
- [x] Add transform identity tests:
      mirror follower is exact inversion,
      crab follower is exact retrograde,
      augmented follower preserves pitch order and scales time.
- [x] Add validator tests:
      known-safe examples pass,
      known dissonant overlaps fail,
      IC-unsafe fifth examples fail when IC is required.
- [x] Add canon integration tests for every new follower type.
- [x] Add standalone harmonized composition tests for:
      transformed subject plus counterpoint,
      hocket piece,
      isorhythmic piece,
      voice exchange phrase.
- [x] Add deterministic seed tests for representative transform families.
- [ ] Add regression tests for existing `canon_inversion`, `invertible_counterpoint`,
      `transform`, and `counterpoint` modules.

### Acceptance criteria

- [x] `scarb test` passes.
- [x] New tests include both identity correctness and musical legality.
- [x] At least one negative test exists per transform family.

---

## Phase 11: Demos and fixtures

- [ ] Add MIDI demo generator for mirror canon.
- [ ] Add MIDI demo generator for crab canon.
- [ ] Add MIDI demo generator for augmentation canon.
- [ ] Add MIDI demo generator for diminution canon.
- [ ] Add MIDI demo generator for voice exchange.
- [ ] Add MIDI demo generator for hocket.
- [ ] Add MIDI demo generator for isorhythm.
- [ ] Add MIDI demo generator for transformed subject plus harmonized accompaniment.
- [ ] Store representative Cairo parser outputs under `demos/` using the existing naming style.
- [ ] Add fixture JSON for transform identity and validation results.

### Acceptance criteria

- [ ] Every transform family has a playable demo.
- [ ] Demos include at least one canon and one standalone harmonized composition.
- [ ] Fixture outputs are deterministic for fixed seeds.

---

## Phase 12: Documentation and composition index

- [x] Add a formal spec:
      `docs/transformational_counterpoint_spec.md`.
- [ ] Add a shorter vault-facing note explaining the musical meaning:
      transformation as reusability under pitch, time, direction, and voice placement.
- [ ] Update the composition feature comparison summary.
- [ ] Update `Composition/Transformation Library.md` if needed.
- [ ] Update `Composition/Melodic Canon.md` with new follower types.
- [ ] Update `Composition/Counterpoint.md` with standalone harmonized composition use.
- [ ] Document when a transform is best used as canon versus freer composition material.

### Acceptance criteria

- [ ] A reader can understand both the math and the musical use cases.
- [ ] Public docs distinguish exact canon, mirror canon, crab canon, hocket, and isorhythm.
- [ ] The docs include implementation status and demo commands.

---

## Recommended implementation order

- [x] Lock the shared representation and transform enum.
- [x] Implement pure transforms first.
- [x] Implement overlap/vertical validators second.
- [x] Integrate exact, mirror, crab, augmentation, and diminution canons.
- [x] Add standalone composition plan and harmonizer integration.
- [x] Add voice exchange, hocket, and isorhythm.
- [ ] Add tests, demos, fixtures, and docs.

---

## Deliverables checklist

- [x] `src/composition/transformational_counterpoint.cairo`
- [x] Tests for transform laws and validators.
- [ ] Canon demos for mirror, crab, augmentation, and diminution.
- [ ] Standalone demos for hocket, isorhythm, voice exchange, and harmonized transformed subject.
- [x] `docs/transformational_counterpoint_spec.md`
- [ ] Updated composition docs and feature summary.

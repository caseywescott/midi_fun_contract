# Timeline family admission decision (v1)

Decision date: generated offline by `scripts/analyze_rhythm_catalog.py`.

## Son/Rumba/Gahu interval family

**Admitted for bounded generation in v1.** Six canonical cyclic variants and 96
oriented candidates are implemented in Cairo with deterministic seed selection.

### Canonical variants at rotation 0

| Variant | IOI | Metric | Symmetry | Distance² from Son |
|---------|-----|--------|----------|-------------------|
| 0 | `[2, 3, 3, 4, 4]` | 2 | none | 2 |
| 1 | `[2, 3, 4, 3, 4]` | 5 | none | 2 |
| 2 | `[2, 3, 4, 4, 3]` | 7 | weak | 4 |
| 3 | `[2, 4, 3, 3, 4]` | 4 | weak | 0 |
| 4 | `[2, 4, 3, 4, 3]` | 6 | none | 2 |
| 5 | `[2, 4, 4, 3, 3]` | 5 | none | 2 |

Listening review: use `demos/timeline_rhythm/reference_presets.mid` for named
presets and regenerate Son-family oriented candidates via catalogue fixtures.
Generated variants must remain labelled `clave-derived timeline` /
`interval-class rhythm`, never as traditional clave names.

## Shiko, Soukous, Bossa-Nova families

**Not admitted for permutation generation in v1.** Keep as exact reference presets
only until offline descriptor analysis and listening review justify expansion.

| Family | Reference IOI | Metric | Symmetry | Distance² from Son | Recommendation |
|--------|---------------|--------|----------|-------------------|----------------|
| Shiko | `[4, 2, 4, 2, 4]` | 2 | strong | 2 | Defer — reference preset only |
| Soukous | `[3, 3, 4, 1, 5]` | 6 | none | 2 | Defer — reference preset only |
| Bossa-Nova | `[3, 3, 4, 3, 3]` | 6 | strong | 2 | Defer — reference preset only |

## Rationale

- Shiko, Soukous, and Bossa-Nova use distinct interval multisets not covered by the
  v1 Son-family generator; admitting them requires separate bounded permutation tables
  and listening validation per spec Milestone 5.
- Descriptor spread shows Soukous and Bossa-Nova are metric/symmetry outliers relative
  to the Son/Rumba/Gahu family; premature admission risks mis-labelling generated
  variants as culturally named patterns.
- Revisit after M5 listening review notes are recorded and optional MIDI previews of
  each family's permutation catalogue are auditioned.

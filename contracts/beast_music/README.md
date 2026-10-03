# beast_music

The Beast Sound composer on its own: the part of the `koji` music library that Beasts V3 sound
actually uses, extracted into a standalone Cairo package with no dependencies.

| | `koji` (repo root) | `beast_music` |
|---|---|---|
| Modules | 84 | 14 |
| Lines | 36,649 | about 2,900 |

`contracts/beast_sound` (`BeastMidiProvider`, `BeastSoundComposer`) depends on this package instead
of `koji`.

## What is in it

| Module | Contents |
|---|---|
| `composition::beast_v3_sound` | Token ID decoding, live state, the v1 mapping, MIDI / BSN1 / BSI1 writers (whole file) |
| `composition::beast_trait_map` | Traits and live stats to composition parameters (whole file) |
| `composition::beast_score` | Theme, sections, form and its length; `note_events_valid` for tests |
| `composition::countersubject` | The invertible countersubject |
| `composition::melodic_canon` | Degree-to-key realization, `NoteEvent` |
| `composition::articulation` | Articulation plans |
| `composition::counterpoint`, `canon_rules`, `invertible_counterpoint`, `stretto` | The few interval and canon helpers the above call |
| `midi::output`, `midi::types` (`Modes` only), `lcg`, `rng` | Felt packing, the mode enum, the seeded random source |

Everything else in `koji` (Barry Harris, harmonic walk and jazz harmony, ornamentation v2,
motif/form, timeline and tiling rhythm, canon variants, the general MIDI toolkit, engine v2) is
left out. `koji` itself is unchanged.

## How it was extracted, and how it was checked

The modules and functions kept are the ones the compiled contracts use: their Sierra function list
(built with `sierra-replace-ids`) plus a static call graph for helpers the compiler inlines. Unused
functions, types and imports were then removed until the package built with no warnings.

- **Same code onchain:** `BeastMidiProvider` and `BeastSoundComposer` built against `beast_music`
  have CASM bytecode identical to the `koji` builds (23,154 and 26,608 felts). The ABI is identical
  apart from type paths (`beast_music::` instead of `koji::`), which changes the class hash but no
  behavior.
- **Same music:** the Beast v3 tests run here (`src/tests.cairo`, 14 tests), and the parity fixture
  prints exactly the lines `koji` does, which `scripts/beast_v3_parity.mjs` matches against the JS
  engine (65 of 65 checks):
  ```bash
  scarb test -- --include-ignored --filter beast_v3_parity_fixture | grep PARITY > /tmp/parity.txt
  node ../../scripts/beast_v3_parity.mjs /tmp/parity.txt
  ```
- `contracts/beast_sound`'s 16 tests pass on it unchanged.

## Keeping it in sync

Composer changes now land here. While `koji` keeps its own copy (its tests, demos and the other
engines use it), a change to the Beast path has to be made in both until `koji`'s copy is retired.
The parity fixture catches a mismatch: both must print the same `PARITY` lines.

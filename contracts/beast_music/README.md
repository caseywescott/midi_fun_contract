# beast_music

The Beast Sound composer on its own: the part of the `koji` music library that Beasts V3 sound
actually uses, extracted into a standalone Cairo package. Its one dependency is `contracts/midi`
(Standard MIDI File writing and felt packing).

| | `koji` (repo root) | `beast_music` |
|---|---|---|
| Modules | 84 | 14 |
| Lines | 36,649 | about 2,900 |

`contracts/beast_sound` (`BeastMidiProvider`, `BeastSoundComposer`) depends on this package instead
of `koji`.

## What is in it

| Module | Contents |
|---|---|
| `composition::beast_v3_sound` | Token ID decoding, live state, the v1 mapping, the bare score as MIDI (on `midi::smf`), BSN1 / BSI1 writers |
| `composition::beast_v11` | Composer v1.1 (same mode, even phrases, history): cadence, rhythm cells, voice-checked followers, episodes, diatonic key plan, even sections, trajectory; what `BeastMidiProvider` plays |
| `composition::full_midi` | The self-contained MIDI for onchain-tinysynth: programs, pan, drum track (on `midi::smf`) |
| `composition::beast_trait_map` | Traits and live stats to composition parameters (whole file) |
| `composition::beast_score` | Theme, sections, form and its length; `note_events_valid` for tests |
| `composition::countersubject` | The invertible countersubject |
| `composition::melodic_canon` | Degree-to-key realization, `NoteEvent` |
| `composition::articulation` | Articulation plans |
| `composition::counterpoint`, `canon_rules`, `invertible_counterpoint`, `stretto` | The few interval and canon helpers the above call |
| `modes`, `lcg`, `rng` | The mode enum, the seeded random source |

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

`smf_golden` (ignored; `scarb test -- --include-ignored --filter smf_golden`) pins every byte both
SMF writers produce for 50 Beasts in two live states; it held unchanged when the writers moved onto
the `midi` package.

### Composer v1.1

`composition::beast_v11` is byte-identical to `createEngineV11(engine).render(beast, live, { keys:
'mode', even: true, traj: true })` (offchain/beast-sound/src/engine_v11.js, the options chosen on the
compare page). The parity fixture is 75 cases (every species; live states reaching every history
branch: stretto, inversion and sequence development, rising, falling and alternating episodes, all
three spacings, trills, countersubjects), compared on notes, section length and the self-contained
MIDI. A Cairo VM run keeps what it allocates until it ends, so it runs in 19 batches of 4, one at a
time, with a memory watchdog (about 5 GB peak for the heaviest batch):

```bash
sh ../../scripts/v11_parity_cairo.sh /tmp/v11.txt && node ../../scripts/v11_parity.mjs /tmp/v11.txt
```

Gas: composing is dominated by the voice checks (every follower, countersubject and episode note
against what sounds with it); notes are kept in chronological runs so each check binary-searches
instead of scanning the section. One `get_midi` for the heaviest Beast is about 1.0B L2 gas (v1:
0.44B), the named rank-1 Warlock about 0.58B, a genesis Warlock about 0.13B.

## Keeping it in sync

Composer changes now land here. While `koji` keeps its own copy (its tests, demos and the other
engines use it), a change to the Beast path has to be made in both until `koji`'s copy is retired.
The parity fixture catches a mismatch: both must print the same `PARITY` lines.

# beast_music

The Beast Sound composer as a standalone Cairo package. Its one dependency is `contracts/midi`
(Standard MIDI File writing and felt packing). `contracts/beast_sound` (`BeastMidiProvider`,
`BeastSoundComposer`) depends on it.

## What is in it

| Module | Contents |
|---|---|
| `composition::beast_v3_sound` | Token ID decoding, live state, the v1 mapping, the bare score as MIDI (on `midi::smf`), BSN1 / BSI1 writers |
| `composition::beast_v11` | Composer v1.1 (same mode, even phrases, history): cadence, rhythm cells, voice-checked followers, episodes, diatonic key plan, even sections, trajectory; what `BeastMidiProvider` plays |
| `composition::full_midi` | The self-contained MIDI for onchain-midi-player: programs, pan, drum track (on `midi::smf`) |
| `composition::beast_trait_map` | Traits and live stats to composition parameters (whole file) |
| `composition::beast_score` | Theme, sections, form and its length; `note_events_valid` for tests |
| `composition::countersubject` | The invertible countersubject |
| `composition::melodic_canon` | Degree-to-key realization, `NoteEvent` |
| `composition::articulation` | Articulation plans |
| `composition::counterpoint`, `canon_rules`, `invertible_counterpoint`, `stretto` | The few interval and canon helpers the above call |
| `modes`, `lcg`, `rng` | The mode enum, the seeded random source |

## What it holds, and how it is checked

The modules and functions here are the ones the compiled contracts use: their Sierra function list
(built with `sierra-replace-ids`) plus a static call graph for helpers the compiler inlines. Unused
functions, types and imports were removed until the package built with no warnings.

- **Tests:** the Beast v3 tests (`src/tests.cairo`), the trait map and the score
  (`src/trait_map_tests.cairo`, `src/score_tests.cairo`), the helpers they build on
  (`src/articulation_tests.cairo`, `contrapuntal_tests.cairo`, `canon_rules_tests.cairo`,
  `melodic_canon_tests.cairo`, `lcg_tests.cairo`, `rng_tests.cairo`), plus the track, Genesis and
  input-packing tests.
- **Same music as the JS engine:** the parity fixture prints `PARITY` lines that
  `scripts/beast_v3_parity.mjs` matches against `offchain/beast-sound` (65 of 65 checks):
  ```bash
  scarb test -- --include-ignored --filter beast_v3_parity_fixture | grep PARITY > /tmp/parity.txt
  node ../../scripts/beast_v3_parity.mjs /tmp/parity.txt
  ```

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
against what sounds with it). Placed notes sit on a 120-tick grid per voice (every onset and length
the checks see is a multiple of 120, asserted), with each voice's placed span, so a check reads only
the cells where other voices sound; the overlaps and the parallel-5ths "note before" are looked up
once per note, not per candidate; scale degrees are realized once per section into a table. None of
this changes a note (the 75-case parity is rerun after each change). One `get_midi` for the heaviest
Beast is about 0.76B L2 gas (v1: 0.44B; the first port: over 2B), the named rank-1 Warlock about
0.44B, a genesis Warlock about 0.1B.

## Keeping it in sync

Composer changes land here, and in the JS mirror in `offchain/beast-sound/src` (`engine.js`,
`engine_v11.js`, `full_midi.js`, `lab.js`) in the same change. The parity fixtures catch a
mismatch: the scripts in `scripts/` compare their output with the JS.

# Testing

The Cairo packages are one Scarb workspace (scarb 2.21.0). Their tests run on Starknet Foundry
(snforge 0.64.1, both pinned in `.tool-versions`): `scarb test` runs `snforge test` in each package
(the root `Scarb.toml`'s `[workspace.scripts]`). Each package has its own tests:

| Package | `scarb test -p …` covers |
|---|---|
| `midi` | SMF writing (VLQ examples, deltas, End of Track, running status, chunks) and both packers |
| `midi_contracts` | `ScaleMidiProvider` (behavior, pinned bytes, `get_sound`); `MidiSoundPage` (`token_uri` equal to the JS reference byte for byte, contract tests with real and mock providers) |
| `beast_composer` | The composer; the parity fixtures are `#[ignore]`d (below) |
| `beast_composer_inputs` | Canonical input codecs, version and range rejection, boolean canonicality, and Store support |
| `beast_contracts` | Existing `BeastMidiProvider`/composer tests; shared pure call interfaces declare no replacement runtime |

```bash
scarb test                      # all five, as CI runs them (one job per package)
scarb test -p beast_composer    # one package
scarb test -p beast_composer -- smf_golden --include-ignored   # tests whose name contains a filter, ignored ones included
scarb fmt --check               # CI checks formatting too
```

## Parity fixtures

The composer's parity fixtures compare Cairo with the JS engine (`offchain/beast-sound`). A Cairo VM
run keeps what it allocates until it ends, so they are `#[ignore]`d, need several GB per batch, and
run locally in batches through `scripts/*_parity_cairo.sh` and `scripts/*_parity.mjs`. See
`beasts/beast_composer/README.md`.

## Generated Cairo

Three files are written by scripts in `offchain/beast-sound/onchain` (run `npm install` in
`offchain/beast-sound` first). After a change to their sources, regenerate them and commit the
result; with unchanged sources, they reproduce the committed files byte for byte:

| File | Generator |
|---|---|
| `core/midi_contracts/src/page/page_data.cairo` | `node onchain/build.mjs` (needs `npx esbuild`) |
| `core/midi_contracts/src/page/tests.cairo` | `node onchain/golden.mjs` |
| `beasts/beast_contracts/src/synth_settings.cairo` | `node onchain/tinychip/synth_settings.mjs --cairo` |

## Catalogue validation and production class sizes

`scripts/check_catalogue.mjs` validates the 75 source rows before packing: numeric/enumerated
metadata, canonical species order and family programs, degree/rhythm bounds, and the bit widths
used by the Cairo reader. In particular, `finalNotes` must be 4–16 so the final cadence cannot
underflow. Valid source reproduces the committed Cairo table byte for byte. Regenerate with
`node scripts/check_catalogue.mjs`, or verify with `--check`.

```sh
node --test offchain/beast-sound/test/catalogue-generation.test.mjs offchain/beast-sound/test/production-size.test.mjs
node scripts/check_catalogue.mjs --check
scarb --profile dev build -p beast_contracts
node scripts/check_production_size.mjs target/dev
```

The existing `beast_contracts` CI job runs these checks. The size gate reads all four named
production `.compiled_contract_class.json` artifacts, including `BeastPureComposer` and
`BeastPureGenerator`; snforge test artifacts do not satisfy it. Missing/malformed production
artifacts or bytecode above 81,920 felts fail the gate. Exactly 81,920 is accepted; this adds no
extra headroom policy and does not change runtime code or compiler settings.

## Gas benchmark

`bench/` (its own Scarb workspace, snforge 0.64.1) runs every production entry point it measures
from the classes `scarb build` makes, and checks each call's whole output: the Genesis Tracks
against the JS engine (`genesisMidi`), everything else against the outputs frozen at the baseline.
A change that alters any output fails the bench instead of reporting a saving. Commands and the
meaning of each number are in `bench/README.md`; `bench/snapshots/baseline-*.json` are the
committed captures to compare against.

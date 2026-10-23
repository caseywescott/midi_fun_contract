# Testing

The Cairo packages are one Scarb workspace (scarb 2.21.0). Their tests run on Starknet Foundry
(snforge 0.64.1, both pinned in `.tool-versions`): `scarb test` runs `snforge test` in each package
(the root `Scarb.toml`'s `[workspace.scripts]`). Each package has its own tests:

| Package | `scarb test -p …` covers |
|---|---|
| `midi` | SMF writing (VLQ examples, deltas, End of Track, running status, chunks) and both packers |
| `midi_contracts` | `ScaleMidiProvider` (behavior, pinned bytes, `get_sound`); `MidiSoundPage` (`token_uri` equal to the JS reference byte for byte, contract tests with real and mock providers) |
| `beast_composer` | The composer; the parity fixtures are `#[ignore]`d (below) |
| `beast_contracts` | `BeastMidiProvider` on a mock Beasts V3 NFT: `get_track_sound` for each of the three tracks and blocks, the rollout and token-owner entry points, SRC5, rejections, `get_sound`, onchain-midi-player's `validate` on the settings |

```bash
scarb test                      # all four, as CI runs them (one job per package)
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

## Gas benchmark

`bench/` (its own Scarb workspace, snforge 0.64.1) runs every production entry point it measures
from the classes `scarb build` makes, and checks each call's whole output: the Genesis Tracks
against the JS engine (`genesisMidi`), everything else against the outputs frozen at the baseline.
A change that alters any output fails the bench instead of reporting a saving. Commands and the
meaning of each number are in `bench/README.md`; `bench/snapshots/baseline-*.json` are the
committed captures to compare against.

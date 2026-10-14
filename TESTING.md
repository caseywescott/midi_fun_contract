# Testing

The Cairo packages are one Scarb workspace (scarb 2.20.1). Each package has its own tests:

| Package | `scarb test -p …` covers |
|---|---|
| `midi` | SMF writing (VLQ examples, deltas, End of Track, running status, chunks) and both packers |
| `midi_contracts` | `ScaleMidiProvider` (behavior, pinned bytes, `get_sound`); `MidiSoundPage` (`token_uri` equal to the JS reference byte for byte, contract tests with real and mock providers) |
| `beast_composer` | The composer; the parity fixtures are `#[ignore]`d (below) |
| `beast_contracts` | `BeastMidiProvider` on a mock NFT and Death Mountain: sources, rejections, `get_sound`, onchain-midi-player's `validate` on the settings |

```bash
scarb test                      # all four, as CI runs them (one job per package)
scarb test -p beast_composer    # one package
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

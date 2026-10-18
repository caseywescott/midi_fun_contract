# midi_fun_contract

Onchain music on Starknet: a core MIDI system, and Beast Sound, which composes music for each
Beasts V3 NFT and is the first consumer of that system.

## Layout

The Cairo code is one Scarb workspace (the root `Scarb.toml`, scarb 2.21.0 as pinned in
`.tool-versions`). Packages are grouped by system; a package named `*_contracts` declares Starknet
contracts, and the others are libraries (`[lib]`, no contracts).

| Package | Path | Kind | What it is |
|---|---|---|---|
| `midi` | `core/midi` | library | The core MIDI types (`midi::types`) and interfaces (`midi::interfaces`: `IMidiProvider`, `ISynthSettingsProvider`, `ISoundProvider`, `IMidiSoundPage`), Standard MIDI File writing (`midi::smf`) and packing (`midi::pack`) |
| `midi_contracts` | `core/midi_contracts` | contracts | `MidiSoundPage` (an NFT's `token_uri` with onchain sound) and an example provider |
| `beast_composer` | `beasts/beast_composer` | library | The Beast Sound composer: a Beasts V3 token and its live state to MIDI |
| `beast_contracts` | `beasts/beast_contracts` | contracts | `BeastMidiProvider`, the composer as an `IMidiProvider`, and the `BeastSoundComposer` benchmark |

```
                 midi  (core/midi)
          ┌───────┴──────────┐
          ▼                  ▼
  midi_contracts       beast_composer
  (core)               (beasts)
                             │
                             ▼
                      beast_contracts ──► midi
```

Nothing in `core/` depends on `beasts/`. The Beast packages reach `midi` through the workspace
dependency (`midi.workspace = true`), so `beasts/` can move to its own repository unchanged: see
`beasts/README.md`.

Each package has a README with its API and details.

## Build and test

Needs scarb 2.21.0 and Starknet Foundry 0.64.1 (`snforge`), both pinned in `.tool-versions` (with
asdf: `asdf install`). The tests run on snforge: `scarb test` runs `snforge test` in each package
through the root `Scarb.toml`'s `[workspace.scripts]`. From the repository root:

```bash
scarb build                     # every package; artifacts in target/dev/<package>_<Contract>.*
scarb test                      # every package's tests (snforge)
scarb test -p beast_contracts   # one package
scarb fmt --check
```

`TESTING.md` covers the `#[ignore]`d parity fixtures and the generated Cairo files.

### Gas

`bench/` measures the per-call L2 gas of the four contract classes over 286 fixed cases (every
species' Genesis Track, the sound page, the composer views, library probes), each checked against
the expected output, plus their CASM and Sierra sizes:

```bash
npm install --prefix offchain/beast-sound   # once: the expected table is checked with the JS engine
python3 bench/scripts/gas_bench.py run --out bench/snapshots/candidate.json
python3 bench/scripts/gas_bench.py compare bench/snapshots/baseline-25be776.json \
    bench/snapshots/candidate.json --markdown
```

It is its own Scarb workspace (snforge 0.64.1, `bench/.tool-versions`); see `bench/README.md`.

## Outside the workspace

- `offchain/beast-sound/`: the JS Beast Sound engine (`beast-sound`), the TinySynth sound page
  sources and the generators of `core/midi_contracts/src/page/page_data.cairo`, its golden tests and
  `beasts/beast_contracts/src/synth_settings.cairo`.
- `scripts/*parity*`: compare the Cairo composer with the JS engine.
- `bench/`: the gas benchmark (its own Scarb workspace, above).
- `docs/beasts/`: the Beast Sound composition guide.

The `koji` music library, its tooling and research, Beast Engine v2 and the old browser simulator
moved to their own repository, [koji-cairo](https://github.com/caseywescott/koji-cairo), with their
history; the `archive/koji` tag here marks the last commit that has them.

## License

This project is licensed under the MIT License.

# midi_fun_contract

Onchain music on Starknet: a core MIDI system, and Beast Sound, which composes music for each
Beasts V3 NFT and is the first consumer of that system.

## Layout

The Cairo code is one Scarb workspace (the root `Scarb.toml`, scarb 2.20.1 as pinned in
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

From the repository root:

```bash
scarb build                     # every package; artifacts in target/dev/<package>_<Contract>.*
scarb test                      # every package's tests
scarb test -p beast_contracts   # one package
scarb fmt --check
```

`TESTING.md` covers the `#[ignore]`d parity fixtures and the generated Cairo files.

## Outside the workspace

- `offchain/beast-sound/`: the JS Beast Sound engine (`@koji/beast-sound`), the TinySynth sound page
  sources and the generators of `core/midi_contracts/src/page/page_data.cairo`, its golden tests and
  `beasts/beast_contracts/src/synth_settings.cairo`.
- `web/beast_sound/`: the browser simulator and instrument patches.
- `scripts/*parity*`: compare the Cairo composer with the JS engine.
- `docs/beasts/`: the Beast Sound composition guide.

The `koji` Cairo library that used to live at the root (`src/`) was removed; the `koji-final` tag
marks its last commit. Its tooling (`python/`, `typescript/`, `demos/`, `pyproject.toml`,
`poetry.lock`, the `Makefile`, `docs/composing.md`, `docs/motif_files/`) still references it and is
due for its own cleanup, as are parts of `fixtures/`, `data/`, `example/` and `scripts/` (check what
uses each before removing it).

## License

This project is licensed under the MIT License.

# beasts

Beast Sound in Cairo: music for each Beasts V3 NFT, built on the core MIDI system (`core/midi`).

| Package | Kind | What it is |
|---|---|---|
| `beast_composer` | library | The composer: a Beasts V3 token and its live state to a Standard MIDI File |
| `beast_contracts` | contracts | `BeastMidiProvider` (`midi::interfaces::IMidiProvider`, `ISynthSettingsProvider`, `ISoundProvider`) and the `BeastSoundComposer` benchmark |

Both depend on `midi` only through the workspace (`midi.workspace = true`), and on nothing else
outside this directory; `beast_contracts` reaches `beast_composer` by a relative path.

## Moving to another repository

Copy `beasts/` unchanged and give it a workspace root that points `midi` at this repository:

```toml
# Scarb.toml at the new repository's root
[workspace]
members = ["beasts/beast_composer", "beasts/beast_contracts"]

[workspace.package]
version = "0.1.0"
edition = "2025_12"

[workspace.dependencies]
midi = { git = "https://github.com/caseywescott/midi_fun_contract", rev = "<commit>" }
openzeppelin_access = "4.0.1"
openzeppelin_upgrades = "4.0.1"
openzeppelin_interfaces = "2.2.0"
starknet = "2.21.0"
snforge_std = "=0.64.1"
assert_macros = "2.21.0"

[workspace.scripts]
test = "snforge test --max-n-steps 4294967295 --max-threads 4"
```

with `scarb 2.21.0` and `starknet-foundry 0.64.1` in its `.tool-versions`. Both packages build and
pass their tests that way.

Beast tooling that lives outside this directory and would move with it: `offchain/beast-sound/`
(the JS engine and the generator of `beast_contracts/src/synth_settings.cairo`; it also generates
the core sound page's Cairo, which stays), `scripts/*parity*` and
`docs/beasts/`.

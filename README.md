# midi_fun_contract

Onchain music on Starknet: Standard MIDI Files written in Cairo, a MIDI provider interface that
turns an NFT token into music, and Beast Sound, which composes every Loot Survivor Beast's theme
from its traits and history. The Cairo composer and its JavaScript mirror produce the same notes,
hashes and MIDI bytes.

## Layout

- `contracts/midi`: Standard MIDI File writing and felt/ByteArray packing (library, no dependencies).
- `contracts/midi_provider`: `IMidiProvider`, the interface that turns a token into MIDI, and an
  example provider.
- `contracts/beast_music`: the Beast Sound composer (library).
- `contracts/beast_sound`: `BeastMidiProvider` (production) and `BeastSoundComposer` (benchmark
  views), the composer as contracts.
- `offchain/beast-sound`: the composer in JavaScript, chain readers, CLI and HTTP endpoint;
  `onchain/` holds the TinySynth sound page for `token_uri`, with its Cairo package in
  `onchain/cairo`.
- `web/beast_sound`: the Beast Sound simulator, a single-file page.
- `docs/beasts`: how to change the music.
- `scripts`: Cairo-to-JS parity scripts for the composer, and `tinysynth_e2e`.

## Build and test

Each Cairo package builds on its own with scarb 2.20.1 (`contracts/.tool-versions`):

```bash
(cd contracts/midi && scarb build && scarb test)
(cd contracts/midi_provider && scarb build && scarb test)
(cd contracts/beast_music && scarb build && scarb test)
(cd contracts/beast_sound && scarb build && scarb test)
(cd offchain/beast-sound/onchain/cairo && scarb build && scarb test)
```

CI also runs `scarb fmt --check` in each. The parity fixtures are `#[ignore]`d there because they
need several GB; `contracts/beast_music/README.md` shows how to run them.

The offchain package (Node 20 or later):

```bash
(cd offchain/beast-sound && npm install && npm test)
```

Builds on Casey Wescott's earlier [MusicTools-StarkNet](https://github.com/caseywescott/MusicTools-StarkNet).

## License

This project is licensed under the MIT License - see the LICENSE file for details.

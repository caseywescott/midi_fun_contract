# Integrating the generic MIDI page into Beasts

`beasts_nft-sound.patch` applies to [Provable-Games/beasts at ae3fa8d](https://github.com/Provable-Games/beasts/tree/ae3fa8d0efdb8de62144abcd26984d34e90aab5b), the 116-bit V3 collection. It adds an owner-set `sound_page` pointer, where zero retains the existing sound-disabled metadata. When enabled, metadata/artwork are passed to `IMidiPage.token_uri(members, svg_b64, get_contract_address(), token_id)`. No music state or Summit data is passed by the NFT.

```bash
# Use an isolated checkout at the exact baseline:
git apply --check beasts_nft-sound.patch
git apply beasts_nft-sound.patch
scarb fmt --check
snforge test --max-n-steps 4294967295
```

The exported patch contains only `interfaces.cairo`, `lib.cairo`, `metadata_generator.cairo` and `sound_page_tests.cairo`. It adds neither a composer dependency nor the temporary end-to-end test module. It was clean-applied and tested with the NFT's own Scarb 2.18.0 / Foundry 0.60.0 toolchain: 74 tests passed. The provider/page use Scarb 2.11.4 and are separate classes; no shared Cairo package version is forced onto the NFT.

## End-to-end harness

`sound_e2e_tests.cairo` is separate from the patch. It instantiates the real NFT and all four real PNG/GIF art classes, our real `MidiPage` and `BeastMidiProvider`, and a Death Mountain ABI mock. State remains mock-controlled; this is not evidence of a configured live production source. The heaviest case explicitly sets 200 kills/64 collects and exercises 3,716-byte MIDI.

The runner builds the MIDI artifacts separately, adds the test module to the **isolated checkout**, and injects those artifacts into Foundry's generated test manifest after each build. The wrapper and logs remain in `/tmp`; it changes no production dependencies or class pointers.

```bash
# Run from offchain/beast-sound:
SCARB_MIDI=/path/to/scarb-2.11.4 \
SCARB_NFT=/path/to/scarb-2.18.0 \
SNFORGE_NFT=/path/to/snforge-0.60.0 \
node onchain/integration/run-e2e.mjs /path/to/isolated-patched-beasts /tmp/nft-flow.log

node onchain/verify-flow.mjs /tmp/midi-flow.log /tmp/nft-flow.log
node onchain/measure.mjs /tmp/midi-flow.log /tmp/nft-flow.log
```

Eight end-to-end tests passed. Independently decoded output retains all name/description/attributes/image fields exactly for plain and animated shiny Beasts. Its embedded raw MIDI matches the independent JS composer for equivalent authoritative mock state. Exact emitted data URLs also pass offline Chromium playback. The ownable setter remains restricted; restoring the pointer to zero retains sound-disabled behavior.

## Activation prerequisites

Declare/deploy decisions and `set_sound_page_address` are outside this implementation. Before considering them, verify a nonzero Death Mountain configuration against the 116-bit source/namespace, configure an RPC read budget that actually accepts the measured full path, and validate the intended marketplace/browser. The documented Sepolia collection currently reports source 0. Newer 180-bit/community collections require their own verified provider policy. See [the full resource and source report](../README.md); class-size success does not establish read/deployment readiness.

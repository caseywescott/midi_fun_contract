# Generic onchain MIDI pages

`MidiPage` asks an `IMidiProvider` for raw Standard MIDI File bytes using only the NFT collection address and token ID. It embeds those bytes and the NFT's existing artwork in an offline TinySynth player. The browser knows no Beast traits or state and makes no music requests. Play requires a gesture; Stop resets playback, Restart starts at zero, and Loop repeats the score.

The implementation is tested and ready for code review. **It is not ready to activate on a production NFT:** the documented Sepolia 116-bit collection has a zero Death Mountain source, and measured read costs exceed common default RPC limits. No contracts or live pointers were deployed or changed.

## Contracts and state policy

```cairo
IMidiProvider.get_midi(token_address: ContractAddress, token_id: u256) -> ByteArray
IMidiPage.token_uri(members: ByteArray, svg_b64: ByteArray,
                   token_address: ContractAddress, token_id: u256) -> ByteArray
```

`token_address` is the NFT address. `members` contains trusted JSON members without braces/image, and `svg_b64` is canonical Base64 of the SVG. These presentation inputs do not authorize or supply musical state.

- Deploy `BeastMidiProvider(collection, death_mountain)` with immutable, verified addresses. Each read checks `owner_of`, checks that the collection still reports the configured source, then reads kills, rank, species count and Death Mountain collect count. Missing contracts, missing getters, zero configuration or address drift fail explicitly.
- The provider supports the **116-bit V3 codec** at Beasts commit [`ae3fa8d`](https://github.com/Provable-Games/beasts/tree/ae3fa8d0efdb8de62144abcd26984d34e90aab5b) and original species **1–75**. Later 180-bit IDs and community species fail explicitly. Community stats caches do not establish a verified Death Mountain defeat source; a separate provider/version must define that policy.
- The pinned NFT's direct live getters pass its Death Mountain contract address as the `dungeon` argument. The provider mirrors that namespace. Beast Systems at [`c0aae755`](https://github.com/Provable-Games/death-mountain/tree/c0aae7553797c0a2f12551bfa324a40be49c8a54) has `_get_correct_dungeon`/`_get_correct_entity_stats` shims for this convention. Verify the actual deployed source class and its shim before using it; `get_dungeon_address()` is not interchangeable with this key.
- Scars are `max(get_collectable_count(source_address, entity_hash) - 1, 0)`, excluding the initial collection/mint. A successful zero count is legitimate zero history. A failed source is never zero history. `entity_hash` is Poseidon of species ID, prefix and suffix.
- Summit is retired. The pure historical composer retains its `summit_held_seconds` field for compatibility; this provider deliberately sets it to **0** and makes no Summit calls. This is the new provider's versioned policy.
- The page/provider never call the NFT's `token_uri`. All live reads execute within the same Starknet call snapshot.

`FixedMidiProvider` in `contracts/midi_integration/src/lib.cairo` demonstrates reuse for a non-Beast collection through the same ABI. The existing `BeastSoundComposer` remains a separate benchmark/compatibility contract; the page uses `BeastMidiProvider`.

## Playback and dependency pin

TinySynth is vendored at commit `3d75aee4b3f43cbd932265e7d60201fd5b770397`. Its untouched minified upstream file is 43,217 bytes, SHA-256 `a381bcc794f476b7e17fefb32d1e18ae053ee33392857118d3101c19eff657ec`. The exact Apache-2.0 license, upstream source, provenance and patch notice are in `vendor/`.

The build removes only the MIDI tempo parser's integer BPM floor. Fractional BPM preserves microseconds-per-quarter timing. MIDI note times, channels, velocities and articulation remain unchanged. There are no added drums or accompaniment: absent SMF program changes, TinySynth uses General MIDI program 0 (acoustic grand piano). Historical chip-synth timbre is intentionally replaced by TinySynth's piano.

Restart, Play after Stop, and Play after EOF reload the cached SMF, resetting programs, controllers and tempo. Repeated Play during playback is idempotent. TinySynth's automatic loop retains late program/controller/tempo state: arbitrary SMFs should initialize those at tick 0 for consistent loop repeats. The Beast scores and short non-Beast loop fixture meet that condition.

Chromium 151 offline tests navigate the actual data URLs from the real NFT contract outputs and a non-Beast provider. Nine cases pass, including nonzero audio RMS, exact fractional tempo/tick duration, artwork, repeated Play, Restart, Stop during asynchronous resume, a loop wrap, EOF status, and reset of delayed program/controller/tempo changes. Other browsers/marketplace WebViews and their data-URL limits remain to be checked before activation. Fixtures here reach 3,716 MIDI bytes and 191,249 URI bytes.

## Encoding

The fixed player is encoded twice at build time:

```text
stored = base64('"animation_url":"data:text/html;base64,' + base64(fixed_html))
```

Only MIDI and presentation content are encoded during the view. MIDI and SVG Base64 live inside closed inert text blocks; raw SVG is displayed as an image. The fixed HTML, MIDI opening segment and JSON prefixes end at compatible 3-byte/9-byte boundaries. Artwork splits at **279 bytes** (9 Cairo words × 31 bytes), so its first Base64 fragment can be reused in both the image and HTML encoding. Its remainder stays in the final encoded fragments, preserving `=` padding and closing tags. See `page.js` for the independent reference.

Cairo/JS tests cover MIDI lengths 0–94, RFC4648 vectors, binary bytes, metadata and artwork identity, and artwork Base64 lengths 276, 280, 556, 560, 836 and 840. Named/genesis, threshold, rarity-flag and heaviest-score MIDI snapshots match the existing composer byte for byte.

## Reproduce

Use Node 20+, Scarb **2.11.4** and Foundry **0.44.0** for the MIDI projects. `SCARB` can name an absolute formatter/compiler path; the generators format their Cairo outputs for reproducibility.

```bash
cd offchain/beast-sound
npm install --ignore-scripts
node onchain/fixtures.mjs
node onchain/build.mjs
node onchain/golden.mjs
npm test
cd onchain/cairo
scarb build
scarb test
cd ../../../../contracts/midi_integration
snforge test --max-n-steps 4294967295 --detailed-resources > /tmp/midi-flow.log
```

The actual NFT integration uses its own pinned Scarb **2.18.0** / Foundry **0.60.0**, and loads the separately built MIDI classes. See [integration/README.md](integration/README.md) for the clean patch and reproducible harness.

```bash
# From offchain/beast-sound; after the real NFT harness produces /tmp/nft-flow.log:
node onchain/verify-flow.mjs /tmp/midi-flow.log /tmp/nft-flow.log
node onchain/measure.mjs /tmp/midi-flow.log /tmp/nft-flow.log
# Install Playwright and Chromium separately, or point at an existing local runtime:
PLAYWRIGHT_MODULE=/path/to/playwright CHROMIUM_PATH=/path/to/chromium node onchain/browser-test.mjs
node onchain/verify-state-sources.mjs <rpc> <116-bit-collection> <token-id>
```

`verify-state-sources.mjs` performs read-only, block-pinned reads, preserves u64 values as strings, records class hashes when configured, and exits nonzero when the source is unavailable. The documented Sepolia collection `0x01dac77837c6751777d917051a6e405967c5c75f46df5ab7c635e52819634bfd` returned source `0x0` on the recorded readiness check. Therefore there is no measured live provider/page RPC latency or verified active production configuration.

## Measured resources and release prerequisites

Scarb 2.11.4 artifacts:

| Class | CASM felts | Sierra felts | Sierra JSON bytes without debug |
|---|---:|---:|---:|
| BeastMidiProvider | 23,605 | 9,995 | 505,368 |
| MidiPage | 16,612 | 14,026 | 720,399 |

Both CASM classes are below 81,920 felts. The prior player baseline on the same compiler was 13,143 CASM felts / 8,661 Sierra felts / 432,212 JSON bytes. New player JavaScript is 45,559 bytes, fixed HTML is 46,539 bytes, and stored text is 82,788 bytes (2,673 serialized felts).

The **actual patched NFT and real PNG/GIF art providers**, with ABI-enforcing mocked Death Mountain state, yielded these Foundry 0.60 estimates after subtracting matching setup:

| Path | L2 gas estimate | URI bytes | MIDI bytes |
|---|---:|---:|---:|
| Plain named Beast | 2,280,652,067 | 177,029 | 816 |
| Animated shiny Beast | 2,388,780,801 | 182,553 | 659 |
| Heaviest score | 2,892,147,907 | 191,249 | 3,716 |

The sound-off plain test including setup was 1,249,521,999; sound-on whole test was 2,475,295,684. The static-library optimization avoids encoding TinySynth at runtime, but safe closed artwork embedding still adds substantial dynamic encoding cost.

A **mock NFT serving precomputed real Warlock presentation** on the 2.11.4/0.44 toolchain reported 31,722,009 named / 39,289,199 heaviest Cairo steps after setup subtraction and different legacy gas estimates. Those numbers omit real NFT/art computation and are not directly comparable to the mixed-toolchain Sierra figures. Detailed evidence is in `dist/resource-evidence.json`; these are unlimited local test results, not a deployed fee estimate or proof that a public RPC accepts the view.

Activation needs an independently verified, nonzero source configuration for a supported collection, a production RPC with sufficient measured call limits/latency, marketplace/browser validation, and a deployment decision. The complete path exceeds the [current 1.1B transaction L2-gas budget](https://docs.starknet.io/learn/cheatsheets/chain-info). Read calls have separate provider limits: Juno exposes configurable [`rpc-call-max-gas` and `rpc-call-max-steps`](https://github.com/NethermindEth/juno/blob/main/cmd/juno/juno.go), so transaction limits do not guarantee read acceptance. Do not enable the page on the assumption that class-size success makes the read affordable. Deployment, NFT pointer changes and merging are separate from this implementation/review.

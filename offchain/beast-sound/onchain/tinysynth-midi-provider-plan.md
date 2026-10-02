# TinySynth and Generic MIDI Provider: Implementation Plan

## Pre-encode the fixed player before storing it onchain

Pre-encoding the fixed library is strategic, and `page_data.cairo` already uses that approach.

[`page.js`](page.js) computes:

```text
base64('"animation_url":"data:text/html;base64,' + base64(fixed HTML and JavaScript))
```

[`build.mjs`](build.mjs) then packs that encoded text into Cairo felts. `token_uri` appends it directly, avoiding runtime encoding of the fixed JavaScript.

Retain this for TinySynth. Base64 increases storage—it is encoding, not compression—but saves repeated computation. TinySynth's approximately 43 KB minified library becomes approximately 76.8 KB after two encoding layers, before the wrapper. The token-specific MIDI still requires runtime encoding.

## Summary and motivation

Introduce a generic MIDI provider interface, a Beast implementation that retrieves its own live state, and a reusable TinySynth page. Make music available through just a collectible's address and token ID, while keeping collectible-specific composition and state retrieval outside the player.

Summit is obsolete and excluded from this implementation. Live state comes from the NFT collection and Death Mountain. There are no Summit calls, configuration, or legacy token-number mappings.

```text
NFT token_uri
      ↓
Music page → get_midi(token_address, token_id)
                         ↓
                  Beast MIDI provider
                         ↓
             Reads traits and live state
                         ↓
                Cairo generates MIDI
      ↓
Pre-encoded TinySynth page + generated MIDI + artwork
      ↓
Browser playback
```

Here, `token_address` means the NFT collection address, not the MIDI provider address.

## 1. Define the generic music interface and contract boundaries

Introduce a shared Cairo interface:

```cairo
#[starknet::interface]
pub trait IMidiProvider<T> {
    fn get_midi(
        self: @T,
        token_address: ContractAddress,
        token_id: u256,
    ) -> ByteArray;
}
```

Return raw Standard MIDI File bytes as a `ByteArray`. The current `[byte_length, packed_chunks…]` representation can remain internal to the existing composer and be converted efficiently at the provider boundary.

Configure the music page with a MIDI provider address. Initially, that provider is the Beast implementation; another implementation can support another collection. A global provider registry is unnecessary for the first version.

Any additional public music methods should follow the same two-identifier pattern rather than exposing Beast state.

**Gate:** callers need only `token_address` and `token_id` to obtain MIDI. A non-Beast mock provider implements the same interface.

## 2. Implement live-state retrieval inside the Beast provider

Adapt [`contracts/beast_sound/src/lib.cairo`](../../../contracts/beast_sound/src/lib.cairo), whose current benchmark interface requires callers to supply `BeastV3LiveState`.

The new provider should:

- Validate the supported collection and token.
- Decode V3 static traits from the token ID.
- Read `get_adventurers_killed(token_id)` and `get_beast_rank(token_id)` from the collection.
- Read `get_species_count(species_id)`.
- Retrieve defeat history from Death Mountain where the composition uses it, verifying the collect-count semantics and entity identity.
- Construct `BeastV3LiveState` internally and invoke the existing MIDI generator.

Configure supporting contract addresses in the provider rather than adding them to every call.

Verify the target NFT and Death Mountain interfaces and their entity-key conventions. If the pure composer retains `summit_held_seconds` for legacy compatibility, supply zero as an explicitly retired input for this provider. Scars include only verified Death Mountain defeats, with no Summit contribution. Do not introduce a Summit identity bridge. The provider must distinguish legitimate zero state from unavailable required NFT or Death Mountain data.

**Gate:** mocked state changes alter MIDI through `get_midi(token_address, token_id)`, with no live-state arguments. Required production state sources are verified.

## 3. Reuse the existing Cairo composition and MIDI export

Start with `v3_score_midi()` and its specialized exporter in [`beast_v3_sound.cairo`](../../../src/composition/beast_v3_sound.cairo). Preserve current note timing, tempo, articulation, and arrangement.

Capture fixtures for genesis and named Beasts, live-state thresholds, rarity flags, and the largest supported score. Compare the new provider's MIDI against the existing composer supplied with equivalent state.

Keep state retrieval separate from pure composition functions so each can be tested independently.

**Gate:** the new provider produces identical MIDI for equivalent inputs. Live-state reads use the same execution snapshot.

## 4. Build and pin the TinySynth player

Vendor a specific [TinySynth](https://github.com/g200kg/webaudio-tinysynth) revision with its checksum and license. Replace the embedded Beast composer with a generic player that:

- Reads embedded MIDI Base64.
- Decodes it into an `ArrayBuffer`.
- Calls TinySynth's `loadMIDI()`.
- Starts audio after a click or tap.
- Supports play, stop, restart, and looping.
- Displays the existing artwork.

Use embedded bytes rather than TinySynth's URL-loading API. Apply and test the previously identified tempo-precision patch: preserve fractional BPM when parsing MIDI tempo instead of rounding down to integer BPM.

Decide instrument assignments and accompaniment explicitly: current Cairo MIDI lacks program changes and the drums added by the browser scheduler. Preserve composition parity first; version intentional orchestration changes separately.

**Gate:** representative MIDI plays offline with correct timing and intended instruments.

## 5. Pre-encode the fixed page and assemble dynamic MIDI efficiently

Adapt the existing build pipeline to generate TinySynth-based `page_data.cairo`. Keep the fixed player HTML and JavaScript pre-encoded at both required layers.

Embed dynamic MIDI in a closed inert text block. Recalculate alignment around its Base64, closing tags, artwork, and JSON; the current layout cannot simply substitute MIDI for the old trait string.

Maintain a JavaScript reference encoder and generate Cairo parity fixtures from it. Include MIDI lengths spanning all chunk and Base64 remainder cases.

**Gate:** decoded JSON, HTML, MIDI, and artwork match the reference bytes. Runtime encoding processes the dynamic content rather than the fixed library.

## 6. Update the NFT integration to stop supplying Beast state

Change the existing sound-page integration to pass the collection address and token ID instead of `BeastSoundInputs`.

The NFT can continue supplying metadata members and artwork for page assembly. Those are presentation inputs; the music provider independently obtains everything needed for composition.

Ensure the provider calls direct state getters and never calls the NFT's `token_uri`, avoiding recursive metadata generation.

**Gate:** the complete NFT path produces playable metadata, retains the existing sound-disabled behavior, and reflects subsequent live-state changes.

## 7. Measure the complete path and document the interface

Benchmark:

```text
NFT → music page → provider → live-state contracts
                           → Cairo MIDI generation → page assembly
```

Measure compiled class sizes, execution resources, MIDI and URI sizes, read latency, and browser behavior. Previous standalone benchmarks cannot establish this combined path's cost.

Document supported collections, provider configuration, missing-state behavior, MIDI format, playback limits, and versioning. Include a second provider example to demonstrate reuse.

**Gate:** compatibility, metadata parity, offline playback, and resource checks pass before deployment.

## Completion criteria

`get_midi(token_address, token_id)` retrieves the necessary state and generates MIDI onchain. `token_uri` embeds that MIDI with a pre-encoded TinySynth player. The browser plays it without understanding Beasts or making further network requests.

## Implementation handoff

Implemented on `feat/tinysynth-sol61`: shared `IMidiProvider`, the 116-bit original-species Beast provider, generic `MidiPage`, pinned/licensed TinySynth, exact MIDI and metadata parity, offline browser controls, NFT integration patch and complete local resource evidence. Summit has been removed from new-provider state sourcing; its compatibility field is deliberately zero.

Release readiness remains gated: the documented Sepolia collection reports a zero Death Mountain source, and measured complete NFT reads exceed ordinary transaction/default RPC budgets. The implementation is ready for formal code review; no production deployment or NFT pointer change is part of this branch. Exact supported source versions, test commands and limitations are recorded in `README.md` and `integration/README.md`.

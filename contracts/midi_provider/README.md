# midi_provider

A MIDI provider turns an NFT into music from two identifiers: the collection address and the token
ID.

```cairo
#[starknet::interface]
pub trait IMidiProvider<T> {
    fn get_midi(self: @T, token_address: ContractAddress, token_id: u256) -> ByteArray;
}
```

`token_address` is the NFT collection, not the provider. Callers such as the TinySynth sound page
(`beast_sound_page::MidiSoundPage`) know nothing about the collection: the provider decides which
collections it supports, reads the token's traits and live state itself, and composes.

## Rules for a provider

| Rule | Why |
|---|---|
| Return a Standard MIDI File (`MThd` + `MTrk` chunks, format 0 or 1) as raw bytes. | The page base64-encodes it as-is and TinySynth parses it in the browser. |
| Revert only for an unsupported collection, an invalid token ID or a token that does not exist. | The call runs inside the NFT's `token_uri`; Starknet cannot catch a failed call, so a revert breaks the metadata. |
| Never revert because optional live state is unavailable. Compose from a documented default and expose where each input came from in a view of your own. | Same reason. |
| Read state through the collection's getters (or other contracts), never through `token_uri`. | `token_uri` is what is calling you. |
| Read everything inside the one `get_midi` call and cache nothing. | Every input then comes from the same state snapshot. |
| Keep extra public views on the same `(token_address, token_id)` pattern. | Callers never need collection-specific state. |

## Instruments

The TinySynth page orchestrates a bare score (no program change, nothing on channel 10) with its
own defaults: a chip lead on every channel and a drum pattern. A score with any program change or
percussion plays exactly as written with TinySynth's General MIDI set. See
`offchain/beast-sound/onchain/README.md` for the orchestration table.

## Providers

| Provider | Collections | Notes |
|---|---|---|
| `beast_sound::provider::BeastMidiProvider` (`contracts/beast_sound`) | One Beasts V3 NFT, set at deploy | Engine v1 Beast themes; reads rank, species count, kills and Death Mountain defeats itself. |
| `midi_provider::examples::scale::ScaleMidiProvider` (this package) | Any one collection, set at deploy | Example: a two-bar pentatonic loop from `poseidon(token_address, token_id)` with its own GM instruments (marimba, fingered bass) and hi-hat. |

`bytes_to_byte_array(Span<u8>)` packs bytes 31 per word with felt arithmetic and deserializes them,
which is several times cheaper than `append_byte` per byte.

## Versioning

A provider's music is part of the token's identity. A different composition is a new provider
deployment (and, for the page, a new `MidiSoundPage` pointing at it); never change what a deployed
provider returns for the same state.

## Build and test

```bash
scarb build
scarb test   # bytes_to_byte_array at every length 0..100, ScaleMidiProvider
```

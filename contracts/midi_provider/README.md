# midi_provider

A MIDI provider turns an NFT token into music. It serves one collection, set at deploy, so the
token ID is all a caller needs.

```cairo
#[starknet::interface]
pub trait IMidiProvider<T> {
    fn get_midi(self: @T, token_id: u256) -> ByteArray;
    fn get_midi_for(self: @T, token_address: ContractAddress, token_id: u256) -> ByteArray;
}
```

- **`get_midi(token_id)`**: what the NFT calls from its `token_uri`.
- **`get_midi_for(token_address, token_id)`**: the same bytes, after checking that `token_address`
  (the NFT collection, not the provider) is the one this provider serves. Callers that pass the
  collection through, such as the TinySynth sound page (`beast_sound_page::MidiSoundPage`), use it
  so a page wired to the wrong provider reverts instead of playing another collection's music.

Callers know nothing about the collection: the provider reads the token's traits and live state
itself, and composes.

## Rules for a provider

| Rule | Why |
|---|---|
| Return a Standard MIDI File (`MThd` + `MTrk` chunks, format 0 or 1) as raw bytes. | The page base64-encodes it as-is and TinySynth parses it in the browser. |
| Revert only for an unsupported collection (`get_midi_for`), an invalid token ID or (if the provider checks it) a token that does not exist. `BeastMidiProvider` checks existence through the NFT; the example `ScaleMidiProvider` does not. | The call runs inside the NFT's `token_uri`; Starknet cannot catch a failed call, so a revert breaks the metadata. |
| Never revert because optional live state is unavailable. Compose from a documented default and expose where each input came from in a view of your own. | Same reason. |
| Read state through the collection's getters (or other contracts), never through `token_uri`. | `token_uri` is what is calling you. |
| Read everything inside the one `get_midi` call and cache nothing. | Every input then comes from the same state snapshot. |
| Keep extra public views on the same `(token_address, token_id)` pattern, or take only the token ID. | Callers never need collection-specific state. |

## Sound settings (`synth`)

onchain-tinysynth (loothero's class library) plays a MIDI file exactly as written and takes its
sounds from a `SynthSettings` value: `midi_segment(midi, settings)`. A provider whose MIDI is written
for particular sounds also implements:

```cairo
#[starknet::interface]
pub trait ISynthSettingsProvider<T> {
    fn get_settings(self: @T, token_id: u256) -> SynthSettings;
}
```

so the NFT's `token_uri` needs only the provider's address and the token ID:

```cairo
let midi = IMidiProviderDispatcher { contract_address: provider }.get_midi(token_id);
let settings = ISynthSettingsProviderDispatcher { contract_address: provider }.get_settings(token_id);
let mut uri = ...; // JSON head, image
uri.append(@synth.animation_url_segment());
uri.append(@synth.midi_segment(midi, settings));
```

- `synth` re-exports the class's own types (`SynthSettings`, `Timbre`, `Operator`, `Waveform`,
  `WaveDef`, `Filter`, `FilterKind`, `FIXED_POINT_SCALE`, `TokenSound`), its `ISoundProvider` with
  dispatchers, and `settings::{default_settings, validate}` from the `onchain_tinysynth` package,
  pinned by commit in this package's `Scarb.toml`. There is no copy to drift: a value is the
  class's own type.
- The settings may depend on the token, never on anything else the caller passes, and follow the
  same revert rules as `get_midi`. A provider without one leaves the caller on the class's
  `default_settings()` (General MIDI sounds).
- It is a separate interface, so an `IMidiProvider` (and a mock of it) stays two functions.

### One call: `ISoundProvider`

A provider can also implement the class's
[sound provider interface](https://github.com/Provable-Games/onchain-tinysynth/blob/main/README.md#sound-provider-interface), one
function that returns the MIDI and the settings together, so the NFT makes one call:

```cairo
#[starknet::interface]
pub trait ISoundProvider<T> {
    fn get_sound(self: @T, token_id: u256) -> TokenSound; // TokenSound { midi, settings }
}

let sound = ISoundProviderDispatcher { contract_address: provider }.get_sound(token_id);
uri.append(@synth.midi_segment(sound.midi, sound.settings));
```

`get_sound(id)` must equal `TokenSound { midi: get_midi(id), settings: get_settings(id) }` (a
provider without `ISynthSettingsProvider` pairs its MIDI with `default_settings()`), with the same
revert rules as `get_midi`; the rest of the
[provider contract](https://github.com/Provable-Games/onchain-tinysynth/blob/main/README.md#the-provider-contract) applies. It adds a
function and changes nothing else: `IMidiProvider` and `ISynthSettingsProvider` keep their
functions and selectors. `BeastMidiProvider` and `ScaleMidiProvider` implement it.

`BeastMidiProvider` serves the TinyChip settings (`beast_sound::synth_settings`). Checked end to end
in a copy of onchain-tinysynth: its `validate` accepts them, `midi_segment` runs through the declared
class by library call, and a Beasts-layout `token_uri` built in Cairo plays in Chrome with every
timbre installed, its MIDI and SETTINGS byte-identical to the JS references
(`scripts/tinysynth_e2e/`). `beast_sound`'s tests run the same `validate` on them.

## Instruments

A bare score (no program change, nothing on channel 10) gets the TinySynth page's own
orchestration: a chip lead on every channel and a drum pattern. onchain-tinysynth adds nothing, so
providers for it write their instruments into the MIDI (`BeastMidiProvider` does: a program change
and pan per voice and a drum track) and serve the sounds those programs select with
`get_settings`. See `offchain/beast-sound/onchain/README.md` for the orchestration table.

## Providers

| Provider | Collections | Notes |
|---|---|---|
| `beast_sound::provider::BeastMidiProvider` (`contracts/beast_sound`) | One Beasts V3 NFT, set at deploy | Engine v1 Beast themes, the TinyChip settings and `get_sound`; reads rank, species count, kills and Death Mountain defeats itself. |
| `midi_provider::examples::scale::ScaleMidiProvider` (this package) | Any one collection, set at deploy | Example: a two-bar pentatonic loop from `poseidon(token_address, token_id)` with its own GM instruments (marimba, fingered bass) and hi-hat; `get_sound` pairs it with `default_settings()`. |

`bytes_to_byte_array(Span<u8>)` (from the `midi` package, re-exported here) packs bytes 31 per word
with felt arithmetic and deserializes them, which is several times cheaper than `append_byte` per
byte. `ScaleMidiProvider` writes its file with `midi::smf::TrackWriter`.

## Versioning

A provider's music is part of the token's identity. A different composition is a new provider
deployment (and, for the page, a new `MidiSoundPage` pointing at it); never change what a deployed
provider returns for the same state.

## Build and test

Needs Cairo 2.20 (scarb 2.20.1, `contracts/.tool-versions`), as `onchain_tinysynth` does.

```bash
scarb build
scarb test   # ScaleMidiProvider (behavior, pinned bytes, get_sound)
```

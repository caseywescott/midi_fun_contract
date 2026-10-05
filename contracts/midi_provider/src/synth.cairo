//! Sound settings for onchain-midi-player's `midi_segment(midi, settings)`: the class's own types,
//! interface and settings checks, re-exported from the `onchain_midi_player` package (pinned in
//! this package's `Scarb.toml`), so there is no copy to keep in sync. `midi_provider::synth::X` and
//! `onchain_midi_player::types::X` are the same type.
//!
//! `ISynthSettingsProvider` (below) serves the settings alone. A provider can also implement the
//! class's `ISoundProvider`, whose one function `get_sound(token_id)` returns the MIDI and the
//! settings together, so an NFT's `token_uri` gets both in one call; it must equal
//! `TinySynthSound { midi: get_midi(id), settings: get_settings(id) }`.
//!
//! Every fractional field is fixed point: a stored `x` means `x / FIXED_POINT_SCALE`. Ranges and
//! the checks `midi_segment` applies (`validate`) are documented on the class's types and in its
//! README.

pub use onchain_midi_player::interface::{
    ISoundProvider, ISoundProviderDispatcher, ISoundProviderDispatcherTrait,
    ISoundProviderLibraryDispatcher, ISoundProviderSafeDispatcher,
    ISoundProviderSafeDispatcherTrait,
};
pub use onchain_midi_player::settings::{default_settings, validate};
pub use onchain_midi_player::types::{
    FIXED_POINT_SCALE, Filter, FilterKind, Operator, Timbre, TinySynthSettings, TinySynthSound,
    WaveDef, Waveform,
};

/// Optional companion to `IMidiProvider`: the sound settings a provider's MIDI is written for.
/// A caller building an onchain-midi-player page passes them with the MIDI:
/// `midi_segment(provider.get_midi(token_id), provider.get_settings(token_id))`.
/// The settings may depend on the token (a provider can give rare tokens other sounds) but, like
/// the MIDI, never on anything the caller passes besides the token ID.
#[starknet::interface]
pub trait ISynthSettingsProvider<T> {
    /// `TinySynthSettings` for `token_id` of the collection this provider serves. May revert for an
    /// invalid token ID; never reverts because live state is unavailable.
    fn get_settings(self: @T, token_id: u256) -> TinySynthSettings;
}

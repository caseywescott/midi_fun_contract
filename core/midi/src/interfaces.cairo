//! The interfaces of the core MIDI system, with the dispatchers `#[starknet::interface]` generates.
//!
//! - `IMidiProvider`: a MIDI provider turns an NFT token into a Standard MIDI File. A provider
//!   serves one collection, set at deploy, so `get_midi(token_id)` is all a caller needs (the NFT
//!   calls it). `get_midi_for(token_address, token_id)` is the same MIDI with the collection
//!   checked, for callers that pass it through (the sound page). A provider owns everything
//!   collection-specific: which collection it serves, how it reads a token's traits and live
//!   state, and how it composes. Callers need only the two identifiers.
//! - `ISynthSettingsProvider`: an optional companion, the sound settings a provider's MIDI is
//!   written for.
//! - `ISoundProvider`: onchain-midi-player's, re-exported: `get_sound(token_id)` returns the MIDI
//!   and the settings together, so an NFT's `token_uri` gets both in one call; it must equal
//!   `TinySynthSound { midi: get_midi(id), settings: get_settings(id) }`.
//! - `IMidiSoundPage`: the sound page (`midi_contracts::page::MidiSoundPage`): an NFT's full
//!   `token_uri` with its music as `animation_url`.

use starknet::ContractAddress;
pub use tinysynth_interface::interface::{
    ISoundProvider, ISoundProviderDispatcher, ISoundProviderDispatcherTrait,
    ISoundProviderLibraryDispatcher, ISoundProviderSafeDispatcher,
    ISoundProviderSafeDispatcherTrait,
};
use crate::types::TinySynthSettings;

#[starknet::interface]
pub trait IMidiProvider<T> {
    /// Standard MIDI File bytes (format 0 or 1) for `token_id` of the collection this provider
    /// serves. May revert for an invalid token ID or a token that does not exist; never reverts
    /// because optional live state is unavailable.
    fn get_midi(self: @T, token_id: u256) -> ByteArray;
    /// The same bytes as `get_midi(token_id)`, after checking that `token_address` is the
    /// collection this provider serves (reverts with 'unsupported collection' otherwise).
    fn get_midi_for(self: @T, token_address: ContractAddress, token_id: u256) -> ByteArray;
}

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

#[starknet::interface]
pub trait IMidiSoundPage<T> {
    /// The token's full token_uri with `animation_url`. `members` and `svg_b64` are as for the
    /// pure `midi_contracts::page::token_uri`; the MIDI comes from the provider's
    /// `get_midi_for(token_address, token_id)` (the collection-checked form of
    /// `get_midi(token_id)`).
    fn token_uri(
        self: @T,
        members: ByteArray,
        svg_b64: ByteArray,
        token_address: ContractAddress,
        token_id: u256,
    ) -> ByteArray;
    fn get_midi_provider(self: @T) -> ContractAddress;
}

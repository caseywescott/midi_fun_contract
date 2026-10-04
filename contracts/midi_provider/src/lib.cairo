//! Generic onchain music: a MIDI provider turns an NFT token into a Standard MIDI File.
//!
//! A provider serves one collection, set at deploy, so `get_midi(token_id)` is all a caller needs
//! (the Beasts NFT calls it). `get_midi_for(token_address, token_id)` is the same MIDI with the
//! collection checked, for callers that pass it through (the TinySynth page).
//!
//! A provider owns everything collection-specific: which collections it supports, how it reads
//! a token's traits and live state, and how it composes. Callers such as the TinySynth sound page
//! (`beast_sound_page::MidiSoundPage`) need only the two identifiers and never see collection
//! state.

use starknet::ContractAddress;

pub mod examples;
pub mod synth;

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

/// `midi::pack::bytes_to_byte_array`, re-exported: a provider's `get_midi` returns its SMF bytes
/// through it.
pub use midi::pack::bytes_to_byte_array;

#[cfg(test)]
mod tests;

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

/// Packs bytes into a ByteArray 31 bytes per word with felt arithmetic, then deserializes it.
/// Several times cheaper than appending byte by byte.
pub fn bytes_to_byte_array(mut bytes: Span<u8>) -> ByteArray {
    let mut full_words = bytes.len() / 31;
    let mut serialized: Array<felt252> = array![full_words.into()];
    while full_words != 0 {
        let mut word: felt252 = 0;
        let mut k: usize = 31;
        while k != 0 {
            word = word * 0x100 + (*bytes.pop_front().unwrap()).into();
            k -= 1;
        }
        serialized.append(word);
        full_words -= 1;
    }
    let pending_len = bytes.len();
    let mut pending: felt252 = 0;
    while let Option::Some(byte) = bytes.pop_front() {
        pending = pending * 0x100 + (*byte).into();
    }
    serialized.append(pending);
    serialized.append(pending_len.into());
    let mut span = serialized.span();
    Serde::deserialize(ref span).unwrap()
}

#[cfg(test)]
mod tests;

//! BeastSoundComposer: the Koji Beast composer as a Starknet contract.
//!
//! Every view is a pure function of a Beasts V3 token ID plus the Beast's live state, passed as
//! calldata (benchmark build). `provider::BeastMidiProvider` is the production path: it serves the
//! same MIDI through `IMidiProvider::get_midi(token_id)` and reads the live state
//! itself from the Beasts NFT and Death Mountain.

use beast_music::composition::beast_trait_map::BeastCompositionParams;
use beast_music::composition::beast_v3_sound::BeastV3LiveState;

pub mod provider;

#[starknet::interface]
pub trait IBeastSoundComposer<T> {
    fn has_sound(self: @T, token_id: u256) -> bool;
    fn get_composition_params(
        self: @T, token_id: u256, live: BeastV3LiveState,
    ) -> BeastCompositionParams;
    fn get_music_state_hash(self: @T, token_id: u256, live: BeastV3LiveState) -> felt252;
    fn get_score_hash(self: @T, token_id: u256, live: BeastV3LiveState) -> felt252;
    /// Standard MIDI File bytes: [byte_len, 31-byte big-endian chunks...].
    fn get_score_midi(self: @T, token_id: u256, live: BeastV3LiveState) -> Array<felt252>;
    /// BSN1 compact note stream (7 bits per note), same packing. Clients rebuild the exact MIDI
    /// file with `bsnToMidi` (web/beast_sound/engine.js).
    fn get_score_notes(self: @T, token_id: u256, live: BeastV3LiveState) -> Array<felt252>;
    /// BSI1 instruction stream (62-bit instructions, 4 per felt): any music, not only grid canons.
    /// Decode with decodeBsi (offchain/beast-sound/src/bsi.js) or the library's notes module.
    fn get_score_instructions(
        self: @T, token_id: u256, live: BeastV3LiveState,
    ) -> Array<felt252>;
}

#[starknet::contract]
pub mod BeastSoundComposer {
    use beast_music::composition::beast_trait_map::BeastCompositionParams;
    use beast_music::composition::beast_v3_sound::{
        BeastV3LiveState, beast_has_sound, build_v3_beast_form, decode_v3_token_id,
        map_v3_beast_to_composition_params, v3_music_state_hash, v3_score_instructions, v3_score_midi,
        v3_score_notes,
    };
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        drop_salt: felt252,
        drop_bps: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, drop_salt: felt252, drop_bps: u32) {
        assert(drop_bps <= 10000, 'bps > 10000');
        self.drop_salt.write(drop_salt);
        self.drop_bps.write(drop_bps);
    }

    #[abi(embed_v0)]
    impl BeastSoundComposerImpl of super::IBeastSoundComposer<ContractState> {
        fn has_sound(self: @ContractState, token_id: u256) -> bool {
            beast_has_sound(
                self.drop_salt.read(), self.drop_bps.read(), decode_v3_token_id(token_id),
            )
        }

        fn get_composition_params(
            self: @ContractState, token_id: u256, live: BeastV3LiveState,
        ) -> BeastCompositionParams {
            map_v3_beast_to_composition_params(decode_v3_token_id(token_id), live)
        }

        fn get_music_state_hash(
            self: @ContractState, token_id: u256, live: BeastV3LiveState,
        ) -> felt252 {
            v3_music_state_hash(decode_v3_token_id(token_id), live)
        }

        fn get_score_hash(self: @ContractState, token_id: u256, live: BeastV3LiveState) -> felt252 {
            build_v3_beast_form(decode_v3_token_id(token_id), live).score_hash
        }

        fn get_score_midi(
            self: @ContractState, token_id: u256, live: BeastV3LiveState,
        ) -> Array<felt252> {
            v3_score_midi(decode_v3_token_id(token_id), live)
        }

        fn get_score_notes(
            self: @ContractState, token_id: u256, live: BeastV3LiveState,
        ) -> Array<felt252> {
            v3_score_notes(decode_v3_token_id(token_id), live)
        }

        fn get_score_instructions(
            self: @ContractState, token_id: u256, live: BeastV3LiveState,
        ) -> Array<felt252> {
            v3_score_instructions(decode_v3_token_id(token_id), live)
        }
    }
}

#[cfg(test)]
mod tests;

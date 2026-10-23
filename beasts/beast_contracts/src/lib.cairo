//! BeastSoundComposer: the Beast composer (`beast_music`) as a Starknet contract.
//!
//! Every view is a pure function of a Beast (`PackableBeastV3`) plus its live state, passed as
//! calldata (benchmark build). `provider::BeastMidiProvider` is the production path: the Beasts V3
//! sound manager, which reads each Beast from the NFT and composes its tracks through
//! `track_composer::BeastTrackComposer`.

use beast_composer::composition::beast_trait_map::BeastCompositionParams;
use beast_composer::composition::beast_v3_sound::{BeastV3LiveState, PackableBeastV3};

pub mod beasts_v3;
pub mod provider;
pub mod synth_settings;
pub mod track_composer;

#[starknet::interface]
pub trait IBeastSoundComposer<T> {
    fn has_sound(self: @T, beast: PackableBeastV3) -> bool;
    fn get_composition_params(
        self: @T, beast: PackableBeastV3, live: BeastV3LiveState,
    ) -> BeastCompositionParams;
    fn get_music_state_hash(self: @T, beast: PackableBeastV3, live: BeastV3LiveState) -> felt252;
    fn get_score_hash(self: @T, beast: PackableBeastV3, live: BeastV3LiveState) -> felt252;
    /// Standard MIDI File bytes: [byte_len, 31-byte big-endian chunks...].
    fn get_score_midi(self: @T, beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252>;
    /// BSN1 compact note stream (7 bits per note), same packing. Clients rebuild the exact MIDI
    /// file with `bsnToMidi` (offchain/beast-sound/src/bsn.js).
    fn get_score_notes(self: @T, beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252>;
    /// BSI1 instruction stream (62-bit instructions, 4 per felt): any music, not only grid canons.
    /// Decode with decodeBsi (offchain/beast-sound/src/bsi.js) or the library's notes module.
    fn get_score_instructions(
        self: @T, beast: PackableBeastV3, live: BeastV3LiveState,
    ) -> Array<felt252>;
}

#[starknet::contract]
pub mod BeastSoundComposer {
    use beast_composer::composition::beast_trait_map::BeastCompositionParams;
    use beast_composer::composition::beast_v3_sound::{
        BeastV3LiveState, PackableBeastV3, assert_valid_v3_beast, beast_has_sound,
        build_v3_beast_form, map_v3_beast_to_composition_params, v3_music_state_hash,
        v3_score_instructions, v3_score_midi, v3_score_notes,
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
        fn has_sound(self: @ContractState, beast: PackableBeastV3) -> bool {
            beast_has_sound(self.drop_salt.read(), self.drop_bps.read(), checked(beast))
        }

        fn get_composition_params(
            self: @ContractState, beast: PackableBeastV3, live: BeastV3LiveState,
        ) -> BeastCompositionParams {
            map_v3_beast_to_composition_params(checked(beast), live)
        }

        fn get_music_state_hash(
            self: @ContractState, beast: PackableBeastV3, live: BeastV3LiveState,
        ) -> felt252 {
            v3_music_state_hash(checked(beast), live)
        }

        fn get_score_hash(
            self: @ContractState, beast: PackableBeastV3, live: BeastV3LiveState,
        ) -> felt252 {
            build_v3_beast_form(checked(beast), live).score_hash
        }

        fn get_score_midi(
            self: @ContractState, beast: PackableBeastV3, live: BeastV3LiveState,
        ) -> Array<felt252> {
            v3_score_midi(checked(beast), live)
        }

        fn get_score_notes(
            self: @ContractState, beast: PackableBeastV3, live: BeastV3LiveState,
        ) -> Array<felt252> {
            v3_score_notes(checked(beast), live)
        }

        fn get_score_instructions(
            self: @ContractState, beast: PackableBeastV3, live: BeastV3LiveState,
        ) -> Array<felt252> {
            v3_score_instructions(checked(beast), live)
        }
    }

    /// `beast`, after the trait range checks every view applies.
    fn checked(beast: PackableBeastV3) -> PackableBeastV3 {
        assert_valid_v3_beast(beast);
        beast
    }
}

#[cfg(test)]
mod composer_tests;
#[cfg(test)]
mod tests;

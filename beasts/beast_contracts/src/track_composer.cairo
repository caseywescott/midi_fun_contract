//! BeastTrackComposer: the Beast Sound composer as its own class, so `BeastMidiProvider` stays
//! under Starknet's contract size limit (81,920 CASM felts). Every track composes here; the
//! provider stores this class's hash and reaches it with a library call. It is declared, never
//! deployed, and has no storage.
//!
//! The provider keeps the token checks, the NFT reads, the block-hash reads for drift and the
//! settings; this class turns a Beast, a track, a seed and a day of drift into MIDI
//! (`beast_composer::composition::tracks::beast_track_smf_bytes`).

use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::drift::DriftClock;

#[starknet::interface]
pub trait IBeastTrackComposer<T> {
    /// Track `track` of `beast` as a self-contained Standard MIDI File: 0 Sound Check, 1 Species
    /// Song, 2 Beast Special Song (the Species Song for a Beast without a special name), 3+ a
    /// bought track (`seed`, never 0; ignored by tracks 0-2), with the day of drift `drift` (none
    /// = as written; the Sound Check never drifts).
    fn compose(
        self: @T, beast: PackableBeastV3, track: u32, seed: felt252, drift: Option<DriftClock>,
    ) -> ByteArray;
    /// `beast`'s packed composer inputs (`params_pack`, layout v1) at the neutral live state: the
    /// felt a track stores to compose that Beast's songs (`unpack_inputs` and `beast_of` give
    /// `beast` back, with the Genesis level and health).
    fn composer_inputs(self: @T, beast: PackableBeastV3) -> felt252;
}

#[starknet::contract]
pub mod BeastTrackComposer {
    use beast_composer::composition::beast_v3_sound::PackableBeastV3;
    use beast_composer::composition::drift::DriftClock;
    use beast_composer::composition::genesis::{genesis_byte_array, neutral_live};
    use beast_composer::composition::params_pack::{composer_inputs, pack_inputs};
    use beast_composer::composition::tracks::{
        TRACK_SPECIAL_SONG, TRACK_SPECIES_SONG, beast_track_smf_bytes,
    };
    use midi::pack::bytes_to_byte_array;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl BeastTrackComposerImpl of super::IBeastTrackComposer<ContractState> {
        fn compose(
            self: @ContractState,
            beast: PackableBeastV3,
            track: u32,
            seed: felt252,
            drift: Option<DriftClock>,
        ) -> ByteArray {
            // The Species Song as written is the Genesis Track: its own, faster copy of the
            // composer (`genesis_byte_array`), byte-identical to the general one.
            let species_song = track == TRACK_SPECIES_SONG
                || (track == TRACK_SPECIAL_SONG && beast.prefix == 0);
            if species_song && drift.is_none() {
                return genesis_byte_array(beast);
            }
            bytes_to_byte_array(beast_track_smf_bytes(beast, track, seed, drift).span())
        }

        fn composer_inputs(self: @ContractState, beast: PackableBeastV3) -> felt252 {
            pack_inputs(composer_inputs(beast, neutral_live()))
        }
    }
}

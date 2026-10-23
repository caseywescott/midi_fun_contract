//! BeastTrackComposer: the Beast Sound composer as its own class, so `BeastMidiProvider` stays
//! under Starknet's contract size limit (81,920 CASM felts). Every track composes here; the
//! provider stores this class's hash and reaches it with a library call. It is declared, never
//! deployed, and has no storage.
//!
//! The provider keeps the token checks, the NFT reads, the block-hash reads for drift and the
//! settings; this class turns a Beast, one of its three tracks and a day of drift into MIDI with
//! the composer unchanged (`beast_composer::composition::tracks::beast_track_smf_bytes`, the body
//! of `track_smf_bytes`), so a track's bytes are the composer's for the same Beast.

use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::drift::DriftClock;

#[starknet::interface]
pub trait IBeastTrackComposer<T> {
    /// Track `track` of `beast` as a self-contained Standard MIDI File: 0 the Sound Check, 1 the
    /// Species Song, 2 the Custom Name Track (the composer's name track, `TRACK_SPECIAL_SONG`; the
    /// Species Song for a Beast without a special name), with the day of drift `drift` (none = as
    /// written; the Sound Check never drifts). Rejects any other track (`unknown track`).
    fn compose(
        self: @T, beast: PackableBeastV3, track: u32, drift: Option<DriftClock>,
    ) -> ByteArray;
}

#[starknet::contract]
pub mod BeastTrackComposer {
    use beast_composer::composition::beast_v3_sound::PackableBeastV3;
    use beast_composer::composition::drift::DriftClock;
    use beast_composer::composition::genesis::genesis_byte_array;
    use beast_composer::composition::tracks::{
        TRACK_SPECIAL_SONG, TRACK_SPECIES_SONG, beast_track_smf_bytes,
    };
    use midi::pack::bytes_to_byte_array;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl BeastTrackComposerImpl of super::IBeastTrackComposer<ContractState> {
        fn compose(
            self: @ContractState, beast: PackableBeastV3, track: u32, drift: Option<DriftClock>,
        ) -> ByteArray {
            assert(track <= TRACK_SPECIAL_SONG, 'unknown track');
            // The Species Song as written is the Genesis Track: its own, faster copy of the
            // composer (`genesis_byte_array`), byte-identical to the general one.
            let species_song = track == TRACK_SPECIES_SONG
                || (track == TRACK_SPECIAL_SONG && beast.prefix == 0);
            if species_song && drift.is_none() {
                return genesis_byte_array(beast);
            }
            bytes_to_byte_array(beast_track_smf_bytes(beast, track, 0, drift).span())
        }
    }
}

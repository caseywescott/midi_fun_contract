//! BeastTrackComposer: the Beast Sound composer as its own class, so `BeastMidiProvider` stays
//! under Starknet's contract size limit. The provider stores this class's hash and reaches it with
//! a library call: it is declared, never deployed, and has no storage. Every track of every Beast
//! is composed here from the Beast's packed composer inputs
//! (`beast_composer::composition::tracks::track_smf_bytes`).

use beast_composer::composition::drift::DriftClock;

#[starknet::interface]
pub trait IBeastTrackComposer<T> {
    /// Track `track` of the Beast whose packed composer inputs are `inputs`, as a self-contained
    /// MIDI file: 0 Sound Check, 1 Species Song, 2 Beast Special Song, 3+ a bought track (`seed`,
    /// never 0), with the day of drift `drift` (none = as written).
    fn compose(
        self: @T, inputs: felt252, track: u32, seed: felt252, drift: Option<DriftClock>,
    ) -> ByteArray;
}

#[starknet::contract]
pub mod BeastTrackComposer {
    use beast_composer::composition::drift::DriftClock;
    use beast_composer::composition::tracks::track_smf_bytes;
    use midi::pack::bytes_to_byte_array;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl BeastTrackComposerImpl of super::IBeastTrackComposer<ContractState> {
        fn compose(
            self: @ContractState,
            inputs: felt252,
            track: u32,
            seed: felt252,
            drift: Option<DriftClock>,
        ) -> ByteArray {
            bytes_to_byte_array(track_smf_bytes(inputs, track, seed, drift).span())
        }
    }
}

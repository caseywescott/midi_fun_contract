//! BeastEditionComposer: the Monthly Track Editions engine
//! (`beast_composer::composition::editions`)
//! as its own class, to measure what the editions cost on chain (CASM size and per-call gas)
//! before deciding where they live. Stateless: every view is a pure function of its arguments.

#[starknet::interface]
pub trait IBeastEditionComposer<T> {
    /// Edition `edition`'s track for a species (1-75), shiny or not, and a track seed, as a
    /// format-0 Standard MIDI File.
    fn get_edition_midi(self: @T, species: u32, shiny: bool, edition: u32, seed: u64) -> ByteArray;
    /// The edition's style engine (editions_data ENGINE order; 255 = the canon, edition 0).
    fn get_edition_engine(self: @T, edition: u32) -> u8;
}

#[starknet::contract]
pub mod BeastEditionComposer {
    use beast_composer::composition::editions::{edition_engine, edition_smf_bytes};
    use midi::pack::bytes_to_byte_array;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl BeastEditionComposerImpl of super::IBeastEditionComposer<ContractState> {
        fn get_edition_midi(
            self: @ContractState, species: u32, shiny: bool, edition: u32, seed: u64,
        ) -> ByteArray {
            bytes_to_byte_array(edition_smf_bytes(species, shiny, edition, seed).span())
        }

        fn get_edition_engine(self: @ContractState, edition: u32) -> u8 {
            edition_engine(edition)
        }
    }
}

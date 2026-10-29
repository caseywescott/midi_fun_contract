//! Shared generation call ABI, and `BeastPureGenerator`: the edition bases and purchase variations
//! behind it (`beast_composer::composition::generation`). Storage-free: no edition clock, sampling
//! policy or hash reads. Its own class, so the composer's stays within the CASM limit.
use beast_composer::inputs::{
    BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig, GenerationInputs,
};

#[starknet::interface]
pub trait IBeastPureGenerator<T> {
    fn get_generation_inputs(
        self: @T, config: EditionCompositionConfig, edition_id: u64, identity: BeastMusicalIdentity,
    ) -> GenerationInputs;
    fn generate_inputs(
        self: @T, base: GenerationInputs, variation_identity: felt252,
    ) -> ComposerInputs;
}

#[starknet::contract]
pub mod BeastPureGenerator {
    use beast_composer::composition::generation::{generate_inputs, get_generation_inputs};
    use beast_composer::inputs::{
        BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig, GenerationInputs,
    };

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl PureGeneratorImpl of super::IBeastPureGenerator<ContractState> {
        fn get_generation_inputs(
            self: @ContractState,
            config: EditionCompositionConfig,
            edition_id: u64,
            identity: BeastMusicalIdentity,
        ) -> GenerationInputs {
            get_generation_inputs(config, edition_id, identity)
        }

        fn generate_inputs(
            self: @ContractState, base: GenerationInputs, variation_identity: felt252,
        ) -> ComposerInputs {
            generate_inputs(base, variation_identity)
        }
    }
}

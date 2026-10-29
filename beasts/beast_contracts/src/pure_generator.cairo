//! Storage-free edition factory and fixed-sample generation. Split from the
//! composer only because the measured combined class exceeded the CASM limit.
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
    use beast_composer::inputs::{
        BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig, GenerationInputs,
    };
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl PureGenerator of super::IBeastPureGenerator<ContractState> {
        fn get_generation_inputs(
            self: @ContractState,
            config: EditionCompositionConfig,
            edition_id: u64,
            identity: BeastMusicalIdentity,
        ) -> GenerationInputs {
            beast_composer::composition::recipe::get_generation_inputs(config, edition_id, identity)
        }
        fn generate_inputs(
            self: @ContractState, base: GenerationInputs, variation_identity: felt252,
        ) -> ComposerInputs {
            beast_composer::composition::genesis::generate_recipe_inputs(base, variation_identity)
        }
    }
}

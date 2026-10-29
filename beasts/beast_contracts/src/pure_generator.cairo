//! Shared generation call ABI. No edition clock, sampling policy or runtime class.
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

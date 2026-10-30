//! Shared canonical composition call ABI. No runtime implementation or contract.
use beast_composer::inputs::ComposerInputs;
use midi::types::TinySynthSound;

#[starknet::interface]
pub trait IBeastPureComposer<T> {
    fn compose(self: @T, inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound;
}

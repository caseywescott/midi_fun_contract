//! EXPERIMENT (exp/kernel-libcall, K2): the Monthly Track Edition engine as its own class, reached
//! by `BeastPureComposer` by library call. The coarse boundary: the edition's inputs in (a few
//! felts), the finished sound out (the file packed 31 bytes a felt, and its settings), one call
//! per composition. Storage-free and syscall-free.
use beast_composer::composition::drift::drift_of;
use beast_composer::composition::editions::edition_byte_array;
use beast_composer::inputs::EditionInputs;
use beast_composer::inputs::drift::DriftInputs;
use midi::types::{TinySynthSettings, TinySynthSound};

#[starknet::interface]
pub trait IBeastEditionComposer<T> {
    /// The performed edition's file: `edition_byte_array` on its day of drift (`Some`).
    fn edition_midi(
        self: @T, edition: EditionInputs, mega: bool, echo: bool, drift: Option<DriftInputs>,
    ) -> ByteArray;
    /// Its settings: the edition style's presets (`edition_synth_settings`).
    fn edition_settings(self: @T, edition: EditionInputs, mega: bool) -> TinySynthSettings;
    /// Both in one call (K2b): what `BeastPureComposer` returns for an edition.
    fn compose_edition(
        self: @T, edition: EditionInputs, mega: bool, echo: bool, drift: Option<DriftInputs>,
    ) -> TinySynthSound;
}

pub fn edition_midi(
    edition: EditionInputs, mega: bool, echo: bool, drift: Option<DriftInputs>,
) -> ByteArray {
    let species = edition.identity.source_species_id;
    let day = match drift {
        Option::Some(d) => Option::Some(drift_of(species, d)),
        Option::None => Option::None,
    };
    edition_byte_array(species, mega, edition.edition, edition.seed, day, echo)
}

/// The edition's style for the species' type (1..=75: Magic, Hunter, Brute by 25s): editions take
/// the styles in turn (`edition_genome`).
pub fn edition_settings(edition: EditionInputs, mega: bool) -> TinySynthSettings {
    let style = (edition.edition - 1) % beast_composer::composition::editions_data::STYLE_COUNT;
    let beast_type = (edition.identity.source_species_id - 1) / 25;
    crate::synth_settings::edition_synth_settings(style, beast_type, mega)
}

#[starknet::contract]
pub mod BeastEditionComposer {
    use beast_composer::inputs::EditionInputs;
    use beast_composer::inputs::drift::DriftInputs;
    use midi::types::{TinySynthSettings, TinySynthSound};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl EditionComposerImpl of super::IBeastEditionComposer<ContractState> {
        fn edition_midi(
            self: @ContractState,
            edition: EditionInputs,
            mega: bool,
            echo: bool,
            drift: Option<DriftInputs>,
        ) -> ByteArray {
            super::edition_midi(edition, mega, echo, drift)
        }

        fn edition_settings(
            self: @ContractState, edition: EditionInputs, mega: bool,
        ) -> TinySynthSettings {
            super::edition_settings(edition, mega)
        }

        fn compose_edition(
            self: @ContractState,
            edition: EditionInputs,
            mega: bool,
            echo: bool,
            drift: Option<DriftInputs>,
        ) -> TinySynthSound {
            TinySynthSound {
                midi: super::edition_midi(edition, mega, echo, drift),
                settings: super::edition_settings(edition, mega),
            }
        }
    }
}

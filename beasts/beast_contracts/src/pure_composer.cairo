//! Shared canonical composition call ABI, and `BeastPureComposer`: the Beast composer behind it.
//! Storage-free: a manager owns tracks, sales, ownership, births, modes and block hashes; this
//! class turns one written song or Sound Check, played with a token's `sound_effects` (and with
//! drift, the manager's day: `DriftInputs`), into its MIDI and settings.
use beast_composer::composition::drift::drift_of;
use beast_composer::composition::editions::edition_byte_array;
use beast_composer::composition::full_midi::{SMF_DIVISION, SMF_FORMAT};
use beast_composer::composition::genesis::{drifted_song_inputs, song_tracks};
use beast_composer::composition::performance::{apply_performance, is_mega};
use beast_composer::composition::sound_check::sound_check_from_inputs;
use beast_composer::inputs::drift::DriftInputs;
use beast_composer::inputs::{ComposerInputs, SpecialArrangement};
use midi::pack::bytes_to_byte_array;
use midi::smf::smf_byte_array;
use midi::types::{TinySynthSettings, TinySynthSound};

#[starknet::interface]
pub trait IBeastPureComposer<T> {
    fn compose(self: @T, inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound;
    /// The track on a day of drift (`beast_composer::composition::drift`): a song's rhythm cells
    /// (by month), channel order (by week) and one knob (by day). A Sound Check does not drift.
    fn compose_drift(
        self: @T, inputs: ComposerInputs, sound_effects: u8, drift: DriftInputs,
    ) -> TinySynthSound;
}

pub fn compose_sound(inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound {
    compose_with(inputs, sound_effects, Option::None)
}

pub fn compose_drift_sound(
    inputs: ComposerInputs, sound_effects: u8, drift: DriftInputs,
) -> TinySynthSound {
    compose_with(inputs, sound_effects, Option::Some(drift))
}

/// `compose`, and with a day (`Some`) `compose_drift`: one body for both (CASM size). The drift
/// changes the written song; the token's sound effects then perform it.
// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
fn compose_with(
    inputs: ComposerInputs, sound_effects: u8, drift: Option<DriftInputs>,
) -> TinySynthSound {
    let drifted = match (inputs, drift) {
        (
            ComposerInputs::Song(song), Option::Some(d),
        ) => ComposerInputs::Song(
            drifted_song_inputs(song, drift_of(song.arrangement.identity.source_species_id, d)),
        ),
        _ => inputs,
    };
    let performed = apply_performance(drifted, sound_effects);
    let mega = is_mega(sound_effects);
    let midi = match performed {
        ComposerInputs::Song(song) => smf_byte_array(
            SMF_FORMAT, SMF_DIVISION, song_tracks(song, mega).span(),
        ),
        ComposerInputs::SoundCheck(check) => bytes_to_byte_array(
            sound_check_from_inputs(check, mega).span(),
        ),
        ComposerInputs::Edition(edition) => edition_byte_array(
            edition.identity.source_species_id, mega, edition.edition, edition.seed,
        ),
    };
    TinySynthSound { midi, settings: settings_for(performed, mega) }
}

/// The sounds the file can select: the family's presets and the drum kit, plus the mega leads when
/// mega. A Yeti special has the Yeti's settings (the Brute family and the avalanche preset: the
/// Yeti is a Brute; an authored Yeti special on another family plays them too), and an edition its
/// style's presets (`edition_synth_settings`).
pub fn settings_for(inputs: ComposerInputs, mega: bool) -> TinySynthSettings {
    let (family, special) = match inputs {
        ComposerInputs::Song(x) => (x.arrangement.family, x.arrangement.special),
        ComposerInputs::SoundCheck(x) => (x.family, SpecialArrangement::None),
        // the edition's style for the species' type (1..=75: Magic, Hunter, Brute by 25s): editions
        // take the four styles in turn (`edition_genome`)
        ComposerInputs::Edition(x) => {
            let style = (x.edition - 1) % 4;
            let beast_type = (x.identity.source_species_id - 1) / 25;
            return crate::synth_settings::edition_synth_settings(style, beast_type, mega);
        },
    };
    let yeti = match special {
        SpecialArrangement::None => false,
        SpecialArrangement::Yeti(_) => true,
    };
    if yeti {
        return crate::synth_settings::yeti_synth_settings(mega);
    }
    crate::synth_settings::beast_synth_settings(family, mega)
}

#[starknet::contract]
pub mod BeastPureComposer {
    use beast_composer::inputs::ComposerInputs;
    use beast_composer::inputs::drift::DriftInputs;
    use midi::types::TinySynthSound;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl PureComposerImpl of super::IBeastPureComposer<ContractState> {
        fn compose(
            self: @ContractState, inputs: ComposerInputs, sound_effects: u8,
        ) -> TinySynthSound {
            super::compose_sound(inputs, sound_effects)
        }

        fn compose_drift(
            self: @ContractState, inputs: ComposerInputs, sound_effects: u8, drift: DriftInputs,
        ) -> TinySynthSound {
            super::compose_drift_sound(inputs, sound_effects, drift)
        }
    }
}

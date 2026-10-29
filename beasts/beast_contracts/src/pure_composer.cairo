//! Storage-free pure target. A manager owns sales, ownership, modes, births and
//! hash availability; this class owns one matching MIDI/settings interpretation.
use beast_composer::composition::recipe::{apply_performance, is_mega};
use beast_composer::inputs::ComposerInputs;
use midi::types::TinySynthSound;

#[starknet::interface]
pub trait IBeastPureComposer<T> {
    fn compose(self: @T, inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound;
}

pub fn settings_for(inputs: ComposerInputs, sound_effects: u8) -> midi::types::TinySynthSettings {
    use beast_composer::inputs::SpecialArrangement;
    use midi::types::{Operator, Timbre, Waveform};
    let mega = is_mega(sound_effects);
    let (family, special) = match inputs {
        ComposerInputs::Song(x) => (x.arrangement.family, x.arrangement.special),
        ComposerInputs::SoundCheck(x) => (x.family, SpecialArrangement::None),
    };
    let has_extra = match special {
        SpecialArrangement::None => false,
        SpecialArrangement::Yeti(_) => true,
    };
    if has_extra && family == 2 {
        return crate::synth_settings::yeti_synth_settings(mega);
    }
    let base = crate::synth_settings::beast_synth_settings(family, mega);
    if !has_extra {
        return base;
    }
    for timbre in base.timbres {
        if !timbre.drum && timbre.slot == 13 {
            return base;
        }
    }
    // Authored Yeti arrangement may use another family. Preserve that family's
    // exact presets; add only the missing avalanche preset and remap its waves.
    let extra = crate::synth_settings::yeti_synth_settings(false);
    let offset: u8 = base.waves.len().try_into().unwrap();
    let mut waves = array![];
    waves.append_span(base.waves);
    waves.append_span(extra.waves);
    let mut timbres = array![];
    timbres.append_span(base.timbres);
    for timbre in extra.timbres {
        if !timbre.drum && timbre.slot == 13 {
            let mut operators = array![];
            for op in timbre.operators {
                let op = *op;
                let wave = match op.wave {
                    Waveform::Custom(i) => Waveform::Custom(i + offset),
                    other => other,
                };
                operators.append(Operator { wave, ..op });
            }
            timbres.append(Timbre { operators: operators.span(), ..*timbre });
        }
    }
    midi::types::TinySynthSettings { waves: waves.span(), timbres: timbres.span(), ..base }
}

pub fn compose_sound(inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound {
    let effective = apply_performance(inputs, sound_effects);
    let mega = is_mega(sound_effects);
    let midi = match effective {
        ComposerInputs::Song(song) => beast_composer::composition::genesis::recipe_byte_array(
            song, mega,
        ),
        ComposerInputs::SoundCheck(check) => midi::pack::bytes_to_byte_array(
            beast_composer::composition::sound_check::sound_check_from_inputs(check, mega).span(),
        ),
    };
    TinySynthSound { midi, settings: settings_for(effective, sound_effects) }
}

#[starknet::contract]
pub mod BeastPureComposer {
    use beast_composer::inputs::ComposerInputs;
    use midi::types::TinySynthSound;
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl PureComposer of super::IBeastPureComposer<ContractState> {
        fn compose(
            self: @ContractState, inputs: ComposerInputs, sound_effects: u8,
        ) -> TinySynthSound {
            super::compose_sound(inputs, sound_effects)
        }
    }
}

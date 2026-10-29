//! Shared canonical composition call ABI, and `BeastPureComposer`: the Beast composer behind it.
//! Storage-free: a manager owns tracks, sales, ownership, births, modes and block hashes; this
//! class turns one written song or Sound Check, played with a token's `sound_effects` (and on a
//! staff, the manager's resolved evolution context), into its MIDI and settings.
use beast_composer::composition::editions::edition_byte_array;
use beast_composer::composition::evolution::resolve_evolution;
use beast_composer::composition::full_midi::{SMF_DIVISION, SMF_FORMAT};
use beast_composer::composition::genesis::{song_tracks, staff_song_tracks};
use beast_composer::composition::performance::{apply_performance, is_mega};
use beast_composer::composition::sound_check::sound_check_from_inputs;
use beast_composer::inputs::evolution::{EvolutionConfig, EvolutionInputs};
use beast_composer::inputs::{ComposerInputs, SpecialArrangement};
use midi::pack::bytes_to_byte_array;
use midi::smf::smf_byte_array;
use midi::types::{Operator, Timbre, TinySynthSettings, TinySynthSound, Waveform};

#[starknet::interface]
pub trait IBeastPureComposer<T> {
    fn compose(self: @T, inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound;
    /// A song on a staff: the evolution unlocks extra channels and performs the notes and tempo
    /// (`beast_composer::composition::evolution`). A Sound Check has no staff: it is `compose`'s.
    fn compose_staff(
        self: @T,
        inputs: ComposerInputs,
        sound_effects: u8,
        evolution: EvolutionConfig,
        context: EvolutionInputs,
    ) -> TinySynthSound;
}

/// The Yeti's avalanche preset (`yeti::YETI_AVALANCHE_PROGRAM`).
const AVALANCHE_SLOT: u8 = 13;

pub fn compose_sound(inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound {
    compose_with(inputs, sound_effects, Option::None)
}

pub fn compose_staff_sound(
    inputs: ComposerInputs, sound_effects: u8, evolution: EvolutionConfig, context: EvolutionInputs,
) -> TinySynthSound {
    assert(context.staff_block >= context.birth_block, 'staff before birth');
    compose_with(inputs, sound_effects, Option::Some((evolution, context)))
}

/// `compose`, and on a staff (`Some`) `compose_staff` after its birth check: one body for both
/// (CASM size). A Sound Check has no staff.
// On purpose (CASM size): stops the compiler emitting a copy per call with constant arguments.
#[inline(never)]
fn compose_with(
    inputs: ComposerInputs, sound_effects: u8, staff: Option<(EvolutionConfig, EvolutionInputs)>,
) -> TinySynthSound {
    let performed = apply_performance(inputs, sound_effects);
    let mega = is_mega(sound_effects);
    let midi = match performed {
        ComposerInputs::Song(song) => {
            let tracks = match staff {
                Option::None => song_tracks(song, mega),
                Option::Some((evolution, context)) => {
                    // the roles past the written channels, in order, that the staff may unlock
                    let roles = song.score.voice_count
                        + if song.score.use_countersubject {
                            1
                        } else {
                            0
                        }
                        + 1;
                    let controls = resolve_evolution(
                        evolution, context, roles - song.arrangement.channel_count,
                    );
                    staff_song_tracks(song, mega, controls)
                },
            };
            smf_byte_array(SMF_FORMAT, SMF_DIVISION, tracks.span())
        },
        ComposerInputs::SoundCheck(check) => bytes_to_byte_array(
            sound_check_from_inputs(check, mega).span(),
        ),
        ComposerInputs::Edition(edition) => edition_byte_array(
            edition.identity.source_species_id.try_into().unwrap(),
            mega,
            edition.edition,
            edition.seed,
        ),
    };
    TinySynthSound { midi, settings: settings_for(performed, mega) }
}

/// The sounds the file can select: the family's presets and the drum kit, plus the mega leads when
/// mega. The Yeti (a Brute) has its own settings; a Yeti special on another family keeps that
/// family's presets and adds the avalanche preset.
pub fn settings_for(inputs: ComposerInputs, mega: bool) -> TinySynthSettings {
    let (family, special) = match inputs {
        ComposerInputs::Song(x) => (x.arrangement.family, x.arrangement.special),
        ComposerInputs::SoundCheck(x) => (x.family, SpecialArrangement::None),
        // species 1..=75: Magic, Hunter, Brute by 25s
        ComposerInputs::Edition(x) => (
            ((x.identity.source_species_id - 1) / 25).try_into().unwrap(), SpecialArrangement::None,
        ),
    };
    let yeti = match special {
        SpecialArrangement::None => false,
        SpecialArrangement::Yeti(_) => true,
    };
    if yeti && family == 2 {
        return crate::synth_settings::yeti_synth_settings(mega);
    }
    let base = crate::synth_settings::beast_synth_settings(family, mega);
    if !yeti {
        return base;
    }
    for timbre in base.timbres {
        if !timbre.drum && timbre.slot == AVALANCHE_SLOT {
            return base;
        }
    }
    // the avalanche preset from the Yeti's settings, its custom waves appended after the family's
    let extra = crate::synth_settings::yeti_synth_settings(false);
    let offset: u8 = base.waves.len().try_into().unwrap();
    let mut waves = array![];
    waves.append_span(base.waves);
    waves.append_span(extra.waves);
    let mut timbres = array![];
    timbres.append_span(base.timbres);
    for timbre in extra.timbres {
        if !timbre.drum && timbre.slot == AVALANCHE_SLOT {
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
    TinySynthSettings { waves: waves.span(), timbres: timbres.span(), ..base }
}

#[starknet::contract]
pub mod BeastPureComposer {
    use beast_composer::inputs::ComposerInputs;
    use beast_composer::inputs::evolution::{EvolutionConfig, EvolutionInputs};
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

        fn compose_staff(
            self: @ContractState,
            inputs: ComposerInputs,
            sound_effects: u8,
            evolution: EvolutionConfig,
            context: EvolutionInputs,
        ) -> TinySynthSound {
            super::compose_staff_sound(inputs, sound_effects, evolution, context)
        }
    }
}

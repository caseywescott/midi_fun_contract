use super::{
    ArrangementInputs, BeastMusicalIdentity, ChannelPolicy, ComposerInputs,
    EditionCompositionConfig, GenerationInputs, MusicIdentity, ScoreInputs, SongInputs,
    SoundCheckInputs, SpecialArrangement, ThemeInputs, TreatmentInputs, decode_generation_inputs,
    decode_inputs, encode_generation_inputs, encode_inputs, validate_inputs, validate_performance,
};

fn song() -> SongInputs {
    SongInputs {
        theme: ThemeInputs { motif_seed: 11, tier: 2, register_band: 1 },
        score: ScoreInputs {
            mode_id: 4,
            tonic_keynum: 60,
            tier: 3,
            weakness: 2,
            voice_count: 4,
            section_count: 3,
            stretto_lag: 2,
            use_inversion: true,
            use_countersubject: true,
            ornament_density: 3,
            articulation_profile: 5,
            velocity_ceiling: 109,
            tempo_us: 500000,
        },
        treatment: TreatmentInputs {
            rhythm_seed: 13,
            flip_side: true,
            development: 1,
            direction: 2,
            spacing: 0,
            trill: true,
            prominence: 2,
            section_rhythm: false,
        },
        arrangement: ArrangementInputs {
            family: 0,
            identity: MusicIdentity { source_species_id: 1, name_variant_id: 37 },
            channel_count: 4,
            channel_policy: ChannelPolicy::Seeded(17),
            special: SpecialArrangement::Yeti(9),
            top_lead: true,
            balanced: false,
            weak_ties: true,
        },
    }
}

// Literal wire oracle from the public field-order contract, independent of Serde.
fn song_wire() -> Array<felt252> {
    array![
        4, 1, 11, 2, 1, 4, 60, 3, 2, 4, 3, 2, 1, 1, 3, 5, 109, 500000, 13, 1, 1, 2, 0, 1, 2, 0, 0,
        1, 37, 4, 1, 17, 1, 9, 1, 0, 1
    ]
}

#[test]
fn song_matches_independent_wire() {
    let x = ComposerInputs::Song(song());
    let expected = song_wire();
    assert(encode_inputs(x) == expected, 'song wire');
    assert(decode_inputs(expected.span()) == x, 'song decode');
}

#[test]
fn sound_check_matches_independent_wire() {
    let x = ComposerInputs::SoundCheck(
        SoundCheckInputs {
            identity: MusicIdentity {
                source_species_id: 0xffffffffffffffff, name_variant_id: 1242,
            },
            mode_id: 26,
            tonic_keynum: 103,
            family: 2,
            tempo_us: 1048575,
            velocity_ceiling: 127,
            articulation_profile: 3,
        },
    );
    let expected = array![4, 0, 0xffffffffffffffff, 1242, 26, 103, 2, 1048575, 127, 3];
    assert(encode_inputs(x) == expected, 'check wire');
    assert(decode_inputs(expected.span()) == x, 'check decode');
}

#[test]
fn generation_has_own_version_and_no_recipe_tag() {
    let x = GenerationInputs { base_song: song() };
    let expected = array![
        2, 11, 2, 1, 4, 60, 3, 2, 4, 3, 2, 1, 1, 3, 5, 109, 500000, 13, 1, 1, 2, 0, 1, 2, 0, 0, 1,
        37, 4, 1, 17, 1, 9, 1, 0, 1
    ];
    assert(encode_generation_inputs(x) == expected, 'generation wire');
    assert(decode_generation_inputs(expected.span()) == x, 'generation decode');
}

#[test]
fn zero_musical_seeds_are_valid_not_sentinels() {
    let mut x = song();
    x.theme.motif_seed = 0;
    x.treatment.rhythm_seed = 0;
    x.arrangement.channel_policy = ChannelPolicy::Seeded(0);
    let recipe = ComposerInputs::Song(x);
    assert(decode_inputs(encode_inputs(recipe).span()) == recipe, 'zero seeds');
}

#[test]
fn smallest_role_set_has_two_selectable_roles() {
    let mut x = song();
    x.score.voice_count = 1;
    x.score.use_countersubject = false;
    x.arrangement.channel_count = 2;
    validate_inputs(ComposerInputs::Song(x));
}

#[test]
fn all_named_modes_and_articulations_round_trip() {
    let modes = array![4_u8, 5, 6, 7, 8, 26];
    let articulations = array![0_u8, 1, 2, 3, 5];
    for mode in modes.span() {
        for articulation in articulations.span() {
            let mut x = song();
            x.score.mode_id = *mode;
            x.score.articulation_profile = *articulation;
            let recipe = ComposerInputs::Song(x);
            assert(decode_inputs(encode_inputs(recipe).span()) == recipe, 'mode articulation');
        }
    }
}

#[test]
fn canonical_types_have_builtin_store() {
    assert(starknet::Store::<ComposerInputs>::size() > 0, 'composer store');
    assert(starknet::Store::<GenerationInputs>::size() > 0, 'generation store');
    assert(starknet::Store::<EditionCompositionConfig>::size() == 1, 'edition store');
    assert(starknet::Store::<BeastMusicalIdentity>::size() == 4, 'identity store');
}

#[test]
#[should_panic(expected: 'unknown inputs version')]
fn reject_unknown_version() {
    decode_inputs(array![2].span());
}

#[test]
#[should_panic(expected: 'invalid inputs encoding')]
fn reject_truncated_recipe() {
    decode_inputs(array![4, 1, 11].span());
}

#[test]
#[should_panic(expected: 'invalid inputs encoding')]
fn reject_unknown_recipe_tag() {
    decode_inputs(array![4, 2].span());
}

#[test]
#[should_panic(expected: 'extra inputs data')]
fn reject_trailing_data() {
    let mut values = song_wire();
    values.append(0);
    decode_inputs(values.span());
}

#[test]
#[should_panic(expected: 'non canonical inputs')]
fn reject_non_boolean_wire_value() {
    let values = array![
        4, 1, 11, 2, 1, 4, 60, 3, 2, 4, 3, 2, 2, 1, 3, 5, 109, 500000, 13, 1, 1, 2, 0, 1, 2, 0, 0,
        1, 37, 4, 1, 17, 1, 9, 1, 0, 1
    ];
    decode_inputs(values.span());
}

#[test]
#[should_panic(expected: 'unsupported musical mode')]
fn reject_silent_scale_fallback() {
    let mut x = song();
    x.score.mode_id = 0;
    validate_inputs(ComposerInputs::Song(x));
}

#[test]
#[should_panic(expected: 'invalid song tonic')]
fn reject_song_tonic_outside_realizer_home() {
    let mut x = song();
    x.score.tonic_keynum = 97;
    validate_inputs(ComposerInputs::Song(x));
}

#[test]
#[should_panic(expected: 'invalid sound check tonic')]
fn reject_sound_check_octave_overflow() {
    validate_inputs(
        ComposerInputs::SoundCheck(
            SoundCheckInputs {
                identity: MusicIdentity { source_species_id: 1, name_variant_id: 0 },
                mode_id: 4,
                tonic_keynum: 104,
                family: 0,
                tempo_us: 500000,
                velocity_ceiling: 112,
                articulation_profile: 0,
            },
        ),
    );
}

#[test]
#[should_panic(expected: 'invalid channel count')]
fn reject_missing_channel_role() {
    let mut x = song();
    x.score.voice_count = 1;
    x.score.use_countersubject = false;
    x.arrangement.channel_count = 3;
    validate_inputs(ComposerInputs::Song(x));
}

#[test]
#[should_panic(expected: 'invalid musical tempo')]
fn reject_zero_tempo() {
    let mut x = song();
    x.score.tempo_us = 0;
    validate_inputs(ComposerInputs::Song(x));
}

#[test]
#[should_panic(expected: 'invalid musical velocity')]
fn reject_zero_velocity_sentinel() {
    let mut x = song();
    x.score.velocity_ceiling = 0;
    validate_inputs(ComposerInputs::Song(x));
}

#[test]
#[should_panic(expected: 'invalid articulation')]
fn reject_undefined_articulation() {
    let mut x = song();
    x.score.articulation_profile = 4;
    validate_inputs(ComposerInputs::Song(x));
}

#[test]
#[should_panic(expected: 'invalid sound effects')]
fn reject_unassigned_pure_preset() {
    validate_performance(4);
}

#[test]
#[should_panic(expected: 'unknown generation version')]
fn reject_generation_version() {
    decode_generation_inputs(array![1].span());
}

#[test]
#[should_panic(expected: 'unknown inputs version')]
fn reject_previous_composition_version3() {
    decode_inputs(array![3].span());
}

#[test]
#[should_panic(expected: 'non canonical inputs')]
fn reject_non_boolean_section_rhythm() {
    let original = song_wire();
    let mut values = array![];
    let mut i = 0;
    for value in original.span() {
        values.append(if i == 25 {
            2
        } else {
            *value
        });
        i += 1;
    }
    decode_inputs(values.span());
}

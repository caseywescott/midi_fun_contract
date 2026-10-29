//! Pure normalized-input semantics, independent of the chain/provider wrapper.
use beast_composer_inputs::{
    BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig, MusicIdentity,
};
use crate::composition::recipe::{apply_performance, get_generation_inputs, is_mega};

fn song() -> ComposerInputs {
    let base = get_generation_inputs(
        EditionCompositionConfig { composition_seed: 0 },
        0,
        BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 },
    );
    let mut value = base.base_song;
    value.score.velocity_ceiling = 109;
    value.score.articulation_profile = 0;
    ComposerInputs::Song(value)
}
#[test]
fn performance_codes_have_exact_units_and_never_mutate_authored_inputs() {
    let x = song();
    let expected = array![
        (500000_u32, 109_u8, 0_u8), (475000, 121, 2), (470000, 117, 5), (455000, 124, 3)
    ];
    let mut code: u8 = 0;
    for values in expected.span() {
        let result = apply_performance(x, code);
        if let ComposerInputs::Song(value) = result {
            let p = value.score;
            assert(
                (p.tempo_us, p.velocity_ceiling, p.articulation_profile) == *values,
                'exact performance',
            );
        } else {
            panic!("changed recipe kind");
        }
        assert(x == song(), 'authored input unchanged');
        assert(is_mega(code) == (code == 1 || code == 3), 'preset mega policy');
        code += 1;
    }
}
#[test]
fn performance_saturates_tempo_and_velocity() {
    let ComposerInputs::Song(mut p) = song() else {
        panic!("fixture");
    };
    p.score.tempo_us = 1;
    p.score.velocity_ceiling = 127;
    for code in array![1_u8, 2, 3].span() {
        let ComposerInputs::Song(effective) = apply_performance(
            ComposerInputs::Song(p), *code,
        ) else {
            panic!("fixture");
        };
        assert(
            effective.score.tempo_us == 1 && effective.score.velocity_ceiling == 127, 'saturation',
        );
    }
}
#[test]
fn factory_preserves_actual_named_identity_across_editions_and_paid39_40() {
    for species_id in array![39_u64, 40, 68, 0xffffffffffffffff].span() {
        let identity = BeastMusicalIdentity {
            species_id: *species_id, name_variant_id: 1242, tier: 5, family: 0,
        };
        let named = beast_composer_inputs::normalize_generation_identity(identity);
        assert(
            named == MusicIdentity { source_species_id: *species_id, name_variant_id: 1242 },
            'named drift identity',
        );
        for edition_id in array![0_u64, 1, 99].span() {
            let base = get_generation_inputs(
                EditionCompositionConfig { composition_seed: 9 }, *edition_id, identity,
            );
            assert(
                base.base_song.arrangement.identity.source_species_id == *species_id,
                'no paid swap',
            );
            assert(
                base.base_song.arrangement.identity.name_variant_id == 0,
                'program identity separate',
            );
        }
    }
}
#[test]
#[should_panic(expected: 'invalid musical tier')]
fn factory_validates_semantic_identity_before_derivation() {
    get_generation_inputs(
        EditionCompositionConfig { composition_seed: 0 },
        0,
        BeastMusicalIdentity { species_id: 21, name_variant_id: 0, tier: 0, family: 0 },
    );
}
#[test]
#[should_panic(expected: 'invalid sound effects')]
fn performance_rejects_reserved_code() {
    apply_performance(song(), 4);
}

#[test]
fn generated_sample_preserves_authored_base_outside_explicit_purchase_treatment() {
    use beast_composer_inputs::{ChannelPolicy, SpecialArrangement};
    let mut base = get_generation_inputs(
        EditionCompositionConfig { composition_seed: 9 },
        2,
        BeastMusicalIdentity { species_id: 76, name_variant_id: 1242, tier: 1, family: 1 },
    );
    base.base_song.score.tempo_us = 400001;
    base.base_song.score.voice_count = 1;
    base.base_song.score.use_countersubject = false;
    base.base_song.arrangement.channel_count = 2;
    base.base_song.arrangement.special = SpecialArrangement::Yeti(1242);
    let before = base;
    for seed in array![0_felt252, 1, 123].span() {
        let ComposerInputs::Song(x) = crate::composition::genesis::generate_recipe_inputs(
            base, *seed,
        ) else {
            panic!("fixture");
        };
        assert(x.theme == base.base_song.theme, 'sample theme retained');
        assert(x.treatment.section_rhythm, 'zero sample explicit rhythm');
        assert(!base.base_song.treatment.section_rhythm, 'written base unchanged');
        assert(
            x.score.tempo_us == 400001 && x.score.voice_count == 1 && !x.score.use_countersubject,
            'sample fixed score',
        );
        assert(
            x.arrangement.special == base.base_song.arrangement.special
                && x.arrangement.identity == base.base_song.arrangement.identity
                && x.arrangement.family == 1,
            'sample fixed arrangement',
        );
        assert(
            x.arrangement.channel_count == 2
                && x.arrangement.channel_policy == ChannelPolicy::Seeded(*seed),
            'sample role clamp',
        );
    }
    assert(base == before, 'generation base immutable');
}

fn shape_bit(index: u8) -> u8 {
    let mut value: u8 = 1;
    let mut i: u8 = 0;
    while i < index {
        value *= 2;
        i += 1;
    }
    value
}
#[test]
fn purchase_shape_keeps_edition_identity_and_uses_only_authored_roles() {
    let base = get_generation_inputs(
        EditionCompositionConfig { composition_seed: 9 },
        2,
        BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 },
    );
    let mut lags: u8 = 0;
    let mut densities: u8 = 0;
    let mut voices: u8 = 0;
    let mut inversions: u8 = 0;
    let mut trills: u8 = 0;
    let mut subjects: u8 = 0;
    let mut seed: u64 = 0;
    while seed < 128 {
        let ComposerInputs::Song(x) = crate::composition::genesis::generate_recipe_inputs(
            base, seed.into(),
        ) else {
            panic!("fixture");
        };
        assert(x.theme == base.base_song.theme, 'edition motif unchanged');
        assert(
            x.score.mode_id == base.base_song.score.mode_id
                && x.score.tonic_keynum == base.base_song.score.tonic_keynum,
            'edition home key unchanged',
        );
        assert(
            x.arrangement.identity == base.base_song.arrangement.identity
                && x.arrangement.family == base.base_song.arrangement.family,
            'edition palette unchanged',
        );
        assert(
            x.score.tempo_us == base.base_song.score.tempo_us
                && x.score.velocity_ceiling == base.base_song.score.velocity_ceiling
                && x.score.articulation_profile == base.base_song.score.articulation_profile
                && x.treatment.prominence == base.base_song.treatment.prominence,
            'not dynamics-only entropy',
        );
        assert(x.score.voice_count == 3 || x.score.voice_count == 4, 'bounded written voices');
        let roles = x.score.voice_count + if x.score.use_countersubject {
            1
        } else {
            0
        } + 1;
        assert(x.arrangement.channel_count <= roles, 'actual sampled roles');
        lags = lags | shape_bit(x.score.stretto_lag - 1);
        densities = densities | shape_bit(x.score.ornament_density);
        voices = voices | shape_bit(x.score.voice_count - 3);
        inversions = inversions | shape_bit(if x.score.use_inversion {
            1
        } else {
            0
        });
        trills = trills | shape_bit(if x.treatment.trill {
            1
        } else {
            0
        });
        subjects = subjects | shape_bit(if x.score.use_countersubject {
            1
        } else {
            0
        });
        seed += 1;
    }
    assert(lags == 15 && densities == 255, 'shape range witnesses');
    assert(
        voices == 3 && inversions == 3 && trills == 3 && subjects == 3, 'counterpoint witnesses',
    );
}

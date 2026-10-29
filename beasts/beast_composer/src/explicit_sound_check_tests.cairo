//! Explicit-input SoundCheck extension performance contract, separate from Song.
use beast_composer_inputs::{ComposerInputs, MusicIdentity, SoundCheckInputs};
use crate::composition::recipe::{apply_performance, is_mega};

fn check() -> ComposerInputs {
    ComposerInputs::SoundCheck(
        SoundCheckInputs {
            identity: MusicIdentity { source_species_id: 21, name_variant_id: 37 },
            mode_id: 4,
            tonic_keynum: 60,
            family: 0,
            tempo_us: 500000,
            velocity_ceiling: 109,
            articulation_profile: 0,
        },
    )
}
#[test]
fn explicit_sound_check_performance_codes_have_exact_units_and_never_mutate_authored_inputs() {
    let x = check();
    let expected = array![
        (500000_u32, 109_u8, 0_u8), (475000, 121, 2), (470000, 117, 5), (455000, 124, 3)
    ];
    let mut code: u8 = 0;
    for values in expected.span() {
        let result = apply_performance(x, code);
        if let ComposerInputs::SoundCheck(p) = result {
            assert(
                (p.tempo_us, p.velocity_ceiling, p.articulation_profile) == *values,
                'exact performance',
            );
        } else {
            panic!("changed recipe kind");
        }
        assert(x == check(), 'authored input unchanged');
        assert(is_mega(code) == (code == 1 || code == 3), 'preset mega policy');
        code += 1;
    }
}
#[test]
fn explicit_sound_check_performance_saturates_tempo_and_velocity() {
    let ComposerInputs::SoundCheck(mut p) = check() else {
        panic!("fixture");
    };
    p.tempo_us = 1;
    p.velocity_ceiling = 127;
    for code in array![1_u8, 2, 3].span() {
        let ComposerInputs::SoundCheck(effective) = apply_performance(
            ComposerInputs::SoundCheck(p), *code,
        ) else {
            panic!("fixture");
        };
        assert(effective.tempo_us == 1 && effective.velocity_ceiling == 127, 'saturation');
    }
}

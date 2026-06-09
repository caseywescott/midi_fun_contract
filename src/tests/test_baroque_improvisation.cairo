//! Tests for the seeded Baroque cadential improvisation generator.

use koji::composition::baroque_improvisation::{
    BaroqueMelody, LocalKey, MelodyAnchor, MODE_MAJOR, MODE_NATURAL_MINOR, MODE_HARMONIC_MINOR,
    MODULE_CADENCE_43, MODULE_CADENCE_3451, MODULE_CADENCE_FRENCH_LONG5,
    MODULE_CADENCE_DESC_3451, MODULE_CADENCE_DESC_4251, MODULE_CADENZA_DOPPIA,
    MODULE_FAUXBOURDON_76, MODULE_CIRCLE_5THS, MODULE_ROMANESCA, MODULE_ASCENDING_5THS,
    TAG_SUSPENSION_43, TAG_CHAIN_76, TAG_RAISED_4,
    TEXTURE_BROKEN_STYLE, TEXTURE_STYLE_BRISE,
    generate_baroque_cadential_improvisation,
    generate_baroque_cadential_improvisation_with_transforms,
    generate_baroque_melody, develop_scaffold_melody,
    module_by_id, module_exists, baroque_traits, validate_baroque_realization,
    ROLE_MELODY,
};

#[test]
#[available_gas(1000000000000)]
fn test_baroque_catalogue_contains_core_modules() {
    assert(module_exists(MODULE_CADENCE_43), '43 exists');
    assert(module_exists(MODULE_CADENCE_3451), '3451 exists');
    assert(module_exists(MODULE_CADENCE_FRENCH_LONG5), 'french exists');
    assert(module_exists(MODULE_CADENCE_DESC_3451), 'desc3451 exists');
    assert(module_exists(MODULE_CADENCE_DESC_4251), 'desc4251 exists');
    assert(module_exists(MODULE_FAUXBOURDON_76), 'fauxbourdon exists');
    assert(module_exists(MODULE_CIRCLE_5THS), 'circle exists');
    assert(module_exists(MODULE_ROMANESCA), 'romanesca exists');
    assert(module_exists(MODULE_ASCENDING_5THS), 'asc5 exists');
    assert(module_exists(MODULE_CADENZA_DOPPIA), 'doppia exists');
    assert(module_by_id(MODULE_CADENCE_3451).default_texture == TEXTURE_BROKEN_STYLE, 'broken');
    assert(module_by_id(MODULE_CADENCE_FRENCH_LONG5).default_texture == TEXTURE_STYLE_BRISE, 'brise');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_melody_repairs_anchor() {
    let key = LocalKey { tonic_pc: 0, mode_id: MODE_MAJOR, degree_offset: 0 };
    let anchors = array![
        MelodyAnchor {
            position: 3,
            target_degree: koji::composition::baroque_improvisation::ScaleDegree {
                degree0: 0, alter: 0,
            },
            anchor_kind: 0,
        },
    ];
    let melody = generate_baroque_melody(99, key, 4, anchors.span());
    assert(melody.degrees.len() == 4, 'melody length');
    assert((*melody.degrees.at(3)).degree0 == 0, 'anchor target');
    assert(melody.anchor_adjustments > 0, 'repair counted');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_cadence_43_validates_resolution() {
    let real = generate_baroque_cadential_improvisation(0); // family 0, variant 0
    assert(validate_baroque_realization(@real), 'valid 43');
    assert(*real.plan.modules.at(0) == MODULE_CADENCE_43, 'module 43');
    assert((*real.figures.at(0)).dissonance_tag == TAG_SUSPENSION_43, 'tag 43');
    assert((*real.figures.at(0)).primary_interval == 4, 'starts 4');
    assert((*real.figures.at(1)).primary_interval == 3, 'resolves 3');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_french_long_five_traits() {
    let real = generate_baroque_cadential_improvisation(32); // family 0, variant 2
    let tr = baroque_traits(@real);
    assert(validate_baroque_realization(@real), 'valid french');
    assert(tr.cadence_type == MODULE_CADENCE_FRENCH_LONG5, 'french cadence');
    assert(tr.texture == TEXTURE_STYLE_BRISE, 'brise texture');
    assert(real.events.len() > real.bass.len(), 'brise adds notes');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_3451_bass_skeleton() {
    let real = generate_baroque_cadential_improvisation(16); // family 0, variant 1
    assert(validate_baroque_realization(@real), 'valid 3451');
    assert(*real.plan.modules.at(0) == MODULE_CADENCE_3451, 'module 3451');
    assert((*real.bass.at(0)).degree0 == 2, 'bass 3');
    assert((*real.bass.at(1)).degree0 == 3, 'bass 4');
    assert((*real.bass.at(2)).degree0 == 4, 'bass 5');
    assert((*real.bass.at(3)).degree0 == 0, 'bass 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_descending_scalar_cadence_basses() {
    let over_3451 = generate_baroque_cadential_improvisation(48); // family 0, variant 3
    assert(validate_baroque_realization(@over_3451), 'valid desc3451');
    assert(*over_3451.plan.modules.at(0) == MODULE_CADENCE_DESC_3451, 'desc 3451');
    assert((*over_3451.bass.at(0)).degree0 == 2, '3451 bass 3');
    assert((*over_3451.bass.at(1)).degree0 == 3, '3451 bass 4');
    assert((*over_3451.bass.at(2)).degree0 == 4, '3451 bass 5');
    assert((*over_3451.bass.at(3)).degree0 == 0, '3451 bass 1');

    let over_4251 = generate_baroque_cadential_improvisation(64); // family 0, variant 4
    assert(validate_baroque_realization(@over_4251), 'valid desc4251');
    assert(*over_4251.plan.modules.at(0) == MODULE_CADENCE_DESC_4251, 'desc 4251');
    assert((*over_4251.bass.at(0)).degree0 == 3, '4251 bass 4');
    assert((*over_4251.bass.at(1)).degree0 == 1, '4251 bass 2');
    assert((*over_4251.bass.at(2)).degree0 == 4, '4251 bass 5');
    assert((*over_4251.bass.at(3)).degree0 == 0, '4251 bass 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_fauxbourdon_76_chain() {
    let real = generate_baroque_cadential_improvisation(1); // family 1, variant 0
    assert(validate_baroque_realization(@real), 'valid fauxbourdon');
    assert(*real.plan.modules.at(0) == MODULE_FAUXBOURDON_76, 'first fauxbourdon');
    let mut found = false;
    let mut i: u32 = 0;
    loop {
        if i >= real.figures.len() {
            break;
        }
        let f = *real.figures.at(i);
        if f.dissonance_tag == TAG_CHAIN_76 {
            assert(f.primary_interval == 7, 'chain starts 7');
            assert((*real.figures.at(i + 1)).primary_interval == 6, 'chain resolves 6');
            found = true;
            break;
        }
        i += 1;
    };
    assert(found, 'found 76 chain');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_romanesca_cells_descend_by_third() {
    let real = generate_baroque_cadential_improvisation(33); // family 1, variant 2
    assert(validate_baroque_realization(@real), 'valid romanesca');
    assert(*real.plan.modules.at(0) == MODULE_ROMANESCA, 'first romanesca');
    let b0 = (*real.bass.at(0)).degree0;
    let b1 = (*real.bass.at(3)).degree0;
    let b2 = (*real.bass.at(6)).degree0;
    assert(b1 == b0 - 2, 'cell 2 down third');
    assert(b2 == b1 - 2, 'cell 3 down third');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_circle_and_ascending_fifths_sequence_routes() {
    let circle = generate_baroque_cadential_improvisation(17); // family 1, variant 1
    assert(validate_baroque_realization(@circle), 'valid circle');
    assert(*circle.plan.modules.at(0) == MODULE_CIRCLE_5THS, 'circle route');
    assert((*circle.bass.at(1)).degree0 == (*circle.bass.at(0)).degree0 - 2, 'third down');
    assert((*circle.bass.at(2)).degree0 == (*circle.bass.at(1)).degree0 + 1, 'step up');

    let ascending = generate_baroque_cadential_improvisation(49); // family 1, variant 3
    assert(validate_baroque_realization(@ascending), 'valid ascending');
    assert(*ascending.plan.modules.at(0) == MODULE_ASCENDING_5THS, 'ascending route');
    assert((*ascending.bass.at(1)).degree0 == (*ascending.bass.at(0)).degree0 + 4, 'up fifth');
    assert((*ascending.bass.at(2)).degree0 == (*ascending.bass.at(1)).degree0 - 3, 'down fourth');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_modular_etude_has_cadenza_doppia_raised_fourth() {
    let real = generate_baroque_cadential_improvisation(2); // family 2
    let tr = baroque_traits(@real);
    assert(validate_baroque_realization(@real), 'valid modular');
    assert(*real.plan.modules.at(1) == MODULE_CADENZA_DOPPIA, 'doppia present');
    assert(tr.modulation_target == 4, 'modulates to V');
    assert((*real.plan.local_keys.at(2)).tonic_pc == ((*real.plan.local_keys.at(0)).tonic_pc + 7) % 12, 'key to V');

    let mut found = false;
    let mut i: u32 = 0;
    loop {
        if i >= real.figures.len() {
            break;
        }
        if (*real.figures.at(i)).dissonance_tag == TAG_RAISED_4 {
            found = true;
            break;
        }
        i += 1;
    };
    assert(found, 'raised fourth tagged');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_minor_policy_routes_through_plan() {
    let real = generate_baroque_cadential_improvisation(0); // low mode bits select natural minor
    let tr = baroque_traits(@real);
    assert(tr.minor_scale_policy == MODE_NATURAL_MINOR, 'natural minor trait');
    assert((*real.plan.local_keys.at(0)).mode_id == MODE_NATURAL_MINOR, 'natural minor key');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_determinism_and_event_sanity() {
    let a = generate_baroque_cadential_improvisation(0x1234);
    let b = generate_baroque_cadential_improvisation(0x1234);
    assert(a.events.len() == b.events.len(), 'same event count');
    let mut i: u32 = 0;
    loop {
        if i >= a.events.len() {
            break;
        }
        let ea = *a.events.at(i);
        let eb = *b.events.at(i);
        assert(ea.time == eb.time, 'same time');
        assert(ea.pitch == eb.pitch, 'same pitch');
        assert(ea.duration > 0, 'positive duration');
        assert(ea.pitch >= 24 && ea.pitch <= 108, 'register sane');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_harmonic_minor_anchor_raises_leading_tone() {
    let key = LocalKey { tonic_pc: 0, mode_id: MODE_HARMONIC_MINOR, degree_offset: 0 };
    let anchors = array![
        MelodyAnchor {
            position: 2,
            target_degree: koji::composition::baroque_improvisation::ScaleDegree {
                degree0: 6, alter: 1,
            },
            anchor_kind: 1,
        },
    ];
    let melody: BaroqueMelody = generate_baroque_melody(17, key, 4, anchors.span());
    assert((*melody.degrees.at(2)).degree0 == 6, 'leading degree');
    assert((*melody.degrees.at(2)).alter == 1, 'raised leading tone');
}

#[test]
#[available_gas(1000000000000)]
fn test_develop_scaffold_preserves_anchors() {
    let key = LocalKey { tonic_pc: 0, mode_id: MODE_MAJOR, degree_offset: 0 };
    let anchors = array![
        MelodyAnchor {
            position: 3,
            target_degree: koji::composition::baroque_improvisation::ScaleDegree {
                degree0: 0, alter: 0,
            },
            anchor_kind: 0,
        },
    ];
    let melody = generate_baroque_melody(99, key, 4, anchors.span());
    let developed = develop_scaffold_melody(0xBEEF, @melody);
    assert(developed.len() == 4, 'developed len');
    assert((*developed.at(3)).degree0 == 0, 'anchor degree kept');
}

#[test]
#[available_gas(1000000000000)]
fn test_baroque_transforms_validate_and_add_passing_tones() {
    let base = generate_baroque_cadential_improvisation(32);
    let with_tr = generate_baroque_cadential_improvisation_with_transforms(32);
    assert(validate_baroque_realization(@with_tr), 'transforms valid');
    assert(with_tr.events.len() >= base.events.len(), 'more events');
    let mut passing: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= with_tr.events.len() {
            break;
        }
        let e = *with_tr.events.at(i);
        if e.voice_id == ROLE_MELODY && e.duration == 2 && e.velocity == 72 {
            passing += 1;
        }
        i += 1;
    };
    assert(passing > 0, 'passing tones added');
}

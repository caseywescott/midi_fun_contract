use core::array::ArrayTrait;
use koji::composition::symmetry_engine::{
    add_pitch, build_pitch_world_from_mask, classify_density, count_pitches,
    find_min_symmetry_step, generate_orbit, generate_symmetry_composition,
    generate_symmetry_composition_from_seed, generate_symmetry_material,
    generate_symmetry_material_from_seed, generate_world_chord, generate_world_from_orbits,
    generate_world_motif, get_pitch_at_index, get_world_by_id, has_pitch, is_symmetric_under,
    is_valid_world_mask, is_world_musically_useful, messiaen_mode_mask, quantize_pitch_to_world,
    registry_size, rng_choose_world_id, rng_choose_world_id_filtered, transpose_mask,
    transpose_world, unique_transposition_count, validate_symmetric_mask, world_augmented_triad,
    world_diminished_seventh, world_tritone_pair, world_whole_tone, FAMILY_AUGMENTED,
    FAMILY_DIMINISHED, FAMILY_MESSIAEN, FAMILY_USER_DEFINED, SymmetryCompositionParams,
};

#[test]
#[available_gas(1000000000000)]
fn test_bitmask_ops() {
    let m0 = add_pitch(0, 0);
    assert(has_pitch(m0, 0), 'bit 0');
    assert(!has_pitch(m0, 1), 'no bit 1');

    let m11 = add_pitch(0, 11);
    assert(has_pitch(m11, 11), 'bit 11');
    assert(!has_pitch(m11, 0), 'no bit 0');

    assert(count_pitches(world_diminished_seventh()) == 4, 'dim count');
    assert(count_pitches(world_augmented_triad()) == 3, 'aug count');
}

#[test]
#[available_gas(1000000000000)]
fn test_transpose_mask() {
    let dim = world_diminished_seventh();
    assert(transpose_mask(dim, 3) == dim, 'dim +3');
    assert(transpose_mask(dim, 1) == 1170, 'dim +1');

    let aug = world_augmented_triad();
    assert(transpose_mask(aug, 4) == aug, 'aug +4');

    let whole = world_whole_tone();
    assert(transpose_mask(whole, 2) == whole, 'whole +2');
}

#[test]
#[available_gas(1000000000000)]
fn test_symmetry_detection() {
    let dim = world_diminished_seventh();
    assert(is_symmetric_under(dim, 3), 'dim sym 3');
    assert(!is_symmetric_under(dim, 1), 'dim not sym 1');

    let aug = world_augmented_triad();
    assert(is_symmetric_under(aug, 4), 'aug sym 4');

    let whole = world_whole_tone();
    assert(is_symmetric_under(whole, 2), 'whole sym 2');

    assert(find_min_symmetry_step(dim) == 3, 'dim min step');
    assert(find_min_symmetry_step(aug) == 4, 'aug min step');
    assert(unique_transposition_count(dim) == 3, 'dim unique');
}

#[test]
#[available_gas(1000000000000)]
fn test_orbit_generation() {
    assert(generate_orbit(0, 3) == world_diminished_seventh(), 'orb 0,3');
    assert(generate_orbit(1, 3) == 1170, 'orb 1,3');
    assert(generate_orbit(0, 4) == world_augmented_triad(), 'orb 0,4');
    assert(generate_orbit(0, 6) == world_tritone_pair(), 'orb 0,6');
}

#[test]
#[available_gas(1000000000000)]
fn test_world_from_orbits() {
    let mut starts: Array<u8> = ArrayTrait::new();
    starts.append(0);
    starts.append(1);
    let mode2 = generate_world_from_orbits(3, starts);
    assert(mode2 == messiaen_mode_mask(2), 'mode2 from orbits');
}

#[test]
#[available_gas(1000000000000)]
fn test_pitch_at_index() {
    let dim = world_diminished_seventh();
    assert(get_pitch_at_index(dim, 0) == 0, 'idx 0');
    assert(get_pitch_at_index(dim, 1) == 3, 'idx 1');
    assert(get_pitch_at_index(dim, 2) == 6, 'idx 2');
    assert(get_pitch_at_index(dim, 3) == 9, 'idx 3');
    assert(get_pitch_at_index(dim, 4) == 0, 'idx wrap');
}

#[test]
#[available_gas(1000000000000)]
fn test_chord_generation() {
    let mode2 = messiaen_mode_mask(2);
    let chord = generate_world_chord(mode2, 0, 2, 4, true);
    assert(chord.len() == 4, 'chord len');
    assert(*chord.at(0) == 0, 'c[0]');
    assert(*chord.at(1) == 3, 'c[1]');
    assert(*chord.at(2) == 6, 'c[2]');
    assert(*chord.at(3) == 9, 'c[3]');
}

#[test]
#[available_gas(1000000000000)]
fn test_chord_deduplication() {
    let dim = world_diminished_seventh();
    let dup = generate_world_chord(dim, 0, 1, 4, true);
    assert(dup.len() == 4, 'dup len');
    let dedup = generate_world_chord(dim, 0, 1, 4, false);
    assert(dedup.len() == 4, 'dedup len');
}

#[test]
#[available_gas(1000000000000)]
fn test_quantize() {
    let mode2 = messiaen_mode_mask(2);
    assert(quantize_pitch_to_world(mode2, 2) == 3, 'q2');
    assert(quantize_pitch_to_world(mode2, 5) == 6, 'q5');
    assert(quantize_pitch_to_world(mode2, 11) == 0, 'q11');
}

#[test]
#[available_gas(1000000000000)]
fn test_messiaen_presets() {
    assert(messiaen_mode_mask(1) == world_whole_tone(), 'm1=whole');
    assert(count_pitches(messiaen_mode_mask(2)) == 8, 'm2 size');
    assert(count_pitches(messiaen_mode_mask(7)) == 10, 'm7 size');
}

#[test]
#[available_gas(1000000000000)]
fn test_user_defined_mask() {
    assert(is_valid_world_mask(1749), 'res valid');
    assert(!validate_symmetric_mask(1749), 'res not sym');
    assert(validate_symmetric_mask(world_diminished_seventh()), 'dim sym');
    let custom = build_pitch_world_from_mask(world_augmented_triad(), FAMILY_AUGMENTED);
    assert(custom.pitch_count == 3, 'custom count');
    assert(custom.symmetry_step == 4, 'custom step');
}

#[test]
#[available_gas(1000000000000)]
fn test_quality_filters() {
    let tritone = get_world_by_id(4);
    assert(!is_world_musically_useful(tritone, false), 'sparse out');
    assert(is_world_musically_useful(tritone, true), 'sparse in');
    let dim = get_world_by_id(1);
    assert(is_world_musically_useful(dim, false), 'dim ok');
    assert(classify_density(4) == 3, 'tetradic');
    assert(classify_density(8) == 5, 'rich modal');
}

#[test]
#[available_gas(1000000000000)]
fn test_registry() {
    assert(registry_size() == 49, 'registry size');
    let w1 = get_world_by_id(1);
    assert(w1.mask == world_diminished_seventh(), 'w1 mask');
    assert(w1.family_id == FAMILY_DIMINISHED, 'w1 family');
    assert(w1.symmetry_step == 3, 'w1 step');

    let w6 = get_world_by_id(6);
    assert(w6.family_id == FAMILY_MESSIAEN, 'w6 family');
    assert(w6.mask == messiaen_mode_mask(2), 'w6 mask');

    let w13 = get_world_by_id(13);
    assert(w13.default_transposition == 1, 'w13 dt');
    assert(w13.mask != w6.mask, 'w13 transposed');

    let w16 = get_world_by_id(16);
    assert(w16.family_id == FAMILY_USER_DEFINED, 'w16 family');
    assert(w16.symmetry_step == 0, 'w16 no sym');

    let w49 = get_world_by_id(49);
    assert(w49.pitch_count == 12, 'chromatic');
}

#[test]
#[available_gas(1000000000000)]
fn test_transpose_world() {
    let world = get_world_by_id(6);
    let t0 = transpose_world(world, 0);
    assert(t0.mask == world.mask, 't0 same');
    let t3 = transpose_world(world, 3);
    assert(t3.mask == world.mask, 't3 wraps mode2');
    let t1 = transpose_world(world, 1);
    assert(t1.mask != world.mask, 't1 differs');
}

#[test]
#[available_gas(1000000000000)]
fn test_motif_deterministic() {
    let seed: felt252 = 42;
    let mask = messiaen_mode_mask(2);
    let m1 = generate_world_motif(seed, mask, 8);
    let m2 = generate_world_motif(seed, mask, 8);
    assert(m1.len() == 8, 'motif len');
    assert(*m1.at(0) == *m2.at(0), 'motif stable');
}

#[test]
#[available_gas(1000000000000)]
fn test_rng_filtered() {
    let seed: felt252 = 99;
    let id = rng_choose_world_id(seed);
    let world = get_world_by_id(id);
    assert(is_world_musically_useful(world, false), 'rng useful');
    assert(world.family_id != FAMILY_USER_DEFINED, 'no color preset');
    let sparse = rng_choose_world_id_filtered(seed, true, true);
    assert(sparse >= 1 && sparse <= registry_size(), 'sparse range');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_material() {
    let mat = generate_symmetry_material_from_seed(12345);
    assert(mat.world_id >= 1 && mat.world_id <= registry_size(), 'world range');
    assert(mat.melody_pitch_classes.len() >= 4, 'melody len');
    assert(mat.chord_pitch_classes.len() >= 3, 'chord len');

    let params = SymmetryCompositionParams {
        seed: 7,
        world_id: 6,
        world_transposition: 0,
        motif_length: 4,
        chord_start_index: 0,
        chord_skip: 2,
        chord_size: 4,
        rhythmic_cycle_length: 12,
    };
    let mat2 = generate_symmetry_material(params);
    assert(mat2.chord_pitch_classes.len() == 4, 'params chord');
    assert(*mat2.chord_pitch_classes.at(0) == 0, 'params c0');
}

#[test]
#[available_gas(1000000000000)]
fn test_combined_composition() {
    let comp = generate_symmetry_composition_from_seed(777);
    assert(comp.rhythmic_cycle_length > 0, 'cycle len');
    assert(comp.pitch_material.melody_pitch_classes.len() >= 4, 'motif');
    assert(comp.voice_motifs.len() > 0, 'voice motifs');

    let params = SymmetryCompositionParams {
        seed: 100,
        world_id: 1,
        world_transposition: 0,
        motif_length: 8,
        chord_start_index: 0,
        chord_skip: 2,
        chord_size: 4,
        rhythmic_cycle_length: 12,
    };
    let comp2 = generate_symmetry_composition(params);
    assert(comp2.rhythmic_cycle_length == 12, 'fixed cycle');
}

#[test]
#[available_gas(1000000000000)]
fn test_fixture_seed_12345_deterministic() {
    let seed: felt252 = 12345;
    let m1 = generate_symmetry_material_from_seed(seed);
    let m2 = generate_symmetry_material_from_seed(seed);
    assert(m1.world_id == m2.world_id, 'fixture world stable');
    assert(m1.melody_pitch_classes.len() == m2.melody_pitch_classes.len(), 'fixture len');
    assert(*m1.melody_pitch_classes.at(0) == *m2.melody_pitch_classes.at(0), 'fixture pc0');
}

#[test]
#[available_gas(1000000000000)]
fn test_fixture_golden_vectors() {
    // fixtures/v1/symmetry_engine.json
    let seed: felt252 = 12345;
    let mat = generate_symmetry_material_from_seed(seed);
    assert(mat.world_id == 12, 'v12345 world');
    assert(mat.world_mask == 2925, 'v12345 mask');
    assert(mat.melody_pitch_classes.len() == 4, 'v12345 motif');

    let seed777: felt252 = 777;
    let mat777 = generate_symmetry_material_from_seed(seed777);
    assert(mat777.world_id == 11, 'v777 world');
    assert(get_world_by_id(11).mask == 3055, 'v777 base mask');
}

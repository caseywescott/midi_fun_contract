use core::array::ArrayTrait;
use koji::composition::messiaen_modes::{
    generate_chord, generate_diminished_symmetry_chord, generate_messiaen_material,
    generate_resonance_chord, get_mode_pitch_at, get_mode_size, get_transposed_mode_pitch_at,
    get_transposition_count, is_pitch_in_mode, quantize_pitch_to_mode, rng_choose_mode,
    rng_generate_chord_params, transpose_pitch,
};

#[test]
#[available_gas(1000000000000)]
fn test_mode_lookup() {
    assert(get_mode_pitch_at(1, 0) == 0, 'm1 i0');
    assert(get_mode_pitch_at(1, 5) == 10, 'm1 i5');
    assert(get_mode_pitch_at(1, 6) == 0, 'm1 wrap');

    assert(get_mode_pitch_at(2, 0) == 0, 'm2 i0');
    assert(get_mode_pitch_at(2, 7) == 10, 'm2 i7');
    assert(get_mode_pitch_at(2, 8) == 0, 'm2 wrap');

    assert(get_mode_size(2) == 8, 'm2 size');
    assert(get_transposition_count(2) == 3, 'm2 tcount');
}

#[test]
#[available_gas(1000000000000)]
fn test_transpose_pitch() {
    assert(transpose_pitch(11, 1) == 0, 't11+1');
    assert(transpose_pitch(10, 4) == 2, 't10+4');
}

#[test]
#[available_gas(1000000000000)]
fn test_mode2_chords() {
    let c1 = generate_chord(2, 0, 0, 2, 4);
    assert(c1.len() == 4, 'c1 len');
    assert(*c1.at(0) == 0, 'c1[0]');
    assert(*c1.at(1) == 3, 'c1[1]');
    assert(*c1.at(2) == 6, 'c1[2]');
    assert(*c1.at(3) == 9, 'c1[3]');

    let c2 = generate_chord(2, 0, 1, 2, 5);
    assert(c2.len() == 5, 'c2 len');
    assert(*c2.at(0) == 1, 'c2[0]');
    assert(*c2.at(1) == 4, 'c2[1]');
    assert(*c2.at(2) == 7, 'c2[2]');
    assert(*c2.at(3) == 10, 'c2[3]');
    // index (1 + 4*2) % 8 = 1 → pitch class 1 (spec example lists 0; formula yields 1)
    assert(*c2.at(4) == 1, 'c2[4]');
}

#[test]
#[available_gas(1000000000000)]
fn test_limited_transposition_wrapping() {
    assert(get_transposition_count(2) == 3, 'm2 tc');
    assert(get_transposed_mode_pitch_at(2, 3, 0) == 0, 't3->0');
    assert(get_transposed_mode_pitch_at(2, 4, 0) == 1, 't4->1');
}

#[test]
#[available_gas(1000000000000)]
fn test_quantize() {
    assert(quantize_pitch_to_mode(2, 2, 0) == 3, 'q2');
    assert(quantize_pitch_to_mode(5, 2, 0) == 6, 'q5');
    assert(quantize_pitch_to_mode(11, 2, 0) == 0, 'q11');
}

#[test]
#[available_gas(1000000000000)]
fn test_membership() {
    assert(is_pitch_in_mode(3, 2, 0), 'in 3');
    assert(!is_pitch_in_mode(2, 2, 0), 'out 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_presets() {
    let dim = generate_diminished_symmetry_chord(0, 0);
    assert(*dim.at(0) == 0 && *dim.at(3) == 9, 'dim');

    let res = generate_resonance_chord(0);
    assert(res.len() == 7, 'res len');
    assert(*res.at(0) == 0 && *res.at(1) == 4 && *res.at(3) == 10, 'res pcs');
}

#[test]
#[available_gas(1000000000000)]
fn test_rng_deterministic() {
    let seed: felt252 = 42;
    assert(rng_choose_mode(seed) == rng_choose_mode(seed), 'mode stable');
    let p1 = rng_generate_chord_params(seed);
    let p2 = rng_generate_chord_params(seed);
    assert(p1.mode_id == p2.mode_id, 'params stable');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_material() {
    let mat = generate_messiaen_material(99);
    assert(mat.mode_id >= 1 && mat.mode_id <= 7, 'mode range');
    assert(mat.melody_pitch_classes.len() >= 16, 'melody len');
    assert(mat.chord_pitch_classes.len() >= 3, 'chord len');
}

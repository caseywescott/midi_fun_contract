//! Canon rules: which diatonic interval classes are consonant, compound intervals reduced to
//! their class, and `abs_i32`.

use crate::composition::canon_rules::{abs_i32, generic_class, is_consonant_class};

#[test]
#[available_gas(1000000000000)]
fn test_consonant_classes() {
    assert(is_consonant_class(0), 'unison consonant');
    assert(is_consonant_class(2), '3rd consonant');
    assert(is_consonant_class(4), '5th consonant');
    assert(is_consonant_class(5), '6th consonant');
    assert(!is_consonant_class(1), '2nd dissonant');
    assert(!is_consonant_class(3), '4th dissonant');
    assert(!is_consonant_class(6), '7th dissonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_reduction() {
    // 11th = 10 diatonic steps → 4th → dissonant; 12th = 11 → 5th → consonant.
    assert(generic_class(0, 10) == 3, '11th reduces to 4th');
    assert(!is_consonant_class(generic_class(0, 10)), '11th dissonant');
    assert(generic_class(0, 11) == 4, '12th reduces to 5th');
    assert(is_consonant_class(generic_class(0, 11)), '12th consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_abs_i32() {
    assert(abs_i32(-4) == 4, 'abs -4');
    assert(abs_i32(7) == 7, 'abs 7');
    assert(abs_i32(0) == 0, 'abs 0');
}

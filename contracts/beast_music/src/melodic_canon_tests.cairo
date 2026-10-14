//! Scale degrees to MIDI keys (`degree_to_keynum` over `mode_scale`), across octaves.

use crate::composition::melodic_canon::{degree_to_keynum, mode_scale};

#[test]
#[available_gas(1000000000000)]
fn test_degree_to_keynum_ionian() {
    let scale = mode_scale(0); // Ionian
    assert(degree_to_keynum(0, 60, scale) == 60, 'deg 0 == tonic');
    assert(degree_to_keynum(7, 60, scale) == 72, 'deg +7 == octave up');
    assert(degree_to_keynum(-7, 60, scale) == 48, 'deg -7 == octave down');
    assert(degree_to_keynum(2, 60, scale) == 64, 'deg +2 == major 3rd');
    assert(degree_to_keynum(4, 60, scale) == 67, 'deg +4 == 5th');
}

#[test]
#[available_gas(1000000000000)]
fn test_degree_to_keynum_negative_below_tonic() {
    let scale = mode_scale(0);
    // degree -1 from C = B below = 59
    assert(degree_to_keynum(-1, 60, scale) == 59, 'deg -1 == 7th below');
}

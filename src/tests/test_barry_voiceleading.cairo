use core::traits::TryInto;
use koji::composition::barry_harris::{normalize_pc, voicelead};

#[test]
fn test_voicelead_minimizes_motion() {
    let prev = array![60_i16, 64, 67, 71].span();
    let target = array![0_u8, 4, 7, 11].span();
    let out = voicelead(prev, target, 48, 72, 0);
    assert(out.len() == 4, 'four voices');
    assert(*out.at(0) >= 48, 'in range');
    assert(*out.at(0) <= 72, 'in range');
    let kn: u32 = (*out.at(0)).try_into().unwrap();
    assert(normalize_pc(kn) == 0, 'C pc');
}

#[test]
fn test_voicelead_empty_previous() {
    let target = array![0_u8, 4, 7].span();
    let out = voicelead(array![].span(), target, 60, 72, 7);
    assert(out.len() == 3, 'three voices');
}

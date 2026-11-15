use crate::common::{RngTrait, fold64, mix, purchase_seed};
use crate::species::{LOOT_FIRST, loot_species};

#[test]
fn rng_matches_js() {
    let mut r = RngTrait::new(12345);
    assert_eq!(r.next(), 4207900869);
    assert_eq!(r.next(), 1317490944);
    assert_eq!(r.next(), 2079646450);
    assert_eq!(r.next(), 3513001552);
    let mut r2 = RngTrait::new(0xdeadbeef);
    assert_eq!(r2.int(7), 6);
    assert_eq!(r2.int(1000), 267);
}

#[test]
fn mix_and_seeds_match_js() {
    assert_eq!(mix(76, 977 * 3 + 13), 1987016915);
    assert_eq!(mix(0xffffffff, 5), 1253290172);
    assert_eq!(purchase_seed(1), 16294208416658607535);
    assert_eq!(purchase_seed(7), 3207296026000306913);
    assert_eq!(fold64(0x1_0000_0003), 2);
}

#[test]
fn species_table() {
    let s = loot_species(LOOT_FIRST);
    assert_eq!(s.id, 76);
    assert_eq!(s.degrees, [0, 1, 3, 5, 3, 4]);
}

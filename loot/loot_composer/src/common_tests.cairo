use crate::common::{GlissNote, GlissPlan, RngTrait, fold64, gliss_plan, glissando, mix, purchase_seed};
use crate::species::{LOOT_FIRST, loot_species, musical_id};

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
    assert_eq!(s.id, 78);
    assert_eq!(s.degrees, [0, 1, 3, 5, 3, 4]);
}

#[test]
fn gliss_matches_js() {
    let p = gliss_plan(12, 0xabcdef12, [3, 3, 1, 0, 2].span()).unwrap();
    assert_eq!(p, GlissPlan { spot: 0, up: true, high: true });
    let n = glissando(p, 5000, 960, 0xabcdef12, 5480);
    assert_eq!(n.len(), 16);
    assert_eq!(*n.at(0), GlissNote { t: 4040, len: 360, d: 0, v: 61 });
    assert_eq!(*n.at(1), GlissNote { t: 4100, len: 360, d: 1, v: 54 });
    assert_eq!(*n.at(15), GlissNote { t: 4940, len: 360, d: 15, v: 51 });
    let p2 = gliss_plan(19, 123456789, [0, 1, 3, 3, 2].span()).unwrap();
    assert_eq!(p2, GlissPlan { spot: 2, up: false, high: true });
    let n2 = glissando(p2, 5000, 960, 123456789, 5480);
    assert_eq!(*n2.at(0), GlissNote { t: 4040, len: 360, d: 15, v: 50 });
    assert_eq!(*n2.at(15), GlissNote { t: 4940, len: 360, d: 0, v: 59 });
    assert!(gliss_plan(5, 1, [0, 2, 3, 3, 1].span()).is_none());
}

#[test]
fn species_allocation_boundaries() {
    assert_eq!(musical_id(78), 76);
    assert_eq!(musical_id(107), 105);
    let last = loot_species(107);
    assert_eq!(last.id, 107);
    assert_eq!(last.tier, 5);
    assert_eq!(last.beast_type, 2);
}

#[test]
#[should_panic(expected: 'not a Loot Beast')]
fn preceding_beast_is_not_a_loot_species() { loot_species(77); }

#[test]
#[should_panic(expected: 'not a Loot Beast')]
fn following_beast_is_not_a_loot_species() { loot_species(108); }

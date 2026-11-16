// Played paths (band, lift and TOP_SOFT written into the tracks) against orchestrating the written
// file and walking it for TOP_SOFT, as the provider did.
use beast_composer::composition::drift::{DriftClock, layered_drift};
use crate::checks::{sound_check_played_byte_array, sound_check_smf_bytes};
use crate::common::purchase_seed;
use crate::orchestra::{has_soft, orchestrate, round_band, top_soft_byte_array};
use crate::rounds::{Play, round_played_byte_array, round_smf_bytes};
use crate::species::{loot_species, musical_id};

fn round_same(species: u32, mega: bool, purchase: u64, clock: Option<DriftClock>) {
    let d = match clock {
        Option::Some(c) => Option::Some(layered_drift(musical_id(species).into(), 0, 0, c)),
        Option::None => Option::None,
    };
    let seed = purchase_seed(purchase);
    let b = round_band(loot_species(species).beast_type, species, d);
    let old = orchestrate(round_smf_bytes(species, mega, seed, d).span(), b.span(), 7, array![].span(), 0);
    let old = top_soft_byte_array(old.span(), b.span());
    let new = round_played_byte_array(
        species, mega, seed, d, Play { band: b.span(), lift: 7, soft: has_soft(b.span()) },
    );
    assert!(old == new, "round {} differs", species);
}

fn check_same(species: u32, mega: bool, take: u64) {
    let seed = purchase_seed(take);
    let b = round_band(loot_species(species).beast_type, species, Option::None);
    let old = orchestrate(sound_check_smf_bytes(species, mega, seed).span(), b.span(), 0, array![].span(), 0);
    let old = top_soft_byte_array(old.span(), b.span());
    let new = sound_check_played_byte_array(species, mega, seed, Play { band: b.span(), lift: 0, soft: has_soft(b.span()) });
    assert!(old == new, "check {} differs", species);
}

#[test]
#[ignore]
fn played_rounds_0() {
    round_same(79, false, 1, Option::None);
    round_same(82, true, 2, Option::None);
}

#[test]
#[ignore]
fn played_rounds_1() {
    round_same(88, false, 5, Option::Some(DriftClock { day: 45, day_hash: 0x2956ffbf266d21c7d5e01968335e1bab126495564d8dcf5a92c5b14507e72c6, week_hash: 0x52e10e4521547a4ed4aa421ffc96e651368b640e0f5998520234a674eb594dc, month_hash: 0x3b2372967bbbc009fcabee385f9fd3a22c32d4f5cd9f29b6b424a25ea8b9ec3 }));
    round_same(95, true, 9, Option::Some(DriftClock { day: 290, day_hash: 0x751b50a16a83719e77709e3993d8e7647a1369f95c1ff67af8612ec4847fede, week_hash: 0x5df86804762153ce15b694cff782ea1b150ea9168b47ac3480b91c366f49920, month_hash: 0x58e4df17f5c690f07fa000d1ab0463862d39799a04d559de783506519689c7f }));
}

#[test]
#[ignore]
fn played_rounds_2() {
    round_same(99, false, 12, Option::None);
    round_same(103, true, 4, Option::Some(DriftClock { day: 45, day_hash: 0x2956ffbf266d21c7d5e01968335e1bab126495564d8dcf5a92c5b14507e72c6, week_hash: 0x52e10e4521547a4ed4aa421ffc96e651368b640e0f5998520234a674eb594dc, month_hash: 0x3b2372967bbbc009fcabee385f9fd3a22c32d4f5cd9f29b6b424a25ea8b9ec3 }));
}

#[test]
#[ignore]
fn played_rounds_3() {
    round_same(106, false, 7, Option::Some(DriftClock { day: 290, day_hash: 0x751b50a16a83719e77709e3993d8e7647a1369f95c1ff67af8612ec4847fede, week_hash: 0x5df86804762153ce15b694cff782ea1b150ea9168b47ac3480b91c366f49920, month_hash: 0x58e4df17f5c690f07fa000d1ab0463862d39799a04d559de783506519689c7f }));
    round_same(107, true, 3, Option::None);
}

#[test]
#[ignore]
fn played_checks_0() {
    check_same(80, false, 1);
    check_same(84, true, 2);
    check_same(90, false, 6);
}

#[test]
#[ignore]
fn played_checks_1() {
    check_same(97, true, 11);
    check_same(101, false, 3);
    check_same(105, true, 8);
}

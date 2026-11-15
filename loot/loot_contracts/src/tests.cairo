//! LootSound end to end: deploy the front with the classes declared, call it as a client would, and
//! compare the files with the lab's (checksums from scripts/songs_parity.mjs).
use beast_composer::composition::drift::DriftClock;
use core::num::traits::{WrappingAdd, WrappingMul};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use crate::interfaces::{ILootSoundDispatcher, ILootSoundDispatcherTrait};

/// The lab's checksum over a file's bytes (h * 31 + b, 32 bits) and its length.
pub fn sum(x: @ByteArray) -> (u32, u32) {
    let mut h: u32 = 0;
    let mut i = 0;
    while i != x.len() {
        h = h.wrapping_mul(31).wrapping_add(x.at(i).unwrap().into());
        i += 1;
    }
    (x.len(), h)
}

pub fn deploy(edition_class: felt252, round_class: felt252) -> ILootSoundDispatcher {
    let song = declare("LootSongComposer").unwrap().contract_class().class_hash;
    let pack: ContractAddress = 0x1234.try_into().unwrap();
    let edition = if edition_class == 0 {
        song.into()
    } else {
        edition_class
    };
    let round = if round_class == 0 {
        song.into()
    } else {
        round_class
    };
    let front = declare("LootSound").unwrap().contract_class();
    let (addr, _) = front.deploy(@array![song.into(), edition, round, pack.into()]).unwrap();
    ILootSoundDispatcher { contract_address: addr }
}

#[test]
fn species_song_through_the_front() {
    let s = deploy(0, 0);
    assert_eq!(sum(@s.species_song(76, false, Option::None)), (4861, 4282407724));
    assert_eq!(s.sound_pack(), 0x1234.try_into().unwrap());
}

#[test]
fn name_song_and_drift_through_the_front() {
    let s = deploy(0, 0);
    assert_eq!(sum(@s.name_song(90, false, 1242, Option::None)), (3522, 4065962252));
    let clock = DriftClock {
        day: 45,
        day_hash: 0x2956ffbf266d21c7d5e01968335e1bab126495564d8dcf5a92c5b14507e72c6,
        week_hash: 0x52e10e4521547a4ed4aa421ffc96e651368b640e0f5998520234a674eb594dc,
        month_hash: 0x3b2372967bbbc009fcabee385f9fd3a22c32d4f5cd9f29b6b424a25ea8b9ec3,
    };
    assert_eq!(sum(@s.species_song(80, false, Option::Some(clock))), (2439, 1886200172));
}

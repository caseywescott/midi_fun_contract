//! LootMidiProvider end to end: declare the classes (the pinned v1.1.0 BeastPureComposer included),
//! deploy the provider and call it as a client would.
use core::num::traits::{WrappingAdd, WrappingMul};
use openzeppelin_interfaces::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};
use starknet::{ClassHash, ContractAddress};
use crate::interfaces::{
    IBeastPureComposerDispatcherTrait, ILootMidiProviderDispatcher, ILootMidiProviderDispatcherTrait,
};

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

pub const BEAST_PURE_COMPOSER_V110: felt252 =
    0x07eb6480204a1367381b782116e6a3d6dedd8fb8b03535ca453e5c681002eb63;

pub fn owner() -> ContractAddress {
    0x0a11ce.try_into().unwrap()
}

pub fn deploy() -> ILootMidiProviderDispatcher {
    let composer = declare("LootPureComposer").unwrap().contract_class().class_hash;
    let song = declare("BeastPureComposer").unwrap().contract_class().class_hash;
    let pack: ContractAddress = 0x1234.try_into().unwrap();
    let provider = declare("LootMidiProvider").unwrap().contract_class();
    let (addr, _) = provider
        .deploy(@array![composer.into(), song.into(), pack.into(), owner().into()])
        .unwrap();
    ILootMidiProviderDispatcher { contract_address: addr }
}

#[test]
fn the_song_class_is_the_v110_release() {
    let s = deploy();
    let want: ClassHash = BEAST_PURE_COMPOSER_V110.try_into().unwrap();
    assert_eq!(s.get_song_class(), want);
    assert_eq!(s.sound_pack(), 0x1234.try_into().unwrap());
    assert_eq!(IOwnableDispatcher { contract_address: s.contract_address }.owner(), owner());
}

#[test]
#[should_panic]
fn only_the_owner_sets_classes() {
    let s = deploy();
    let c = s.get_composer_class();
    s.set_classes(c, c, 0x1.try_into().unwrap());
}

#[test]
fn the_owner_sets_classes() {
    let s = deploy();
    let c = s.get_composer_class();
    start_cheat_caller_address(s.contract_address, owner());
    s.set_classes(c, c, 0x1.try_into().unwrap());
    assert_eq!(s.get_song_class(), c);
}

/// A song with sound effects through the provider is the pinned class's own performed file (called
/// directly here), given the lab's band, lift, LEAD_SOFT and TOP_SOFT.
fn performed_song_matches(species: u32, name: u16, sound_effects: u8) {
    let s = deploy();
    let (prefix, suffix) = loot_composer::songs::name_from_variant(name);
    let beast = crate::provider::loot_beast(species, prefix, suffix);
    let inputs = beast_composer::inputs::ComposerInputs::Song(
        beast_composer::composition::genesis::genesis_song_inputs(beast, prefix, suffix, 0, Option::None),
    );
    let (addr, _) = declare("BeastPureComposer").unwrap().contract_class().deploy(@array![]).unwrap();
    let direct = crate::interfaces::IBeastPureComposerDispatcher { contract_address: addr }
        .compose(inputs, sound_effects);
    let band = loot_composer::orchestra::song_band(
        loot_composer::species::loot_species(species).beast_type, species, Option::None,
    );
    let played = loot_composer::orchestra::orchestrate(
        loot_composer::orchestra::byte_array_bytes(@direct.midi).span(),
        band.span(),
        if name == 0 {
            0
        } else {
            12
        },
    );
    // and LEAD_SOFT and TOP_SOFT, as the lab plays it
    let want = loot_composer::orchestra::top_soft_byte_array(
        played.span(), band.span(), loot_composer::orchestra::lead_soft(*band.at(0)),
    );
    let got = s
        .compose(crate::interfaces::LootInputs::Song(crate::interfaces::LootSongInputs { species, name }), sound_effects);
    assert!(got == want, "performed song differs");
}

#[test]
#[ignore]
fn mega_species_song() {
    performed_song_matches(84, 0, 1);
}

#[test]
#[ignore]
fn mega_echo_name_song() {
    performed_song_matches(99, 300, 3);
}

#[test]
#[should_panic]
fn sound_effects_above_3_revert() {
    let s = deploy();
    s
        .compose(
            crate::interfaces::LootInputs::SoundCheck(
                crate::interfaces::LootSoundCheckInputs { species: 80, take: 0 },
            ),
            4,
        );
}

//! BeastMidiProvider against mock Beasts NFT and Death Mountain contracts.

use beast_music::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, encode_v3_token_id, v3_score_full_midi,
};
use core::dict::{Felt252Dict, Felt252DictTrait};
use midi_provider::synth::{ISynthSettingsProviderDispatcher, ISynthSettingsProviderDispatcherTrait};
use midi_provider::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
use starknet::syscalls::deploy_syscall;
use starknet::{ClassHash, ContractAddress};
use crate::provider::{
    BeastMidiProvider, IBeastMidiProviderDispatcher, IBeastMidiProviderDispatcherTrait, StateSource,
};

#[starknet::interface]
pub trait IMockBeasts<T> {
    fn mint(ref self: T, token_id: u256, rank: u16);
    fn set_rank(ref self: T, token_id: u256, rank: u16);
    fn set_species_count(ref self: T, beast_id: u64, count: u16);
    fn set_kills(ref self: T, token_id: u256, kills: u64);
    fn set_cached_kills(ref self: T, token_id: u256, kills: u64);
    fn set_death_mountain(ref self: T, death_mountain: ContractAddress);
}

/// The Beasts V3 getters the provider uses, with the same owned-token checks. `token_uri` panics:
/// the provider must never call it.
#[starknet::contract]
pub mod MockBeasts {
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use crate::provider::{BeastCachedStats, IBeastsLiveState};

    #[storage]
    struct Storage {
        minted: Map<u256, bool>,
        rank: Map<u256, u16>,
        species_count: Map<u64, u16>,
        kills: Map<u256, u64>,
        cached_kills: Map<u256, u64>,
        death_mountain: ContractAddress,
    }

    #[abi(embed_v0)]
    impl LiveState of IBeastsLiveState<ContractState> {
        fn get_beast_rank(self: @ContractState, token_id: u256) -> u16 {
            assert(self.minted.read(token_id), 'ERC721: invalid token ID');
            self.rank.read(token_id)
        }
        fn get_species_count(self: @ContractState, beast_id: u64) -> u16 {
            self.species_count.read(beast_id)
        }
        fn get_adventurers_killed(self: @ContractState, token_id: u256) -> u64 {
            assert(self.minted.read(token_id), 'ERC721: invalid token ID');
            self.kills.read(token_id)
        }
        fn get_cached_stats(self: @ContractState, token_id: u256) -> BeastCachedStats {
            BeastCachedStats {
                adventurers_killed: self.cached_kills.read(token_id),
                last_killed_by: 0,
                last_killed_timestamp: 0,
            }
        }
        fn get_death_mountain_address(self: @ContractState) -> ContractAddress {
            self.death_mountain.read()
        }
    }

    #[abi(embed_v0)]
    impl Admin of super::IMockBeasts<ContractState> {
        fn mint(ref self: ContractState, token_id: u256, rank: u16) {
            self.minted.write(token_id, true);
            self.rank.write(token_id, rank);
        }
        fn set_rank(ref self: ContractState, token_id: u256, rank: u16) {
            self.rank.write(token_id, rank);
        }
        fn set_species_count(ref self: ContractState, beast_id: u64, count: u16) {
            self.species_count.write(beast_id, count);
        }
        fn set_kills(ref self: ContractState, token_id: u256, kills: u64) {
            self.kills.write(token_id, kills);
        }
        fn set_cached_kills(ref self: ContractState, token_id: u256, kills: u64) {
            self.cached_kills.write(token_id, kills);
        }
        fn set_death_mountain(ref self: ContractState, death_mountain: ContractAddress) {
            self.death_mountain.write(death_mountain);
        }
    }

    #[external(v0)]
    fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
        panic!("provider called token_uri")
    }
}

#[starknet::interface]
pub trait IMockDeathMountain<T> {
    fn set_collects(ref self: T, dungeon: ContractAddress, entity_hash: felt252, count: u64);
}

/// Collect counts keyed by (dungeon, entity hash), like Death Mountain's `CollectableCount`.
#[starknet::contract]
pub mod MockDeathMountain {
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use crate::provider::IDeathMountainCollects;

    #[storage]
    struct Storage {
        collects: Map<(ContractAddress, felt252), u64>,
    }

    #[abi(embed_v0)]
    impl Collects of IDeathMountainCollects<ContractState> {
        fn get_collectable_count(
            self: @ContractState, dungeon: ContractAddress, entity_hash: felt252,
        ) -> u64 {
            self.collects.read((dungeon, entity_hash))
        }
    }

    #[abi(embed_v0)]
    impl Admin of super::IMockDeathMountain<ContractState> {
        fn set_collects(
            ref self: ContractState, dungeon: ContractAddress, entity_hash: felt252, count: u64,
        ) {
            self.collects.write((dungeon, entity_hash), count);
        }
    }
}

#[derive(Drop, Copy)]
struct World {
    nft: IMockBeastsDispatcher,
    dm: IMockDeathMountainDispatcher,
    midi: IMidiProviderDispatcher,
    provider: IBeastMidiProviderDispatcher,
}

fn deploy(class_hash: ClassHash, calldata: Array<felt252>, salt: felt252) -> ContractAddress {
    let (address, _) = deploy_syscall(class_hash, salt, calldata.span(), false).unwrap();
    address
}

fn setup() -> World {
    let nft = deploy(MockBeasts::TEST_CLASS_HASH, array![], 1);
    let dm = deploy(MockDeathMountain::TEST_CLASS_HASH, array![], 2);
    let provider = deploy(BeastMidiProvider::TEST_CLASS_HASH, array![nft.into()], 3);
    let world = World {
        nft: IMockBeastsDispatcher { contract_address: nft },
        dm: IMockDeathMountainDispatcher { contract_address: dm },
        midi: IMidiProviderDispatcher { contract_address: provider },
        provider: IBeastMidiProviderDispatcher { contract_address: provider },
    };
    world.nft.set_death_mountain(dm);
    world
}

fn entity_hash(b: PackableBeastV3) -> felt252 {
    core::poseidon::poseidon_hash_span(array![b.id.into(), b.prefix.into(), b.suffix.into()].span())
}

/// Puts `live` on the mocks the way the real contracts hold it (scars as collects - 1). Death
/// Mountain keys collects by the dungeon argument, and Beasts NFTs pass Death Mountain's own
/// address there.
fn set_state(w: World, b: PackableBeastV3, live: BeastV3LiveState) -> u256 {
    let token_id = encode_v3_token_id(b);
    w.nft.mint(token_id, live.rank);
    w.nft.set_species_count(b.id, live.species_count);
    if b.id <= 75 {
        w.nft.set_kills(token_id, live.adventurers_killed);
        let collects = if b.prefix == 0 {
            0
        } else {
            live.scars + 1
        };
        w.dm.set_collects(w.dm.contract_address, entity_hash(b), collects);
    } else {
        w.nft.set_cached_kills(token_id, live.adventurers_killed);
    }
    token_id
}

/// The existing composer's `[byte_len, 31-byte chunks]` as a ByteArray.
fn composer_midi(b: PackableBeastV3, live: BeastV3LiveState) -> ByteArray {
    let packed = v3_score_full_midi(b, live);
    let len: u32 = (*packed.at(0)).try_into().unwrap();
    let full = len / 31;
    let mut serialized: Array<felt252> = array![full.into()];
    let mut i: u32 = 1;
    while i <= full {
        serialized.append(*packed.at(i));
        i += 1;
    }
    serialized.append(if len % 31 == 0 {
        0
    } else {
        *packed.at(full + 1)
    });
    serialized.append((len % 31).into());
    let mut span = serialized.span();
    Serde::deserialize(ref span).unwrap()
}

fn live(kills: u64, scars: u64, rank: u16, count: u16) -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: kills, scars, summit_held_seconds: 0, rank, species_count: count,
    }
}

fn genesis_warlock() -> PackableBeastV3 {
    PackableBeastV3 {
        id: 1,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 1,
        animated: 1,
        tier: 1,
        beast_type: 0,
    }
}

fn sorrow_peak_warlock() -> PackableBeastV3 {
    PackableBeastV3 {
        id: 1,
        prefix: 57,
        suffix: 15,
        level: 126,
        health: 229,
        shiny: 0,
        animated: 0,
        tier: 1,
        beast_type: 0,
    }
}

fn plain(id: u64, tier: u8, beast_type: u8, shiny: u8, animated: u8) -> PackableBeastV3 {
    PackableBeastV3 {
        id, prefix: 13, suffix: 6, level: 22, health: 60, shiny, animated, tier, beast_type,
    }
}

/// Tier 1, every voice, countersubject and inversion: the largest score the provider can make.
fn heaviest() -> PackableBeastV3 {
    PackableBeastV3 {
        id: 53,
        prefix: 69,
        suffix: 18,
        level: 255,
        health: 1023,
        shiny: 1,
        animated: 1,
        tier: 1,
        beast_type: 2,
    }
}

fn assert_parity(w: World, b: PackableBeastV3, l: BeastV3LiveState) {
    let token_id = set_state(w, b, l);
    let midi = w.midi.get_midi(token_id);
    assert_eq!(midi, composer_midi(b, l));
    // the collection-checked form returns the same bytes
    assert_eq!(w.midi.get_midi_for(w.nft.contract_address, token_id), midi);
}

#[test]
fn genesis_warlock_matches_composer() {
    // Sepolia genesis Warlock 0x7006400010000000000000000001: unranked, species count 0 there.
    let b = genesis_warlock();
    assert_eq!(encode_v3_token_id(b), 0x7006400010000000000000000001);
    assert_parity(setup(), b, live(0, 0, 0, 0));
}

#[test]
fn named_warlock_matches_composer() {
    assert_parity(setup(), sorrow_peak_warlock(), live(2, 12, 1, 954));
}

#[test]
fn rarity_flags_match_composer() {
    let w = setup();
    assert_parity(w, plain(47, 5, 1, 0, 0), live(0, 0, 600, 1100));
    assert_parity(w, plain(48, 5, 1, 1, 0), live(0, 0, 600, 1100));
    assert_parity(w, plain(49, 5, 1, 0, 1), live(0, 0, 600, 1100));
    assert_parity(w, plain(50, 5, 1, 1, 1), live(0, 0, 600, 1100));
}

#[test]
fn live_thresholds_match_composer() {
    let w = setup();
    // kill buckets (sections, extra voice), scar bucket 3 (inversion), crown, rank tiers.
    assert_parity(w, plain(29, 1, 1, 0, 0), live(1, 0, 40, 1200));
    assert_parity(w, plain(30, 2, 1, 0, 0), live(16, 0, 300, 1200));
    assert_parity(w, plain(31, 3, 1, 0, 0), live(5, 8, 2, 1200));
    assert_parity(w, plain(32, 3, 1, 0, 0), live(0, 0, 1, 1200));
}

#[test]
fn community_species_matches_composer() {
    // Agony Bane Gloomfang (species 76, Hunter, tier 3): kills from the NFT's stats cache.
    let b = PackableBeastV3 {
        id: 76,
        prefix: 1,
        suffix: 2,
        level: 10,
        health: 100,
        shiny: 0,
        animated: 1,
        tier: 3,
        beast_type: 1,
    };
    assert_parity(setup(), b, live(7, 0, 1, 1));
}

#[test]
fn heaviest_score_matches_composer() {
    assert_parity(setup(), heaviest(), live(200, 63, 1, 1243));
}

#[test]
fn live_state_changes_change_the_midi() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(2, 0, 30, 954));
    let nft = w.nft.contract_address;
    let calm = w.midi.get_midi_for(nft, token_id);
    assert_eq!(calm, composer_midi(b, live(2, 0, 30, 954)));

    // Later Death Mountain defeats are scars: 9 collects = 8 defeats after the minting one,
    // enough to invert the canon.
    w.dm.set_collects(w.dm.contract_address, entity_hash(b), 9);
    let scarred = w.midi.get_midi_for(nft, token_id);
    assert!(scarred != calm);
    assert_eq!(scarred, composer_midi(b, live(2, 8, 30, 954)));

    // More kills: a new kill bucket.
    w.nft.set_kills(token_id, 40);
    let hunted = w.midi.get_midi_for(nft, token_id);
    assert!(hunted != scarred);
    assert_eq!(hunted, composer_midi(b, live(40, 8, 30, 954)));

    // Taking the species crown.
    w.nft.set_rank(token_id, 1);
    assert_eq!(w.midi.get_midi_for(nft, token_id), composer_midi(b, live(40, 8, 1, 954)));
}

#[test]
fn report_shows_sources() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(3, 4, 7, 954));
    let r = w.provider.get_live_state(w.nft.contract_address, token_id);
    assert_eq!(r.live.adventurers_killed, 3);
    assert_eq!(r.live.scars, 4);
    assert_eq!(r.live.summit_held_seconds, 0);
    assert_eq!(r.live.rank, 7);
    assert_eq!(r.live.species_count, 954);
    assert_eq!(r.adventurers_killed, StateSource::Read);
    assert_eq!(r.scars, StateSource::Read);
    assert_eq!(r.summit_held_seconds, StateSource::Retired);
    assert!(r.complete);
}

#[test]
fn legitimate_zero_is_read() {
    // A fresh genesis token with Death Mountain configured: zero kills, zero collects, species
    // count 0. Every value is real.
    let w = setup();
    let token_id = set_state(w, genesis_warlock(), live(0, 0, 0, 0));
    let r = w.provider.get_live_state(w.nft.contract_address, token_id);
    assert_eq!(r.adventurers_killed, StateSource::Read);
    assert_eq!(r.scars, StateSource::Read);
    assert!(r.complete);
}

#[test]
fn missing_death_mountain_is_unavailable_not_zero() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(25, 6, 9, 954));
    w.nft.set_death_mountain(0.try_into().unwrap());
    let r = w.provider.get_live_state(w.nft.contract_address, token_id);
    assert_eq!(r.adventurers_killed, StateSource::Unavailable);
    assert_eq!(r.scars, StateSource::Unavailable);
    assert!(!r.complete);
    assert_eq!(r.live.adventurers_killed, 0);
    assert_eq!(r.live.scars, 0);
    // Still composes (no revert inside token_uri), from the values it could read.
    assert_eq!(
        w.midi.get_midi_for(w.nft.contract_address, token_id), composer_midi(b, live(0, 0, 9, 954)),
    );
}

#[test]
fn community_species_scars_are_not_tracked() {
    let w = setup();
    let b = PackableBeastV3 {
        id: 76,
        prefix: 1,
        suffix: 2,
        level: 10,
        health: 100,
        shiny: 0,
        animated: 1,
        tier: 3,
        beast_type: 1,
    };
    let token_id = set_state(w, b, live(7, 0, 1, 1));
    // Even if Death Mountain had a record under this hash, it is not this Beast's history.
    w.dm.set_collects(w.dm.contract_address, entity_hash(b), 50);
    let r = w.provider.get_live_state(w.nft.contract_address, token_id);
    assert_eq!(r.adventurers_killed, StateSource::Read);
    assert_eq!(r.scars, StateSource::NotTracked);
    assert_eq!(r.live.scars, 0);
    assert!(r.complete);
}

#[test]
fn reports_collection_and_engine() {
    let w = setup();
    assert_eq!(w.provider.get_collection(), w.nft.contract_address);
    assert_eq!(w.provider.get_engine_version(), 1);
}

#[test]
#[should_panic(expected: ('unsupported collection', 'ENTRYPOINT_FAILED'))]
fn rejects_other_collections() {
    let w = setup();
    let token_id = set_state(w, sorrow_peak_warlock(), live(0, 0, 1, 1));
    w.midi.get_midi_for(w.dm.contract_address, token_id);
}

#[test]
#[should_panic(expected: ('invalid token id', 'ENTRYPOINT_FAILED'))]
fn rejects_invalid_token_ids() {
    let w = setup();
    w.midi.get_midi_for(w.nft.contract_address, 1_u256 * 0x10000000000000000000000000000000);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn rejects_unminted_tokens() {
    let w = setup();
    w.midi.get_midi_for(w.nft.contract_address, encode_v3_token_id(sorrow_peak_warlock()));
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn get_midi_rejects_unminted_tokens() {
    let w = setup();
    w.midi.get_midi(encode_v3_token_id(sorrow_peak_warlock()));
}

#[test]
fn beast_synth_settings_serialize_as_generated() {
    let mut felts: Array<felt252> = array![];
    crate::synth_settings::beast_synth_settings().serialize(ref felts);
    assert_eq!(
        core::poseidon::poseidon_hash_span(felts.span()),
        crate::synth_settings::BEAST_SYNTH_SETTINGS_SERDE_HASH,
    );
}

/// The checks onchain-tinysynth's `settings::validate` applies (at 973f4cf), so `midi_segment`
/// accepts these settings: slots, operator counts, routes, built-in waves only, no filters and the
/// interim engine limits on volume, ratio, sustain, pitch ratio and key scaling.
#[test]
fn beast_synth_settings_pass_the_class_checks() {
    let s = crate::synth_settings::beast_synth_settings();
    assert!(s.quality <= 1 && s.voices >= 1 && s.waves.len() == 0);
    assert!(s.timbres.len() <= 175);
    let mut programs: Felt252Dict<bool> = Default::default();
    for t in s.timbres {
        let key: felt252 = (*t.slot).into() + if *t.drum {
            256
        } else {
            0
        };
        assert!(!programs.get(key), "slot twice");
        programs.insert(key, true);
        if *t.drum {
            assert!(*t.slot >= 35 && *t.slot <= 81);
        } else {
            assert!(*t.slot <= 127);
        }
        let n = t.operators.len();
        assert!(n >= 1 && n <= 8);
        let mut i: u32 = 0;
        for o in t.operators {
            let route: u32 = (*o.route).into();
            if route >= 1 && route <= 10 {
                assert!(route <= i, "FM target");
            } else if route >= 11 {
                assert!(route <= 18 && route - 10 <= i, "AM target");
            }
            match *o.wave {
                midi_provider::synth::Waveform::Custom(_) => panic!("custom wave"),
                _ => {},
            }
            assert!(o.filter.is_none());
            assert!(*o.volume <= 1_000_000 && *o.ratio <= 640_000 && *o.sustain <= 1_000_000);
            assert!(*o.pitch_ratio <= 160_000 && *o.key_scale >= -80_000 && *o.key_scale <= 80_000);
            i += 1;
        }
    }
    // The program the self-contained MIDI selects and the drum notes it plays.
    assert!(
        programs.get(beast_music::composition::full_midi::VOICE_PROGRAM.into()), "program missing",
    );
    for d in array![36_u8, 38, 41, 42, 43, 45, 46, 47, 48, 49, 50] {
        assert!(programs.get(d.into() + 256), "drum missing");
    }
}

#[test]
fn get_settings_serves_the_beast_settings() {
    let w = setup();
    let settings = ISynthSettingsProviderDispatcher { contract_address: w.midi.contract_address };
    let token_id = encode_v3_token_id(sorrow_peak_warlock());
    // The token ID's format only: an unminted token gets the same settings.
    assert_eq!(settings.get_settings(token_id), crate::synth_settings::beast_synth_settings());
    w.nft.mint(token_id, 1);
    assert_eq!(settings.get_settings(token_id), crate::synth_settings::beast_synth_settings());
}

#[test]
#[should_panic(expected: ('invalid token id', 'ENTRYPOINT_FAILED'))]
fn get_settings_rejects_invalid_token_ids() {
    let w = setup();
    ISynthSettingsProviderDispatcher { contract_address: w.midi.contract_address }
        .get_settings(1_u256 * 0x10000000000000000000000000000000);
}

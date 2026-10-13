//! BeastMidiProvider against mock Beasts NFT and Death Mountain contracts.

use beast_music::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, encode_v3_token_id,
};
use beast_music::composition::genesis::genesis_midi;
use core::dict::{Felt252Dict, Felt252DictTrait};
use midi_provider::synth::{
    ISoundProviderDispatcher, ISoundProviderDispatcherTrait, ISynthSettingsProviderDispatcher,
    ISynthSettingsProviderDispatcherTrait, TinySynthSound,
};
use midi_provider::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
use starknet::syscalls::deploy_syscall;
use starknet::{ClassHash, ContractAddress};
use crate::provider::{
    BeastMidiProvider, IBeastMidiProviderDispatcher, IBeastMidiProviderDispatcherTrait,
    IBeastTracksDispatcher, IBeastTracksDispatcherTrait, StateSource,
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

/// The Beast's Genesis Track (`[byte_len, 31-byte chunks]`) as a ByteArray.
fn genesis_track(b: PackableBeastV3) -> ByteArray {
    let packed = genesis_midi(b);
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

/// Tier 1 and shiny: the most sections and channels, plus the mega double and drums.
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
    assert_eq!(midi, genesis_track(b));
    // the collection-checked form returns the same bytes
    assert_eq!(w.midi.get_midi_for(w.nft.contract_address, token_id), midi);
}

#[test]
fn genesis_warlock_plays_its_genesis_track() {
    // Sepolia genesis Warlock 0x7006400010000000000000000001: unranked, species count 0 there.
    let b = genesis_warlock();
    assert_eq!(encode_v3_token_id(b), 0x7006400010000000000000000001);
    assert_parity(setup(), b, live(0, 0, 0, 0));
}

#[test]
fn named_warlock_plays_the_species_track() {
    let w = setup();
    let b = sorrow_peak_warlock();
    assert_parity(w, b, live(2, 12, 1, 954));
    // the name, level and health do not change it: the species' Genesis Track (not shiny here)
    let token_id = encode_v3_token_id(b);
    assert_eq!(
        w.midi.get_midi(token_id), genesis_track(PackableBeastV3 { shiny: 0, ..genesis_warlock() }),
    );
}

#[test]
fn shiny_plays_the_mega_arrangement() {
    let w = setup();
    let normal = set_state(w, plain(47, 5, 1, 0, 0), live(0, 0, 600, 1100));
    let shiny = set_state(w, plain(48, 5, 1, 1, 0), live(0, 0, 600, 1100));
    assert_eq!(w.midi.get_midi(normal), genesis_track(plain(47, 5, 1, 0, 0)));
    assert_eq!(w.midi.get_midi(shiny), genesis_track(plain(48, 5, 1, 1, 0)));
    // animated does not change the track
    assert_parity(w, plain(49, 5, 1, 0, 1), live(0, 0, 600, 1100));
    assert_eq!(genesis_track(plain(49, 5, 1, 0, 1)), genesis_track(plain(49, 5, 1, 0, 0)));
    assert!(genesis_track(plain(49, 5, 1, 1, 0)) != genesis_track(plain(49, 5, 1, 0, 0)));
}

#[test]
fn harpy_and_pegasus_play_each_others_tracks() {
    let w = setup();
    let harpy = plain(39, 4, 1, 0, 0);
    let pegasus = plain(40, 4, 1, 0, 0);
    assert_parity(w, harpy, live(0, 0, 3, 900));
    assert_parity(w, pegasus, live(0, 0, 4, 900));
    let h = w.midi.get_midi(encode_v3_token_id(harpy));
    let p = w.midi.get_midi(encode_v3_token_id(pegasus));
    assert!(h != p);
    // each plays the other species' Genesis Track
    assert_eq!(beast_music::composition::genesis::genesis_swap(39), 40);
    assert_eq!(beast_music::composition::genesis::genesis_swap(40), 39);
}

#[test]
fn community_species_plays_its_genesis_track() {
    // Agony Bane Gloomfang (species 76, Hunter, tier 3): its own tier and type, its own theme.
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
fn heaviest_track_plays() {
    assert_parity(setup(), heaviest(), live(200, 63, 1, 1243));
}

#[test]
fn live_state_does_not_change_the_midi() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(2, 0, 30, 954));
    let nft = w.nft.contract_address;
    let calm = w.midi.get_midi_for(nft, token_id);
    assert_eq!(calm, genesis_track(b));
    w.dm.set_collects(w.dm.contract_address, entity_hash(b), 9);
    w.nft.set_kills(token_id, 40);
    w.nft.set_rank(token_id, 1);
    assert_eq!(w.midi.get_midi_for(nft, token_id), calm);
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
    assert_eq!(w.midi.get_midi_for(w.nft.contract_address, token_id), genesis_track(b));
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

/// The Yeti's two settings serialize to the generated hashes, pass the class checks, and carry the
/// Brute family, its avalanche's Pulse 12.5% Pluck (13), the drums, and the mega leads when mega.
#[test]
fn yeti_synth_settings_are_the_brute_family_and_the_avalanche() {
    for mega in array![false, true] {
        let s = crate::synth_settings::yeti_synth_settings(mega);
        let mut felts: Array<felt252> = array![];
        s.serialize(ref felts);
        assert_eq!(
            core::poseidon::poseidon_hash_span(felts.span()),
            crate::synth_settings::yeti_synth_settings_serde_hash(mega),
        );
        midi_provider::synth::validate(@s);
        let mut slots: Felt252Dict<bool> = Default::default();
        for tb in s.timbres {
            slots.insert(tb.slot.into() + if tb.drum {
                256
            } else {
                0
            }, true);
        }
        for p in beast_music::composition::full_midi::family_leads(2).span() {
            assert!(slots.get((*p).into()), "lead missing");
        }
        for p in beast_music::composition::full_midi::family_plucks(2).span() {
            assert!(slots.get((*p).into()), "pluck missing");
        }
        assert!(slots.get(13), "avalanche preset missing");
        for d in array![36_u8, 38, 42, 45, 46, 47, 48, 49, 50] {
            assert!(slots.get(d.into() + 256), "drum missing");
        }
        for p in beast_music::composition::full_midi::MEGA_LEADS.span() {
            assert_eq!(slots.get((*p).into()), mega);
        }
    }
}

/// The six settings (each type's family, normal and mega) serialize to the hashes the generator
/// computed.
#[test]
fn beast_synth_settings_serialize_as_generated() {
    for t in array![0_u8, 1, 2] {
        for mega in array![false, true] {
            let mut felts: Array<felt252> = array![];
            crate::synth_settings::beast_synth_settings(t, mega).serialize(ref felts);
            assert_eq!(
                core::poseidon::poseidon_hash_span(felts.span()),
                crate::synth_settings::beast_synth_settings_serde_hash(t, mega),
            );
        }
    }
}

/// onchain-midi-player's own `settings::validate` (the checks `midi_segment` applies) accepts every
/// settings value, and each carries everything its Beasts' MIDI can select: the family's leads and
/// plucks, every drum note the groove and fills play, and the mega leads exactly when mega.
#[test]
fn beast_synth_settings_pass_the_class_checks() {
    for t in array![0_u8, 1, 2] {
        for mega in array![false, true] {
            let s = crate::synth_settings::beast_synth_settings(t, mega);
            midi_provider::synth::validate(@s);
            let mut slots: Felt252Dict<bool> = Default::default();
            for tb in s.timbres {
                let key: felt252 = tb.slot.into() + if tb.drum {
                    256
                } else {
                    0
                };
                assert!(!slots.get(key), "slot twice");
                slots.insert(key, true);
            }
            for p in beast_music::composition::full_midi::family_leads(t).span() {
                assert!(slots.get((*p).into()), "family lead missing");
            }
            for p in beast_music::composition::full_midi::family_plucks(t).span() {
                assert!(slots.get((*p).into()), "family pluck missing");
            }
            for d in array![36_u8, 38, 41, 42, 43, 45, 46, 47, 48, 49, 50] {
                assert!(slots.get(d.into() + 256), "drum missing");
            }
            for p in beast_music::composition::full_midi::MEGA_LEADS.span() {
                assert_eq!(slots.get((*p).into()), mega);
            }
        }
    }
}

#[test]
fn get_settings_serves_the_beast_settings() {
    let w = setup();
    let settings = ISynthSettingsProviderDispatcher { contract_address: w.midi.contract_address };
    let b = sorrow_peak_warlock();
    let token_id = encode_v3_token_id(b);
    let expected = crate::synth_settings::beast_synth_settings(b.beast_type, b.shiny == 1);
    // The token ID's format only: an unminted token gets the same settings.
    assert_eq!(settings.get_settings(token_id), expected);
    w.nft.mint(token_id, 1);
    assert_eq!(settings.get_settings(token_id), expected);
}

#[test]
fn get_settings_serves_settings_by_type_and_shiny() {
    let w = setup();
    let settings = ISynthSettingsProviderDispatcher { contract_address: w.midi.contract_address };
    for t in array![0_u8, 1, 2] {
        for shiny in array![0_u8, 1] {
            let b = PackableBeastV3 { beast_type: t, shiny, ..sorrow_peak_warlock() };
            assert_eq!(
                settings.get_settings(encode_v3_token_id(b)),
                crate::synth_settings::beast_synth_settings(t, shiny == 1),
            );
        }
    }
}

#[test]
#[should_panic(expected: ('invalid token id', 'ENTRYPOINT_FAILED'))]
fn get_settings_rejects_invalid_token_ids() {
    let w = setup();
    ISynthSettingsProviderDispatcher { contract_address: w.midi.contract_address }
        .get_settings(1_u256 * 0x10000000000000000000000000000000);
}

/// onchain-midi-player's `ISoundProvider` rule: `get_sound` is `get_midi` and `get_settings` in one
/// call, for a minted Beast with live state.
#[test]
fn get_sound_is_get_midi_and_get_settings() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(40, 8, 1, 954));
    let address = w.midi.contract_address;
    let sound = ISoundProviderDispatcher { contract_address: address }.get_sound(token_id);
    let settings = ISynthSettingsProviderDispatcher { contract_address: address }
        .get_settings(token_id);
    assert_eq!(sound, TinySynthSound { midi: w.midi.get_midi(token_id), settings });
    assert_eq!(sound.midi, genesis_track(b));
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn get_sound_rejects_unminted_tokens() {
    let w = setup();
    ISoundProviderDispatcher { contract_address: w.midi.contract_address }
        .get_sound(encode_v3_token_id(sorrow_peak_warlock()));
}

// ── gas probes (ignored): cairo-test's estimate of one `get_midi` / `get_sound` call is the
// probe minus `gas_probe_baseline` (mock deploys and minting). Run:
//   scarb test -- --include-ignored --filter gas_probe
fn gas_beast(id: u64, shiny: u8) -> PackableBeastV3 {
    PackableBeastV3 {
        id,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny,
        animated: 0,
        tier: beast_music::composition::genesis::species_tier(id),
        beast_type: beast_music::composition::genesis::species_type(id),
    }
}

fn gas_probe(b: PackableBeastV3, call: bool, sound: bool) {
    let w = setup();
    let token_id = set_state(w, b, live(0, 0, 1, 954));
    if call {
        if sound {
            ISoundProviderDispatcher { contract_address: w.midi.contract_address }
                .get_sound(token_id);
        } else {
            w.midi.get_midi(token_id);
        }
    }
}

#[test]
#[ignore]
fn gas_probe_baseline() {
    gas_probe(gas_beast(32, 1), false, false);
}

/// The largest Genesis file: shiny #32 (7,197 bytes, 442 notes; shiny #28 costs slightly more).
#[test]
#[ignore]
fn gas_probe_get_midi_32_shiny() {
    gas_probe(gas_beast(32, 1), true, false);
}

#[test]
#[ignore]
fn gas_probe_get_sound_32_shiny() {
    gas_probe(gas_beast(32, 1), true, true);
}

#[test]
#[ignore]
fn gas_probe_get_midi_32() {
    gas_probe(gas_beast(32, 0), true, false);
}

#[test]
#[ignore]
fn gas_probe_get_midi_warlock() {
    gas_probe(gas_beast(1, 0), true, false);
}

#[test]
#[ignore]
fn gas_probe_get_midi_warlock_shiny() {
    gas_probe(gas_beast(1, 1), true, false);
}

/// The lightest: #21 (1,406 bytes, 74 notes).
#[test]
#[ignore]
fn gas_probe_get_midi_21() {
    gas_probe(gas_beast(21, 0), true, false);
}

/// The old v1.1 get_midi path (live state) on the old heaviest Beast, for comparison: crate call.
#[test]
#[ignore]
fn gas_probe_direct_v11_heaviest() {
    beast_music::composition::beast_v11::v11_score_full_smf_bytes(
        heaviest(), live(200, 63, 1, 1243),
    );
}

#[test]
#[ignore]
fn gas_probe_direct_genesis_32_shiny() {
    beast_music::composition::genesis::genesis_smf_bytes(gas_beast(32, 1));
}

#[test]
#[ignore]
fn gas_probe_direct_nothing() {}

// ── tracks (IBeastTracks)
// ──────────────────────────────────────────────────────────────────────

fn tracks(w: World) -> IBeastTracksDispatcher {
    IBeastTracksDispatcher { contract_address: w.midi.contract_address }
}

fn bytes(b: Array<u8>) -> ByteArray {
    midi_provider::bytes_to_byte_array(b.span())
}

#[test]
fn composer_inputs_are_the_packed_beast() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let inputs = tracks(w).get_composer_inputs(encode_v3_token_id(b));
    let expected = beast_music::composition::params_pack::pack_inputs(
        beast_music::composition::params_pack::composer_inputs(
            b, beast_music::composition::genesis::neutral_live(),
        ),
    );
    assert_eq!(inputs, expected);
}

/// Track 1, the Species Song, is what get_sound plays.
#[test]
fn species_song_is_get_sound() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(3, 1, 2, 40));
    let sound = ISoundProviderDispatcher { contract_address: w.midi.contract_address }
        .get_sound(token_id);
    assert_eq!(tracks(w).get_track_sound(token_id, 1, 0, 0), sound);
}

/// A named Beast's Sound Check, Special Song and a bought track, from the token and from its
/// stored inputs, each with the Beast's own settings.
#[test]
fn tracks_compose_from_the_token_and_from_stored_inputs() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(0, 0, 1, 1));
    let t = tracks(w);
    let inputs = t.get_composer_inputs(token_id);
    let settings = crate::synth_settings::beast_synth_settings(b.beast_type, false);
    let check = t.get_track_sound(token_id, 0, 0, 0);
    assert_eq!(check.midi, bytes(beast_music::composition::sound_check::sound_check_smf_bytes(b)));
    assert_eq!(check.settings, settings);
    let special = t.get_track_sound(token_id, 2, 0, 0);
    assert_eq!(
        special.midi,
        bytes(beast_music::composition::genesis::name_track_smf_bytes(b, b.prefix, b.suffix)),
    );
    assert_eq!(t.get_track_sound_for_inputs(inputs, 2, 0, 0), special);
    let bought = t.get_track_sound(token_id, 3, 0xabc123, 0);
    assert_eq!(
        bought.midi,
        bytes(
            beast_music::composition::genesis::seeded_track_smf_bytes(
                b, b.prefix, b.suffix, 0xabc123,
            ),
        ),
    );
    assert_eq!(bought.settings, settings);
}

/// The Yeti's tracks and get_settings carry its avalanche's preset.
#[test]
fn yeti_tracks_carry_the_avalanche_preset() {
    let w = setup();
    let b = PackableBeastV3 {
        id: 68,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 1,
        animated: 0,
        tier: 4,
        beast_type: 2,
    };
    let token_id = set_state(w, b, live(0, 0, 1, 1));
    let yeti = crate::synth_settings::yeti_synth_settings(true);
    assert_eq!(
        ISynthSettingsProviderDispatcher { contract_address: w.midi.contract_address }
            .get_settings(token_id),
        yeti,
    );
    assert_eq!(tracks(w).get_track_sound(token_id, 1, 0, 0).settings, yeti);
}

/// A block's drift: the day at that block, its day, week and month read from their first blocks'
/// hashes.
#[test]
fn drift_reads_the_block_hashes() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = set_state(w, b, live(0, 0, 1, 1));
    let n = beast_music::composition::drift::DRIFT_EPOCH_BLOCKS;
    let block = 40 * n + 500; // day 41: week 5, month 1
    starknet::testing::set_block_number(block + 20);
    let day = beast_music::composition::drift::day_at_block(block);
    assert_eq!(day, 41);
    let (d, wk, m) = beast_music::composition::drift::drift_anchor_blocks(day);
    starknet::testing::set_block_hash(d, 0x111);
    starknet::testing::set_block_hash(wk, 0x222);
    starknet::testing::set_block_hash(m, 0x333);
    let clock = beast_music::composition::drift::DriftClock {
        day, day_hash: 0x111, week_hash: 0x222, month_hash: 0x333,
    };
    let sound = tracks(w).get_track_sound(token_id, 2, 0, block);
    assert_eq!(
        sound.midi,
        bytes(
            beast_music::composition::genesis::song_smf_bytes(
                b, b.prefix, b.suffix, 0, Option::Some(clock),
            ),
        ),
    );
}

#[test]
#[should_panic(expected: ('block in the future', 'ENTRYPOINT_FAILED'))]
fn drift_rejects_future_blocks() {
    let w = setup();
    starknet::testing::set_block_number(1000);
    tracks(w)
        .get_track_sound_for_inputs(
            tracks(w).get_composer_inputs(encode_v3_token_id(sorrow_peak_warlock())), 1, 0, 1001,
        );
}

#[test]
#[should_panic(expected: ('bought track needs a seed', 'ENTRYPOINT_FAILED'))]
fn bought_tracks_need_a_seed() {
    let w = setup();
    tracks(w)
        .get_track_sound_for_inputs(
            tracks(w).get_composer_inputs(encode_v3_token_id(sorrow_peak_warlock())), 3, 0, 0,
        );
}

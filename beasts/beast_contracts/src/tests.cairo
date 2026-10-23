//! BeastMidiProvider, the Beasts V3 sound manager, against a mock Beasts NFT.

use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::drift::{DriftClock, day_at_block, drift_anchor_blocks};
use beast_composer::composition::genesis::{genesis_midi, neutral_live, song_smf_bytes};
use beast_composer::composition::params_pack::{composer_inputs, pack_inputs};
use beast_composer::composition::sound_check::sound_check_smf_bytes;
use beast_composer::composition::tracks::{beast_track_smf_bytes, track_smf_bytes};
use core::dict::{Felt252Dict, Felt252DictTrait};
use midi::interfaces::{
    IMidiProviderDispatcher, IMidiProviderDispatcherTrait, ISoundProviderDispatcher,
    ISoundProviderDispatcherTrait, ISynthSettingsProviderDispatcher,
    ISynthSettingsProviderDispatcherTrait,
};
use midi::pack::bytes_to_byte_array;
use midi::types::TinySynthSound;
use openzeppelin_interfaces::introspection::{ISRC5Dispatcher, ISRC5DispatcherTrait, ISRC5_ID};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpy, EventSpyTrait, EventsFilterTrait, declare,
    spy_events, start_cheat_block_hash, start_cheat_block_number, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress};
use crate::beasts_v3::{
    CardCondition, IBEASTS_SOUND_MANAGER_ID, IBeastSoundTracksDispatcher,
    IBeastSoundTracksDispatcherTrait, ISoundManagerDispatcher, ISoundManagerDispatcherTrait,
    PackableBeast, TrackInputs, get_hash,
};
use crate::provider::BeastMidiProvider::composer_beast;
use crate::provider::{
    IBeastMidiProviderDispatcher, IBeastMidiProviderDispatcherTrait, IBeastSoundAdminDispatcher,
    IBeastSoundAdminDispatcherTrait, IBeastSoundTokenOwnerDispatcher,
    IBeastSoundTokenOwnerDispatcherTrait, SOUND_PRESET_MEGA, TRACK_COMPOSED, TRACK_SOUND_CHECK,
    TRACK_SPECIES_SONG, TokenTrack,
};

// ── the mock NFT ──

#[starknet::interface]
pub trait IMockBeasts<T> {
    fn mint(ref self: T, token_id: felt252, owner: ContractAddress, beast: PackableBeast);
    fn set_rank(ref self: T, token_id: felt252, rank: u16);
    fn set_species_count(ref self: T, species_id: u64, count: u16);
    fn set_kills(ref self: T, entity_hash: felt252, kills: u64);
    /// The species' sound manager: the only caller the track mutations accept.
    fn set_sound_manager(ref self: T, manager: ContractAddress);
    /// `(track_capacity, num_tracks, default_track)`.
    fn config(self: @T, token_id: felt252) -> (u8, u8, u8);
}

/// The ERC-721 read the provider makes for the token-owner entry point.
#[starknet::interface]
pub trait IMockOwnerOf<T> {
    fn owner_of(self: @T, token_id: u256) -> ContractAddress;
}

/// The Beasts V3 NFT entry points the provider calls, with the real contract's checks and error
/// messages: every token read rejects an unminted token, the track mutations accept only the sound
/// manager, and the track rules are `IBeastSoundTracks`'. `token_uri` panics: the provider must
/// never call it.
#[starknet::contract]
pub mod MockBeasts {
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::beasts_v3::{
        BeastLiveStats, IBeastSoundTracks, IBeastStats, IBeasts, PackableBeast, TrackInputs,
    };

    const BEAST_FELTS: u32 = 26;

    #[storage]
    struct Storage {
        owners: Map<felt252, ContractAddress>,
        beast_felts: Map<(felt252, u32), felt252>,
        rank: Map<felt252, u16>,
        species_count: Map<u64, u16>,
        kills: Map<felt252, u64>,
        manager: ContractAddress,
        capacity: Map<felt252, u8>,
        num_tracks: Map<felt252, u8>,
        default_track: Map<felt252, u8>,
        track_version: Map<(felt252, u8), u16>,
        track_len: Map<(felt252, u8), u32>,
        track_words: Map<(felt252, u8, u32), felt252>,
    }

    fn require_token(self: @ContractState, token_id: felt252) {
        assert(self.owners.read(token_id).is_non_zero(), 'ERC721: invalid token ID');
    }

    fn require_manager(self: @ContractState, token_id: felt252) {
        require_token(self, token_id);
        let manager = self.manager.read();
        assert(manager.is_non_zero(), 'Sound: manager disabled');
        assert(get_caller_address() == manager, 'Sound: caller not manager');
    }

    #[abi(embed_v0)]
    impl Beasts of IBeasts<ContractState> {
        fn get_beast(self: @ContractState, token_id: felt252) -> PackableBeast {
            require_token(self, token_id);
            let mut felts: Array<felt252> = array![];
            for i in 0..BEAST_FELTS {
                felts.append(self.beast_felts.read((token_id, i)));
            }
            let mut span = felts.span();
            Serde::deserialize(ref span).unwrap()
        }

        fn get_beast_rank(self: @ContractState, token_id: felt252) -> u16 {
            require_token(self, token_id);
            self.rank.read(token_id)
        }

        fn get_species_count(self: @ContractState, species_id: u64) -> u16 {
            self.species_count.read(species_id)
        }
    }

    #[abi(embed_v0)]
    impl Stats of IBeastStats<ContractState> {
        fn get_beast_stats(self: @ContractState, entity_hash: felt252) -> BeastLiveStats {
            BeastLiveStats {
                adventurers_killed: self.kills.read(entity_hash),
                last_killed_by: 0,
                last_killed_timestamp: 0,
            }
        }
    }

    #[abi(embed_v0)]
    impl SoundTracks of IBeastSoundTracks<ContractState> {
        fn track_inputs(self: @ContractState, token_id: felt252, track_number: u8) -> TrackInputs {
            require_token(self, token_id);
            assert(track_number < self.num_tracks.read(token_id), 'Sound: invalid track');
            let mut data: Array<felt252> = array![];
            for i in 0..self.track_len.read((token_id, track_number)) {
                data.append(self.track_words.read((token_id, track_number, i)));
            }
            TrackInputs {
                version: self.track_version.read((token_id, track_number)), data: data.span(),
            }
        }

        fn update_track_capacity(ref self: ContractState, token_id: felt252, new_capacity: u8) {
            require_manager(@self, token_id);
            assert(new_capacity >= self.num_tracks.read(token_id), 'Sound: capacity below tracks');
            self.capacity.write(token_id, new_capacity);
        }

        fn add_track(ref self: ContractState, token_id: felt252, inputs: TrackInputs) -> u8 {
            require_manager(@self, token_id);
            let index = self.num_tracks.read(token_id);
            assert(index < self.capacity.read(token_id), 'Sound: no free track slot');
            self.track_version.write((token_id, index), inputs.version);
            self.track_len.write((token_id, index), inputs.data.len());
            let mut i: u32 = 0;
            for word in inputs.data {
                self.track_words.write((token_id, index, i), *word);
                i += 1;
            }
            self.num_tracks.write(token_id, index + 1);
            index
        }

        fn set_default_track(ref self: ContractState, token_id: felt252, track_number: u8) {
            require_manager(@self, token_id);
            let n = self.num_tracks.read(token_id);
            assert(
                track_number < n || (n == 0 && track_number == 0), 'Sound: invalid default track',
            );
            self.default_track.write(token_id, track_number);
        }
    }

    #[abi(embed_v0)]
    impl OwnerOf of super::IMockOwnerOf<ContractState> {
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let token_id: felt252 = token_id.try_into().unwrap();
            require_token(self, token_id);
            self.owners.read(token_id)
        }
    }

    #[abi(embed_v0)]
    impl Admin of super::IMockBeasts<ContractState> {
        fn mint(
            ref self: ContractState,
            token_id: felt252,
            owner: ContractAddress,
            beast: PackableBeast,
        ) {
            self.owners.write(token_id, owner);
            let mut felts: Array<felt252> = array![];
            beast.serialize(ref felts);
            assert(felts.len() == BEAST_FELTS, 'beast felts');
            let mut i: u32 = 0;
            for felt in felts {
                self.beast_felts.write((token_id, i), felt);
                i += 1;
            }
        }

        fn set_rank(ref self: ContractState, token_id: felt252, rank: u16) {
            self.rank.write(token_id, rank);
        }

        fn set_species_count(ref self: ContractState, species_id: u64, count: u16) {
            self.species_count.write(species_id, count);
        }

        fn set_kills(ref self: ContractState, entity_hash: felt252, kills: u64) {
            self.kills.write(entity_hash, kills);
        }

        fn set_sound_manager(ref self: ContractState, manager: ContractAddress) {
            self.manager.write(manager);
        }

        fn config(self: @ContractState, token_id: felt252) -> (u8, u8, u8) {
            (
                self.capacity.read(token_id),
                self.num_tracks.read(token_id),
                self.default_track.read(token_id),
            )
        }
    }

    #[external(v0)]
    fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
        panic!("provider called token_uri")
    }
}

// ── setup ──

#[derive(Drop, Copy)]
struct World {
    nft: IMockBeastsDispatcher,
    provider: ContractAddress,
    composer: ClassHash,
}

/// The class of the contract `name` (a contract of this package or of its tests).
fn class(name: ByteArray) -> ClassHash {
    declare(name).unwrap().contract_class().class_hash
}

fn deploy(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = declare(name).unwrap().contract_class().deploy(@calldata).unwrap();
    address
}

/// The provider's owner in the tests.
const OWNER: felt252 = 0x0a11ce;
/// The holder of every minted test token.
const HOLDER: felt252 = 0x401de2;

fn addr(x: felt252) -> ContractAddress {
    x.try_into().unwrap()
}

fn setup() -> World {
    let nft = deploy("MockBeasts", array![]);
    let composer = class("BeastTrackComposer");
    let provider = deploy("BeastMidiProvider", array![nft.into(), OWNER, composer.into()]);
    let w = World { nft: IMockBeastsDispatcher { contract_address: nft }, provider, composer };
    w.nft.set_sound_manager(provider);
    w
}

fn midi_of(w: World) -> IMidiProviderDispatcher {
    IMidiProviderDispatcher { contract_address: w.provider }
}

fn manager(w: World) -> ISoundManagerDispatcher {
    ISoundManagerDispatcher { contract_address: w.provider }
}

fn provider(w: World) -> IBeastMidiProviderDispatcher {
    IBeastMidiProviderDispatcher { contract_address: w.provider }
}

fn admin(w: World) -> IBeastSoundAdminDispatcher {
    IBeastSoundAdminDispatcher { contract_address: w.provider }
}

/// The provider sees `who` as the caller from now on.
fn as_caller(w: World, who: felt252) {
    start_cheat_caller_address(w.provider, addr(who));
}

fn perfect() -> CardCondition {
    CardCondition {
        centering_x_bps: 10000,
        centering_x_direction: 0,
        centering_y_bps: 10000,
        centering_y_direction: 0,
        hickey_count: 0,
        hickeys_in_art: 0,
        void_level: 0,
        voids_in_art: 0,
        roller_level: 0,
        rollers_in_art: 0,
        edge_chip_level: 0,
        corner_chip_level: 0,
    }
}

/// A Beast as the NFT returns it. The fields no sound reads carry arbitrary values.
fn beast(
    species_id: u64,
    prefix: u8,
    suffix: u8,
    level: u16,
    health: u16,
    sound_effects: u8,
    tier: u8,
    beast_type: u8,
) -> PackableBeast {
    PackableBeast {
        species_id,
        prefix,
        suffix,
        level,
        health,
        visual_effects: 3,
        sound_effects,
        tier,
        beast_type,
        minted_at_block_number: 1234567,
        transfer_damage_chance: 511,
        transfer_lock_hours: 0,
        minted_at_minute: 29000000,
        minter_data: 0xabcdef,
        condition: perfect(),
    }
}

fn genesis_warlock() -> PackableBeast {
    beast(1, 0, 0, 1, 100, SOUND_PRESET_MEGA, 1, 0)
}

fn sorrow_peak_warlock() -> PackableBeast {
    beast(1, 57, 15, 126, 229, 0, 1, 0)
}

/// Tier 1 and mega: the most sections and channels, plus the mega double and drums.
fn heaviest() -> PackableBeast {
    beast(53, 69, 18, 255, 1023, SOUND_PRESET_MEGA, 1, 2)
}

/// Agony Bane Gloomfang (species 76, Hunter, tier 3): a community species.
fn gloomfang() -> PackableBeast {
    beast(76, 1, 2, 10, 100, 0, 3, 1)
}

/// A species-first token ID like Beasts V3's (species at bit 219 and up, the special name and the
/// sound preset in their fields). The provider never decodes it: the mock keys Beasts by it.
fn token_of(b: PackableBeast) -> felt252 {
    let two_219: felt252 = 0x8000000000000000000000000000000000000000000000000000000;
    let two_174: felt252 = 0x40000000000000000000000000000000000000000000;
    let two_169: felt252 = 0x2000000000000000000000000000000000000000000;
    let two_43: felt252 = 0x80000000000;
    b.species_id.into() * two_219
        + b.prefix.into() * two_174
        + b.suffix.into() * two_169
        + b.sound_effects.into() * two_43
        + 1
}

fn mint(w: World, b: PackableBeast) -> felt252 {
    let token_id = token_of(b);
    w.nft.mint(token_id, addr(HOLDER), b);
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

fn assert_parity(w: World, b: PackableBeast) {
    let token_id = mint(w, b);
    let midi = midi_of(w).get_midi(token_id.into());
    assert_eq!(midi, genesis_track(composer_beast(b)));
    // the collection-checked form returns the same bytes
    assert_eq!(midi_of(w).get_midi_for(w.nft.contract_address, token_id.into()), midi);
}

/// Gives the token `capacity` slots and appends `inputs`, as its sound manager.
fn add_tracks(w: World, token_id: felt252, capacity: u8, inputs: Span<TrackInputs>) {
    as_caller(w, OWNER);
    admin(w).batch_update_track_capacity(array![token_id].span(), capacity);
    for i in inputs {
        admin(w).batch_add_track(array![token_id].span(), *i);
    }
    stop_cheat_caller_address(w.provider);
}

fn sound_check_inputs() -> TrackInputs {
    TrackInputs { version: TRACK_SOUND_CHECK, data: array![].span() }
}

fn species_song_inputs() -> TrackInputs {
    TrackInputs { version: TRACK_SPECIES_SONG, data: array![].span() }
}

/// The launch tracks: the Sound Check, the Species Song and the Beast's own Special Song.
fn launch_tracks(w: World, b: PackableBeast) -> felt252 {
    let token_id = mint(w, b);
    let inputs = provider(w).get_composer_inputs(token_id);
    let special = TrackInputs { version: TRACK_COMPOSED, data: array![inputs].span() };
    add_tracks(w, token_id, 3, array![sound_check_inputs(), species_song_inputs(), special].span());
    token_id
}

fn bytes(midi: Array<u8>) -> ByteArray {
    bytes_to_byte_array(midi.span())
}

/// The hash the tests give block `block`.
fn hash_of(block: u64) -> felt252 {
    0xb10c0000 + block.into()
}

/// Sets the current block to `now` and the hashes of the three blocks the day of drift at `block`
/// reads (one block can be the first of its day, week and month); returns the clock the provider
/// should build.
fn cheat_drift(w: World, block: u64, now: u64) -> DriftClock {
    start_cheat_block_number(w.provider, now);
    let day = day_at_block(block);
    let (d, wk, m) = drift_anchor_blocks(day);
    for b in array![d, wk, m] {
        start_cheat_block_hash(w.provider, b, hash_of(b));
    }
    DriftClock { day, day_hash: hash_of(d), week_hash: hash_of(wk), month_hash: hash_of(m) }
}

// ── the Beast ──

#[test]
fn composer_beast_takes_the_traits_and_the_mega_preset() {
    let b = beast(39, 13, 6, 22, 60, SOUND_PRESET_MEGA, 4, 1);
    let c = composer_beast(b);
    assert_eq!(c.id, 39);
    assert_eq!((c.prefix, c.suffix, c.level, c.health), (13, 6, 22, 60));
    assert_eq!((c.tier, c.beast_type), (4, 1));
    assert_eq!((c.shiny, c.animated), (1, 0));
    // Every other preset plays the normal sound, and the visual preset changes nothing.
    for preset in array![0_u8, 2, 3, 15, 31, 255] {
        assert_eq!(composer_beast(PackableBeast { sound_effects: preset, ..b }).shiny, 0);
    }
    for visual in array![0_u8, 1, 2, 3, 31] {
        assert!(composer_beast(PackableBeast { visual_effects: visual, ..b }) == c);
    }
}

/// `PackableBeast` serializes as `beasts_core::pack::PackableBeast` does: 26 felts, the fourteen
/// base fields in declaration order, then the twelve condition fields.
#[test]
fn packable_beast_serde_is_beasts_core() {
    let b = PackableBeast {
        species_id: 1,
        prefix: 2,
        suffix: 3,
        level: 4,
        health: 5,
        visual_effects: 6,
        sound_effects: 7,
        tier: 8,
        beast_type: 9,
        minted_at_block_number: 10,
        transfer_damage_chance: 11,
        transfer_lock_hours: 12,
        minted_at_minute: 13,
        minter_data: 14,
        condition: CardCondition {
            centering_x_bps: 15,
            centering_x_direction: 16,
            centering_y_bps: 17,
            centering_y_direction: 18,
            hickey_count: 19,
            hickeys_in_art: 20,
            void_level: 21,
            voids_in_art: 22,
            roller_level: 23,
            rollers_in_art: 24,
            edge_chip_level: 25,
            corner_chip_level: 26,
        },
    };
    let mut felts: Array<felt252> = array![];
    b.serialize(ref felts);
    let mut expected: Array<felt252> = array![];
    for i in 1..27_u32 {
        expected.append(i.into());
    }
    assert_eq!(felts, expected);
}

#[test]
fn sound_manager_id_is_the_beasts_selector() {
    assert_eq!(IBEASTS_SOUND_MANAGER_ID, selector!("beasts_sound_manager_v1"));
}

#[test]
fn entity_hash_is_poseidon_of_species_and_name() {
    assert_eq!(get_hash(1, 57, 15), core::poseidon::poseidon_hash_span(array![1, 57, 15].span()),);
}

// ── the Species Song: get_midi, get_sound, get_settings ──

#[test]
fn genesis_warlock_plays_its_genesis_track() {
    assert_parity(setup(), genesis_warlock());
}

#[test]
fn named_warlock_plays_the_species_track() {
    let w = setup();
    let b = sorrow_peak_warlock();
    assert_parity(w, b);
    // the name, level and health do not change it: the species' Genesis Track (not mega here)
    assert_eq!(
        midi_of(w).get_midi(token_of(b).into()),
        genesis_track(composer_beast(PackableBeast { sound_effects: 0, ..genesis_warlock() })),
    );
}

#[test]
fn the_mega_preset_plays_the_mega_arrangement() {
    let w = setup();
    let normal = beast(47, 13, 6, 22, 60, 0, 5, 1);
    let mega = beast(48, 13, 6, 22, 60, SOUND_PRESET_MEGA, 5, 1);
    assert_parity(w, normal);
    assert_parity(w, mega);
    // another preset plays the normal sound
    let other = PackableBeast { sound_effects: 7, ..normal };
    let id = token_of(other);
    w.nft.mint(id, addr(HOLDER), other);
    assert_eq!(midi_of(w).get_midi(id.into()), midi_of(w).get_midi(token_of(normal).into()));
}

#[test]
fn harpy_and_pegasus_play_each_others_tracks() {
    let w = setup();
    let harpy = beast(39, 13, 6, 22, 60, 0, 4, 1);
    let pegasus = beast(40, 13, 6, 22, 60, 0, 4, 1);
    assert_parity(w, harpy);
    assert_parity(w, pegasus);
    let h = midi_of(w).get_midi(token_of(harpy).into());
    let p = midi_of(w).get_midi(token_of(pegasus).into());
    assert!(h != p);
    // each plays the other species' Genesis Track
    assert_eq!(beast_composer::composition::genesis::genesis_swap(39), 40);
    assert_eq!(beast_composer::composition::genesis::genesis_swap(40), 39);
}

#[test]
fn community_species_plays_its_genesis_track() {
    assert_parity(setup(), gloomfang());
}

#[test]
fn heaviest_track_plays() {
    assert_parity(setup(), heaviest());
}

#[test]
fn get_sound_is_get_midi_and_get_settings() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id: u256 = mint(w, b).into();
    let sound = ISoundProviderDispatcher { contract_address: w.provider }.get_sound(token_id);
    let settings = ISynthSettingsProviderDispatcher { contract_address: w.provider }
        .get_settings(token_id);
    assert_eq!(sound, TinySynthSound { midi: midi_of(w).get_midi(token_id), settings });
    assert_eq!(sound.midi, genesis_track(composer_beast(b)));
}

#[test]
fn get_settings_serves_settings_by_type_and_mega() {
    let w = setup();
    let settings = ISynthSettingsProviderDispatcher { contract_address: w.provider };
    for t in array![0_u8, 1, 2] {
        for preset in array![0_u8, SOUND_PRESET_MEGA] {
            let b = beast(76, 13, 6, 22, 60, preset, 3, t);
            let token_id = token_of(b) + t.into() * 0x100;
            w.nft.mint(token_id, addr(HOLDER), b);
            assert_eq!(
                settings.get_settings(token_id.into()),
                crate::synth_settings::beast_synth_settings(t, preset == SOUND_PRESET_MEGA),
            );
        }
    }
}

/// The Species Song plays its swapped partner's music, so its settings are the partner's type.
#[test]
fn get_settings_follows_the_default_swap() {
    let w = setup();
    let harpy = beast(39, 0, 0, 1, 100, 0, 4, 1);
    let token_id = mint(w, harpy);
    let partner_type = beast_composer::composition::genesis::species_type(
        beast_composer::composition::genesis::genesis_swap(39),
    );
    assert_eq!(
        ISynthSettingsProviderDispatcher { contract_address: w.provider }
            .get_settings(token_id.into()),
        crate::synth_settings::beast_synth_settings(partner_type, false),
    );
}

/// The Yeti's get_settings carries its avalanche's preset.
#[test]
fn yeti_settings_carry_the_avalanche_preset() {
    let w = setup();
    let yeti = beast(68, 0, 0, 1, 100, SOUND_PRESET_MEGA, 4, 2);
    let token_id = mint(w, yeti);
    assert_eq!(
        ISynthSettingsProviderDispatcher { contract_address: w.provider }
            .get_settings(token_id.into()),
        crate::synth_settings::yeti_synth_settings(true),
    );
}

#[test]
#[should_panic(expected: ('unsupported collection', 'ENTRYPOINT_FAILED'))]
fn rejects_other_collections() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    midi_of(w).get_midi_for(w.provider, token_id.into());
}

/// A u256 at or above the field prime is no Beasts token ID.
#[test]
#[should_panic(expected: ('invalid token id', 'ENTRYPOINT_FAILED'))]
fn rejects_token_ids_above_a_felt() {
    let w = setup();
    midi_of(w).get_midi(u256 { low: 1, high: 0x08000000000000110000000000000000 });
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn get_midi_rejects_unminted_tokens() {
    let w = setup();
    midi_of(w).get_midi(token_of(sorrow_peak_warlock()).into());
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn get_settings_rejects_unminted_tokens() {
    let w = setup();
    ISynthSettingsProviderDispatcher { contract_address: w.provider }
        .get_settings(token_of(sorrow_peak_warlock()).into());
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn get_sound_rejects_unminted_tokens() {
    let w = setup();
    ISoundProviderDispatcher { contract_address: w.provider }
        .get_sound(token_of(sorrow_peak_warlock()).into());
}

// ── SRC5 ──

#[test]
fn reports_the_sound_manager_interface() {
    let w = setup();
    let src5 = ISRC5Dispatcher { contract_address: w.provider };
    assert!(src5.supports_interface(IBEASTS_SOUND_MANAGER_ID));
    assert!(src5.supports_interface(ISRC5_ID));
    assert!(!src5.supports_interface(selector!("beasts_renderer_v1")));
}

#[test]
fn owner_registers_an_interface() {
    let w = setup();
    as_caller(w, OWNER);
    admin(w).register_interface('another_interface');
    assert!(
        ISRC5Dispatcher { contract_address: w.provider }.supports_interface('another_interface'),
    );
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_register_interfaces() {
    let w = setup();
    as_caller(w, 0xbad);
    admin(w).register_interface(IBEASTS_SOUND_MANAGER_ID);
}

// ── get_track_sound ──

#[test]
fn sound_check_track_plays_the_sound_check() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = launch_tracks(w, b);
    let sound = manager(w).get_track_sound(token_id, 0, Option::None);
    assert_eq!(sound.midi, bytes(sound_check_smf_bytes(composer_beast(b))));
    // the Beast's own type (the Warlock is Magic), not its partner's
    assert_eq!(sound.settings, crate::synth_settings::beast_synth_settings(0, false));
    // the Sound Check never drifts, so a block changes nothing and reads no hash
    assert_eq!(manager(w).get_track_sound(token_id, 0, Option::Some(5000000)), sound);
}

#[test]
fn species_song_track_as_written_is_get_sound() {
    let w = setup();
    let b = genesis_warlock();
    let token_id = launch_tracks(w, b);
    let sound = manager(w).get_track_sound(token_id, 1, Option::None);
    assert_eq!(
        sound, ISoundProviderDispatcher { contract_address: w.provider }.get_sound(token_id.into()),
    );
}

#[test]
fn species_song_track_drifts_at_a_block() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = launch_tracks(w, b);
    let block = 3 * 43200 + 500; // day 4
    let clock = cheat_drift(w, block, block + 10);
    let sound = manager(w).get_track_sound(token_id, 1, Option::Some(block));
    let cb = composer_beast(b);
    assert_eq!(sound.midi, bytes(song_smf_bytes(cb, 0, 0, 0, Option::Some(clock))));
    assert_eq!(sound.settings, crate::synth_settings::beast_synth_settings(0, false));
    assert!(sound.midi != manager(w).get_track_sound(token_id, 1, Option::None).midi);
}

/// Live before block 10 asks for block 0: day 1, which composes (it does not mean "as written").
#[test]
fn block_zero_is_the_first_day() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = launch_tracks(w, b);
    let clock = cheat_drift(w, 0, 20);
    assert_eq!(clock.day, 1);
    let sound = manager(w).get_track_sound(token_id, 1, Option::Some(0));
    assert_eq!(sound.midi, bytes(song_smf_bytes(composer_beast(b), 0, 0, 0, Option::Some(clock))),);
}

#[test]
fn special_song_track_plays_the_name_track() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = launch_tracks(w, b);
    let inputs = provider(w).get_composer_inputs(token_id);
    assert_eq!(inputs, pack_inputs(composer_inputs(composer_beast(b), neutral_live())));
    let sound = manager(w).get_track_sound(token_id, 2, Option::None);
    assert_eq!(sound.midi, bytes(track_smf_bytes(inputs, 2, 0, Option::None)));
    assert_eq!(sound.midi, bytes(song_smf_bytes(composer_beast(b), 57, 15, 0, Option::None)));
    assert_eq!(sound.settings, crate::synth_settings::beast_synth_settings(0, false));
}

#[test]
fn special_song_track_drifts_at_a_block() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = launch_tracks(w, b);
    let inputs = provider(w).get_composer_inputs(token_id);
    let block = 40 * 43200 + 7; // day 41: a new month's rhythm cells may apply
    let clock = cheat_drift(w, block, block + 100);
    let sound = manager(w).get_track_sound(token_id, 2, Option::Some(block));
    assert_eq!(sound.midi, bytes(track_smf_bytes(inputs, 2, 0, Option::Some(clock))));
}

/// A Special Song track of a Beast without a special name plays its Species Song.
#[test]
fn special_song_of_a_genesis_beast_is_its_species_song() {
    let w = setup();
    let b = genesis_warlock();
    let token_id = launch_tracks(w, b);
    assert_eq!(
        manager(w).get_track_sound(token_id, 2, Option::None),
        manager(w).get_track_sound(token_id, 1, Option::None),
    );
}

#[test]
fn composed_track_with_a_seed_is_a_bought_track() {
    let w = setup();
    let b = gloomfang();
    let token_id = mint(w, b);
    let inputs = provider(w).get_composer_inputs(token_id);
    let bought = TrackInputs { version: TRACK_COMPOSED, data: array![inputs, 0xabc123].span() };
    add_tracks(w, token_id, 1, array![bought].span());
    let sound = manager(w).get_track_sound(token_id, 0, Option::None);
    assert_eq!(sound.midi, bytes(track_smf_bytes(inputs, 3, 0xabc123, Option::None)));
    assert_eq!(sound.settings, crate::synth_settings::beast_synth_settings(1, false));
}

/// A composed track plays the Beast its inputs describe, whichever token holds it.
#[test]
fn composed_track_plays_the_beast_of_its_inputs() {
    let w = setup();
    let warlock = sorrow_peak_warlock();
    let warlock_id = mint(w, warlock);
    let inputs = provider(w).get_composer_inputs(warlock_id);
    let token_id = mint(w, gloomfang());
    let track = TrackInputs { version: TRACK_COMPOSED, data: array![inputs].span() };
    add_tracks(w, token_id, 1, array![track].span());
    let sound = manager(w).get_track_sound(token_id, 0, Option::None);
    assert_eq!(
        sound.midi, bytes(song_smf_bytes(composer_beast(warlock), 57, 15, 0, Option::None)),
    );
}

/// Tracks mean their version, not their index.
#[test]
fn versions_decide_whatever_the_index() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = mint(w, b);
    add_tracks(w, token_id, 2, array![species_song_inputs(), sound_check_inputs()].span());
    assert_eq!(
        manager(w).get_track_sound(token_id, 1, Option::None).midi,
        bytes(sound_check_smf_bytes(composer_beast(b))),
    );
}

#[test]
#[should_panic(expected: ('Sound: invalid track', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn rejects_a_track_the_token_does_not_have() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    add_tracks(w, token_id, 2, array![sound_check_inputs()].span());
    manager(w).get_track_sound(token_id, 1, Option::None);
}

#[test]
#[should_panic(expected: ('Sound: invalid track', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn a_token_without_tracks_has_no_track_sound() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn get_track_sound_rejects_unminted_tokens() {
    let w = setup();
    manager(w).get_track_sound(token_of(sorrow_peak_warlock()), 0, Option::None);
}

fn one_track(w: World, version: u16, data: Array<felt252>) -> felt252 {
    let token_id = mint(w, sorrow_peak_warlock());
    add_tracks(w, token_id, 1, array![TrackInputs { version, data: data.span() }].span());
    token_id
}

#[test]
#[should_panic(expected: ('unknown track version', 'ENTRYPOINT_FAILED'))]
fn rejects_an_unknown_version() {
    let w = setup();
    let token_id = one_track(w, 9, array![]);
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('bad track data', 'ENTRYPOINT_FAILED'))]
fn rejects_data_on_a_sound_check() {
    let w = setup();
    let token_id = one_track(w, TRACK_SOUND_CHECK, array![1]);
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('bad track data', 'ENTRYPOINT_FAILED'))]
fn rejects_data_on_a_species_song() {
    let w = setup();
    let token_id = one_track(w, TRACK_SPECIES_SONG, array![1]);
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('bad track data', 'ENTRYPOINT_FAILED'))]
fn rejects_a_composed_track_without_inputs() {
    let w = setup();
    let token_id = one_track(w, TRACK_COMPOSED, array![]);
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('bad track data', 'ENTRYPOINT_FAILED'))]
fn rejects_a_composed_track_with_extra_data() {
    let w = setup();
    let inputs = pack_inputs(
        composer_inputs(composer_beast(sorrow_peak_warlock()), neutral_live()),
    );
    let token_id = one_track(w, TRACK_COMPOSED, array![inputs, 1, 2]);
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('bought track needs a seed', 'ENTRYPOINT_FAILED'))]
fn rejects_a_zero_seed() {
    let w = setup();
    let inputs = pack_inputs(
        composer_inputs(composer_beast(sorrow_peak_warlock()), neutral_live()),
    );
    let token_id = one_track(w, TRACK_COMPOSED, array![inputs, 0]);
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('unknown params layout', 'ENTRYPOINT_FAILED'))]
fn rejects_inputs_of_an_unknown_layout() {
    let w = setup();
    let token_id = one_track(w, TRACK_COMPOSED, array![2]);
    manager(w).get_track_sound(token_id, 0, Option::None);
}

#[test]
#[should_panic(expected: ('block in the future', 'ENTRYPOINT_FAILED'))]
fn rejects_a_block_in_the_future() {
    let w = setup();
    let token_id = launch_tracks(w, sorrow_peak_warlock());
    start_cheat_block_number(w.provider, 1000);
    manager(w).get_track_sound(token_id, 1, Option::Some(1001));
}

// ── the composer class ──

/// A Beast's songs compose the same from the Beast as from its packed inputs.
#[test]
fn composing_the_beast_is_composing_its_inputs_sound_check() {
    let b = composer_beast(sorrow_peak_warlock());
    let inputs = pack_inputs(composer_inputs(b, neutral_live()));
    assert_eq!(
        beast_track_smf_bytes(b, 0, 0, Option::None), track_smf_bytes(inputs, 0, 0, Option::None),
    );
}

#[test]
fn composing_the_beast_is_composing_its_inputs_species_song() {
    let b = composer_beast(heaviest());
    let inputs = pack_inputs(composer_inputs(b, neutral_live()));
    assert_eq!(
        beast_track_smf_bytes(b, 1, 0, Option::None), track_smf_bytes(inputs, 1, 0, Option::None),
    );
}

/// The composer class's Genesis Track copy (the Species Song as written) is the general composer's
/// file, byte for byte.
fn assert_genesis_copy(b: PackableBeast) {
    let w = setup();
    let token_id = mint(w, b);
    let sound = ISoundProviderDispatcher { contract_address: w.provider }
        .get_sound(token_id.into());
    assert_eq!(sound.midi, bytes(song_smf_bytes(composer_beast(b), 0, 0, 0, Option::None)));
}

#[test]
fn genesis_copy_is_the_general_composer_warlock() {
    assert_genesis_copy(genesis_warlock());
}

#[test]
fn genesis_copy_is_the_general_composer_harpy() {
    assert_genesis_copy(beast(39, 13, 6, 22, 60, 0, 4, 1));
}

#[test]
fn genesis_copy_is_the_general_composer_yeti() {
    assert_genesis_copy(beast(68, 0, 0, 1, 100, SOUND_PRESET_MEGA, 4, 2));
}

#[test]
fn genesis_copy_is_the_general_composer_community() {
    assert_genesis_copy(gloomfang());
}

#[test]
fn reports_collection_engine_and_composer() {
    let w = setup();
    assert_eq!(provider(w).get_collection(), w.nft.contract_address);
    assert_eq!(provider(w).get_engine_version(), 1);
    assert_eq!(provider(w).get_composer_class(), w.composer);
}

#[test]
fn owner_replaces_the_composer_class() {
    let w = setup();
    as_caller(w, OWNER);
    admin(w).set_composer_class(class("ProviderV2"));
    assert_eq!(provider(w).get_composer_class(), class("ProviderV2"));
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_replace_the_composer_class() {
    let w = setup();
    as_caller(w, 0xbad);
    admin(w).set_composer_class(class("ProviderV2"));
}

#[test]
#[should_panic(expected: ('zero composer class', 'ENTRYPOINT_FAILED'))]
fn the_composer_class_cannot_be_zero() {
    let w = setup();
    as_caller(w, OWNER);
    admin(w).set_composer_class(0.try_into().unwrap());
}

// ── live state ──

#[test]
fn live_state_reads_rank_count_and_verified_kills() {
    let w = setup();
    let b = sorrow_peak_warlock();
    let token_id = mint(w, b);
    w.nft.set_rank(token_id, 7);
    w.nft.set_species_count(1, 954);
    w.nft.set_kills(get_hash(1, 57, 15), 3);
    // another Beast's kills are not this one's
    w.nft.set_kills(get_hash(1, 57, 16), 99);
    let live = provider(w).get_live_state(token_id);
    assert_eq!(live.adventurers_killed, 3);
    assert_eq!(live.rank, 7);
    assert_eq!(live.species_count, 954);
    assert_eq!(live.scars, 0);
    assert_eq!(live.summit_held_seconds, 0);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn live_state_rejects_unminted_tokens() {
    let w = setup();
    provider(w).get_live_state(token_of(sorrow_peak_warlock()));
}

// ── the rollout ──

fn composed(inputs: felt252) -> TrackInputs {
    TrackInputs { version: TRACK_COMPOSED, data: array![inputs].span() }
}

/// The launch rollout over a batch: capacity, the Sound Check (the default), then the Species Song
/// made the default, then each token's own Special Song made the default.
#[test]
fn owner_rolls_out_the_launch_tracks() {
    let w = setup();
    let a = mint(w, sorrow_peak_warlock());
    let b = mint(w, gloomfang());
    let c = mint(w, genesis_warlock());
    let tokens = array![a, b, c].span();
    let inputs_a = provider(w).get_composer_inputs(a);
    let inputs_b = provider(w).get_composer_inputs(b);
    let inputs_c = provider(w).get_composer_inputs(c);
    as_caller(w, OWNER);
    admin(w).batch_update_track_capacity(tokens, 3);
    admin(w).batch_add_track(tokens, sound_check_inputs());
    assert_eq!(w.nft.config(b), (3, 1, 0));
    admin(w).batch_add_track(tokens, species_song_inputs());
    admin(w).batch_set_default_track(tokens, 1);
    assert_eq!(w.nft.config(c), (3, 2, 1));
    admin(w)
        .batch_add_tracks(
            array![
                TokenTrack { token_id: a, inputs: composed(inputs_a) },
                TokenTrack { token_id: b, inputs: composed(inputs_b) },
                TokenTrack { token_id: c, inputs: composed(inputs_c) },
            ]
                .span(),
        );
    admin(w).batch_set_default_track(tokens, 2);
    for t in tokens {
        assert_eq!(w.nft.config(*t), (3, 3, 2));
    }
    // each token's track 2 holds its own inputs
    let nft = IBeastSoundTracksDispatcher { contract_address: w.nft.contract_address };
    assert_eq!(nft.track_inputs(b, 2), composed(inputs_b));
    assert_eq!(nft.track_inputs(a, 0), sound_check_inputs());
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_set_capacity() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    as_caller(w, 0xbad);
    admin(w).batch_update_track_capacity(array![token_id].span(), 3);
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_add_tracks() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    as_caller(w, 0xbad);
    admin(w).batch_add_track(array![token_id].span(), sound_check_inputs());
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_add_tracks_per_token() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    as_caller(w, 0xbad);
    admin(w).batch_add_tracks(array![TokenTrack { token_id, inputs: sound_check_inputs() }].span());
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_set_defaults() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    as_caller(w, 0xbad);
    admin(w).batch_set_default_track(array![token_id].span(), 0);
}

/// One NFT rejection reverts the whole batch.
#[test]
#[should_panic(expected: ('Sound: no free track slot', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn a_batch_reverts_on_any_token() {
    let w = setup();
    let a = mint(w, sorrow_peak_warlock());
    let b = mint(w, gloomfang());
    as_caller(w, OWNER);
    admin(w).batch_update_track_capacity(array![a].span(), 1);
    admin(w).batch_add_track(array![a, b].span(), sound_check_inputs());
}

/// The NFT accepts track mutations only from the species' sound manager.
#[test]
#[should_panic(expected: ('Sound: caller not manager', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn the_rollout_needs_the_species_sound_manager() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    w.nft.set_sound_manager(addr(0x5afe));
    as_caller(w, OWNER);
    admin(w).batch_update_track_capacity(array![token_id].span(), 3);
}

#[test]
fn token_owner_sets_the_default_track() {
    let w = setup();
    let token_id = launch_tracks(w, sorrow_peak_warlock());
    as_caller(w, HOLDER);
    IBeastSoundTokenOwnerDispatcher { contract_address: w.provider }.set_default_track(token_id, 2);
    assert_eq!(w.nft.config(token_id), (3, 3, 2));
}

#[test]
#[should_panic(expected: ('caller is not token owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_set_a_tokens_default_track() {
    let w = setup();
    let token_id = launch_tracks(w, sorrow_peak_warlock());
    as_caller(w, OWNER);
    IBeastSoundTokenOwnerDispatcher { contract_address: w.provider }.set_default_track(token_id, 2);
}

#[test]
#[should_panic(
    expected: ('Sound: invalid default track', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'),
)]
fn token_owner_default_must_be_a_track() {
    let w = setup();
    let token_id = launch_tracks(w, sorrow_peak_warlock());
    as_caller(w, HOLDER);
    IBeastSoundTokenOwnerDispatcher { contract_address: w.provider }.set_default_track(token_id, 3);
}

// ── settings ──

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
        midi::settings::validate(@s);
        let mut slots: Felt252Dict<bool> = Default::default();
        for tb in s.timbres {
            slots.insert(tb.slot.into() + if tb.drum {
                256
            } else {
                0
            }, true);
        }
        for p in beast_composer::composition::full_midi::family_leads(2).span() {
            assert!(slots.get((*p).into()), "lead missing");
        }
        for p in beast_composer::composition::full_midi::family_plucks(2).span() {
            assert!(slots.get((*p).into()), "pluck missing");
        }
        assert!(slots.get(13), "avalanche preset missing");
        for d in array![36_u8, 38, 42, 45, 46, 47, 48, 49, 50] {
            assert!(slots.get(d.into() + 256), "drum missing");
        }
        for p in beast_composer::composition::full_midi::MEGA_LEADS.span() {
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
            midi::settings::validate(@s);
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
            for p in beast_composer::composition::full_midi::family_leads(t).span() {
                assert!(slots.get((*p).into()), "family lead missing");
            }
            for p in beast_composer::composition::full_midi::family_plucks(t).span() {
                assert!(slots.get((*p).into()), "family pluck missing");
            }
            for d in array![36_u8, 38, 41, 42, 43, 45, 46, 47, 48, 49, 50] {
                assert!(slots.get(d.into() + 256), "drum missing");
            }
            for p in beast_composer::composition::full_midi::MEGA_LEADS.span() {
                assert_eq!(slots.get((*p).into()), mega);
            }
        }
    }
}

// ── gas probes (ignored) ──
// The L2 gas of one `get_track_sound` call. Run:
//   snforge test gas_probe --include-ignored --tracked-resource sierra-gas \
//       --trace-verbosity standard --trace-components contract-name call-type gas
// and read the provider call's gas in the trace (or subtract `gas_probe_baseline` from a probe's
// test total).

/// The probe Beast: mega #32, the largest Genesis file, named so tracks 0-2 all differ.
fn probe_beast() -> PackableBeast {
    beast(
        32,
        13,
        6,
        22,
        60,
        SOUND_PRESET_MEGA,
        beast_composer::composition::genesis::species_tier(32),
        beast_composer::composition::genesis::species_type(32),
    )
}

const PROBE_BLOCK: u64 = 3 * 43200 + 500;

fn gas_probe(b: PackableBeast, track: u8, block: Option<u64>, call: bool) {
    let w = setup();
    let token_id = launch_tracks(w, b);
    cheat_drift(w, PROBE_BLOCK, PROBE_BLOCK + 10);
    if call {
        manager(w).get_track_sound(token_id, track, block);
    }
}

#[test]
#[ignore]
fn gas_probe_baseline() {
    gas_probe(probe_beast(), 0, Option::None, false);
}

#[test]
#[ignore]
fn gas_probe_track_0() {
    gas_probe(probe_beast(), 0, Option::None, true);
}

#[test]
#[ignore]
fn gas_probe_track_1_original() {
    gas_probe(probe_beast(), 1, Option::None, true);
}

#[test]
#[ignore]
fn gas_probe_track_1_live() {
    gas_probe(probe_beast(), 1, Option::Some(PROBE_BLOCK), true);
}

#[test]
#[ignore]
fn gas_probe_track_2_original() {
    gas_probe(probe_beast(), 2, Option::None, true);
}

#[test]
#[ignore]
fn gas_probe_track_2_live() {
    gas_probe(probe_beast(), 2, Option::Some(PROBE_BLOCK), true);
}

/// The same for Sorrow Peak Warlock (species 1, normal sound), a lighter Species Song.
#[test]
#[ignore]
fn gas_probe_warlock_track_0() {
    gas_probe(sorrow_peak_warlock(), 0, Option::None, true);
}

#[test]
#[ignore]
fn gas_probe_warlock_track_1_original() {
    gas_probe(sorrow_peak_warlock(), 1, Option::None, true);
}

#[test]
#[ignore]
fn gas_probe_warlock_track_1_live() {
    gas_probe(sorrow_peak_warlock(), 1, Option::Some(PROBE_BLOCK), true);
}

#[test]
#[ignore]
fn gas_probe_warlock_track_2_original() {
    gas_probe(sorrow_peak_warlock(), 2, Option::None, true);
}

#[test]
#[ignore]
fn gas_probe_warlock_track_2_live() {
    gas_probe(sorrow_peak_warlock(), 2, Option::Some(PROBE_BLOCK), true);
}

// ── upgrades (OpenZeppelin Ownable and Upgradeable) ──

/// A stand-in for a later provider class: answers one view, so a test can see the class changed.
#[starknet::interface]
pub trait IProviderV2<T> {
    fn version(self: @T) -> u32;
}

#[starknet::contract]
pub mod ProviderV2 {
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl V2 of super::IProviderV2<ContractState> {
        fn version(self: @ContractState) -> u32 {
            2
        }
    }
}
use openzeppelin_interfaces::access::ownable::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_interfaces::upgrades::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};

fn ownable(w: World) -> IOwnableDispatcher {
    IOwnableDispatcher { contract_address: w.provider }
}

fn upgradeable(w: World) -> IUpgradeableDispatcher {
    IUpgradeableDispatcher { contract_address: w.provider }
}

/// The first event `contract` emitted since `spy` was made: its keys and data.
fn first_event(ref spy: EventSpy, contract: ContractAddress) -> (Array<felt252>, Array<felt252>) {
    let events = spy.get_events().emitted_by(contract).events;
    let (_, event) = events.at(0);
    (event.keys.clone(), event.data.clone())
}

fn version(w: World) -> u32 {
    IProviderV2Dispatcher { contract_address: w.provider }.version()
}

#[test]
fn owner_is_set_at_deploy_and_announced() {
    let mut spy = spy_events();
    let w = setup();
    assert_eq!(ownable(w).owner(), addr(OWNER));
    let (keys, data) = first_event(ref spy, w.provider);
    assert_eq!(keys, array![selector!("OwnershipTransferred"), 0, OWNER]);
    assert_eq!(data, array![]);
}

#[test]
fn owner_upgrades_the_class() {
    let w = setup();
    let mut spy = spy_events(); // after the constructor's event
    as_caller(w, OWNER);
    upgradeable(w).upgrade(class("ProviderV2"));
    assert_eq!(version(w), 2);
    let (keys, data) = first_event(ref spy, w.provider);
    assert_eq!(keys, array![selector!("Upgraded")]);
    assert_eq!(data, array![class("ProviderV2").into()]);
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn others_cannot_upgrade() {
    let w = setup();
    as_caller(w, 0xbad);
    upgradeable(w).upgrade(class("ProviderV2"));
}

#[test]
fn ownership_transfers() {
    let w = setup();
    as_caller(w, OWNER);
    ownable(w).transfer_ownership(addr(0xb0b));
    assert_eq!(ownable(w).owner(), addr(0xb0b));
    as_caller(w, 0xb0b);
    upgradeable(w).upgrade(class("ProviderV2"));
    assert_eq!(version(w), 2);
}

/// After renouncing, the owner is zero and the former owner (or anyone) can no longer upgrade.
#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn renounced_ends_upgrades_for_good() {
    let w = setup();
    as_caller(w, OWNER);
    ownable(w).renounce_ownership();
    assert_eq!(ownable(w).owner(), addr(0));
    upgradeable(w).upgrade(class("ProviderV2"));
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn renounced_ends_the_rollout_for_good() {
    let w = setup();
    let token_id = mint(w, sorrow_peak_warlock());
    as_caller(w, OWNER);
    ownable(w).renounce_ownership();
    admin(w).batch_update_track_capacity(array![token_id].span(), 3);
}

#[test]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn renounced_cannot_be_reclaimed() {
    let w = setup();
    as_caller(w, OWNER);
    ownable(w).renounce_ownership();
    ownable(w).transfer_ownership(addr(OWNER));
}

fn deploy_error(calldata: Array<felt252>) -> Array<felt252> {
    declare("BeastMidiProvider").unwrap().contract_class().deploy(@calldata).unwrap_err()
}

#[test]
fn constructor_rejects_a_zero_owner() {
    let nft = deploy("MockBeasts", array![]);
    let composer = class("BeastTrackComposer");
    assert_eq!(
        deploy_error(array![nft.into(), 0, composer.into()]),
        array!['New owner is the zero address'],
    );
}

#[test]
fn constructor_rejects_a_zero_collection() {
    let composer = class("BeastTrackComposer");
    assert_eq!(deploy_error(array![0, OWNER, composer.into()]), array!['zero collection']);
}

#[test]
fn constructor_rejects_a_zero_composer_class() {
    let nft = deploy("MockBeasts", array![]);
    assert_eq!(deploy_error(array![nft.into(), OWNER, 0]), array!['zero composer class']);
}

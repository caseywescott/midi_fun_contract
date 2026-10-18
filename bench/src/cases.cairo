//! What each bench case does: deploy, set state, make the one measured call, check its output.
//! The generated tests (`tests.cairo`, from `scripts/gen_expected.mjs`) call these; every test
//! makes exactly one call to its measured entry point, and every other call it makes (deploys,
//! mock setters) has a different selector.

use beast_composer::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, encode_v3_token_id,
};
use beast_composer::composition::genesis::{species_tier, species_type};
use beast_contracts::provider::{IBeastMidiProviderDispatcher, IBeastMidiProviderDispatcherTrait};
use beast_contracts::{IBeastSoundComposerDispatcher, IBeastSoundComposerDispatcherTrait};
use midi::interfaces::{
    IMidiProviderDispatcher, IMidiProviderDispatcherTrait, IMidiSoundPageDispatcher,
    IMidiSoundPageDispatcherTrait, ISoundProviderDispatcher, ISoundProviderDispatcherTrait,
    ISynthSettingsProviderDispatcher, ISynthSettingsProviderDispatcherTrait,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use crate::digest::{bytes_digest, check, serde_digest, u8s_digest};
use crate::mocks::{
    IMockBeastsDispatcher, IMockBeastsDispatcherTrait, IMockDeathMountainDispatcher,
    IMockDeathMountainDispatcherTrait,
};
use crate::probes::{
    IBenchGenesisDispatcher, IBenchGenesisDispatcherTrait, IBenchLibDispatcher,
    IBenchLibDispatcherTrait, IBenchScoreDispatcher, IBenchScoreDispatcherTrait,
};

/// OpenZeppelin `IOwnable::owner`, the one function of it the bench calls.
#[starknet::interface]
pub trait IOwner<T> {
    fn owner(self: @T) -> ContractAddress;
}

/// The provider's owner (as in beast_contracts' tests).
pub const OWNER: felt252 = 0x0a11ce;
/// The collection `ScaleMidiProvider` serves, and the token address the fixed-bytes page cases
/// pass.
pub const COLLECTION: felt252 = 'BEASTS';
/// `BeastSoundComposer`'s constructor (as in beasts/beast_contracts/scripts/deploy_and_bench.mjs).
pub const DROP_SALT: felt252 = 'LS_V3_DEMO_SALT';
pub const DROP_BPS: felt252 = 500;

pub fn deploy(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = declare(name).unwrap().contract_class().deploy(@calldata).unwrap();
    address
}

#[derive(Drop, Copy)]
pub struct World {
    pub nft: IMockBeastsDispatcher,
    pub dm: IMockDeathMountainDispatcher,
    pub provider: ContractAddress,
}

/// A mock NFT (`nft_class`: MockBeasts, or BurnBeasts for group M) and Death Mountain, and the
/// production BeastMidiProvider serving the NFT.
pub fn world_with(nft_class: ByteArray) -> World {
    let nft = deploy(nft_class, array![]);
    let dm = deploy("MockDeathMountain", array![]);
    let provider = deploy("BeastMidiProvider", array![nft.into(), OWNER]);
    let w = World {
        nft: IMockBeastsDispatcher { contract_address: nft },
        dm: IMockDeathMountainDispatcher { contract_address: dm },
        provider,
    };
    w.nft.set_death_mountain(dm);
    w
}

pub fn world() -> World {
    world_with("MockBeasts")
}

fn entity_hash(b: PackableBeastV3) -> felt252 {
    core::poseidon::poseidon_hash_span(array![b.id.into(), b.prefix.into(), b.suffix.into()].span())
}

/// Puts `live` on the mocks the way the real contracts hold it (as beast_contracts' tests do).
pub fn set_state(w: World, b: PackableBeastV3, live: BeastV3LiveState) -> u256 {
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

pub fn live(kills: u64, scars: u64, rank: u16, count: u16) -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: kills, scars, summit_held_seconds: 0, rank, species_count: count,
    }
}

pub fn live_summit(kills: u64, scars: u64, summit: u64, rank: u16, count: u16) -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: kills, scars, summit_held_seconds: summit, rank, species_count: count,
    }
}

/// The Beasts of `genesis_parity_range` (beast_composer/src/genesis_tests.cairo).
pub fn gbeast(id: u64, shiny: u8) -> PackableBeastV3 {
    PackableBeastV3 {
        id,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny,
        animated: 0,
        tier: species_tier(id),
        beast_type: species_type(id),
    }
}

pub fn beast(
    id: u64,
    prefix: u8,
    suffix: u8,
    level: u16,
    health: u16,
    shiny: u8,
    animated: u8,
    tier: u8,
    beast_type: u8,
) -> PackableBeastV3 {
    PackableBeastV3 { id, prefix, suffix, level, health, shiny, animated, tier, beast_type }
}

// ── A: BeastMidiProvider
// ─────────────────────────────────────────────────────────────────────

pub fn get_midi(b: PackableBeastV3, l: BeastV3LiveState, key: ByteArray, exp: (u32, felt252)) {
    let w = world();
    let token_id = set_state(w, b, l);
    let midi = IMidiProviderDispatcher { contract_address: w.provider }.get_midi(token_id);
    check(key, bytes_digest(@midi), exp);
}

/// Group M: `get_midi` with BurnBeasts as the NFT.
pub fn get_midi_burn(b: PackableBeastV3, l: BeastV3LiveState, key: ByteArray, exp: (u32, felt252)) {
    let w = world_with("BurnBeasts");
    let token_id = set_state(w, b, l);
    let midi = IMidiProviderDispatcher { contract_address: w.provider }.get_midi(token_id);
    check(key, bytes_digest(@midi), exp);
}

pub fn get_midi_for(b: PackableBeastV3, l: BeastV3LiveState, key: ByteArray, exp: (u32, felt252)) {
    let w = world();
    let token_id = set_state(w, b, l);
    let midi = IMidiProviderDispatcher { contract_address: w.provider }
        .get_midi_for(w.nft.contract_address, token_id);
    check(key, bytes_digest(@midi), exp);
}

pub fn get_sound(
    b: PackableBeastV3,
    l: BeastV3LiveState,
    midi_key: ByteArray,
    midi_exp: (u32, felt252),
    settings_key: ByteArray,
    settings_exp: (u32, felt252),
) {
    let w = world();
    let token_id = set_state(w, b, l);
    let sound = ISoundProviderDispatcher { contract_address: w.provider }.get_sound(token_id);
    check(midi_key, bytes_digest(@sound.midi), midi_exp);
    check(settings_key, serde_digest(@sound.settings), settings_exp);
}

/// `get_settings` checks the token ID's format only, so the token is not minted.
pub fn get_settings(b: PackableBeastV3, key: ByteArray, exp: (u32, felt252)) {
    let w = world();
    let settings = ISynthSettingsProviderDispatcher { contract_address: w.provider }
        .get_settings(encode_v3_token_id(b));
    check(key, serde_digest(@settings), exp);
}

pub fn get_live_state(
    b: PackableBeastV3,
    l: BeastV3LiveState,
    death_mountain: bool,
    key: ByteArray,
    exp: (u32, felt252),
) {
    let w = world();
    let token_id = set_state(w, b, l);
    if !death_mountain {
        w.nft.set_death_mountain(0.try_into().unwrap());
    }
    let report = IBeastMidiProviderDispatcher { contract_address: w.provider }
        .get_live_state(w.nft.contract_address, token_id);
    check(key, serde_digest(@report), exp);
}

pub fn get_collection(key: ByteArray, exp: (u32, felt252)) {
    let w = world();
    let collection = IBeastMidiProviderDispatcher { contract_address: w.provider }.get_collection();
    assert(collection == w.nft.contract_address, 'not the collection');
    check(key, serde_digest(@collection), exp);
}

pub fn get_engine_version(key: ByteArray, exp: (u32, felt252)) {
    let w = world();
    let version = IBeastMidiProviderDispatcher { contract_address: w.provider }
        .get_engine_version();
    check(key, serde_digest(@version), exp);
}

pub fn owner(key: ByteArray, exp: (u32, felt252)) {
    let w = world();
    let owner = IOwnerDispatcher { contract_address: w.provider }.owner();
    assert(owner == OWNER.try_into().unwrap(), 'not the owner');
    check(key, serde_digest(@owner), exp);
}

// ── B: BeastSoundComposer
// ────────────────────────────────────────────────────────────────────

pub const HAS_SOUND: u8 = 0;
pub const PARAMS: u8 = 1;
pub const STATE_HASH: u8 = 2;
pub const SCORE_HASH: u8 = 3;
pub const SCORE_NOTES: u8 = 4;
pub const SCORE_INSTRUCTIONS: u8 = 5;
pub const SCORE_MIDI: u8 = 6;

/// One `BeastSoundComposer` view (`view`, one of the constants above) for a Beast and live state.
pub fn composer(
    view: u8, b: PackableBeastV3, l: BeastV3LiveState, key: ByteArray, exp: (u32, felt252),
) {
    let c = IBeastSoundComposerDispatcher {
        contract_address: deploy("BeastSoundComposer", array![DROP_SALT, DROP_BPS]),
    };
    let token_id = encode_v3_token_id(b);
    let got = if view == HAS_SOUND {
        serde_digest(@c.has_sound(token_id))
    } else if view == PARAMS {
        serde_digest(@c.get_composition_params(token_id, l))
    } else if view == STATE_HASH {
        serde_digest(@c.get_music_state_hash(token_id, l))
    } else if view == SCORE_HASH {
        serde_digest(@c.get_score_hash(token_id, l))
    } else if view == SCORE_NOTES {
        serde_digest(@c.get_score_notes(token_id, l))
    } else if view == SCORE_INSTRUCTIONS {
        serde_digest(@c.get_score_instructions(token_id, l))
    } else {
        assert(view == SCORE_MIDI, 'unknown view');
        serde_digest(@c.get_score_midi(token_id, l))
    };
    check(key, got, exp);
}

// ── C: MidiSoundPage
// ─────────────────────────────────────────────────────────────────────────

fn page(provider: ContractAddress) -> IMidiSoundPageDispatcher {
    IMidiSoundPageDispatcher { contract_address: deploy("MidiSoundPage", array![provider.into()]) }
}

/// `token_uri` with FixedMidiProvider's MIDI fixture `fixture`.
pub fn token_uri_fixed(
    fixture: u256, members: ByteArray, svg_b64: ByteArray, key: ByteArray, exp: (u32, felt252),
) {
    let p = page(deploy("FixedMidiProvider", array![]));
    let uri = p.token_uri(members, svg_b64, COLLECTION.try_into().unwrap(), fixture);
    check(key, bytes_digest(@uri), exp);
}

/// `token_uri` end to end: the page asks the production BeastMidiProvider (mock NFT) for the MIDI.
pub fn token_uri_e2e(
    b: PackableBeastV3,
    l: BeastV3LiveState,
    members: ByteArray,
    svg_b64: ByteArray,
    key: ByteArray,
    exp: (u32, felt252),
) {
    let w = world();
    let token_id = set_state(w, b, l);
    let uri = page(w.provider).token_uri(members, svg_b64, w.nft.contract_address, token_id);
    check(key, bytes_digest(@uri), exp);
}

pub fn get_midi_provider(key: ByteArray, exp: (u32, felt252)) {
    let provider = deploy("FixedMidiProvider", array![]);
    let got = page(provider).get_midi_provider();
    assert(got == provider, 'not the provider');
    check(key, serde_digest(@got), exp);
}

// ── D: ScaleMidiProvider
// ─────────────────────────────────────────────────────────────────────

fn scale() -> IMidiProviderDispatcher {
    IMidiProviderDispatcher { contract_address: deploy("ScaleMidiProvider", array![COLLECTION]) }
}

pub fn scale_get_midi(token_id: u256, key: ByteArray, exp: (u32, felt252)) {
    let midi = scale().get_midi(token_id);
    check(key, bytes_digest(@midi), exp);
}

pub fn scale_get_midi_for(token_id: u256, key: ByteArray, exp: (u32, felt252)) {
    let midi = scale().get_midi_for(COLLECTION.try_into().unwrap(), token_id);
    check(key, bytes_digest(@midi), exp);
}

// ── E: BenchLib, BenchGenesis, BenchScore (library attribution)
// ────────────────────────────────────────────────────────

fn lib() -> IBenchLibDispatcher {
    IBenchLibDispatcher { contract_address: deploy("BenchLib", array![]) }
}

pub fn pack_input(len: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, serde_digest(@lib().pack_input(len)), exp);
}

pub fn bytes_to_byte_array(len: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, bytes_digest(@lib().bytes_to_byte_array(len)), exp);
}

pub fn to_felt252_array(len: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, serde_digest(@lib().to_felt252_array(len)), exp);
}

pub fn b64_input(index: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, serde_digest(@lib().b64_input(index)), exp);
}

pub fn append_base64(index: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, bytes_digest(@lib().append_base64(index)), exp);
}

pub fn midi_html(index: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, bytes_digest(@lib().midi_html(index)), exp);
}

pub fn u8_output(len: u32, key: ByteArray, exp: (u32, felt252)) {
    let bytes = lib().u8_output(len);
    check(key, u8s_digest(bytes.span()), exp);
}

pub fn felt_input(n: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, serde_digest(@lib().felt_input(n)), exp);
}

pub fn felt_output(n: u32, key: ByteArray, exp: (u32, felt252)) {
    check(key, serde_digest(@lib().felt_output(n)), exp);
}

pub fn genesis_smf_bytes(b: PackableBeastV3, key: ByteArray, exp: (u32, felt252)) {
    let bytes = IBenchGenesisDispatcher { contract_address: deploy("BenchGenesis", array![]) }
        .genesis_smf_bytes(b);
    check(key, u8s_digest(bytes.span()), exp);
}

pub fn genesis_score(b: PackableBeastV3, key: ByteArray, exp: (u32, felt252)) {
    let score = IBenchScoreDispatcher { contract_address: deploy("BenchScore", array![]) }
        .genesis_score(b);
    check(key, serde_digest(@score), exp);
}

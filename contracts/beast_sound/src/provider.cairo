//! BeastMidiProvider: a Beasts V3 token's theme behind the generic `IMidiProvider` interface.
//!
//! `get_midi(token_id)` needs nothing else (`get_midi_for(token_address, token_id)` also checks the
//! collection). The provider validates the token, decodes the static traits from the token ID,
//! reads the live state itself and runs composer v1.1 (`beast_music::composition::beast_v11`: same
//! mode, even phrases, history), so the MIDI is byte-identical to `v11_score_full_midi` for the
//! same state: the score plus a program change and pan on every voice
//! at tick 0 and a drum track on channel 10, so a player that adds nothing (onchain-tinysynth)
//! plays it as intended.
//!
//! Live state, all read inside one entry-point call (one state snapshot, nothing cached):
//!
//! | Field | Source |
//! |---|---|
//! | rank | `get_beast_rank(token_id)` on the collection (reverts for an unminted token) |
//! | species_count | `get_species_count(species)` on the collection |
//! | adventurers_killed | species 1-75: `get_adventurers_killed(token_id)` (Death Mountain, live);
//! community species: `get_cached_stats(token_id)`, the value their `token_uri` shows |
//! | scars | species 1-75: Death Mountain `get_collectable_count(dm, poseidon(id, prefix, suffix))
//! - 1`, the defeats after the one that made the Beast mintable; community species: 0, Death
//! Mountain does not track them |
//! | summit_held_seconds | retired (Summit is obsolete): always 0 |
//!
//! Death Mountain is whatever the collection's `get_death_mountain_address()` returns, passed as
//! the `dungeon` key exactly as the NFT's own metadata does. When it is unset, the Death Mountain
//! fields are composed as 0 and `get_live_state` reports them `Unavailable` rather than `Read`.
//! `get_midi` never reverts for that: it runs inside the NFT's `token_uri`, where a revert cannot
//! be caught. It reverts only for an unsupported collection, an invalid token ID or an unminted
//! token. The provider only calls state getters, never `token_uri`, so metadata cannot recurse.

use beast_music::composition::beast_v3_sound::BeastV3LiveState;
use starknet::ContractAddress;

/// `IBeasts::get_cached_stats` (Beasts V3 `BeastLiveStats`).
#[derive(Copy, Drop, Serde)]
pub struct BeastCachedStats {
    pub adventurers_killed: u64,
    pub last_killed_by: u64,
    pub last_killed_timestamp: u64,
}

/// The Beasts V3 NFT state getters the provider reads.
#[starknet::interface]
pub trait IBeastsLiveState<T> {
    fn get_beast_rank(self: @T, token_id: u256) -> u16;
    fn get_species_count(self: @T, beast_id: u64) -> u16;
    fn get_adventurers_killed(self: @T, token_id: u256) -> u64;
    fn get_cached_stats(self: @T, token_id: u256) -> BeastCachedStats;
    fn get_death_mountain_address(self: @T) -> ContractAddress;
}

/// Death Mountain `IBeastSystems::get_collectable_count`.
#[starknet::interface]
pub trait IDeathMountainCollects<T> {
    fn get_collectable_count(self: @T, dungeon: ContractAddress, entity_hash: felt252) -> u64;
}

/// Where a composed live value came from.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum StateSource {
    /// Read from its source; zero is a real zero.
    Read,
    /// The source does not track this Beast (Death Mountain and community species): zero by
    /// definition.
    NotTracked,
    /// The source is not configured (the collection has no Death Mountain address): composed as
    /// zero, but the real value is unknown.
    Unavailable,
    /// The input is retired (Summit): always zero.
    Retired,
}

/// The exact live state `get_midi` composes from, with each field's provenance.
#[derive(Copy, Drop, Serde)]
pub struct BeastLiveStateReport {
    pub live: BeastV3LiveState,
    pub adventurers_killed: StateSource,
    pub scars: StateSource,
    pub summit_held_seconds: StateSource,
    /// No field is `Unavailable`.
    pub complete: bool,
}

#[starknet::interface]
pub trait IBeastMidiProvider<T> {
    /// The live state `get_midi(token_id)` composes from, and where each field
    /// came from.
    fn get_live_state(
        self: @T, token_address: ContractAddress, token_id: u256,
    ) -> BeastLiveStateReport;
    /// The one Beasts collection this provider serves.
    fn get_collection(self: @T) -> ContractAddress;
    /// Composition engine (`BEAST_V3_ENGINE_VERSION`): a new engine means a new provider.
    fn get_engine_version(self: @T) -> u32;
}

#[starknet::contract]
pub mod BeastMidiProvider {
    use beast_music::composition::beast_v11::v11_score_full_smf_bytes;
    use beast_music::composition::beast_v3_sound::{
        BEAST_V3_ENGINE_VERSION, BeastV3LiveState, GENESIS_SPECIES_MAX, PackableBeastV3,
        decode_v3_token_id,
    };
    use core::num::traits::Zero;
    use core::poseidon::poseidon_hash_span;
    use midi_provider::synth::{ISynthSettingsProvider, SynthSettings};
    use midi_provider::{IMidiProvider, bytes_to_byte_array};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::{
        BeastLiveStateReport, IBeastMidiProvider, IBeastsLiveStateDispatcher,
        IBeastsLiveStateDispatcherTrait, IDeathMountainCollectsDispatcher,
        IDeathMountainCollectsDispatcherTrait, StateSource,
    };

    #[storage]
    struct Storage {
        collection: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, collection: ContractAddress) {
        assert(collection.is_non_zero(), 'zero collection');
        self.collection.write(collection);
    }

    #[abi(embed_v0)]
    impl MidiProviderImpl of IMidiProvider<ContractState> {
        fn get_midi(self: @ContractState, token_id: u256) -> ByteArray {
            let (beast, report) = read_live_state(self, self.collection.read(), token_id);
            bytes_to_byte_array(v11_score_full_smf_bytes(beast, report.live).span())
        }

        fn get_midi_for(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            let (beast, report) = read_live_state(self, token_address, token_id);
            bytes_to_byte_array(v11_score_full_smf_bytes(beast, report.live).span())
        }
    }

    #[abi(embed_v0)]
    impl SynthSettingsProviderImpl of ISynthSettingsProvider<ContractState> {
        /// The Beast sound settings (`crate::synth_settings`), the same for every Beast for now.
        /// Validates the token ID's format only: no calls, so it costs no more than building the
        /// value.
        fn get_settings(self: @ContractState, token_id: u256) -> SynthSettings {
            decode_v3_token_id(token_id);
            crate::synth_settings::beast_synth_settings()
        }
    }

    #[abi(embed_v0)]
    impl BeastMidiProviderImpl of IBeastMidiProvider<ContractState> {
        fn get_live_state(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> BeastLiveStateReport {
            let (_, report) = read_live_state(self, token_address, token_id);
            report
        }

        fn get_collection(self: @ContractState) -> ContractAddress {
            self.collection.read()
        }

        fn get_engine_version(self: @ContractState) -> u32 {
            BEAST_V3_ENGINE_VERSION
        }
    }

    fn read_live_state(
        self: @ContractState, token_address: ContractAddress, token_id: u256,
    ) -> (PackableBeastV3, BeastLiveStateReport) {
        let collection = self.collection.read();
        assert(token_address == collection, 'unsupported collection');
        let beast = decode_v3_token_id(token_id);
        let nft = IBeastsLiveStateDispatcher { contract_address: collection };
        let rank = nft.get_beast_rank(token_id);
        let species_count = nft.get_species_count(beast.id);

        let (adventurers_killed, kills_source, scars, scars_source) = if beast
            .id <= GENESIS_SPECIES_MAX {
            let death_mountain = nft.get_death_mountain_address();
            if death_mountain.is_zero() {
                (0, StateSource::Unavailable, 0, StateSource::Unavailable)
            } else {
                let entity_hash = poseidon_hash_span(
                    array![beast.id.into(), beast.prefix.into(), beast.suffix.into()].span(),
                );
                let collects = IDeathMountainCollectsDispatcher { contract_address: death_mountain }
                    .get_collectable_count(death_mountain, entity_hash);
                let scars = if collects > 0 {
                    collects - 1
                } else {
                    0
                };
                (nft.get_adventurers_killed(token_id), StateSource::Read, scars, StateSource::Read)
            }
        } else {
            let cached = nft.get_cached_stats(token_id);
            (cached.adventurers_killed, StateSource::Read, 0, StateSource::NotTracked)
        };

        let live = BeastV3LiveState {
            adventurers_killed, scars, summit_held_seconds: 0, rank, species_count,
        };
        let report = BeastLiveStateReport {
            live,
            adventurers_killed: kills_source,
            scars: scars_source,
            summit_held_seconds: StateSource::Retired,
            complete: kills_source != StateSource::Unavailable
                && scars_source != StateSource::Unavailable,
        };
        (beast, report)
    }
}

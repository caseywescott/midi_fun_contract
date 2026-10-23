//! BeastMidiProvider: the Beasts V3 sound manager of the Beast Sound composer.
//!
//! A species' sound manager (Provable-Games/beasts-v3 `docs/sound-storage.md`) answers SRC5
//! `IBEASTS_SOUND_MANAGER_ID`, so the registry accepts it for a species, and implements
//! `ISoundManager::get_track_sound(token_id, track_number, block_number)`, which the Beasts
//! renderer calls for the token's default track. It is also the only caller the NFT accepts for a
//! token's track mutations (`update_track_capacity`, `add_track`, `set_default_track`), so the
//! provider forwards them: batched for its owner (the launch rollout), and `set_default_track` for
//! the token's owner.
//!
//! # Tracks
//!
//! A token's tracks are stored on the NFT as `TrackInputs { version, data }`; the NFT never reads
//! them. This provider's versions:
//!
//! | `version` | `data` | Plays (`beast_composer::composition::tracks`) |
//! |---|---|---|
//! | `TRACK_SOUND_CHECK` (1) | none | track 0, the Sound Check: the Beast's scale through each of
//! its presets |
//! | `TRACK_SPECIES_SONG` (2) | none | track 1, the Species Song (the Genesis Track, default swaps)
//! |
//! | `TRACK_COMPOSED` (3) | `[inputs]` | track 2, the Beast Special Song of packed composer inputs
//! `inputs` (`get_composer_inputs`): the name track, or the Species Song without a special name |
//! | `TRACK_COMPOSED` (3) | `[inputs, seed]` | track 3+, a bought track: `seed` (never 0) on the
//! Beast of `inputs` |
//!
//! The Sound Check and the Species Song compose from the token itself (`get_beast`), so they store
//! no per-token data: the launch rollout appends them to every token with the same inputs. A
//! `TRACK_COMPOSED` track (the launch's "transmission") carries its Beast in its data, so it plays
//! whatever Beast its inputs describe. Versions are what a track means, whatever its index, so a
//! token's tracks can come in any order. The composer's track numbers are the indices of the launch
//! rollout (Sound Check 0, Species Song 1, the transmission 2).
//!
//! `block_number` picks the day of drift (`beast_composer::composition::drift`): `None` (the
//! Original mode) plays the track as written; `Some(n)` (Live and AtBlock) the day at block `n`,
//! read from the hashes of its day's, week's and month's first blocks. `n` must not be in the
//! future. The Sound Check never drifts.
//!
//! # The Beast
//!
//! The provider reads the Beast from the NFT (`get_beast`), never from the token ID's bits, so the
//! Beasts V3 token layout can change without it. `sound_effects` is a preset this provider
//! defines: `SOUND_PRESET_MEGA` (1) plays the mega sound (the shiny arrangement and settings) and
//! every other value plays the normal sound. `visual_effects`, the image provider's preset, does
//! not change the sound.
//!
//! # Other entry points
//!
//! `get_sound(token_id)` (onchain-midi-player's `ISoundProvider`), `get_midi`, `get_midi_for` and
//! `get_settings` serve the token's Species Song as written, whether or not the token has tracks.
//! `get_live_state` reports the live state a composition could read (no track uses it today).
//! Every read happens inside one call; nothing is cached. The provider only calls state getters on
//! the NFT, never `token_uri`, so metadata cannot recurse.
//!
//! # Composer class
//!
//! The composer is too large to share a class with the provider under Starknet's 81,920-felt CASM
//! limit, so every track composes in `crate::track_composer::BeastTrackComposer`, a declared class
//! the provider library-calls (`get_composer_class`). The owner can replace it
//! (`set_composer_class`).
//!
//! # Owner
//!
//! OpenZeppelin Ownable and Upgradeable: for a short period after launch the owner (set at deploy)
//! can `upgrade` the class, replace the composer class, and drive the track rollout;
//! `renounce_ownership` then ends all of these for good (the owner becomes zero). The constructor
//! registers `IBEASTS_SOUND_MANAGER_ID`. An upgrade does not rerun the constructor, so an instance
//! upgraded from an earlier class needs the owner to call `set_composer_class` and
//! `register_interface(IBEASTS_SOUND_MANAGER_ID)` before a species can use it.
//!
//! # Rollout batches
//!
//! Every NFT track mutation emits two events (its own and ERC-4906 `MetadataUpdate`), and Starknet
//! caps a transaction at 1,000 events; the batch entry points emit none of their own. So a
//! transaction holds at most about 500 tokens of one batch call (`batch_set_default_track` alone),
//! 250 of two (`batch_add_track` and `batch_set_default_track` in one multicall) and 166 of all
//! three (capacity, track and default). Gas and steps bound a batch too: size it by a dry run.

use beast_composer::composition::beast_v3_sound::BeastV3LiveState;
use starknet::{ClassHash, ContractAddress};
use crate::beasts_v3::TrackInputs;

/// `TrackInputs.version` of the Sound Check: no data.
pub const TRACK_SOUND_CHECK: u16 = 1;
/// `TrackInputs.version` of the Species Song: no data.
pub const TRACK_SPECIES_SONG: u16 = 2;
/// `TrackInputs.version` of a track composed from stored composer inputs: `[inputs]` (the Beast
/// Special Song) or `[inputs, seed]` (a bought track).
pub const TRACK_COMPOSED: u16 = 3;

/// The `sound_effects` preset that plays the mega sound. Any other value plays the normal sound.
pub const SOUND_PRESET_MEGA: u8 = 1;

/// A token and the track to append to it (`batch_add_tracks`).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct TokenTrack {
    pub token_id: felt252,
    pub inputs: TrackInputs,
}

#[starknet::interface]
pub trait IBeastMidiProvider<T> {
    /// The Beast's live state: its rank (`get_beast_rank`), its species' count
    /// (`get_species_count`) and its verified kills (the NFT's `IBeastStats`). Beasts V3 tracks no
    /// scars and Summit is retired, so both are 0. No track composes from it today.
    fn get_live_state(self: @T, token_id: felt252) -> BeastV3LiveState;
    /// The one Beasts collection this provider serves.
    fn get_collection(self: @T) -> ContractAddress;
    /// Composition engine (`BEAST_V3_ENGINE_VERSION`): a new engine means a new provider.
    fn get_engine_version(self: @T) -> u32;
    /// The `BeastTrackComposer` class every track composes in (a library call).
    fn get_composer_class(self: @T) -> ClassHash;
    /// The token's packed composer inputs: the `[inputs]` of a `TRACK_COMPOSED` track that plays
    /// its own Beast Special Song.
    fn get_composer_inputs(self: @T, token_id: felt252) -> felt252;
}

/// What the token's owner can change through the provider (the NFT accepts track mutations only
/// from the species' sound manager).
#[starknet::interface]
pub trait IBeastSoundTokenOwner<T> {
    /// Makes track `track_number` the token's default (the NFT's `set_default_track` rules apply).
    /// Only the token's current owner may call it.
    fn set_default_track(ref self: T, token_id: felt252, track_number: u8);
}

/// The owner's administration and track rollout. Every entry point is owner-only. The batch entry
/// points forward one NFT mutation per token, in order, and the whole call reverts if any does.
#[starknet::interface]
pub trait IBeastSoundAdmin<T> {
    /// Registers an SRC5 interface ID, for an instance upgraded from a class whose constructor did
    /// not register `IBEASTS_SOUND_MANAGER_ID`.
    fn register_interface(ref self: T, interface_id: felt252);
    /// Replaces the composer class (`get_composer_class`).
    fn set_composer_class(ref self: T, composer_class: ClassHash);
    /// `update_track_capacity(token_id, new_capacity)` for every token.
    fn batch_update_track_capacity(ref self: T, token_ids: Span<felt252>, new_capacity: u8);
    /// `add_track(token_id, inputs)` for every token, with the same inputs.
    fn batch_add_track(ref self: T, token_ids: Span<felt252>, inputs: TrackInputs);
    /// `add_track(token_id, inputs)` for every pair, each with its own inputs.
    fn batch_add_tracks(ref self: T, tracks: Span<TokenTrack>);
    /// `set_default_track(token_id, track_number)` for every token.
    fn batch_set_default_track(ref self: T, token_ids: Span<felt252>, track_number: u8);
}

#[starknet::contract]
pub mod BeastMidiProvider {
    use beast_composer::composition::beast_v3_sound::{
        BEAST_V3_ENGINE_VERSION, BeastV3LiveState, GENESIS_SPECIES_MAX, PackableBeastV3,
    };
    use beast_composer::composition::drift::{DriftClock, day_at_block, drift_anchor_blocks};
    use beast_composer::composition::genesis::{genesis_swap, species_type};
    use beast_composer::composition::params_pack::unpack_inputs;
    use beast_composer::composition::tracks;
    use beast_composer::composition::yeti::YETI;
    use core::num::traits::Zero;
    use midi::interfaces::{IMidiProvider, ISoundProvider, ISynthSettingsProvider};
    use midi::types::{TinySynthSettings, TinySynthSound};
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_interfaces::token::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_interfaces::upgrades::IUpgradeable;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_upgrades::UpgradeableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::get_block_hash_syscall;
    use starknet::{
        ClassHash, ContractAddress, SyscallResultTrait, get_block_number, get_caller_address,
    };
    use crate::beasts_v3::{
        IBEASTS_SOUND_MANAGER_ID, IBeastSoundTracksDispatcher, IBeastSoundTracksDispatcherTrait,
        IBeastStatsDispatcher, IBeastStatsDispatcherTrait, IBeastsDispatcher,
        IBeastsDispatcherTrait, ISoundManager, PackableBeast, TrackInputs, get_hash,
    };
    use crate::track_composer::{
        IBeastTrackComposerDispatcherTrait, IBeastTrackComposerLibraryDispatcher,
    };
    use super::{
        IBeastMidiProvider, IBeastSoundAdmin, IBeastSoundTokenOwner, SOUND_PRESET_MEGA,
        TRACK_COMPOSED, TRACK_SOUND_CHECK, TRACK_SPECIES_SONG, TokenTrack,
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    /// OpenZeppelin Ownable: `owner`, `transfer_ownership`, `renounce_ownership`.
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    /// OpenZeppelin SRC5: `supports_interface`.
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        collection: ContractAddress,
        composer_class: ClassHash,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    /// `collection`: the Beasts V3 NFT served. `owner` may upgrade the class and drive the rollout
    /// until it renounces ownership. `composer_class`: the declared `BeastTrackComposer`.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        collection: ContractAddress,
        owner: ContractAddress,
        composer_class: ClassHash,
    ) {
        assert(collection.is_non_zero(), 'zero collection');
        self.collection.write(collection);
        self.ownable.initializer(owner);
        self.src5.register_interface(IBEASTS_SOUND_MANAGER_ID);
        set_composer(ref self, composer_class);
    }

    /// OpenZeppelin `IUpgradeable`: the owner replaces the class (storage is kept).
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl SoundManagerImpl of ISoundManager<ContractState> {
        /// Rejects a token the NFT has not minted and a track at or above its `num_tracks` (both
        /// `track_inputs`), a version this provider does not define or data that does not fit
        /// it, and a block in the future.
        fn get_track_sound(
            self: @ContractState, token_id: felt252, track_number: u8, block_number: Option<u64>,
        ) -> TinySynthSound {
            let collection = self.collection.read();
            let inputs = IBeastSoundTracksDispatcher { contract_address: collection }
                .track_inputs(token_id, track_number);
            let (beast, track, seed) = composition(collection, token_id, inputs);
            let drift = if track == tracks::TRACK_SOUND_CHECK {
                Option::None
            } else {
                drift_clock(block_number)
            };
            sound(self, beast, track, seed, drift)
        }
    }

    #[abi(embed_v0)]
    impl MidiProviderImpl of IMidiProvider<ContractState> {
        fn get_midi(self: @ContractState, token_id: u256) -> ByteArray {
            species_song(self, token_id).midi
        }

        fn get_midi_for(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            assert(token_address == self.collection.read(), 'unsupported collection');
            species_song(self, token_id).midi
        }
    }

    #[abi(embed_v0)]
    impl SynthSettingsProviderImpl of ISynthSettingsProvider<ContractState> {
        /// The settings of the token's Species Song (`crate::synth_settings`), without composing
        /// it: one `get_beast` read.
        fn get_settings(self: @ContractState, token_id: u256) -> TinySynthSettings {
            let beast = read_beast(self.collection.read(), felt_token_id(token_id));
            track_settings(beast, tracks::TRACK_SPECIES_SONG)
        }
    }

    #[abi(embed_v0)]
    impl SoundProviderImpl of ISoundProvider<ContractState> {
        /// The token's Species Song as written, with its settings: `get_midi` and `get_settings`
        /// in one call.
        fn get_sound(self: @ContractState, token_id: u256) -> TinySynthSound {
            species_song(self, token_id)
        }
    }

    #[abi(embed_v0)]
    impl BeastMidiProviderImpl of IBeastMidiProvider<ContractState> {
        fn get_live_state(self: @ContractState, token_id: felt252) -> BeastV3LiveState {
            let collection = self.collection.read();
            let nft = IBeastsDispatcher { contract_address: collection };
            let beast = nft.get_beast(token_id);
            let rank = nft.get_beast_rank(token_id);
            let species_count = nft.get_species_count(beast.species_id);
            let stats = IBeastStatsDispatcher { contract_address: collection }
                .get_beast_stats(get_hash(beast.species_id, beast.prefix, beast.suffix));
            BeastV3LiveState {
                adventurers_killed: stats.adventurers_killed,
                scars: 0,
                summit_held_seconds: 0,
                rank,
                species_count,
            }
        }

        fn get_collection(self: @ContractState) -> ContractAddress {
            self.collection.read()
        }

        fn get_engine_version(self: @ContractState) -> u32 {
            BEAST_V3_ENGINE_VERSION
        }

        fn get_composer_class(self: @ContractState) -> ClassHash {
            self.composer_class.read()
        }

        fn get_composer_inputs(self: @ContractState, token_id: felt252) -> felt252 {
            let beast = read_beast(self.collection.read(), token_id);
            composer(self).composer_inputs(beast)
        }
    }

    #[abi(embed_v0)]
    impl BeastSoundTokenOwnerImpl of IBeastSoundTokenOwner<ContractState> {
        fn set_default_track(ref self: ContractState, token_id: felt252, track_number: u8) {
            let collection = self.collection.read();
            let owner = IERC721Dispatcher { contract_address: collection }
                .owner_of(token_id.into());
            assert(get_caller_address() == owner, 'caller is not token owner');
            IBeastSoundTracksDispatcher { contract_address: collection }
                .set_default_track(token_id, track_number);
        }
    }

    #[abi(embed_v0)]
    impl BeastSoundAdminImpl of IBeastSoundAdmin<ContractState> {
        fn register_interface(ref self: ContractState, interface_id: felt252) {
            self.ownable.assert_only_owner();
            self.src5.register_interface(interface_id);
        }

        fn set_composer_class(ref self: ContractState, composer_class: ClassHash) {
            self.ownable.assert_only_owner();
            set_composer(ref self, composer_class);
        }

        fn batch_update_track_capacity(
            ref self: ContractState, token_ids: Span<felt252>, new_capacity: u8,
        ) {
            let nft = owner_tracks(@self);
            for token_id in token_ids {
                nft.update_track_capacity(*token_id, new_capacity);
            }
        }

        fn batch_add_track(ref self: ContractState, token_ids: Span<felt252>, inputs: TrackInputs) {
            let nft = owner_tracks(@self);
            for token_id in token_ids {
                nft.add_track(*token_id, inputs);
            }
        }

        fn batch_add_tracks(ref self: ContractState, tracks: Span<TokenTrack>) {
            let nft = owner_tracks(@self);
            for track in tracks {
                let TokenTrack { token_id, inputs } = *track;
                nft.add_track(token_id, inputs);
            }
        }

        fn batch_set_default_track(
            ref self: ContractState, token_ids: Span<felt252>, track_number: u8,
        ) {
            let nft = owner_tracks(@self);
            for token_id in token_ids {
                nft.set_default_track(*token_id, track_number);
            }
        }
    }

    fn set_composer(ref self: ContractState, composer_class: ClassHash) {
        assert(composer_class.is_non_zero(), 'zero composer class');
        self.composer_class.write(composer_class);
    }

    /// The NFT's track mutations, after checking that the caller is the owner.
    fn owner_tracks(self: @ContractState) -> IBeastSoundTracksDispatcher {
        self.ownable.assert_only_owner();
        IBeastSoundTracksDispatcher { contract_address: self.collection.read() }
    }

    fn composer(self: @ContractState) -> IBeastTrackComposerLibraryDispatcher {
        IBeastTrackComposerLibraryDispatcher { class_hash: self.composer_class.read() }
    }

    /// A `u256` token ID as the felt the Beasts interfaces take.
    fn felt_token_id(token_id: u256) -> felt252 {
        match token_id.try_into() {
            Option::Some(id) => id,
            Option::None => core::panic_with_felt252('invalid token id'),
        }
    }

    /// The minted Beast `token_id` as the composer sees it (`get_beast` rejects any other).
    fn read_beast(collection: ContractAddress, token_id: felt252) -> PackableBeastV3 {
        composer_beast(IBeastsDispatcher { contract_address: collection }.get_beast(token_id))
    }

    /// The composer's Beast: the token's species, special name, level, health, tier and type, and
    /// the mega sound for `SOUND_PRESET_MEGA`. No track reads the animated flag.
    pub fn composer_beast(beast: PackableBeast) -> PackableBeastV3 {
        PackableBeastV3 {
            id: beast.species_id,
            prefix: beast.prefix,
            suffix: beast.suffix,
            level: beast.level,
            health: beast.health,
            shiny: if beast.sound_effects == SOUND_PRESET_MEGA {
                1
            } else {
                0
            },
            animated: 0,
            tier: beast.tier,
            beast_type: beast.beast_type,
        }
    }

    /// What the token's stored track `inputs` composes: the Beast (the token's own, read from the
    /// NFT, or the one its inputs describe), the composer's track number and the seed.
    fn composition(
        collection: ContractAddress, token_id: felt252, inputs: TrackInputs,
    ) -> (PackableBeastV3, u32, felt252) {
        let data = inputs.data;
        if inputs.version == TRACK_SOUND_CHECK {
            assert(data.len() == 0, 'bad track data');
            return (read_beast(collection, token_id), tracks::TRACK_SOUND_CHECK, 0);
        }
        if inputs.version == TRACK_SPECIES_SONG {
            assert(data.len() == 0, 'bad track data');
            return (read_beast(collection, token_id), tracks::TRACK_SPECIES_SONG, 0);
        }
        assert(inputs.version == TRACK_COMPOSED, 'unknown track version');
        assert(data.len() == 1 || data.len() == 2, 'bad track data');
        let beast = tracks::beast_of(unpack_inputs(*data.at(0)));
        if data.len() == 1 {
            return (beast, tracks::TRACK_SPECIAL_SONG, 0);
        }
        let seed = *data.at(1);
        assert(seed != 0, 'bought track needs a seed');
        (beast, tracks::TRACK_SPECIAL_SONG + 1, seed)
    }

    /// The day of drift at `block_number` (none: as written), its day, week and month read from
    /// their first blocks' hashes.
    fn drift_clock(block_number: Option<u64>) -> Option<DriftClock> {
        let block = match block_number {
            Option::Some(block) => block,
            Option::None => { return Option::None; },
        };
        assert(block <= get_block_number(), 'block in the future');
        let day = day_at_block(block);
        let (d, w, m) = drift_anchor_blocks(day);
        Option::Some(
            DriftClock {
                day,
                day_hash: get_block_hash_syscall(d).unwrap_syscall(),
                week_hash: get_block_hash_syscall(w).unwrap_syscall(),
                month_hash: get_block_hash_syscall(m).unwrap_syscall(),
            },
        )
    }

    /// The token's Species Song as written.
    fn species_song(self: @ContractState, token_id: u256) -> TinySynthSound {
        let beast = read_beast(self.collection.read(), felt_token_id(token_id));
        sound(self, beast, tracks::TRACK_SPECIES_SONG, 0, Option::None)
    }

    /// A composed track and the settings it is written for.
    fn sound(
        self: @ContractState,
        beast: PackableBeastV3,
        track: u32,
        seed: felt252,
        drift: Option<DriftClock>,
    ) -> TinySynthSound {
        let midi = composer(self).compose(beast, track, seed, drift);
        TinySynthSound { midi, settings: track_settings(beast, track) }
    }

    /// The settings a track is written for: the sounds its MIDI can select, the Beast type's
    /// family of presets and the drum kit, plus the mega leads for a mega Beast. The Species Song
    /// plays its swapped partner's music, so it takes the partner's type; the other tracks are the
    /// Beast's own. The Yeti's carry its avalanche's preset.
    fn track_settings(beast: PackableBeastV3, track: u32) -> TinySynthSettings {
        let species_song = track == tracks::TRACK_SPECIES_SONG
            || (track == tracks::TRACK_SPECIAL_SONG && beast.prefix == 0);
        let src = if species_song {
            genesis_swap(beast.id)
        } else {
            beast.id
        };
        if src == YETI {
            return crate::synth_settings::yeti_synth_settings(beast.shiny == 1);
        }
        let beast_type = if src != beast.id && src <= GENESIS_SPECIES_MAX {
            species_type(src)
        } else {
            beast.beast_type
        };
        crate::synth_settings::beast_synth_settings(beast_type, beast.shiny == 1)
    }
}

//! The Beasts V3 surface `BeastMidiProvider` uses: the SoundManager interface and its SRC5 ID, the
//! NFT reads and the sound-track mutations, and the types they carry.
//!
//! TEMPORARY until beasts-v3 is public. Each item is declared field for field and function for
//! function from `beasts_core` at Provable-Games/beasts-v3 `main` `4856f91` (token ID v2, #194),
//! so the selectors, calldata and Serde encodings are the same; only what the provider calls is
//! declared. Once beasts-v3 is public, replace this module with a git dependency on
//! `beasts_core` (`pack`, `sound`, `sound_manager`, `interfaces`).
//!
//! `ISoundManager::get_track_sound` returns onchain-midi-player's `TinySynthSound`
//! (`midi::types`). `beasts_core::sound_manager` declares the same type field for field, so the
//! entry point, its calldata and its reply are the same.

use midi::types::TinySynthSound;

/// `beasts_core::sound_manager::IBEASTS_SOUND_MANAGER_ID`, `selector!("beasts_sound_manager_v1")`:
/// the registry accepts a species' sound manager only if it reports this ID through SRC5.
pub const IBEASTS_SOUND_MANAGER_ID: felt252 =
    0x1f268c5b361211a8650d5f3a862f3108067a38059a190fd26aef2ac3425e7b1;

/// `beasts_core::sound_manager::ISoundManager`: what a Beasts renderer calls on a species' sound
/// manager.
#[starknet::interface]
pub trait ISoundManager<TContractState> {
    /// The playable sound of the token's track `track_number` (zero-based, below the NFT's
    /// `num_tracks`). `block_number` is the renderer's resolution of the token's saved sound mode:
    /// `Live` asks for `Some(current block - 10)`, `AtBlock(n)` for `Some(n)` and `Original` for
    /// `None`.
    fn get_track_sound(
        self: @TContractState, token_id: felt252, track_number: u8, block_number: Option<u64>,
    ) -> TinySynthSound;
}

/// `beasts_core::pack::CardCondition`: the card's print condition.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct CardCondition {
    pub centering_x_bps: u16,
    pub centering_x_direction: u8,
    pub centering_y_bps: u16,
    pub centering_y_direction: u8,
    pub hickey_count: u8,
    pub hickeys_in_art: u8,
    pub void_level: u8,
    pub voids_in_art: u8,
    pub roller_level: u8,
    pub rollers_in_art: u8,
    pub edge_chip_level: u8,
    pub corner_chip_level: u8,
}

/// `beasts_core::pack::PackableBeast`: a whole Beast, as the NFT's `get_beast` returns it (26
/// felts). `visual_effects` and `sound_effects` are presets (0..=31) whose meaning the species'
/// image provider and sound manager define. `transfer_lock_hours` is a `u64` so that it holds
/// `TRANSFER_LOCK_FOREVER` (`u64::MAX`, a Beast locked forever).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct PackableBeast {
    pub species_id: u64,
    pub prefix: u8,
    pub suffix: u8,
    pub level: u16,
    pub health: u16,
    pub visual_effects: u8,
    pub sound_effects: u8,
    pub tier: u8,
    pub beast_type: u8,
    pub minted_at_block_number: u64,
    pub transfer_damage_chance: u16,
    pub transfer_lock_hours: u64,
    pub minted_at_minute: u32,
    pub minter_data: u32,
    pub condition: CardCondition,
}

/// `beasts_core::sound::TrackInputs`: one stored track, a version tag and felts that only the
/// species' sound manager reads.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct TrackInputs {
    pub version: u16,
    pub data: Span<felt252>,
}

/// `beasts_core::sound::SoundMode`: how a token's tracks play, saved for all of them. Declared in
/// storage-tag order, so the Serde encoding is Live `[0]`, Original `[1]` and AtBlock(n) `[2, n]`.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum SoundMode {
    Live,
    Original,
    AtBlock: u64,
}

/// The `beasts_core::interfaces::IBeasts` read the provider makes. It rejects a token that does not
/// exist with the ERC721 invalid-token error.
#[starknet::interface]
pub trait IBeasts<TContractState> {
    fn get_beast(self: @TContractState, token_id: felt252) -> PackableBeast;
}

/// The `beasts_core::sound::IBeastSoundTracks` entry points the provider calls. The mutations
/// accept only the token's species' registered sound manager as the caller, and each emits two
/// events (its own and an ERC-4906 `MetadataUpdate`).
#[starknet::interface]
pub trait IBeastSoundTracks<TContractState> {
    /// The track at zero-based `track_number`; `'Sound: invalid track'` at or above `num_tracks`.
    fn track_inputs(self: @TContractState, token_id: felt252, track_number: u8) -> TrackInputs;
    fn update_track_capacity(ref self: TContractState, token_id: felt252, new_capacity: u8);
    fn add_track(ref self: TContractState, token_id: felt252, inputs: TrackInputs) -> u8;
    fn set_default_track(ref self: TContractState, token_id: felt252, track_number: u8);
    fn set_sound_mode(ref self: TContractState, token_id: felt252, mode: SoundMode);
}

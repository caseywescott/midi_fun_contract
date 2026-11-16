//! The Loot Dungeon Sound ABI, in the pattern of Beast Sound v1.1.0 (`beast_contracts::pure_composer`):
//! one call shape for every track, `compose(inputs, sound_effects)` and, on a day of drift,
//! `compose_drift(inputs, sound_effects, drift)`, returning a Standard MIDI File as the Loot lab plays
//! it: each pitched channel's program is the instrument the lab's band gives it (for the Loot FM
//! pack), and Name Songs and Rounds are lifted as the lab lifts them (+12, +7 semitones).
//!
//! `sound_effects` is a token's, as in v1.1 (`beast_composer::composition::performance`): 0 as
//! written, 1 mega, 2 echo, 3 mega and echo; 4 and up are rejected. Songs are rendered by the pinned
//! v1.1 `BeastPureComposer`, so they get the whole v1.1 performance (mega leads, echo, faster tempo,
//! louder, articulation). Editions, Rounds and Sound Checks play their own tempo and dynamics: only
//! the mega sound applies (as v1.1 does for its editions).
//!
//! `drift`: v1.1's `DriftInputs` (the day from 1 and the hashes of the first blocks of its day, week
//! and month). Day 1 plays the track as written, as in the lab. A Song's drift belongs to the song's
//! name: its `name_variant_id` is taken from the inputs. Sound Checks do not drift.
use beast_composer::inputs::ComposerInputs;
use beast_composer::inputs::drift::DriftInputs;
use midi::types::TinySynthSound;
use starknet::{ClassHash, ContractAddress};

/// A Species Song (`name` 0) or a Name Song (special-name variant 1..1242) of Loot Beast `species`
/// (76..105).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct LootSongInputs {
    pub species: u32,
    pub name: u16,
}

/// Monthly Track Edition `edition` (from 1), bought as purchase `purchase` (the lab's purchase
/// number, from 1; the seed is `purchase_seed(purchase)`).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct LootEditionInputs {
    pub species: u32,
    pub edition: u32,
    pub purchase: u64,
}

/// A Round: purchase 0 is the species' own, 1.. a bought Round.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct LootRoundInputs {
    pub species: u32,
    pub purchase: u64,
}

/// A Sound Check: take 0 is the species' own, 1.. another take.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct LootSoundCheckInputs {
    pub species: u32,
    pub take: u64,
}

#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum LootInputs {
    Song: LootSongInputs,
    Edition: LootEditionInputs,
    Round: LootRoundInputs,
    SoundCheck: LootSoundCheckInputs,
}

/// `LootPureComposer`: storage-free, Editions, Rounds and Sound Checks (a `Song` reverts: songs are
/// the Beast composer's, through the provider).
#[starknet::interface]
pub trait ILootPureComposer<T> {
    fn compose(self: @T, inputs: LootInputs, sound_effects: u8) -> ByteArray;
    fn compose_drift(self: @T, inputs: LootInputs, sound_effects: u8, drift: DriftInputs) -> ByteArray;
}

/// `LootMidiProvider`: every Loot track (`compose` / `compose_drift`, songs included) and where the
/// pieces live.
#[starknet::interface]
pub trait ILootMidiProvider<T> {
    fn compose(self: @T, inputs: LootInputs, sound_effects: u8) -> ByteArray;
    fn compose_drift(self: @T, inputs: LootInputs, sound_effects: u8, drift: DriftInputs) -> ByteArray;
    /// The FM sound pack contract (`LootFmPack`) that plays these files.
    fn sound_pack(self: @T) -> ContractAddress;
    /// The `LootPureComposer` class (Editions, Rounds, Sound Checks).
    fn get_composer_class(self: @T) -> ClassHash;
    /// The Beast Sound v1.1.0 `BeastPureComposer` class (Songs).
    fn get_song_class(self: @T) -> ClassHash;
    /// Owner only (until ownership is renounced): point at new classes or a new sound pack.
    fn set_classes(ref self: T, composer_class: ClassHash, song_class: ClassHash, pack: ContractAddress);
}

/// Beast Sound v1.1.0 `beast_contracts::pure_composer::IBeastPureComposer`, the same ABI (the
/// selectors are the function names), for library calls into the pinned class.
#[starknet::interface]
pub trait IBeastPureComposer<T> {
    fn compose(self: @T, inputs: ComposerInputs, sound_effects: u8) -> TinySynthSound;
    fn compose_drift(
        self: @T, inputs: ComposerInputs, sound_effects: u8, drift: DriftInputs,
    ) -> TinySynthSound;
}

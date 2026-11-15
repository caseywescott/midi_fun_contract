//! The Loot Dungeon Sound ABI. Every getter returns a Standard MIDI File as the Loot lab plays it:
//! orchestrated for the Loot FM pack (each channel's program is the instrument the lab's band gives
//! it) and, for Name Songs and Rounds, lifted as the lab lifts them (+12, +7 semitones).
//!
//! `drift`: none plays a track as written; a day (`DriftClock`: the day from 1 and the hashes of
//! the first blocks of its day, week and month, `beast_composer::composition::drift`) plays it on
//! that day. Day 1 is as written, as in the lab. `purchase`: the purchase number the lab uses
//! (1, 2, ...); the track's seed is `purchase_seed(purchase)`. For Rounds and Sound Checks 0 is the
//! species' own.
use beast_composer::composition::drift::DriftClock;

#[starknet::interface]
pub trait ILootSound<T> {
    /// The Species Song (Beasts composer v1.0.1, unchanged).
    fn species_song(self: @T, species: u32, mega: bool, drift: Option<DriftClock>) -> ByteArray;
    /// A Name Song: special-name variant `name` (1..1242).
    fn name_song(
        self: @T, species: u32, mega: bool, name: u16, drift: Option<DriftClock>,
    ) -> ByteArray;
    /// Monthly Track Edition `edition` (from 1), bought as purchase `purchase` (from 1).
    fn edition(
        self: @T, species: u32, mega: bool, edition: u32, purchase: u64, drift: Option<DriftClock>,
    ) -> ByteArray;
    /// A Round (0 = the species' own).
    fn round(
        self: @T, species: u32, mega: bool, purchase: u64, drift: Option<DriftClock>,
    ) -> ByteArray;
    /// A Sound Check (take 0 = the species' own). Sound Checks do not drift.
    fn sound_check(self: @T, species: u32, mega: bool, take: u64) -> ByteArray;
    /// The FM sound pack contract that plays these files.
    fn sound_pack(self: @T) -> starknet::ContractAddress;
}

/// The Species/Name Song class (library-called by LootSound).
#[starknet::interface]
pub trait ILootSongComposer<T> {
    fn song(self: @T, species: u32, mega: bool, name: u16, drift: Option<DriftClock>) -> ByteArray;
}

/// The Editions / Rounds / Sound Checks class(es) (library-called by LootSound).
#[starknet::interface]
pub trait ILootTrackComposer<T> {
    fn edition(
        self: @T, species: u32, mega: bool, edition: u32, purchase: u64, drift: Option<DriftClock>,
    ) -> ByteArray;
    fn round(
        self: @T, species: u32, mega: bool, purchase: u64, drift: Option<DriftClock>,
    ) -> ByteArray;
    fn sound_check(self: @T, species: u32, mega: bool, take: u64) -> ByteArray;
}

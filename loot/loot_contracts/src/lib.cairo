//! Loot Dungeon Sound contracts, in the pattern of Beast Sound v1.1.0: `LootPureComposer` (the one
//! storage-free composer class: Editions, Rounds, Sound Checks), `LootMidiProvider` (every track,
//! Songs through the pinned v1.1.0 `BeastPureComposer`; Ownable, Upgradeable) and `LootFmPack` (the
//! FM sound pack).
pub mod composer;
pub mod fm_pack;
pub mod fm_pack_data;
pub mod interfaces;
pub mod provider;
#[cfg(test)]
mod front_tests;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod v11_song_tests;

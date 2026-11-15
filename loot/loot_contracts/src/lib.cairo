//! Loot Dungeon Sound contracts: `LootSound` (front), `LootSongComposer` (Species/Name Songs),
//! the track composer class(es) (Editions, Rounds, Sound Checks) and `LootFmPack` (the FM sound pack).
pub mod edition_composer;
pub mod fm_pack;
pub mod fm_pack_data;
pub mod interfaces;
pub mod round_composer;
pub mod song_composer;
pub mod sound;
#[cfg(test)]
mod front_tests;
#[cfg(test)]
mod tests;

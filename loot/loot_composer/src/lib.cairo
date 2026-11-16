//! Loot Dungeon Sound composer. Each module is the Cairo port of one file of
//! offchain/loot-sound/src, byte for byte (parity scripts in scripts/). Each parity fixture is behind a
//! feature (all on by default): a batch script builds only its own (`--no-default-features --features
//! rounds_fx`), so the test crate compiles in less memory.
pub mod common;
pub mod orchestra;
pub mod orchestra_data;
pub mod songs;
pub mod species;
#[cfg(test)]
mod common_tests;
#[cfg(test, feature: 'songs_fx')]
mod songs_parity_tests;
pub mod editions;
pub mod editions_data;
#[cfg(test, feature: 'editions_fx')]
mod editions_tests;
#[cfg(test, feature: 'gas_fx')]
mod editions_gas;
pub mod rounds;
pub mod rounds_data;
#[cfg(test, feature: 'rounds_fx')]
mod rounds_parity;
pub mod checks;
pub mod checks_data;
#[cfg(test, feature: 'checks_fx')]
mod checks_parity;
#[cfg(test, feature: 'played_fx')]
mod played_tests;

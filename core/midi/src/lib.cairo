//! midi: the core MIDI system's library. Everything a composer, a provider or a page needs to
//! share, and no contracts.
//!
//! - `types`: the data that crosses contracts: `TinySynthSettings`, `TinySynthSound` and their
//!   parts (onchain-midi-player's own types, re-exported).
//! - `interfaces`: `IMidiProvider`, `ISynthSettingsProvider`, `ISoundProvider` and
//!   `IMidiSoundPage`, with their dispatchers.
//! - `settings`: `default_settings` and `validate` for `TinySynthSettings`.
//! - `smf`: the file format. `TrackWriter` turns timed events into a track body (delta times,
//!   optional running status, End of Track); `smf_bytes` wraps track bodies in `MThd` and `MTrk`
//!   chunks.
//! - `pack`: getting bytes out of a contract: `bytes_to_byte_array` (a `ByteArray`, what
//!   `IMidiProvider::get_midi` returns) and `to_felt252_array` (`[byte_len, 31-byte words...]`).
//!
//! No storage and no syscalls. Composers (`beast_composer`) and contracts (`midi_contracts`,
//! `beast_contracts`) build on it; it depends on nothing of theirs.

pub mod interfaces;
pub mod pack;
pub mod settings;
pub mod smf;

#[cfg(test)]
mod tests;
pub mod types;

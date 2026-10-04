//! midi: Standard MIDI Files onchain.
//!
//! - `smf`: the file format. `TrackWriter` turns timed events into a track body (delta times,
//!   optional running status, End of Track); `smf_bytes` wraps track bodies in `MThd` and `MTrk`
//!   chunks.
//! - `pack`: getting bytes out of a contract: `bytes_to_byte_array` (a `ByteArray`, what
//!   `IMidiProvider::get_midi` returns) and `to_felt252_array` (`[byte_len, 31-byte words...]`).
//!
//! No storage, no syscalls and no dependencies: composers (`beast_music`) and providers
//! (`midi_provider`) build on it.

pub mod pack;
pub mod smf;

#[cfg(test)]
mod tests;

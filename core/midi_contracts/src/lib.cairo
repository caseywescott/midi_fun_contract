//! midi_contracts: the core MIDI system's contracts. Their types and interfaces are in `midi`.
//!
//! - `page::MidiSoundPage`: an NFT's `token_uri` with its music as `animation_url`, built onchain
//!   from any `midi::interfaces::IMidiProvider`.
//! - `examples::scale::ScaleMidiProvider`: an `IMidiProvider` unrelated to Beasts, to show the
//!   interface is collection-agnostic.

pub mod examples;
pub mod page;

#[cfg(test)]
mod tests;

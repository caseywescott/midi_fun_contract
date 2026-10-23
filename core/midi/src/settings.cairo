//! `TinySynthSettings` helpers from onchain-midi-player, re-exported: `default_settings()` (the
//! engine defaults: no custom waves or timbres) and `validate(@settings)`, which applies the checks
//! `midi_segment` makes and reverts on the first failure.

pub use onchain_midi_types::settings::{default_settings, validate};

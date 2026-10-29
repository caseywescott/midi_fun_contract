//! The data types of the core MIDI system: what a provider serves and a page plays.
//!
//! These are onchain-midi-player's own types, re-exported from its `onchain_midi_types` package
//! (pinned in the workspace `Scarb.toml`), so there is no copy to keep in sync: `midi::types::X`
//! and `onchain_midi_types::types::X` are the same type, which the class re-exports as
//! `onchain_midi_player::types::X`, and a value built here is what the class's
//! `midi_segment(midi, settings)` takes.
//!
//! Every fractional field is fixed point: a stored `x` means `x / FIXED_POINT_SCALE`. Ranges and
//! the checks `midi_segment` applies (`midi::settings::validate`) are documented on the class's
//! types and in its README.

pub use onchain_midi_types::types::{
    FIXED_POINT_SCALE, Filter, FilterKind, Operator, Timbre, TinySynthSettings, TinySynthSound,
    WaveDef, Waveform,
};

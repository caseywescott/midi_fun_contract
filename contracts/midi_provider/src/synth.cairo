//! Sound settings for onchain-tinysynth's `midi_segment(midi, settings)`: a mirror of
//! `onchain_tinysynth::types` (Provable-Games/onchain-tinysynth at 973f4cf), field for field and
//! variant for variant, so a value serializes to the same felts and a caller deserializes it
//! straight into the class's own types. The mirror exists because that package needs Cairo 2.20 and
//! this workspace builds with 2.11; once both match, these become a re-export.
//!
//! Every fractional field is fixed point: a stored `x` means `x / FIXED_POINT_SCALE`. Ranges and
//! the checks `midi_segment` applies are documented on the class's types.

pub const FIXED_POINT_SCALE: u32 = 10_000;

/// Engine-wide settings plus custom sounds (`SynthSettings`).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct SynthSettings {
    /// 0 = chip-tune built-ins, 1 = FM built-ins.
    pub quality: u8,
    /// Reverb level in percent; 0 is off.
    pub reverb: u8,
    /// Master volume in percent of full scale.
    pub master_vol: u8,
    /// Maximum simultaneous notes.
    pub voices: u8,
    /// Custom waveforms; must be empty until the class's issue #2 lands.
    pub waves: Span<WaveDef>,
    /// Sounds replacing built-in programs (0..=127) or drum notes (35..=81).
    pub timbres: Span<Timbre>,
}

/// One custom sound, selected by a program change to `slot` or by note `slot` on channel 10.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Timbre {
    pub drum: bool,
    pub slot: u8,
    /// 1..=8 operators.
    pub operators: Span<Operator>,
}

/// One oscillator, TinySynth's operator model (`{g, w, v, t, f, a, h, d, s, r, p, q, k}`).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Operator {
    /// [g] 0 = audio out, 1..=10 = FM of that (earlier) operator, 11..=18 = AM of `route - 10`.
    pub route: u8,
    /// [w]
    pub wave: Waveform,
    /// [v] level
    pub volume: u32,
    /// [t] frequency multiple of the note; 0 = fixed at `offset_hz`
    pub ratio: u32,
    /// [f] frequency offset, Hz
    pub offset_hz: i32,
    /// [a] seconds
    pub attack: u32,
    /// [h] seconds
    pub hold: u32,
    /// [d] time constant, seconds
    pub decay: u32,
    /// [s] multiple of `volume`
    pub sustain: u32,
    /// [r] time constant, seconds
    pub release: u32,
    /// [p] pitch envelope target, multiple of the start frequency
    pub pitch_ratio: u32,
    /// [q] pitch envelope time constant, seconds
    pub pitch_time: u32,
    /// [k] volume key scaling
    pub key_scale: i32,
    /// Must be `None` until the class's issue #3 lands.
    pub filter: Option<Filter>,
}

/// Variant order is the wire tag: never reorder or insert.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Waveform {
    Sine,
    Square,
    Sawtooth,
    Triangle,
    WhiteNoise,
    MetallicNoise,
    Custom: u8,
}

#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum WaveDef {
    Harmonics: Span<u16>,
    Samples: Span<i8>,
}

#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Filter {
    pub kind: FilterKind,
    pub cutoff: u32,
    pub key_track: bool,
    pub q: u32,
}

#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum FilterKind {
    LowPass,
    HighPass,
    BandPass,
}

/// The class's `default_settings()`: FM built-ins, reverb 30, volume 40, 64 voices, no timbres.
pub fn default_settings() -> SynthSettings {
    SynthSettings {
        quality: 1, reverb: 30, master_vol: 40, voices: 64, waves: [].span(), timbres: [].span(),
    }
}

/// Optional companion to `IMidiProvider`: the sound settings a provider's MIDI is written for.
/// A caller building an onchain-tinysynth page passes them with the MIDI:
/// `midi_segment(provider.get_midi(token_id), provider.get_settings(token_id))`.
/// The settings may depend on the token (a provider can give rare tokens other sounds) but, like
/// the MIDI, never on anything the caller passes besides the token ID.
#[starknet::interface]
pub trait ISynthSettingsProvider<T> {
    /// `SynthSettings` for `token_id` of the collection this provider serves. May revert for an
    /// invalid token ID; never reverts because live state is unavailable.
    fn get_settings(self: @T, token_id: u256) -> SynthSettings;
}

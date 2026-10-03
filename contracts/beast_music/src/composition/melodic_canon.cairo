//! Renaissance Improvised-Canon — Generator.
//!
//! Deterministic melodic-canon generation. A seed selects a `CanonConfig`, mode, length and
//! time unit; an LCG walks the leader within the proven-consonant alphabet (see `canon_rules`);
//! the followers are forced exact delayed transpositions; correctness is asserted, not searched.
//!
//! Output is a stream of [`NoteEvent`]s for the existing MIDI/media engine.
//!
//! See `docs/renaissance_canon_improvisation_spec.md`.

use core::option::OptionTrait;

/// Keep the leader within ±this many diatonic degrees of its start (≈ one octave), so realized
/// pitches stay in a singable register and MIDI keynums never under/overflow.
pub const REGISTER_BAND: i32 = 7;
pub const DEFAULT_VELOCITY: u8 = 90;

// ──────────────────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────────────────

/// A single sounding note for the renderer.
#[derive(Copy, Drop)]
pub struct NoteEvent {
    /// Absolute grid position (in `time_unit`s).
    pub time: u32,
    pub duration: u32,
    /// MIDI keynum.
    pub pitch: u8,
    pub velocity: u8,
    pub voice_id: u32,
}

// ──────────────────────────────────────────────────────────
// Modal realization
// ──────────────────────────────────────────────────────────

/// Semitone offsets from the final for the 7 diatonic degrees of a mode.
pub fn mode_scale(mode_id: u8) -> Span<u8> {
    if mode_id == MODE_MELODIC_MINOR {
        // Jazz melodic minor ascending: 1 2 b3 4 5 6 7
        return array![0_u8, 2, 3, 5, 7, 9, 11].span();
    }
    if mode_id == MODE_WHOLE_TONE {
        // Whole tone: 1 2 3 #4 #5 b7 — six degrees per octave
        return array![0_u8, 2, 4, 6, 8, 10].span();
    }
    let m = mode_id % 6;
    if m == 0 {
        array![0_u8, 2, 4, 5, 7, 9, 11].span() // Ionian / major
    } else if m == 1 {
        array![0_u8, 2, 3, 5, 7, 9, 10].span() // Dorian
    } else if m == 2 {
        array![0_u8, 1, 3, 5, 7, 8, 10].span() // Phrygian
    } else if m == 3 {
        array![0_u8, 2, 4, 6, 7, 9, 11].span() // Lydian
    } else if m == 4 {
        array![0_u8, 2, 4, 5, 7, 9, 10].span() // Mixolydian
    } else {
        array![0_u8, 2, 3, 5, 7, 8, 10].span() // Aeolian / natural minor
    }
}
/// Melodic minor ascending (outside the legacy `% 6` diatonic set).
pub const MODE_MELODIC_MINOR: u8 = 6;
/// Whole tone — six scale degrees per octave (outside the legacy `% 6` diatonic set).
pub const MODE_WHOLE_TONE: u8 = 7;

/// Realize a signed diatonic degree to a MIDI keynum. Degree 0 maps to `tonic_keynum`.
/// Uses an octave bias so all arithmetic stays unsigned (no signed division).
/// `degrees_per_octave` is 7 for diatonic modes, 6 for whole tone.
pub fn degree_to_keynum_sized(
    degree: i32, tonic_keynum: u8, scale: Span<u8>, degrees_per_octave: u32,
) -> u8 {
    let bias: i32 = (10 * degrees_per_octave).try_into().unwrap();
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    let oct: u32 = du / degrees_per_octave;
    let idx: u32 = du % degrees_per_octave;
    let semis: u32 = (*scale.at(idx)).into();
    let base: u32 = tonic_keynum.into();
    let oct_bias: u32 = 12 * 10;
    let total: u32 = base + 12 * oct + semis - oct_bias;
    total.try_into().unwrap()
}

/// Realize a signed diatonic degree to a MIDI keynum. Degree 0 maps to `tonic_keynum`.
/// Uses an octave bias so all arithmetic stays unsigned (no signed division).
pub fn degree_to_keynum(degree: i32, tonic_keynum: u8, scale: Span<u8>) -> u8 {
    degree_to_keynum_sized(degree, tonic_keynum, scale, 7)
}

/// Realize a chromatic (semitone-lattice) degree: the degree *is* the signed semitone offset from
/// the tonic. Octave-biased so all arithmetic stays unsigned.
pub fn chromatic_degree_to_keynum(degree: i32, tonic_keynum: u8) -> u8 {
    let bias: i32 = 60;
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    let base: u32 = tonic_keynum.into();
    (base + du - 60).try_into().unwrap()
}

/// Realize a degree on either lattice. Diatonic (octave 7) goes through the mode; chromatic
/// (octave 12) maps the degree directly to a semitone offset.
pub fn realize_degree(octave: u32, degree: i32, tonic_keynum: u8, mode_id: u8) -> u8 {
    if octave == 12 {
        chromatic_degree_to_keynum(degree, tonic_keynum)
    } else if mode_id == MODE_WHOLE_TONE {
        degree_to_keynum_sized(degree, tonic_keynum, mode_scale(mode_id), 6)
    } else {
        degree_to_keynum(degree, tonic_keynum, mode_scale(mode_id))
    }
}

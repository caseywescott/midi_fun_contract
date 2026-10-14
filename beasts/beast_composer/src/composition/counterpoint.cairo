//! Linear two-voice counterpoint: Parsons contour + greedy scored selection.
//!
//! Forward-only: each counter note is chosen from local candidates and committed.
//! No backtracking or retroactive fixes.
//!
//! Mode handling supports a single fixed mode/world or a per-note timeline aligned
//! to cantus indices.

use crate::modes::Modes;

/// Sentinel pitch for rests on the tile grid (no sounding note at this index).
pub const REST_PITCH: u8 = 255;

pub fn is_rest_pitch(p: u8) -> bool {
    p == REST_PITCH
}

// ──────────────────────────────────────────────────────────
// Mode ID registry (stable u8 indices for timelines)
// ──────────────────────────────────────────────────────────

pub fn mode_to_id(mode: Modes) -> u8 {
    match mode {
        Modes::Major(()) => 0,
        Modes::Minor(()) => 1,
        Modes::Lydian(()) => 2,
        Modes::Mixolydian(()) => 3,
        Modes::Dorian(()) => 4,
        Modes::Phrygian(()) => 5,
        Modes::Locrian(()) => 6,
        Modes::Aeolian(()) => 7,
        Modes::HarmonicMinor(()) => 8,
        Modes::NaturalMinor(()) => 9,
        Modes::Chromatic(()) => 10,
        Modes::Pentatonic(()) => 11,
        Modes::MelodicMinor(()) => 12,
        Modes::DorianFlat2(()) => 13,
        Modes::LydianAugmented(()) => 14,
        Modes::LydianDominant(()) => 15,
        Modes::MixolydianFlat13(()) => 16,
        Modes::LocrianNatural2(()) => 17,
        Modes::Altered(()) => 18,
        Modes::HarmonicMajor(()) => 19,
        Modes::DorianFlat5(()) => 20,
        Modes::PhrygianFlat4(()) => 21,
        Modes::LydianFlat3(()) => 22,
        Modes::MixolydianFlat2(()) => 23,
        Modes::LydianAugmentedSharp2(()) => 24,
        Modes::LocrianDoubleFlat7(()) => 25,
        Modes::DorianSharp4(()) => 26,
        Modes::LocrianNatural6(()) => 27,
        Modes::WholeTone(()) => 28,
        Modes::HalfWholeDiminished(()) => 29,
        Modes::WholeHalfDiminished(()) => 30,
    }
}

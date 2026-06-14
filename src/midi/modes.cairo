use core::array::ArrayTrait;
use koji::midi::types::Modes;
//**********************************************************************************************************
//  Mode & Key Definitions
//
// We define Scales/Modes as an ordered array of ascending interval steps
//
// Example 1: [do, re, me, fa, sol, la, ti] in C Major Key -> C,D,E,F,G,A,B -> Modal Steps: [2,2,1,2,2,1]
//
// It is from these defined steps that we can compute a 'Key' AKA Pitches of a Mode at a given Note Base
//
// For microtonal scales, steps should be defined as ratios of BASEOCTAVE
//**********************************************************************************************************

pub fn major_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

pub fn minor_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

pub fn lydian_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

pub fn mixolydian_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

pub fn dorian_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

pub fn phrygian_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

pub fn locrian_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

pub fn aeolian_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

pub fn harmonicminor_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

pub fn naturalminor_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Melodic minor (jazz minor): 1 2 b3 4 5 6 7.
pub fn melodicminor_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

// Dorian b2 (Phrygian #6): 1 b2 b3 4 5 6 b7.
pub fn dorian_flat2_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Lydian augmented (#5): 1 2 3 #4 #5 6 7.
pub fn lydian_augmented_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

// Lydian dominant (acoustic/overtone): 1 2 3 #4 5 6 b7.
pub fn lydian_dominant_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Mixolydian b13 (b6): 1 2 3 4 5 b6 b7.
pub fn mixolydian_flat13_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Locrian natural 2 (Aeolian b5): 1 2 b3 4 b5 b6 b7.
pub fn locrian_natural2_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Altered (super Locrian): 1 b2 b3 b4 b5 b6 b7.
pub fn altered_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Harmonic major: 1 2 3 4 5 b6 7.
pub fn harmonicmajor_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

// Dorian b5 (Dorian-Locrian), harmonic major mode 2: 1 2 b3 4 b5 6 b7.
pub fn dorian_flat5_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Phrygian b4, harmonic major mode 3: 1 b2 b3 b4 5 b6 b7.
pub fn phrygian_flat4_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Lydian b3, harmonic major mode 4: 1 2 b3 #4 5 6 7.
pub fn lydian_flat3_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

// Mixolydian b2, harmonic major mode 5: 1 b2 3 4 5 6 b7.
pub fn mixolydian_flat2_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Lydian augmented #2, harmonic major mode 6: 1 #2 3 #4 #5 6 7.
pub fn lydian_augmented_sharp2_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

// Locrian bb7, harmonic major mode 7: 1 b2 b3 4 b5 b6 bb7.
pub fn locrian_double_flat7_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    mode.span()
}

// Dorian #4, harmonic minor mode 4: 1 2 b3 #4 5 6 b7.
pub fn dorian_sharp4_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Locrian natural 6, harmonic minor mode 2: 1 b2 b3 4 b5 6 b7.
pub fn locrian_natural6_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Whole tone: 1 2 3 #4 #5 b7.
pub fn whole_tone_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Dominant diminished (half-whole): 1 b2 b3 3 #4 5 6 b7.
pub fn half_whole_diminished_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

// Pure diminished (whole-half): 1 2 b3 4 b5 b6 bb7 7.
pub fn whole_half_diminished_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

pub fn chromatic_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 1);
    mode.span()
}

pub fn pentatonic_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 3);
    mode.span()
}

pub fn mode_steps(mode: Modes) -> Span<u8> {
    match mode {
        Modes::Major(()) => major_steps(),
        Modes::Minor(()) => minor_steps(),
        Modes::Lydian(()) => lydian_steps(),
        Modes::Mixolydian(()) => mixolydian_steps(),
        Modes::Dorian(()) => dorian_steps(),
        Modes::Phrygian(()) => phrygian_steps(),
        Modes::Locrian(()) => locrian_steps(),
        Modes::Aeolian(()) => aeolian_steps(),
        Modes::HarmonicMinor(()) => harmonicminor_steps(),
        Modes::NaturalMinor(()) => naturalminor_steps(),
        Modes::Chromatic(()) => chromatic_steps(),
        Modes::Pentatonic(()) => pentatonic_steps(),
        Modes::MelodicMinor(()) => melodicminor_steps(),
        Modes::DorianFlat2(()) => dorian_flat2_steps(),
        Modes::LydianAugmented(()) => lydian_augmented_steps(),
        Modes::LydianDominant(()) => lydian_dominant_steps(),
        Modes::MixolydianFlat13(()) => mixolydian_flat13_steps(),
        Modes::LocrianNatural2(()) => locrian_natural2_steps(),
        Modes::Altered(()) => altered_steps(),
        Modes::HarmonicMajor(()) => harmonicmajor_steps(),
        Modes::DorianFlat5(()) => dorian_flat5_steps(),
        Modes::PhrygianFlat4(()) => phrygian_flat4_steps(),
        Modes::LydianFlat3(()) => lydian_flat3_steps(),
        Modes::MixolydianFlat2(()) => mixolydian_flat2_steps(),
        Modes::LydianAugmentedSharp2(()) => lydian_augmented_sharp2_steps(),
        Modes::LocrianDoubleFlat7(()) => locrian_double_flat7_steps(),
        Modes::DorianSharp4(()) => dorian_sharp4_steps(),
        Modes::LocrianNatural6(()) => locrian_natural6_steps(),
        Modes::WholeTone(()) => whole_tone_steps(),
        Modes::HalfWholeDiminished(()) => half_whole_diminished_steps(),
        Modes::WholeHalfDiminished(()) => whole_half_diminished_steps(),
    }
}

/// True when the scale contains a minor third above its root.
pub fn has_minor_third(mode: Modes) -> bool {
    let steps = mode_steps(mode);
    let mut semitones = 0_u8;
    let mut i = 0;
    loop {
        if semitones == 3 {
            return true;
        }
        if semitones > 3 || i >= steps.len() {
            return false;
        }
        semitones += *steps.at(i);
        i += 1;
    };
    false
}

/// Curated dark palette for Beast traits, ordered from warmer minor colors to maximum tension.
pub fn is_dark_mode(mode: Modes) -> bool {
    match mode {
        Modes::Minor(()) | Modes::NaturalMinor(()) | Modes::Dorian(()) | Modes::Aeolian(())
        | Modes::Phrygian(()) | Modes::Locrian(()) | Modes::HarmonicMinor(())
        | Modes::DorianSharp4(()) | Modes::LocrianNatural6(()) | Modes::DorianFlat5(())
        | Modes::PhrygianFlat4(()) | Modes::HalfWholeDiminished(())
        | Modes::WholeHalfDiminished(()) => true,
        _ => false,
    }
}

pub fn dark_mode_count() -> u8 {
    11
}

/// Primary dark modes without semantic aliases, ordered from warmest to darkest.
pub fn dark_mode_at(index: u8) -> Modes {
    let i = index % dark_mode_count();
    if i == 0 {
        Modes::Dorian(())
    } else if i == 1 {
        Modes::Aeolian(())
    } else if i == 2 {
        Modes::Phrygian(())
    } else if i == 3 {
        Modes::Locrian(())
    } else if i == 4 {
        Modes::HarmonicMinor(())
    } else if i == 5 {
        Modes::DorianSharp4(())
    } else if i == 6 {
        Modes::LocrianNatural6(())
    } else if i == 7 {
        Modes::DorianFlat5(())
    } else if i == 8 {
        Modes::PhrygianFlat4(())
    } else if i == 9 {
        Modes::HalfWholeDiminished(())
    } else {
        Modes::WholeHalfDiminished(())
    }
}

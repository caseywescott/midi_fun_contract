use array::ArrayTrait;
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

fn major_steps() -> Span<u8> {
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

fn minor_steps() -> Span<u8> {
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

fn lydian_steps() -> Span<u8> {
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

fn mixolydian_steps() -> Span<u8> {
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

fn dorian_steps() -> Span<u8> {
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

fn phrygian_steps() -> Span<u8> {
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

fn locrian_steps() -> Span<u8> {
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

fn aeolian_steps() -> Span<u8> {
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

fn harmonicminor_steps() -> Span<u8> {
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

fn naturalminor_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 1);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    mode.span()
}

fn chromatic_steps() -> Span<u8> {
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
    mode.span()
}

fn pentatonic_steps() -> Span<u8> {
    let mut mode: Array<u8> = ArrayTrait::new();
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 3);
    ArrayTrait::append(ref mode, 2);
    ArrayTrait::append(ref mode, 3);
    mode.span()
}

fn mode_steps(mode: Modes) -> Span<u8> {
    match mode {
        Modes::Major => major_steps(),
        Modes::Minor => minor_steps(),
        Modes::Lydian => lydian_steps(),
        Modes::Mixolydian => mixolydian_steps(),
        Modes::Dorian => dorian_steps(),
        Modes::Phrygian => phrygian_steps(),
        Modes::Locrian => locrian_steps(),
        Modes::Aeolian => aeolian_steps(),
        Modes::Harmonicminor => harmonicminor_steps(),
        Modes::Naturalminor => naturalminor_steps(),
        Modes::Chromatic => chromatic_steps(),
        Modes::Pentatonic => pentatonic_steps(),
    }
}

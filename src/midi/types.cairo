use koji::math::Time;
use koji::midi::modes::{
    major_steps, minor_steps, lydian_steps, mixolydian_steps, dorian_steps, phrygian_steps,
    locrian_steps, aeolian_steps, harmonicminor_steps, naturalminor_steps, chromatic_steps,
    pentatonic_steps
};


/// =========================================
/// ================ MIDI ===================
/// =========================================

#[derive(Copy, Drop, Serde)]
pub struct Midi {
    pub events: Span<Message>
}


/// =========================================
/// ================ MESSAGES ===============
/// =========================================

#[derive(Copy, Drop, Serde)]
pub enum Message {
    NOTE_ON: NoteOn,
    NOTE_OFF: NoteOff,
    SET_TEMPO: SetTempo,
    TIME_SIGNATURE: TimeSignature,
    CONTROL_CHANGE: ControlChange,
    PITCH_WHEEL: PitchWheel,
    AFTER_TOUCH: AfterTouch,
    POLY_TOUCH: PolyTouch,
    PROGRAM_CHANGE: ProgramChange,
    SYSTEM_EXCLUSIVE: SystemExclusive,
}

#[derive(Copy, Drop, Serde)]
pub struct NoteOn {
    pub channel: u8,
    pub note: u8,
    pub velocity: u8,
    pub time: Time
}

#[derive(Copy, Drop, Serde)]
pub struct NoteOff {
    pub channel: u8,
    pub note: u8,
    pub velocity: u8,
    pub time: Time
}

#[derive(Copy, Drop, Serde)]
pub struct SetTempo {
    pub tempo: u32, // microseconds per beat
    pub time: Option<Time>
}

#[derive(Copy, Drop, Serde)]
pub struct TimeSignature {
    pub numerator: u8,
    pub denominator: u8,
    pub clocks_per_click: u8,
    pub time: Option<Time>
}

#[derive(Copy, Drop, Serde)]
pub struct ControlChange {
    pub channel: u8,
    pub control: u8,
    pub value: u8,
    pub time: Time
}

#[derive(Copy, Drop, Serde)]
pub struct PitchWheel {
    pub channel: u8,
    pub value: u16,
    pub time: Time
}

#[derive(Copy, Drop, Serde)]
pub struct AfterTouch {
    pub channel: u8,
    pub value: u8,
    pub time: Time
}

#[derive(Copy, Drop, Serde)]
pub struct PolyTouch {
    pub channel: u8,
    pub note: u8,
    pub value: u8,
    pub time: Time
}

#[derive(Copy, Drop, Serde)]
pub struct ProgramChange {
    pub channel: u8,
    pub program: u8,
    pub time: Time
}

#[derive(Copy, Drop, Serde)]
pub struct SystemExclusive {
    pub data: Span<u8>,
    pub time: Time
}

/// =========================================
/// ================ PATTERNS ===============
/// =========================================

#[derive(Copy, Drop, Serde)]
pub enum Modes {
    Major: (),
    Minor: (),
    Lydian: (),
    Mixolydian: (),
    Dorian: (),
    Phrygian: (),
    Locrian: (),
    Aeolian: (),
    HarmonicMinor: (),
    NaturalMinor: (),
    Chromatic: (),
    Pentatonic: (),
}

#[derive(Copy, Drop, Serde)]
pub enum ArpPattern {
    Up: (),
    Down: (),
    UpDown: (),
    DownUp: (),
    Converge: (),
    Diverge: (),
    ConDiverge: (),
    Pinky: (),
    Thumb: (),
    Random: (),
}

// VelocityCurve represents time & level "breakpoint" pairs indexed:
#[derive(Copy, Drop, Serde)]
pub struct VelocityCurve {
    pub times: Span<Time>,
    pub levels: Span<u8>
}

/// =========================================
/// ============== PitchClass ===============
/// =========================================

// Define a 12 note octave base
// For Microtonal mode definition, change the OCTAVEBASE and represent scales as intervallic ratios summing to OCTAVEBASE

pub const OCTAVEBASE: u8 = 12;

//*************************************************************************
// Pitch and Interval Structs 
//
// PitchClass: Used to Calculate Keynums. Pitch Class Keynums can be 0-127
// Example: MIDI Keynum 69 == A440 
//
// Notes are values from 0 <= note < OCTAVEBASE and increment
// Example: If OCTAVEBASE = 12, [C -> 0, C# -> 1, D -> 2...B-> 11]
// Example 2: MIDI Keynum 69: Note = 9, Octave = 5
//*************************************************************************

#[derive(Copy, Drop, Serde)]
pub struct PitchClass {
    pub note: u8,
    pub octave: u8,
}

#[derive(Copy, Drop, Serde)]
pub enum Direction {
    Up: (),
    Down: (),
    Oblique: ()
}

#[derive(Copy, Drop, Serde)]
pub struct PitchInterval {
    pub size: u8,
    pub direction: Direction,
    pub quality: Option<Quality>,
}

#[derive(Copy, Drop, Serde)]
pub enum Quality {
    Major: (),
    Minor: (),
    Perfect: (),
    Diminshed: (),
    Augmented: (),
    Undefined: ()
}

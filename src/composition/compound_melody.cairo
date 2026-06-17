//! Compound melody — a single voice that implies two independent voices through register.
//!
//! Bach's solo violin and cello works alternate rapidly between a high implied melody and
//! a low bass line; the listener completes the illusion of two independent voices.
//!
//! This module provides:
//!   - `CompoundMelodyConfig` — parameters for the alternation
//!   - `generate_compound_melody` — interleaves two-register events from a degree sequence
//!   - `split_compound_voices` — analysis: separate a compound-melody NoteEvent stream
//!     back into its two implied voices by register split
//!   - Validators

use core::array::ArrayTrait;
use koji::composition::melodic_canon::{NoteEvent, realize_degree};

// ─────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────

/// Controls how the two implied voices are generated.
#[derive(Copy, Drop)]
pub struct CompoundMelodyConfig {
    /// Octave transposition applied to the "high" register notes (in semitones).
    /// Typically 12 (one octave above) to place the soprano line above the bass.
    pub high_octave_shift: u8,
    /// Semitone register split point used by `split_compound_voices`:
    /// pitches at or above this keynum go to the "high" voice; below → "low" voice.
    pub split_keynum: u8,
    /// True = interleave high/low within each structural beat (creates the illusion of
    /// two simultaneous voices); false = emit only the high notes for simple ornamentation.
    pub interleave: bool,
    /// Velocity of the high (melody) implied voice.
    pub high_velocity: u8,
    /// Velocity of the low (bass) implied voice.
    pub low_velocity: u8,
}

/// Default: one octave separation, alternating within each beat.
pub fn default_compound_config() -> CompoundMelodyConfig {
    CompoundMelodyConfig {
        high_octave_shift: 12,
        split_keynum: 60,
        interleave: true,
        high_velocity: 95,
        low_velocity: 75,
    }
}

/// Wide-range compound melody (two octaves separation, prominent bass).
pub fn wide_compound_config() -> CompoundMelodyConfig {
    CompoundMelodyConfig {
        high_octave_shift: 24,
        split_keynum: 66,
        interleave: true,
        high_velocity: 90,
        low_velocity: 80,
    }
}

// ─────────────────────────────────────────────────────────────
// Generator
// ─────────────────────────────────────────────────────────────

/// Generate compound-melody NoteEvents from a sequence of diatonic degrees.
///
/// Each degree produces TWO notes per structural beat when `interleave` is true:
///   - sub-beat 0 (first half): the "low" pitch at the given degree
///   - sub-beat 1 (second half): the "high" pitch at the same degree raised by `high_octave_shift`
///
/// When `interleave` is false only the high-register note is emitted (melody-only mode).
pub fn generate_compound_melody(
    degrees: Span<i32>,
    config: @CompoundMelodyConfig,
    octave: u32,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
    voice_id: u32,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let len = degrees.len();
    if len == 0 {
        return out;
    }
    let sub = if *config.interleave {
        2_u32
    } else {
        1_u32
    };
    let sub_dur = if sub == 0 || time_unit < sub {
        time_unit
    } else {
        time_unit / sub
    };

    let mut p: u32 = 0;
    loop {
        if p >= len {
            break;
        }
        let deg = *degrees.at(p);
        let low_pitch = realize_degree(octave, deg, tonic_keynum, mode_id);
        // Apply the high register shift to MIDI pitch (chromatic).
        // Clamp to 127 to avoid MIDI overflow.
        let high_total: u16 = low_pitch.into() + (*config.high_octave_shift).into();
        let high_pitch: u8 = if high_total > 127 {
            127
        } else {
            high_total.try_into().unwrap()
        };
        let beat_start = p * time_unit;

        if *config.interleave {
            // Sub-beat 0: low voice
            out.append(
                NoteEvent {
                    time: beat_start,
                    duration: sub_dur,
                    pitch: low_pitch,
                    velocity: *config.low_velocity,
                    voice_id,
                },
            );
            // Sub-beat 1: high voice
            out.append(
                NoteEvent {
                    time: beat_start + sub_dur,
                    duration: sub_dur,
                    pitch: high_pitch,
                    velocity: *config.high_velocity,
                    voice_id,
                },
            );
        } else {
            // Melody-only: emit only the high note for the full beat duration
            out.append(
                NoteEvent {
                    time: beat_start,
                    duration: time_unit,
                    pitch: high_pitch,
                    velocity: *config.high_velocity,
                    voice_id,
                },
            );
        }
        p += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Analysis: split into implied voices
// ─────────────────────────────────────────────────────────────

/// Separate a compound-melody NoteEvent stream into two implied voices by register.
/// Notes with pitch ≥ `split_keynum` → high voice; below → low voice.
/// Both output arrays preserve original time ordering.
pub fn split_compound_voices(
    events: Span<NoteEvent>, split_keynum: u8,
) -> (Array<NoteEvent>, Array<NoteEvent>) {
    let mut high: Array<NoteEvent> = ArrayTrait::new();
    let mut low: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        if e.pitch >= split_keynum {
            high.append(e);
        } else {
            low.append(e);
        }
        i += 1;
    };
    (high, low)
}

// ─────────────────────────────────────────────────────────────
// Melodic curve helpers
// ─────────────────────────────────────────────────────────────

/// Extract only the high-register events from a compound melody stream.
pub fn compound_high_voice(events: Span<NoteEvent>, split_keynum: u8) -> Array<NoteEvent> {
    let (high, _low) = split_compound_voices(events, split_keynum);
    high
}

/// Extract only the low-register events from a compound melody stream.
pub fn compound_low_voice(events: Span<NoteEvent>, split_keynum: u8) -> Array<NoteEvent> {
    let (_high, low) = split_compound_voices(events, split_keynum);
    low
}

/// Merge two NoteEvent arrays into one, preserving order within each source.
/// (Caller is responsible for re-sorting by time if required.)
pub fn merge_voices(a: Span<NoteEvent>, b: Span<NoteEvent>) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    let mut j: u32 = 0;
    loop {
        if j >= b.len() {
            break;
        }
        out.append(*b.at(j));
        j += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Validators
// ─────────────────────────────────────────────────────────────

/// True iff a compound melody stream contains events in both registers (both implied voices
/// are present), given a register split keynum.
pub fn compound_has_both_registers(events: Span<NoteEvent>, split_keynum: u8) -> bool {
    let mut has_high = false;
    let mut has_low = false;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let p = (*events.at(i)).pitch;
        if p >= split_keynum {
            has_high = true;
        } else {
            has_low = true;
        }
        i += 1;
    };
    has_high && has_low
}

/// True iff a compound melody has exactly two events per structural beat (interleaved mode).
pub fn compound_is_interleaved(events: Span<NoteEvent>, time_unit: u32, beat_count: u32) -> bool {
    if time_unit == 0 {
        return false;
    }
    events.len() == beat_count * 2
}

/// True iff all pitches are within the MIDI range [1, 127].
pub fn compound_pitches_valid(events: Span<NoteEvent>) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= events.len() || !ok {
            break;
        }
        let p = (*events.at(i)).pitch;
        if p == 0 || p > 127 {
            ok = false;
        }
        i += 1;
    };
    ok
}

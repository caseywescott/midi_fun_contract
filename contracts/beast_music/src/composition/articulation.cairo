//! Articulation layer — bakes articulation marks into NoteEvent duration and velocity.
//!
//! Articulation is stored as `u8` codes in the `MusicalObject.articulations` plane
//! (`transform.cairo`). This module provides the policy tables that convert those codes
//! into concrete duration fractions and velocity deltas, plus helpers to:
//!
//!  - apply an articulation plan to any `Array<NoteEvent>` from any existing generator,
//!  - extend `transform::assemble` to honour the articulation plane (`assemble_articulated`),
//!  - generate cyclic patterns from a profile id or a seed.
//!
//! No existing files are modified.

use core::array::ArrayTrait;
use crate::composition::melodic_canon::NoteEvent;

// ─────────────────────────────────────────────────────────────
// Articulation codes  (u8 constants)
// ─────────────────────────────────────────────────────────────

/// No modification to duration or velocity.
pub const ART_NORMAL: u8 = 0;
/// Half duration (staccato dot).
pub const ART_STACCATO: u8 = 1;
/// Full written duration held; makes the intent explicit.
pub const ART_TENUTO: u8 = 2;
/// +20 velocity, duration unchanged.
pub const ART_ACCENT: u8 = 3;
/// +40 velocity, duration unchanged.
pub const ART_SFORZANDO: u8 = 4;
/// 3/4 duration (portato — carried but shortened).
pub const ART_PORTATO: u8 = 5;

/// Highest valid articulation code. Values above this are treated as ART_NORMAL.
pub const ART_MAX: u8 = 5;

// ─────────────────────────────────────────────────────────────
// Core plan
// ─────────────────────────────────────────────────────────────

/// Controls how a cyclic articulation pattern is applied to a NoteEvent stream.
#[derive(Drop)]
pub struct ArticulationPlan {
    /// Cyclic articulation pattern.  Codes cycle over the event stream.
    /// Empty ⇒ ART_NORMAL for every event.
    pub pattern: Array<u8>,
    /// Velocity after boost is clamped to this value (prevents MIDI clipping).
    pub velocity_ceiling: u8,
    /// Duration after staccato / portato shortening is clamped to at least this value
    /// (prevents zero-length or sub-tick notes).
    pub min_duration: u32,
}

// ─────────────────────────────────────────────────────────────
// Duration and velocity policies
// ─────────────────────────────────────────────────────────────

/// Return the sounding duration for a note given its written duration and articulation code.
/// `min_duration` prevents the result from reaching zero.
pub fn articulation_duration(written: u32, art: u8, min_duration: u32) -> u32 {
    let shortened = if art == ART_STACCATO {
        // × 1/2
        if written < 2 {
            written
        } else {
            written / 2
        }
    } else if art == ART_PORTATO {
        // × 3/4
        let three_quarters = written * 3 / 4;
        if three_quarters == 0 {
            written
        } else {
            three_quarters
        }
    } else {
        written
    };
    if shortened < min_duration {
        min_duration
    } else {
        shortened
    }
}

/// Return the sounding velocity for a note given its written velocity and articulation code.
/// Result is clamped to `[1, velocity_ceiling]`.
pub fn articulation_velocity(written: u8, art: u8, velocity_ceiling: u8) -> u8 {
    let ceiling = if velocity_ceiling == 0 {
        127_u8
    } else {
        velocity_ceiling
    };
    let boosted: u8 = if art == ART_ACCENT {
        let sum: u16 = written.into() + 20_u16;
        if sum > ceiling.into() {
            ceiling
        } else {
            sum.try_into().unwrap()
        }
    } else if art == ART_SFORZANDO {
        let sum: u16 = written.into() + 40_u16;
        if sum > ceiling.into() {
            ceiling
        } else {
            sum.try_into().unwrap()
        }
    } else {
        written
    };
    if boosted == 0 {
        1_u8
    } else if boosted > ceiling {
        ceiling
    } else {
        boosted
    }
}

// ─────────────────────────────────────────────────────────────
// Core application
// ─────────────────────────────────────────────────────────────

/// Apply an articulation plan to an existing NoteEvent stream.
/// The pattern cycles over events regardless of voice — use `filter_voice` wrappers
/// when per-voice articulation is needed.
pub fn apply_articulation_plan(
    events: Span<NoteEvent>, plan: @ArticulationPlan,
) -> Array<NoteEvent> {
    let plen = plan.pattern.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        let art = if plen == 0 {
            ART_NORMAL
        } else {
            *plan.pattern.at(i % plen)
        };
        let art_safe = if art > ART_MAX {
            ART_NORMAL
        } else {
            art
        };
        out
            .append(
                NoteEvent {
                    time: e.time,
                    duration: articulation_duration(e.duration, art_safe, *plan.min_duration),
                    pitch: e.pitch,
                    velocity: articulation_velocity(e.velocity, art_safe, *plan.velocity_ceiling),
                    voice_id: e.voice_id,
                },
            );
        i += 1;
    }
    out
}

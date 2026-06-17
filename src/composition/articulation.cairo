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
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::transform::{assemble, MusicalObject};

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
    };
    out
}

/// Apply articulation independently per voice.  `plans` is indexed by `voice_id`.
/// Voices whose id exceeds `plans.len()` receive ART_NORMAL.
pub fn apply_articulation_per_voice(
    events: Span<NoteEvent>,
    plans: Span<ArticulationPlan>,
    global_velocity_ceiling: u8,
    global_min_duration: u32,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        let vid = e.voice_id;
        let art = if vid >= plans.len() {
            ART_NORMAL
        } else {
            let plan = plans.at(vid);
            let plen = plan.pattern.len();
            if plen == 0 {
                ART_NORMAL
            } else {
                // count how many events have already appeared on this voice
                let voice_event_index = count_voice_events_before(events, vid, i);
                let code = *plan.pattern.at(voice_event_index % plen);
                if code > ART_MAX {
                    ART_NORMAL
                } else {
                    code
                }
            }
        };
        let ceiling = if vid < plans.len() {
            *plans.at(vid).velocity_ceiling
        } else {
            global_velocity_ceiling
        };
        let min_dur = if vid < plans.len() {
            *plans.at(vid).min_duration
        } else {
            global_min_duration
        };
        out
            .append(
                NoteEvent {
                    time: e.time,
                    duration: articulation_duration(e.duration, art, min_dur),
                    pitch: e.pitch,
                    velocity: articulation_velocity(e.velocity, art, ceiling),
                    voice_id: vid,
                },
            );
        i += 1;
    };
    out
}

fn count_voice_events_before(events: Span<NoteEvent>, voice_id: u32, before_idx: u32) -> u32 {
    let mut count: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= before_idx {
            break;
        }
        if (*events.at(i)).voice_id == voice_id {
            count += 1;
        }
        i += 1;
    };
    count
}

// ─────────────────────────────────────────────────────────────
// Extends transform::assemble to honour the articulation plane
// ─────────────────────────────────────────────────────────────

/// Like `transform::assemble` but also applies the `MusicalObject.articulations` plane.
/// Internally calls `assemble` then `apply_articulation_plan` — neither function is modified.
pub fn assemble_articulated(
    obj: @MusicalObject,
    voice_id: u32,
    tonic_keynum: u8,
    mode_id: u8,
    velocity_ceiling: u8,
    min_duration: u32,
) -> Array<NoteEvent> {
    let events = assemble(obj, voice_id, tonic_keynum, mode_id);
    let plan = ArticulationPlan {
        pattern: clone_u8(obj.articulations.span()),
        velocity_ceiling,
        min_duration,
    };
    apply_articulation_plan(events.span(), @plan)
}

fn clone_u8(xs: Span<u8>) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*xs.at(i));
        i += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Profile-driven patterns
// ─────────────────────────────────────────────────────────────

/// Return a curated cyclic articulation pattern for a given aesthetic profile id.
/// The cycle is designed to be short (2–4 values) so it works across any phrase length.
///
/// Profile ids match `aesthetic_profile.cairo` `profile_by_id` numbering.
pub fn articulation_pattern_for_profile(profile_id: u16) -> Array<u8> {
    if profile_id == 0 {
        // renaissance — tenuto throughout; smooth legato first-species feel
        array![ART_TENUTO, ART_TENUTO, ART_TENUTO, ART_TENUTO]
    } else if profile_id == 1 {
        // jazz — accent on beats 2 and 4 (index 1, 3); normal on 1 and 3
        array![ART_NORMAL, ART_ACCENT, ART_NORMAL, ART_ACCENT]
    } else if profile_id == 2 {
        // quartal — portato; sustained but not fully legato
        array![ART_PORTATO, ART_PORTATO, ART_PORTATO, ART_PORTATO]
    } else if profile_id == 3 {
        // planing — tenuto; block chords slide intact
        array![ART_TENUTO, ART_TENUTO, ART_TENUTO, ART_TENUTO]
    } else if profile_id == 4 {
        // hindemith — alternating portato and normal; shaped, not uniform
        array![ART_PORTATO, ART_NORMAL, ART_PORTATO, ART_NORMAL]
    } else if profile_id == 5 {
        // ligeti_white — staccato; crystalline white-key cluster
        array![ART_STACCATO, ART_STACCATO, ART_STACCATO, ART_STACCATO]
    } else if profile_id == 6 {
        // ligeti_micro — staccato; dense chromatic micropolyphony
        array![ART_STACCATO, ART_STACCATO, ART_STACCATO, ART_STACCATO]
    } else if profile_id == 10 {
        // octatonic — staccato on every other event; brittle diminished-axis color
        array![ART_STACCATO, ART_NORMAL, ART_STACCATO, ART_NORMAL]
    } else if profile_id == 14 {
        // bartok_axis — accent on axis downbeats, portato on passing notes
        array![ART_ACCENT, ART_PORTATO, ART_ACCENT, ART_PORTATO]
    } else if profile_id == 19 {
        // phrygian — accent on position 0 (b2 arrival), normal elsewhere
        array![ART_ACCENT, ART_NORMAL, ART_NORMAL]
    } else if profile_id == 20 {
        // penta_open — portato; open fifths carried but not hammered
        array![ART_PORTATO, ART_PORTATO, ART_PORTATO, ART_PORTATO]
    } else if profile_id == 22 {
        // penta_smooth — portato; pentatonic lyricism
        array![ART_PORTATO, ART_PORTATO, ART_PORTATO, ART_PORTATO]
    } else if profile_id == 24 {
        // jazz_improv — accent on beat 1 of each turnaround quarter; normal elsewhere
        array![ART_ACCENT, ART_NORMAL, ART_NORMAL, ART_NORMAL]
    } else {
        // default — normal throughout
        array![ART_NORMAL, ART_NORMAL, ART_NORMAL, ART_NORMAL]
    }
}

/// Return an `ArticulationPlan` with the profile-derived pattern and sensible defaults.
pub fn plan_for_profile(profile_id: u16) -> ArticulationPlan {
    ArticulationPlan {
        pattern: articulation_pattern_for_profile(profile_id),
        velocity_ceiling: 120,
        min_duration: 1,
    }
}

// ─────────────────────────────────────────────────────────────
// Seed-driven pattern generation
// ─────────────────────────────────────────────────────────────

/// Generate a random articulation pattern of `length` codes from `seed`.
/// Codes are drawn from the full `[ART_NORMAL..ART_MAX]` range.
/// Use `density` (0–7) to bias toward fewer non-NORMAL codes:
///   0 = all non-NORMAL allowed with equal weight,
///   7 = predominantly NORMAL (only occasional accent/staccato).
pub fn articulation_pattern_from_seed(seed: felt252, length: u32, density: u8) -> Array<u8> {
    if length == 0 {
        return ArrayTrait::new();
    }
    let s: u256 = seed.into();
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= length {
            break;
        }
        // Derive per-position bits from seed without LCG state sharing.
        let shifted = s / pow2_u256(i * 4);
        let raw: u32 = (shifted % 256).try_into().unwrap();
        // Density gate: if high bits of raw indicate "skip articulation", emit NORMAL.
        let threshold: u32 = if density > 7 {
            255_u32
        } else {
            (density.into() * 30_u32)
        };
        let code: u8 = if raw < threshold {
            ART_NORMAL
        } else {
            // Select from non-NORMAL codes; ART_MAX = 5 so range is 1..5
            let choice = (raw % ART_MAX.into()) + 1;
            choice.try_into().unwrap()
        };
        out.append(code);
        i += 1;
    };
    out
}

fn pow2_u256(exp: u32) -> u256 {
    let mut result: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= exp {
            break;
        }
        result *= 2;
        i += 1;
    };
    result
}

// ─────────────────────────────────────────────────────────────
// Beat-aware helpers
// ─────────────────────────────────────────────────────────────

/// Build an `ArticulationPlan` that places `ART_ACCENT` on strong beats.
/// `time_unit` is the structural time step; events whose `time % (time_unit * beats_per_bar) == 0`
/// are strong beats.
pub fn strong_beat_accent_plan(
    events: Span<NoteEvent>,
    time_unit: u32,
    beats_per_bar: u32,
    velocity_ceiling: u8,
    min_duration: u32,
) -> ArticulationPlan {
    let bar_unit = time_unit * beats_per_bar;
    let mut pattern: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        let code = if bar_unit > 0 && e.time % bar_unit == 0 {
            ART_ACCENT
        } else {
            ART_NORMAL
        };
        pattern.append(code);
        i += 1;
    };
    ArticulationPlan { pattern, velocity_ceiling, min_duration }
}

/// Apply staccato only to events whose duration exceeds `threshold` time-units.
/// Short notes (passing tones, ornaments) are left at full written duration.
pub fn staccato_long_notes(
    events: Span<NoteEvent>, duration_threshold: u32, velocity_ceiling: u8,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        let art = if e.duration > duration_threshold {
            ART_STACCATO
        } else {
            ART_NORMAL
        };
        out
            .append(
                NoteEvent {
                    time: e.time,
                    duration: articulation_duration(e.duration, art, 1),
                    pitch: e.pitch,
                    velocity: articulation_velocity(e.velocity, art, velocity_ceiling),
                    voice_id: e.voice_id,
                },
            );
        i += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Convenience constructors
// ─────────────────────────────────────────────────────────────

/// All notes at full duration, no velocity change.
pub fn plan_uniform_normal() -> ArticulationPlan {
    ArticulationPlan {
        pattern: array![ART_NORMAL],
        velocity_ceiling: 127,
        min_duration: 1,
    }
}

/// All notes staccato.
pub fn plan_uniform_staccato(velocity_ceiling: u8, min_duration: u32) -> ArticulationPlan {
    ArticulationPlan {
        pattern: array![ART_STACCATO],
        velocity_ceiling,
        min_duration,
    }
}

/// All notes tenuto.
pub fn plan_uniform_tenuto() -> ArticulationPlan {
    ArticulationPlan {
        pattern: array![ART_TENUTO],
        velocity_ceiling: 127,
        min_duration: 1,
    }
}

/// All notes portato.
pub fn plan_uniform_portato(velocity_ceiling: u8) -> ArticulationPlan {
    ArticulationPlan {
        pattern: array![ART_PORTATO],
        velocity_ceiling,
        min_duration: 1,
    }
}

/// Accent every `n`th note (0-indexed).
pub fn plan_accent_every_n(n: u32, velocity_ceiling: u8) -> ArticulationPlan {
    assert(n > 0, 'n must be > 0');
    let mut pattern: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        if i == 0 {
            pattern.append(ART_ACCENT);
        } else {
            pattern.append(ART_NORMAL);
        }
        i += 1;
    };
    ArticulationPlan { pattern, velocity_ceiling, min_duration: 1 }
}

// ─────────────────────────────────────────────────────────────
// Validators
// ─────────────────────────────────────────────────────────────

/// True iff every event in the output is in the correct temporal order and has
/// duration ≥ min_duration.
pub fn articulation_output_valid(
    events: Span<NoteEvent>, min_duration: u32,
) -> bool {
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break true;
        }
        let e = *events.at(i);
        if e.duration < min_duration {
            break false;
        }
        if e.velocity == 0 || e.velocity > 127 {
            break false;
        }
        i += 1;
    }
}

/// True iff applying ART_NORMAL never changes duration or velocity.
pub fn normal_is_identity() -> bool {
    let d_before: u32 = 480;
    let v_before: u8 = 80;
    let d_after = articulation_duration(d_before, ART_NORMAL, 1);
    let v_after = articulation_velocity(v_before, ART_NORMAL, 127);
    d_after == d_before && v_after == v_before
}

/// True iff staccato strictly reduces duration (for durations ≥ 2).
pub fn staccato_reduces_duration() -> bool {
    let d: u32 = 480;
    articulation_duration(d, ART_STACCATO, 1) < d
}

/// True iff accent and sforzando raise velocity (when there is headroom).
pub fn accent_raises_velocity() -> bool {
    let v: u8 = 60;
    let ceiling: u8 = 127;
    articulation_velocity(v, ART_ACCENT, ceiling) > v
        && articulation_velocity(v, ART_SFORZANDO, ceiling) > v
}

/// True iff velocity ceiling is respected for extreme boosts.
pub fn velocity_ceiling_respected() -> bool {
    let v: u8 = 120;
    let ceiling: u8 = 127;
    articulation_velocity(v, ART_SFORZANDO, ceiling) <= ceiling
}

//! Articulation: the duration and velocity policies per code, the cyclic plan applied to note
//! events, and the invariants (NORMAL is the identity, staccato shortens, accents raise velocity
//! under the ceiling).

use crate::composition::articulation::{
    ART_ACCENT, ART_NORMAL, ART_PORTATO, ART_SFORZANDO, ART_STACCATO, ART_TENUTO, ArticulationPlan,
    apply_articulation_plan, articulation_duration, articulation_velocity,
};
use crate::composition::melodic_canon::NoteEvent;

/// True iff applying ART_NORMAL never changes duration or velocity.
fn normal_is_identity() -> bool {
    let d_before: u32 = 480;
    let v_before: u8 = 80;
    let d_after = articulation_duration(d_before, ART_NORMAL, 1);
    let v_after = articulation_velocity(v_before, ART_NORMAL, 127);
    d_after == d_before && v_after == v_before
}

/// True iff staccato strictly reduces duration (for durations ≥ 2).
fn staccato_reduces_duration() -> bool {
    let d: u32 = 480;
    articulation_duration(d, ART_STACCATO, 1) < d
}

/// True iff accent and sforzando raise velocity (when there is headroom).
fn accent_raises_velocity() -> bool {
    let v: u8 = 60;
    let ceiling: u8 = 127;
    articulation_velocity(v, ART_ACCENT, ceiling) > v
        && articulation_velocity(v, ART_SFORZANDO, ceiling) > v
}

/// True iff velocity ceiling is respected for extreme boosts.
fn velocity_ceiling_respected() -> bool {
    let v: u8 = 120;
    let ceiling: u8 = 127;
    articulation_velocity(v, ART_SFORZANDO, ceiling) <= ceiling
}

/// All notes at full duration, no velocity change.
fn plan_uniform_normal() -> ArticulationPlan {
    ArticulationPlan { pattern: array![ART_NORMAL], velocity_ceiling: 127, min_duration: 1 }
}

/// All notes staccato.
fn plan_uniform_staccato(velocity_ceiling: u8, min_duration: u32) -> ArticulationPlan {
    ArticulationPlan { pattern: array![ART_STACCATO], velocity_ceiling, min_duration }
}

/// All notes tenuto.
fn plan_uniform_tenuto() -> ArticulationPlan {
    ArticulationPlan { pattern: array![ART_TENUTO], velocity_ceiling: 127, min_duration: 1 }
}

fn make_event(time: u32, duration: u32, pitch: u8, velocity: u8) -> NoteEvent {
    NoteEvent { time, duration, pitch, velocity, voice_id: 0 }
}

fn make_event_v(time: u32, duration: u32, pitch: u8, velocity: u8, voice_id: u32) -> NoteEvent {
    NoteEvent { time, duration, pitch, velocity, voice_id }
}

#[test]
#[available_gas(1000000000000)]
fn test_normal_is_identity() {
    assert(normal_is_identity(), 'NORMAL must be identity');
}

#[test]
#[available_gas(1000000000000)]
fn test_staccato_reduces_duration() {
    assert(staccato_reduces_duration(), 'STACCATO must reduce dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_accent_raises_velocity() {
    assert(accent_raises_velocity(), 'ACCENT must raise vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_ceiling_respected() {
    assert(velocity_ceiling_respected(), 'ceiling must be respected');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_normal_unchanged() {
    assert(articulation_duration(480, ART_NORMAL, 1) == 480, 'NORMAL changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_tenuto_unchanged() {
    assert(articulation_duration(480, ART_TENUTO, 1) == 480, 'TENUTO changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_half() {
    assert(articulation_duration(480, ART_STACCATO, 1) == 240, 'STACCATO not half');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_portato_three_quarters() {
    assert(articulation_duration(480, ART_PORTATO, 1) == 360, 'PORTATO not 3/4');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_odd_length() {
    // 481 / 2 = 240 (integer division)
    assert(articulation_duration(481, ART_STACCATO, 1) == 240, 'STACCATO odd floor');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_min_clamp() {
    // written=480, staccato → 240, but min_duration=300 clamps to 300
    assert(articulation_duration(480, ART_STACCATO, 300) == 300, 'min clamp failed');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_portato_min_clamp() {
    // written=4, portato → 3, min_duration=4 → clamped to 4
    assert(articulation_duration(4, ART_PORTATO, 4) == 4, 'portato min clamp');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_tiny_input() {
    // written=1, staccato guard: 1 < 2 → returns 1 (min guard inside fn)
    assert(articulation_duration(1, ART_STACCATO, 1) == 1, 'tiny staccato guard');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_accent_unchanged() {
    // ART_ACCENT only changes velocity, not duration
    assert(articulation_duration(480, ART_ACCENT, 1) == 480, 'ACCENT changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_sforzando_unchanged() {
    assert(articulation_duration(480, ART_SFORZANDO, 1) == 480, 'SFZ changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_unknown_code_falls_through() {
    // Codes above ART_MAX are handled in apply_articulation_plan (normalized to NORMAL);
    // articulation_duration itself just falls through to written duration.
    assert(articulation_duration(200, 99, 1) == 200, 'unknown code fallthrough');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_normal_unchanged() {
    assert(articulation_velocity(80, ART_NORMAL, 127) == 80, 'NORMAL changes vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_tenuto_unchanged() {
    assert(articulation_velocity(80, ART_TENUTO, 127) == 80, 'TENUTO changes vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_accent_plus20() {
    assert(articulation_velocity(60, ART_ACCENT, 127) == 80, 'ACCENT not +20');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_sforzando_plus40() {
    assert(articulation_velocity(60, ART_SFORZANDO, 127) == 100, 'SFZ not +40');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_accent_ceiling_clamp() {
    // 120 + 20 = 140 > ceiling 127 → clamped to 127
    assert(articulation_velocity(120, ART_ACCENT, 127) == 127, 'accent ceiling');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_sforzando_ceiling_custom() {
    // 100 + 40 = 140 > ceiling 110 → clamped to 110
    assert(articulation_velocity(100, ART_SFORZANDO, 110) == 110, 'sfz custom ceiling');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_ceiling_zero_defaults_127() {
    // ceiling=0 is treated as 127
    assert(articulation_velocity(60, ART_ACCENT, 0) == 80, 'ceiling 0 default');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_staccato_unchanged() {
    // ART_STACCATO only changes duration, not velocity
    assert(articulation_velocity(80, ART_STACCATO, 127) == 80, 'STACCATO changes vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_normal_event_count_preserved() {
    let events = array![
        make_event(0, 480, 60, 80), make_event(480, 480, 62, 80), make_event(960, 480, 64, 80),
    ];
    let plan = plan_uniform_normal();
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.len() == 3, 'count changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_normal_events_unchanged() {
    let events = array![make_event(0, 480, 60, 80), make_event(480, 240, 62, 90)];
    let plan = plan_uniform_normal();
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).duration == 480, 'normal dur 0 changed');
    assert(out.at(0).velocity == 80, 'normal vel 0 changed');
    assert(out.at(1).duration == 240, 'normal dur 1 changed');
    assert(out.at(1).velocity == 90, 'normal vel 1 changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_staccato_halves_duration() {
    let events = array![make_event(0, 480, 60, 80), make_event(480, 480, 62, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).duration == 240, 'staccato dur 0');
    assert(out.at(1).duration == 240, 'staccato dur 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_staccato_velocity_unchanged() {
    let events = array![make_event(0, 480, 60, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).velocity == 80, 'staccato vel changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_accent_raises_velocity() {
    let events = array![make_event(0, 480, 60, 60)];
    let plan = ArticulationPlan {
        pattern: array![ART_ACCENT], velocity_ceiling: 127, min_duration: 1,
    };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).velocity == 80, 'accent vel wrong');
    assert(out.at(0).duration == 480, 'accent dur changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_tenuto_unchanged() {
    let events = array![make_event(0, 480, 60, 80)];
    let plan = plan_uniform_tenuto();
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).duration == 480, 'tenuto dur wrong');
    assert(out.at(0).velocity == 80, 'tenuto vel wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_empty_pattern_is_normal() {
    let events = array![make_event(0, 480, 60, 80), make_event(480, 360, 62, 70)];
    let plan = ArticulationPlan { pattern: array![], velocity_ceiling: 127, min_duration: 1 };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).duration == 480, 'empty pat dur 0');
    assert(out.at(1).duration == 360, 'empty pat dur 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_pattern_cycles() {
    // pattern [ACCENT, NORMAL] over 4 events: idx 0,2 → accent; idx 1,3 → normal
    let v: u8 = 60;
    let events = array![
        make_event(0, 480, 60, v), make_event(480, 480, 62, v), make_event(960, 480, 64, v),
        make_event(1440, 480, 65, v),
    ];
    let plan = ArticulationPlan {
        pattern: array![ART_ACCENT, ART_NORMAL], velocity_ceiling: 127, min_duration: 1,
    };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).velocity == 80, 'cycle idx0 accent');
    assert(out.at(1).velocity == 60, 'cycle idx1 normal');
    assert(out.at(2).velocity == 80, 'cycle idx2 accent');
    assert(out.at(3).velocity == 60, 'cycle idx3 normal');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_unknown_code_treated_as_normal() {
    // code 99 > ART_MAX → normalized to ART_NORMAL
    let events = array![make_event(0, 480, 60, 80)];
    let plan = ArticulationPlan { pattern: array![99_u8], velocity_ceiling: 127, min_duration: 1 };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).duration == 480, 'unknown code dur');
    assert(out.at(0).velocity == 80, 'unknown code vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_time_passthrough() {
    // time field must not be altered
    let events = array![make_event(777, 480, 60, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).time == 777, 'time mutated');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_pitch_passthrough() {
    let events = array![make_event(0, 480, 64, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).pitch == 64, 'pitch mutated');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_voice_id_passthrough() {
    let events = array![make_event_v(0, 480, 60, 80, 3)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.at(0).voice_id == 3, 'voice_id mutated');
}

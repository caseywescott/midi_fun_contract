use core::array::ArrayTrait;
use core::option::OptionTrait;
use koji::composition::phase_rhythm::{phase_orbit_length, render_phase_plan, PhaseRhythmPlan};
use koji::composition::rhythmic_tiling::OnsetEvent;
use koji::composition::timeline_rhythm::{PRESET_SON, known_timeline, rotate_mask};

fn count_events_at_time(events: Span<OnsetEvent>, time: u32) -> u32 {
    let mut count: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        if (*events.at(i)).time == time {
            count += 1;
        }
        i += 1;
    };
    count
}

fn has_collision_events(events: Span<OnsetEvent>) -> bool {
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let t = (*events.at(i)).time;
        if count_events_at_time(events, t) > 1 {
            return true;
        }
        i += 1;
    };
    false
}

#[test]
fn test_phase_orbit_lengths() {
    assert(phase_orbit_length(16, 1).unwrap() == 16, 'orbit16_1');
    assert(phase_orbit_length(16, 2).unwrap() == 8, 'orbit16_2');
    assert(phase_orbit_length(16, 4).unwrap() == 4, 'orbit16_4');
    assert(phase_orbit_length(0, 1).is_none(), 'orbit n0');
    assert(phase_orbit_length(16, 0).is_none(), 'orbit s0');
    assert(phase_orbit_length(16, 16).is_none(), 'orbit s16');
}

#[test]
fn test_full_orbit_realignment() {
    let son = known_timeline(PRESET_SON).unwrap();
    let orbit = phase_orbit_length(16, 1).unwrap();
    let realigned = rotate_mask(16, son.onset_mask, orbit * 1);
    assert(realigned == son.onset_mask, 'orbitrealign');
}

#[test]
fn test_render_phase_plan_event_count() {
    let son = known_timeline(PRESET_SON).unwrap();
    let plan = PhaseRhythmPlan {
        base: son,
        repeats_per_shift: 2,
        shift_step: 1,
        phase_count: 4,
        static_voice_id: 0,
        rotating_voice_id: 1,
        static_velocity: 100,
        rotating_velocity: 80,
    };
    let events = render_phase_plan(@plan);
    assert(events.len() == 4 * 2 * 5 * 2, 'event count');
}

#[test]
fn test_render_phase_plan_full_orbit_default_count() {
    let son = known_timeline(PRESET_SON).unwrap();
    let plan = PhaseRhythmPlan {
        base: son,
        repeats_per_shift: 1,
        shift_step: 1,
        phase_count: 0,
        static_voice_id: 0,
        rotating_voice_id: 1,
        static_velocity: 100,
        rotating_velocity: 80,
    };
    let orbit = phase_orbit_length(16, 1).unwrap();
    let events = render_phase_plan(@plan);
    assert(events.len() == orbit * 1 * 5 * 2, 'full orbit count');
}

#[test]
fn test_phase_collisions_retained() {
    let son = known_timeline(PRESET_SON).unwrap();
    let plan = PhaseRhythmPlan {
        base: son,
        repeats_per_shift: 1,
        shift_step: 1,
        phase_count: 8,
        static_voice_id: 0,
        rotating_voice_id: 1,
        static_velocity: 100,
        rotating_velocity: 80,
    };
    let events = render_phase_plan(@plan);
    assert(has_collision_events(events.span()), 'collisions kept');
}

#[test]
fn test_phase_event_times_monotonic() {
    let son = known_timeline(PRESET_SON).unwrap();
    let plan = PhaseRhythmPlan {
        base: son,
        repeats_per_shift: 1,
        shift_step: 2,
        phase_count: 4,
        static_voice_id: 0,
        rotating_voice_id: 1,
        static_velocity: 90,
        rotating_velocity: 70,
    };
    let events = render_phase_plan(@plan);
    let mut prev: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let t = (*events.at(i)).time;
        assert(t >= prev, 'monotonic times');
        prev = t;
        i += 1;
    };
}

#[test]
fn test_phase_velocities_and_voices() {
    let son = known_timeline(PRESET_SON).unwrap();
    let plan = PhaseRhythmPlan {
        base: son,
        repeats_per_shift: 1,
        shift_step: 1,
        phase_count: 1,
        static_voice_id: 3,
        rotating_voice_id: 7,
        static_velocity: 110,
        rotating_velocity: 55,
    };
    let events = render_phase_plan(@plan);
    let mut static_ok = false;
    let mut rotating_ok = false;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        if e.voice_id == 3 && e.velocity == 110 {
            static_ok = true;
        }
        if e.voice_id == 7 && e.velocity == 55 {
            rotating_ok = true;
        }
        i += 1;
    };
    assert(static_ok, 'static voice');
    assert(rotating_ok, 'rotating voice');
}

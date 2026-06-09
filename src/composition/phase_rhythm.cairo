//! Phase-shift rendering for timeline rhythms.
//!
//! See `docs/clave_african_math_timeline_spec.md`.

use core::array::ArrayTrait;
use koji::composition::rhythmic_tiling::OnsetEvent;
use koji::composition::timeline_rhythm::{is_onset, rotate_mask, TimelineRhythm};

#[derive(Copy, Drop, Serde)]
pub struct PhaseRhythmPlan {
    pub base: TimelineRhythm,
    pub repeats_per_shift: u16,
    pub shift_step: u8,
    pub phase_count: u16,
    pub static_voice_id: u32,
    pub rotating_voice_id: u32,
    pub static_velocity: u8,
    pub rotating_velocity: u8,
}

fn gcd_u32(mut a: u32, mut b: u32) -> u32 {
    loop {
        if b == 0 {
            break;
        }
        let t = a % b;
        a = b;
        b = t;
    };
    a
}

pub fn phase_orbit_length(n: u32, shift_step: u32) -> Option<u32> {
    if n == 0 || shift_step == 0 || shift_step >= n {
        return Option::None;
    }
    let g = gcd_u32(n, shift_step);
    Option::Some(n / g)
}

fn phase_positions(plan: @PhaseRhythmPlan) -> Option<u32> {
    let n = (*plan.base).n;
    let shift = (*plan.shift_step).into();
    match phase_orbit_length(n, shift) {
        Option::Some(orbit) => {
            if *plan.phase_count == 0 {
                Option::Some(orbit)
            } else {
                Option::Some((*plan.phase_count).into())
            }
        },
        Option::None => Option::None,
    }
}

fn append_cycle_events(
    ref events: Array<OnsetEvent>,
    n: u32,
    static_mask: u32,
    rotating_mask: u32,
    cycle_base: u32,
    static_voice_id: u32,
    rotating_voice_id: u32,
    static_velocity: u8,
    rotating_velocity: u8,
) {
    let mut t: u32 = 0;
    loop {
        if t >= n {
            break;
        }
        if is_onset(static_mask, t) {
            events
                .append(
                    OnsetEvent {
                        time: cycle_base + t,
                        duration: 1,
                        voice_id: static_voice_id,
                        velocity: static_velocity,
                    },
                );
        }
        if is_onset(rotating_mask, t) {
            events
                .append(
                    OnsetEvent {
                        time: cycle_base + t,
                        duration: 1,
                        voice_id: rotating_voice_id,
                        velocity: rotating_velocity,
                    },
                );
        }
        t += 1;
    };
}

pub fn render_phase_plan(plan: @PhaseRhythmPlan) -> Array<OnsetEvent> {
    let mut events: Array<OnsetEvent> = ArrayTrait::new();
    let n = (*plan.base).n;
    let shift: u32 = (*plan.shift_step).into();
    let repeats: u32 = (*plan.repeats_per_shift).into();
    let positions = match phase_positions(plan) {
        Option::Some(v) => v,
        Option::None => { return events; },
    };

    let mut phase: u32 = 0;
    loop {
        if phase >= positions {
            break;
        }
        let static_mask = (*plan.base).onset_mask;
        let rotating_mask = rotate_mask(n, static_mask, phase * shift);
        let mut rep: u32 = 0;
        loop {
            if rep >= repeats {
                break;
            }
            let cycle_index = phase * repeats + rep;
            let cycle_base = cycle_index * n;
            append_cycle_events(
                ref events,
                n,
                static_mask,
                rotating_mask,
                cycle_base,
                *plan.static_voice_id,
                *plan.rotating_voice_id,
                *plan.static_velocity,
                *plan.rotating_velocity,
            );
            rep += 1;
        };
        phase += 1;
    };
    events
}

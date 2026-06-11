//! Barry Harris v2 elevator grammar — stable/diminished alternation through 6th-dim field.
//!
//! See `docs/barry_harris_v2.md` §BH12.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    contains_pc, diminished_connector_tones, scale_for_family, stable_chord_tones,
    stable_chord_tones_for, BarryRule, ChordFamily, HarmonicState,
};
use koji::composition::barry_rules::apply_rule;

#[derive(Copy, Drop, PartialEq)]
pub enum ElevatorDirection {
    Up,
    Down,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BarryElevatorKind {
    ElevatorUp,
    ElevatorDown,
    ElevatorBounce,
}

pub fn is_stable_state(state: @HarmonicState) -> bool {
    let stable = stable_chord_tones(state);
    if state.active_pcs.len() != stable.len() {
        return false;
    }
    let mut i: usize = 0;
    loop {
        if i >= stable.len() {
            break;
        }
        if !contains_pc(state.active_pcs.span(), *stable.at(i)) {
            return false;
        }
        i += 1;
    };
    true
}

pub fn apply_elevator_step(state: HarmonicState, direction: ElevatorDirection) -> HarmonicState {
    if is_stable_state(@state) {
        apply_rule(state, BarryRule::DiminishedInterpolation)
    } else {
        let mut next = if direction == ElevatorDirection::Up {
            apply_rule(state, BarryRule::InversionShiftUp)
        } else {
            apply_rule(state, BarryRule::InversionShiftDown)
        };
        next.active_pcs = stable_chord_tones(@next);
        next
    }
}

pub fn apply_elevator_bounce_step(state: HarmonicState) -> HarmonicState {
    let direction = if state.inversion >= 2 {
        ElevatorDirection::Down
    } else {
        ElevatorDirection::Up
    };
    apply_elevator_step(state, direction)
}

pub fn generate_elevator_path(
    start: HarmonicState, direction: ElevatorDirection, length_steps: u8,
) -> Array<HarmonicState> {
    let mut out: Array<HarmonicState> = ArrayTrait::new();
    let mut state = start;
    if !is_stable_state(@state) {
        state.active_pcs = stable_chord_tones(@state);
    }
    out.append(clone_state(@state));
    let mut step: u8 = 1;
    loop {
        if step >= length_steps {
            break;
        }
        state = apply_elevator_step(state, direction);
        out.append(clone_state(@state));
        step += 1;
    };
    out
}

pub fn generate_elevator_bounce_path(
    start: HarmonicState, length_steps: u8,
) -> Array<HarmonicState> {
    let mut out: Array<HarmonicState> = ArrayTrait::new();
    let mut state = start;
    if !is_stable_state(@state) {
        state.active_pcs = stable_chord_tones(@state);
    }
    out.append(clone_state(@state));
    let mut step: u8 = 1;
    loop {
        if step >= length_steps {
            break;
        }
        state = apply_elevator_bounce_step(state);
        out.append(clone_state(@state));
        step += 1;
    };
    out
}

pub fn elevator_path_all_pcs_in_scale(path: Span<HarmonicState>) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= path.len() {
            break;
        }
        let st = path.at(i);
        let scale = scale_for_family(*st.tonic_pc, *st.family);
        let mut j: usize = 0;
        loop {
            if j >= st.active_pcs.len() {
                break;
            }
            if !contains_pc(scale.span(), *st.active_pcs.at(j)) {
                return false;
            }
            j += 1;
        };
        i += 1;
    };
    true
}

pub fn c_major_elevator_up_stable_tonics() -> Array<u8> {
    array![0_u8, 0, 0, 0, 0, 0, 0, 0, 0]
}

pub fn elevator_alternates_stable_dim(path: Span<HarmonicState>) -> bool {
    if path.len() < 2 {
        return true;
    }
    let mut i: usize = 1;
    loop {
        if i >= path.len() {
            break;
        }
        let prev_stable = is_stable_state(path.at(i - 1));
        let cur_stable = is_stable_state(path.at(i));
        if prev_stable == cur_stable {
            return false;
        }
        i += 1;
    };
    true
}

fn clone_state(state: @HarmonicState) -> HarmonicState {
    let mut pcs: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= state.active_pcs.len() {
            break;
        }
        pcs.append(*state.active_pcs.at(i));
        i += 1;
    };
    HarmonicState {
        tonic_pc: *state.tonic_pc,
        family: *state.family,
        inversion: *state.inversion,
        beat_phase: *state.beat_phase,
        tension_level: *state.tension_level,
        active_pcs: pcs,
        register_hint: *state.register_hint,
        previous_state_hash: *state.previous_state_hash,
    }
}

pub fn major_c_elevator_first_dim_pcs() -> Array<u8> {
    diminished_connector_tones(
        @HarmonicState {
            tonic_pc: 0,
            family: ChordFamily::Major6Dim,
            inversion: 0,
            beat_phase: 0,
            tension_level: 0,
            active_pcs: stable_chord_tones_for(0, ChordFamily::Major6Dim),
            register_hint: 60,
            previous_state_hash: 0,
        },
    )
}

//! Barry Harris state transition rules and beat-phase constraints.
//!
//! See `docs/barry_harris_spec.md`.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    diminished_connector_tones, pc_add, pc_sub, scale_for_family, stable_chord_tones,
    stable_chord_tones_for, BarryRule, BeatRole, ChordFamily, HarmonicState,
};

pub fn beat_role(beat_phase: u8) -> BeatRole {
    match beat_phase % 4 {
        0 => BeatRole::Strong,
        1 => BeatRole::Weak,
        2 => BeatRole::Passing,
        _ => BeatRole::Approach,
    }
}

pub fn advance_beat(beat_phase: u8) -> u8 {
    beat_phase + 1
}

pub fn tension_for_rule(rule: BarryRule) -> i8 {
    match rule {
        BarryRule::Stay => -1,
        BarryRule::ScaleStepUp => 0,
        BarryRule::ScaleStepDown => 0,
        BarryRule::DiminishedInterpolation => 2,
        BarryRule::HalfStepApproachUp => 1,
        BarryRule::HalfStepApproachDown => 1,
        BarryRule::FamilyRotation => 1,
        BarryRule::InversionShiftUp => 0,
        BarryRule::InversionShiftDown => 0,
        BarryRule::ResolveToStable => -3,
    }
}

pub fn allowed_rules_for_beat(
    role: BeatRole, tension_level: u8, max_tension: u8,
) -> Span<BarryRule> {
    if tension_level >= max_tension {
        return array![BarryRule::ResolveToStable].span();
    }
    match role {
        BeatRole::Strong => array![
            BarryRule::Stay,
            BarryRule::ScaleStepUp,
            BarryRule::ScaleStepDown,
            BarryRule::ResolveToStable,
            BarryRule::InversionShiftUp,
            BarryRule::InversionShiftDown,
        ]
            .span(),
        BeatRole::Weak => array![
            BarryRule::Stay,
            BarryRule::DiminishedInterpolation,
            BarryRule::ScaleStepUp,
            BarryRule::ScaleStepDown,
            BarryRule::FamilyRotation,
        ]
            .span(),
        BeatRole::Passing => array![
            BarryRule::DiminishedInterpolation,
            BarryRule::HalfStepApproachUp,
            BarryRule::HalfStepApproachDown,
            BarryRule::ScaleStepUp,
            BarryRule::ScaleStepDown,
        ]
            .span(),
        BeatRole::Approach => array![
            BarryRule::HalfStepApproachUp,
            BarryRule::HalfStepApproachDown,
            BarryRule::ResolveToStable,
            BarryRule::Stay,
        ]
            .span(),
    }
}

pub fn melody_constraints_for_state(state: @HarmonicState) -> Array<u8> {
    let role = beat_role(*state.beat_phase);
    match role {
        BeatRole::Strong => stable_chord_tones(state),
        BeatRole::Weak => {
            let mut out = stable_chord_tones(state);
            let dim = diminished_connector_tones(state);
            let mut i: usize = 0;
            loop {
                if i >= dim.len() {
                    break;
                }
                out.append(*dim.at(i));
                i += 1;
            };
            out
        },
        BeatRole::Passing => scale_for_family(*state.tonic_pc, *state.family),
        BeatRole::Approach => approach_tones(state),
    }
}

fn approach_tones(state: @HarmonicState) -> Array<u8> {
    let stable = stable_chord_tones(state);
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= stable.len() {
            break;
        }
        let t = *stable.at(i);
        out.append(pc_sub(t, 1));
        out.append(t);
        out.append(pc_add(t, 1));
        i += 1;
    };
    out
}

pub fn apply_rule(state: HarmonicState, rule: BarryRule) -> HarmonicState {
    match rule {
        BarryRule::Stay => rule_stay(state),
        BarryRule::ScaleStepUp => scale_step_up(state),
        BarryRule::ScaleStepDown => scale_step_down(state),
        BarryRule::DiminishedInterpolation => diminished_interpolation(state),
        BarryRule::HalfStepApproachUp => halfstep_approach_up(state),
        BarryRule::HalfStepApproachDown => halfstep_approach_down(state),
        BarryRule::FamilyRotation => family_rotation(state),
        BarryRule::InversionShiftUp => inversion_shift_up(state),
        BarryRule::InversionShiftDown => inversion_shift_down(state),
        BarryRule::ResolveToStable => resolve_to_stable(state),
    }
}

fn rule_stay(state: HarmonicState) -> HarmonicState {
    let mut next = state;
    next.active_pcs = stable_chord_tones(@next);
    next
}

fn scale_index_of(scale: Span<u8>, pc: u8) -> u8 {
    let mut i: usize = 0;
    loop {
        if i >= scale.len() {
            break;
        }
        if *scale.at(i) == pc {
            return i.try_into().unwrap();
        }
        i += 1;
    };
    0
}

fn scale_step_up(state: HarmonicState) -> HarmonicState {
    let scale = scale_for_family(state.tonic_pc, state.family);
    let idx = scale_index_of(scale.span(), state.tonic_pc);
    let next_idx: u32 = (idx.into() + 1) % 8;
    let new_tonic = *scale.at(next_idx.try_into().unwrap());
    let mut next = state;
    next.tonic_pc = new_tonic;
    next.active_pcs = stable_chord_tones(@next);
    next
}

fn scale_step_down(state: HarmonicState) -> HarmonicState {
    let scale = scale_for_family(state.tonic_pc, state.family);
    let idx = scale_index_of(scale.span(), state.tonic_pc);
    let next_idx: i32 = if idx == 0 {
        7
    } else {
        idx.into() - 1
    };
    let new_tonic = *scale.at(next_idx.try_into().unwrap());
    let mut next = state;
    next.tonic_pc = new_tonic;
    next.active_pcs = stable_chord_tones(@next);
    next
}

fn diminished_interpolation(state: HarmonicState) -> HarmonicState {
    let mut next = state;
    next.active_pcs = diminished_connector_tones(@next);
    next
}

fn halfstep_approach_up(state: HarmonicState) -> HarmonicState {
    let tonic_pc = state.tonic_pc;
    let family = state.family;
    let stable = stable_chord_tones_for(tonic_pc, family);
    let target = if stable.len() > 0 {
        *stable.at(0)
    } else {
        tonic_pc
    };
    let mut out: Array<u8> = ArrayTrait::new();
    out.append(pc_sub(target, 1));
    HarmonicState { active_pcs: out, ..state }
}

fn halfstep_approach_down(state: HarmonicState) -> HarmonicState {
    let tonic_pc = state.tonic_pc;
    let family = state.family;
    let stable = stable_chord_tones_for(tonic_pc, family);
    let target = if stable.len() > 0 {
        *stable.at(0)
    } else {
        tonic_pc
    };
    let mut out: Array<u8> = ArrayTrait::new();
    out.append(pc_add(target, 1));
    HarmonicState { active_pcs: out, ..state }
}

fn family_rotation(state: HarmonicState) -> HarmonicState {
    let (new_family, new_tonic) = match state.family {
        ChordFamily::Major6Dim => (ChordFamily::Minor6Dim, pc_add(state.tonic_pc, 9)),
        ChordFamily::Minor6Dim => (ChordFamily::Dominant7Dim, pc_add(state.tonic_pc, 5)),
        ChordFamily::Dominant7Dim => (ChordFamily::Diminished, pc_add(state.tonic_pc, 1)),
        ChordFamily::Diminished => (ChordFamily::Major6Dim, state.tonic_pc),
    };
    let mut next = state;
    next.family = new_family;
    next.tonic_pc = new_tonic;
    next.inversion = 0;
    next.active_pcs = stable_chord_tones(@next);
    next
}

fn inversion_shift_up(state: HarmonicState) -> HarmonicState {
    let mut next = state;
    next.inversion = (next.inversion + 1) % 4;
    next.active_pcs = rotate_stable_bass(@next);
    next
}

fn inversion_shift_down(state: HarmonicState) -> HarmonicState {
    let mut next = state;
    next.inversion = if next.inversion == 0 {
        3
    } else {
        next.inversion - 1
    };
    next.active_pcs = rotate_stable_bass(@next);
    next
}

fn rotate_stable_bass(state: @HarmonicState) -> Array<u8> {
    let stable = stable_chord_tones(state);
    let n = stable.len();
    if n == 0 {
        return ArrayTrait::new();
    }
    let inv: usize = (*state.inversion).into() % n;
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= n {
            break;
        }
        let idx = (inv + i) % n;
        out.append(*stable.at(idx));
        i += 1;
    };
    out
}

fn resolve_to_stable(state: HarmonicState) -> HarmonicState {
    let mut next = state;
    next.tension_level = 0;
    next.active_pcs = stable_chord_tones(@next);
    next
}

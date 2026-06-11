//! Barry Harris v2 turnaround grammar through 6th-diminished families.
//!
//! See `docs/barry_harris_v2.md` §BH16.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    initial_harmonic_state, pc_add, stable_chord_tones_for, ChordFamily, HarmonicState,
};
use koji::composition::barry_v2_types::BarryTurnaroundKind;
use koji::composition::voice_leading::{harmony_target, HarmonicTimeline};

#[derive(Copy, Drop)]
pub struct BarryTurnaroundStep {
    pub tonic_pc: u8,
    pub family: ChordFamily,
    pub duration_steps: u8,
    pub function_label: u8,
}

pub fn generate_barry_turnaround(
    tonic_pc: u8, kind: BarryTurnaroundKind, length_steps: u8,
) -> Array<BarryTurnaroundStep> {
    let steps = if length_steps == 0 { 8 } else { length_steps };
    match kind {
        BarryTurnaroundKind::None => single_step_path(tonic_pc, steps),
        BarryTurnaroundKind::SixToTwoFive => six_to_two_five(tonic_pc, steps),
        BarryTurnaroundKind::OneSixTwoFive => one_six_two_five(tonic_pc, steps),
        BarryTurnaroundKind::TritoneDominantChain => tritone_dominant_chain(tonic_pc, steps),
        BarryTurnaroundKind::DiminishedPassingTurnaround => {
            diminished_passing_turnaround(tonic_pc, steps)
        },
        BarryTurnaroundKind::BackdoorSixDim => backdoor_six_dim(tonic_pc, steps),
    }
}

/// Saturating remainder used for the final functional step before the
/// duration-0 tonic marker. Never underflows and never returns 0.
fn remaining_dur(total: u8, used: u8) -> u8 {
    if total > used {
        total - used
    } else {
        1
    }
}

fn single_step_path(tonic_pc: u8, steps: u8) -> Array<BarryTurnaroundStep> {
    array![
        BarryTurnaroundStep {
            tonic_pc,
            family: ChordFamily::Major6Dim,
            duration_steps: steps,
            function_label: 1,
        },
    ]
}

fn six_to_two_five(tonic_pc: u8, steps: u8) -> Array<BarryTurnaroundStep> {
    let dur = if steps < 4 { 1 } else { steps / 4 };
    array![
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: dur, function_label: 1,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 9),
            family: ChordFamily::Dominant7Dim,
            duration_steps: dur,
            function_label: 6,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 2),
            family: ChordFamily::Minor6Dim,
            duration_steps: dur,
            function_label: 2,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 7),
            family: ChordFamily::Dominant7Dim,
            duration_steps: remaining_dur(steps, 3 * dur),
            function_label: 5,
        },
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: 0, function_label: 1,
        },
    ]
}

fn one_six_two_five(tonic_pc: u8, steps: u8) -> Array<BarryTurnaroundStep> {
    six_to_two_five(tonic_pc, steps)
}

fn tritone_dominant_chain(tonic_pc: u8, steps: u8) -> Array<BarryTurnaroundStep> {
    let dur = if steps < 3 { 1 } else { steps / 3 };
    array![
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: dur, function_label: 1,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 1),
            family: ChordFamily::Dominant7Dim,
            duration_steps: dur,
            function_label: 5,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 7),
            family: ChordFamily::Dominant7Dim,
            duration_steps: remaining_dur(steps, 2 * dur),
            function_label: 5,
        },
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: 0, function_label: 1,
        },
    ]
}

fn diminished_passing_turnaround(tonic_pc: u8, steps: u8) -> Array<BarryTurnaroundStep> {
    let dur = if steps < 4 { 1 } else { steps / 4 };
    array![
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: dur, function_label: 1,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 2),
            family: ChordFamily::Diminished,
            duration_steps: dur,
            function_label: 0,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 7),
            family: ChordFamily::Dominant7Dim,
            duration_steps: dur,
            function_label: 5,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 1),
            family: ChordFamily::Diminished,
            duration_steps: remaining_dur(steps, 3 * dur),
            function_label: 0,
        },
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: 0, function_label: 1,
        },
    ]
}

fn backdoor_six_dim(tonic_pc: u8, steps: u8) -> Array<BarryTurnaroundStep> {
    let dur = if steps < 3 { 1 } else { steps / 3 };
    array![
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: dur, function_label: 1,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 5),
            family: ChordFamily::Minor6Dim,
            duration_steps: dur,
            function_label: 4,
        },
        BarryTurnaroundStep {
            tonic_pc: pc_add(tonic_pc, 10),
            family: ChordFamily::Dominant7Dim,
            duration_steps: remaining_dur(steps, 2 * dur),
            function_label: 7,
        },
        BarryTurnaroundStep {
            tonic_pc, family: ChordFamily::Major6Dim, duration_steps: 0, function_label: 1,
        },
    ]
}

pub fn turnaround_step_to_harmonic_state(
    step: BarryTurnaroundStep, previous_hash: felt252,
) -> HarmonicState {
    let mut st = initial_harmonic_state(step.tonic_pc, step.family);
    st.previous_state_hash = previous_hash;
    st
}

pub fn barry_turnaround_to_timeline(
    tonic_pc: u8, kind: BarryTurnaroundKind, length_steps: u8,
) -> HarmonicTimeline {
    let steps = generate_barry_turnaround(tonic_pc, kind, length_steps);
    let mut targets = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        let step = steps.at(i);
        if *step.duration_steps == 0 {
            i += 1;
            continue;
        }
        let pcs = stable_chord_tones_for(*step.tonic_pc, *step.family);
        targets.append(harmony_target(pcs));
        i += 1;
    };
    HarmonicTimeline { targets }
}

pub fn turnaround_starts_and_ends_on_tonic(
    tonic_pc: u8, kind: BarryTurnaroundKind, length_steps: u8,
) -> bool {
    let steps = generate_barry_turnaround(tonic_pc, kind, length_steps);
    if steps.len() == 0 {
        return false;
    }
    let first = steps.at(0);
    let last = steps.at(steps.len() - 1);
    *first.tonic_pc == tonic_pc
        && *first.family == ChordFamily::Major6Dim
        && *last.tonic_pc == tonic_pc
        && *last.family == ChordFamily::Major6Dim
}

pub fn turnaround_total_duration(
    steps: Span<BarryTurnaroundStep>,
) -> u8 {
    let mut total: u8 = 0;
    let mut i: usize = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        total += *steps.at(i).duration_steps;
        i += 1;
    };
    total
}

pub fn six_to_two_five_function_labels() -> Array<u8> {
    array![1_u8, 6, 2, 5, 1]
}

//! Barry Harris v2 line-cell melodic grammar.
//!
//! See `docs/barry_harris_v2.md` §BH15.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    diminished_connector_tones, pc_add, pc_sub, scale_for_family, stable_chord_tones,
    BeatRole, HarmonicState,
};
use koji::composition::barry_v2_types::{BarryLineCell, BarryLineCellProfile};
use koji::composition::barry_rules::beat_role;
use koji::lcg::LCG;
use koji::rng::{LCGRandomSource, bounded};

pub fn line_cell_length(cell: BarryLineCell) -> u8 {
    match cell {
        BarryLineCell::DirectTarget => 1,
        BarryLineCell::ScaleRun3 => 3,
        BarryLineCell::ScaleRun4 => 4,
        BarryLineCell::HalfStepApproachBelow => 2,
        BarryLineCell::HalfStepApproachAbove => 2,
        BarryLineCell::EnclosureUpperLower => 3,
        BarryLineCell::EnclosureLowerUpper => 3,
        BarryLineCell::DiatonicUpperNeighbor => 2,
        BarryLineCell::DiatonicLowerNeighbor => 2,
        BarryLineCell::DoubleChromaticBelow => 3,
        BarryLineCell::DoubleChromaticAbove => 3,
        BarryLineCell::DiminishedArpeggio => 4,
        BarryLineCell::TurnbackCell => 5,
    }
}

pub fn line_cell_allowed_on_beat(cell: BarryLineCell, role: BeatRole) -> bool {
    match cell {
        BarryLineCell::DiminishedArpeggio => role != BeatRole::Strong,
        BarryLineCell::EnclosureUpperLower | BarryLineCell::EnclosureLowerUpper => {
            role == BeatRole::Approach || role == BeatRole::Passing
        },
        _ => true,
    }
}

/// Nearest scale tone strictly above `target_pc` on the pitch-class circle.
/// Works for transposed (unsorted) scales and wraps past the octave.
fn scale_neighbor_above(target_pc: u8, state: @HarmonicState) -> u8 {
    let scale = scale_for_family(*state.tonic_pc, *state.family);
    let t: u32 = target_pc.into();
    let mut best: u8 = target_pc;
    let mut best_dist: u32 = 13;
    let mut i: usize = 0;
    loop {
        if i >= scale.len() {
            break;
        }
        let pc = *scale.at(i);
        let p: u32 = pc.into();
        let dist = (p + 12 - t) % 12;
        if dist != 0 && dist < best_dist {
            best_dist = dist;
            best = pc;
        }
        i += 1;
    };
    best
}

/// Nearest scale tone strictly below `target_pc` on the pitch-class circle.
fn scale_neighbor_below(target_pc: u8, state: @HarmonicState) -> u8 {
    let scale = scale_for_family(*state.tonic_pc, *state.family);
    let t: u32 = target_pc.into();
    let mut best: u8 = target_pc;
    let mut best_dist: u32 = 13;
    let mut i: usize = 0;
    loop {
        if i >= scale.len() {
            break;
        }
        let pc = *scale.at(i);
        let p: u32 = pc.into();
        let dist = (t + 12 - p) % 12;
        if dist != 0 && dist < best_dist {
            best_dist = dist;
            best = pc;
        }
        i += 1;
    };
    best
}

pub fn realize_line_cell(
    cell: BarryLineCell, target_pc: u8, state: HarmonicState, direction_hint: i8,
) -> Array<u8> {
    match cell {
        BarryLineCell::DirectTarget => array![target_pc],
        BarryLineCell::HalfStepApproachBelow => array![pc_sub(target_pc, 1), target_pc],
        BarryLineCell::HalfStepApproachAbove => array![pc_add(target_pc, 1), target_pc],
        BarryLineCell::EnclosureUpperLower => {
            array![pc_add(target_pc, 1), pc_sub(target_pc, 1), target_pc]
        },
        BarryLineCell::EnclosureLowerUpper => {
            array![pc_sub(target_pc, 1), pc_add(target_pc, 1), target_pc]
        },
        BarryLineCell::DiatonicUpperNeighbor => {
            array![scale_neighbor_above(target_pc, @state), target_pc]
        },
        BarryLineCell::DiatonicLowerNeighbor => {
            array![scale_neighbor_below(target_pc, @state), target_pc]
        },
        BarryLineCell::DoubleChromaticBelow => {
            array![pc_sub(target_pc, 2), pc_sub(target_pc, 1), target_pc]
        },
        BarryLineCell::DoubleChromaticAbove => {
            array![pc_add(target_pc, 2), pc_add(target_pc, 1), target_pc]
        },
        BarryLineCell::ScaleRun3 => realize_scale_run(target_pc, @state, 3, direction_hint),
        BarryLineCell::ScaleRun4 => realize_scale_run(target_pc, @state, 4, direction_hint),
        BarryLineCell::DiminishedArpeggio => realize_diminished_arpeggio(target_pc, @state),
        BarryLineCell::TurnbackCell => {
            let upper = scale_neighbor_above(target_pc, @state);
            let lower = scale_neighbor_below(target_pc, @state);
            array![target_pc, upper, target_pc, lower, target_pc]
        },
    }
}

fn realize_scale_run(
    target_pc: u8, state: @HarmonicState, len: u8, direction_hint: i8,
) -> Array<u8> {
    let scale = scale_for_family(*state.tonic_pc, *state.family);
    let mut idx: usize = 0;
    loop {
        if idx >= scale.len() {
            break;
        }
        if *scale.at(idx) == target_pc {
            break;
        }
        idx += 1;
    };
    let mut out: Array<u8> = ArrayTrait::new();
    let dir: i32 = if direction_hint >= 0 { 1 } else { -1 };
    let mut step: i32 = len.into() - 1;
    loop {
        if step < 0 {
            break;
        }
        let offset: i32 = step * dir;
        let raw: i32 = idx.try_into().unwrap() + offset;
        let wrapped = ((raw % 8) + 8) % 8;
        out.append(*scale.at(wrapped.try_into().unwrap()));
        step -= 1;
    };
    out
}

fn realize_diminished_arpeggio(target_pc: u8, state: @HarmonicState) -> Array<u8> {
    let dim = diminished_connector_tones(state);
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= dim.len() && i >= 3 {
            break;
        }
        if i < dim.len() {
            out.append(*dim.at(i));
        }
        if i >= 2 {
            break;
        }
        i += 1;
    };
    out.append(target_pc);
    out
}

fn profile_cells(profile: BarryLineCellProfile) -> Span<BarryLineCell> {
    match profile {
        BarryLineCellProfile::SimpleApproaches => array![
            BarryLineCell::DirectTarget,
            BarryLineCell::HalfStepApproachBelow,
            BarryLineCell::HalfStepApproachAbove,
        ]
            .span(),
        BarryLineCellProfile::EnclosureHeavy => array![
            BarryLineCell::EnclosureUpperLower,
            BarryLineCell::EnclosureLowerUpper,
            BarryLineCell::HalfStepApproachBelow,
        ]
            .span(),
        BarryLineCellProfile::DiminishedArpeggioHeavy => array![
            BarryLineCell::DiminishedArpeggio,
            BarryLineCell::HalfStepApproachBelow,
            BarryLineCell::DirectTarget,
        ]
            .span(),
        BarryLineCellProfile::Scalar => array![
            BarryLineCell::ScaleRun3,
            BarryLineCell::DiatonicUpperNeighbor,
            BarryLineCell::DirectTarget,
        ]
            .span(),
        BarryLineCellProfile::MixedBebop => array![
            BarryLineCell::HalfStepApproachBelow,
            BarryLineCell::EnclosureUpperLower,
            BarryLineCell::TurnbackCell,
            BarryLineCell::DiminishedArpeggio,
            BarryLineCell::DirectTarget,
        ]
            .span(),
    }
}

pub fn pick_line_cell(
    rng: LCG, profile: BarryLineCellProfile, beat_role_val: BeatRole, max_len: u8,
) -> (BarryLineCell, LCG) {
    let pool = profile_cells(profile);
    let mut legal: Array<BarryLineCell> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= pool.len() {
            break;
        }
        let cell = *pool.at(i);
        if line_cell_length(cell) <= max_len && line_cell_allowed_on_beat(cell, beat_role_val) {
            legal.append(cell);
        }
        i += 1;
    };
    if legal.len() == 0 {
        return (BarryLineCell::DirectTarget, rng);
    }
    let (raw, next) = LCGRandomSource::draw(@rng);
    let pick = bounded(raw, legal.len().try_into().unwrap());
    (*legal.at(pick.try_into().unwrap()), next)
}

pub fn line_cell_ends_on_target(cell: BarryLineCell, target_pc: u8, state: HarmonicState) -> bool {
    let path = realize_line_cell(cell, target_pc, state, 1);
    if path.len() == 0 {
        return false;
    }
    let last_idx = path.len() - 1;
    let last_pc = *path.at(last_idx);
    last_pc == target_pc
}

pub fn line_cell_respects_max_len(cell: BarryLineCell, max_len: u8) -> bool {
    line_cell_length(cell) <= max_len
}

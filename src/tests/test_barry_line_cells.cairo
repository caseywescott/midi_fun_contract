use core::array::ArrayTrait;
use koji::composition::barry_harris::{initial_harmonic_state, ChordFamily};
use koji::composition::barry_labyrinth::{BarryLineCell, BarryLineCellProfile};
use koji::composition::barry_line_cells::{
    line_cell_ends_on_target, line_cell_length, line_cell_respects_max_len, pick_line_cell,
    realize_line_cell,
};
use koji::composition::barry_rules::beat_role;
use koji::lcg::LCG;

#[test]
fn test_direct_target_c() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let path = realize_line_cell(BarryLineCell::DirectTarget, 0, state, 1);
    assert(path.len() == 1, 'len 1');
    assert(*path.at(0) == 0, 'C');
}

#[test]
fn test_half_step_below_c() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let path = realize_line_cell(BarryLineCell::HalfStepApproachBelow, 0, state, 1);
    assert(path.len() == 2, 'len 2');
    assert(*path.at(0) == 11, 'B');
    assert(*path.at(1) == 0, 'C');
}

#[test]
fn test_enclosure_ends_on_target() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    assert(
        line_cell_ends_on_target(BarryLineCell::EnclosureUpperLower, 0, state), 'enclosure',
    );
}

#[test]
fn test_max_len_respected() {
    assert(line_cell_respects_max_len(BarryLineCell::DirectTarget, 2), 'direct');
    assert(!line_cell_respects_max_len(BarryLineCell::TurnbackCell, 3), 'turnback');
}

#[test]
fn test_diminished_arpeggio_uses_connectors() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let path = realize_line_cell(BarryLineCell::DiminishedArpeggio, 0, state, 1);
    assert(path.len() == 4, 'len 4');
    assert(*path.at(3) == 0, 'ends C');
}

#[test]
fn test_pick_line_cell_deterministic() {
    let rng = LCG { state: 99, multiplier: 5, increment: 3, modulus: 256 };
    let role = beat_role(2);
    let (c1, _) = pick_line_cell(rng, BarryLineCellProfile::MixedBebop, role, 5);
    let rng2 = LCG { state: 99, multiplier: 5, increment: 3, modulus: 256 };
    let (c2, _) = pick_line_cell(rng2, BarryLineCellProfile::MixedBebop, role, 5);
    assert(c1 == c2, 'same cell');
}

#[test]
fn test_every_cell_ends_on_target() {
    let cells = array![
        BarryLineCell::DirectTarget,
        BarryLineCell::HalfStepApproachBelow,
        BarryLineCell::HalfStepApproachAbove,
        BarryLineCell::EnclosureUpperLower,
        BarryLineCell::EnclosureLowerUpper,
        BarryLineCell::DiatonicUpperNeighbor,
        BarryLineCell::DiatonicLowerNeighbor,
        BarryLineCell::DoubleChromaticBelow,
        BarryLineCell::DoubleChromaticAbove,
        BarryLineCell::DiminishedArpeggio,
        BarryLineCell::TurnbackCell,
    ];
    let mut i: usize = 0;
    loop {
        if i >= cells.len() {
            break;
        }
        let cell = *cells.at(i);
        let st = initial_harmonic_state(0, ChordFamily::Major6Dim);
        assert(line_cell_ends_on_target(cell, 0, st), 'ends target');
        i += 1;
    };
}

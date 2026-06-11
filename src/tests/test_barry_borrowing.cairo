use koji::composition::barry_harris::{initial_harmonic_state, ChordFamily};
use koji::composition::barry_borrowing::{
    borrow_neighbor_state, borrowed_pcs_in_known_scale, borrowed_state_must_resolve,
    decrement_borrow_span, return_borrowed_state, BarryBorrowKind,
};
use core::option::OptionTrait;

#[test]
fn test_borrowing_sets_borrow_state() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let v2 = borrow_neighbor_state(state, BarryBorrowKind::BorrowUpperNeighbor, 3);
    match v2.borrow_state {
        Option::Some(bs) => {
            assert(bs.remaining_span == 3, 'span');
            assert(bs.borrow_kind == BarryBorrowKind::BorrowUpperNeighbor, 'kind');
        },
        Option::None(_) => {
            assert(false, 'has borrow');
        },
    }
}

#[test]
fn test_borrowing_increases_tension() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let before = state.tension_level;
    let v2 = borrow_neighbor_state(state, BarryBorrowKind::BorrowLowerNeighbor, 2);
    assert(v2.harmonic_state.tension_level > before, 'tension up');
}

#[test]
fn test_borrow_resolves_within_span() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let v2 = borrow_neighbor_state(state, BarryBorrowKind::BorrowUpperNeighbor, 2);
    let v2a = decrement_borrow_span(v2);
    let v2b = decrement_borrow_span(v2a);
    assert(borrowed_state_must_resolve(@v2b), 'must resolve');
    let resolved = return_borrowed_state(v2b);
    match resolved.borrow_state {
        Option::None(_) => {},
        Option::Some(_) => {
            assert(false, 'cleared');
        },
    }
}

#[test]
fn test_borrowed_pcs_in_scale() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let v2 = borrow_neighbor_state(state, BarryBorrowKind::BorrowRelativeMinorSix, 3);
    assert(borrowed_pcs_in_known_scale(@v2), 'in scale');
}

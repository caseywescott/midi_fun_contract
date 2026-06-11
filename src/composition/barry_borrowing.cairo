//! Barry Harris v2 neighbor borrowing — local color with bounded resolution.
//!
//! See `docs/barry_harris_v2.md` §BH14.

use core::hash::HashStateTrait;
use core::option::OptionTrait;
use core::poseidon::PoseidonTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    contains_pc, pc_add, pc_sub, scale_for_family, state_hash, stable_chord_tones,
    ChordFamily, HarmonicState,
};
use koji::composition::barry_v2_types::BarryTextureMode;

#[derive(Copy, Drop, PartialEq)]
pub enum BarryBorrowKind {
    BorrowUpperNeighbor,
    BorrowLowerNeighbor,
    BorrowDiminishedNeighbor,
    BorrowRelativeMinorSix,
    BorrowDominantNeighbor,
}

#[derive(Copy, Drop)]
pub struct BorrowState {
    pub origin_hash: felt252,
    pub borrowed_from_family: ChordFamily,
    pub borrowed_from_tonic_pc: u8,
    pub borrow_kind: BarryBorrowKind,
    pub remaining_span: u8,
}

#[derive(Drop)]
pub struct BarryV2State {
    pub harmonic_state: HarmonicState,
    pub borrow_state: Option<BorrowState>,
    pub texture_mode: BarryTextureMode,
}

pub fn borrow_neighbor_state(
    state: HarmonicState, kind: BarryBorrowKind, max_span: u8,
) -> BarryV2State {
    let origin_hash = state_hash(@state);
    let origin_tonic = state.tonic_pc;
    let origin_family = state.family;
    let span = if max_span == 0 { 2 } else { max_span };
    let (tonic, family) = borrow_target(state.tonic_pc, state.family, kind);
    let mut hs = state;
    hs.tonic_pc = tonic;
    hs.family = family;
    let tension_delta: u8 = 1;
    if hs.tension_level < 255 - tension_delta {
        hs.tension_level += tension_delta;
    }
    hs.active_pcs = scale_for_family(tonic, family);
    BarryV2State {
        harmonic_state: hs,
        borrow_state: Option::Some(
            BorrowState {
                origin_hash,
                borrowed_from_family: origin_family,
                borrowed_from_tonic_pc: origin_tonic,
                borrow_kind: kind,
                remaining_span: span,
            },
        ),
        texture_mode: BarryTextureMode::MonophonicLine,
    }
}

fn borrow_target(tonic_pc: u8, family: ChordFamily, kind: BarryBorrowKind) -> (u8, ChordFamily) {
    match kind {
        BarryBorrowKind::BorrowUpperNeighbor => (pc_add(tonic_pc, 1), family),
        BarryBorrowKind::BorrowLowerNeighbor => (pc_sub(tonic_pc, 1), family),
        BarryBorrowKind::BorrowDiminishedNeighbor => {
            (pc_add(tonic_pc, 2), ChordFamily::Diminished)
        },
        BarryBorrowKind::BorrowRelativeMinorSix => {
            (pc_add(tonic_pc, 9), ChordFamily::Minor6Dim)
        },
        BarryBorrowKind::BorrowDominantNeighbor => {
            (pc_add(tonic_pc, 5), ChordFamily::Dominant7Dim)
        },
    }
}

pub fn decrement_borrow_span(state: BarryV2State) -> BarryV2State {
    match state.borrow_state {
        Option::Some(bs) => {
            let remaining = if bs.remaining_span == 0 { 0 } else { bs.remaining_span - 1 };
            BarryV2State {
                borrow_state: Option::Some(BorrowState { remaining_span: remaining, ..bs }),
                ..state
            }
        },
        Option::None(_) => state,
    }
}

pub fn return_borrowed_state(state: BarryV2State) -> BarryV2State {
    match state.borrow_state {
        Option::Some(bs) => {
            let mut hs = state.harmonic_state;
            hs.tonic_pc = bs.borrowed_from_tonic_pc;
            hs.family = bs.borrowed_from_family;
            hs.tension_level = if hs.tension_level > 0 { hs.tension_level - 1 } else { 0 };
            hs.active_pcs = stable_chord_tones(@hs);
            BarryV2State {
                harmonic_state: hs,
                borrow_state: Option::None,
                texture_mode: state.texture_mode,
            }
        },
        Option::None(_) => state,
    }
}

pub fn borrowed_state_must_resolve(state: @BarryV2State) -> bool {
    match *state.borrow_state {
        Option::Some(bs) => bs.remaining_span == 0,
        Option::None(_) => false,
    }
}

pub fn borrowed_pcs_in_known_scale(state: @BarryV2State) -> bool {
    let tonic = *state.harmonic_state.tonic_pc;
    let family = *state.harmonic_state.family;
    let scale = scale_for_family(tonic, family);
    let mut i: usize = 0;
    loop {
        if i >= state.harmonic_state.active_pcs.len() {
            break;
        }
        if !contains_pc(scale.span(), *state.harmonic_state.active_pcs.at(i)) {
            return false;
        }
        i += 1;
    };
    true
}

pub fn v2_state_from_harmonic(
    state: HarmonicState, texture_mode: BarryTextureMode,
) -> BarryV2State {
    BarryV2State {
        harmonic_state: state,
        borrow_state: Option::None,
        texture_mode,
    }
}

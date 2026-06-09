//! Harmonic slot types, constants, skeleton catalogues.
//!
//! See `docs/harmonic_substitution_walk_spec.md`.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::voice_leading::{harmony_target, HarmonyTarget};

pub const HARMONIC_SLOTS_MAX: u32 = 64;
pub const PREFIX_DEPTH_MAX: u8 = 3;
pub const REWRITE_TABLE_MAX: u16 = 48;
pub const CONTINUATION_TABLE_MAX: u16 = 128;
pub const HARMONIC_BEATS_PER_BAR: u8 = 4;

pub const FAMILY_JAZZ_SUBSTITUTION: u8 = 1;

pub const SKELETON_BLUES_12: u16 = 1;
pub const SKELETON_RHYTHM_CHANGES_32: u16 = 2;
pub const SKELETON_TURNAROUND_AXIOM_3: u16 = 3;
pub const SKELETON_TWO_FIVE_ONE_1: u16 = 4;

pub const RULE_REPETITION: u8 = 1;
pub const RULE_ENRICHMENT: u8 = 2;
pub const RULE_RELATIVE_MINOR: u8 = 3;
pub const RULE_TRITONE_SUB: u8 = 4;
pub const RULE_PREP_DOM: u8 = 5;
pub const RULE_PREP_MINOR: u8 = 6;
pub const RULE_TO_FOURTH: u8 = 7;
pub const RULE_TWO_FIVE: u8 = 8;
pub const RULE_NEAPOLITAN_2X2: u8 = 9;

pub const FN_TONIC: u8 = 0;
pub const FN_PREDOM: u8 = 1;
pub const FN_DOM: u8 = 2;
pub const FN_PASS: u8 = 3;
pub const FN_HALF_DIM: u8 = 4;

#[derive(Copy, Drop, PartialEq)]
pub struct HarmonicSlot {
    pub beats: u8,
    pub root_pc: u8,
    pub quality_id: u8,
    pub function_class: u8,
}

#[derive(Copy, Drop, PartialEq)]
pub struct ChordTransition {
    pub from_quality: u8,
    pub to_quality: u8,
    pub to_root_pc: u8,
    pub slot_span: u8,
}

fn pc_add(root: u8, interval: u8) -> u8 {
    let r: u32 = root.into();
    let i: u32 = interval.into();
    ((r + i) % 12).try_into().unwrap()
}

pub fn quality_pcs(root_pc: u8, quality_id: u8) -> Span<u8> {
    if quality_id == 0 {
        array![pc_add(root_pc, 0), pc_add(root_pc, 4), pc_add(root_pc, 7)].span()
    } else if quality_id == 1 {
        array![pc_add(root_pc, 0), pc_add(root_pc, 4), pc_add(root_pc, 7), pc_add(root_pc, 10)].span()
    } else if quality_id == 2 {
        array![pc_add(root_pc, 0), pc_add(root_pc, 3), pc_add(root_pc, 7), pc_add(root_pc, 10)].span()
    } else if quality_id == 3 {
        array![pc_add(root_pc, 0), pc_add(root_pc, 3), pc_add(root_pc, 6), pc_add(root_pc, 10)].span()
    } else if quality_id == 4 {
        array![pc_add(root_pc, 0), pc_add(root_pc, 3), pc_add(root_pc, 6), pc_add(root_pc, 9)].span()
    } else if quality_id == 5 {
        array![pc_add(root_pc, 0), pc_add(root_pc, 4), pc_add(root_pc, 7), pc_add(root_pc, 11)].span()
    } else {
        array![pc_add(root_pc, 0), pc_add(root_pc, 4), pc_add(root_pc, 7)].span()
    }
}

pub fn slot_to_harmony_target(slot: HarmonicSlot) -> HarmonyTarget {
    let pcs = quality_pcs(slot.root_pc, slot.quality_id);
    let mut arr: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        arr.append(*pcs.at(i));
        i += 1;
    };
    harmony_target(arr)
}

pub fn chord_transition_normalized(from_slot: HarmonicSlot, to_slot: HarmonicSlot) -> ChordTransition {
    let fr: u32 = from_slot.root_pc.into();
    let tr: u32 = to_slot.root_pc.into();
    let delta: u8 = ((12 + tr - fr) % 12).try_into().unwrap();
    ChordTransition {
        from_quality: from_slot.quality_id,
        to_quality: to_slot.quality_id,
        to_root_pc: delta,
        slot_span: to_slot.beats,
    }
}

pub fn slot_beats(slot: HarmonicSlot) -> u8 {
    slot.beats
}

pub fn slots_per_bar(beats: u8) -> u8 {
    if beats >= HARMONIC_BEATS_PER_BAR {
        beats / HARMONIC_BEATS_PER_BAR
    } else {
        0
    }
}

pub fn contains_u8(pcs: Span<u8>, pc: u8) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        if *pcs.at(i) == pc {
            return true;
        }
        i += 1;
    };
    false
}

pub fn pcs_sets_equal(a: Span<u8>, b: Span<u8>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: usize = 0;
    loop {
        if i >= a.len() {
            break;
        }
        if !contains_u8(b, *a.at(i)) {
            return false;
        }
        i += 1;
    };
    true
}

#[derive(Copy, Drop)]
pub struct SkeletonMeta {
    pub skeleton_id: u16,
    pub slot_count: u16,
    pub total_beats: u16,
}

pub fn skeleton_meta(skeleton_id: u16) -> Option<SkeletonMeta> {
    if skeleton_id == SKELETON_TURNAROUND_AXIOM_3 {
        Option::Some(SkeletonMeta { skeleton_id, slot_count: 3, total_beats: 12 })
    } else if skeleton_id == SKELETON_TWO_FIVE_ONE_1 {
        Option::Some(SkeletonMeta { skeleton_id, slot_count: 3, total_beats: 8 })
    } else if skeleton_id == SKELETON_BLUES_12 {
        Option::Some(SkeletonMeta { skeleton_id, slot_count: 12, total_beats: 48 })
    } else if skeleton_id == SKELETON_RHYTHM_CHANGES_32 {
        Option::Some(SkeletonMeta { skeleton_id, slot_count: 8, total_beats: 32 })
    } else {
        Option::None
    }
}

fn turnaround_axiom_slot(index: u16) -> Option<HarmonicSlot> {
    if index >= 3 {
        return Option::None;
    }
    Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 0, function_class: 0 })
}

fn two_five_one_slot(index: u16) -> Option<HarmonicSlot> {
    if index == 0 {
        Option::Some(HarmonicSlot { beats: 2, root_pc: 2, quality_id: 2, function_class: 1 })
    } else if index == 1 {
        Option::Some(HarmonicSlot { beats: 2, root_pc: 7, quality_id: 1, function_class: 2 })
    } else if index == 2 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 5, function_class: 0 })
    } else {
        Option::None
    }
}

fn blues_12_slot(index: u16) -> Option<HarmonicSlot> {
    if index == 0 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 0, function_class: 0 })
    } else if index == 1 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 5, quality_id: 0, function_class: 1 })
    } else if index == 2 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 0, function_class: 0 })
    } else if index == 3 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 1, function_class: 2 })
    } else if index == 4 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 5, quality_id: 0, function_class: 1 })
    } else if index == 5 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 5, quality_id: 0, function_class: 1 })
    } else if index == 6 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 0, function_class: 0 })
    } else if index == 7 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 0, function_class: 0 })
    } else if index == 8 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 7, quality_id: 1, function_class: 2 })
    } else if index == 9 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 5, quality_id: 0, function_class: 1 })
    } else if index == 10 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 0, function_class: 0 })
    } else if index == 11 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 0, function_class: 0 })
    } else {
        Option::None
    }
}

fn rhythm_changes_32_slot(index: u16) -> Option<HarmonicSlot> {
    if index == 0 || index == 1 || index == 4 || index == 5 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 5, function_class: 0 })
    } else if index == 2 || index == 3 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 5, quality_id: 5, function_class: 1 })
    } else if index == 6 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 7, quality_id: 1, function_class: 2 })
    } else if index == 7 {
        Option::Some(HarmonicSlot { beats: 4, root_pc: 0, quality_id: 5, function_class: 0 })
    } else {
        Option::None
    }
}

pub fn skeleton_slot_at(skeleton_id: u16, index: u16) -> Option<HarmonicSlot> {
    if skeleton_id == SKELETON_TURNAROUND_AXIOM_3 {
        turnaround_axiom_slot(index)
    } else if skeleton_id == SKELETON_TWO_FIVE_ONE_1 {
        two_five_one_slot(index)
    } else if skeleton_id == SKELETON_BLUES_12 {
        blues_12_slot(index)
    } else if skeleton_id == SKELETON_RHYTHM_CHANGES_32 {
        rhythm_changes_32_slot(index)
    } else {
        Option::None
    }
}

pub fn skeleton_slot_count(skeleton_id: u16) -> u16 {
    match skeleton_meta(skeleton_id) {
        Option::Some(m) => m.slot_count,
        Option::None => 0,
    }
}

pub fn known_skeleton(skeleton_id: u16) -> Option<Span<HarmonicSlot>> {
    let count = skeleton_slot_count(skeleton_id);
    if count == 0 {
        return Option::None;
    }
    let mut out: Array<HarmonicSlot> = ArrayTrait::new();
    let mut i: u16 = 0;
    loop {
        if i >= count {
            break;
        }
        let s = skeleton_slot_at(skeleton_id, i).unwrap();
        out.append(s);
        i += 1;
    };
    Option::Some(out.span())
}

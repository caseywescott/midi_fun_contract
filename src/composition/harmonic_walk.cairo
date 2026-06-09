//! Harmonic substitution walk — rewrites, continuations, LCG timeline (Pachet 1999).
//!
//! See `docs/harmonic_substitution_walk_spec.md`.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::known_harmonic_skeletons::{
    chord_transition_normalized, contains_u8, known_skeleton, pcs_sets_equal, quality_pcs,
    slot_beats, slot_to_harmony_target, slots_per_bar, ChordTransition, HarmonicSlot,
    HARMONIC_BEATS_PER_BAR, HARMONIC_SLOTS_MAX, SKELETON_BLUES_12, SKELETON_RHYTHM_CHANGES_32,
    SKELETON_TURNAROUND_AXIOM_3, SKELETON_TWO_FIVE_ONE_1, FAMILY_JAZZ_SUBSTITUTION,
};
use koji::composition::voice_leading::HarmonicTimeline;

// ──────────────────────────────────────────────────────────
// H2 — Rewrites
// ──────────────────────────────────────────────────────────

use koji::composition::known_harmonic_rewrites::{
    build_rhs_slots, lhs_matches, rewrite_meta, HarmonicRewrite, MAX_APPLICABLE, REWRITE_COUNT,
};

pub fn rewrites_applicable_at(
    slots: Span<HarmonicSlot>, index: u32,
) -> Span<u16> {
    let mut ids: Array<u16> = ArrayTrait::new();
    let mut rid: u16 = 0;
    loop {
        if rid >= REWRITE_COUNT || ids.len() >= MAX_APPLICABLE.into() {
            break;
        }
        if index >= slots.len() {
            break;
        }
        let anchor = *slots.at(index);
        if lhs_matches(rid, anchor, slots, index) {
            ids.append(rid);
        }
        rid += 1;
    };
    ids.span()
}

pub fn sum_slot_beats(slots: Span<HarmonicSlot>) -> u16 {
    let mut total: u16 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= slots.len() {
            break;
        }
        total += (*slots.at(i)).beats.into();
        i += 1;
    };
    total
}

pub fn rewrite_preserves_beats(before: Span<HarmonicSlot>, after: Span<HarmonicSlot>) -> bool {
    sum_slot_beats(before) == sum_slot_beats(after)
}

pub fn apply_rewrite(
    slots: Span<HarmonicSlot>, rule_id: u16, index: u32,
) -> Array<HarmonicSlot> {
    let meta = rewrite_meta(rule_id).unwrap();
    let before_beats = sum_slot_beats(slots);
    let anchor = *slots.at(index);
    let rhs = build_rhs_slots(rule_id, anchor);
    let mut out: Array<HarmonicSlot> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= slots.len() {
            break;
        }
        if i == index {
            let mut k: u32 = 0;
            loop {
                if k >= rhs.len() {
                    break;
                }
                out.append(*rhs.at(k));
                k += 1;
            };
            i += meta.lhs_len.into();
        } else {
            out.append(*slots.at(i));
            i += 1;
        }
    };
    assert(rewrite_preserves_beats(slots, out.span()), 'rewrite beats');
    assert(sum_slot_beats(out.span()) == before_beats, 'beats preserved');
    out
}

// ──────────────────────────────────────────────────────────
// H3 — Continuations
// ──────────────────────────────────────────────────────────

use koji::composition::known_harmonic_continuations::{
    continuation_at, continuation_next_slot, CONTINUATION_COUNT, MAX_CONT_CANDS,
    TransitionContinuation,
};
use koji::lcg::LCG;
use koji::rng::{RandomSource, bounded};

pub fn prefix_matches(row: TransitionContinuation, from_q: u8, to_q: u8, to_root: u8) -> bool {
    if row.prefix_from_q == 255 {
        return true;
    }
    row.prefix_from_q == from_q && row.prefix_to_q == to_q && row.prefix_to_root == to_root
}

pub fn continuations_for_prefix(from_q: u8, to_q: u8, to_root: u8) -> Span<u16> {
    let mut ids: Array<u16> = ArrayTrait::new();
    let mut i: u16 = 0;
    loop {
        if i >= CONTINUATION_COUNT || ids.len() >= MAX_CONT_CANDS.into() {
            break;
        }
        let row = continuation_at(i).unwrap();
        if prefix_matches(row, from_q, to_q, to_root) {
            ids.append(i);
        }
        i += 1;
    };
    ids.span()
}

pub fn pick_continuation(
    raw: u32, cands: Span<u16>, surprise_bias: u8,
) -> u16 {
    if cands.len() == 0 {
        return 0;
    }
    if cands.len() == 1 {
        return *cands.at(0);
    }
    let idx = if surprise_bias < 85 {
        0
    } else if surprise_bias > 170 {
        cands.len() - 1
    } else {
        bounded(raw, cands.len())
    };
    *cands.at(idx)
}

pub fn surprise_tier_for_row(row_id: u16) -> u8 {
    match continuation_at(row_id) {
        Option::Some(r) => r.surprise_tier,
        Option::None => 128,
    }
}

pub fn pick_continuation_by_tier(cands: Span<u16>, prefer_high_surprise: bool) -> u16 {
    if cands.len() == 0 {
        return 0;
    }
    let mut best: u16 = *cands.at(0);
    let mut best_tier: u8 = surprise_tier_for_row(best);
    let mut i: u32 = 1;
    loop {
        if i >= cands.len() {
            break;
        }
        let rid = *cands.at(i);
        let tier = surprise_tier_for_row(rid);
        let better = if prefer_high_surprise {
            tier > best_tier
        } else {
            tier < best_tier
        };
        if better {
            best = rid;
            best_tier = tier;
        }
        i += 1;
    };
    best
}

// ──────────────────────────────────────────────────────────
// H4 — Walk plan and timeline
// ──────────────────────────────────────────────────────────

use koji::composition::voice_leading::{
    HarmonyTarget, generate_ornamented_min_motion_from_timeline, long_plr_progression_params,
    ornamented_timeline_cycle_ticks,
};
use koji::composition::melodic_canon::NoteEvent;

#[derive(Copy, Drop)]
pub struct HarmonicWalkPlan {
    pub family_id: u8,
    pub skeleton_id: u16,
    pub rewrite_budget: u8,
    pub max_rewrites_per_section: u8,
    pub continuation_depth: u8,
    pub surprise_bias: u8,
}

fn pow2(p: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= p {
            break;
        }
        r = r * 2;
        i += 1;
    };
    r
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

pub fn harmonic_walk_plan_default() -> HarmonicWalkPlan {
    HarmonicWalkPlan {
        family_id: FAMILY_JAZZ_SUBSTITUTION,
        skeleton_id: SKELETON_TURNAROUND_AXIOM_3,
        rewrite_budget: 0,
        max_rewrites_per_section: 4,
        continuation_depth: 0,
        surprise_bias: 0,
    }
}

pub fn harmonic_walk_plan_from_seed(seed: felt252) -> HarmonicWalkPlan {
    let s: u256 = seed.into();
    let sk_bits = extract_bits(s, 16, 4);
    let skeleton_id = if sk_bits == 0 {
        SKELETON_TURNAROUND_AXIOM_3
    } else if sk_bits == 1 {
        SKELETON_BLUES_12
    } else if sk_bits == 2 {
        SKELETON_RHYTHM_CHANGES_32
    } else if sk_bits == 3 {
        SKELETON_TWO_FIVE_ONE_1
    } else {
        SKELETON_TURNAROUND_AXIOM_3
    };
    let rb = extract_bits(s, 20, 4);
    HarmonicWalkPlan {
        family_id: FAMILY_JAZZ_SUBSTITUTION,
        skeleton_id,
        rewrite_budget: if rb > 8 {
            8
        } else {
            rb.try_into().unwrap()
        },
        max_rewrites_per_section: 4,
        continuation_depth: extract_bits(s, 24, 2).try_into().unwrap(),
        surprise_bias: extract_bits(s, 28, 8).try_into().unwrap(),
    }
}

fn lcg_from_seed(seed: felt252, shift: u32) -> LCG {
    let s: u256 = seed.into();
    let mut state: u32 = extract_bits(s, shift, 8);
    if state == 0 {
        state = 11;
    }
    LCG { state, multiplier: 5, increment: 3, modulus: 256 }
}

pub fn expand_skeleton_with_rewrites(
    plan: @HarmonicWalkPlan, seed: felt252,
) -> Array<HarmonicSlot> {
    let sk = known_skeleton(*plan.skeleton_id).unwrap();
    let mut slots: Array<HarmonicSlot> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= sk.len() {
            break;
        }
        slots.append(*sk.at(i));
        i += 1;
    };
    if *plan.rewrite_budget == 0 {
        return slots;
    }
    let mut rng = lcg_from_seed(seed, 0);
    let mut applied: u8 = 0;
    let mut pos: u32 = 0;
    loop {
        if pos >= slots.len() || applied >= *plan.rewrite_budget {
            break;
        }
        let cands = rewrites_applicable_at(slots.span(), pos);
        if cands.len() > 0 {
            let (raw, next) = rng.draw();
            rng = next;
            if raw % 3 != 0 {
                let pick = bounded(raw, cands.len());
                let rid = *cands.at(pick);
                slots = apply_rewrite(slots.span(), rid, pos);
                applied += 1;
            }
        }
        pos += 1;
    };
    slots
}

pub fn walk_harmonic_continuations(
    plan: @HarmonicWalkPlan, seed: felt252, mut slots: Array<HarmonicSlot>,
) -> Array<HarmonicSlot> {
    if *plan.continuation_depth == 0 || slots.len() == 0 {
        return slots;
    }
    let mut rng = lcg_from_seed(seed, 8);
    let mut step: u8 = 0;
    loop {
        if step >= *plan.continuation_depth || slots.len() >= HARMONIC_SLOTS_MAX {
            break;
        }
        let last = *slots.at(slots.len() - 1);
        let (from_q, to_q, to_root) = if slots.len() >= 2 {
            let prev = *slots.at(slots.len() - 2);
            let tr = chord_transition_normalized(prev, last);
            (prev.quality_id, tr.to_quality, tr.to_root_pc)
        } else {
            (255_u8, 255, 255)
        };
        let cands = continuations_for_prefix(from_q, to_q, to_root);
        let (raw, next) = rng.draw();
        rng = next;
        let row_id = pick_continuation(raw, cands, *plan.surprise_bias);
        let row = continuation_at(row_id).unwrap();
        slots.append(continuation_next_slot(row, last));
        step += 1;
    };
    slots
}

pub fn timeline_slot_count_bounded(slots: Span<HarmonicSlot>) -> bool {
    slots.len() <= HARMONIC_SLOTS_MAX
}

pub fn all_targets_non_empty(slots: Span<HarmonicSlot>) -> bool {
    let mut i: u32 = 0;
    loop {
        if i >= slots.len() {
            break;
        }
        let ht = slot_to_harmony_target(*slots.at(i));
        if ht.pcs.len() == 0 {
            return false;
        }
        i += 1;
    };
    true
}

pub fn harmonic_walk_to_timeline(
    plan: @HarmonicWalkPlan, seed: felt252,
) -> HarmonicTimeline {
    let mut slots = expand_skeleton_with_rewrites(plan, seed);
    slots = walk_harmonic_continuations(plan, seed, slots);
    assert(timeline_slot_count_bounded(slots.span()), 'slot bound');
    assert(all_targets_non_empty(slots.span()), 'empty target');
    let mut targets: Array<HarmonyTarget> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= slots.len() {
            break;
        }
        targets.append(slot_to_harmony_target(*slots.at(i)));
        i += 1;
    };
    HarmonicTimeline { targets }
}

pub fn surprise_script_tier(_script_index: u32, is_surprise: bool) -> u8 {
    if is_surprise {
        255
    } else {
        0
    }
}

pub fn slots_from_skeleton_id(skeleton_id: u16) -> Array<HarmonicSlot> {
    let sk = known_skeleton(skeleton_id).unwrap();
    let mut out: Array<HarmonicSlot> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= sk.len() {
            break;
        }
        out.append(*sk.at(i));
        i += 1;
    };
    out
}

pub fn timeline_from_harmonic_walk(seed: felt252, plan: HarmonicWalkPlan) -> HarmonicTimeline {
    harmonic_walk_to_timeline(@plan, seed)
}

/// Map structural position to slot index for material gates (walk timeline).
pub fn harmonic_walk_region_at(pos: u32, len: u32, slot_count: u32) -> u32 {
    if len == 0 || slot_count == 0 {
        return 0;
    }
    (pos * slot_count) / len
}

/// Bit 36: when set, profile-24 canon material gates follow the harmonic-walk timeline.
pub fn harmonic_walk_enabled_from_seed(seed: felt252) -> bool {
    let s: u256 = seed.into();
    extract_bits(s, 36, 1) != 0
}

/// Force harmonic-walk material gates for profile 24 (demo / explicit opt-in).
pub fn canon_seed_enable_harmonic_walk(seed: felt252) -> felt252 {
    let s: u256 = seed.into();
    let mask: u256 = pow2(36);
    (s | mask).try_into().unwrap()
}

/// Build a reproducible harmonic-walk demo seed (domain bits match `harmonic_walk_plan_from_seed`).
/// `sk_bits`: 0=turnaround axiom, 1=blues-12, 2=rhythm-changes-32, 3=two-five-one.
pub fn harmonic_walk_demo_seed(
    sk_bits: u32, rewrite_budget: u8, continuation_depth: u8, surprise_bias: u8, tag: u32,
) -> felt252 {
    let t: u256 = (tag % 65536).into();
    let sk: u256 = ((sk_bits % 16) * 65536).into();
    let rb: u256 = (rewrite_budget.into() * 1048576).into();
    let cd_u: u32 = continuation_depth.into();
    let cd: u256 = ((cd_u % 4) * 16777216).into();
    let sb: u256 = (surprise_bias.into() * 268435456).into();
    (t + sk + rb + cd + sb).try_into().unwrap()
}

/// Harmonic-walk demo seed with profile-24 canon walk bit (36) set.
pub fn jazz_canon_walk_demo_seed(
    sk_bits: u32, rewrite_budget: u8, continuation_depth: u8, surprise_bias: u8, tag: u32,
) -> felt252 {
    canon_seed_enable_harmonic_walk(
        harmonic_walk_demo_seed(sk_bits, rewrite_budget, continuation_depth, surprise_bias, tag),
    )
}

/// Ornamented four-part block harmony from a seeded harmonic walk + minimal-motion allocation.
pub fn generate_ornamented_harmonic_walk_progression(seed: felt252) -> Array<NoteEvent> {
    let plan = harmonic_walk_plan_from_seed(seed);
    let timeline = harmonic_walk_to_timeline(@plan, seed);
    let params = long_plr_progression_params(seed);
    generate_ornamented_min_motion_from_timeline(seed, timeline, params)
}

/// Grid ticks for one ornamented harmonic-walk pass (MIDI loop length).
pub fn harmonic_walk_progression_cycle_ticks(seed: felt252) -> u32 {
    let plan = harmonic_walk_plan_from_seed(seed);
    let timeline = harmonic_walk_to_timeline(@plan, seed);
    let nbeats: u32 = timeline.targets.len();
    ornamented_timeline_cycle_ticks(seed, nbeats)
}

use core::array::ArrayTrait;
use core::option::OptionTrait;
use koji::composition::known_harmonic_skeletons::HarmonicSlot;
use koji::composition::harmonic_walk::{
    apply_rewrite, continuations_for_prefix, expand_skeleton_with_rewrites,
    harmonic_walk_plan_default, harmonic_walk_plan_from_seed, harmonic_walk_to_timeline,
    pick_continuation, rewrite_preserves_beats, rewrites_applicable_at, sum_slot_beats,
    surprise_script_tier, surprise_tier_for_row, timeline_from_harmonic_walk,
    HarmonicWalkPlan,
};
use koji::composition::known_harmonic_skeletons::{
    HARMONIC_BEATS_PER_BAR, SKELETON_BLUES_12, SKELETON_RHYTHM_CHANGES_32,
    SKELETON_TURNAROUND_AXIOM_3, SKELETON_TWO_FIVE_ONE_1, contains_u8, pcs_sets_equal,
    quality_pcs, slot_beats, slot_to_harmony_target, slots_per_bar,
};
use koji::composition::known_harmonic_rewrites::{REWRITE_COUNT, rewrite_meta};
use koji::composition::known_harmonic_skeletons::{
    known_skeleton, skeleton_meta, skeleton_slot_at, skeleton_slot_count,
};

fn sum_beats(skeleton_id: u16) -> u16 {
    let count = skeleton_slot_count(skeleton_id);
    let mut total: u16 = 0;
    let mut i: u16 = 0;
    loop {
        if i >= count {
            break;
        }
        let s = skeleton_slot_at(skeleton_id, i).unwrap();
        total += s.beats.into();
        i += 1;
    };
    total
}

#[test]
fn test_turnaround_axiom_skeleton() {
    assert(skeleton_slot_count(SKELETON_TURNAROUND_AXIOM_3) == 3, 'turnaround slots');
    let meta = skeleton_meta(SKELETON_TURNAROUND_AXIOM_3).unwrap();
    assert(meta.total_beats == 12, 'turnaround beats');
    let s0 = skeleton_slot_at(SKELETON_TURNAROUND_AXIOM_3, 0).unwrap();
    assert(s0.beats == 4 && s0.root_pc == 0 && s0.quality_id == 0, 'C maj bar');
    let pcs = quality_pcs(0, 0);
    assert(contains_u8(pcs, 0) && contains_u8(pcs, 4) && contains_u8(pcs, 7), 'C triad');
}

#[test]
fn test_blues_12_skeleton() {
    assert(skeleton_slot_count(SKELETON_BLUES_12) == 12, 'blues slots');
    assert(sum_beats(SKELETON_BLUES_12) == 48, 'blues beats');
    let s1 = skeleton_slot_at(SKELETON_BLUES_12, 1).unwrap();
    assert(s1.root_pc == 5, 'bar 2 F');
    let s3 = skeleton_slot_at(SKELETON_BLUES_12, 3).unwrap();
    assert(s3.root_pc == 0 && s3.quality_id == 1, 'bar 4 C7');
    let dom = quality_pcs(0, 1);
    assert(contains_u8(dom, 10), 'dom has b7');
}

#[test]
fn test_rhythm_changes_32_skeleton() {
    assert(skeleton_slot_count(SKELETON_RHYTHM_CHANGES_32) == 8, 'rc slots');
    let meta = skeleton_meta(SKELETON_RHYTHM_CHANGES_32).unwrap();
    assert(meta.total_beats == 32, 'rc beats');
    let g7 = skeleton_slot_at(SKELETON_RHYTHM_CHANGES_32, 6).unwrap();
    assert(g7.root_pc == 7 && g7.quality_id == 1, 'G7 bar');
}

#[test]
fn test_two_five_one_skeleton() {
    let sk = known_skeleton(SKELETON_TWO_FIVE_ONE_1).unwrap();
    assert(sk.len() == 3, '251 len');
    let ii = *sk.at(0);
    assert(ii.root_pc == 2 && ii.quality_id == 2 && ii.beats == 2, 'Dmin7');
    let v = *sk.at(1);
    assert(v.root_pc == 7 && v.quality_id == 1 && v.beats == 2, 'G7');
    let i = *sk.at(2);
    assert(i.root_pc == 0 && i.quality_id == 5 && i.beats == 4, 'Cmaj7');
    let maj7 = quality_pcs(0, 5);
    assert(pcs_sets_equal(maj7, array![0_u8, 4, 7, 11].span()), 'maj7 pcs');
}

#[test]
fn test_invalid_skeleton_id() {
    assert(skeleton_slot_count(99) == 0, 'bad count');
    assert(skeleton_slot_at(99, 0).is_none(), 'bad slot');
    assert(known_skeleton(99).is_none(), 'bad skeleton');
    assert(skeleton_meta(99).is_none(), 'bad meta');
}

#[test]
fn test_metric_grid_helpers() {
    assert(slot_beats(skeleton_slot_at(SKELETON_TURNAROUND_AXIOM_3, 0).unwrap()) == 4, 'slot beats');
    assert(slots_per_bar(4) == 1, 'one bar');
    assert(slots_per_bar(2) == 0, 'half bar not whole bars');
    assert(HARMONIC_BEATS_PER_BAR == 4, '4/4');
}

#[test]
fn test_slot_to_harmony_target() {
    let slot = skeleton_slot_at(SKELETON_TWO_FIVE_ONE_1, 2).unwrap();
    let ht = slot_to_harmony_target(slot);
    assert(ht.pcs.len() == 4, 'target len');
    assert(contains_u8(ht.pcs.span(), 11), 'maj7 B');
}

#[test]
fn test_rewrite_preserves_beats() {
    let sk = known_skeleton(SKELETON_TURNAROUND_AXIOM_3).unwrap();
    let mut slots: Array<HarmonicSlot> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= sk.len() {
            break;
        }
        slots.append(*sk.at(i));
        i += 1;
    };
    let before = sum_slot_beats(slots.span());
    let cands = rewrites_applicable_at(slots.span(), 0);
    if cands.len() > 0 {
        let after = apply_rewrite(slots.span(), *cands.at(0), 0);
        assert(rewrite_preserves_beats(slots.span(), after.span()), 'rewrite ok');
        assert(sum_slot_beats(after.span()) == before, 'same beats');
    }
}

#[test]
fn test_tritone_sub_rule_meta() {
    let m = rewrite_meta(3).unwrap();
    assert(m.rule_kind == 4, 'tritone kind');
    let sk = known_skeleton(SKELETON_BLUES_12).unwrap();
    let s3 = *sk.at(3);
    assert(s3.quality_id == 1, 'C7 bar');
    let out = apply_rewrite(sk, 3, 3);
    assert(out.len() == sk.len(), 'same slot count');
    assert(*out.at(3).root_pc == 6, 'F#7');
}

#[test]
fn test_continuations_cmin_f7_prefix() {
    let cands = continuations_for_prefix(2, 1, 5);
    assert(cands.len() > 0, 'has cands');
    let e = pick_continuation(0, cands, 0);
    let s = surprise_tier_for_row(e);
    assert(s < 50, 'E tier');
    let s_row = pick_continuation(0, cands, 255);
    let s_tier = surprise_tier_for_row(s_row);
    assert(s_tier >= s, 'S not lower than E');
}

#[test]
fn test_harmonic_walk_deterministic() {
    let seed: felt252 = 424242;
    let plan = harmonic_walk_plan_from_seed(seed);
    let t1 = harmonic_walk_to_timeline(@plan, seed);
    let t2 = harmonic_walk_to_timeline(@plan, seed);
    assert(t1.targets.len() == t2.targets.len(), 'same len');
    assert(t1.targets.len() > 0, 'nonempty');
}

#[test]
fn test_timeline_from_harmonic_walk_wrapper() {
    let seed: felt252 = 99;
    let plan = harmonic_walk_plan_default();
    let tl = timeline_from_harmonic_walk(seed, plan);
    assert(tl.targets.len() == 3, 'turnaround slots');
}

#[test]
fn test_expand_with_rewrites_budget() {
    let seed: felt252 = 777;
    let plan = HarmonicWalkPlan {
        family_id: 1,
        skeleton_id: SKELETON_TURNAROUND_AXIOM_3,
        rewrite_budget: 3,
        max_rewrites_per_section: 4,
        continuation_depth: 0,
        surprise_bias: 0,
    };
    let slots = expand_skeleton_with_rewrites(@plan, seed);
    assert(sum_slot_beats(slots.span()) == 12, 'beats preserved');
}

#[test]
fn test_surprise_script_tier() {
    assert(surprise_script_tier(0, false) == 0, 'E');
    assert(surprise_script_tier(1, true) == 255, 'S');
}

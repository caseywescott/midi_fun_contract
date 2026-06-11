use core::array::ArrayTrait;
use koji::composition::barry_harris::BarryRule;
use koji::composition::barry_labyrinth::{
    barry_labyrinth_plan_from_seed, BarryLimitation, BarryTextureMode, VoiceMotionPolicy,
};
use koji::composition::barry_limitations::{
    all_v2_rules, allowed_v2_rules_for_limitation, apply_limitation_to_plan, is_elevator_rule,
    is_family_rotation_rule, limitation_allows_rule, limitation_forces_resolution,
    limitation_allows_line_cell, BarryV2Rule,
};
use koji::composition::barry_labyrinth::BarryLineCell;

#[test]
fn test_only_elevators_never_family_rotation() {
    let base = all_v2_rules();
    let allowed = allowed_v2_rules_for_limitation(BarryLimitation::OnlyElevators, base.span());
    assert(allowed.len() > 0, 'nonempty');
    let mut i: usize = 0;
    loop {
        if i >= allowed.len() {
            break;
        }
        let rule = *allowed.at(i);
        assert(is_elevator_rule(rule) || rule == BarryV2Rule::V1RuleResolveToStable, 'elevator');
        assert(!is_family_rotation_rule(rule), 'no family rot');
        i += 1;
    };
}

#[test]
fn test_no_family_rotation_filters() {
    let base = all_v2_rules();
    let allowed = allowed_v2_rules_for_limitation(BarryLimitation::NoFamilyRotation, base.span());
    assert(allowed.len() > 0, 'nonempty');
    let mut i: usize = 0;
    loop {
        if i >= allowed.len() {
            break;
        }
        assert(!is_family_rotation_rule(*allowed.at(i)), 'no rot');
        assert(*allowed.at(i) != BarryV2Rule::BarryTurnaroundStep, 'no turnaround');
        i += 1;
    };
}

#[test]
fn test_limitation_never_empty() {
    let base = all_v2_rules();
    let mut lim: u32 = 0;
    loop {
        if lim >= 10 {
            break;
        }
        let limitation = match lim {
            0 => BarryLimitation::None,
            1 => BarryLimitation::OnlyElevators,
            2 => BarryLimitation::OnlyContraryMotion,
            3 => BarryLimitation::OnlyDiminishedConnectors,
            4 => BarryLimitation::OnlyHalfStepApproaches,
            5 => BarryLimitation::OnlyTwoVoice,
            6 => BarryLimitation::NoLeaps,
            7 => BarryLimitation::NoFamilyRotation,
            8 => BarryLimitation::StrongBeatsOnlyChordTones,
            _ => BarryLimitation::ResolveEveryFourSteps,
        };
        let allowed = allowed_v2_rules_for_limitation(limitation, base.span());
        assert(allowed.len() > 0, 'nonempty set');
        lim += 1;
    };
}

#[test]
fn test_only_two_voice_forces_texture() {
    let seed: felt252 = 0xB200_0000_0000_5555;
    let mut plan = barry_labyrinth_plan_from_seed(seed);
    plan.limitation = BarryLimitation::OnlyTwoVoice;
    let adjusted = apply_limitation_to_plan(plan);
    assert(adjusted.texture_mode == BarryTextureMode::TwoVoiceCounterpoint, 'two voice');
}

#[test]
fn test_only_contrary_motion_forces_policy() {
    let seed: felt252 = 0xB200_0000_0000_6666;
    let mut plan = barry_labyrinth_plan_from_seed(seed);
    plan.limitation = BarryLimitation::OnlyContraryMotion;
    let adjusted = apply_limitation_to_plan(plan);
    assert(
        adjusted.voice_motion_policy == VoiceMotionPolicy::ContraryOuterVoices, 'contrary',
    );
}

#[test]
fn test_resolve_every_four_steps() {
    assert(limitation_forces_resolution(BarryLimitation::ResolveEveryFourSteps, 0, 0), 'beat 0');
    assert(!limitation_forces_resolution(BarryLimitation::ResolveEveryFourSteps, 1, 0), 'beat 1');
    assert(limitation_forces_resolution(BarryLimitation::ResolveEveryFourSteps, 4, 0), 'beat 4');
}

#[test]
fn test_no_leaps_rejects_large_cells() {
    assert(
        limitation_allows_line_cell(BarryLimitation::NoLeaps, BarryLineCell::HalfStepApproachBelow),
        'half step ok',
    );
    assert(
        !limitation_allows_line_cell(BarryLimitation::NoLeaps, BarryLineCell::ScaleRun4), 'run4 bad',
    );
}

#[test]
fn test_limitation_allows_v1_rule() {
    assert(
        limitation_allows_rule(BarryLimitation::OnlyElevators, BarryRule::ResolveToStable), 'resolve',
    );
    assert(
        !limitation_allows_rule(BarryLimitation::OnlyElevators, BarryRule::FamilyRotation),
        'no rot',
    );
}

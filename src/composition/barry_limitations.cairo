//! Barry Harris v2 limitation profiles — hard compositional constraints.
//!
//! See `docs/barry_harris_v2.md` §BH18.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::BarryRule;
use koji::composition::barry_labyrinth::{
    BarryLimitation, BarryLabyrinthPlan, BarryLineCell, BarryLineCellProfile, BarryTextureMode,
    BarryVoicingStyle, VoiceMotionPolicy,
};

#[derive(Copy, Drop, PartialEq)]
pub enum BarryV2Rule {
    V1RuleBarryStay,
    V1RuleScaleStepUp,
    V1RuleScaleStepDown,
    V1RuleDiminishedInterpolation,
    V1RuleHalfStepApproachUp,
    V1RuleHalfStepApproachDown,
    V1RuleFamilyRotation,
    V1RuleInversionShiftUp,
    V1RuleInversionShiftDown,
    V1RuleResolveToStable,
    ElevatorUp,
    ElevatorDown,
    ElevatorBounce,
    BorrowNeighborUp,
    BorrowNeighborDown,
    BorrowDiminishedNeighbor,
    ReturnBorrowedTone,
    BarryTurnaroundStep,
}

pub fn v2_rule_from_v1(rule: BarryRule) -> BarryV2Rule {
    match rule {
        BarryRule::Stay => BarryV2Rule::V1RuleBarryStay,
        BarryRule::ScaleStepUp => BarryV2Rule::V1RuleScaleStepUp,
        BarryRule::ScaleStepDown => BarryV2Rule::V1RuleScaleStepDown,
        BarryRule::DiminishedInterpolation => BarryV2Rule::V1RuleDiminishedInterpolation,
        BarryRule::HalfStepApproachUp => BarryV2Rule::V1RuleHalfStepApproachUp,
        BarryRule::HalfStepApproachDown => BarryV2Rule::V1RuleHalfStepApproachDown,
        BarryRule::FamilyRotation => BarryV2Rule::V1RuleFamilyRotation,
        BarryRule::InversionShiftUp => BarryV2Rule::V1RuleInversionShiftUp,
        BarryRule::InversionShiftDown => BarryV2Rule::V1RuleInversionShiftDown,
        BarryRule::ResolveToStable => BarryV2Rule::V1RuleResolveToStable,
    }
}

pub fn all_v2_rules() -> Array<BarryV2Rule> {
    array![
        BarryV2Rule::V1RuleBarryStay,
        BarryV2Rule::V1RuleScaleStepUp,
        BarryV2Rule::V1RuleScaleStepDown,
        BarryV2Rule::V1RuleDiminishedInterpolation,
        BarryV2Rule::V1RuleHalfStepApproachUp,
        BarryV2Rule::V1RuleHalfStepApproachDown,
        BarryV2Rule::V1RuleFamilyRotation,
        BarryV2Rule::V1RuleInversionShiftUp,
        BarryV2Rule::V1RuleInversionShiftDown,
        BarryV2Rule::V1RuleResolveToStable,
        BarryV2Rule::ElevatorUp,
        BarryV2Rule::ElevatorDown,
        BarryV2Rule::ElevatorBounce,
        BarryV2Rule::BorrowNeighborUp,
        BarryV2Rule::BorrowNeighborDown,
        BarryV2Rule::BorrowDiminishedNeighbor,
        BarryV2Rule::ReturnBorrowedTone,
        BarryV2Rule::BarryTurnaroundStep,
    ]
}

fn limitation_allows_v2_rule(limitation: BarryLimitation, rule: BarryV2Rule) -> bool {
    match limitation {
        BarryLimitation::None => true,
        BarryLimitation::OnlyElevators => match rule {
            BarryV2Rule::ElevatorUp => true,
            BarryV2Rule::ElevatorDown => true,
            BarryV2Rule::ElevatorBounce => true,
            BarryV2Rule::V1RuleResolveToStable => true,
            _ => false,
        },
        BarryLimitation::OnlyContraryMotion => match rule {
            BarryV2Rule::V1RuleBarryStay => true,
            BarryV2Rule::V1RuleResolveToStable => true,
            _ => false,
        },
        BarryLimitation::OnlyDiminishedConnectors => match rule {
            BarryV2Rule::V1RuleDiminishedInterpolation => true,
            BarryV2Rule::V1RuleScaleStepUp => true,
            BarryV2Rule::V1RuleScaleStepDown => true,
            BarryV2Rule::V1RuleResolveToStable => true,
            _ => false,
        },
        BarryLimitation::OnlyHalfStepApproaches => match rule {
            BarryV2Rule::V1RuleHalfStepApproachUp => true,
            BarryV2Rule::V1RuleHalfStepApproachDown => true,
            BarryV2Rule::V1RuleResolveToStable => true,
            _ => false,
        },
        BarryLimitation::OnlyTwoVoice => match rule {
            BarryV2Rule::V1RuleBarryStay => true,
            BarryV2Rule::V1RuleScaleStepUp => true,
            BarryV2Rule::V1RuleScaleStepDown => true,
            BarryV2Rule::V1RuleResolveToStable => true,
            _ => false,
        },
        BarryLimitation::NoLeaps => match rule {
            BarryV2Rule::V1RuleHalfStepApproachUp => true,
            BarryV2Rule::V1RuleHalfStepApproachDown => true,
            BarryV2Rule::V1RuleScaleStepUp => true,
            BarryV2Rule::V1RuleScaleStepDown => true,
            BarryV2Rule::V1RuleResolveToStable => true,
            BarryV2Rule::V1RuleBarryStay => true,
            _ => false,
        },
        BarryLimitation::NoFamilyRotation => match rule {
            BarryV2Rule::V1RuleFamilyRotation => false,
            BarryV2Rule::BarryTurnaroundStep => false,
            _ => true,
        },
        BarryLimitation::StrongBeatsOnlyChordTones => true,
        BarryLimitation::ResolveEveryFourSteps => true,
    }
}

pub fn limitation_allows_rule(limitation: BarryLimitation, rule: BarryRule) -> bool {
    limitation_allows_v2_rule(limitation, v2_rule_from_v1(rule))
}

pub fn allowed_v2_rules_for_limitation(
    limitation: BarryLimitation, base_allowed: Span<BarryV2Rule>,
) -> Array<BarryV2Rule> {
    let mut out: Array<BarryV2Rule> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= base_allowed.len() {
            break;
        }
        let rule = *base_allowed.at(i);
        if limitation_allows_v2_rule(limitation, rule) {
            out.append(rule);
        }
        i += 1;
    };
    if out.len() == 0 {
        out.append(BarryV2Rule::V1RuleResolveToStable);
    }
    out
}

pub fn limitation_forces_resolution(
    limitation: BarryLimitation, beat_phase: u8, borrow_remaining: u8,
) -> bool {
    if borrow_remaining == 0 && limitation == BarryLimitation::ResolveEveryFourSteps {
        return beat_phase % 4 == 0;
    }
    false
}

pub fn borrow_must_resolve(borrow_remaining: u8) -> bool {
    borrow_remaining == 0
}

pub fn apply_limitation_to_plan(plan: BarryLabyrinthPlan) -> BarryLabyrinthPlan {
    match plan.limitation {
        BarryLimitation::OnlyContraryMotion => BarryLabyrinthPlan {
            texture_mode: BarryTextureMode::TwoVoiceCounterpoint,
            voice_motion_policy: VoiceMotionPolicy::ContraryOuterVoices,
            ..plan
        },
        BarryLimitation::OnlyTwoVoice => BarryLabyrinthPlan {
            texture_mode: BarryTextureMode::TwoVoiceCounterpoint,
            voicing_style: BarryVoicingStyle::ClosedPosition,
            ..plan
        },
        BarryLimitation::OnlyElevators => BarryLabyrinthPlan {
            use_elevators: true,
            use_neighbor_borrowing: false,
            use_turnaround: false,
            ..plan
        },
        BarryLimitation::NoLeaps => BarryLabyrinthPlan {
            line_cell_profile: BarryLineCellProfile::SimpleApproaches,
            max_line_cell_len: if plan.max_line_cell_len > 3 { 3 } else { plan.max_line_cell_len },
            ..plan
        },
        BarryLimitation::NoFamilyRotation => BarryLabyrinthPlan {
            use_turnaround: false,
            ..plan
        },
        _ => plan,
    }
}

pub fn limitation_allows_line_cell(limitation: BarryLimitation, cell: BarryLineCell) -> bool {
    if limitation != BarryLimitation::NoLeaps {
        return true;
    }
    match cell {
        BarryLineCell::DirectTarget => true,
        BarryLineCell::HalfStepApproachBelow => true,
        BarryLineCell::HalfStepApproachAbove => true,
        BarryLineCell::EnclosureUpperLower => true,
        BarryLineCell::EnclosureLowerUpper => true,
        BarryLineCell::DiatonicUpperNeighbor => true,
        BarryLineCell::DiatonicLowerNeighbor => true,
        BarryLineCell::ScaleRun3 => true,
        BarryLineCell::ScaleRun4 => false,
        BarryLineCell::DoubleChromaticBelow => true,
        BarryLineCell::DoubleChromaticAbove => true,
        BarryLineCell::DiminishedArpeggio => false,
        BarryLineCell::TurnbackCell => true,
    }
}

pub fn is_elevator_rule(rule: BarryV2Rule) -> bool {
    rule == BarryV2Rule::ElevatorUp
        || rule == BarryV2Rule::ElevatorDown
        || rule == BarryV2Rule::ElevatorBounce
}

pub fn is_family_rotation_rule(rule: BarryV2Rule) -> bool {
    rule == BarryV2Rule::V1RuleFamilyRotation
}

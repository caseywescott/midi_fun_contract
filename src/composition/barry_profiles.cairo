//! Barry Harris rule profiles and LCG rule selection.
//!
//! See `docs/barry_harris_spec.md` §Rule Profiles.

use core::traits::TryInto;
use koji::composition::barry_harris::BarryRule;
use koji::lcg::LCG;
use koji::rng::{LCGRandomSource, RandomSource, bounded};

pub const BARRY_RULE_COUNT: u32 = 10;

#[derive(Copy, Drop, PartialEq)]
pub enum BarryRuleProfile {
    Conservative,
    BebopLine,
    DenseBlockChords,
    DiminishedHeavy,
    MediaLoop,
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

/// Domain-separated LCG for Barry Harris walks (tag bits 52..59 XOR low bits; canon orn uses 51).
pub fn barry_lcg_from_seed(seed: felt252) -> LCG {
    let s: u256 = seed.into();
    let mut state = extract_bits(s, 52, 8) ^ extract_bits(s, 0, 8);
    if state == 0 {
        state = extract_bits(s, 16, 8);
    }
    if state == 0 {
        state = 17;
    }
    LCG { state, multiplier: 5, increment: 3, modulus: 256 }
}

pub fn max_tension_for_profile(profile: BarryRuleProfile) -> u8 {
    match profile {
        BarryRuleProfile::Conservative => 6,
        BarryRuleProfile::BebopLine => 8,
        BarryRuleProfile::DenseBlockChords => 7,
        BarryRuleProfile::DiminishedHeavy => 10,
        BarryRuleProfile::MediaLoop => 5,
    }
}

fn profile_weight(profile: BarryRuleProfile, rule: BarryRule) -> u8 {
    match profile {
        BarryRuleProfile::Conservative => match rule {
            BarryRule::Stay => 20,
            BarryRule::ScaleStepUp => 20,
            BarryRule::ScaleStepDown => 20,
            BarryRule::DiminishedInterpolation => 10,
            BarryRule::HalfStepApproachUp => 10,
            BarryRule::HalfStepApproachDown => 10,
            BarryRule::ResolveToStable => 10,
            _ => 0,
        },
        BarryRuleProfile::BebopLine => match rule {
            BarryRule::ScaleStepUp => 18,
            BarryRule::ScaleStepDown => 18,
            BarryRule::HalfStepApproachUp => 15,
            BarryRule::HalfStepApproachDown => 15,
            BarryRule::DiminishedInterpolation => 12,
            BarryRule::FamilyRotation => 8,
            BarryRule::Stay => 7,
            BarryRule::ResolveToStable => 7,
            _ => 0,
        },
        BarryRuleProfile::DenseBlockChords => match rule {
            BarryRule::Stay => 25,
            BarryRule::InversionShiftUp => 20,
            BarryRule::InversionShiftDown => 20,
            BarryRule::ResolveToStable => 15,
            BarryRule::ScaleStepUp => 10,
            BarryRule::ScaleStepDown => 10,
            _ => 0,
        },
        BarryRuleProfile::DiminishedHeavy => match rule {
            BarryRule::DiminishedInterpolation => 35,
            BarryRule::FamilyRotation => 20,
            BarryRule::InversionShiftUp => 15,
            BarryRule::InversionShiftDown => 15,
            BarryRule::ResolveToStable => 15,
            _ => 0,
        },
        BarryRuleProfile::MediaLoop => match rule {
            BarryRule::Stay => 30,
            BarryRule::ScaleStepUp => 15,
            BarryRule::ScaleStepDown => 15,
            BarryRule::ResolveToStable => 20,
            BarryRule::FamilyRotation => 10,
            BarryRule::DiminishedInterpolation => 10,
            _ => 0,
        },
    }
}

pub fn pick_rule(
    rng: LCG, profile: BarryRuleProfile, allowed: Span<BarryRule>,
) -> (BarryRule, LCG) {
    if allowed.len() == 0 {
        return (BarryRule::Stay, rng);
    }
    let mut total: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= allowed.len() {
            break;
        }
        total += profile_weight(profile, *allowed.at(i)).into();
        i += 1;
    };
    if total == 0 {
        return (*allowed.at(0), rng);
    }
    let (raw, next) = LCGRandomSource::draw(@rng);
    let pick = bounded(raw, total);
    let mut cum: u32 = 0;
    i = 0;
    loop {
        if i >= allowed.len() {
            break;
        }
        let rule = *allowed.at(i);
        cum += profile_weight(profile, rule).into();
        if pick < cum {
            return (rule, next);
        }
        i += 1;
    };
    (*allowed.at(allowed.len() - 1), next)
}

pub fn rule_histogram_skew_diminished(profile: BarryRuleProfile) -> bool {
    profile == BarryRuleProfile::DiminishedHeavy
}

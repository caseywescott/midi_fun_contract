//! Barry Harris v2 — Labyrinth-style formalization layer.
//!
//! See `docs/barry_harris_v2.md`.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    barry_phrase_to_note_events, barry_traits_from_phrase, generate_barry_phrase, BarryPhrase,
    BarryTraits, ChordFamily, HarmonicState,
};
use koji::composition::barry_profiles::{barry_lcg_from_seed, BarryRuleProfile};
use koji::composition::melodic_canon::NoteEvent;
use koji::lcg::LCG;

pub const BARRY_LABYRINTH_V2_PLAN_ID: felt252 = 'barry_labyrinth_v2';
pub const BARRY_LABYRINTH_V2_TAG: u32 = 0xB2;
pub const BARRY_LABYRINTH_MAX_LINE_CELL_LEN: u8 = 8;
pub const BARRY_LABYRINTH_MAX_BORROW_SPAN: u8 = 8;

#[derive(Copy, Drop, PartialEq)]
pub enum BarryTextureMode {
    MonophonicLine,
    TwoVoiceCounterpoint,
    ThreeVoiceShells,
    FourVoiceBlock,
    DropTwoBlock,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BarryLimitation {
    None,
    OnlyElevators,
    OnlyContraryMotion,
    OnlyDiminishedConnectors,
    OnlyHalfStepApproaches,
    OnlyTwoVoice,
    NoLeaps,
    NoFamilyRotation,
    StrongBeatsOnlyChordTones,
    ResolveEveryFourSteps,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BarryLineCellProfile {
    SimpleApproaches,
    EnclosureHeavy,
    DiminishedArpeggioHeavy,
    Scalar,
    MixedBebop,
}

#[derive(Copy, Drop, PartialEq)]
pub enum VoiceMotionPolicy {
    MinimalMotion,
    Parallel,
    ContraryOuterVoices,
    ContraryBassMelody,
    ObliqueTopVoice,
    ObliqueBass,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BarryVoicingStyle {
    ClosedPosition,
    DropTwo,
    DropThree,
    FourWayClose,
    RootlessShell,
    TwoHandBlock,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BarryTurnaroundKind {
    None,
    SixToTwoFive,
    OneSixTwoFive,
    TritoneDominantChain,
    DiminishedPassingTurnaround,
    BackdoorSixDim,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BarryLineCell {
    DirectTarget,
    ScaleRun3,
    ScaleRun4,
    HalfStepApproachBelow,
    HalfStepApproachAbove,
    EnclosureUpperLower,
    EnclosureLowerUpper,
    DiatonicUpperNeighbor,
    DiatonicLowerNeighbor,
    DoubleChromaticBelow,
    DoubleChromaticAbove,
    DiminishedArpeggio,
    TurnbackCell,
}

#[derive(Copy, Drop)]
pub struct BarryLabyrinthPlan {
    pub version_id: felt252,
    pub texture_mode: BarryTextureMode,
    pub limitation: BarryLimitation,
    pub line_cell_profile: BarryLineCellProfile,
    pub voice_motion_policy: VoiceMotionPolicy,
    pub voicing_style: BarryVoicingStyle,
    pub turnaround_kind: BarryTurnaroundKind,
    pub use_turnaround: bool,
    pub use_neighbor_borrowing: bool,
    pub use_elevators: bool,
    pub max_borrow_span: u8,
    pub max_line_cell_len: u8,
}

#[derive(Drop)]
pub struct BarryLabyrinthTraits {
    pub base_traits: BarryTraits,
    pub texture_mode: BarryTextureMode,
    pub limitation: BarryLimitation,
}

#[derive(Drop)]
pub struct BarryLabyrinthPhrase {
    pub base_phrase: BarryPhrase,
    pub plan: BarryLabyrinthPlan,
    pub note_events: Array<NoteEvent>,
    pub line_cells: Array<BarryLineCell>,
    pub voice_motion_tags: Array<VoiceMotionPolicy>,
    pub voicing_style_tags: Array<BarryVoicingStyle>,
    pub traits: BarryLabyrinthTraits,
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

pub fn barry_labyrinth_v2_lcg_from_seed(seed: felt252) -> LCG {
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

fn texture_mode_from_bits(bits: u32) -> BarryTextureMode {
    match bits % 5 {
        0 => BarryTextureMode::MonophonicLine,
        1 => BarryTextureMode::TwoVoiceCounterpoint,
        2 => BarryTextureMode::ThreeVoiceShells,
        3 => BarryTextureMode::FourVoiceBlock,
        _ => BarryTextureMode::DropTwoBlock,
    }
}

fn limitation_from_bits(bits: u32) -> BarryLimitation {
    match bits % 10 {
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
    }
}

fn line_cell_profile_from_bits(bits: u32) -> BarryLineCellProfile {
    match bits % 5 {
        0 => BarryLineCellProfile::SimpleApproaches,
        1 => BarryLineCellProfile::EnclosureHeavy,
        2 => BarryLineCellProfile::DiminishedArpeggioHeavy,
        3 => BarryLineCellProfile::Scalar,
        _ => BarryLineCellProfile::MixedBebop,
    }
}

fn voice_motion_policy_from_bits(bits: u32) -> VoiceMotionPolicy {
    match bits % 6 {
        0 => VoiceMotionPolicy::MinimalMotion,
        1 => VoiceMotionPolicy::Parallel,
        2 => VoiceMotionPolicy::ContraryOuterVoices,
        3 => VoiceMotionPolicy::ContraryBassMelody,
        4 => VoiceMotionPolicy::ObliqueTopVoice,
        _ => VoiceMotionPolicy::ObliqueBass,
    }
}

fn voicing_style_from_bits(bits: u32) -> BarryVoicingStyle {
    match bits % 6 {
        0 => BarryVoicingStyle::ClosedPosition,
        1 => BarryVoicingStyle::DropTwo,
        2 => BarryVoicingStyle::DropThree,
        3 => BarryVoicingStyle::FourWayClose,
        4 => BarryVoicingStyle::RootlessShell,
        _ => BarryVoicingStyle::TwoHandBlock,
    }
}

fn turnaround_kind_from_bits(bits: u32) -> BarryTurnaroundKind {
    match bits % 6 {
        0 => BarryTurnaroundKind::None,
        1 => BarryTurnaroundKind::SixToTwoFive,
        2 => BarryTurnaroundKind::OneSixTwoFive,
        3 => BarryTurnaroundKind::TritoneDominantChain,
        4 => BarryTurnaroundKind::DiminishedPassingTurnaround,
        _ => BarryTurnaroundKind::BackdoorSixDim,
    }
}

pub fn barry_labyrinth_plan_from_seed(seed: felt252) -> BarryLabyrinthPlan {
    let s: u256 = seed.into();
    let max_borrow = extract_bits(s, 35, 5).try_into().unwrap();
    let max_borrow_span = if max_borrow == 0 { 2 } else if max_borrow > BARRY_LABYRINTH_MAX_BORROW_SPAN {
        BARRY_LABYRINTH_MAX_BORROW_SPAN
    } else {
        max_borrow
    };
    let max_line_len = extract_bits(s, 40, 5).try_into().unwrap();
    let max_line_cell_len = if max_line_len == 0 {
        4
    } else if max_line_len > BARRY_LABYRINTH_MAX_LINE_CELL_LEN {
        BARRY_LABYRINTH_MAX_LINE_CELL_LEN
    } else {
        max_line_len
    };
    BarryLabyrinthPlan {
        version_id: BARRY_LABYRINTH_V2_PLAN_ID,
        texture_mode: texture_mode_from_bits(extract_bits(s, 8, 4)),
        limitation: limitation_from_bits(extract_bits(s, 12, 4)),
        line_cell_profile: line_cell_profile_from_bits(extract_bits(s, 16, 4)),
        voice_motion_policy: voice_motion_policy_from_bits(extract_bits(s, 20, 4)),
        voicing_style: voicing_style_from_bits(extract_bits(s, 24, 4)),
        turnaround_kind: turnaround_kind_from_bits(extract_bits(s, 28, 4)),
        use_turnaround: extract_bits(s, 32, 1) == 1,
        use_neighbor_borrowing: extract_bits(s, 33, 1) == 1,
        use_elevators: extract_bits(s, 34, 1) == 1,
        max_borrow_span,
        max_line_cell_len,
    }
}

pub fn generate_barry_labyrinth_phrase(
    seed: felt252,
    tonic_pc: u8,
    family: ChordFamily,
    length_steps: u32,
    profile: BarryRuleProfile,
    register_min: i16,
    register_max: i16,
) -> BarryLabyrinthPhrase {
    let plan = barry_labyrinth_plan_from_seed(seed);
    let base_phrase = generate_barry_phrase(
        seed, tonic_pc, family, length_steps, profile, register_min, register_max,
    );
    let note_events = barry_phrase_to_note_events(@base_phrase, 4);
    let base_traits = barry_traits_from_phrase(@base_phrase, profile);
    let traits = BarryLabyrinthTraits {
        base_traits,
        texture_mode: plan.texture_mode,
        limitation: plan.limitation,
    };
    BarryLabyrinthPhrase {
        base_phrase,
        plan,
        note_events,
        line_cells: ArrayTrait::new(),
        voice_motion_tags: ArrayTrait::new(),
        voicing_style_tags: ArrayTrait::new(),
        traits,
    }
}

pub fn labyrinth_plan_uses_monophonic(plan: @BarryLabyrinthPlan) -> bool {
    *plan.texture_mode == BarryTextureMode::MonophonicLine
}

pub fn labyrinth_plan_uses_polyphonic(plan: @BarryLabyrinthPlan) -> bool {
    !labyrinth_plan_uses_monophonic(plan)
}

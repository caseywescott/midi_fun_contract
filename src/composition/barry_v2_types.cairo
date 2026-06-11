//! Shared Barry Harris v2 type definitions.

pub const BARRY_LABYRINTH_V2_PLAN_ID: felt252 = 'barry_labyrinth_v2';

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

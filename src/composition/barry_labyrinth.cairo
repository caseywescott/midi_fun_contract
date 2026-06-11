//! Barry Harris v2 — Labyrinth-style formalization layer.
//!
//! See `docs/barry_harris_v2.md`.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{
    barry_traits_from_phrase, generate_barry_phrase, stable_chord_tones, BarryPhrase, BarryTraits,
    ChordFamily, HarmonicState,
};
use koji::composition::barry_line_cells::{pick_line_cell, realize_line_cell};
use koji::composition::barry_limitations::apply_limitation_to_plan;
use koji::composition::barry_profiles::BarryRuleProfile;
use koji::composition::barry_rules::beat_role;
use koji::composition::barry_voicing_styles::realize_voicing_style;
use koji::composition::barry_voice_motion::voicelead_with_policy;
use koji::composition::melodic_canon::NoteEvent;
use koji::lcg::LCG;
use koji::rng::{LCGRandomSource, bounded};

pub const BARRY_LABYRINTH_V2_TAG: u32 = 0xB2;
pub const BARRY_LABYRINTH_MAX_LINE_CELL_LEN: u8 = 8;
pub const BARRY_LABYRINTH_MAX_BORROW_SPAN: u8 = 8;

pub use koji::composition::barry_v2_types::{
    BarryLimitation, BarryLineCell, BarryLineCellProfile, BarryLabyrinthPlan, BarryTextureMode,
    BarryTurnaroundKind, BarryVoicingStyle, VoiceMotionPolicy, BARRY_LABYRINTH_V2_PLAN_ID,
};

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
    let plan = BarryLabyrinthPlan {
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
    };
    apply_limitation_to_plan(plan)
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
    let (note_events, line_cells, voice_motion_tags, voicing_style_tags) =
        realize_labyrinth_surface(
        @base_phrase, @plan, seed, register_min, register_max,
    );
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
        line_cells,
        voice_motion_tags,
        voicing_style_tags,
        traits,
    }
}

fn realize_labyrinth_surface(
    phrase: @BarryPhrase,
    plan: @BarryLabyrinthPlan,
    seed: felt252,
    register_min: i16,
    register_max: i16,
) -> (
    Array<NoteEvent>, Array<BarryLineCell>, Array<VoiceMotionPolicy>, Array<BarryVoicingStyle>,
) {
    if *plan.texture_mode == BarryTextureMode::MonophonicLine {
        realize_monophonic_surface(phrase, plan, seed, register_min, register_max)
    } else {
        realize_polyphonic_surface(phrase, plan, seed, register_min, register_max)
    }
}

fn realize_monophonic_surface(
    phrase: @BarryPhrase,
    plan: @BarryLabyrinthPlan,
    seed: felt252,
    register_min: i16,
    register_max: i16,
) -> (
    Array<NoteEvent>, Array<BarryLineCell>, Array<VoiceMotionPolicy>, Array<BarryVoicingStyle>,
) {
    let mut note_events: Array<NoteEvent> = ArrayTrait::new();
    let mut line_cells: Array<BarryLineCell> = ArrayTrait::new();
    let mut voice_motion_tags: Array<VoiceMotionPolicy> = ArrayTrait::new();
    let mut voicing_style_tags: Array<BarryVoicingStyle> = ArrayTrait::new();
    let mut rng = barry_labyrinth_v2_lcg_from_seed(seed);
    let mut prev_mono: i16 = register_min + 12;
    let mut i: usize = 0;
    loop {
        if i >= phrase.states.len() {
            break;
        }
        let hs = clone_harmonic_state(phrase.states.at(i));
        let role = beat_role(hs.beat_phase);
        let (raw, nr) = LCGRandomSource::draw(@rng);
        rng = nr;
        let target_pc = melody_target_for_step(phrase, i, @hs, raw);
        let (cell, nr2) = pick_line_cell(rng, *plan.line_cell_profile, role, *plan.max_line_cell_len);
        rng = nr2;
        line_cells.append(cell);
        voice_motion_tags.append(*plan.voice_motion_policy);
        voicing_style_tags.append(*plan.voicing_style);
        let path = realize_line_cell(cell, target_pc, hs, 1);
        append_mono_path(
            ref note_events, path.span(), i, prev_mono, register_min, register_max, raw,
        );
        if path.len() > 0 {
            let last_idx = path.len() - 1;
            let last_pc = *path.at(last_idx);
            prev_mono = nearest_keynum(last_pc, prev_mono, register_min, register_max, raw);
        }
        i += 1;
    };
    (note_events, line_cells, voice_motion_tags, voicing_style_tags)
}

fn append_mono_path(
    ref note_events: Array<NoteEvent>,
    path: Span<u8>,
    step: usize,
    prev_mono: i16,
    register_min: i16,
    register_max: i16,
    raw: u32,
) {
    let time: u32 = step.try_into().unwrap() * 4;
    let mut prev = prev_mono;
    let mut j: usize = 0;
    loop {
        if j >= path.len() {
            break;
        }
        let pc = *path.at(j);
        prev = nearest_keynum(pc, prev, register_min, register_max, raw + j.try_into().unwrap());
        note_events.append(
            NoteEvent {
                time: time + j.try_into().unwrap(),
                duration: 1,
                pitch: prev.try_into().unwrap(),
                velocity: 80,
                voice_id: 0,
            },
        );
        j += 1;
    };
}

fn realize_polyphonic_surface(
    phrase: @BarryPhrase,
    plan: @BarryLabyrinthPlan,
    seed: felt252,
    register_min: i16,
    register_max: i16,
) -> (
    Array<NoteEvent>, Array<BarryLineCell>, Array<VoiceMotionPolicy>, Array<BarryVoicingStyle>,
) {
    let mut note_events: Array<NoteEvent> = ArrayTrait::new();
    let mut line_cells: Array<BarryLineCell> = ArrayTrait::new();
    let mut voice_motion_tags: Array<VoiceMotionPolicy> = ArrayTrait::new();
    let mut voicing_style_tags: Array<BarryVoicingStyle> = ArrayTrait::new();
    let mut rng = barry_labyrinth_v2_lcg_from_seed(seed);
    let mut prev_voicing: Array<i16> = ArrayTrait::new();
    let style = labyrinth_voicing_style_for_mode(*plan.texture_mode, *plan.voicing_style);
    let mut i: usize = 0;
    loop {
        if i >= phrase.states.len() {
            break;
        }
        let hs = clone_harmonic_state(phrase.states.at(i));
        let (raw, nr) = LCGRandomSource::draw(@rng);
        rng = nr;
        let target_pc = melody_target_for_step(phrase, i, @hs, raw);
        let voiced = realize_polyphonic_step(
            target_pc, prev_voicing.span(), register_min, register_max, plan, style, raw,
        );
        voice_motion_tags.append(*plan.voice_motion_policy);
        voicing_style_tags.append(style);
        line_cells.append(BarryLineCell::DirectTarget);
        append_voiced_notes(ref note_events, voiced.span(), i);
        prev_voicing = clone_i16(voiced.span());
        i += 1;
    };
    (note_events, line_cells, voice_motion_tags, voicing_style_tags)
}

fn realize_polyphonic_step(
    target_pc: u8,
    prev_voicing: Span<i16>,
    register_min: i16,
    register_max: i16,
    plan: @BarryLabyrinthPlan,
    style: BarryVoicingStyle,
    raw: u32,
) -> Array<i16> {
    let voice_count = texture_voice_count(*plan.texture_mode);
    let mut pcs: Array<u8> = ArrayTrait::new();
    let mut vi: u32 = 0;
    loop {
        if vi >= voice_count {
            break;
        }
        pcs.append(target_pc);
        vi += 1;
    };
    realize_voicing_style(
        pcs.span(), prev_voicing, register_min, register_max, style, *plan.voice_motion_policy, raw,
    )
}

fn append_voiced_notes(ref note_events: Array<NoteEvent>, voiced: Span<i16>, step: usize) {
    let time: u32 = step.try_into().unwrap() * 4;
    let grid: u32 = 4;
    let mut v: usize = 0;
    loop {
        if v >= voiced.len() {
            break;
        }
        let kn = *voiced.at(v);
        let pitch: u8 = if kn >= 0 {
            kn.try_into().unwrap()
        } else {
            0
        };
        note_events.append(
            NoteEvent { time, duration: grid, pitch, velocity: 80, voice_id: v.try_into().unwrap() },
        );
        v += 1;
    };
}

fn melody_target_for_step(phrase: @BarryPhrase, step: usize, hs: @HarmonicState, raw: u32) -> u8 {
    if step < phrase.melody_constraints.len() {
        let constraints = phrase.melody_constraints.at(step);
        if constraints.len() > 0 {
            let pick = bounded(raw, constraints.len().try_into().unwrap()).try_into().unwrap();
            return *constraints.at(pick);
        }
    }
    let stable = stable_chord_tones(hs);
    if stable.len() > 0 {
        *stable.at(0)
    } else {
        *hs.tonic_pc
    }
}

fn texture_voice_count(mode: BarryTextureMode) -> u32 {
    match mode {
        BarryTextureMode::MonophonicLine => 1,
        BarryTextureMode::TwoVoiceCounterpoint => 2,
        BarryTextureMode::ThreeVoiceShells => 3,
        BarryTextureMode::FourVoiceBlock | BarryTextureMode::DropTwoBlock => 4,
    }
}

fn labyrinth_voicing_style_for_mode(
    mode: BarryTextureMode, fallback: BarryVoicingStyle,
) -> BarryVoicingStyle {
    match mode {
        BarryTextureMode::DropTwoBlock => BarryVoicingStyle::DropTwo,
        BarryTextureMode::ThreeVoiceShells => BarryVoicingStyle::RootlessShell,
        BarryTextureMode::FourVoiceBlock => BarryVoicingStyle::FourWayClose,
        _ => fallback,
    }
}

fn nearest_keynum(
    pc: u8, prev: i16, register_min: i16, register_max: i16, tie_break: u32,
) -> i16 {
    let out = voicelead_with_policy(
        array![prev].span(), array![pc].span(), register_min, register_max,
        VoiceMotionPolicy::MinimalMotion, tie_break,
    );
    *out.at(0)
}

fn clone_i16(src: Span<i16>) -> Array<i16> {
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= src.len() {
            break;
        }
        out.append(*src.at(i));
        i += 1;
    };
    out
}

fn clone_harmonic_state(state: @HarmonicState) -> HarmonicState {
    let mut pcs: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= state.active_pcs.len() {
            break;
        }
        pcs.append(*state.active_pcs.at(i));
        i += 1;
    };
    HarmonicState {
        tonic_pc: *state.tonic_pc,
        family: *state.family,
        inversion: *state.inversion,
        beat_phase: *state.beat_phase,
        tension_level: *state.tension_level,
        active_pcs: pcs,
        register_hint: *state.register_hint,
        previous_state_hash: *state.previous_state_hash,
    }
}

pub fn motif_from_barry_labyrinth_phrase(
    phrase: BarryLabyrinthPhrase,
    seed: felt252,
    register_min: i16,
    register_max: i16,
) -> Array<NoteEvent> {
    if phrase.note_events.len() > 0 {
        return phrase.note_events;
    }
    let regen = generate_barry_labyrinth_phrase(
        seed,
        phrase.traits.base_traits.tonic_pc,
        phrase.traits.base_traits.family,
        phrase.traits.base_traits.step_count,
        phrase.traits.base_traits.profile,
        register_min,
        register_max,
    );
    regen.note_events
}

pub fn labyrinth_plan_uses_monophonic(plan: @BarryLabyrinthPlan) -> bool {
    *plan.texture_mode == BarryTextureMode::MonophonicLine
}

pub fn labyrinth_plan_uses_polyphonic(plan: @BarryLabyrinthPlan) -> bool {
    !labyrinth_plan_uses_monophonic(plan)
}

//! Linear two-voice counterpoint: Parsons contour + greedy scored selection.
//!
//! Forward-only: each counter note is chosen from local candidates and committed.
//! No backtracking or retroactive fixes.
//!
//! Mode handling supports a single fixed mode/world or a per-note timeline aligned
//! to cantus indices.

use core::array::ArrayTrait;
use core::traits::{Into, TryInto};
use koji::composition::known_symmetric_worlds::registry_entry;
use koji::composition::symmetry_engine::{has_pitch, quantize_pitch_to_world, transpose_mask};
use koji::midi::modes::mode_steps;
use koji::midi::pitch::{keynum_to_pc, modal_transposition, PitchClassTrait};
use koji::midi::types::{Direction, Modes, PitchClass};
use koji::rng::bounded;

// ──────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────

/// Melodic contour symbol (Parsons code: u / d / r).
#[derive(Copy, Drop, Serde, PartialEq)]
pub enum Contour {
    Up: (),
    Down: (),
    Repeat: (),
}

/// Simultaneous motion between cantus and counter.
#[derive(Copy, Drop, Serde, PartialEq)]
pub enum MotionKind {
    Parallel: (),
    Contrary: (),
    Oblique: (),
}

#[derive(Copy, Drop, Serde)]
pub struct MotionBias {
    pub parallel: u32,
    pub contrary: u32,
    pub oblique: u32,
}

/// Single mode/world for the entire cantus (previous default behaviour).
#[derive(Copy, Drop, Serde)]
pub struct FixedMode {
    pub mode: Modes,
    pub world_mask: u16,
}

/// Per-note mode schedule aligned to cantus note indices.
///
/// `mode_ids.len()` must equal cantus length when used in generation.
/// `world_ids`, `transpositions`, `tonic_notes`, and `tonic_octaves` may be empty
/// (fallback to params) or shorter than cantus (last entry is held).
#[derive(Drop, Serde)]
pub struct ModeTimeline {
    pub mode_ids: Array<u8>,
    pub world_ids: Array<u16>,
    pub transpositions: Array<u8>,
    pub tonic_notes: Array<u8>,
    pub tonic_octaves: Array<u8>,
    /// When non-empty, per-index Lydian/world bitmasks for [`quantize_pitch_to_world`].
    /// Overrides registry lookup via `world_ids`.
    pub pitch_world_masks: Array<u16>,
}

/// Keep counter voice above or below the cantus at each index.
#[derive(Copy, Drop, Serde, PartialEq)]
pub enum VoicePlacement {
    AboveCantus: (),
    BelowCantus: (),
    Free: (),
}

#[derive(Drop, Serde)]
pub enum ModeSpec {
    Fixed: FixedMode,
    Timeline: ModeTimeline,
}

#[derive(Copy, Drop)]
pub struct ResolvedMode {
    pub mode: Modes,
    pub world_mask: u16,
}

#[derive(Drop)]
pub struct CounterpointParams {
    pub seed: felt252,
    pub tonic: PitchClass,
    pub mode_spec: ModeSpec,
    pub register_lo: u8,
    pub register_hi: u8,
    pub max_melodic_leap: u8,
    pub motion_bias: MotionBias,
    pub voice_placement: VoicePlacement,
    pub forbid_parallel_perfects: bool,
    pub forbid_similar_perfects: bool,
    /// When true, reject vertical perfect fifths so the pair remains invertible at the octave.
    pub require_invertible_at_octave: bool,
}

#[derive(Drop, Serde)]
pub struct CounterpointResult {
    pub cantus: Array<u8>,
    pub counter: Array<u8>,
    pub cantus_contour: Array<Contour>,
    pub counter_contour: Array<Contour>,
    pub motion_trace: Array<MotionKind>,
    pub contrary_count: u32,
    pub parallel_count: u32,
    pub oblique_count: u32,
}

const GOLDEN: u256 = 0x9E3779B9;
const MAX_MODAL_STEPS: u8 = 4;
const BOUNDARY_OBLIQUE_BONUS: u32 = 15;
const CADENCE_BONUS_OCTAVE: u32 = 50;
const CADENCE_BONUS_FIFTH: u32 = 40;
const CADENCE_BONUS_THIRD: u32 = 35;

/// Sentinel pitch for rests on the tile grid (no sounding note at this index).
pub const REST_PITCH: u8 = 255;

pub fn is_rest_pitch(p: u8) -> bool {
    p == REST_PITCH
}

// ──────────────────────────────────────────────────────────
// Mode ID registry (stable u8 indices for timelines)
// ──────────────────────────────────────────────────────────

pub fn mode_to_id(mode: Modes) -> u8 {
    match mode {
        Modes::Major(()) => 0,
        Modes::Minor(()) => 1,
        Modes::Lydian(()) => 2,
        Modes::Mixolydian(()) => 3,
        Modes::Dorian(()) => 4,
        Modes::Phrygian(()) => 5,
        Modes::Locrian(()) => 6,
        Modes::Aeolian(()) => 7,
        Modes::HarmonicMinor(()) => 8,
        Modes::NaturalMinor(()) => 9,
        Modes::Chromatic(()) => 10,
        Modes::Pentatonic(()) => 11,
        Modes::MelodicMinor(()) => 12,
        Modes::DorianFlat2(()) => 13,
        Modes::LydianAugmented(()) => 14,
        Modes::LydianDominant(()) => 15,
        Modes::MixolydianFlat13(()) => 16,
        Modes::LocrianNatural2(()) => 17,
        Modes::Altered(()) => 18,
        Modes::HarmonicMajor(()) => 19,
        Modes::DorianFlat5(()) => 20,
        Modes::PhrygianFlat4(()) => 21,
        Modes::LydianFlat3(()) => 22,
        Modes::MixolydianFlat2(()) => 23,
        Modes::LydianAugmentedSharp2(()) => 24,
        Modes::LocrianDoubleFlat7(()) => 25,
        Modes::DorianSharp4(()) => 26,
        Modes::LocrianNatural6(()) => 27,
        Modes::WholeTone(()) => 28,
        Modes::HalfWholeDiminished(()) => 29,
        Modes::WholeHalfDiminished(()) => 30,
    }
}

pub fn mode_from_id(id: u8) -> Modes {
    if id == 0 {
        Modes::Major(())
    } else if id == 1 {
        Modes::Minor(())
    } else if id == 2 {
        Modes::Lydian(())
    } else if id == 3 {
        Modes::Mixolydian(())
    } else if id == 4 {
        Modes::Dorian(())
    } else if id == 5 {
        Modes::Phrygian(())
    } else if id == 6 {
        Modes::Locrian(())
    } else if id == 7 {
        Modes::Aeolian(())
    } else if id == 8 {
        Modes::HarmonicMinor(())
    } else if id == 9 {
        Modes::NaturalMinor(())
    } else if id == 10 {
        Modes::Chromatic(())
    } else if id == 11 {
        Modes::Pentatonic(())
    } else if id == 12 {
        Modes::MelodicMinor(())
    } else if id == 13 {
        Modes::DorianFlat2(())
    } else if id == 14 {
        Modes::LydianAugmented(())
    } else if id == 15 {
        Modes::LydianDominant(())
    } else if id == 16 {
        Modes::MixolydianFlat13(())
    } else if id == 17 {
        Modes::LocrianNatural2(())
    } else if id == 18 {
        Modes::Altered(())
    } else if id == 19 {
        Modes::HarmonicMajor(())
    } else if id == 20 {
        Modes::DorianFlat5(())
    } else if id == 21 {
        Modes::PhrygianFlat4(())
    } else if id == 22 {
        Modes::LydianFlat3(())
    } else if id == 23 {
        Modes::MixolydianFlat2(())
    } else if id == 24 {
        Modes::LydianAugmentedSharp2(())
    } else if id == 25 {
        Modes::LocrianDoubleFlat7(())
    } else if id == 26 {
        Modes::DorianSharp4(())
    } else if id == 27 {
        Modes::LocrianNatural6(())
    } else if id == 28 {
        Modes::WholeTone(())
    } else if id == 29 {
        Modes::HalfWholeDiminished(())
    } else if id == 30 {
        Modes::WholeHalfDiminished(())
    } else {
        Modes::Pentatonic(())
    }
}

pub fn fixed_mode_spec(mode: Modes, world_mask: u16) -> ModeSpec {
    ModeSpec::Fixed(FixedMode { mode, world_mask })
}

pub fn build_mode_timeline(
    mode_ids: Array<u8>,
    world_ids: Array<u16>,
    transpositions: Array<u8>,
) -> ModeTimeline {
    ModeTimeline {
        mode_ids,
        world_ids,
        transpositions,
        tonic_notes: array![],
        tonic_octaves: array![],
        pitch_world_masks: array![],
    }
}

pub fn build_mode_timeline_full(
    mode_ids: Array<u8>,
    world_ids: Array<u16>,
    transpositions: Array<u8>,
    tonic_notes: Array<u8>,
    tonic_octaves: Array<u8>,
) -> ModeTimeline {
    build_mode_timeline_with_masks(
        mode_ids, world_ids, transpositions, tonic_notes, tonic_octaves, array![],
    )
}

pub fn build_mode_timeline_with_masks(
    mode_ids: Array<u8>,
    world_ids: Array<u16>,
    transpositions: Array<u8>,
    tonic_notes: Array<u8>,
    tonic_octaves: Array<u8>,
    pitch_world_masks: Array<u16>,
) -> ModeTimeline {
    ModeTimeline {
        mode_ids,
        world_ids,
        transpositions,
        tonic_notes,
        tonic_octaves,
        pitch_world_masks,
    }
}

fn clone_array_u8(src: @Array<u8>) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
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

fn clone_array_u16(src: @Array<u16>) -> Array<u16> {
    let mut out: Array<u16> = ArrayTrait::new();
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

pub fn clone_mode_spec(spec: @ModeSpec) -> ModeSpec {
    match spec {
        ModeSpec::Fixed(fixed) => ModeSpec::Fixed(*fixed),
        ModeSpec::Timeline(timeline) => ModeSpec::Timeline(
            ModeTimeline {
                mode_ids: clone_array_u8(timeline.mode_ids),
                world_ids: clone_array_u16(timeline.world_ids),
                transpositions: clone_array_u8(timeline.transpositions),
                tonic_notes: clone_array_u8(timeline.tonic_notes),
                tonic_octaves: clone_array_u8(timeline.tonic_octaves),
                pitch_world_masks: clone_array_u16(timeline.pitch_world_masks),
            },
        ),
    }
}

// ──────────────────────────────────────────────────────────
// Sparse onset alignment (tile grid ↔ sounding-onset sequence)
// ──────────────────────────────────────────────────────────

/// Build an onset mask from tile pitches: 1 where pitch is not [`REST_PITCH`], else 0.
pub fn onset_mask_from_pitches(tile: Span<u8>) -> Array<u32> {
    let mut mask: Array<u32> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= tile.len() {
            break;
        }
        if is_rest_pitch(*tile.at(i)) {
            mask.append(0);
        } else {
            mask.append(1);
        }
        i += 1;
    };
    mask
}

/// All-onsets mask (every tile index sounds).
pub fn all_onsets_mask(tile_len: u32) -> Array<u32> {
    let mut mask: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= tile_len {
            break;
        }
        mask.append(1);
        i += 1;
    };
    mask
}

pub fn count_onsets(mask: Span<u32>) -> usize {
    let mut c: usize = 0;
    let mut i: usize = 0;
    loop {
        if i >= mask.len() {
            break;
        }
        if *mask.at(i) == 1 {
            c += 1;
        }
        i += 1;
    };
    c
}

/// Extract sounding pitches at tile indices where `mask[i] == 1`.
pub fn extract_onset_pitches(tile: Span<u8>, mask: Span<u32>) -> Array<u8> {
    assert(tile.len() == mask.len(), 'mask len mismatch');
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= mask.len() {
            break;
        }
        if *mask.at(i) == 1 {
            out.append(*tile.at(i));
        }
        i += 1;
    };
    out
}

/// Expand a sparse onset sequence back to tile length; rest tiles get [`REST_PITCH`].
pub fn expand_onset_pitches(sparse: Span<u8>, mask: Span<u32>) -> Array<u8> {
    assert(count_onsets(mask) == sparse.len(), 'sparse len mismatch');
    let mut out: Array<u8> = ArrayTrait::new();
    let mut si: usize = 0;
    let mut ti: usize = 0;
    loop {
        if ti >= mask.len() {
            break;
        }
        if *mask.at(ti) == 1 {
            out.append(*sparse.at(si));
            si += 1;
        } else {
            out.append(REST_PITCH);
        }
        ti += 1;
    };
    out
}

fn filter_u8_for_onsets(src: @Array<u8>, mask: Span<u32>) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= mask.len() {
            break;
        }
        if *mask.at(i) == 1 {
            assert(i < src.len(), 'filter u8 OOB');
            out.append(*src.at(i));
        }
        i += 1;
    };
    out
}

fn filter_u16_for_onsets(src: @Array<u16>, mask: Span<u32>) -> Array<u16> {
    let mut out: Array<u16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= mask.len() {
            break;
        }
        if *mask.at(i) == 1 {
            if src.len() == 0 {
                out.append(0);
            } else {
                let last = src.len() - 1;
                let idx = if i > last {
                    last
                } else {
                    i
                };
                out.append(*src.at(idx));
            }
        }
        i += 1;
    };
    out
}

/// Compress a per-tile mode timeline to one entry per sounding onset.
pub fn filter_timeline_for_onsets(timeline: @ModeTimeline, mask: Span<u32>) -> ModeTimeline {
    ModeTimeline {
        mode_ids: filter_u8_for_onsets(timeline.mode_ids, mask),
        world_ids: filter_u16_for_onsets(timeline.world_ids, mask),
        transpositions: filter_u8_for_onsets(timeline.transpositions, mask),
        tonic_notes: filter_u8_for_onsets(timeline.tonic_notes, mask),
        tonic_octaves: filter_u8_for_onsets(timeline.tonic_octaves, mask),
        pitch_world_masks: filter_u16_for_onsets(timeline.pitch_world_masks, mask),
    }
}

pub fn filter_mode_spec_for_onsets(spec: @ModeSpec, mask: Span<u32>) -> ModeSpec {
    match spec {
        ModeSpec::Fixed(fixed) => ModeSpec::Fixed(*fixed),
        ModeSpec::Timeline(timeline) => ModeSpec::Timeline(
            filter_timeline_for_onsets(timeline, mask),
        ),
    }
}

fn timeline_mode_id(timeline: @ModeTimeline, index: usize) -> u8 {
    assert(index < timeline.mode_ids.len(), 'mode idx OOB');
    *timeline.mode_ids.at(index)
}

fn timeline_world_id(timeline: @ModeTimeline, index: usize) -> u16 {
    if timeline.world_ids.len() == 0 {
        return 0;
    }
    let last = timeline.world_ids.len() - 1;
    let idx = if index > last {
        last
    } else {
        index
    };
    *timeline.world_ids.at(idx)
}

fn timeline_transposition(timeline: @ModeTimeline, index: usize) -> u8 {
    if timeline.transpositions.len() == 0 {
        return 0;
    }
    let last = timeline.transpositions.len() - 1;
    let idx = if index > last {
        last
    } else {
        index
    };
    *timeline.transpositions.at(idx)
}

pub fn world_mask_from_timeline_entry(world_id: u16, transposition: u8) -> u16 {
    if world_id == 0 {
        return 0;
    }
    let entry = registry_entry(world_id);
    transpose_mask(entry.mask, transposition)
}

pub fn world_mask_at_timeline(timeline: @ModeTimeline, index: usize) -> u16 {
    if timeline.pitch_world_masks.len() > 0 {
        let last = timeline.pitch_world_masks.len() - 1;
        let idx = if index > last {
            last
        } else {
            index
        };
        return *timeline.pitch_world_masks.at(idx);
    }
    world_mask_from_timeline_entry(
        timeline_world_id(timeline, index), timeline_transposition(timeline, index),
    )
}

/// Resolve tonic at cantus index; falls back to `default_tonic` when timeline tonics empty.
pub fn tonic_at_timeline(
    timeline: @ModeTimeline, index: usize, default_tonic: PitchClass,
) -> PitchClass {
    if timeline.tonic_notes.len() == 0 {
        return default_tonic;
    }
    let last = timeline.tonic_notes.len() - 1;
    let idx = if index > last {
        last
    } else {
        index
    };
    let note = *timeline.tonic_notes.at(idx);
    let octave = if timeline.tonic_octaves.len() == 0 {
        default_tonic.octave
    } else {
        let olast = timeline.tonic_octaves.len() - 1;
        let oidx = if index > olast {
            olast
        } else {
            index
        };
        *timeline.tonic_octaves.at(oidx)
    };
    PitchClass { note, octave }
}

pub fn tonic_at(params: @CounterpointParams, index: usize) -> PitchClass {
    match params.mode_spec {
        ModeSpec::Fixed(_) => *params.tonic,
        ModeSpec::Timeline(timeline) => tonic_at_timeline(timeline, index, *params.tonic),
    }
}

/// Resolve the active mode and world mask at cantus note index `index`.
pub fn resolve_mode_at(spec: @ModeSpec, index: usize) -> ResolvedMode {
    match spec {
        ModeSpec::Fixed(fixed) => ResolvedMode {
            mode: *fixed.mode, world_mask: *fixed.world_mask,
        },
        ModeSpec::Timeline(timeline) => {
            let mode = mode_from_id(timeline_mode_id(timeline, index));
            let world_mask = world_mask_at_timeline(timeline, index);
            ResolvedMode { mode, world_mask }
        },
    }
}

fn mode_key(spec: @ModeSpec, index: usize) -> (u8, u16) {
    let resolved = resolve_mode_at(spec, index);
    (mode_to_id(resolved.mode), resolved.world_mask)
}

/// True when the harmonic world changes between cantus indices `index - 1` and `index`.
pub fn is_mode_boundary(spec: @ModeSpec, index: usize) -> bool {
    if index == 0 {
        return false;
    }
    let (prev_id, prev_mask) = mode_key(spec, index - 1);
    let (cur_id, cur_mask) = mode_key(spec, index);
    prev_id != cur_id || prev_mask != cur_mask
}

pub fn validate_mode_spec(spec: @ModeSpec, cantus_len: usize) {
    match spec {
        ModeSpec::Fixed(_) => {},
        ModeSpec::Timeline(timeline) => {
            assert(timeline.mode_ids.len() == cantus_len, 'timeline len mismatch');
        },
    }
}

// ──────────────────────────────────────────────────────────
// Hash / helpers
// ──────────────────────────────────────────────────────────

fn step_hash(seed: felt252, index: u32) -> u32 {
    let s: u256 = seed.into();
    let i: u256 = index.into();
    let mixed = s + i * GOLDEN;
    let mask: u256 = 0x100000000;
    (mixed % mask).try_into().unwrap()
}

fn span_to_array(values: Span<u8>) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= values.len() {
            break;
        }
        out.append(*values.at(i));
        i += 1;
    };
    out
}

fn abs_semitone(a: u8, b: u8) -> u8 {
    if a >= b {
        a - b
    } else {
        b - a
    }
}

fn signed_delta(next: u8, prev: u8) -> i16 {
    next.into() - prev.into()
}

fn harmonic_interval_class(counter: u8, cantus: u8) -> u8 {
    abs_semitone(counter, cantus) % 12
}

/// Unisons/octaves (0), minor/major seconds (1–2), and tritone (6) are vetoed as vertical intervals.
pub fn is_forbidden_vertical_interval_class(class: u8) -> bool {
    class == 1 || class == 2 || class == 6
}

pub fn violates_forbidden_interval(a: u8, b: u8) -> bool {
    is_forbidden_vertical_interval_class(harmonic_interval_class(a, b))
}

fn is_perfect_class(class: u8) -> bool {
    class == 0 || class == 5 || class == 7
}

/// True when a vertical perfect fifth would become a dissonant fourth after octave inversion.
pub fn violates_octave_inversion_fifth(a: u8, b: u8) -> bool {
    harmonic_interval_class(a, b) == 7
}

fn violates_invertible_requirement(
    a: u8, b: u8, params: @CounterpointParams,
) -> bool {
    *params.require_invertible_at_octave && violates_octave_inversion_fifth(a, b)
}

fn in_register(keynum: u8, lo: u8, hi: u8) -> bool {
    keynum >= lo && keynum <= hi
}

fn apply_world_quantize(keynum: u8, mask: u16) -> u8 {
    if mask == 0 {
        return keynum;
    }
    let pc = keynum % 12;
    let octave = keynum / 12;
    let q = quantize_pitch_to_world(mask, pc);
    octave * 12 + q
}

fn append_unique(ref cands: Array<u8>, keynum: u8) {
    let mut i: usize = 0;
    loop {
        if i >= cands.len() {
            cands.append(keynum);
            break;
        }
        if *cands.at(i) == keynum {
            break;
        }
        i += 1;
    }
}

fn merge_candidates(ref base: Array<u8>, extra: Span<u8>) {
    let mut i: usize = 0;
    loop {
        if i >= extra.len() {
            break;
        }
        append_unique(ref base, *extra.at(i));
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Contour & motion
// ──────────────────────────────────────────────────────────

pub fn motion_contour(prev: u8, next: u8) -> Contour {
    if next > prev {
        Contour::Up(())
    } else if next < prev {
        Contour::Down(())
    } else {
        Contour::Repeat(())
    }
}

pub fn encode_contour(notes: Span<u8>) -> Array<Contour> {
    let mut out: Array<Contour> = ArrayTrait::new();
    if notes.len() == 0 {
        return out;
    }
    let mut i: usize = 1;
    loop {
        if i >= notes.len() {
            break;
        }
        out.append(motion_contour(*notes.at(i - 1), *notes.at(i)));
        i += 1;
    };
    out
}

pub fn classify_motion(cantus_motion: Contour, counter_motion: Contour) -> MotionKind {
    if counter_motion == Contour::Repeat(()) {
        return MotionKind::Oblique(());
    }
    if cantus_motion == Contour::Repeat(()) {
        return MotionKind::Oblique(());
    }
    if cantus_motion == counter_motion {
        MotionKind::Parallel(())
    } else {
        MotionKind::Contrary(())
    }
}

pub fn would_create_parallel_perfect(
    prev_counter: u8, prev_cantus: u8, cand: u8, cantus_now: u8,
) -> bool {
    let cantus_delta = signed_delta(cantus_now, prev_cantus);
    let counter_delta = signed_delta(cand, prev_counter);
    if cantus_delta == 0 || counter_delta == 0 {
        return false;
    }
    let same_dir = (cantus_delta > 0) == (counter_delta > 0);
    if !same_dir {
        return false;
    }
    let prev_class = harmonic_interval_class(prev_counter, prev_cantus);
    let new_class = harmonic_interval_class(cand, cantus_now);
    prev_class == new_class && is_perfect_class(prev_class)
}

/// Similar/direct motion into a perfect consonance (both voices move same direction).
pub fn would_create_similar_motion_perfect(
    prev_counter: u8, prev_cantus: u8, cand: u8, cantus_now: u8,
) -> bool {
    let cantus_delta = signed_delta(cantus_now, prev_cantus);
    let counter_delta = signed_delta(cand, prev_counter);
    if cantus_delta == 0 || counter_delta == 0 {
        return false;
    }
    if (cantus_delta > 0) != (counter_delta > 0) {
        return false;
    }
    is_perfect_class(harmonic_interval_class(cand, cantus_now))
}

pub fn violates_voice_placement(
    cand: u8, cantus_now: u8, placement: VoicePlacement,
) -> bool {
    match placement {
        VoicePlacement::BelowCantus(()) => cand >= cantus_now,
        VoicePlacement::AboveCantus(()) => cand <= cantus_now,
        VoicePlacement::Free(()) => false,
    }
}

/// True when `cand` crosses an already-placed voice on the same side of the cantus.
///
/// Below voices only compete with other below-cantus lowers; above voices only with
/// above-cantus lowers. This keeps bass layers from being forced under tenor/alto slots.
pub fn violates_lower_voices(
    cand: u8,
    cantus_now: u8,
    lower_at_index: Span<u8>,
    placement: VoicePlacement,
) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= lower_at_index.len() {
            break;
        }
        let lower = *lower_at_index.at(i);
        match placement {
            VoicePlacement::BelowCantus(()) => {
                if lower < cantus_now && cand >= lower {
                    return true;
                }
            },
            VoicePlacement::AboveCantus(()) => {
                if lower > cantus_now && cand <= lower {
                    return true;
                }
            },
            VoicePlacement::Free(()) => {},
        };
        i += 1;
    };
    false
}

fn is_in_pitch_world(keynum: u8, world_mask: u16) -> bool {
    if world_mask == 0 {
        return true;
    }
    has_pitch(world_mask, keynum % 12)
}

fn is_note_in_mode(keynum: u8, tonic: PitchClass, steps: Span<u8>) -> bool {
    keynum_to_pc(keynum).get_scale_degree(tonic, steps) != 0
}

fn safe_modal_transposition(
    pc: PitchClass, tonic: PitchClass, steps: Span<u8>, n: u8, dir: Direction,
) -> u8 {
    if !is_note_in_mode(pc.keynum(), tonic, steps) {
        return pc.keynum();
    }
    modal_transposition(pc, tonic, steps, n, dir)
}

// ──────────────────────────────────────────────────────────
// Scoring
// ──────────────────────────────────────────────────────────

fn motion_score(kind: MotionKind, bias: MotionBias) -> u32 {
    match kind {
        MotionKind::Parallel(()) => bias.parallel,
        MotionKind::Contrary(()) => bias.contrary,
        MotionKind::Oblique(()) => bias.oblique,
    }
}

fn parsons_bonus(cantus_motion: Contour, counter_motion: Contour, bias: MotionBias) -> u32 {
    match (cantus_motion, counter_motion) {
        (Contour::Up(()), Contour::Down(())) => bias.contrary / 2,
        (Contour::Down(()), Contour::Up(())) => bias.contrary / 2,
        (Contour::Up(()), Contour::Up(())) => bias.parallel / 2,
        (Contour::Down(()), Contour::Down(())) => bias.parallel / 2,
        (Contour::Repeat(()), Contour::Repeat(())) => bias.oblique / 2,
        _ => bias.oblique / 4,
    }
}

fn interval_score(counter: u8, cantus: u8) -> u32 {
    let class = harmonic_interval_class(counter, cantus);
    if class == 3 || class == 4 {
        40
    } else if class == 8 || class == 9 {
        35
    } else if class == 7 {
        25
    } else if class == 0 {
        15
    } else if class == 6 {
        5
    } else {
        20
    }
}

fn cadence_bonus(counter: u8, cantus: u8) -> u32 {
    let class = harmonic_interval_class(counter, cantus);
    if class == 0 {
        CADENCE_BONUS_OCTAVE
    } else if class == 7 {
        CADENCE_BONUS_FIFTH
    } else if class == 3 || class == 4 {
        CADENCE_BONUS_THIRD
    } else if class == 8 || class == 9 {
        30
    } else {
        0
    }
}

pub fn count_motion_stats(trace: Span<MotionKind>) -> (u32, u32, u32) {
    let mut contrary: u32 = 0;
    let mut parallel: u32 = 0;
    let mut oblique: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= trace.len() {
            break;
        }
        match *trace.at(i) {
            MotionKind::Contrary(()) => contrary += 1,
            MotionKind::Parallel(()) => parallel += 1,
            MotionKind::Oblique(()) => oblique += 1,
        };
        i += 1;
    };
    (contrary, parallel, oblique)
}

fn melodic_score(prev: u8, cand: u8, max_leap: u8) -> u32 {
    let leap = abs_semitone(prev, cand);
    if leap == 0 {
        25
    } else if leap <= 2 {
        30
    } else if leap <= max_leap {
        10
    } else {
        0
    }
}

pub fn score_counter_candidate(
    cand: u8,
    prev_counter: u8,
    prev_cantus: u8,
    cantus_now: u8,
    cantus_motion: Contour,
    params: @CounterpointParams,
    step_index: usize,
    at_mode_boundary: bool,
    is_final: bool,
    lower_voices_at_index: Span<u8>,
    lower_voices_prev: Span<u8>,
) -> u32 {
    if !in_register(cand, *params.register_lo, *params.register_hi) {
        return 0;
    }
    let resolved = resolve_mode_at(params.mode_spec, step_index);
    let tonic = tonic_at(params, step_index);
    let steps = mode_steps(resolved.mode);
    if !is_note_in_mode(cand, tonic, steps) {
        return 0;
    }
    if !is_in_pitch_world(cand, resolved.world_mask) {
        return 0;
    }
    if abs_semitone(cand, prev_counter) > *params.max_melodic_leap {
        return 0;
    }
    if violates_voice_placement(cand, cantus_now, *params.voice_placement) {
        return 0;
    }
    if violates_lower_voices(
        cand, cantus_now, lower_voices_at_index, *params.voice_placement,
    ) {
        return 0;
    }
    if violates_forbidden_interval(cand, cantus_now) {
        return 0;
    }
    if violates_invertible_requirement(cand, cantus_now, params) {
        return 0;
    }
    if *params.forbid_parallel_perfects
        && would_create_parallel_perfect(prev_counter, prev_cantus, cand, cantus_now) {
        return 0;
    }
    if *params.forbid_similar_perfects
        && would_create_similar_motion_perfect(
            prev_counter, prev_cantus, cand, cantus_now,
        ) {
        return 0;
    }

    let mut j: usize = 0;
    loop {
        if j >= lower_voices_at_index.len() {
            break;
        }
        let ref_now = *lower_voices_at_index.at(j);
        let ref_prev = if j < lower_voices_prev.len() {
            *lower_voices_prev.at(j)
        } else {
            ref_now
        };
        if *params.forbid_parallel_perfects
            && would_create_parallel_perfect(prev_counter, ref_prev, cand, ref_now) {
            return 0;
        }
        if *params.forbid_similar_perfects
            && would_create_similar_motion_perfect(
                prev_counter, ref_prev, cand, ref_now,
            ) {
            return 0;
        }
        if violates_forbidden_interval(cand, ref_now) {
            return 0;
        }
        if violates_invertible_requirement(cand, ref_now, params) {
            return 0;
        }
        j += 1;
    };

    let counter_motion = motion_contour(prev_counter, cand);
    let kind = classify_motion(cantus_motion, counter_motion);
    let mut score = motion_score(kind, *params.motion_bias);
    score += parsons_bonus(cantus_motion, counter_motion, *params.motion_bias);
    score += interval_score(cand, cantus_now);
    score += melodic_score(prev_counter, cand, *params.max_melodic_leap);

    j = 0;
    loop {
        if j >= lower_voices_at_index.len() {
            break;
        }
        score += interval_score(cand, *lower_voices_at_index.at(j)) / 4;
        j += 1;
    };

    if at_mode_boundary && counter_motion == Contour::Repeat(()) {
        score += BOUNDARY_OBLIQUE_BONUS;
    }
    if is_final {
        score += cadence_bonus(cand, cantus_now);
    }

    score
}

// ──────────────────────────────────────────────────────────
// Candidates
// ──────────────────────────────────────────────────────────

fn maybe_append_candidate(
    ref cands: Array<u8>,
    keynum: u8,
    prev: u8,
    lo: u8,
    hi: u8,
    max_leap: u8,
    mask: u16,
) {
    let q = apply_world_quantize(keynum, mask);
    if in_register(q, lo, hi) && abs_semitone(q, prev) <= max_leap {
        append_unique(ref cands, q);
    }
}

fn append_chromatic_neighbors(
    ref cands: Array<u8>,
    prev_counter: u8,
    lo: u8,
    hi: u8,
    max_leap: u8,
    mask: u16,
) {
    let mut delta: u8 = 1;
    loop {
        if delta > 2 {
            break;
        }
        if prev_counter >= delta {
            maybe_append_candidate(
                ref cands,
                prev_counter - delta,
                prev_counter,
                lo,
                hi,
                max_leap,
                mask,
            );
        }
        maybe_append_candidate(
            ref cands,
            prev_counter + delta,
            prev_counter,
            lo,
            hi,
            max_leap,
            mask,
        );
        delta += 1;
    };
}

pub fn collect_candidates(
    prev_counter: u8,
    tonic: PitchClass,
    mode_steps: Span<u8>,
    register_lo: u8,
    register_hi: u8,
    max_leap: u8,
    world_mask: u16,
) -> Array<u8> {
    let mut cands: Array<u8> = ArrayTrait::new();
    let pc = keynum_to_pc(prev_counter);

    maybe_append_candidate(
        ref cands, prev_counter, prev_counter, register_lo, register_hi, max_leap, world_mask,
    );

    let mut steps: u8 = 1;
    loop {
        if steps > MAX_MODAL_STEPS {
            break;
        }
        let up = safe_modal_transposition(pc, tonic, mode_steps, steps, Direction::Up(()));
        let down = safe_modal_transposition(pc, tonic, mode_steps, steps, Direction::Down(()));
        maybe_append_candidate(
            ref cands, up, prev_counter, register_lo, register_hi, max_leap, world_mask,
        );
        maybe_append_candidate(
            ref cands, down, prev_counter, register_lo, register_hi, max_leap, world_mask,
        );
        steps += 1;
    };
    cands
}

fn collect_candidates_for_index(
    prev_counter: u8,
    params: @CounterpointParams,
    index: usize,
    include_previous_mode: bool,
) -> Array<u8> {
    let resolved = resolve_mode_at(params.mode_spec, index);
    let steps = mode_steps(resolved.mode);
    let tonic = tonic_at(params, index);
    let reg_lo = *params.register_lo;
    let reg_hi = *params.register_hi;
    let max_leap = *params.max_melodic_leap;
    let anchor = if in_register(prev_counter, reg_lo, reg_hi) {
        prev_counter
    } else {
        (reg_lo + reg_hi) / 2
    };
    let mut cands = collect_candidates(
        anchor,
        tonic,
        steps,
        reg_lo,
        reg_hi,
        max_leap,
        resolved.world_mask,
    );

    if include_previous_mode {
        let prev_resolved = resolve_mode_at(params.mode_spec, index - 1);
        let prev_steps = mode_steps(prev_resolved.mode);
        let prev_tonic = tonic_at(params, index - 1);
        let extra = collect_candidates(
            anchor,
            prev_tonic,
            prev_steps,
            reg_lo,
            reg_hi,
            max_leap,
            prev_resolved.world_mask,
        );
        merge_candidates(ref cands, extra.span());
        append_chromatic_neighbors(
            ref cands,
            anchor,
            reg_lo,
            reg_hi,
            max_leap,
            resolved.world_mask,
        );
    }

    if cands.len() == 0 {
        append_chromatic_neighbors(
            ref cands,
            anchor,
            reg_lo,
            reg_hi,
            max_leap,
            resolved.world_mask,
        );
    }
    if cands.len() == 0 {
        maybe_append_candidate(
            ref cands,
            anchor,
            anchor,
            reg_lo,
            reg_hi,
            max_leap,
            resolved.world_mask,
        );
    }

    cands
}

fn pick_initial_counter(
    cantus_first: u8, params: @CounterpointParams, lower_at_first: Span<u8>,
) -> u8 {
    let resolved = resolve_mode_at(params.mode_spec, 0);
    let tonic = tonic_at(params, 0);
    let cantus_pc = keynum_to_pc(cantus_first);
    let mut cands: Array<u8> = ArrayTrait::new();

    let offsets: Array<u8> = array![2_u8, 3_u8, 4_u8, 5_u8];
    let mut i: usize = 0;
    loop {
        if i >= offsets.len() {
            break;
        }
        let n = *offsets.at(i);
        let above = safe_modal_transposition(
            cantus_pc, tonic, mode_steps(resolved.mode), n, Direction::Up(()),
        );
        let below = safe_modal_transposition(
            cantus_pc, tonic, mode_steps(resolved.mode), n, Direction::Down(()),
        );
        if *params.voice_placement == VoicePlacement::Free(())
            || *params.voice_placement == VoicePlacement::AboveCantus(()) {
            maybe_append_candidate(
                ref cands,
                above,
                above,
                *params.register_lo,
                *params.register_hi,
                *params.max_melodic_leap,
                resolved.world_mask,
            );
        }
        if *params.voice_placement == VoicePlacement::Free(())
            || *params.voice_placement == VoicePlacement::BelowCantus(()) {
            maybe_append_candidate(
                ref cands,
                below,
                below,
                *params.register_lo,
                *params.register_hi,
                *params.max_melodic_leap,
                resolved.world_mask,
            );
        }
        i += 1;
    };

    if cands.len() == 0 {
        let mut fallback: u8 = cantus_first;
        if *params.voice_placement == VoicePlacement::AboveCantus(()) {
            fallback = if cantus_first < 115 {
                cantus_first + 4
            } else {
                cantus_first
            };
        } else if *params.voice_placement == VoicePlacement::BelowCantus(()) {
            fallback = if cantus_first > 12 {
                cantus_first - 4
            } else {
                cantus_first
            };
        }
        maybe_append_candidate(
            ref cands,
            fallback,
            fallback,
            *params.register_lo,
            *params.register_hi,
            *params.max_melodic_leap,
            resolved.world_mask,
        );
    }

    if cands.len() == 0 {
        append_unique(ref cands, cantus_first);
    }

    assert(cands.len() > 0, 'no initial candidate');

    let mut best: u8 = *cands.at(0);
    let mut best_score: u32 = 0;
    let mut best_tie: u32 = 999999999;
    i = 0;
    loop {
        if i >= cands.len() {
            break;
        }
        let cand = *cands.at(i);
        if violates_voice_placement(cand, cantus_first, *params.voice_placement) {
            i += 1;
            continue;
        }
        if violates_lower_voices(
            cand, cantus_first, lower_at_first, *params.voice_placement,
        ) {
            i += 1;
            continue;
        }
        if violates_forbidden_interval(cand, cantus_first) {
            i += 1;
            continue;
        }
        if violates_invertible_requirement(cand, cantus_first, params) {
            i += 1;
            continue;
        }
        let mut unsafe_lower = false;
        let mut li: usize = 0;
        loop {
            if li >= lower_at_first.len() {
                break;
            }
            if violates_invertible_requirement(cand, *lower_at_first.at(li), params) {
                unsafe_lower = true;
                break;
            }
            li += 1;
        };
        if unsafe_lower {
            i += 1;
            continue;
        }
        let mut score = interval_score(cand, cantus_first);
        score += melodic_score(cantus_first, cand, *params.max_melodic_leap);
        let tie_key = bounded(step_hash(*params.seed, 0) + cand.into(), 1000000);
        if score > best_score || (score == best_score && tie_key < best_tie) {
            best_score = score;
            best = cand;
            best_tie = tie_key;
        }
        i += 1;
    };
    if *params.require_invertible_at_octave {
        assert(best_score > 0, 'no ic initial');
    }
    best
}

fn pick_best_candidate(
    cands: Span<u8>,
    prev_counter: u8,
    prev_cantus: u8,
    cantus_now: u8,
    cantus_motion: Contour,
    params: @CounterpointParams,
    step_index: u32,
    at_mode_boundary: bool,
    is_final: bool,
    lower_voices_at_index: Span<u8>,
    lower_voices_prev: Span<u8>,
) -> u8 {
    assert(cands.len() > 0, 'no candidates');

    let mut best: u8 = *cands.at(0);
    let mut best_score: u32 = 0;
    let mut best_tie: u32 = 999999999;
    let mut i: usize = 0;
    loop {
        if i >= cands.len() {
            break;
        }
        let cand = *cands.at(i);
        let score = score_counter_candidate(
            cand,
            prev_counter,
            prev_cantus,
            cantus_now,
            cantus_motion,
            params,
            step_index.try_into().unwrap(),
            at_mode_boundary,
            is_final,
            lower_voices_at_index,
            lower_voices_prev,
        );
        let tie_key = bounded(step_hash(*params.seed, step_index) + cand.into(), 1000000);
        if score > best_score || (score == best_score && tie_key < best_tie) {
            best_score = score;
            best = cand;
            best_tie = tie_key;
        }
        i += 1;
    };

    if best_score > 0 {
        return best;
    }

    let mut j: usize = 0;
    loop {
        if j >= cands.len() {
            break;
        }
        let cand = *cands.at(j);
        if in_register(cand, *params.register_lo, *params.register_hi)
            && !violates_voice_placement(cand, cantus_now, *params.voice_placement)
            && !violates_lower_voices(
                cand, cantus_now, lower_voices_at_index, *params.voice_placement,
            )
            && !violates_forbidden_interval(cand, cantus_now)
            && !violates_invertible_requirement(cand, cantus_now, params) {
            let mut unsafe_lower = false;
            let mut li: usize = 0;
            loop {
                if li >= lower_voices_at_index.len() {
                    break;
                }
                if violates_invertible_requirement(
                    cand, *lower_voices_at_index.at(li), params,
                ) {
                    unsafe_lower = true;
                    break;
                }
                li += 1;
            };
            if unsafe_lower {
                j += 1;
                continue;
            }
            return cand;
        }
        j += 1;
    };

    if *params.require_invertible_at_octave {
        assert(false, 'no ic candidate');
    }

    if in_register(prev_counter, *params.register_lo, *params.register_hi) {
        prev_counter
    } else {
        best
    }
}

// ──────────────────────────────────────────────────────────
// Main generator
// ──────────────────────────────────────────────────────────

fn build_lower_refs_at_index(
    lower_voices: @Array<Array<u8>>, index: usize,
) -> (Array<u8>, Array<u8>) {
    let mut lower_now: Array<u8> = ArrayTrait::new();
    let mut lower_prev: Array<u8> = ArrayTrait::new();
    let mut j: usize = 0;
    loop {
        if j >= lower_voices.len() {
            break;
        }
        let voice = lower_voices.at(j);
        lower_now.append(*voice.at(index));
        if index == 0 {
            lower_prev.append(*voice.at(0));
        } else {
            lower_prev.append(*voice.at(index - 1));
        }
        j += 1;
    };
    (lower_now, lower_prev)
}

fn build_lower_at_first(lower_voices: @Array<Array<u8>>) -> Array<u8> {
    let mut lower_now: Array<u8> = ArrayTrait::new();
    let mut j: usize = 0;
    loop {
        if j >= lower_voices.len() {
            break;
        }
        lower_now.append(*lower_voices.at(j).at(0));
        j += 1;
    };
    lower_now
}

fn voice_params_for_index(
    base_params: @CounterpointParams, vi: u32,
) -> CounterpointParams {
    let placement = if vi % 2 == 1 {
        VoicePlacement::BelowCantus(())
    } else {
        VoicePlacement::AboveCantus(())
    };
    let layer: u32 = vi / 2;
    let layer_off: u8 = (layer * 8).try_into().unwrap();
    let (reg_lo, reg_hi) = if vi % 2 == 1 {
        let reg_hi: u8 = 64_u8 - layer_off;
        let reg_lo: u8 = if reg_hi > 12 { reg_hi - 12 } else { 28_u8 };
        (reg_lo, reg_hi)
    } else {
        let reg_lo: u8 = 65_u8 + layer_off;
        let reg_hi: u8 = if reg_lo <= 84 { reg_lo + 12 } else { 96_u8 };
        (reg_lo, reg_hi)
    };
    CounterpointParams {
        seed: *base_params.seed + vi.into(),
        tonic: *base_params.tonic,
        mode_spec: clone_mode_spec(base_params.mode_spec),
        register_lo: reg_lo,
        register_hi: reg_hi,
        max_melodic_leap: *base_params.max_melodic_leap,
        motion_bias: *base_params.motion_bias,
        voice_placement: placement,
        forbid_parallel_perfects: *base_params.forbid_parallel_perfects,
        forbid_similar_perfects: *base_params.forbid_similar_perfects,
        require_invertible_at_octave: *base_params.require_invertible_at_octave,
    }
}

/// Generate a counter voice against cantus, scoring pairwise against all lower voices.
pub fn generate_counterpoint_with_lowers(
    cantus: Span<u8>,
    params: CounterpointParams,
    lower_voices: @Array<Array<u8>>,
) -> CounterpointResult {
    assert(cantus.len() > 0, 'empty cantus');
    validate_mode_spec(@params.mode_spec, cantus.len());

    let mut counter: Array<u8> = ArrayTrait::new();
    let mut counter_contour: Array<Contour> = ArrayTrait::new();
    let mut motion_trace: Array<MotionKind> = ArrayTrait::new();

    let cantus_contour = encode_contour(cantus);
    let last_idx = cantus.len() - 1;

    let first = *cantus.at(0);
    let lower_first = build_lower_at_first(lower_voices);
    let initial = pick_initial_counter(first, @params, lower_first.span());
    counter.append(initial);

    if cantus.len() == 1 {
        let (c, p, o) = count_motion_stats(motion_trace.span());
        return CounterpointResult {
            cantus: span_to_array(cantus),
            counter,
            cantus_contour,
            counter_contour,
            motion_trace,
            contrary_count: c,
            parallel_count: p,
            oblique_count: o,
        };
    }

    let mut i: usize = 1;
    loop {
        if i >= cantus.len() {
            break;
        }

        let prev_cantus = *cantus.at(i - 1);
        let cantus_now = *cantus.at(i);
        let prev_counter = *counter.at(i - 1);
        let cantus_motion = motion_contour(prev_cantus, cantus_now);
        let boundary = is_mode_boundary(@params.mode_spec, i);
        let is_final = i == last_idx;

        let cands = collect_candidates_for_index(
            prev_counter, @params, i, boundary,
        );

        let (lower_now, lower_prev) = build_lower_refs_at_index(lower_voices, i);

        let chosen = pick_best_candidate(
            cands.span(),
            prev_counter,
            prev_cantus,
            cantus_now,
            cantus_motion,
            @params,
            i.try_into().unwrap(),
            boundary,
            is_final,
            lower_now.span(),
            lower_prev.span(),
        );

        counter.append(chosen);
        counter_contour.append(motion_contour(prev_counter, chosen));
        motion_trace
            .append(
                classify_motion(cantus_motion, motion_contour(prev_counter, chosen)),
            );

        i += 1;
    };

    let (c, p, o) = count_motion_stats(motion_trace.span());
    CounterpointResult {
        cantus: span_to_array(cantus),
        counter,
        cantus_contour,
        counter_contour,
        motion_trace,
        contrary_count: c,
        parallel_count: p,
        oblique_count: o,
    }
}

pub fn generate_counterpoint(
    cantus: Span<u8>, params: CounterpointParams,
) -> CounterpointResult {
    let empty_lowers: Array<Array<u8>> = ArrayTrait::new();
    generate_counterpoint_with_lowers(cantus, params, @empty_lowers)
}

/// Counterpoint on tile grid: only advances on sounding onsets; rests expand to [`REST_PITCH`].
pub fn generate_counterpoint_sparse(
    tile_pitches: Span<u8>,
    onset_mask: Span<u32>,
    params: CounterpointParams,
) -> CounterpointResult {
    assert(tile_pitches.len() == onset_mask.len(), 'sparse tile mismatch');
    let sparse_cantus = extract_onset_pitches(tile_pitches, onset_mask);
    assert(sparse_cantus.len() > 0, 'no sounding onsets');
    let filtered_spec = filter_mode_spec_for_onsets(@params.mode_spec, onset_mask);
    let sparse_params = CounterpointParams {
        seed: params.seed,
        tonic: params.tonic,
        mode_spec: filtered_spec,
        register_lo: params.register_lo,
        register_hi: params.register_hi,
        max_melodic_leap: params.max_melodic_leap,
        motion_bias: params.motion_bias,
        voice_placement: params.voice_placement,
        forbid_parallel_perfects: params.forbid_parallel_perfects,
        forbid_similar_perfects: params.forbid_similar_perfects,
        require_invertible_at_octave: params.require_invertible_at_octave,
    };
    let sparse_result = generate_counterpoint(sparse_cantus.span(), sparse_params);
    let tile_counter = expand_onset_pitches(sparse_result.counter.span(), onset_mask);
    CounterpointResult {
        cantus: span_to_array(tile_pitches),
        counter: tile_counter,
        cantus_contour: sparse_result.cantus_contour,
        counter_contour: sparse_result.counter_contour,
        motion_trace: sparse_result.motion_trace,
        contrary_count: sparse_result.contrary_count,
        parallel_count: sparse_result.parallel_count,
        oblique_count: sparse_result.oblique_count,
    }
}

/// Build harmony voices 1..N-1 against cantus voice 0 with pairwise lower-voice scoring.
pub fn generate_n_voice_counterpoint(
    cantus: Span<u8>, base_params: @CounterpointParams, num_voices: u32,
) -> Array<Array<u8>> {
    assert(num_voices >= 1, 'need >=1 voice');
    let mut out: Array<Array<u8>> = ArrayTrait::new();
    out.append(span_to_array(cantus));

    let mut vi: u32 = 1;
    loop {
        if vi >= num_voices {
            break;
        }
        let mut lowers: Array<Array<u8>> = ArrayTrait::new();
        let mut lj: u32 = 0;
        loop {
            if lj >= vi {
                break;
            }
            lowers.append(clone_array_u8(out.at(lj.try_into().unwrap())));
            lj += 1;
        };
        let voice_params = voice_params_for_index(base_params, vi);
        let result = generate_counterpoint_with_lowers(cantus, voice_params, @lowers);
        out.append(result.counter);
        vi += 1;
    };
    out
}

/// N-voice counterpoint on tile grid with per-onset sparse alignment.
pub fn generate_n_voice_counterpoint_sparse(
    tile_pitches: Span<u8>,
    onset_mask: Span<u32>,
    base_params: @CounterpointParams,
    num_voices: u32,
) -> Array<Array<u8>> {
    assert(num_voices >= 1, 'need >=1 voice');
    assert(tile_pitches.len() == onset_mask.len(), 'sparse tile mismatch');
    let sparse_cantus = extract_onset_pitches(tile_pitches, onset_mask);
    assert(sparse_cantus.len() > 0, 'no sounding onsets');
    let filtered_spec = filter_mode_spec_for_onsets(base_params.mode_spec, onset_mask);

    let mut out: Array<Array<u8>> = ArrayTrait::new();
    out.append(span_to_array(tile_pitches));

    let mut vi: u32 = 1;
    loop {
        if vi >= num_voices {
            break;
        }
        let mut lowers_sparse: Array<Array<u8>> = ArrayTrait::new();
        let mut lj: u32 = 0;
        loop {
            if lj >= vi {
                break;
            }
            let lower_tile = out.at(lj.try_into().unwrap());
            lowers_sparse
                .append(extract_onset_pitches(lower_tile.span(), onset_mask));
            lj += 1;
        };
        let base_voice = voice_params_for_index(base_params, vi);
        let voice_params = CounterpointParams {
            seed: base_voice.seed,
            tonic: base_voice.tonic,
            mode_spec: clone_mode_spec(@filtered_spec),
            register_lo: base_voice.register_lo,
            register_hi: base_voice.register_hi,
            max_melodic_leap: base_voice.max_melodic_leap,
            motion_bias: base_voice.motion_bias,
            voice_placement: base_voice.voice_placement,
            forbid_parallel_perfects: base_voice.forbid_parallel_perfects,
            forbid_similar_perfects: base_voice.forbid_similar_perfects,
            require_invertible_at_octave: base_voice.require_invertible_at_octave,
        };
        let result = generate_counterpoint_with_lowers(
            sparse_cantus.span(), voice_params, @lowers_sparse,
        );
        out.append(expand_onset_pitches(result.counter.span(), onset_mask));
        vi += 1;
    };
    out
}

/// Convenience wrapper for symmetry/canon pipelines (single fixed mode).
pub fn generate_canon_counterpoint(
    seed: felt252,
    cantus: Span<u8>,
    world_mask: u16,
    tonic: PitchClass,
    mode: Modes,
    motion_bias: MotionBias,
    register_lo: u8,
    register_hi: u8,
) -> Array<u8> {
    let params = CounterpointParams {
        seed,
        tonic,
        mode_spec: fixed_mode_spec(mode, world_mask),
        register_lo,
        register_hi,
        max_melodic_leap: 12,
        motion_bias,
        voice_placement: VoicePlacement::BelowCantus(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
        require_invertible_at_octave: false,
    };
    generate_counterpoint(cantus, params).counter
}

pub fn motion_bias_contrary() -> MotionBias {
    MotionBias { parallel: 20, contrary: 80, oblique: 50 }
}

pub fn motion_bias_parallel() -> MotionBias {
    MotionBias { parallel: 90, contrary: 10, oblique: 30 }
}

pub fn motion_bias_balanced() -> MotionBias {
    MotionBias { parallel: 40, contrary: 40, oblique: 40 }
}

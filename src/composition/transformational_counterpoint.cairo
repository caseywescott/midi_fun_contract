//! Transformational counterpoint: reusable musical lines under pitch, time, order, and voice
//! placement transforms.
//!
//! This layer sits above the generic parameter-plane transforms and below higher-level canon /
//! composition generators.  It keeps material in signed degree space long enough to validate
//! contrapuntal relationships before realizing to MIDI keynums.

use core::array::ArrayTrait;
use koji::composition::aesthetic_profile::{AestheticProfile, vertical_ok};
use koji::composition::canon_rules::{abs_i32, is_consonant_class};
use koji::composition::invertible_counterpoint::lattice_ic_safe;
use koji::composition::melodic_canon::{NoteEvent, DEFAULT_VELOCITY, realize_degree};

// ─────────────────────────────────────────────────────────────
// Core data structures
// ─────────────────────────────────────────────────────────────

/// Degree-space timed event.  `degree` is diatonic/chromatic lattice position, not MIDI keynum.
#[derive(Copy, Drop, Serde)]
pub struct DegreeEvent {
    pub degree: i32,
    pub time: u32,
    pub duration: u32,
    pub velocity: u8,
    pub voice_id: u32,
}

#[derive(Copy, Drop, Serde)]
pub struct TimeRatio {
    pub num: u32,
    pub den: u32,
}

#[derive(Copy, Drop, Serde)]
pub enum TransformRole {
    CanonFollower: (),
    Countersubject: (),
    Accompaniment: (),
    Bass: (),
    InnerVoice: (),
    CompositeLine: (),
}

#[derive(Copy, Drop, Serde)]
pub enum TransformFailure {
    Ok: (),
    LengthMismatch: (),
    PitchTransformMismatch: (),
    RhythmTransformMismatch: (),
    VerticalClash: (),
    ICSafetyClash: (),
    InvalidRatio: (),
    InvalidVoiceCount: (),
}

#[derive(Copy, Drop, Serde)]
pub enum CanonTransformKind {
    Exact: (),
    Mirror: (),
    Crab: (),
    Augmentation: (),
    Diminution: (),
    RetrogradeInversion: (),
}

#[derive(Copy, Drop, Serde)]
pub struct CanonTransformPlan {
    pub kind: CanonTransformKind,
    pub entry_time: u32,
    /// Added to transformed follower degrees after exact, crab, augmentation, and diminution.
    pub transposition: i32,
    /// Existing canon-inversion convention: follower degree = pivot - leader degree.
    pub pivot: i32,
    pub factor: u32,
    pub follower_voice_id: u32,
}

#[derive(Drop, Serde)]
pub struct TransformCompositionPlan {
    pub subject: Array<DegreeEvent>,
    pub companion: Array<DegreeEvent>,
    pub role: TransformRole,
}

#[derive(Drop, Serde)]
pub struct TransformRepairResult {
    pub found: bool,
    pub transposition: i32,
    pub line: Array<DegreeEvent>,
}

// ─────────────────────────────────────────────────────────────
// Construction and conversion
// ─────────────────────────────────────────────────────────────

pub fn degree_event(
    degree: i32, time: u32, duration: u32, velocity: u8, voice_id: u32,
) -> DegreeEvent {
    DegreeEvent { degree, time, duration, velocity, voice_id }
}

pub fn degree_line_from_degrees(
    degrees: Span<i32>, unit: u32, voice_id: u32,
) -> Array<DegreeEvent> {
    assert(unit > 0, 'unit must be >0');
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= degrees.len() {
            break;
        }
        out.append(degree_event(*degrees.at(i), i * unit, unit, DEFAULT_VELOCITY, voice_id));
        i += 1;
    };
    out
}

pub fn clone_degree_line(line: Span<DegreeEvent>) -> Array<DegreeEvent> {
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        out.append(*line.at(i));
        i += 1;
    };
    out
}

pub fn append_degree_line(ref out: Array<DegreeEvent>, line: Span<DegreeEvent>) {
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        out.append(*line.at(i));
        i += 1;
    };
}

pub fn concat_degree_lines(a: Span<DegreeEvent>, b: Span<DegreeEvent>) -> Array<DegreeEvent> {
    let mut out = clone_degree_line(a);
    append_degree_line(ref out, b);
    out
}

pub fn degree_events_to_note_events(
    line: Span<DegreeEvent>, octave: u32, tonic_keynum: u8, mode_id: u8,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let e = *line.at(i);
        out.append(
            NoteEvent {
                time: e.time,
                duration: e.duration,
                pitch: realize_degree(octave, e.degree, tonic_keynum, mode_id),
                velocity: e.velocity,
                voice_id: e.voice_id,
            },
        );
        i += 1;
    };
    out
}

pub fn total_end_time(line: Span<DegreeEvent>) -> u32 {
    let mut max_end: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let e = *line.at(i);
        let end = e.time + e.duration;
        if end > max_end {
            max_end = end;
        }
        i += 1;
    };
    max_end
}

pub fn assign_voice_id(line: Span<DegreeEvent>, voice_id: u32) -> Array<DegreeEvent> {
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let mut e = *line.at(i);
        e.voice_id = voice_id;
        out.append(e);
        i += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Pure line transforms
// ─────────────────────────────────────────────────────────────

pub fn transpose_line(line: Span<DegreeEvent>, interval: i32) -> Array<DegreeEvent> {
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let mut e = *line.at(i);
        e.degree += interval;
        out.append(e);
        i += 1;
    };
    out
}

/// Mirror around a pivot using the existing canon convention: `d -> pivot - d`.
pub fn invert_line(line: Span<DegreeEvent>, pivot: i32) -> Array<DegreeEvent> {
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let mut e = *line.at(i);
        e.degree = pivot - e.degree;
        out.append(e);
        i += 1;
    };
    out
}

/// Axis-style inversion: `d -> 2 * axis - d`.
pub fn axis_invert_line(line: Span<DegreeEvent>, axis: i32) -> Array<DegreeEvent> {
    invert_line(line, 2 * axis)
}

pub fn delay_line(line: Span<DegreeEvent>, entry_time: u32) -> Array<DegreeEvent> {
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let mut e = *line.at(i);
        e.time += entry_time;
        out.append(e);
        i += 1;
    };
    out
}

pub fn time_scale_line(line: Span<DegreeEvent>, ratio: TimeRatio) -> Array<DegreeEvent> {
    assert(ratio.num > 0, 'ratio num');
    assert(ratio.den > 0, 'ratio den');
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let mut e = *line.at(i);
        assert((e.time * ratio.num) % ratio.den == 0, 'time ratio');
        assert((e.duration * ratio.num) % ratio.den == 0, 'dur ratio');
        e.time = e.time * ratio.num / ratio.den;
        e.duration = e.duration * ratio.num / ratio.den;
        assert(e.duration > 0, 'zero duration');
        out.append(e);
        i += 1;
    };
    out
}

pub fn augment_line(line: Span<DegreeEvent>, factor: u32) -> Array<DegreeEvent> {
    time_scale_line(line, TimeRatio { num: factor, den: 1 })
}

pub fn diminish_line(line: Span<DegreeEvent>, factor: u32) -> Array<DegreeEvent> {
    time_scale_line(line, TimeRatio { num: 1, den: factor })
}

/// Reverse pitch/order while preserving the original timespan.
pub fn retrograde_line(line: Span<DegreeEvent>) -> Array<DegreeEvent> {
    let len = line.len();
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    if len == 0 {
        return out;
    }
    let total = total_end_time(line);
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        let src = *line.at(len - 1 - i);
        let mut e = src;
        e.time = total - (src.time + src.duration);
        out.append(e);
        i += 1;
    };
    out
}

/// Reverse event order and lay the reversed events back out from time zero using carried durations.
pub fn retrograde_keep_durations(line: Span<DegreeEvent>) -> Array<DegreeEvent> {
    let len = line.len();
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut t: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        let mut e = *line.at(len - 1 - i);
        e.time = t;
        t += e.duration;
        out.append(e);
        i += 1;
    };
    out
}

pub fn retrograde_inversion_line(line: Span<DegreeEvent>, pivot: i32) -> Array<DegreeEvent> {
    invert_line(retrograde_line(line).span(), pivot)
}

// ─────────────────────────────────────────────────────────────
// Voice exchange
// ─────────────────────────────────────────────────────────────

pub fn voice_exchange_by_index(
    a: Span<DegreeEvent>, b: Span<DegreeEvent>, start: u32, end: u32,
) -> (Array<DegreeEvent>, Array<DegreeEvent>) {
    assert(a.len() == b.len(), 'exchange len');
    let mut out_a: Array<DegreeEvent> = ArrayTrait::new();
    let mut out_b: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        let mut ea = *a.at(i);
        let mut eb = *b.at(i);
        if i >= start && i < end {
            let da = ea.degree;
            ea.degree = eb.degree;
            eb.degree = da;
        }
        out_a.append(ea);
        out_b.append(eb);
        i += 1;
    };
    (out_a, out_b)
}

pub fn voice_exchange_material_by_index(
    a: Span<DegreeEvent>, b: Span<DegreeEvent>, start: u32, end: u32,
) -> (Array<DegreeEvent>, Array<DegreeEvent>) {
    assert(a.len() == b.len(), 'exchange len');
    let mut out_a: Array<DegreeEvent> = ArrayTrait::new();
    let mut out_b: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        let ea = *a.at(i);
        let eb = *b.at(i);
        if i >= start && i < end {
            out_a.append(DegreeEvent { voice_id: ea.voice_id, ..eb });
            out_b.append(DegreeEvent { voice_id: eb.voice_id, ..ea });
        } else {
            out_a.append(ea);
            out_b.append(eb);
        }
        i += 1;
    };
    (out_a, out_b)
}

// ─────────────────────────────────────────────────────────────
// Hocket
// ─────────────────────────────────────────────────────────────

pub fn hocket_part(
    line: Span<DegreeEvent>, voice_count: u32, part_index: u32, voice_id: u32,
) -> Array<DegreeEvent> {
    assert(voice_count > 0, 'voices >0');
    assert(part_index < voice_count, 'part index');
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        if i % voice_count == part_index {
            let mut e = *line.at(i);
            e.voice_id = voice_id;
            out.append(e);
        }
        i += 1;
    };
    out
}

/// Flattened hocket texture: each source event is assigned to one of `voice_count` voices.
pub fn hocket_partition(
    line: Span<DegreeEvent>, voice_count: u32, first_voice_id: u32,
) -> Array<DegreeEvent> {
    assert(voice_count > 0, 'voices >0');
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= line.len() {
            break;
        }
        let mut e = *line.at(i);
        e.voice_id = first_voice_id + (i % voice_count);
        out.append(e);
        i += 1;
    };
    out
}

pub fn hocket_reconstructs(original: Span<DegreeEvent>, hocketed: Span<DegreeEvent>) -> bool {
    if original.len() != hocketed.len() {
        return false;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= original.len() || !ok {
            break;
        }
        let a = *original.at(i);
        let b = *hocketed.at(i);
        if a.degree != b.degree || a.time != b.time || a.duration != b.duration {
            ok = false;
        }
        i += 1;
    };
    ok
}

// ─────────────────────────────────────────────────────────────
// Isorhythm
// ─────────────────────────────────────────────────────────────

pub fn gcd_u32(a: u32, b: u32) -> u32 {
    let mut x = a;
    let mut y = b;
    loop {
        if y == 0 {
            break;
        }
        let r = x % y;
        x = y;
        y = r;
    };
    x
}

pub fn lcm_u32(a: u32, b: u32) -> u32 {
    if a == 0 || b == 0 {
        return 0;
    }
    a / gcd_u32(a, b) * b
}

pub fn isorhythm_period(color_len: u32, talea_len: u32) -> u32 {
    lcm_u32(color_len, talea_len)
}

pub fn isorhythm_line(
    color: Span<i32>, talea: Span<u32>, repeat_count: u32, voice_id: u32,
) -> Array<DegreeEvent> {
    assert(color.len() > 0, 'color empty');
    assert(talea.len() > 0, 'talea empty');
    let period = isorhythm_period(color.len(), talea.len());
    let total = period * repeat_count;
    let mut out: Array<DegreeEvent> = ArrayTrait::new();
    let mut t: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= total {
            break;
        }
        let dur = *talea.at(i % talea.len());
        assert(dur > 0, 'talea zero');
        out.append(degree_event(*color.at(i % color.len()), t, dur, DEFAULT_VELOCITY, voice_id));
        t += dur;
        i += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Canon and standalone texture constructors
// ─────────────────────────────────────────────────────────────

pub fn default_canon_transform_plan(
    kind: CanonTransformKind, entry_time: u32, follower_voice_id: u32,
) -> CanonTransformPlan {
    CanonTransformPlan {
        kind,
        entry_time,
        transposition: 0,
        pivot: 0,
        factor: 1,
        follower_voice_id,
    }
}

pub fn transformed_follower(
    leader: Span<DegreeEvent>, plan: CanonTransformPlan,
) -> Array<DegreeEvent> {
    let mut out = match plan.kind {
        CanonTransformKind::Exact(_) => transpose_line(leader, plan.transposition),
        CanonTransformKind::Mirror(_) => invert_line(leader, plan.pivot),
        CanonTransformKind::Crab(_) => transpose_line(retrograde_line(leader).span(), plan.transposition),
        CanonTransformKind::Augmentation(_) => {
            transpose_line(augment_line(leader, plan.factor).span(), plan.transposition)
        },
        CanonTransformKind::Diminution(_) => {
            transpose_line(diminish_line(leader, plan.factor).span(), plan.transposition)
        },
        CanonTransformKind::RetrogradeInversion(_) => {
            retrograde_inversion_line(leader, plan.pivot)
        },
    };
    out = delay_line(out.span(), plan.entry_time);
    assign_voice_id(out.span(), plan.follower_voice_id)
}

pub fn transformed_canon_texture(
    leader: Span<DegreeEvent>, plan: CanonTransformPlan,
) -> Array<DegreeEvent> {
    let follower = transformed_follower(leader, plan);
    concat_degree_lines(leader, follower.span())
}

pub fn standalone_harmonized_transform(
    subject: Span<DegreeEvent>, companion: Span<DegreeEvent>, role: TransformRole,
) -> TransformCompositionPlan {
    TransformCompositionPlan {
        subject: clone_degree_line(subject),
        companion: clone_degree_line(companion),
        role,
    }
}

/// A conservative non-canonic harmonization: same rhythm, companion at a stable third above.
pub fn simple_third_harmonized_composition(subject: Span<DegreeEvent>, voice_id: u32) -> TransformCompositionPlan {
    let companion = assign_voice_id(transpose_line(subject, 2).span(), voice_id);
    standalone_harmonized_transform(subject, companion.span(), TransformRole::Accompaniment(()))
}

pub fn composition_to_events(plan: @TransformCompositionPlan) -> Array<DegreeEvent> {
    concat_degree_lines(plan.subject.span(), plan.companion.span())
}

// ─────────────────────────────────────────────────────────────
// Generation policy and repair
// ─────────────────────────────────────────────────────────────

fn seed_bits(seed: felt252, shift: u32, width: u32) -> u32 {
    let s: u256 = seed.into();
    let mut p: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= shift {
            break;
        }
        p = p * 2;
        i += 1;
    };
    let mut w: u256 = 1;
    i = 0;
    loop {
        if i >= width {
            break;
        }
        w = w * 2;
        i += 1;
    };
    ((s / p) % w).try_into().unwrap()
}

pub fn canon_transform_kind_id(kind: CanonTransformKind) -> u32 {
    match kind {
        CanonTransformKind::Exact(_) => 0,
        CanonTransformKind::Mirror(_) => 1,
        CanonTransformKind::Crab(_) => 2,
        CanonTransformKind::Augmentation(_) => 3,
        CanonTransformKind::Diminution(_) => 4,
        CanonTransformKind::RetrogradeInversion(_) => 5,
    }
}

pub fn canon_transform_descriptor(kind: CanonTransformKind) -> felt252 {
    match kind {
        CanonTransformKind::Exact(_) => 'ExactCanon',
        CanonTransformKind::Mirror(_) => 'MirrorCanon',
        CanonTransformKind::Crab(_) => 'CrabCanon',
        CanonTransformKind::Augmentation(_) => 'AugCanon',
        CanonTransformKind::Diminution(_) => 'DimCanon',
        CanonTransformKind::RetrogradeInversion(_) => 'RetroInvCanon',
    }
}

pub fn canon_transform_kind_from_id(id: u32) -> CanonTransformKind {
    let k = id % 6;
    if k == 0 {
        CanonTransformKind::Exact(())
    } else if k == 1 {
        CanonTransformKind::Mirror(())
    } else if k == 2 {
        CanonTransformKind::Crab(())
    } else if k == 3 {
        CanonTransformKind::Augmentation(())
    } else if k == 4 {
        CanonTransformKind::Diminution(())
    } else {
        CanonTransformKind::RetrogradeInversion(())
    }
}

/// Deterministic bounded selector for canonic transform plans.
///
/// The output deliberately uses small integer ratios: factor 1 or 2, safe for the current grid
/// when the caller's unit is divisible by 2 for diminution.
pub fn seeded_canon_transform_plan(
    seed: felt252, entry_time: u32, follower_voice_id: u32,
) -> CanonTransformPlan {
    let kind = canon_transform_kind_from_id(seed_bits(seed, 0, 8));
    let factor = (seed_bits(seed, 8, 2) % 2) + 1;
    let pivot_raw = seed_bits(seed, 10, 3) % 5;
    let pivot: i32 = pivot_raw.try_into().unwrap();
    let tr_raw = seed_bits(seed, 13, 3) % 5;
    let transposition: i32 = tr_raw.try_into().unwrap() - 2;
    CanonTransformPlan { kind, entry_time, transposition, pivot, factor, follower_voice_id }
}

pub fn transpose_repair_profile(
    leader: Span<DegreeEvent>,
    candidate: Span<DegreeEvent>,
    profile: @AestheticProfile,
    min_transposition: i32,
    max_transposition: i32,
) -> TransformRepairResult {
    let mut t = min_transposition;
    loop {
        if t > max_transposition {
            break;
        }
        let repaired = transpose_line(candidate, t);
        if overlaps_profile_ok(leader, repaired.span(), profile) {
            return TransformRepairResult { found: true, transposition: t, line: repaired };
        }
        t += 1;
    };
    TransformRepairResult {
        found: false,
        transposition: 0,
        line: clone_degree_line(candidate),
    }
}

/// Strict mode: emit the requested follower and report whether it validates.
pub fn strict_transformed_follower(
    leader: Span<DegreeEvent>, plan: CanonTransformPlan, profile: @AestheticProfile,
) -> TransformRepairResult {
    let follower = transformed_follower(leader, plan);
    let ok = overlaps_profile_ok(leader, follower.span(), profile);
    TransformRepairResult { found: ok, transposition: 0, line: follower }
}

/// Permissive mode: try the requested transform, transpose-repair it, then fall back to a third.
pub fn permissive_transformed_follower(
    leader: Span<DegreeEvent>, plan: CanonTransformPlan, profile: @AestheticProfile,
) -> TransformRepairResult {
    let strict = strict_transformed_follower(leader, plan, profile);
    if strict.found {
        return strict;
    }
    let repair = transpose_repair_profile(leader, strict.line.span(), profile, -4, 4);
    if repair.found {
        return repair;
    }
    let fallback = assign_voice_id(transpose_line(leader, 2).span(), plan.follower_voice_id);
    TransformRepairResult {
        found: overlaps_profile_ok(leader, fallback.span(), profile),
        transposition: 2,
        line: delay_line(fallback.span(), plan.entry_time),
    }
}

// ─────────────────────────────────────────────────────────────
// Validators
// ─────────────────────────────────────────────────────────────

pub fn events_overlap(a: DegreeEvent, b: DegreeEvent) -> bool {
    a.time < b.time + b.duration && b.time < a.time + a.duration
}

pub fn rhythm_valid(line: Span<DegreeEvent>) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= line.len() || !ok {
            break;
        }
        if (*line.at(i)).duration == 0 {
            ok = false;
        }
        i += 1;
    };
    ok
}

pub fn overlaps_consonant(a: Span<DegreeEvent>, b: Span<DegreeEvent>) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= a.len() || !ok {
            break;
        }
        let ea = *a.at(i);
        let mut j: u32 = 0;
        loop {
            if j >= b.len() || !ok {
                break;
            }
            let eb = *b.at(j);
            if ea.voice_id != eb.voice_id && events_overlap(ea, eb) {
                let cls = abs_i32(ea.degree - eb.degree) % 7;
                if !is_consonant_class(cls) {
                    ok = false;
                }
            }
            j += 1;
        };
        i += 1;
    };
    ok
}

pub fn overlaps_profile_ok(
    a: Span<DegreeEvent>, b: Span<DegreeEvent>, profile: @AestheticProfile,
) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= a.len() || !ok {
            break;
        }
        let ea = *a.at(i);
        let mut j: u32 = 0;
        loop {
            if j >= b.len() || !ok {
                break;
            }
            let eb = *b.at(j);
            if ea.voice_id != eb.voice_id && events_overlap(ea, eb) {
                if !vertical_ok(profile, ea.degree, eb.degree) {
                    ok = false;
                }
            }
            j += 1;
        };
        i += 1;
    };
    ok
}

pub fn overlaps_ic_safe(a: Span<DegreeEvent>, b: Span<DegreeEvent>, octave: u32) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= a.len() || !ok {
            break;
        }
        let ea = *a.at(i);
        let mut j: u32 = 0;
        loop {
            if j >= b.len() || !ok {
                break;
            }
            let eb = *b.at(j);
            if ea.voice_id != eb.voice_id && events_overlap(ea, eb) {
                if !lattice_ic_safe(octave, ea.degree, eb.degree) {
                    ok = false;
                }
            }
            j += 1;
        };
        i += 1;
    };
    ok
}

pub fn no_same_voice_overlaps(line: Span<DegreeEvent>) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= line.len() || !ok {
            break;
        }
        let ea = *line.at(i);
        let mut j: u32 = i + 1;
        loop {
            if j >= line.len() || !ok {
                break;
            }
            let eb = *line.at(j);
            if ea.voice_id == eb.voice_id && events_overlap(ea, eb) {
                ok = false;
            }
            j += 1;
        };
        i += 1;
    };
    ok
}

pub fn texture_profile_ok(line: Span<DegreeEvent>, profile: @AestheticProfile) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= line.len() || !ok {
            break;
        }
        let ea = *line.at(i);
        let mut j: u32 = i + 1;
        loop {
            if j >= line.len() || !ok {
                break;
            }
            let eb = *line.at(j);
            if ea.voice_id != eb.voice_id && events_overlap(ea, eb) {
                if !vertical_ok(profile, ea.degree, eb.degree) {
                    ok = false;
                }
            }
            j += 1;
        };
        i += 1;
    };
    ok
}

pub fn texture_ic_safe(line: Span<DegreeEvent>, octave: u32) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= line.len() || !ok {
            break;
        }
        let ea = *line.at(i);
        let mut j: u32 = i + 1;
        loop {
            if j >= line.len() || !ok {
                break;
            }
            let eb = *line.at(j);
            if ea.voice_id != eb.voice_id && events_overlap(ea, eb) {
                if !lattice_ic_safe(octave, ea.degree, eb.degree) {
                    ok = false;
                }
            }
            j += 1;
        };
        i += 1;
    };
    ok
}

pub fn mirror_identity_holds(
    leader: Span<DegreeEvent>, follower: Span<DegreeEvent>, pivot: i32, entry_time: u32,
) -> bool {
    if leader.len() != follower.len() {
        return false;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= leader.len() || !ok {
            break;
        }
        let l = *leader.at(i);
        let f = *follower.at(i);
        if f.degree != pivot - l.degree || f.time != l.time + entry_time || f.duration != l.duration {
            ok = false;
        }
        i += 1;
    };
    ok
}

pub fn exact_identity_holds(
    leader: Span<DegreeEvent>, follower: Span<DegreeEvent>, transposition: i32, entry_time: u32,
) -> bool {
    if leader.len() != follower.len() {
        return false;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= leader.len() || !ok {
            break;
        }
        let l = *leader.at(i);
        let f = *follower.at(i);
        if f.degree != l.degree + transposition || f.time != l.time + entry_time || f.duration != l.duration {
            ok = false;
        }
        i += 1;
    };
    ok
}

pub fn crab_identity_holds(
    leader: Span<DegreeEvent>, follower: Span<DegreeEvent>, transposition: i32, entry_time: u32,
) -> bool {
    if leader.len() != follower.len() {
        return false;
    }
    let retro = delay_line(transpose_line(retrograde_line(leader).span(), transposition).span(), entry_time);
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= follower.len() || !ok {
            break;
        }
        let a = *retro.at(i);
        let b = *follower.at(i);
        if a.degree != b.degree || a.time != b.time || a.duration != b.duration {
            ok = false;
        }
        i += 1;
    };
    ok
}

pub fn transform_failure_for_pair(
    a: Span<DegreeEvent>, b: Span<DegreeEvent>, profile: @AestheticProfile, require_ic: bool,
) -> TransformFailure {
    if !rhythm_valid(a) || !rhythm_valid(b) {
        return TransformFailure::RhythmTransformMismatch(());
    }
    if !overlaps_profile_ok(a, b, profile) {
        return TransformFailure::VerticalClash(());
    }
    if require_ic && !overlaps_ic_safe(a, b, *profile.octave) {
        return TransformFailure::ICSafetyClash(());
    }
    TransformFailure::Ok(())
}

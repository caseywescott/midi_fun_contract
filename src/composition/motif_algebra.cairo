//! Motif development algebra — developing variation on the degree lattice.
//!
//! Transforms compose as pure total functions over signed lattice degrees (same representation as
//! `MelodicCanon.leader_degrees`). World-aware ops snap through `symmetry_engine::quantize_pitch_to_world`.
//! See `docs/motif_development_algebra_spec.md`.

use core::option::OptionTrait;
use core::array::ArrayTrait;
use koji::composition::canon_rules::{abs_i32, config_by_id};
use koji::composition::melodic_canon::{
    MelodicCanon, NoteEvent, all_pairs_consonant, build_canon_for_test,
    canon_to_ornamented_note_events_with_fill, exact_imitation,
    generate_melodic_canon_with_params, plan_ornament_subdivisions_dense, realize_degree,
    subdivide_min_step, CADENCE_LEN,
};
use koji::composition::symmetry_engine::{
    generate_world_motif, has_pitch, quantize_pitch_to_world,
};
use koji::composition::transform::{
    augment_u32, arrays_equal_i32, concat_i32, diminish_u32, invert_i32, reverse_i32, rotate_i32,
    span_i32, transpose_i32,
};

fn clone_i32(xs: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*xs.at(i));
        i += 1;
    };
    out
}

fn clone_u32(xs: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*xs.at(i));
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────────────────

#[derive(Drop, Serde)]
pub struct Motif {
    pub degrees: Array<i32>,
    pub octave: u32,
    pub world_mask: u16,
}

#[derive(Copy, Drop, Serde)]
pub struct FragmentOp {
    pub start: u32,
    pub len: u32,
}

#[derive(Copy, Drop, Serde)]
pub struct SequenceOp {
    pub step: i32,
    pub count: u32,
}

#[derive(Copy, Drop, Serde)]
pub struct StutterOp {
    pub index: u32,
    pub reps: u32,
}

#[derive(Copy, Drop, Serde)]
pub struct IntervalScaleOp {
    pub num: i32,
    pub den: i32,
}

#[derive(Drop, Serde)]
pub enum MotifOp {
    Transpose: i32,
    Invert: i32,
    Retrograde: (),
    RetrogradeInvert: i32,
    Augment: u32,
    Diminish: u32,
    Fragment: FragmentOp,
    Sequence: SequenceOp,
    Rotate: u32,
    Stutter: StutterOp,
    Interpolate: u32,
    IntervalScale: IntervalScaleOp,
    Concat: Array<i32>,
}

#[derive(Drop, Serde)]
pub struct MotifProgram {
    pub ops: Array<MotifOp>,
}

#[derive(Drop, Serde)]
pub struct DevelopedMotif {
    pub degrees: Array<i32>,
    pub durations: Array<u32>,
    pub octave: u32,
    pub world_mask: u16,
}

const DEFAULT_TONIC: u8 = 60;
const DEFAULT_MODE: u8 = 0;

// ──────────────────────────────────────────────────────────
// Seed / bit helpers
// ──────────────────────────────────────────────────────────

fn seed_u256(seed: felt252) -> u256 {
    seed.into()
}

fn pow2(p: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= p {
            break;
        }
        r *= 2;
        i += 1;
    };
    r
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

// ──────────────────────────────────────────────────────────
// Pitch-class / world gate
// ──────────────────────────────────────────────────────────

pub fn degree_to_pc(degree: i32, octave: u32, tonic_keynum: u8, mode_id: u8) -> u8 {
    let kn = realize_degree(octave, degree, tonic_keynum, mode_id);
    (kn % 12).try_into().unwrap()
}

fn nearest_degree_with_pc(
    degree: i32, target_pc: u8, octave: u32, tonic_keynum: u8, mode_id: u8,
) -> i32 {
    let cur_pc = degree_to_pc(degree, octave, tonic_keynum, mode_id);
    if cur_pc == target_pc {
        return degree;
    }
    let mut best = degree;
    let mut best_dist: u32 = 100;
    let mut delta: i32 = -14;
    loop {
        if delta > 14 {
            break;
        }
        let cand = degree + delta;
        let pc = degree_to_pc(cand, octave, tonic_keynum, mode_id);
        if pc == target_pc {
            let dist: u32 = abs_i32(delta).try_into().unwrap();
            if dist < best_dist {
                best_dist = dist;
                best = cand;
            }
        }
        delta += 1;
    };
    best
}

pub fn snap_to_world(
    degree: i32, octave: u32, mask: u16, tonic_keynum: u8, mode_id: u8,
) -> i32 {
    if mask == 0 {
        return degree;
    }
    let pc = degree_to_pc(degree, octave, tonic_keynum, mode_id);
    let qpc = quantize_pitch_to_world(mask, pc);
    nearest_degree_with_pc(degree, qpc, octave, tonic_keynum, mode_id)
}

fn snap_degrees_to_world(
    degrees: Span<i32>, octave: u32, mask: u16, tonic_keynum: u8, mode_id: u8,
) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= degrees.len() {
            break;
        }
        out.append(snap_to_world(*degrees.at(i), octave, mask, tonic_keynum, mode_id));
        i += 1;
    };
    out
}

fn op_needs_world_snap(op: @MotifOp) -> bool {
    match op {
        MotifOp::Transpose(_) => true,
        MotifOp::Invert(_) => true,
        MotifOp::RetrogradeInvert(_) => true,
        MotifOp::Sequence(_) => true,
        MotifOp::Interpolate(_) => true,
        MotifOp::IntervalScale(_) => true,
        MotifOp::Concat(_) => true,
        _ => false,
    }
}

// ──────────────────────────────────────────────────────────
// Duration helpers
// ──────────────────────────────────────────────────────────

fn default_durations(n: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        out.append(1);
        i += 1;
    };
    out
}

fn normalize_durations(degrees_len: u32, durations: Span<u32>) -> Array<u32> {
    if durations.len() == degrees_len && degrees_len > 0 {
        return clone_u32(durations);
    }
    default_durations(degrees_len)
}

fn fragment_durations(durations: Span<u32>, start: u32, len: u32) -> Array<u32> {
    let total = durations.len();
    if total == 0 || len == 0 {
        return ArrayTrait::new();
    }
    let mut s = start;
    if s >= total {
        s = 0;
    }
    let mut n = len;
    if s + n > total {
        n = total - s;
    }
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        out.append(*durations.at(s + i));
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Motif-specific transforms
// ──────────────────────────────────────────────────────────

fn interval_scale_degrees(degrees: Span<i32>, num: i32, den: i32) -> Array<i32> {
    let len = degrees.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    if len == 1 {
        return array![*degrees.at(0)];
    }
    if den == 0 {
        return clone_i32(degrees);
    }
    let mut out: Array<i32> = ArrayTrait::new();
    out.append(*degrees.at(0));
    let mut i: u32 = 1;
    loop {
        if i >= len {
            break;
        }
        let step = *degrees.at(i) - *degrees.at(i - 1);
        let scaled = step * num / den;
        let prev = *out.at(out.len() - 1);
        out.append(prev + scaled);
        i += 1;
    };
    out
}

fn interpolate_degrees(degrees: Span<i32>, min_step: u32) -> Array<i32> {
    let len = degrees.len();
    if len <= 1 {
        return clone_i32(degrees);
    }
    let stride: i32 = if min_step == 0 {
        1
    } else {
        min_step.try_into().unwrap()
    };
    let mut out: Array<i32> = ArrayTrait::new();
    out.append(*degrees.at(0));
    let mut i: u32 = 1;
    loop {
        if i >= len {
            break;
        }
        let from = *out.at(out.len() - 1);
        let to = *degrees.at(i);
        let gap = abs_i32(to - from);
        let stride_u: u32 = stride.try_into().unwrap();
        if gap > stride_u && gap > 1 {
            let s = gap / stride_u + 1;
            let ms = if min_step == 0 {
                1_u32
            } else {
                min_step
            };
            let fill = subdivide_min_step(from, to, s, ms);
            let mut k: u32 = 1;
            loop {
                if k >= fill.len() {
                    break;
                }
                out.append(*fill.at(k));
                k += 1;
            };
        } else {
            out.append(to);
        }
        i += 1;
    };
    out
}

fn stutter_degrees(degrees: Span<i32>, index: u32, reps: u32) -> Array<i32> {
    let len = degrees.len();
    if len == 0 || reps == 0 {
        return clone_i32(degrees);
    }
    let idx = if index >= len {
        0
    } else {
        index
    };
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        if i == idx {
            let mut r: u32 = 0;
            loop {
                if r >= reps {
                    break;
                }
                out.append(*degrees.at(i));
                r += 1;
            };
        } else {
            out.append(*degrees.at(i));
        }
        i += 1;
    };
    out
}

fn stutter_durations(durations: Span<u32>, index: u32, reps: u32) -> Array<u32> {
    let len = durations.len();
    if len == 0 || reps == 0 {
        return clone_u32(durations);
    }
    let idx = if index >= len {
        0
    } else {
        index
    };
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        if i == idx {
            let mut r: u32 = 0;
            loop {
                if r >= reps {
                    break;
                }
                out.append(*durations.at(i));
                r += 1;
            };
        } else {
            out.append(*durations.at(i));
        }
        i += 1;
    };
    out
}

fn sequence_degrees(base: Span<i32>, step: i32, count: u32) -> Array<i32> {
    if count == 0 || base.len() == 0 {
        return ArrayTrait::new();
    }
    let mut out = clone_i32(base);
    let mut c: u32 = 1;
    loop {
        if c >= count {
            break;
        }
        let shift = step * c.try_into().unwrap();
        let transposed = transpose_i32(base, shift);
        out = concat_i32(out.span(), transposed.span());
        c += 1;
    };
    out
}

fn concat_u32(a: Span<u32>, b: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    i = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

fn sequence_durations(base: Span<u32>, count: u32) -> Array<u32> {
    if count == 0 || base.len() == 0 {
        return ArrayTrait::new();
    }
    let mut out = clone_u32(base);
    let mut c: u32 = 1;
    loop {
        if c >= count {
            break;
        }
        out = concat_u32(out.span(), base);
        c += 1;
    };
    out
}

fn reverse_u32(xs: Span<u32>) -> Array<u32> {
    let len = xs.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        out.append(*xs.at(len - 1 - i));
        i += 1;
    };
    out
}

fn rotate_u32(xs: Span<u32>, n: u32) -> Array<u32> {
    let len = xs.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let k = n % len;
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        let src = (i + k) % len;
        out.append(*xs.at(src));
        i += 1;
    };
    out
}

fn motif_to_developed(m: @Motif, durations: Span<u32>) -> DevelopedMotif {
    DevelopedMotif {
        degrees: clone_i32(m.degrees.span()),
        durations: normalize_durations(m.degrees.len(), durations),
        octave: *m.octave,
        world_mask: *m.world_mask,
    }
}

fn maybe_snap(
    degrees: Array<i32>, mask: u16, octave: u32, snap: bool,
) -> Array<i32> {
    if !snap || mask == 0 {
        return degrees;
    }
    snap_degrees_to_world(
        degrees.span(), octave, mask, DEFAULT_TONIC, DEFAULT_MODE,
    )
}

/// Single-op application on a developed motif (pure, total).
pub fn apply_op_to_developed(m: @DevelopedMotif, op: MotifOp) -> DevelopedMotif {
    let octave = *m.octave;
    let mask = *m.world_mask;
    let snap = mask != 0;
    let needs_snap = op_needs_world_snap(@op);
    let degs = m.degrees.span();
    let durs = m.durations.span();

    let (new_degrees, new_durations) = match op {
        MotifOp::Transpose(n) => {
            (transpose_i32(degs, n), clone_u32(durs))
        },
        MotifOp::Invert(axis) => {
            (invert_i32(degs, axis), clone_u32(durs))
        },
        MotifOp::Retrograde => {
            (reverse_i32(degs), reverse_u32(durs))
        },
        MotifOp::RetrogradeInvert(axis) => {
            let inv = invert_i32(degs, axis);
            (
                reverse_i32(inv.span()),
                reverse_u32(durs),
            )
        },
        MotifOp::Augment(k) => {
            (clone_i32(degs), augment_u32(durs, k))
        },
        MotifOp::Diminish(k) => {
            (clone_i32(degs), diminish_u32(durs, k))
        },
        MotifOp::Fragment(frag) => {
            (
                span_i32(degs, frag.start, frag.start + frag.len),
                fragment_durations(durs, frag.start, frag.len),
            )
        },
        MotifOp::Sequence(seq) => {
            (
                sequence_degrees(degs, seq.step, seq.count),
                sequence_durations(durs, seq.count),
            )
        },
        MotifOp::Rotate(r) => {
            (
                rotate_i32(degs, r.try_into().unwrap()),
                rotate_u32(durs, r),
            )
        },
        MotifOp::Stutter(st) => {
            (
                stutter_degrees(degs, st.index, st.reps),
                stutter_durations(durs, st.index, st.reps),
            )
        },
        MotifOp::Interpolate(min_step) => {
            (interpolate_degrees(degs, min_step), clone_u32(durs))
        },
        MotifOp::IntervalScale(scale) => {
            (
                interval_scale_degrees(degs, scale.num, scale.den),
                clone_u32(durs),
            )
        },
        MotifOp::Concat(other) => {
            let extra_durs = default_durations(other.len());
            (
                concat_i32(degs, other.span()),
                concat_u32(durs, extra_durs.span()),
            )
        },
    };

    let snapped = maybe_snap(new_degrees, mask, octave, snap && needs_snap);

    let normalized_durations = normalize_durations(snapped.len(), new_durations.span());

    DevelopedMotif {
        degrees: snapped,
        durations: normalized_durations,
        octave,
        world_mask: mask,
    }
}

/// Single-op application from a theme motif + parallel durations.
pub fn apply_op(m: @Motif, durations: @Array<u32>, op: MotifOp) -> DevelopedMotif {
    apply_op_to_developed(@motif_to_developed(m, durations.span()), op)
}

/// Fold a program over a theme (left-to-right). Consumes `program` (ops are moved).
pub fn apply_program(
    theme: @Motif, durations: @Array<u32>, mut program: MotifProgram,
) -> DevelopedMotif {
    let mut current = motif_to_developed(theme, durations.span());
    loop {
        match program.ops.pop_front() {
            Option::Some(op) => {
                current = apply_op_to_developed(@current, op);
            },
            Option::None(_) => {
                break;
            },
        }
    };
    current
}

// ──────────────────────────────────────────────────────────
// Theme sources
// ──────────────────────────────────────────────────────────

pub fn motif_from_degrees(
    degrees: Array<i32>, octave: u32, world_mask: u16,
) -> Motif {
    Motif { degrees, octave, world_mask }
}

/// Curated Grundgestalt themes (diatonic degrees, octave 7).
pub fn grundgestalt_theme(id: u32) -> Motif {
    if id == 0 {
        motif_from_degrees(array![0_i32, 2, 1, 4], 7, 0)
    } else if id == 1 {
        motif_from_degrees(array![0_i32, 4, 2, 5, 4], 7, 0)
    } else if id == 2 {
        motif_from_degrees(array![0_i32, -1, 1, 0], 7, 0)
    } else {
        motif_from_degrees(array![0_i32, 2, 4, 7, 4, 2], 7, 0)
    }
}

pub fn motif_from_world(seed: felt252, mask: u16, length: u8) -> Motif {
    let pcs = generate_world_motif(seed, mask, length);
    let pc_span = pcs.span();
    let mut degrees: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= pc_span.len() {
            break;
        }
        degrees.append((*pc_span.at(i)).into());
        i += 1;
    };
    Motif { degrees, octave: 12, world_mask: mask }
}

pub fn motif_from_canon_leader(canon: @MelodicCanon) -> Motif {
    let mut degrees: Array<i32> = ArrayTrait::new();
    let ld = *canon.leader_degrees;
    let mut i: u32 = 0;
    loop {
        if i >= ld.len() {
            break;
        }
        degrees.append(*ld.at(i));
        i += 1;
    };
    Motif { degrees, octave: *canon.octave, world_mask: 0 }
}

// ──────────────────────────────────────────────────────────
// Seed → program
// ──────────────────────────────────────────────────────────

fn decode_op_kind(raw: u32) -> u32 {
    raw % 12
}

fn push_op(ref ops: Array<MotifOp>, op: MotifOp) {
    ops.append(op);
}

pub fn program_from_seed(seed: felt252, max_ops: u32) -> MotifProgram {
    let s = seed_u256(seed);
    let mut ops: Array<MotifOp> = ArrayTrait::new();
    let cap = if max_ops == 0 {
        4_u32
    } else if max_ops > 8 {
        8_u32
    } else {
        max_ops
    };
    let mut i: u32 = 0;
    loop {
        if i >= cap {
            break;
        }
        let shift = 8 + i * 16;
        let raw = extract_bits(s, shift, 16);
        let kind = decode_op_kind(raw);
        if kind == 0 {
            let n: i32 = (extract_bits(s, shift + 4, 6) % 7).try_into().unwrap();
            let signed = if extract_bits(s, shift + 10, 1) == 0 {
                n
            } else {
                -n
            };
            push_op(ref ops, MotifOp::Transpose(signed));
        } else if kind == 1 {
            let axis: i32 = (extract_bits(s, shift + 4, 5)).try_into().unwrap();
            push_op(ref ops, MotifOp::Invert(axis));
        } else if kind == 2 {
            push_op(ref ops, MotifOp::Retrograde(()));
        } else if kind == 3 {
            let axis: i32 = (extract_bits(s, shift + 4, 5)).try_into().unwrap();
            push_op(ref ops, MotifOp::RetrogradeInvert(axis));
        } else if kind == 4 {
            let k = extract_bits(s, shift + 4, 3) + 1;
            push_op(ref ops, MotifOp::Augment(k));
        } else if kind == 5 {
            let k = extract_bits(s, shift + 4, 3) + 1;
            push_op(ref ops, MotifOp::Diminish(k));
        } else if kind == 6 {
            let start = extract_bits(s, shift + 4, 4);
            let len = extract_bits(s, shift + 8, 4) + 1;
            push_op(
                ref ops,
                MotifOp::Fragment(FragmentOp { start, len }),
            );
        } else if kind == 7 {
            let step: i32 = (extract_bits(s, shift + 4, 5) % 5).try_into().unwrap();
            let count = extract_bits(s, shift + 9, 3) + 1;
            push_op(
                ref ops,
                MotifOp::Sequence(SequenceOp { step, count }),
            );
        } else if kind == 8 {
            let r = extract_bits(s, shift + 4, 4) + 1;
            push_op(ref ops, MotifOp::Rotate(r));
        } else if kind == 9 {
            let index = extract_bits(s, shift + 4, 4);
            let reps = extract_bits(s, shift + 8, 3) + 1;
            push_op(
                ref ops,
                MotifOp::Stutter(StutterOp { index, reps }),
            );
        } else if kind == 10 {
            let min_step = extract_bits(s, shift + 4, 3) + 1;
            push_op(ref ops, MotifOp::Interpolate(min_step));
        } else {
            let num: i32 = (extract_bits(s, shift + 4, 4) + 1).try_into().unwrap();
            let den: i32 = (extract_bits(s, shift + 8, 4) + 1).try_into().unwrap();
            push_op(
                ref ops,
                MotifOp::IntervalScale(IntervalScaleOp { num, den }),
            );
        }
        i += 1;
    };
    MotifProgram { ops }
}

// ──────────────────────────────────────────────────────────
// Hand-off to canon / MIDI
// ──────────────────────────────────────────────────────────

pub fn developed_as_canon_leader(m: @DevelopedMotif) -> Span<i32> {
    m.degrees.span()
}

/// Recompute melodic steps from a degree sequence (length = degrees.len() − 1).
pub fn leader_steps_from_degrees(degrees: Span<i32>) -> Array<i32> {
    let mut steps: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 1;
    loop {
        if i >= degrees.len() {
            break;
        }
        steps.append(*degrees.at(i) - *degrees.at(i - 1));
        i += 1;
    };
    steps
}

fn canon_with_octave(base: MelodicCanon, octave: u32) -> MelodicCanon {
    MelodicCanon {
        config_id: base.config_id,
        config_name: base.config_name,
        offsets: base.offsets,
        leader_degrees: base.leader_degrees,
        leader_steps: base.leader_steps,
        mode_id: base.mode_id,
        tonic_keynum: base.tonic_keynum,
        time_unit: base.time_unit,
        voices: base.voices,
        octave,
        profile_id: base.profile_id,
    }
}

/// Build a multi-voice `MelodicCanon` from a developed motif leader. Asserts imitation + consonance.
pub fn build_canon_from_developed(
    developed: @DevelopedMotif, config_id: u32, mode_id: u8,
) -> MelodicCanon {
    let config = config_by_id(config_id);
    let degrees = developed_as_canon_leader(developed);
    let base = build_canon_for_test(
        config.config_id, config.name, config.offsets, degrees, mode_id,
    );
    let canon = canon_with_octave(base, *developed.octave);
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_consonant(@canon), 'canon not consonant');
    canon
}

/// Developed leader + dense Montanos subdivision plan (same policy as jazz long demos).
pub fn generate_ornamented_canon_from_developed(
    seed: felt252,
    config_id: u32,
    developed: @DevelopedMotif,
    mode_id: u8,
) -> (MelodicCanon, Array<u32>) {
    let canon = build_canon_from_developed(developed, config_id, mode_id);
    let s = seed_u256(seed);
    let mut orn_seed = extract_bits(s, 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions_dense(orn_seed, canon.leader_steps, CADENCE_LEN);
    (canon, subs)
}

/// Solo ornamented line: one-voice Montanos subdivisions over a developed motif.
pub fn developed_to_ornamented_note_events(
    developed: @DevelopedMotif,
    ornament_seed: u32,
    mode_id: u8,
    fill_mode: u8,
) -> Array<NoteEvent> {
    let degrees = developed_as_canon_leader(developed);
    let solo_offsets = array![0_i32].span();
    let base = build_canon_for_test(0, 'developed_solo', solo_offsets, degrees, mode_id);
    let canon = canon_with_octave(base, *developed.octave);
    let mut orn = ornament_seed % 256;
    if orn == 0 {
        orn = 19;
    }
    let subs = plan_ornament_subdivisions_dense(orn, canon.leader_steps, CADENCE_LEN);
    canon_to_ornamented_note_events_with_fill(@canon, subs.span(), fill_mode)
}

/// Long-demo developed line: lift a consonant cantus (28 steps), fragment to 24, augment rhythm ×2.
pub fn long_demo_developed_motif() -> DevelopedMotif {
    let seed: felt252 = 4242;
    let canon = generate_melodic_canon_with_params(seed, 0, 32);
    let theme = motif_from_canon_leader(@canon);
    let len: u32 = 24;
    let mut durs: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= 32 {
            break;
        }
        durs.append(4);
        i += 1;
    };
    let mut ops: Array<MotifOp> = ArrayTrait::new();
    ops.append(MotifOp::Fragment(FragmentOp { start: 0, len: len }));
    ops.append(MotifOp::Augment(2));
    apply_program(@theme, @durs, MotifProgram { ops })
}

pub fn developed_to_note_events(
    m: @DevelopedMotif, tonic_keynum: u8, mode_id: u8,
) -> Array<NoteEvent> {
    let n = m.degrees.len();
    if n == 0 {
        return ArrayTrait::new();
    }
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut time: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let degree = *m.degrees.at(i);
        let dur = if m.durations.len() > 0 {
            *m.durations.at(i % m.durations.len())
        } else {
            1_u32
        };
        out.append(
            NoteEvent {
                time,
                duration: dur,
                pitch: realize_degree(*m.octave, degree, tonic_keynum, mode_id),
                velocity: 90,
                voice_id: 0,
            },
        );
        time += dur;
        i += 1;
    };
    out
}

pub fn generate_developed_line(seed: felt252) -> DevelopedMotif {
    let s = seed_u256(seed);
    let theme_id = extract_bits(s, 0, 4);
    let theme = grundgestalt_theme(theme_id);
    let program = program_from_seed(seed, 5);
    apply_program(@theme, @array![1_u32, 1, 1, 1, 1, 1], program)
}

// ──────────────────────────────────────────────────────────
// Validators
// ──────────────────────────────────────────────────────────

pub fn motif_in_world(m: @DevelopedMotif) -> bool {
    if *m.world_mask == 0 {
        return true;
    }
    let mut i: u32 = 0;
    loop {
        if i >= m.degrees.len() {
            break true;
        }
        let pc = degree_to_pc(
            *m.degrees.at(i), *m.octave, DEFAULT_TONIC, DEFAULT_MODE,
        );
        if !has_pitch(*m.world_mask, pc) {
            break false;
        }
        i += 1;
    }
}

pub fn op_laws_hold() -> bool {
    let xs = array![0_i32, 2, 4, 5, 7].span();
    let axis: i32 = 2;

    let rev = reverse_i32(xs);
    let rev2 = reverse_i32(rev.span());
    if !arrays_equal_i32(rev2.span(), xs) {
        return false;
    }

    let inv = invert_i32(xs, axis);
    let inv2 = invert_i32(inv.span(), axis);
    if !arrays_equal_i32(inv2.span(), xs) {
        return false;
    }

    let t2 = transpose_i32(xs, 2);
    let t3 = transpose_i32(t2.span(), 3);
    let t5 = transpose_i32(xs, 5);
    if !arrays_equal_i32(t3.span(), t5.span()) {
        return false;
    }

    let t0 = transpose_i32(xs, 0);
    if !arrays_equal_i32(t0.span(), xs) {
        return false;
    }

    let ri = reverse_i32(invert_i32(xs, axis).span());
    let ri2 = reverse_i32(invert_i32(ri.span(), axis).span());
    if !arrays_equal_i32(ri2.span(), xs) {
        return false;
    }

    true
}

pub fn motif_ops_total() -> bool {
    let theme = grundgestalt_theme(0);
    let durs = array![1_u32, 1, 1, 1];
    let _ = apply_op(@theme, @durs, MotifOp::Fragment(FragmentOp { start: 99, len: 0 }));
    let _ = apply_op(@theme, @durs, MotifOp::Diminish(0));
    let _ = apply_op(@theme, @durs, MotifOp::Stutter(StutterOp { index: 99, reps: 0 }));
    let _ = apply_op(
        @theme,
        @durs,
        MotifOp::IntervalScale(IntervalScaleOp { num: 2, den: 0 }),
    );
    true
}

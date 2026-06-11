//! Form-level extensions to the motif development algebra.
//!
//! Two additions grounded in the research:
//!   1. `weighted_program_from_seed` — biases op selection toward developing-variation
//!      order (Schoenberg / MeloForm use *musically plausible probabilities*, not uniform).
//!   2. `develop_period` — arranges developed fragments into a hierarchical AABA period,
//!      the structural level MeloForm adds above flat motif-op application.
//!
//! Depends on the existing motif algebra module (Motif, MotifOp, MotifProgram,
//! DevelopedMotif, apply_program, motif_to_developed, concat helpers, seed helpers).

use core::array::ArrayTrait;
use koji::composition::motif_algebra::{
    DevelopedMotif, FragmentOp, Motif, MotifOp, MotifProgram, SequenceOp,
    apply_program, motif_from_degrees,
};

// ──────────────────────────────────────────────────────────
// Local copies of the seed/bit helpers (kept private in the algebra module).
// If you make those `pub`, delete these and import instead.
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
// Weighted op selection
// ──────────────────────────────────────────────────────────

/// Cumulative-weight table over the 13 ops, indexed the same as `decode_op_kind`'s
/// 0..12 space plus Concat at 12 (Concat omitted from auto-generation — it needs a
/// payload). Weights encode developing-variation practice: transposition, sequence,
/// and fragmentation dominate; inversion/retrograde are rarer "answering" gestures.
///
/// Returns (kind, ()) where kind is the chosen op index 0..11.
pub fn weighted_kind(raw: u32, phase: u32) -> u32 {
    // Two phase profiles. Early phase (phase==0): statement/spinning-out — favor
    // transpose(0), sequence(7), fragment(6), stutter(9). Late phase (phase==1):
    // answering/contrast — raise invert(1), retrograde(2), retrograde-invert(3).
    //
    // Weights are small integers; we build a cumulative table and pick by `raw % total`.
    let w_transpose = if phase == 0 { 6_u32 } else { 3 };
    let w_invert = if phase == 0 { 1_u32 } else { 4 };
    let w_retro = if phase == 0 { 1_u32 } else { 3 };
    let w_retroinv = if phase == 0 { 1_u32 } else { 3 };
    let w_augment = 2_u32;
    let w_diminish = 2_u32;
    let w_fragment = if phase == 0 { 4_u32 } else { 2 };
    let w_sequence = if phase == 0 { 5_u32 } else { 2 };
    let w_rotate = 2_u32;
    let w_stutter = if phase == 0 { 3_u32 } else { 1 };
    let w_interp = 2_u32;
    let w_iscale = 2_u32;

    let mut cum = ArrayTrait::new();
    let mut total: u32 = 0;
    total += w_transpose;
    cum.append(total); // 0
    total += w_invert;
    cum.append(total); // 1
    total += w_retro;
    cum.append(total); // 2
    total += w_retroinv;
    cum.append(total); // 3
    total += w_augment;
    cum.append(total); // 4
    total += w_diminish;
    cum.append(total); // 5
    total += w_fragment;
    cum.append(total); // 6
    total += w_sequence;
    cum.append(total); // 7
    total += w_rotate;
    cum.append(total); // 8
    total += w_stutter;
    cum.append(total); // 9
    total += w_interp;
    cum.append(total); // 10
    total += w_iscale;
    cum.append(total); // 11

    let pick = raw % total;
    let mut k: u32 = 0;
    loop {
        if k >= cum.len() {
            break;
        }
        if pick < *cum.at(k) {
            break;
        }
        k += 1;
    };
    k
}

/// Same windowed-bit decoding as `program_from_seed`, but op KIND is chosen from
/// the weighted table and the first/second halves of the program use early/late
/// phase profiles (statement then answer). Concat is never auto-emitted.
pub fn weighted_program_from_seed(seed: felt252, max_ops: u32) -> MotifProgram {
    let s = seed_u256(seed);
    let mut ops: Array<MotifOp> = ArrayTrait::new();
    let cap = if max_ops == 0 {
        6_u32
    } else if max_ops > 8 {
        8_u32
    } else {
        max_ops
    };
    let half = cap / 2;
    let mut i: u32 = 0;
    loop {
        if i >= cap {
            break;
        }
        let shift = 8 + i * 16;
        let raw = extract_bits(s, shift, 16);
        let phase = if i < half {
            0_u32
        } else {
            1_u32
        };
        let kind = weighted_kind(raw, phase);

        if kind == 0 {
            let n: i32 = (extract_bits(s, shift + 4, 6) % 7).try_into().unwrap();
            let signed = if extract_bits(s, shift + 10, 1) == 0 {
                n
            } else {
                -n
            };
            ops.append(MotifOp::Transpose(signed));
        } else if kind == 1 {
            let axis: i32 = (extract_bits(s, shift + 4, 5)).try_into().unwrap();
            ops.append(MotifOp::Invert(axis));
        } else if kind == 2 {
            ops.append(MotifOp::Retrograde(()));
        } else if kind == 3 {
            let axis: i32 = (extract_bits(s, shift + 4, 5)).try_into().unwrap();
            ops.append(MotifOp::RetrogradeInvert(axis));
        } else if kind == 4 {
            let k = extract_bits(s, shift + 4, 3) + 1;
            ops.append(MotifOp::Augment(k));
        } else if kind == 5 {
            let k = extract_bits(s, shift + 4, 3) + 1;
            ops.append(MotifOp::Diminish(k));
        } else if kind == 6 {
            let start = extract_bits(s, shift + 4, 4);
            let len = extract_bits(s, shift + 8, 4) + 1;
            ops.append(MotifOp::Fragment(FragmentOp { start, len }));
        } else if kind == 7 {
            let step: i32 = (extract_bits(s, shift + 4, 5) % 5).try_into().unwrap();
            let count = extract_bits(s, shift + 9, 3) + 1;
            ops.append(MotifOp::Sequence(SequenceOp { step, count }));
        } else if kind == 8 {
            let r = extract_bits(s, shift + 4, 4) + 1;
            ops.append(MotifOp::Rotate(r));
        } else if kind == 9 {
            let index = extract_bits(s, shift + 4, 4);
            let reps = extract_bits(s, shift + 8, 3) + 1;
            ops.append(MotifOp::Stutter(crate_stutter(index, reps)));
        } else if kind == 10 {
            let min_step = extract_bits(s, shift + 4, 3) + 1;
            ops.append(MotifOp::Interpolate(min_step));
        } else {
            let num: i32 = (extract_bits(s, shift + 4, 4) + 1).try_into().unwrap();
            let den: i32 = (extract_bits(s, shift + 8, 4) + 1).try_into().unwrap();
            ops.append(MotifOp::IntervalScale(crate_iscale(num, den)));
        }
        i += 1;
    };
    MotifProgram { ops }
}

// Tiny constructors so this file doesn't need to import the op-payload structs by
// value in match arms. Replace with direct struct literals if you prefer.
use koji::composition::motif_algebra::{IntervalScaleOp, StutterOp};

fn crate_stutter(index: u32, reps: u32) -> StutterOp {
    StutterOp { index, reps }
}

fn crate_iscale(num: i32, den: i32) -> IntervalScaleOp {
    IntervalScaleOp { num, den }
}

// ──────────────────────────────────────────────────────────
// Hierarchical form: AABA period
// ──────────────────────────────────────────────────────────

fn concat_i32_local(a: Span<i32>, b: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
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

fn concat_u32_local(a: Span<u32>, b: Span<u32>) -> Array<u32> {
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

fn append_developed(acc: DevelopedMotif, next: @DevelopedMotif) -> DevelopedMotif {
    DevelopedMotif {
        degrees: concat_i32_local(acc.degrees.span(), next.degrees.span()),
        durations: concat_u32_local(acc.durations.span(), next.durations.span()),
        octave: acc.octave,
        world_mask: acc.world_mask,
    }
}

/// Build an AABA period from one theme. The A sections share an identical
/// development (literal repetition — the structural backbone), and B is a
/// contrasting development driven by a perturbed seed. This is the hierarchical
/// layer MeloForm adds above flat op application: a motif becomes a phrase, and
/// phrases are arranged into a form with repetition + contrast.
///
/// `a_ops` develops the A material; B uses `weighted_program_from_seed(seed ^ salt)`
/// in late-phase-heavy form so it reads as an answer, not a restatement.
pub const B_SALT: felt252 = 0x9E3779B9;

pub fn develop_period(
    theme: @Motif, durations: @Array<u32>, seed: felt252, max_ops: u32,
) -> DevelopedMotif {
    // A: statement development.
    let a_program = weighted_program_from_seed(seed, max_ops);
    let a = apply_program(theme, durations, a_program);

    // B: contrasting development from a perturbed seed.
    let b_seed = seed + B_SALT;
    let b_program = weighted_program_from_seed(b_seed, max_ops);
    let b = apply_program(theme, durations, b_program);

    // Assemble A A B A. Each section is independently developed; the A's are
    // identical (true repetition), B contrasts, final A returns home.
    let a1 = a;
    let a2_src = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    let acc = append_developed(a1, @a2_src);
    let acc = append_developed(acc, @b);

    let a4_src = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    append_developed(acc, @a4_src)
}

// ──────────────────────────────────────────────────────────
// Smoke checks (call from a #[test], or inline-assert during bring-up)
// ──────────────────────────────────────────────────────────

/// Period length must equal 3 × |A| + |B|.
pub fn period_length_consistent(seed: felt252) -> bool {
    let theme = motif_from_degrees(array![0_i32, 2, 1, 4], 7, 0);
    let durs = array![1_u32, 1, 1, 1];
    let a = apply_program(@theme, @durs, weighted_program_from_seed(seed, 4));
    let b = apply_program(@theme, @durs, weighted_program_from_seed(seed + B_SALT, 4));
    let period = develop_period(@theme, @durs, seed, 4);
    period.degrees.len() == a.degrees.len() * 3 + b.degrees.len()
}

//! Opusmodus-style transformation combinator library over parameter planes.
//! Generic list algebra for pitch / length / velocity / articulation sequences.

use core::array::ArrayTrait;
use koji::composition::melodic_canon::{NoteEvent, realize_degree};
use koji::lcg::{LCG, RNGTrait};
use koji::rng::{bounded, RandomSource};

// ──────────────────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────────────────

/// Parallel parameter planes for a musical object.
#[derive(Drop, Serde)]
pub struct MusicalObject {
    pub pitches: Array<i32>,
    pub lengths: Array<u32>,
    pub velocities: Array<u8>,
    pub articulations: Array<u8>,
    /// 7 (diatonic) or 12 (chromatic); used by pitch-aware verbs.
    pub octave: u32,
}

#[derive(Copy, Drop, Serde)]
pub struct U32Pair {
    pub a: u32,
    pub b: u32,
}

#[derive(Copy, Drop, Serde)]
pub struct I32Pair {
    pub lo: i32,
    pub hi: i32,
}

#[derive(Copy, Drop, Serde)]
pub struct EveryNthOp {
    pub n: u32,
    pub delta: i32,
}

#[derive(Copy, Drop, Serde)]
pub struct ScaleOp {
    pub num: i32,
    pub den: i32,
}

#[derive(Copy, Drop, Serde)]
pub enum Selector {
    All: (),
    EveryNth: u32,
    Range: U32Pair,
    Mask: u32,
    ValueIn: I32Pair,
}

#[derive(Drop, Serde)]
pub enum PlaneOp {
    Rotate: i32,
    Reverse: (),
    Palindrome: (),
    Permute: Array<u32>,
    Transpose: i32,
    Invert: i32,
    IntervalInvert: (),
    Ambitus: I32Pair,
    Take: u32,
    Drop: u32,
    Span: U32Pair,
    EveryNth: EveryNthOp,
    MapAdd: Array<i32>,
    MapScale: ScaleOp,
    MapByPosition: Array<i32>,
    Augment: u32,
    Diminish: u32,
    Repeat: u32,
    Trim: u32,
    Concat: Array<i32>,
    Interleave: Array<i32>,
}

#[derive(Copy, Drop, Serde)]
pub enum PlaneId {
    Pitch,
    Length,
    Velocity,
    Articulation,
}

#[derive(Drop, Serde)]
pub struct Pipeline {
    pub ops: Array<PlaneOp>,
}

// ──────────────────────────────────────────────────────────
// Seed helpers
// ──────────────────────────────────────────────────────────

fn seed_u256(seed: felt252) -> u256 {
    seed.into()
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
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
    let v = (s / p) % w;
    v.try_into().unwrap()
}

fn lcg_from_seed(seed: felt252) -> LCG {
    let s = seed_u256(seed);
    let state = extract_bits(s, 0, 32) % 256;
    LCG {
        state: if state == 0 {
            1
        } else {
            state
        },
        multiplier: 5,
        increment: 3,
        modulus: 256,
    }
}

// ──────────────────────────────────────────────────────────
// Internal helpers
// ──────────────────────────────────────────────────────────

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

fn normalize_rotate(n: i32, len: u32) -> u32 {
    if len == 0 {
        return 0;
    }
    let len_i: i32 = len.try_into().unwrap();
    let mut k = n % len_i;
    if k < 0 {
        k += len_i;
    }
    k.try_into().unwrap()
}

fn matches_selector(sel: Selector, pos: u32, val: i32) -> bool {
    match sel {
        Selector::All(_) => true,
        Selector::EveryNth(n) => {
            if n == 0 {
                true
            } else {
                pos % n == 0
            }
        },
        Selector::Range(r) => pos >= r.a && pos < r.b,
        Selector::Mask(m) => {
            let bit: u32 = pow2(pos);
            m & bit != 0
        },
        Selector::ValueIn(v) => val >= v.lo && val <= v.hi,
    }
}

fn pow2(p: u32) -> u32 {
    let mut r: u32 = 1;
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

fn apply_scalar_op(v: i32, op: @PlaneOp) -> i32 {
    match op {
        PlaneOp::Transpose(n) => v + *n,
        PlaneOp::Invert(axis) => 2 * *axis - v,
        PlaneOp::EveryNth(en) => v + *en.delta,
        PlaneOp::MapAdd(deltas) => {
            if deltas.len() == 0 {
                v
            } else {
                v + *deltas.at(0)
            }
        },
        PlaneOp::MapScale(scale) => {
            if *scale.den == 0 {
                v
            } else {
                v * *scale.num / *scale.den
            }
        },
        _ => v,
    }
}

fn fold_into_ambitus(v: i32, lo: i32, hi: i32, octave: u32) -> i32 {
    if lo > hi {
        return fold_into_ambitus(v, hi, lo, octave);
    }
    let oct: i32 = if octave == 12 {
        12
    } else {
        7
    };
    let span: i32 = hi - lo + 1;
    if span <= 0 {
        return v;
    }
    if span <= oct {
        let offset = v - lo;
        let mut m = offset % span;
        if m < 0 {
            m += span;
        }
        return lo + m;
    }
    let mut x = v;
    let mut guard: u32 = 0;
    loop {
        if x >= lo && x <= hi {
            break x;
        }
        if guard >= 32 {
            if x < lo {
                break lo;
            }
            break hi;
        }
        if x > hi {
            x -= oct;
        } else {
            x += oct;
        }
        guard += 1;
    }
}

fn u32_plane_to_i32(xs: @Array<u32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append((*xs.at(i)).try_into().unwrap());
        i += 1;
    };
    out
}

fn i32_plane_to_u32(xs: @Array<i32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        let v = *xs.at(i);
        if v < 0 {
            out.append(0);
        } else {
            out.append(v.try_into().unwrap());
        }
        i += 1;
    };
    out
}

fn u8_plane_to_i32(xs: @Array<u8>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append((*xs.at(i)).into());
        i += 1;
    };
    out
}

fn i32_plane_to_u8(xs: @Array<i32>) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        let mut v = *xs.at(i);
        if v < 1 {
            v = 1;
        }
        if v > 127 {
            v = 127;
        }
        out.append(v.try_into().unwrap());
        i += 1;
    };
    out
}

fn plane_at_i32(plane: Span<i32>, idx: u32) -> i32 {
    if plane.len() == 0 {
        0
    } else {
        *plane.at(idx % plane.len())
    }
}

fn plane_at_u32(plane: Span<u32>, idx: u32) -> u32 {
    if plane.len() == 0 {
        0
    } else {
        *plane.at(idx % plane.len())
    }
}

fn plane_at_u8(plane: Span<u8>, idx: u32) -> u8 {
    if plane.len() == 0 {
        0
    } else {
        *plane.at(idx % plane.len())
    }
}

pub fn arrays_equal_i32(a: Span<i32>, b: Span<i32>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break true;
        }
        if *a.at(i) != *b.at(i) {
            break false;
        }
        i += 1;
    }
}

// ──────────────────────────────────────────────────────────
// Layer 1 — generic i32 combinators
// ──────────────────────────────────────────────────────────

pub fn rotate_i32(xs: Span<i32>, n: i32) -> Array<i32> {
    let len = xs.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let k = normalize_rotate(n, len);
    let mut out: Array<i32> = ArrayTrait::new();
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

pub fn reverse_i32(xs: Span<i32>) -> Array<i32> {
    let len = xs.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let mut out: Array<i32> = ArrayTrait::new();
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

pub fn palindrome_i32(xs: Span<i32>, keep_pivot: bool) -> Array<i32> {
    let mut out = clone_i32(xs);
    let len = xs.len();
    if len == 0 {
        return out;
    }
    let start = if keep_pivot {
        1_u32
    } else {
        0_u32
    };
    let mut i: u32 = start;
    loop {
        if i >= len {
            break;
        }
        out.append(*xs.at(len - 1 - i));
        i += 1;
    };
    out
}

pub fn permute_i32(xs: Span<i32>, perm: Span<u32>) -> Array<i32> {
    let len = xs.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let plen = perm.len();
    if plen == 0 {
        return clone_i32(xs);
    }
    let mut i: u32 = 0;
    loop {
        if i >= plen {
            break;
        }
        let src = *perm.at(i) % len;
        out.append(*xs.at(src));
        i += 1;
    };
    out
}

pub fn transpose_i32(xs: Span<i32>, n: i32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*xs.at(i) + n);
        i += 1;
    };
    out
}

pub fn invert_i32(xs: Span<i32>, axis: i32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(2 * axis - *xs.at(i));
        i += 1;
    };
    out
}

pub fn interval_invert_i32(xs: Span<i32>) -> Array<i32> {
    let len = xs.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let mut out: Array<i32> = ArrayTrait::new();
    out.append(*xs.at(0));
    if len == 1 {
        return out;
    }
    let mut i: u32 = 1;
    loop {
        if i >= len {
            break;
        }
        let cur = *xs.at(i);
        let prior = *xs.at(i - 1);
        out.append(2 * prior - cur);
        i += 1;
    };
    out
}

pub fn ambitus_i32(xs: Span<i32>, lo: i32, hi: i32, octave: u32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(fold_into_ambitus(*xs.at(i), lo, hi, octave));
        i += 1;
    };
    out
}

pub fn take_i32(xs: Span<i32>, k: u32) -> Array<i32> {
    let len = xs.len();
    let mut n = k;
    if n > len {
        n = len;
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        out.append(*xs.at(i));
        i += 1;
    };
    out
}

pub fn drop_i32(xs: Span<i32>, k: u32) -> Array<i32> {
    let len = xs.len();
    let mut start = k;
    if start > len {
        start = len;
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = start;
    loop {
        if i >= len {
            break;
        }
        out.append(*xs.at(i));
        i += 1;
    };
    out
}

pub fn span_i32(xs: Span<i32>, a: u32, b: u32) -> Array<i32> {
    let len = xs.len();
    let mut start = a;
    let mut end = b;
    if start > len {
        start = len;
    }
    if end > len {
        end = len;
    }
    if end < start {
        end = start;
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = start;
    loop {
        if i >= end {
            break;
        }
        out.append(*xs.at(i));
        i += 1;
    };
    out
}

pub fn interleave_i32(a: Span<i32>, b: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let alen = a.len();
    let blen = b.len();
    let max = if alen > blen {
        alen
    } else {
        blen
    };
    let mut i: u32 = 0;
    loop {
        if i >= max {
            break;
        }
        if i < alen {
            out.append(*a.at(i));
        }
        if i < blen {
            out.append(*b.at(i));
        }
        i += 1;
    };
    out
}

pub fn concat_i32(a: Span<i32>, b: Span<i32>) -> Array<i32> {
    let mut out = clone_i32(a);
    let mut i: u32 = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

pub fn map_add_i32(xs: Span<i32>, deltas: Span<i32>) -> Array<i32> {
    let dlen = deltas.len();
    if dlen == 0 {
        return clone_i32(xs);
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*xs.at(i) + *deltas.at(i % dlen));
        i += 1;
    };
    out
}

pub fn map_scale_i32(xs: Span<i32>, num: i32, den: i32) -> Array<i32> {
    if den == 0 {
        return clone_i32(xs);
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*xs.at(i) * num / den);
        i += 1;
    };
    out
}

pub fn map_by_position_i32(xs: Span<i32>, table: Span<i32>) -> Array<i32> {
    let tlen = table.len();
    if tlen == 0 {
        return clone_i32(xs);
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*table.at(i % tlen));
        i += 1;
    };
    out
}

pub fn augment_u32(xs: Span<u32>, k: u32) -> Array<u32> {
    if k == 0 {
        return clone_u32(xs);
    }
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        out.append(*xs.at(i) * k);
        i += 1;
    };
    out
}

pub fn diminish_u32(xs: Span<u32>, k: u32) -> Array<u32> {
    if k == 0 {
        return clone_u32(xs);
    }
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        let v = *xs.at(i);
        if v % k == 0 {
            out.append(v / k);
        } else {
            out.append(v);
        }
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

pub fn repeat_i32(xs: Span<i32>, k: u32) -> Array<i32> {
    if k == 0 || xs.len() == 0 {
        return ArrayTrait::new();
    }
    let mut out: Array<i32> = ArrayTrait::new();
    let mut rep: u32 = 0;
    loop {
        if rep >= k {
            break;
        }
        let mut i: u32 = 0;
        loop {
            if i >= xs.len() {
                break;
            }
            out.append(*xs.at(i));
            i += 1;
        };
        rep += 1;
    };
    out
}

pub fn trim_i32(xs: Span<i32>, len: u32) -> Array<i32> {
    take_i32(xs, len)
}

pub fn divide_i32(xs: Span<i32>, k: u32) -> Array<Array<i32>> {
    let mut groups: Array<Array<i32>> = ArrayTrait::new();
    if k == 0 || xs.len() == 0 {
        return groups;
    }
    let mut group: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        group.append(*xs.at(i));
        if group.len() == k {
            groups.append(group);
            group = ArrayTrait::new();
        }
        i += 1;
    };
    if group.len() > 0 {
        groups.append(group);
    }
    groups
}

pub fn flatten_i32(xss: @Array<Array<i32>>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut g: u32 = 0;
    loop {
        if g >= xss.len() {
            break;
        }
        let group = xss.at(g);
        let mut i: u32 = 0;
        loop {
            if i >= group.len() {
                break;
            }
            out.append(*group.at(i));
            i += 1;
        };
        g += 1;
    };
    out
}

pub fn map_where_i32(xs: Span<i32>, sel: Selector, op: @PlaneOp) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        let v = *xs.at(i);
        if matches_selector(sel, i, v) {
            out.append(apply_scalar_op(v, op));
        } else {
            out.append(v);
        }
        i += 1;
    };
    out
}

pub fn filter_where_i32(xs: Span<i32>, sel: Selector) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= xs.len() {
            break;
        }
        let v = *xs.at(i);
        if matches_selector(sel, i, v) {
            out.append(v);
        }
        i += 1;
    };
    out
}

fn array_u32_set(arr: @Array<u32>, idx: u32, val: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= arr.len() {
            break;
        }
        if i == idx {
            out.append(val);
        } else {
            out.append(*arr.at(i));
        }
        i += 1;
    };
    out
}

fn swap_indices(mut indices: Array<u32>, j: u32, k: u32) -> Array<u32> {
    let tmp = *indices.at(j);
    let other = *indices.at(k);
    indices = array_u32_set(@indices, j, other);
    array_u32_set(@indices, k, tmp)
}

pub fn gen_rotate(seed: felt252, xs: Span<i32>) -> Array<i32> {
    let len = xs.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let s = seed_u256(seed);
    let raw = extract_bits(s, 0, 32);
    let n: i32 = bounded(raw, len.try_into().unwrap()).try_into().unwrap();
    rotate_i32(xs, n)
}

pub fn gen_permute(seed: felt252, xs: Span<i32>) -> Array<i32> {
    let len = xs.len();
    if len <= 1 {
        return clone_i32(xs);
    }
    let mut indices: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        indices.append(i);
        i += 1;
    };
    let mut rng = lcg_from_seed(seed);
    let mut j: u32 = len - 1;
    loop {
        if j == 0 {
            break;
        }
        let (raw, next_rng) = rng.draw();
        rng = next_rng;
        let bound = j + 1;
        let k = bounded(raw, bound);
        indices = swap_indices(indices, j, k);
        j -= 1;
    };
    permute_i32(xs, indices.span())
}

// ──────────────────────────────────────────────────────────
// Plane op / pipeline / object
// ──────────────────────────────────────────────────────────

pub fn apply_op(plane: Span<i32>, op: @PlaneOp) -> Array<i32> {
    match op {
        PlaneOp::Rotate(n) => rotate_i32(plane, *n),
        PlaneOp::Reverse(_) => reverse_i32(plane),
        PlaneOp::Palindrome(_) => palindrome_i32(plane, false),
        PlaneOp::Permute(perm) => permute_i32(plane, perm.span()),
        PlaneOp::Transpose(n) => transpose_i32(plane, *n),
        PlaneOp::Invert(axis) => invert_i32(plane, *axis),
        PlaneOp::IntervalInvert(_) => interval_invert_i32(plane),
        PlaneOp::Ambitus(bounds) => ambitus_i32(plane, *bounds.lo, *bounds.hi, 7),
        PlaneOp::Take(k) => take_i32(plane, *k),
        PlaneOp::Drop(k) => drop_i32(plane, *k),
        PlaneOp::Span(bounds) => span_i32(plane, *bounds.a, *bounds.b),
        PlaneOp::EveryNth(en) => {
            map_where_i32(plane, Selector::EveryNth(*en.n), op)
        },
        PlaneOp::MapAdd(deltas) => map_add_i32(plane, deltas.span()),
        PlaneOp::MapScale(scale) => map_scale_i32(plane, *scale.num, *scale.den),
        PlaneOp::MapByPosition(table) => map_by_position_i32(plane, table.span()),
        PlaneOp::Augment(k) => {
            let as_u32 = i32_plane_to_u32(@clone_i32(plane));
            u32_plane_to_i32(@augment_u32(as_u32.span(), *k))
        },
        PlaneOp::Diminish(k) => {
            let as_u32 = i32_plane_to_u32(@clone_i32(plane));
            u32_plane_to_i32(@diminish_u32(as_u32.span(), *k))
        },
        PlaneOp::Repeat(k) => repeat_i32(plane, *k),
        PlaneOp::Trim(len) => trim_i32(plane, *len),
        PlaneOp::Concat(b) => concat_i32(plane, b.span()),
        PlaneOp::Interleave(b) => interleave_i32(plane, b.span()),
    }
}

pub fn apply_pipeline(plane: Span<i32>, pipeline: @Pipeline) -> Array<i32> {
    let mut current = clone_i32(plane);
    let mut i: u32 = 0;
    loop {
        if i >= pipeline.ops.len() {
            break;
        }
        current = apply_op(current.span(), pipeline.ops.at(i));
        i += 1;
    };
    current
}

pub fn apply_to_object(obj: MusicalObject, which: PlaneId, pipeline: @Pipeline) -> MusicalObject {
    let mut pitches = obj.pitches;
    let mut lengths = obj.lengths;
    let mut velocities = obj.velocities;
    let mut articulations = obj.articulations;
    let octave = obj.octave;

    match which {
        PlaneId::Pitch => {
            pitches = apply_pipeline(pitches.span(), pipeline);
        },
        PlaneId::Length => {
            let as_i32 = u32_plane_to_i32(@lengths);
            lengths = i32_plane_to_u32(@apply_pipeline(as_i32.span(), pipeline));
        },
        PlaneId::Velocity => {
            let as_i32 = u8_plane_to_i32(@velocities);
            velocities = i32_plane_to_u8(@apply_pipeline(as_i32.span(), pipeline));
        },
        PlaneId::Articulation => {
            let as_i32 = u8_plane_to_i32(@articulations);
            articulations = i32_plane_to_u8(@apply_pipeline(as_i32.span(), pipeline));
        },
    };

    MusicalObject { pitches, lengths, velocities, articulations, octave }
}

/// Zip parallel planes into `NoteEvent`s. Shorter planes recycle (span semantics).
pub fn assemble(obj: @MusicalObject, voice_id: u32, tonic_keynum: u8, mode_id: u8) -> Array<NoteEvent> {
    let pitch_len = obj.pitches.len();
    let length_len = obj.lengths.len();
    let n = if pitch_len > length_len {
        pitch_len
    } else if length_len > 0 {
        length_len
    } else {
        pitch_len
    };
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
        let degree = plane_at_i32(obj.pitches.span(), i);
        let dur = plane_at_u32(obj.lengths.span(), i);
        let vel = plane_at_u8(obj.velocities.span(), i);
        let pitch = realize_degree(*obj.octave, degree, tonic_keynum, mode_id);
        let velocity = if vel == 0 {
            80_u8
        } else {
            vel
        };
        out.append(
            NoteEvent {
                time,
                duration: dur,
                pitch,
                velocity,
                voice_id,
            },
        );
        time += dur;
        i += 1;
    };
    out
}

/// Re-express pitch-class transposition on u8 planes via generic transpose.
pub fn transpose_pitch_classes_via_i32(pcs: Span<u8>, transposition: u8) -> Array<u8> {
    let mut as_i32: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        as_i32.append((*pcs.at(i)).into());
        i += 1;
    };
    let shifted = transpose_i32(as_i32.span(), transposition.into());
    let mut out: Array<u8> = ArrayTrait::new();
    i = 0;
    loop {
        if i >= shifted.len() {
            break;
        }
        let v = *shifted.at(i);
        out.append((v % 12).try_into().unwrap());
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Validators
// ──────────────────────────────────────────────────────────

pub fn combinator_laws_hold() -> bool {
    let xs = array![0_i32, 1, 2, 3, 4].span();
    let r1 = rotate_i32(xs, 2);
    let r2 = rotate_i32(r1.span(), 3);
    let r_sum = rotate_i32(xs, 5);
    if !arrays_equal_i32(r2.span(), r_sum.span()) {
        return false;
    }
    let r0 = rotate_i32(xs, 0);
    if !arrays_equal_i32(r0.span(), xs) {
        return false;
    }
    let rev = reverse_i32(xs);
    let rev2 = reverse_i32(rev.span());
    if !arrays_equal_i32(rev2.span(), xs) {
        return false;
    }
    let inv = invert_i32(xs, 2);
    let inv2 = invert_i32(inv.span(), 2);
    if !arrays_equal_i32(inv2.span(), xs) {
        return false;
    }
    let f = map_add_i32(xs, array![1_i32].span());
    let g = map_add_i32(f.span(), array![2_i32].span());
    let fg = map_add_i32(xs, array![3_i32].span());
    if !arrays_equal_i32(g.span(), fg.span()) {
        return false;
    }
    let groups = divide_i32(xs, 2);
    let flat = flatten_i32(@groups);
    if !arrays_equal_i32(flat.span(), xs) {
        return false;
    }
    true
}

pub fn pipeline_total(plane: Span<i32>, pipeline: @Pipeline) -> bool {
    let _ = apply_pipeline(plane, pipeline);
    true
}

pub fn edge_cases_total() -> bool {
    let empty = array![].span();
    let _ = rotate_i32(empty, 99);
    let _ = take_i32(empty, 5);
    let _ = diminish_u32(array![7_u32, 5].span(), 2);
    let one = array![42_i32].span();
    let _ = rotate_i32(one, 100);
    let _ = palindrome_i32(one, true);
    let _ = gen_rotate(12345, one);
    let _ = gen_permute(67890, one);
    true
}

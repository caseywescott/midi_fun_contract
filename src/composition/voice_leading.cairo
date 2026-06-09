//! Minimal-motion voice-leading allocator (Viterbi over legal voicings).
//!
//! Given a harmonic timeline (pitch-class target per beat), assigns each voice a keynum
//! sequence that minimizes total L1 motion subject to hard contrapuntal constraints.
//! See `docs/minimal_motion_harmony_spec.md`.

use core::array::ArrayTrait;
use core::traits::{Into, TryInto};
use koji::composition::counterpoint::{
    MotionKind, classify_motion, motion_contour, violates_forbidden_interval,
    would_create_parallel_perfect, would_create_similar_motion_perfect,
};
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::neo_riemannian_harmony::{plr_region_at, plr_triad_pcs};
use koji::lcg::LCG;
use koji::rng::{RandomSource, bounded};

const GOLDEN: u256 = 0x9E3779B9;
const MAX_COST: u32 = 999999999;
const MAX_VOICINGS_PER_BEAT: usize = 128;

/// `bass_pc` / `root_pc` / `top_keynum` unset — free choice in that slot.
pub const FREE_PC: u8 = 255;
pub const FREE_KEYNUM: u8 = 255;

#[derive(Drop)]
pub struct HarmonyTarget {
    pub pcs: Array<u8>,
    pub bass_pc: u8,
    pub root_pc: u8,
    /// When not `FREE_KEYNUM`, the highest voice must sound this exact keynum.
    pub top_keynum: u8,
}

#[derive(Drop)]
pub struct HarmonicTimeline {
    pub targets: Array<HarmonyTarget>,
}

#[derive(Drop)]
pub struct AllocatorParams {
    pub seed: felt252,
    pub num_voices: u32,
    pub register_lo: Array<u8>,
    pub register_hi: Array<u8>,
    pub max_melodic_leap: u8,
    pub allow_crossing: bool,
    pub forbid_parallel_perfects: bool,
    pub forbid_similar_perfects: bool,
    pub w_spacing: u32,
    pub w_double: u32,
    pub w_consonance: u32,
}

#[derive(Drop)]
pub struct AllocationResult {
    pub voices: Array<Array<u8>>,
    pub total_motion: u32,
    pub motion_trace: Array<MotionKind>,
}

fn step_hash(seed: felt252, index: u32) -> u32 {
    let s: u256 = seed.into();
    let i: u256 = index.into();
    let mixed = s + i * GOLDEN;
    let mask: u256 = 0x100000000;
    (mixed % mask).try_into().unwrap()
}

pub fn abs_semitone(a: u8, b: u8) -> u8 {
    if a >= b {
        a - b
    } else {
        b - a
    }
}

fn harmonic_interval_class(a: u8, b: u8) -> u8 {
    abs_semitone(a, b) % 12
}

fn pc_in_set(pc: u8, pcs: Span<u8>) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        if *pcs.at(i) == pc {
            return true;
        }
        i += 1;
    };
    false
}

fn register_at(params: @AllocatorParams, voice: u32) -> (u8, u8) {
    let vi: usize = voice.try_into().unwrap();
    (*params.register_lo.at(vi), *params.register_hi.at(vi))
}

fn voicing_sorted_asc(voicing: Span<u8>) -> bool {
    let mut i: usize = 1;
    loop {
        if i >= voicing.len() {
            break;
        }
        if *voicing.at(i) < *voicing.at(i - 1) {
            return false;
        }
        i += 1;
    };
    true
}

fn voicing_in_registers(voicing: Span<u8>, params: @AllocatorParams) -> bool {
    let mut v: u32 = 0;
    loop {
        if v >= *params.num_voices {
            break;
        }
        let (lo, hi) = register_at(params, v);
        let p = *voicing.at(v.try_into().unwrap());
        if p < lo || p > hi {
            return false;
        }
        v += 1;
    };
    true
}

fn voicing_has_target_pcs(voicing: Span<u8>, pcs: Span<u8>) -> bool {
    let mut need_count = pcs.len();
    if need_count > voicing.len() {
        need_count = voicing.len();
    }
    if need_count == 0 {
        return true;
    }
    let mut covered: usize = 0;
    let mut i: usize = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        let need = *pcs.at(i);
        let mut found = false;
        let mut j: usize = 0;
        loop {
            if j >= voicing.len() {
                break;
            }
            if *voicing.at(j) % 12 == need {
                found = true;
                break;
            }
            j += 1;
        };
        if found {
            covered += 1;
        }
        i += 1;
    };
    covered >= need_count
}

fn verticals_legal(voicing: Span<u8>) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= voicing.len() {
            break;
        }
        let mut j: usize = i + 1;
        loop {
            if j >= voicing.len() {
                break;
            }
            if violates_forbidden_interval(*voicing.at(i), *voicing.at(j)) {
                return false;
            }
            j += 1;
        };
        i += 1;
    };
    true
}

fn bass_pinned_ok(voicing: Span<u8>, bass_pc: u8) -> bool {
    if bass_pc == FREE_PC || voicing.len() == 0 {
        return true;
    }
    let k0 = *voicing.at(0);
    k0 % 12 == bass_pc
}

fn top_pinned_ok(voicing: Span<u8>, top_keynum: u8) -> bool {
    if top_keynum == FREE_KEYNUM || voicing.len() == 0 {
        return true;
    }
    let top = *voicing.at(voicing.len() - 1);
    top == top_keynum
}

fn spacing_penalty(voicing: Span<u8>) -> u32 {
    let mut pen: u32 = 0;
    let mut i: usize = 1;
    loop {
        if i >= voicing.len() {
            break;
        }
        let gap = abs_semitone(*voicing.at(i), *voicing.at(i - 1));
        if gap > 12_u8 {
            pen += (gap - 12_u8).into();
        }
        i += 1;
    };
    pen
}

fn doubling_penalty(voicing: Span<u8>, root_pc: u8) -> u32 {
    let mut pen: u32 = 0;
    if root_pc == FREE_PC {
        return pen;
    }
    let mut doubled_root: u32 = 0;
    let mut v: usize = 0;
    loop {
        if v >= voicing.len() {
            break;
        }
        let kv = *voicing.at(v);
        if kv % 12 == root_pc {
            doubled_root += 1;
        }
        v += 1;
    };
    if doubled_root > 1 {
        pen += (doubled_root - 1) * 5;
    }
    pen
}

fn consonance_bias(voicing: Span<u8>) -> u32 {
    let mut bonus: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= voicing.len() {
            break;
        }
        let mut j: usize = i + 1;
        loop {
            if j >= voicing.len() {
                break;
            }
            let class = harmonic_interval_class(*voicing.at(i), *voicing.at(j));
            if class == 3 || class == 4 || class == 8 || class == 9 {
                bonus += 2;
            }
            j += 1;
        };
        i += 1;
    };
    bonus
}

pub fn node_cost(
    voicing: Span<u8>, root_pc: u8, params: @AllocatorParams,
) -> u32 {
    let mut cost = *params.w_spacing * spacing_penalty(voicing);
    cost += *params.w_double * doubling_penalty(voicing, root_pc);
    if *params.w_consonance > 0 {
        let b = consonance_bias(voicing);
        if cost > b {
            cost -= b;
        } else {
            cost = 0;
        }
    }
    cost
}

fn voicing_passes_filters(
    voicing: Span<u8>,
    pcs: Span<u8>,
    bass_pc: u8,
    top_keynum: u8,
    params: @AllocatorParams,
) -> bool {
    if voicing.len() != (*params.num_voices).try_into().unwrap() {
        return false;
    }
    if !voicing_sorted_asc(voicing) {
        return false;
    }
    if !voicing_in_registers(voicing, params) {
        return false;
    }
    if !voicing_has_target_pcs(voicing, pcs) {
        return false;
    }
    if !verticals_legal(voicing) {
        return false;
    }
    if !bass_pinned_ok(voicing, bass_pc) {
        return false;
    }
    if !top_pinned_ok(voicing, top_keynum) {
        return false;
    }
    true
}

fn enumerate_rec(
    voice: u32,
    partial: Array<u8>,
    pcs: Span<u8>,
    bass_pc: u8,
    top_keynum: u8,
    params: @AllocatorParams,
    ref out: Array<Array<u8>>,
) {
    if out.len() >= MAX_VOICINGS_PER_BEAT {
        return;
    }
    if voice == *params.num_voices {
        if voicing_passes_filters(partial.span(), pcs, bass_pc, top_keynum, params) {
            out.append(partial);
        }
        return;
    }
    let last_voice = voice == *params.num_voices - 1;
    if last_voice && top_keynum != FREE_KEYNUM {
        let (lo, hi) = register_at(params, voice);
        if top_keynum >= lo && top_keynum <= hi && pc_in_set(top_keynum % 12, pcs) {
            let mut next_partial: Array<u8> = ArrayTrait::new();
            let mut pi: usize = 0;
            loop {
                if pi >= partial.len() {
                    break;
                }
                next_partial.append(*partial.at(pi));
                pi += 1;
            };
            next_partial.append(top_keynum);
            if voicing_passes_filters(next_partial.span(), pcs, bass_pc, top_keynum, params) {
                out.append(next_partial);
            }
        }
        return;
    }
    let (lo, hi) = register_at(params, voice);
    let min_key = if voice == 0 {
        lo
    } else {
        let prev = *partial.at((voice - 1).try_into().unwrap());
        if lo > prev {
            lo
        } else {
            prev
        }
    };
    let mut k: u8 = min_key;
    loop {
        if k > hi {
            break;
        }
        if out.len() >= MAX_VOICINGS_PER_BEAT {
            break;
        }
        let pc = k % 12;
        if pc_in_set(pc, pcs) {
            if voice == 0 && bass_pc != FREE_PC && pc != bass_pc {
                k += 1;
                continue;
            }
            let mut next_partial: Array<u8> = ArrayTrait::new();
            let mut pi: usize = 0;
            loop {
                if pi >= partial.len() {
                    break;
                }
                next_partial.append(*partial.at(pi));
                pi += 1;
            };
            next_partial.append(k);
            enumerate_rec(voice + 1, next_partial, pcs, bass_pc, top_keynum, params, ref out);
        }
        k += 1;
    };
}

/// Enumerate legal sorted voicings for one harmonic target.
pub fn enumerate_voicings(target: @HarmonyTarget, params: @AllocatorParams) -> Array<Array<u8>> {
    let mut out: Array<Array<u8>> = ArrayTrait::new();
    let empty: Array<u8> = array![];
    enumerate_rec(
        0,
        empty,
        target.pcs.span(),
        *target.bass_pc,
        *target.top_keynum,
        params,
        ref out,
    );
    out
}

pub fn voicing_distance(prev: Span<u8>, next: Span<u8>, allow_crossing: bool) -> u32 {
    assert(prev.len() == next.len(), 'voicing len');
    if allow_crossing {
        return voicing_distance_matched(prev, next);
    }
    let mut total: u32 = 0;
    let mut v: usize = 0;
    loop {
        if v >= prev.len() {
            break;
        }
        total += abs_semitone(*prev.at(v), *next.at(v)).into();
        v += 1;
    };
    total
}

fn voicing_distance_matched(prev: Span<u8>, next: Span<u8>) -> u32 {
    let n = prev.len();
    if n == 0 {
        return 0;
    }
    if n == 1 {
        return abs_semitone(*prev.at(0), *next.at(0)).into();
    }
    if n == 2 {
        let a0 = abs_semitone(*prev.at(0), *next.at(0)) + abs_semitone(*prev.at(1), *next.at(1));
        let a1 = abs_semitone(*prev.at(0), *next.at(1)) + abs_semitone(*prev.at(1), *next.at(0));
        if a0 <= a1 {
            return a0.into();
        }
        return a1.into();
    }
    if n == 3 {
        return perm3_min_distance(prev, next);
    }
    perm4_min_distance(prev, next)
}

fn perm3_min_distance(prev: Span<u8>, next: Span<u8>) -> u32 {
    let p0 = *prev.at(0);
    let p1 = *prev.at(1);
    let p2 = *prev.at(2);
    let n0 = *next.at(0);
    let n1 = *next.at(1);
    let n2 = *next.at(2);
    let mut best: u32 = MAX_COST;
    best = min_u32(best, dist3(p0, p1, p2, n0, n1, n2));
    best = min_u32(best, dist3(p0, p1, p2, n0, n2, n1));
    best = min_u32(best, dist3(p0, p1, p2, n1, n0, n2));
    best = min_u32(best, dist3(p0, p1, p2, n1, n2, n0));
    best = min_u32(best, dist3(p0, p1, p2, n2, n0, n1));
    best = min_u32(best, dist3(p0, p1, p2, n2, n1, n0));
    best
}

fn dist3(a0: u8, a1: u8, a2: u8, b0: u8, b1: u8, b2: u8) -> u32 {
    abs_semitone(a0, b0).into()
        + abs_semitone(a1, b1).into()
        + abs_semitone(a2, b2).into()
}

fn perm4_min_distance(prev: Span<u8>, next: Span<u8>) -> u32 {
    let p0 = *prev.at(0);
    let p1 = *prev.at(1);
    let p2 = *prev.at(2);
    let p3 = *prev.at(3);
    let n0 = *next.at(0);
    let n1 = *next.at(1);
    let n2 = *next.at(2);
    let n3 = *next.at(3);
    let mut best: u32 = MAX_COST;
    best = min_u32(best, dist4(p0, p1, p2, p3, n0, n1, n2, n3));
    best = min_u32(best, dist4(p0, p1, p2, p3, n0, n1, n3, n2));
    best = min_u32(best, dist4(p0, p1, p2, p3, n0, n2, n1, n3));
    best = min_u32(best, dist4(p0, p1, p2, p3, n0, n2, n3, n1));
    best = min_u32(best, dist4(p0, p1, p2, p3, n0, n3, n1, n2));
    best = min_u32(best, dist4(p0, p1, p2, p3, n0, n3, n2, n1));
    best = min_u32(best, dist4(p0, p1, p2, p3, n1, n0, n2, n3));
    best = min_u32(best, dist4(p0, p1, p2, p3, n1, n0, n3, n2));
    best = min_u32(best, dist4(p0, p1, p2, p3, n1, n2, n0, n3));
    best = min_u32(best, dist4(p0, p1, p2, p3, n1, n2, n3, n0));
    best = min_u32(best, dist4(p0, p1, p2, p3, n1, n3, n0, n2));
    best = min_u32(best, dist4(p0, p1, p2, p3, n1, n3, n2, n0));
    best = min_u32(best, dist4(p0, p1, p2, p3, n2, n0, n1, n3));
    best = min_u32(best, dist4(p0, p1, p2, p3, n2, n0, n3, n1));
    best = min_u32(best, dist4(p0, p1, p2, p3, n2, n1, n0, n3));
    best = min_u32(best, dist4(p0, p1, p2, p3, n2, n1, n3, n0));
    best = min_u32(best, dist4(p0, p1, p2, p3, n2, n3, n0, n1));
    best = min_u32(best, dist4(p0, p1, p2, p3, n2, n3, n1, n0));
    best = min_u32(best, dist4(p0, p1, p2, p3, n3, n0, n1, n2));
    best = min_u32(best, dist4(p0, p1, p2, p3, n3, n0, n2, n1));
    best = min_u32(best, dist4(p0, p1, p2, p3, n3, n1, n0, n2));
    best = min_u32(best, dist4(p0, p1, p2, p3, n3, n1, n2, n0));
    best = min_u32(best, dist4(p0, p1, p2, p3, n3, n2, n0, n1));
    best = min_u32(best, dist4(p0, p1, p2, p3, n3, n2, n1, n0));
    best
}

fn dist4(a0: u8, a1: u8, a2: u8, a3: u8, b0: u8, b1: u8, b2: u8, b3: u8) -> u32 {
    abs_semitone(a0, b0).into()
        + abs_semitone(a1, b1).into()
        + abs_semitone(a2, b2).into()
        + abs_semitone(a3, b3).into()
}

fn min_u32(a: u32, b: u32) -> u32 {
    if a <= b {
        a
    } else {
        b
    }
}

fn pair_transition_legal(
    prev_a: u8, prev_b: u8, next_a: u8, next_b: u8, params: @AllocatorParams,
) -> bool {
    if *params.forbid_parallel_perfects
        && would_create_parallel_perfect(prev_a, prev_b, next_a, next_b) {
        return false;
    }
    if *params.forbid_similar_perfects
        && would_create_similar_motion_perfect(prev_a, prev_b, next_a, next_b) {
        return false;
    }
    true
}

pub fn transition_legal(prev: Span<u8>, next: Span<u8>, params: @AllocatorParams) -> bool {
    if prev.len() != next.len() {
        return false;
    }
    let mut v: usize = 0;
    loop {
        if v >= prev.len() {
            break;
        }
        if abs_semitone(*prev.at(v), *next.at(v)) > *params.max_melodic_leap {
            return false;
        }
        v += 1;
    };
    if !verticals_legal(next) {
        return false;
    }
    let mut i: usize = 0;
    loop {
        if i >= prev.len() {
            break;
        }
        let mut j: usize = i + 1;
        loop {
            if j >= prev.len() {
                break;
            }
            if !pair_transition_legal(
                *prev.at(i), *prev.at(j), *next.at(i), *next.at(j), params,
            ) {
                return false;
            }
            j += 1;
        };
        i += 1;
    };
    true
}

fn build_motion_trace(voices: @Array<Array<u8>>) -> Array<MotionKind> {
    let mut trace: Array<MotionKind> = ArrayTrait::new();
    if voices.len() == 0 {
        return trace;
    }
    let beats = voices.at(0).len();
    if beats < 2 {
        return trace;
    }
    let bass = voices.at(0);
    let tenor = if voices.len() > 1 {
        voices.at(1)
    } else {
        bass
    };
    let mut t: usize = 1;
    loop {
        if t >= beats {
            break;
        }
        let b_motion = motion_contour(*bass.at(t - 1), *bass.at(t));
        let t_motion = motion_contour(*tenor.at(t - 1), *tenor.at(t));
        trace.append(classify_motion(b_motion, t_motion));
        t += 1;
    };
    trace
}

fn voices_from_path(layers: Span<Array<Array<u8>>>, path: Span<u32>) -> Array<Array<u8>> {
    let nv = if layers.len() > 0 {
        layers.at(0).at(0).len()
    } else {
        0
    };
    let mut voices: Array<Array<u8>> = ArrayTrait::new();
    let mut vi: usize = 0;
    loop {
        if vi >= nv {
            break;
        }
        let mut row: Array<u8> = ArrayTrait::new();
        let mut t: usize = 0;
        loop {
            if t >= path.len() {
                break;
            }
            let idx: usize = (*path.at(t)).try_into().unwrap();
            row.append(*layers.at(t).at(idx).at(vi));
            t += 1;
        };
        voices.append(row);
        vi += 1;
    };
    voices
}

pub fn allocate_min_motion(
    timeline: @HarmonicTimeline, params: AllocatorParams,
) -> AllocationResult {
    let t_len = timeline.targets.len();
    assert(t_len > 0, 'empty timeline');
    assert(params.num_voices > 0, 'num voices');
    assert(params.register_lo.len() == params.num_voices.try_into().unwrap(), 'reg lo');
    assert(params.register_hi.len() == params.num_voices.try_into().unwrap(), 'reg hi');

    let mut layers: Array<Array<Array<u8>>> = ArrayTrait::new();
    let first_target = timeline.targets.at(0);
    let v0 = enumerate_voicings(first_target, @params);
    assert(v0.len() > 0, 'no voicings');
    layers.append(v0);

    let mut dp: Array<u32> = ArrayTrait::new();
    let mut back_layers: Array<Array<u32>> = ArrayTrait::new();
    let mut j0: usize = 0;
    loop {
        if j0 >= layers.at(0).len() {
            break;
        }
        let v = layers.at(0).at(j0).span();
        dp.append(node_cost(v, *first_target.root_pc, @params));
        j0 += 1;
    };

    let mut t: usize = 1;
    loop {
        if t >= t_len {
            break;
        }
        let target = timeline.targets.at(t);
        let vt = enumerate_voicings(target, @params);
        assert(vt.len() > 0, 'no voicings t');
        layers.append(vt);

        let prev_layer = layers.at(t - 1);
        let curr_layer = layers.at(t);
        let mut dp_next: Array<u32> = ArrayTrait::new();
        let mut back_t: Array<u32> = ArrayTrait::new();

        let mut j: usize = 0;
        loop {
            if j >= curr_layer.len() {
                break;
            }
            let next_v = curr_layer.at(j).span();
            let ncost = node_cost(next_v, *target.root_pc, @params);
            let mut best_cost: u32 = MAX_COST;
            let mut best_i: u32 = 0;
            let mut best_tie: u32 = MAX_COST;

            let mut i: usize = 0;
            loop {
                if i >= prev_layer.len() {
                    break;
                }
                let prev_v = prev_layer.at(i).span();
                if transition_legal(prev_v, next_v, @params) {
                    let edge = voicing_distance(prev_v, next_v, params.allow_crossing);
                    let total = *dp.at(i) + edge + ncost;
                    let tie_key = bounded(
                        step_hash(params.seed, (t * 1000 + i * 17 + j).try_into().unwrap())
                            + total,
                        1000000,
                    );
                    if total < best_cost || (total == best_cost && tie_key < best_tie) {
                        best_cost = total;
                        best_i = i.try_into().unwrap();
                        best_tie = tie_key;
                    }
                }
                i += 1;
            };
            assert(best_cost < MAX_COST, 'dp dead end');
            dp_next.append(best_cost);
            back_t.append(best_i);
            j += 1;
        };

        back_layers.append(back_t);
        dp = dp_next;
        t += 1;
    };

    let mut best_j: usize = 0;
    let mut best_final: u32 = MAX_COST;
    let mut best_final_tie: u32 = MAX_COST;
    let mut fj: usize = 0;
    loop {
        if fj >= dp.len() {
            break;
        }
        let c = *dp.at(fj);
        let tie_key = bounded(step_hash(params.seed, fj.try_into().unwrap()) + c, 1000000);
        if c < best_final || (c == best_final && tie_key < best_final_tie) {
            best_final = c;
            best_j = fj;
            best_final_tie = tie_key;
        }
        fj += 1;
    };

    let mut path: Array<u32> = ArrayTrait::new();
    let mut idx: usize = best_j;
    let mut ti: usize = t_len;
    loop {
        if ti == 0 {
            break;
        }
        ti -= 1;
        path.append(idx.try_into().unwrap());
        if ti > 0 {
            let back_t = back_layers.at(ti - 1);
            idx = (*back_t.at(idx)).try_into().unwrap();
        }
    };

    let mut path_rev: Array<u32> = ArrayTrait::new();
    let mut pi: usize = path.len();
    loop {
        if pi == 0 {
            break;
        }
        pi -= 1;
        path_rev.append(*path.at(pi));
    };

    let voices = voices_from_path(layers.span(), path_rev.span());
    let total_motion = best_final;
    let motion_trace = build_motion_trace(@voices);

    AllocationResult { voices, total_motion, motion_trace }
}

pub fn harmony_target(pcs: Array<u8>) -> HarmonyTarget {
    HarmonyTarget { pcs, bass_pc: FREE_PC, root_pc: FREE_PC, top_keynum: FREE_KEYNUM }
}

pub fn harmony_target_pinned(pcs: Array<u8>, bass_pc: u8, root_pc: u8) -> HarmonyTarget {
    HarmonyTarget { pcs, bass_pc, root_pc, top_keynum: FREE_KEYNUM }
}

pub fn harmony_target_with_top(pcs: Array<u8>, top_keynum: u8) -> HarmonyTarget {
    let root = if pcs.len() > 0 {
        *pcs.at(0)
    } else {
        FREE_PC
    };
    HarmonyTarget { pcs, bass_pc: FREE_PC, root_pc: root, top_keynum }
}

fn triad_pcs_g_major() -> Array<u8> {
    array![7_u8, 11, 2]
}

fn triad_pcs_d_minor() -> Array<u8> {
    array![2_u8, 5, 9]
}

fn plr_region_step(region: u32, step: u32) -> u32 {
    if step == 0 {
        region
    } else if step == 1 {
        (region + 1) % 4
    } else if step == 2 {
        (region + 3) % 4
    } else {
        (region + 2) % 4
    }
}

/// PLR regions with seeded random walk (not four equal slabs) plus occasional G / Dm color.
pub fn timeline_from_plr_walk(seed: felt252, len: u32) -> HarmonicTimeline {
    let s256: u256 = seed.into();
    let mut state: u32 = (s256 % 256).try_into().unwrap();
    if state == 0 {
        state = 17;
    }
    let mut rng = LCG { state, multiplier: 5, increment: 3, modulus: 256 };
    let mut region: u32 = (s256 % 4).try_into().unwrap();
    let mut targets: Array<HarmonyTarget> = ArrayTrait::new();
    let mut pos: u32 = 0;
    loop {
        if pos >= len {
            break;
        }
        let (raw, next) = rng.draw();
        rng = next;
        let use_color = bounded(raw, 100) < 18;
        if use_color && bounded(raw / 7, 2) == 0 {
            targets.append(harmony_target(triad_pcs_g_major()));
        } else if use_color {
            targets.append(harmony_target(triad_pcs_d_minor()));
        } else {
            let pcs_span = plr_triad_pcs(region);
            let mut arr: Array<u8> = ArrayTrait::new();
            let mut j: usize = 0;
            loop {
                if j >= pcs_span.len() {
                    break;
                }
                arr.append(*pcs_span.at(j));
                j += 1;
            };
            targets.append(harmony_target(arr));
        };
        let (raw2, next2) = rng.draw();
        rng = next2;
        let step = bounded(raw2, 4);
        region = plr_region_step(region, step);
        pos += 1;
    };
    HarmonicTimeline { targets }
}

fn pick_melody_keynum(
    prev: u8, pcs: Span<u8>, lo: u8, hi: u8, prefer_up: bool, raw: u32,
) -> u8 {
    let mut best: u8 = prev;
    let mut best_score: u32 = 999999;
    let mut k: u8 = lo;
    loop {
        if k > hi {
            break;
        }
        if pc_in_set(k % 12, pcs) {
            let dist: u32 = abs_semitone(k, prev).into();
            if dist <= 7 {
                let mut score = dist * 4;
                if dist == 0 {
                    score += 6;
                }
                if prefer_up && k < prev {
                    score += 5;
                }
                if !prefer_up && k > prev {
                    score += 5;
                }
                let tie = bounded(raw + k.into() + dist, 1000);
                let best_tie = bounded(raw + best.into(), 1000);
                if score < best_score || (score == best_score && tie < best_tie) {
                    best_score = score;
                    best = k;
                }
            }
        }
        k += 1;
    };
    best
}

/// PLR walk timeline with a conjunct soprano line pinned per beat.
pub fn timeline_with_melody(
    seed: felt252, len: u32, top_lo: u8, top_hi: u8,
) -> HarmonicTimeline {
    let base = timeline_from_plr_walk(seed, len);
    let s256: u256 = seed.into();
    let mut state: u32 = ((s256 / 65536) % 256).try_into().unwrap();
    if state == 0 {
        state = 41;
    }
    let mut rng = LCG { state, multiplier: 5, increment: 3, modulus: 256 };
    let mut prev: u8 = top_lo;
    loop {
        if prev > top_hi {
            prev = top_lo;
            break;
        }
        if prev % 12 == 0 {
            break;
        }
        prev += 1;
    };
    let mut out: Array<HarmonyTarget> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= base.targets.len() {
            break;
        }
        let t = base.targets.at(i);
        let (raw, next) = rng.draw();
        rng = next;
        let prefer_up = (i < base.targets.len() / 2) || (i % 5 < 3);
        let top = pick_melody_keynum(prev, t.pcs.span(), top_lo, top_hi, prefer_up, raw);
        prev = top;
        let mut pcs_copy: Array<u8> = ArrayTrait::new();
        let mut j: usize = 0;
        loop {
            if j >= t.pcs.len() {
                break;
            }
            pcs_copy.append(*t.pcs.at(j));
            j += 1;
        };
        out.append(harmony_target_with_top(pcs_copy, top));
        i += 1;
    };
    HarmonicTimeline { targets: out }
}

pub fn timeline_from_pc_sets(beats: Span<Span<u8>>) -> HarmonicTimeline {
    let mut targets: Array<HarmonyTarget> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= beats.len() {
            break;
        }
        let pcs = *beats.at(i);
        let mut arr: Array<u8> = ArrayTrait::new();
        let mut j: usize = 0;
        loop {
            if j >= pcs.len() {
                break;
            }
            arr.append(*pcs.at(j));
            j += 1;
        };
        targets.append(harmony_target(arr));
        i += 1;
    };
    HarmonicTimeline { targets }
}

pub fn timeline_from_plr(len: u32) -> HarmonicTimeline {
    let mut targets: Array<HarmonyTarget> = ArrayTrait::new();
    let mut pos: u32 = 0;
    loop {
        if pos >= len {
            break;
        }
        let r = plr_region_at(pos, len);
        let pcs_span = plr_triad_pcs(r);
        let mut arr: Array<u8> = ArrayTrait::new();
        let mut j: usize = 0;
        loop {
            if j >= pcs_span.len() {
                break;
            }
            arr.append(*pcs_span.at(j));
            j += 1;
        };
        targets.append(harmony_target(arr));
        pos += 1;
    };
    HarmonicTimeline { targets }
}

pub fn default_triad_params(seed: felt252, num_voices: u32) -> AllocatorParams {
    AllocatorParams {
        seed,
        num_voices,
        register_lo: array![43_u8, 50, 55, 60],
        register_hi: array![55_u8, 58, 62, 67],
        max_melodic_leap: 12,
        allow_crossing: false,
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
        w_spacing: 0,
        w_double: 0,
        w_consonance: 0,
    }
}

/// Params tuned for long PLR timelines (wider registers, four parts).
pub fn long_plr_progression_params(seed: felt252) -> AllocatorParams {
    AllocatorParams {
        seed,
        num_voices: 2,
        register_lo: array![40_u8, 53],
        register_hi: array![52_u8, 64],
        max_melodic_leap: 10,
        allow_crossing: false,
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
        w_spacing: 2,
        w_double: 1,
        w_consonance: 4,
    }
}

/// Conjunct soprano keynums (one per beat) matching each harmony target.
pub fn build_melody_line(
    seed: felt252, timeline: @HarmonicTimeline, top_lo: u8, top_hi: u8,
) -> Array<u8> {
    let s256: u256 = seed.into();
    let mut state: u32 = ((s256 / 65536) % 256).try_into().unwrap();
    if state == 0 {
        state = 41;
    }
    let mut rng = LCG { state, multiplier: 5, increment: 3, modulus: 256 };
    let mut prev: u8 = top_lo;
    loop {
        if prev > top_hi {
            prev = top_lo;
            break;
        }
        if prev % 12 == 0 {
            break;
        }
        prev += 1;
    };
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= timeline.targets.len() {
            break;
        }
        let t = timeline.targets.at(i);
        let (raw, next) = rng.draw();
        rng = next;
        let prefer_up = (i < timeline.targets.len() / 2) || (i % 5 < 3);
        let top = pick_melody_keynum(prev, t.pcs.span(), top_lo, top_hi, prefer_up, raw);
        prev = top;
        out.append(top);
        i += 1;
    };
    out
}

pub fn path_total_motion(
    layers: Span<Array<Array<u8>>>,
    path: Span<u32>,
    targets: Span<HarmonyTarget>,
    params: @AllocatorParams,
) -> u32 {
    if path.len() == 0 {
        return 0;
    }
    let t0: usize = (*path.at(0)).try_into().unwrap();
    let mut sum = node_cost(layers.at(0).at(t0).span(), *targets.at(0).root_pc, params);
    if path.len() < 2 {
        return sum;
    }
    let mut t: usize = 1;
    loop {
        if t >= path.len() {
            break;
        }
        let ti: usize = (*path.at(t)).try_into().unwrap();
        let tip: usize = (*path.at(t - 1)).try_into().unwrap();
        let prev = layers.at(t - 1).at(tip).span();
        let next = layers.at(t).at(ti).span();
        if !transition_legal(prev, next, params) {
            return MAX_COST;
        }
        sum += voicing_distance(prev, next, *params.allow_crossing);
        sum += node_cost(next, *targets.at(t).root_pc, params);
        t += 1;
    };
    sum
}

pub fn allocation_legal(result: @AllocationResult, params: @AllocatorParams) -> bool {
    if result.voices.len() == 0 {
        return false;
    }
    let beats = result.voices.at(0).len();
    if beats == 0 {
        return false;
    }
    let mut v: usize = 0;
    loop {
        if v >= result.voices.len() {
            break;
        }
        let voice = result.voices.at(v);
        if voice.len() != beats {
            return false;
        }
        let (lo, hi) = register_at(params, v.try_into().unwrap());
        let mut t: usize = 0;
        loop {
            if t >= beats {
                break;
            }
            let p = *voice.at(t);
            if p < lo || p > hi {
                return false;
            }
            t += 1;
        };
        v += 1;
    };
    let mut t2: usize = 1;
    loop {
        if t2 >= beats {
            break;
        }
        let mut prev_v: Array<u8> = ArrayTrait::new();
        let mut next_v: Array<u8> = ArrayTrait::new();
        let mut vi: usize = 0;
        loop {
            if vi >= result.voices.len() {
                break;
            }
            prev_v.append(*result.voices.at(vi).at(t2 - 1));
            next_v.append(*result.voices.at(vi).at(t2));
            vi += 1;
        };
        if !transition_legal(prev_v.span(), next_v.span(), params) {
            return false;
        }
        t2 += 1;
    };
    true
}

/// Brute-force check (small fixtures): no legal path has lower cost than `claimed`.
pub fn no_lower_cost_path(
    timeline: @HarmonicTimeline, params: @AllocatorParams, claimed: u32,
) -> bool {
    let t_len = timeline.targets.len();
    if t_len == 0 {
        return true;
    }
    let mut layers: Array<Array<Array<u8>>> = ArrayTrait::new();
    let mut t: usize = 0;
    loop {
        if t >= t_len {
            break;
        }
        layers.append(enumerate_voicings(timeline.targets.at(t), params));
        t += 1;
    };
    brute_better_exists(
        layers.span(), timeline.targets.span(), 0, array![].span(), params, claimed,
    )
}

fn brute_better_exists(
    layers: Span<Array<Array<u8>>>,
    targets: Span<HarmonyTarget>,
    depth: usize,
    partial: Span<u32>,
    params: @AllocatorParams,
    claimed: u32,
) -> bool {
    if depth >= layers.len() {
        let cost = path_total_motion(layers, partial, targets, params);
        return cost >= claimed;
    }
    let layer = layers.at(depth);
    let mut i: usize = 0;
    loop {
        if i >= layer.len() {
            break;
        }
        let mut next_path: Array<u32> = ArrayTrait::new();
        let mut p: usize = 0;
        loop {
            if p >= partial.len() {
                break;
            }
            next_path.append(*partial.at(p));
            p += 1;
        };
        next_path.append(i.try_into().unwrap());
        if !brute_better_exists(layers, targets, depth + 1, next_path.span(), params, claimed) {
            return false;
        }
        i += 1;
    };
    true
}

pub fn summed_motion(result: @AllocationResult) -> u32 {
    if result.voices.len() == 0 {
        return 0;
    }
    let beats = result.voices.at(0).len();
    if beats < 2 {
        return 0;
    }
    let mut sum: u32 = 0;
    let mut t: usize = 1;
    loop {
        if t >= beats {
            break;
        }
        let mut prev_v: Array<u8> = ArrayTrait::new();
        let mut next_v: Array<u8> = ArrayTrait::new();
        let mut vi: usize = 0;
        loop {
            if vi >= result.voices.len() {
                break;
            }
            prev_v.append(*result.voices.at(vi).at(t - 1));
            next_v.append(*result.voices.at(vi).at(t));
            vi += 1;
        };
        sum += voicing_distance(prev_v.span(), next_v.span(), false);
        t += 1;
    };
    sum
}

pub const MIN_MOTION_VELOCITY: u8 = 86;

/// Stepwise fill from `p` toward `q` over `s` attacks (conjunct melody-friendly).
fn melodic_step_fill(p: i32, q: i32, s: u32) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    if s <= 1 {
        out.append(p);
        return out;
    }
    let mut cur: i32 = p;
    out.append(cur);
    let mut i: u32 = 1;
    loop {
        if i >= s {
            break;
        }
        if i == s - 1 {
            cur = q;
        } else if cur < q {
            cur += 1;
        } else if cur > q {
            cur -= 1;
        }
        out.append(cur);
        i += 1;
    };
    out
}

fn beat_unit_ticks(raw: u32) -> u32 {
    let r = bounded(raw, 100);
    if r < 25 {
        3_u32
    } else if r < 75 {
        4_u32
    } else {
        5_u32
    }
}

fn subs_for_voice(voice: u32, raw: u32, unit: u32) -> u32 {
    let r = bounded(raw, 100);
    let mut subs = if voice == 0 {
        if r < 70 {
            1_u32
        } else {
            2_u32
        }
    } else if voice == 1 {
        if r < 40 {
            1_u32
        } else if r < 85 {
            2_u32
        } else {
            3_u32
        }
    } else if r < 20 {
        2_u32
    } else if r < 55 {
        3_u32
    } else {
        4_u32
    };
    if unit % subs != 0 {
        if unit % 2 == 0 {
            subs = 2;
        } else {
            subs = 1;
        }
    }
    subs
}

fn velocity_for(voice: u32, sub_idx: u32, subs: u32) -> u8 {
    if voice == 0 {
        if sub_idx == 0 {
            78_u8
        } else {
            62_u8
        }
    } else if voice == 1 {
        if sub_idx == 0 {
            82_u8
        } else {
            70_u8
        }
    } else if sub_idx == 0 {
        94_u8
    } else if sub_idx == subs - 1 {
        76_u8
    } else {
        72_u8
    }
}

/// Neighbor / passing fill between structural keynums `p` and `q` over `s` sub-beats.
fn ornament_cell(p: i32, q: i32, s: u32, up: bool) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    if s <= 1 {
        out.append(p);
        return out;
    }
    let nb: i32 = if up {
        2
    } else {
        -2
    };
    let delta = q - p;
    let toward_q: i32 = if delta > 0 {
        1
    } else if delta < 0 {
        -1
    } else {
        0
    };
    let mut i: u32 = 0;
    loop {
        if i >= s {
            break;
        }
        let v = if i == 0 {
            p
        } else if i == s - 1 {
            if toward_q != 0 {
                p + toward_q
            } else {
                p + nb
            }
        } else if i % 2 == 1 {
            p + nb
        } else {
            p
        };
        out.append(v);
        i += 1;
    };
    out
}

/// Varied PLR walk, conjunct soprano, minimal-motion bass/tenor, ornamented MIDI.
pub fn generate_ornamented_min_motion_progression(
    seed: felt252, nbeats: u32,
) -> Array<NoteEvent> {
    assert(nbeats > 0, 'nbeats');
    let timeline = timeline_from_plr_walk(seed, nbeats);
    let params = long_plr_progression_params(seed);
    generate_ornamented_min_motion_from_timeline(seed, timeline, params)
}

/// Ornamented minimal-motion realization for an arbitrary harmonic timeline.
pub fn generate_ornamented_min_motion_from_timeline(
    seed: felt252, timeline: HarmonicTimeline, params: AllocatorParams,
) -> Array<NoteEvent> {
    let t_len = timeline.targets.len();
    assert(t_len > 0, 'empty timeline');
    let top_lo: u8 = 64;
    let top_hi: u8 = 79;
    let timeline_ref = @timeline;
    let melody = build_melody_line(seed, timeline_ref, top_lo, top_hi);
    let seed_copy = seed;
    let alloc = allocate_min_motion(timeline_ref, params);
    assert(allocation_legal(@alloc, @long_plr_progression_params(seed_copy)), 'alloc legal');

    let s256: u256 = seed.into();
    let mut orn_state: u32 = ((s256 / 256) % 256).try_into().unwrap();
    if orn_state == 0 {
        orn_state = 31;
    }
    let mut rng = LCG { state: orn_state, multiplier: 5, increment: 3, modulus: 256 };

    let beats = alloc.voices.at(0).len();
    let num_parts: u32 = 3;
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut beat_starts: Array<u32> = ArrayTrait::new();
    let mut k: u32 = 0;
    let mut tick: u32 = 0;
    loop {
        if k >= beats {
            break;
        }
        beat_starts.append(tick);
        let (raw_u, next_u) = rng.draw();
        rng = next_u;
        tick += beat_unit_ticks(raw_u);
        k += 1;
    };

    let mut v: u32 = 0;
    loop {
        if v >= num_parts {
            break;
        }
        let mut b: u32 = 0;
        loop {
            if b >= beats {
                break;
            }
            let p: i32 = if v == 2 {
                (*melody.at(b.try_into().unwrap())).into()
            } else {
                (*alloc.voices.at(v.try_into().unwrap()).at(b.try_into().unwrap())).into()
            };
            let q: i32 = if b + 1 < beats {
                if v == 2 {
                    (*melody.at((b + 1).try_into().unwrap())).into()
                } else {
                    (*alloc
                        .voices
                        .at(v.try_into().unwrap())
                        .at((b + 1).try_into().unwrap()))
                    .into()
                }
            } else {
                p
            };
            let beat_start = *beat_starts.at(b.try_into().unwrap());
            let unit = if b + 1 < beats {
                *beat_starts.at((b + 1).try_into().unwrap()) - beat_start
            } else {
                4_u32
            };
            let (raw, next) = rng.draw();
            rng = next;
            let subs = subs_for_voice(v, raw, unit);
            let fill = if v == 0 && subs == 1 {
                melodic_step_fill(p, q, 1)
            } else if v >= 1 {
                melodic_step_fill(p, q, subs)
            } else {
                ornament_cell(p, q, subs, (v + b) % 2 == 0)
            };
            let sub_dur = unit / subs;
            let mut i: u32 = 0;
            loop {
                if i >= subs {
                    break;
                }
                let pitch_i: i32 = *fill.at(i);
                let pitch_u8: u8 = if pitch_i < 0 {
                    0
                } else if pitch_i > 127 {
                    127
                } else {
                    pitch_i.try_into().unwrap()
                };
                let vel = velocity_for(v, i, subs);
                out
                    .append(
                        NoteEvent {
                            time: beat_start + i * sub_dur,
                            duration: sub_dur,
                            pitch: pitch_u8,
                            velocity: vel,
                            voice_id: v,
                        },
                    );
                i += 1;
            };
            b += 1;
        };
        v += 1;
    };
    out
}

/// Total grid ticks for one pass (for MIDI loop length).
pub fn ornamented_min_motion_cycle_ticks(seed: felt252, nbeats: u32) -> u32 {
    ornamented_timeline_cycle_ticks(seed, nbeats)
}

/// Total grid ticks for one ornamented pass over `nbeats` harmony changes.
pub fn ornamented_timeline_cycle_ticks(seed: felt252, nbeats: u32) -> u32 {
    let s256: u256 = seed.into();
    let mut state: u32 = ((s256 / 256) % 256).try_into().unwrap();
    if state == 0 {
        state = 31;
    }
    let mut rng = LCG { state, multiplier: 5, increment: 3, modulus: 256 };
    let mut tick: u32 = 0;
    let mut k: u32 = 0;
    loop {
        if k >= nbeats {
            break;
        }
        let (raw_u, next_u) = rng.draw();
        rng = next_u;
        tick += beat_unit_ticks(raw_u);
        k += 1;
    };
    tick
}

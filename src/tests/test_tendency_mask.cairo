use core::array::ArrayTrait;
use koji::composition::envelope::{TimePoint, PitchRangeEnvelope, envelope_at, range_at};
use koji::composition::tendency_mask::{
    TendencyMask, new_tendency_mask, pick_weighted_index, pick_pitch_in_range, masked_scale_degree,
};
use koji::rng::{LCGRandomSource, RandomSource, bounded};
use koji::lcg::{LCG, RNGTrait};

// ──────────────────────────────────────────────────────────
// envelope_at
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_envelope_linear_ascending() {
    // (0,10) → (100,30) : midpoint should be 20
    let pts = array![TimePoint { x: 0, y: 10 }, TimePoint { x: 100, y: 30 }];
    assert(envelope_at(pts.span(), 50) == 20, 'ascending mid wrong');
    assert(envelope_at(pts.span(), 0) == 10, 'ascending start wrong');
    assert(envelope_at(pts.span(), 100) == 30, 'ascending end wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_envelope_linear_descending() {
    // (0,30) → (100,10) : midpoint should be 20
    let pts = array![TimePoint { x: 0, y: 30 }, TimePoint { x: 100, y: 10 }];
    assert(envelope_at(pts.span(), 50) == 20, 'descending mid wrong');
    assert(envelope_at(pts.span(), 0) == 30, 'descending start wrong');
    assert(envelope_at(pts.span(), 100) == 10, 'descending end wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_envelope_clamp_before_first() {
    let pts = array![TimePoint { x: 10, y: 5 }, TimePoint { x: 100, y: 25 }];
    assert(envelope_at(pts.span(), 0) == 5, 'clamp before failed');
}

#[test]
#[available_gas(1000000000000)]
fn test_envelope_clamp_after_last() {
    let pts = array![TimePoint { x: 10, y: 5 }, TimePoint { x: 100, y: 25 }];
    assert(envelope_at(pts.span(), 150) == 25, 'clamp after failed');
}

#[test]
#[available_gas(1000000000000)]
fn test_envelope_single_point() {
    let pts = array![TimePoint { x: 50, y: 15 }];
    assert(envelope_at(pts.span(), 0) == 15, 'single pt before');
    assert(envelope_at(pts.span(), 50) == 15, 'single pt at');
    assert(envelope_at(pts.span(), 200) == 15, 'single pt after');
}

#[test]
#[available_gas(1000000000000)]
fn test_envelope_three_knots() {
    // (0,0) → (50,50) → (100,0)  (tent shape)
    let pts = array![
        TimePoint { x: 0, y: 0 },
        TimePoint { x: 50, y: 50 },
        TimePoint { x: 100, y: 0 },
    ];
    assert(envelope_at(pts.span(), 25) == 25, 'tent left mid wrong');
    assert(envelope_at(pts.span(), 75) == 25, 'tent right mid wrong');
    assert(envelope_at(pts.span(), 50) == 50, 'tent peak wrong');
}

// ──────────────────────────────────────────────────────────
// range_at
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_range_at_normal() {
    let lo_pts = array![TimePoint { x: 0, y: 60 }];
    let hi_pts = array![TimePoint { x: 0, y: 72 }];
    let env = PitchRangeEnvelope { lo: lo_pts.span(), hi: hi_pts.span() };
    let (lo, hi) = range_at(@env, 0);
    assert(lo == 60, 'range lo wrong');
    assert(hi == 72, 'range hi wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_range_at_inverted_swaps() {
    // lo envelope returns 72, hi returns 60 — should swap
    let lo_pts = array![TimePoint { x: 0, y: 72 }];
    let hi_pts = array![TimePoint { x: 0, y: 60 }];
    let env = PitchRangeEnvelope { lo: lo_pts.span(), hi: hi_pts.span() };
    let (lo, hi) = range_at(@env, 0);
    assert(lo == 60, 'inverted lo wrong');
    assert(hi == 72, 'inverted hi wrong');
}

// ──────────────────────────────────────────────────────────
// Descending swarm scenario
// ──────────────────────────────────────────────────────────

fn descending_swarm(n_steps: u32) -> PitchRangeEnvelope {
    let mid = n_steps / 2;
    let end = if n_steps > 0 { n_steps - 1 } else { 0 };
    let lo_pts = array![
        TimePoint { x: 0, y: 84 },
        TimePoint { x: mid, y: 72 },
        TimePoint { x: end, y: 60 },
    ];
    let hi_pts = array![
        TimePoint { x: 0, y: 84 },
        TimePoint { x: mid, y: 78 },
        TimePoint { x: end, y: 84 },
    ];
    PitchRangeEnvelope { lo: lo_pts.span(), hi: hi_pts.span() }
}

#[test]
#[available_gas(1000000000000)]
fn test_swarm_start_collapsed() {
    let env = descending_swarm(16);
    let (lo, hi) = range_at(@env, 0);
    assert(lo == 84, 'swarm start lo wrong');
    assert(hi == 84, 'swarm start hi wrong');
    assert(lo == hi, 'swarm start not collapsed');
}

#[test]
#[available_gas(1000000000000)]
fn test_swarm_end_width_24() {
    let n: u32 = 16;
    let env = descending_swarm(n);
    let (lo, hi) = range_at(@env, n - 1);
    assert(lo == 60, 'swarm end lo wrong');
    assert(hi == 84, 'swarm end hi wrong');
    assert(hi - lo == 24, 'swarm end width != 24');
}

#[test]
#[available_gas(1000000000000)]
fn test_swarm_collapsed_pick_is_unique() {
    // When lo == hi the only candidate must be that single note.
    let env = descending_swarm(16);
    let (lo, hi) = range_at(@env, 0);
    assert(lo == hi, 'must be collapsed');
    // C major (offsets from C4=60) — none reach 84 (C6), so use a simple scale
    // anchored at root=72 (C5) with offset 12 = C6 = 84.
    let scale = array![12_u8]; // only one degree: 72+12=84
    let root: u8 = 72;
    let pitch = pick_pitch_in_range(scale.span(), root, lo, hi, 999);
    assert(pitch == 84, 'collapsed pick wrong');
}

// ──────────────────────────────────────────────────────────
// pick_weighted_index
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_pick_weighted_index_first_bucket() {
    // weights [8, 2, 3, 2, 6, 2, 1], total = 24
    let w = array![8_u32, 2, 3, 2, 6, 2, 1];
    let mask = new_tendency_mask(w.span());
    // raw=0 → pick=0 < acc=8 after i=0 → index 0
    assert(pick_weighted_index(@mask, 0) == 0, 'first bucket wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_pick_weighted_index_second_bucket() {
    let w = array![8_u32, 2, 3, 2, 6, 2, 1];
    let mask = new_tendency_mask(w.span());
    // pick = 8: acc=8 after i=0 (8<8? No), acc=10 after i=1 (8<10? Yes) → index 1
    assert(pick_weighted_index(@mask, 8) == 1, 'second bucket wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_pick_weighted_index_last_bucket() {
    let w = array![3_u32, 5, 2];
    let mask = new_tendency_mask(w.span());
    // total=10, raw=8 → pick=8
    // acc=3 (8<3? No), acc=8 (8<8? No), acc=10 (8<10? Yes) → index 2
    assert(pick_weighted_index(@mask, 8) == 2, 'last bucket wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_pick_weighted_index_wraps_modulo() {
    let w = array![3_u32, 5, 2];
    let mask = new_tendency_mask(w.span());
    // raw=13 → pick = 13 % 10 = 3 → acc=3 (3<3? No), acc=8 (3<8? Yes) → index 1
    assert(pick_weighted_index(@mask, 13) == 1, 'modulo wrap wrong');
}

// ──────────────────────────────────────────────────────────
// pick_pitch_in_range
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_pick_pitch_in_range_all_candidates() {
    // C major offsets, root=60, lo=60, hi=71 → 7 candidates [60,62,64,65,67,69,71]
    let scale = array![0_u8, 2, 4, 5, 7, 9, 11];
    let pitch = pick_pitch_in_range(scale.span(), 60, 60, 71, 0);
    assert(pitch == 60, 'first candidate wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_pick_pitch_in_range_narrow() {
    // Only 62,64,65 fall in [62,65]: offsets 2,4,5 from root 60
    let scale = array![0_u8, 2, 4, 5, 7, 9, 11];
    // raw=0 → idx=0 → 62
    let p0 = pick_pitch_in_range(scale.span(), 60, 62, 65, 0);
    // raw=2 → bounded(2,3)=2 → idx=2 → 65
    let p2 = pick_pitch_in_range(scale.span(), 60, 62, 65, 2);
    assert(p0 == 62, 'narrow pick 0 wrong');
    assert(p2 == 65, 'narrow pick 2 wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_pick_pitch_collapsed_range() {
    // lo == hi == 65 (F4). Only degree 5 (offset 5 from 60) hits 65.
    let scale = array![0_u8, 2, 4, 5, 7, 9, 11];
    let pitch = pick_pitch_in_range(scale.span(), 60, 65, 65, 999);
    assert(pitch == 65, 'collapsed range wrong');
}

// ──────────────────────────────────────────────────────────
// bounded
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_bounded_basic() {
    assert(bounded(10, 3) == 1, 'bounded 10%3 wrong');
    assert(bounded(0, 7) == 0, 'bounded 0%7 wrong');
    assert(bounded(100, 100) == 0, 'bounded 100%100 wrong');
    assert(bounded(99, 100) == 99, 'bounded 99%100 wrong');
}

// ──────────────────────────────────────────────────────────
// new_tendency_mask
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_new_tendency_mask_total() {
    let w = array![3_u32, 5, 2];
    let mask = new_tendency_mask(w.span());
    assert(mask.total == 10, 'total wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_new_tendency_mask_lydian_weights() {
    // Lydian gravity: degrees [0,1,2,3,4,5,6] weighted [8,2,3,2,6,2,1] → total=24
    let w = array![8_u32, 2, 3, 2, 6, 2, 1];
    let mask = new_tendency_mask(w.span());
    assert(mask.total == 24, 'lydian total wrong');
}

// ──────────────────────────────────────────────────────────
// RandomSource (LCG)
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_lcg_random_source_draw() {
    let lcg = LCG { state: 1, multiplier: 5, increment: 3, modulus: 16 };
    // value() = (5*1+3)%16 = 8; next state = 8
    let (v, new_lcg) = LCGRandomSource::draw(@lcg);
    assert(v == 8, 'draw value wrong');
    assert(new_lcg.state == 8, 'draw new state wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_lcg_random_source_chain() {
    let lcg = LCG { state: 1, multiplier: 5, increment: 3, modulus: 16 };
    let (v0, lcg1) = LCGRandomSource::draw(@lcg);
    let (v1, _lcg2) = LCGRandomSource::draw(@lcg1);
    // From test_lcg_sequence we know sequence is 8, 11, ...
    assert(v0 == 8, 'chain v0 wrong');
    assert(v1 == 11, 'chain v1 wrong');
}

// ──────────────────────────────────────────────────────────
// masked_scale_degree
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_masked_scale_degree_tonic() {
    // Lydian weights heavily favor degree 0 (tonic).
    let w = array![8_u32, 2, 3, 2, 6, 2, 1];
    let mask = new_tendency_mask(w.span());
    let scale = array![0_u8, 2, 4, 6, 7, 9, 11]; // Lydian offsets
    // raw=0 → pick=0 < 8 → index 0 → scale[0]=0
    let degree = masked_scale_degree(@mask, scale.span(), 0);
    assert(degree == 0, 'tonic degree wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_masked_scale_degree_fifth() {
    // Lydian weights: [8,2,3,2,6,2,1], total=24.
    // pick=10 → acc after i=0: 8 (10<8? No), acc after i=1: 10 (10<10? No),
    // acc after i=2: 13 (10<13? Yes) → index 2 → Lydian scale[2]=4 (major third)
    let w = array![8_u32, 2, 3, 2, 6, 2, 1];
    let mask = new_tendency_mask(w.span());
    let scale = array![0_u8, 2, 4, 6, 7, 9, 11];
    let degree = masked_scale_degree(@mask, scale.span(), 10);
    assert(degree == 4, 'third degree wrong');
}

// ──────────────────────────────────────────────────────────
// Regression: flat weights ≡ uniform modulo
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_regression_flat_mask_equals_modulo() {
    // All weights equal → same result as raw % scale_len
    let scale_len: u32 = 7;
    let w = array![1_u32, 1, 1, 1, 1, 1, 1];
    let mask = new_tendency_mask(w.span());

    let mut step: u32 = 0;
    loop {
        if step >= 20 {
            break;
        }
        let raw = step * 13 + 7; // arbitrary sequence
        let mask_idx: usize = pick_weighted_index(@mask, raw);
        let modulo_idx: usize = (raw % scale_len).try_into().unwrap();
        assert(mask_idx == modulo_idx, 'flat mask vs modulo mismatch');
        step += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Scale discipline: every picked pitch stays in scale and range
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_scale_discipline_all_picks_in_scale() {
    let n_steps: u32 = 16;
    let env = descending_swarm(n_steps);
    // C major offsets (7 degrees); root = 60
    let scale = array![0_u8, 2, 4, 5, 7, 9, 11];
    let root: u8 = 60;

    // Small-parameter LCG avoids u32 multiplication overflow (multiplier * state must fit u32).
    let mut lcg = LCG { state: 42, multiplier: 5, increment: 3, modulus: 256 };
    let mut step: u32 = 0;
    loop {
        if step >= n_steps {
            break;
        }
        let (lo, hi) = range_at(@env, step);
        let (raw, new_lcg) = LCGRandomSource::draw(@lcg);
        lcg = new_lcg;

        // Only call pick if range contains at least one scale pitch
        let mut has_candidate = false;
        let mut j: usize = 0;
        loop {
            if j >= scale.len() {
                break;
            }
            let degree = *scale.at(j);
            let midi: u32 = root.into() + degree.into();
            if midi >= lo && midi <= hi {
                has_candidate = true;
            }
            j += 1;
        };

        if has_candidate {
            let pitch = pick_pitch_in_range(scale.span(), root, lo, hi, raw);
            // Verify the pitch is in the scale
            let mut found = false;
            let mut k: usize = 0;
            loop {
                if k >= scale.len() {
                    break;
                }
                let candidate: u8 = root + *scale.at(k);
                if pitch == candidate {
                    found = true;
                }
                k += 1;
            };
            assert(found, 'pitch not in scale');
            // Verify the pitch is in range
            let pitch_u32: u32 = pitch.into();
            assert(pitch_u32 >= lo, 'pitch below lo');
            assert(pitch_u32 <= hi, 'pitch above hi');
        }

        step += 1;
    };
}

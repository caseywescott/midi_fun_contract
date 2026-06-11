//! Acceptance tests for the grouping-driven motif period pipeline.

use koji::composition::known_symmetric_worlds::registry_entry;
use koji::composition::motif_algebra::{
    developed_to_note_events, motif_from_degrees, motif_from_world, motif_in_world,
    motif_ops_total, op_laws_hold, DevelopedMotif, MotifOp,
};
use koji::composition::motif_form::weighted_program_from_seed;
use koji::composition::period_assembly::{
    develop_period_grouped, grouped_period_length_consistent, head_phrase,
    head_phrase_well_formed, period_section_lengths,
};
use koji::composition::transform::arrays_equal_i32;

fn arrays_equal_u32(a: Span<u32>, b: Span<u32>) -> bool {
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

fn op_kind(op: @MotifOp) -> u32 {
    match op {
        MotifOp::Transpose(_) => 0,
        MotifOp::Invert(_) => 1,
        MotifOp::Retrograde => 2,
        MotifOp::RetrogradeInvert(_) => 3,
        MotifOp::Augment(_) => 4,
        MotifOp::Diminish(_) => 5,
        MotifOp::Fragment(_) => 6,
        MotifOp::Sequence(_) => 7,
        MotifOp::Rotate(_) => 8,
        MotifOp::Stutter(_) => 9,
        MotifOp::Interpolate(_) => 10,
        MotifOp::IntervalScale(_) => 11,
        MotifOp::Concat(_) => 12,
    }
}

fn a_sections_repeat_exactly(period: @DevelopedMotif, a_len: u32, b_len: u32) -> bool {
    if period.degrees.len() != a_len * 3 + b_len {
        return false;
    }
    let final_a_start = a_len * 2 + b_len;
    let mut i: u32 = 0;
    loop {
        if i >= a_len {
            break true;
        }
        let degree = *period.degrees.at(i);
        let duration = *period.durations.at(i);
        if degree != *period.degrees.at(a_len + i)
            || degree != *period.degrees.at(final_a_start + i)
            || duration != *period.durations.at(a_len + i)
            || duration != *period.durations.at(final_a_start + i) {
            break false;
        }
        i += 1;
    }
}

#[test]
#[available_gas(1000000000000)]
fn test_grouped_period_consistent_across_seeds() {
    let mut i: u32 = 0;
    loop {
        if i >= 8 {
            break;
        }
        let seed: felt252 = ((i + 1) * 123456789).into();
        assert(grouped_period_length_consistent(seed), 'grouped length');
        assert(head_phrase_well_formed(seed), 'head well formed');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_grouped_period_deterministic_and_repeats_a() {
    let theme = motif_from_degrees(array![0_i32, 2, 4, 7, 4, 2], 7, 0);
    let durations = array![1_u32, 1, 3, 1, 1, 2];
    let seed: felt252 = 987654321;
    let (a_len, b_len) = period_section_lengths(@theme, @durations, seed, 6);
    let first = develop_period_grouped(@theme, @durations, seed, 6);
    let second = develop_period_grouped(@theme, @durations, seed, 6);
    assert(arrays_equal_i32(first.degrees.span(), second.degrees.span()), 'grouped degrees');
    assert(arrays_equal_u32(first.durations.span(), second.durations.span()), 'grouped durations');
    assert(a_sections_repeat_exactly(@first, a_len, b_len), 'A sections exact');
    assert(first.degrees.len() == first.durations.len(), 'grouped parallel');
    assert(developed_to_note_events(@first, 60, 0).len() == first.degrees.len(), 'MIDI handoff');
}

#[test]
#[available_gas(1000000000000)]
fn test_grouped_period_totality() {
    let empty = motif_from_degrees(array![], 7, 0);
    let empty_period = develop_period_grouped(@empty, @array![], 1, 8);
    assert(empty_period.degrees.len() == 0, 'empty period');
    assert(empty_period.durations.len() == 0, 'empty durations');

    let single = motif_from_degrees(array![3_i32], 7, 0);
    let single_period = develop_period_grouped(@single, @array![2_u32], 2, 8);
    assert(single_period.degrees.len() == single_period.durations.len(), 'single parallel');
    assert(head_phrase(@single_period).degrees.len() > 0, 'single head');

    let flat = motif_from_degrees(array![0_i32, 0, 0, 0], 7, 0);
    let flat_period = develop_period_grouped(@flat, @array![1_u32, 1, 1, 1], 3, 8);
    assert(flat_period.degrees.len() == flat_period.durations.len(), 'flat parallel');
}

#[test]
#[available_gas(1000000000000)]
fn test_grouped_period_world_invariant() {
    let entry = registry_entry(7);
    let theme = motif_from_world(4242, entry.mask, 6);
    let durations = array![1_u32, 1, 2, 1, 1, 2];
    let mut i: u32 = 0;
    loop {
        if i >= 8 {
            break;
        }
        let seed: felt252 = ((i + 1) * 7654321).into();
        let period = develop_period_grouped(@theme, @durations, seed, 6);
        assert(period.degrees.len() == period.durations.len(), 'world parallel');
        assert(motif_in_world(@period), 'grouped in world');
        i += 1;
    };
}

#[test]
fn test_phase0_distribution_over_256_seeds() {
    let mut transpose_count: u32 = 0;
    let mut invert_count: u32 = 0;
    let mut fragment_count: u32 = 0;
    let mut sequence_count: u32 = 0;
    let mut raw: u32 = 0;
    loop {
        if raw >= 256 {
            break;
        }
        let seed: felt252 = (raw * 256).into();
        let mut program = weighted_program_from_seed(seed, 2);
        match program.ops.pop_front() {
            Option::Some(op) => {
                let kind = op_kind(@op);
                if kind == 0 {
                    transpose_count += 1;
                } else if kind == 1 {
                    invert_count += 1;
                } else if kind == 6 {
                    fragment_count += 1;
                } else if kind == 7 {
                    sequence_count += 1;
                }
            },
            Option::None(_) => {
                assert(false, 'missing weighted op');
            },
        }
        raw += 1;
    };
    assert(transpose_count == 54, 'transpose weight');
    assert(invert_count == 9, 'invert weight');
    assert(fragment_count == 32, 'fragment weight');
    assert(sequence_count == 40, 'sequence weight');
}

#[test]
#[available_gas(1000000000000)]
fn test_base_motif_regressions() {
    assert(op_laws_hold(), 'group laws');
    assert(motif_ops_total(), 'ops total');
}

//! Tests for weighted motif development and flat AABA form.

use koji::composition::motif_algebra::{
    apply_program, motif_from_degrees, MotifOp,
};
use koji::composition::motif_form::{
    develop_period, period_length_consistent, weighted_kind, weighted_program_from_seed,
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

fn count_kind(phase: u32, kind: u32, samples: u32) -> u32 {
    let mut count: u32 = 0;
    let mut raw: u32 = 0;
    loop {
        if raw >= samples {
            break;
        }
        if weighted_kind(raw, phase) == kind {
            count += 1;
        }
        raw += 1;
    };
    count
}

#[test]
fn test_weighted_kind_tables() {
    assert(count_kind(0, 0, 31) == 6, 'phase0 transpose');
    assert(count_kind(0, 6, 31) == 4, 'phase0 fragment');
    assert(count_kind(0, 7, 31) == 5, 'phase0 sequence');
    assert(count_kind(0, 9, 31) == 3, 'phase0 stutter');
    assert(count_kind(1, 0, 28) == 3, 'phase1 transpose');
    assert(count_kind(1, 1, 28) == 4, 'phase1 invert');
    assert(count_kind(1, 2, 28) == 3, 'phase1 retro');
    assert(count_kind(1, 3, 28) == 3, 'phase1 retroinv');
}

#[test]
fn test_weighted_program_caps_and_omits_concat() {
    let default_program = weighted_program_from_seed(123456, 0);
    assert(default_program.ops.len() == 6, 'default cap');
    let mut capped_program = weighted_program_from_seed(123456, 99);
    assert(capped_program.ops.len() == 8, 'max cap');
    loop {
        match capped_program.ops.pop_front() {
            Option::Some(op) => {
                match op {
                    MotifOp::Concat(_) => {
                        assert(false, 'concat emitted');
                    },
                    _ => {},
                }
            },
            Option::None(_) => {
                break;
            },
        }
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_weighted_program_deterministic_and_parallel() {
    let theme = motif_from_degrees(array![0_i32, 4, 1, 7], 7, 0);
    let durations = array![2_u32, 1, 3, 1];
    let a = apply_program(@theme, @durations, weighted_program_from_seed(987654, 6));
    let b = apply_program(@theme, @durations, weighted_program_from_seed(987654, 6));
    assert(arrays_equal_i32(a.degrees.span(), b.degrees.span()), 'weighted degrees');
    assert(arrays_equal_u32(a.durations.span(), b.durations.span()), 'weighted durations');
    assert(a.degrees.len() == a.durations.len(), 'parallel arrays');
}

#[test]
#[available_gas(1000000000000)]
fn test_flat_period_consistent_and_parallel() {
    assert(period_length_consistent(424242), 'period length');
    let theme = motif_from_degrees(array![0_i32, 2, 1, 4], 7, 0);
    let durations = array![1_u32, 1, 1, 1];
    let period = develop_period(@theme, @durations, 424242, 4);
    assert(period.degrees.len() == period.durations.len(), 'period parallel');
}

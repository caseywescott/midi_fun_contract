//! Tests for local GTTM grouping-boundary detection.

use koji::composition::grouping_boundaries::{
    group_lengths, grouping_boundaries, groups_partition_exact, groups_respect_min,
    segment_into_groups,
};
use koji::composition::motif_algebra::{
    apply_program, grundgestalt_theme, DevelopedMotif,
};
use koji::composition::motif_form::weighted_program_from_seed;

fn developed(degrees: Array<i32>, durations: Array<u32>) -> DevelopedMotif {
    DevelopedMotif { degrees, durations, octave: 7, world_mask: 0 }
}

#[test]
fn test_duration_spike_creates_boundary() {
    let line = developed(
        array![0_i32, 1, 2, 3, 4, 5],
        array![1_u32, 1, 4, 1, 1, 1],
    );
    let bounds = grouping_boundaries(@line);
    assert(bounds.len() == 1, 'duration bound count');
    assert(*bounds.at(0) == 2, 'duration bound index');
    let groups = segment_into_groups(@line);
    assert(groups.len() == 2, 'duration group count');
    assert(groups.at(0).degrees.len() == 3, 'duration head len');
    assert(groups.at(1).degrees.len() == 3, 'duration tail len');
}

#[test]
fn test_register_leap_creates_boundary() {
    let line = developed(
        array![0_i32, 1, 2, 10, 11, 12],
        array![1_u32, 1, 1, 1, 1, 1],
    );
    let bounds = grouping_boundaries(@line);
    assert(bounds.len() == 1, 'leap bound count');
    assert(*bounds.at(0) == 2, 'leap bound index');
    assert(groups_partition_exact(@line), 'leap partition');
    assert(groups_respect_min(@line), 'leap min groups');
}

#[test]
fn test_grouping_total_on_empty_and_short_lines() {
    let empty = developed(array![], array![]);
    assert(grouping_boundaries(@empty).len() == 0, 'empty bounds');
    assert(segment_into_groups(@empty).len() == 0, 'empty groups');
    assert(group_lengths(@empty).len() == 0, 'empty lengths');
    assert(groups_partition_exact(@empty), 'empty partition');
    assert(groups_respect_min(@empty), 'empty min');

    let single = developed(array![4_i32], array![2_u32]);
    assert(grouping_boundaries(@single).len() == 0, 'single bounds');
    assert(segment_into_groups(@single).len() == 1, 'single group');
    assert(groups_partition_exact(@single), 'single partition');
    assert(groups_respect_min(@single), 'single min');
}

#[test]
#[available_gas(1000000000000)]
fn test_groups_partition_developed_themes() {
    let durations = array![1_u32, 2, 1, 3, 1, 2];
    let mut theme_id: u32 = 0;
    loop {
        if theme_id >= 4 {
            break;
        }
        let theme = grundgestalt_theme(theme_id);
        let mut seed_index: u32 = 0;
        loop {
            if seed_index >= 4 {
                break;
            }
            let seed: felt252 = (theme_id * 100 + seed_index + 1).into();
            let line = apply_program(
                @theme, @durations, weighted_program_from_seed(seed, 6),
            );
            assert(groups_partition_exact(@line), 'theme partition');
            assert(groups_respect_min(@line), 'theme min groups');
            seed_index += 1;
        };
        theme_id += 1;
    };
}

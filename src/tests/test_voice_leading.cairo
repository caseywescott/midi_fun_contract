use core::array::ArrayTrait;
use koji::composition::voice_leading::{
    FREE_PC, allocate_min_motion, allocation_legal, default_triad_params, enumerate_voicings,
    harmony_target, harmony_target_pinned, no_lower_cost_path, summed_motion,
    timeline_from_pc_sets, timeline_from_plr, transition_legal, voicing_distance,
};
use koji::composition::counterpoint::would_create_parallel_perfect;

fn plr_test_params(seed: felt252) -> koji::composition::voice_leading::AllocatorParams {
    let mut params = default_triad_params(seed, 3);
    params.register_lo = array![43_u8, 50, 55];
    params.register_hi = array![55_u8, 58, 64];
    params
}

fn narrow_triad_params(seed: felt252, num_voices: u32) -> koji::composition::voice_leading::AllocatorParams {
    if num_voices == 3 {
        koji::composition::voice_leading::AllocatorParams {
            seed,
            num_voices: 3,
            register_lo: array![43_u8, 50, 55],
            register_hi: array![55_u8, 58, 64],
            max_melodic_leap: 7,
            allow_crossing: false,
            forbid_parallel_perfects: true,
            forbid_similar_perfects: true,
            w_spacing: 0,
            w_double: 0,
            w_consonance: 0,
        }
    } else {
        default_triad_params(seed, num_voices)
    }
}

#[test]
#[available_gas(1000000000000)]
fn test_voicing_distance_order_preserving() {
    let a = array![48_u8, 55, 60];
    let b = array![48_u8, 55, 62];
    assert(voicing_distance(a.span(), b.span(), false) == 2, 'dist 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_enumerate_voicings_c_major() {
    let target = harmony_target(array![0_u8, 4, 7]);
    let params = narrow_triad_params(1, 3);
    let voicings = enumerate_voicings(@target, @params);
    assert(voicings.len() > 0, 'has voicings');
    let v0 = voicings.at(0);
    assert(v0.len() == 3, '3 voices');
    assert(*v0.at(0) <= *v0.at(1), 'sorted 01');
    assert(*v0.at(1) <= *v0.at(2), 'sorted 12');
}

#[test]
#[available_gas(1000000000000)]
fn test_transition_blocks_parallel_fifth() {
    let prev = array![60_u8, 67, 72];
    let bad = array![62_u8, 69, 74];
    let params = narrow_triad_params(2, 3);
    assert(
        would_create_parallel_perfect(*prev.at(1), *prev.at(0), *bad.at(1), *bad.at(0)),
        'parallel 5th pair',
    );
    assert(!transition_legal(prev.span(), bad.span(), @params), 'blocked');
}

#[test]
#[available_gas(1000000000000)]
fn test_allocate_min_motion_legal() {
    let beats = array![
        array![0_u8, 4, 7].span(),
        array![7_u8, 11, 2].span(),
        array![5_u8, 9, 0].span(),
    ];
    let timeline = timeline_from_pc_sets(beats.span());
    let result = allocate_min_motion(@timeline, narrow_triad_params(42, 3));
    assert(allocation_legal(@result, @narrow_triad_params(42, 3)), 'legal');
    assert(result.voices.len() == 3, '3 voices out');
    assert(result.voices.at(0).len() == 3, '3 beats');
}

#[test]
#[available_gas(1000000000000)]
fn test_allocate_deterministic() {
    let beats = array![
        array![0_u8, 4, 7].span(),
        array![9_u8, 0, 4].span(),
        array![5_u8, 9, 0].span(),
    ];
    let timeline = timeline_from_pc_sets(beats.span());
    let a = allocate_min_motion(@timeline, narrow_triad_params(99, 3));
    let b = allocate_min_motion(@timeline, narrow_triad_params(99, 3));
    assert(a.total_motion == b.total_motion, 'same cost');
    assert(*a.voices.at(0).at(0) == *b.voices.at(0).at(0), 'same bass');
}

#[test]
#[available_gas(1000000000000)]
fn test_no_lower_cost_path_brute() {
    let beats = array![
        array![0_u8, 4, 7].span(),
        array![7_u8, 11, 2].span(),
    ];
    let timeline = timeline_from_pc_sets(beats.span());
    let result = allocate_min_motion(@timeline, narrow_triad_params(7, 3));
    assert(
        no_lower_cost_path(@timeline, @narrow_triad_params(7, 3), result.total_motion),
        'optimal',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_pinned_bass() {
    let target = harmony_target_pinned(array![0_u8, 4, 7], 0, FREE_PC);
    let mut params = narrow_triad_params(3, 3);
    params.register_lo = array![43_u8, 50, 55];
    params.register_hi = array![55_u8, 58, 64];
    let voicings = enumerate_voicings(@target, @params);
    let mut i: usize = 0;
    loop {
        if i >= voicings.len() {
            break;
        }
        assert(*voicings.at(i).at(0) % 12 == 0, 'bass C');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_plr_timeline_allocates() {
    let timeline = timeline_from_plr(4);
    let params = plr_test_params(2026);
    let result = allocate_min_motion(@timeline, params);
    assert(allocation_legal(@result, @plr_test_params(2026)), 'plr legal');
    assert(result.voices.len() == 3, '3 voices');
}

#[test]
#[available_gas(1000000000000)]
fn test_summed_motion_matches_total() {
    let beats = array![
        array![0_u8, 4, 7].span(),
        array![0_u8, 4, 7].span(),
        array![0_u8, 4, 7].span(),
    ];
    let timeline = timeline_from_pc_sets(beats.span());
    let params = narrow_triad_params(5, 3);
    let result = allocate_min_motion(@timeline, params);
    let edge_only = summed_motion(@result);
    assert(edge_only <= result.total_motion, 'edges <= total');
}

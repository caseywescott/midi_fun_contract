use core::array::ArrayTrait;
use core::dict::Felt252Dict;
use koji::composition::known_tilings::{
    templates_for, gen_supported_n, velocity_pattern, num_velocity_patterns,
};
use koji::composition::rhythmic_tiling::{
    OnsetEvent, RhythmicVoice, MAX_VOICES, MIN_TILE_ONSETS, span_eq, ap_set, is_direct_sum,
    find_complement, legato_durations, apply_offset, cyclic_gaps, gap_variety,
    is_arithmetic_progression, is_trivial_block_pattern, distance_of_entrance, score_tiling,
    is_periodic, is_candidate_prime_canon, validate_scaled_tile, derive_velocity, canon_to_events,
    generate_rhythmic_canon, canon_traits,
};

// ──────────────────────────────────────────────────────────
// Test helpers
// ──────────────────────────────────────────────────────────

fn assert_some_eq(actual: Option<Array<u32>>, expected: Array<u32>, msg: felt252) {
    match actual {
        Option::Some(a) => { assert(span_eq(a.span(), expected.span()), msg); },
        Option::None => { assert(false, msg); },
    }
}

fn assert_is_none(actual: Option<Array<u32>>, msg: felt252) {
    match actual {
        Option::Some(_) => { assert(false, msg); },
        Option::None => {},
    }
}

fn sum_span(s: Span<u32>) -> u32 {
    let mut total: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= s.len() {
            break;
        }
        total += *s.at(i);
        i += 1;
    };
    total
}

// ──────────────────────────────────────────────────────────
// Direct Sum
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_direct_sum_true_block() {
    let r = array![0_u32, 1];
    let s = array![0_u32, 2, 4, 6, 8, 10];
    assert(is_direct_sum(12, r.span(), s.span()), 'R{0,1} S even should tile');
}

#[test]
#[available_gas(1000000000000)]
fn test_direct_sum_collision() {
    let r = array![0_u32, 3];
    let s = array![0_u32, 1, 2, 4];
    assert(!is_direct_sum(8, r.span(), s.span()), 'collision must be false');
}

#[test]
#[available_gas(1000000000000)]
fn test_direct_sum_true_hocket() {
    let r = array![0_u32, 2];
    let s = array![0_u32, 1, 4, 5];
    assert(is_direct_sum(8, r.span(), s.span()), 'R{0,2} S should tile Z8');
}

#[test]
#[available_gas(1000000000000)]
fn test_direct_sum_non_tiling() {
    // {0,4} does not tile Z_12.
    let r = array![0_u32, 4];
    let s = array![0_u32, 1, 4, 5, 8, 9];
    assert(!is_direct_sum(12, r.span(), s.span()), '{0,4} cannot tile Z12');
}

#[test]
#[available_gas(1000000000000)]
fn test_direct_sum_wrong_cardinality() {
    let r = array![0_u32, 2];
    let s = array![0_u32, 1, 4];
    // 2 * 3 = 6 != 8
    assert(!is_direct_sum(8, r.span(), s.span()), 'cardinality mismatch false');
}

// ──────────────────────────────────────────────────────────
// AP Construction
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_ap_set_basic() {
    assert_some_eq(ap_set(2, 2, 12), array![0, 2], 'ap(2,2,12)');
    assert_some_eq(ap_set(3, 4, 12), array![0, 4, 8], 'ap(3,4,12)');
    assert_some_eq(ap_set(6, 2, 12), array![0, 2, 4, 6, 8, 10], 'ap(6,2,12)');
    assert_some_eq(ap_set(4, 3, 12), array![0, 3, 6, 9], 'ap(4,3,12)');
}

#[test]
#[available_gas(1000000000000)]
fn test_ap_set_self_intersect() {
    // step 2 over 8: {0,2,4,6,0,2} self-intersects after 4 entries.
    assert_is_none(ap_set(6, 2, 8), 'ap(6,2,8) self intersects');
}

#[test]
#[available_gas(1000000000000)]
fn test_ap_set_two_elements_distinct() {
    assert_some_eq(ap_set(2, 6, 8), array![0, 6], 'ap(2,6,8) distinct');
}

// ──────────────────────────────────────────────────────────
// Polynomial Complement
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_find_complement_known() {
    assert_some_eq(find_complement(12, array![0, 2].span()), array![0, 1, 4, 5, 8, 9], 'fc(12,{0,2})');
    assert_some_eq(find_complement(12, array![0, 6].span()), array![0, 1, 2, 3, 4, 5], 'fc(12,{0,6})');
    assert_some_eq(find_complement(8, array![0, 2].span()), array![0, 1, 4, 5], 'fc(8,{0,2})');
    assert_some_eq(find_complement(8, array![0, 2, 4, 6].span()), array![0, 1], 'fc(8,{0,2,4,6})');
}

#[test]
#[available_gas(1000000000000)]
fn test_find_complement_none() {
    assert_is_none(find_complement(12, array![0, 4].span()), 'fc(12,{0,4}) none');
}

// ──────────────────────────────────────────────────────────
// Legato Durations
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_legato_durations_hocket() {
    let r = array![0_u32, 1, 4, 5, 8, 9];
    let durs = legato_durations(r.span(), 12);
    assert(span_eq(durs.span(), array![1, 3, 1, 3, 1, 3].span()), 'hocket durs');
    assert(sum_span(durs.span()) == 12, 'durs sum to n');
}

#[test]
#[available_gas(1000000000000)]
fn test_legato_durations_even() {
    let r = array![0_u32, 2, 4, 6];
    let durs = legato_durations(r.span(), 8);
    assert(span_eq(durs.span(), array![2, 2, 2, 2].span()), 'even durs');
}

#[test]
#[available_gas(1000000000000)]
fn test_legato_durations_sparse() {
    let r = array![0_u32, 1];
    let durs = legato_durations(r.span(), 12);
    assert(span_eq(durs.span(), array![1, 11].span()), 'sparse durs');
    assert(sum_span(durs.span()) == 12, 'sparse sum');
}

// ──────────────────────────────────────────────────────────
// Rotation Offsets
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_apply_offset_even() {
    let set = array![0_u32, 2, 4, 6, 8, 10];
    let out = apply_offset(set.span(), 1, 12);
    assert(span_eq(out.span(), array![1, 3, 5, 7, 9, 11].span()), 'offset even');
}

#[test]
#[available_gas(1000000000000)]
fn test_apply_offset_wraps_and_sorts() {
    let set = array![0_u32, 1, 4, 5, 8, 9];
    let out = apply_offset(set.span(), 3, 12);
    assert(span_eq(out.span(), array![0, 3, 4, 7, 8, 11].span()), 'offset wrap sort');
}

#[test]
#[available_gas(1000000000000)]
fn test_offset_preserves_direct_sum() {
    let r = array![0_u32, 2];
    let s = array![0_u32, 1, 4, 5, 8, 9];
    let mut offset: u32 = 0;
    loop {
        if offset >= 12 {
            break;
        }
        let ro = apply_offset(r.span(), offset, 12);
        let so = apply_offset(s.span(), offset, 12);
        assert(is_direct_sum(12, ro.span(), so.span()), 'rotation preserves tiling');
        offset += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Augmentation
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_validate_scaled_tile_collision() {
    let r = array![0_u32, 2];
    let s = array![0_u32, 1, 4, 5, 8, 9];
    // 2R = {0,4} collides with S.
    assert(!validate_scaled_tile(12, r.span(), s.span(), 2), 'scaled tile collides');
}

#[test]
#[available_gas(1000000000000)]
fn test_validate_scaled_tile_identity() {
    let r = array![0_u32, 2];
    let s = array![0_u32, 1, 4, 5];
    // factor 1 is the identity scaling and must still tile.
    assert(validate_scaled_tile(8, r.span(), s.span(), 1), 'identity scale tiles');
}

// ──────────────────────────────────────────────────────────
// Gap Analysis & Classification
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_cyclic_gaps() {
    let positions = array![0_u32, 2, 5];
    let gaps = cyclic_gaps(8, positions.span());
    assert(span_eq(gaps.span(), array![2, 3, 3].span()), 'cyclic gaps {0,2,5}');
}

#[test]
#[available_gas(1000000000000)]
fn test_trivial_block_pattern() {
    let r = array![0_u32, 2, 4, 6, 8, 10];
    let s = array![0_u32, 1];
    assert(is_trivial_block_pattern(12, r.span(), s.span()), 'both AP is trivial');

    let r2 = array![0_u32, 2];
    let s2 = array![0_u32, 1, 4, 5, 8, 9];
    assert(!is_trivial_block_pattern(12, r2.span(), s2.span()), 'S non-AP not trivial');
}

#[test]
#[available_gas(1000000000000)]
fn test_is_arithmetic_progression() {
    assert(is_arithmetic_progression(array![0_u32, 2, 4, 6].span(), 8), 'even is AP');
    assert(is_arithmetic_progression(array![0_u32, 1].span(), 12), 'pair is AP');
    assert(!is_arithmetic_progression(array![0_u32, 1, 4, 5, 8, 9].span(), 12), 'hocket not AP');
}

#[test]
#[available_gas(1000000000000)]
fn test_distance_of_entrance() {
    let s = array![0_u32, 1, 4, 5, 8, 9];
    assert(distance_of_entrance(s.span()) == 1, 'min nonzero S');
    let s2 = array![0_u32, 4, 8];
    assert(distance_of_entrance(s2.span()) == 4, 'min nonzero S2');
}

#[test]
#[available_gas(1000000000000)]
fn test_score_class2_beats_class0() {
    // class 0: both pure APs (trivial block).
    let r0 = array![0_u32, 2, 4, 6, 8, 10];
    let s0 = array![0_u32, 1];
    let class0 = score_tiling(12, r0.span(), s0.span());

    // class 2: neither side a pure AP.
    let r2 = array![0_u32, 2];
    let s2 = array![0_u32, 1, 4, 5, 8, 9];
    let class2 = score_tiling(12, r2.span(), s2.span());

    assert(class2 > class0, 'class2 outscores class0');
}

#[test]
#[available_gas(1000000000000)]
fn test_gap_variety() {
    // {0,2} in Z_12 has gaps [2,10] -> 2 distinct.
    assert(gap_variety(12, array![0_u32, 2].span()) == 2, 'gap variety {0,2}');
    // {0,4,8} in Z_12 has gaps [4,4,4] -> 1 distinct.
    assert(gap_variety(12, array![0_u32, 4, 8].span()) == 1, 'gap variety {0,4,8}');
}

// ──────────────────────────────────────────────────────────
// Periodicity
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_is_periodic() {
    // {0,4,8} in Z_12 is invariant under rotation by 4 (= 12/3).
    assert(is_periodic(array![0_u32, 4, 8].span(), 12), '{0,4,8} periodic');
    // {0,2} in Z_12 is not invariant under any prime rotation.
    assert(!is_periodic(array![0_u32, 2].span(), 12), '{0,2} not periodic');
}

#[test]
#[available_gas(1000000000000)]
fn test_no_vuza_for_supported_n() {
    // All supported n are Hajos: at least one side is always periodic.
    let r = array![0_u32, 2];
    let s = array![0_u32, 1, 4, 5, 8, 9];
    assert(!is_candidate_prime_canon(12, r.span(), s.span()), 'no vuza for n=12');
}

// ──────────────────────────────────────────────────────────
// Velocity
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_velocity_flat() {
    let voice = RhythmicVoice {
        voice_id: 0, translation: 0, tiling_participant: true, velocity_curve: 0,
    };
    assert(derive_velocity(0, voice) == 100, 'flat v0');
    assert(derive_velocity(5, voice) == 100, 'flat v5');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_accent_first() {
    let voice = RhythmicVoice {
        voice_id: 0, translation: 0, tiling_participant: true, velocity_curve: 1,
    };
    assert(derive_velocity(0, voice) == 120, 'accent index0');
    assert(derive_velocity(1, voice) == 80, 'accent index1');
    assert(derive_velocity(2, voice) == 120, 'accent wraps');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_pattern_count() {
    assert(num_velocity_patterns() == 5, 'five velocity patterns');
    let mut c: u8 = 0;
    loop {
        if c.into() >= num_velocity_patterns() {
            break;
        }
        assert(velocity_pattern(c).len() > 0, 'pattern non-empty');
        c += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Template Table Integrity
// ──────────────────────────────────────────────────────────

fn check_template_table(n: u32) {
    let templates = templates_for(n);
    let mut i: u32 = 0;
    loop {
        if i >= templates.len() {
            break;
        }
        let tmpl = *templates.at(i);
        assert(tmpl.n == n, 'template n matches');

        // Direct sum holds.
        assert(is_direct_sum(n, tmpl.r_base, tmpl.s_base), 'template tiles');

        // Cardinalities.
        assert(tmpl.r_base.len() == tmpl.k, 'r len == k');
        assert(tmpl.r_base.len() * tmpl.s_base.len() == n, 'rk * sk == n');
        assert(tmpl.r_base.len() >= MIN_TILE_ONSETS, 'k >= MIN_TILE_ONSETS');
        assert(tmpl.s_base.len() <= MAX_VOICES, '|S| <= MAX_VOICES');

        // s_base is the polynomial complement of r_base.
        assert_some_eq(find_complement(n, tmpl.r_base), to_array(tmpl.s_base), 'complement == s_base');

        // Durations are correct and sum to n.
        let durs = legato_durations(tmpl.r_base, n);
        assert(span_eq(durs.span(), tmpl.durations), 'durations match');
        assert(sum_span(tmpl.durations) == n, 'durations sum to n');

        // Sets are sorted, in-range, deduplicated.
        assert(is_sorted_unique(tmpl.r_base, n), 'r sorted unique in range');
        assert(is_sorted_unique(tmpl.s_base, n), 's sorted unique in range');

        i += 1;
    };
}

fn to_array(s: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= s.len() {
            break;
        }
        out.append(*s.at(i));
        i += 1;
    };
    out
}

fn is_sorted_unique(s: Span<u32>, n: u32) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= s.len() {
            break;
        }
        if *s.at(i) >= n {
            ok = false;
            break;
        }
        if i + 1 < s.len() {
            if *s.at(i) >= *s.at(i + 1) {
                ok = false;
                break;
            }
        }
        i += 1;
    };
    ok
}

#[test]
#[available_gas(1000000000000)]
fn test_template_table_integrity_8() {
    check_template_table(8);
}

#[test]
#[available_gas(1000000000000)]
fn test_template_table_integrity_12() {
    check_template_table(12);
}

#[test]
#[available_gas(1000000000000)]
fn test_template_table_integrity_16() {
    check_template_table(16);
}

#[test]
#[available_gas(1000000000000)]
fn test_template_table_integrity_24() {
    check_template_table(24);
}

#[test]
#[available_gas(1000000000000)]
fn test_every_supported_n_has_templates() {
    let ns = gen_supported_n();
    let mut i: u32 = 0;
    loop {
        if i >= ns.len() {
            break;
        }
        let n = *ns.at(i);
        assert(templates_for(n).len() > 0, 'n has templates');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_each_n_has_class2_entry() {
    let ns = gen_supported_n();
    let mut i: u32 = 0;
    loop {
        if i >= ns.len() {
            break;
        }
        let templates = templates_for(*ns.at(i));
        let mut has2 = false;
        let mut j: u32 = 0;
        loop {
            if j >= templates.len() {
                break;
            }
            if *templates.at(j).syncopation_class == 2 {
                has2 = true;
            }
            j += 1;
        };
        assert(has2, 'n has a class-2 template');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Event Generation & Generator Pipeline
// ──────────────────────────────────────────────────────────

/// Verify a participant-event stream covers every position in 0..n exactly once.
fn assert_full_cover(events: Span<OnsetEvent>, n: u32) {
    assert(events.len() == n, 'events len == n');
    let mut counts: Felt252Dict<u32> = Default::default();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        assert(e.time < n, 'time in range');
        assert(e.duration > 0, 'duration positive');
        counts.insert(e.time.into(), counts.get(e.time.into()) + 1);
        i += 1;
    };
    let mut p: u32 = 0;
    loop {
        if p >= n {
            break;
        }
        assert(counts.get(p.into()) == 1, 'each position once');
        p += 1;
    };
}

fn events_equal(a: Span<OnsetEvent>, b: Span<OnsetEvent>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: u32 = 0;
    let mut res = true;
    loop {
        if i >= a.len() {
            break;
        }
        let x = *a.at(i);
        let y = *b.at(i);
        if x.time != y.time
            || x.duration != y.duration
            || x.voice_id != y.voice_id
            || x.velocity != y.velocity {
            res = false;
            break;
        }
        i += 1;
    };
    res
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_to_events_full_cover() {
    let canon = generate_rhythmic_canon(123456);
    let events = canon_to_events(@canon);
    assert_full_cover(events.span(), canon.n);
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_events_sorted_by_time() {
    let canon = generate_rhythmic_canon(987654321);
    let events = canon_to_events(@canon);
    let span = events.span();
    let mut i: u32 = 0;
    loop {
        if i + 1 >= span.len() {
            break;
        }
        assert(*span.at(i).time <= *span.at(i + 1).time, 'events sorted by time');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_is_valid_tiling() {
    let canon = generate_rhythmic_canon(42);
    assert(is_direct_sum(canon.n, canon.rhythm_tile, canon.translations), 'generated tiling valid');
    assert(sum_span(canon.durations) == canon.n, 'generated durs sum n');
    assert(canon.voices.len() == canon.translations.len(), 'voice per translation');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_deterministic() {
    let c1 = generate_rhythmic_canon(0xABCDEF);
    let c2 = generate_rhythmic_canon(0xABCDEF);
    let e1 = canon_to_events(@c1);
    let e2 = canon_to_events(@c2);
    assert(events_equal(e1.span(), e2.span()), 'same seed same events');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_seeds_differ() {
    // Sweep seeds and confirm at least two distinct event streams appear.
    let base = generate_rhythmic_canon(1);
    let base_events = canon_to_events(@base);
    let mut seed: felt252 = 2;
    let mut differ = false;
    let mut tries: u32 = 0;
    loop {
        if tries >= 40 || differ {
            break;
        }
        let c = generate_rhythmic_canon(seed);
        let e = canon_to_events(@c);
        if !events_equal(base_events.span(), e.span()) {
            differ = true;
        }
        seed += 7;
        tries += 1;
    };
    assert(differ, 'different seeds differ');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_all_seeds_valid_cover() {
    // Every seed in a sweep must produce a fully-covering, valid tiling.
    let mut seed: felt252 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= 32 {
            break;
        }
        let canon = generate_rhythmic_canon(seed);
        let events = canon_to_events(@canon);
        assert_full_cover(events.span(), canon.n);
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_traits() {
    let canon = generate_rhythmic_canon(555);
    let traits = canon_traits(@canon);
    assert(traits.cycle_length == canon.n, 'trait cycle length');
    assert(traits.tile_size == canon.rhythm_tile.len(), 'trait tile size');
    assert(traits.voice_count == canon.translations.len(), 'trait voice count');
    assert(traits.tile_size * traits.voice_count == canon.n, 'trait card product');
}

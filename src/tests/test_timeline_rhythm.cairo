use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::known_timeline_rhythms::{all_preset_ids, son_family_canonical_ioi};
use koji::composition::phase_rhythm::{phase_orbit_length, render_phase_plan, PhaseRhythmPlan};
use koji::composition::timeline_rhythm::{
    PRESET_BOSSA_NOVA, PRESET_GAHU, PRESET_RUMBA, PRESET_SHIKO, PRESET_SON, PRESET_SOUKOUS,
    SOURCE_INTERVAL_VARIANT, SOURCE_MORPH, SOURCE_PRESET, SYMMETRY_ANY, SYMMETRY_NONE,
    SYMMETRY_STRONG, SYMMETRY_WEAK, TIMELINE_N, TIMELINE_ONSETS, NO_PRESET, SON_FAMILY_CANDIDATES,
    TimelineRhythm, TimelineSelectionProfile, canonical_ioi_rotation, cyclic_interval_distance_sq,
    generate_profiled_son_family_timeline, generate_son_family_timeline, ioi_to_mask, is_onset,
    known_morph_edges, known_pressing_complexity_x2, known_timeline, known_timeline_name,
    mask_to_ioi, mask_to_onsets, metric_complexity_5_on_16, next_known_morph, onsets_to_mask,
    popcount_u32, rotate_mask, single_onset_displacement, son_family_candidate_at_index,
    timeline_accent, timeline_gate, timeline_symmetry_class, timeline_to_events, timeline_traits,
    validate_timeline_mask,
};

// ──────────────────────────────────────────────────────────
// Test helpers
// ──────────────────────────────────────────────────────────

fn span_eq_u32(a: Span<u32>, b: Span<u32>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        if *a.at(i) != *b.at(i) {
            return false;
        }
        i += 1;
    };
    true
}

fn assert_span_eq(actual: Array<u32>, expected: Array<u32>, msg: felt252) {
    assert(span_eq_u32(actual.span(), expected.span()), msg);
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

fn masks_equal_mod_rotation(n: u32, a: u32, b: u32) -> bool {
    if a == b {
        return true;
    }
    let mut r: u32 = 1;
    loop {
        if r >= n {
            break;
        }
        if rotate_mask(n, a, r) == b {
            return true;
        }
        r += 1;
    };
    false
}

// ──────────────────────────────────────────────────────────
// Preset fixtures
// ──────────────────────────────────────────────────────────

#[test]
fn test_preset_masks() {
    assert(known_timeline(PRESET_SHIKO).unwrap().onset_mask == 0x1451_u32, 'shiko mask');
    assert(known_timeline(PRESET_SON).unwrap().onset_mask == 0x1449_u32, 'son mask');
    assert(known_timeline(PRESET_SOUKOUS).unwrap().onset_mask == 0x0C49_u32, 'soukous mask');
    assert(known_timeline(PRESET_RUMBA).unwrap().onset_mask == 0x1489_u32, 'rumba mask');
    assert(known_timeline(PRESET_BOSSA_NOVA).unwrap().onset_mask == 0x2449_u32, 'bossa mask');
    assert(known_timeline(PRESET_GAHU).unwrap().onset_mask == 0x4449_u32, 'gahu mask');
}

#[test]
fn test_preset_onsets() {
    assert_span_eq(
        mask_to_onsets(16, 0x1451_u32),
        array![0_u32, 4, 6, 10, 12],
        'shiko onsets',
    );
    assert_span_eq(
        mask_to_onsets(16, 0x1449_u32),
        array![0_u32, 3, 6, 10, 12],
        'son onsets',
    );
    assert_span_eq(
        mask_to_onsets(16, 0x0C49_u32),
        array![0_u32, 3, 6, 10, 11],
        'soukous onsets',
    );
    assert_span_eq(
        mask_to_onsets(16, 0x1489_u32),
        array![0_u32, 3, 7, 10, 12],
        'rumba onsets',
    );
    assert_span_eq(
        mask_to_onsets(16, 0x2449_u32),
        array![0_u32, 3, 6, 10, 13],
        'bossa onsets',
    );
    assert_span_eq(
        mask_to_onsets(16, 0x4449_u32),
        array![0_u32, 3, 6, 10, 14],
        'gahu onsets',
    );
}

#[test]
fn test_preset_ioi_vectors() {
    assert_span_eq(
        mask_to_ioi(16, 0x1451_u32).unwrap(),
        array![4_u32, 2, 4, 2, 4],
        'shiko ioi',
    );
    assert_span_eq(
        mask_to_ioi(16, 0x1449_u32).unwrap(),
        array![3_u32, 3, 4, 2, 4],
        'son ioi',
    );
    assert_span_eq(
        mask_to_ioi(16, 0x0C49_u32).unwrap(),
        array![3_u32, 3, 4, 1, 5],
        'soukous ioi',
    );
    assert_span_eq(
        mask_to_ioi(16, 0x1489_u32).unwrap(),
        array![3_u32, 4, 3, 2, 4],
        'rumba ioi',
    );
    assert_span_eq(
        mask_to_ioi(16, 0x2449_u32).unwrap(),
        array![3_u32, 3, 4, 3, 3],
        'bossa ioi',
    );
    assert_span_eq(
        mask_to_ioi(16, 0x4449_u32).unwrap(),
        array![3_u32, 3, 4, 4, 2],
        'gahu ioi',
    );
}

#[test]
fn test_preset_families_and_source() {
    let shiko = known_timeline(PRESET_SHIKO).unwrap();
    assert(shiko.family_id == 1, 'shiko family');
    assert(shiko.source_kind == SOURCE_PRESET, 'shiko source');
    assert(shiko.preset_id == PRESET_SHIKO, 'shiko preset id');

    let son = known_timeline(PRESET_SON).unwrap();
    assert(son.family_id == 2, 'son family');
    assert(son.variant_id == 3, 'son variant');
    assert(son.rotation == 10, 'son rotation');
}

#[test]
fn test_unknown_preset_returns_none() {
    assert(known_timeline(0).is_none(), 'preset 0 none');
    assert(known_timeline(7).is_none(), 'preset 7 none');
    assert(known_timeline(255).is_none(), 'preset 255 none');
    assert(known_pressing_complexity_x2(0).is_none(), 'pressing 0 none');
}

#[test]
fn test_preset_names() {
    assert(known_timeline_name(PRESET_SHIKO) == 'Shiko', 'shiko name');
    assert(known_timeline_name(PRESET_SON) == 'Son', 'son name');
    assert(known_timeline_name(PRESET_SOUKOUS) == 'Soukous', 'soukous name');
    assert(known_timeline_name(PRESET_RUMBA) == 'Rumba', 'rumba name');
    assert(known_timeline_name(PRESET_BOSSA_NOVA) == 'Bossa-Nova', 'bossa name');
    assert(known_timeline_name(PRESET_GAHU) == 'Gahu', 'gahu name');
    assert(known_timeline_name(0) == 'unknown', 'unknown name');
}

#[test]
fn test_pressing_metadata() {
    assert(known_pressing_complexity_x2(PRESET_SHIKO).unwrap() == 12, 'shiko pressing');
    assert(known_pressing_complexity_x2(PRESET_SON).unwrap() == 29, 'son pressing');
    assert(known_pressing_complexity_x2(PRESET_SOUKOUS).unwrap() == 30, 'soukous pressing');
    assert(known_pressing_complexity_x2(PRESET_RUMBA).unwrap() == 34, 'rumba pressing');
    assert(known_pressing_complexity_x2(PRESET_BOSSA_NOVA).unwrap() == 44, 'bossa pressing');
    assert(known_pressing_complexity_x2(PRESET_GAHU).unwrap() == 39, 'gahu pressing');
}

// ──────────────────────────────────────────────────────────
// Representation round trips
// ──────────────────────────────────────────────────────────

#[test]
fn test_onset_mask_round_trip_all_presets() {
    let ids = all_preset_ids();
    let mut i: u32 = 0;
    loop {
        if i >= ids.len() {
            break;
        }
        let preset_id = *ids.at(i);
        let rhythm = known_timeline(preset_id).unwrap();
        let onsets = mask_to_onsets(rhythm.n, rhythm.onset_mask);
        let round = onsets_to_mask(rhythm.n, onsets.span()).unwrap();
        assert(round == rhythm.onset_mask, 'onset round trip');
        i += 1;
    };
}

#[test]
fn test_ioi_round_trip_all_presets() {
    let ids = all_preset_ids();
    let mut i: u32 = 0;
    loop {
        if i >= ids.len() {
            break;
        }
        let preset_id = *ids.at(i);
        let rhythm = known_timeline(preset_id).unwrap();
        let ioi = mask_to_ioi(rhythm.n, rhythm.onset_mask).unwrap();
        assert(sum_span(ioi.span()) == 16, 'ioi sums to 16');
        let rebuilt = ioi_to_mask(rhythm.n, ioi.span()).unwrap();
        assert(
            masks_equal_mod_rotation(rhythm.n, rebuilt, rhythm.onset_mask),
            'ioi round trip rotation',
        );
        i += 1;
    };
}

#[test]
fn test_validate_timeline_mask() {
    assert(validate_timeline_mask(16, 5, 0x1449_u32), 'son valid');
    assert(!validate_timeline_mask(0, 5, 0x1449_u32), 'n zero invalid');
    assert(!validate_timeline_mask(33, 5, 0x1449_u32), 'n too large');
    assert(!validate_timeline_mask(16, 5, 0x10000_u32), 'high bit invalid');
    assert(!validate_timeline_mask(16, 4, 0x1449_u32), 'wrong popcount');
}

#[test]
fn test_onsets_to_mask_rejects_duplicates() {
    let dup = array![0_u32, 0, 3];
    assert(onsets_to_mask(16, dup.span()).is_none(), 'duplicate onset');
}

#[test]
fn test_onsets_to_mask_rejects_out_of_range() {
    let bad = array![0_u32, 16];
    assert(onsets_to_mask(16, bad.span()).is_none(), 'onset out of range');
}

#[test]
fn test_ioi_to_mask_rejects_zero_and_bad_sum() {
    let zero = array![0_u32, 3, 3, 4, 6];
    assert(ioi_to_mask(16, zero.span()).is_none(), 'zero ioi');
    let bad_sum = array![3_u32, 3, 3, 3, 3];
    assert(ioi_to_mask(16, bad_sum.span()).is_none(), 'bad ioi sum');
}

#[test]
fn test_popcount_and_is_onset() {
    assert(popcount_u32(0x1449_u32) == 5, 'son popcount');
    assert(is_onset(0x1449_u32, 0), 'onset at 0');
    assert(is_onset(0x1449_u32, 3), 'onset at 3');
    assert(!is_onset(0x1449_u32, 1), 'rest at 1');
}

// ──────────────────────────────────────────────────────────
// Metric complexity and symmetry
// ──────────────────────────────────────────────────────────

#[test]
fn test_preset_metric_complexity() {
    assert(metric_complexity_5_on_16(0x1451_u32).unwrap() == 2, 'shiko metric');
    assert(metric_complexity_5_on_16(0x1449_u32).unwrap() == 4, 'son metric');
    assert(metric_complexity_5_on_16(0x0C49_u32).unwrap() == 6, 'soukous metric');
    assert(metric_complexity_5_on_16(0x1489_u32).unwrap() == 5, 'rumba metric');
    assert(metric_complexity_5_on_16(0x2449_u32).unwrap() == 6, 'bossa metric');
    assert(metric_complexity_5_on_16(0x4449_u32).unwrap() == 5, 'gahu metric');
}

#[test]
fn test_rotation_changes_metric_complexity() {
    let son = known_timeline(PRESET_SON).unwrap();
    let rotated = rotate_mask(16, son.onset_mask, 1);
    let son_metric = metric_complexity_5_on_16(son.onset_mask).unwrap();
    let rot_metric = metric_complexity_5_on_16(rotated).unwrap();
    assert(son_metric != rot_metric, 'rotation changes metric');
}

#[test]
fn test_preset_symmetry_classes() {
    assert(timeline_symmetry_class(16, 0x1451_u32) == SYMMETRY_STRONG, 'shiko strong');
    assert(timeline_symmetry_class(16, 0x1449_u32) == SYMMETRY_WEAK, 'son weak');
    assert(timeline_symmetry_class(16, 0x0C49_u32) == SYMMETRY_NONE, 'soukous none');
    assert(timeline_symmetry_class(16, 0x1489_u32) == SYMMETRY_NONE, 'rumba none');
    assert(timeline_symmetry_class(16, 0x2449_u32) == SYMMETRY_STRONG, 'bossa strong');
    assert(timeline_symmetry_class(16, 0x4449_u32) == SYMMETRY_NONE, 'gahu none');
}

#[test]
fn test_timeline_traits_presets() {
    let ids = all_preset_ids();
    let expected_metrics = array![2_u16, 4, 6, 5, 6, 5];
    let expected_symmetry = array![
        SYMMETRY_STRONG, SYMMETRY_WEAK, SYMMETRY_NONE, SYMMETRY_NONE, SYMMETRY_STRONG,
        SYMMETRY_NONE,
    ];
    let expected_pressing = array![12_u16, 29, 30, 34, 44, 39];
    let mut i: u32 = 0;
    loop {
        if i >= ids.len() {
            break;
        }
        let rhythm = known_timeline(*ids.at(i)).unwrap();
        let traits = timeline_traits(@rhythm);
        assert(traits.metric_complexity == *expected_metrics.at(i), 'trait metric');
        assert(traits.symmetry_class == *expected_symmetry.at(i), 'trait symmetry');
        assert(traits.has_pressing_score, 'pressing exposed');
        assert(traits.pressing_complexity_x2 == *expected_pressing.at(i), 'trait pressing');
        i += 1;
    };
}

#[test]
fn test_timeline_traits_no_pressing_for_non_preset() {
    let generated = TimelineRhythm {
        n: TIMELINE_N,
        onset_mask: 0x1449_u32,
        onset_count: TIMELINE_ONSETS,
        family_id: 2,
        variant_id: 3,
        rotation: 10,
        preset_id: 0,
        source_kind: 2,
    };
    let traits = timeline_traits(@generated);
    assert(!traits.has_pressing_score, 'no pressing for generated');
}

#[test]
fn test_cyclic_distance_self_zero() {
    let son = known_timeline(PRESET_SON).unwrap();
    assert(cyclic_interval_distance_sq(@son, @son).unwrap() == 0, 'self distance zero');
}

#[test]
fn test_canonical_ioi_idempotent_son() {
    let ioi = mask_to_ioi(16, 0x1449_u32).unwrap();
    let canonical = canonical_ioi_rotation(ioi.span());
    let again = canonical_ioi_rotation(canonical.span());
    assert_span_eq(canonical, again, 'canonical idempotent');
}

#[test]
fn test_son_family_canonical_table() {
    let mut vid: u16 = 0;
    loop {
        if vid >= 6 {
            break;
        }
        let ioi = son_family_canonical_ioi(vid).unwrap();
        let canonical = canonical_ioi_rotation(ioi.span());
        assert_span_eq(ioi, canonical, 'variant canonical');
        vid += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Son-family generation
// ──────────────────────────────────────────────────────────

fn is_son_family_ioi(ioi: Span<u32>) -> bool {
    if ioi.len() != 5 {
        return false;
    }
    let mut sorted: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= ioi.len() {
            break;
        }
        let v = *ioi.at(i);
        let mut next: Array<u32> = ArrayTrait::new();
        let mut inserted = false;
        let mut j: u32 = 0;
        loop {
            if j >= sorted.len() {
                break;
            }
            let cur = *sorted.at(j);
            if !inserted && v < cur {
                next.append(v);
                inserted = true;
            }
            next.append(cur);
            j += 1;
        };
        if !inserted {
            next.append(v);
        }
        sorted = next;
        i += 1;
    };
    *sorted.at(0) == 2
        && *sorted.at(1) == 3
        && *sorted.at(2) == 3
        && *sorted.at(3) == 4
        && *sorted.at(4) == 4
}

#[test]
fn test_generate_son_family_deterministic() {
    let a = generate_son_family_timeline(42);
    let b = generate_son_family_timeline(42);
    assert(a.onset_mask == b.onset_mask, 'seed deterministic');
    assert(a.preset_id == NO_PRESET, 'no preset id');
    assert(a.source_kind == SOURCE_INTERVAL_VARIANT, 'interval source');
}

#[test]
fn test_generate_son_family_invariants() {
    let rhythm = generate_son_family_timeline(99);
    assert(validate_timeline_mask(16, 5, rhythm.onset_mask), 'valid mask');
    assert(popcount_u32(rhythm.onset_mask) == 5, 'five onsets');
    let ioi = mask_to_ioi(16, rhythm.onset_mask).unwrap();
    assert(is_son_family_ioi(ioi.span()), 'son multiset');
}

#[test]
fn test_generate_son_family_all_orientations() {
    let mut v: u16 = 0;
    loop {
        if v >= 6 {
            break;
        }
        let mut r: u32 = 0;
        loop {
            if r >= 16 {
                break;
            }
            let low: u32 = v.into() + r * 8;
            let seed: felt252 = low.into();
            let rhythm = generate_son_family_timeline(seed);
            assert(rhythm.variant_id == v, 'variant id');
            assert(rhythm.rotation == r.try_into().unwrap(), 'rotation');
            r += 1;
        };
        v += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_profiled_generation_bounded_scan() {
    let profile = TimelineSelectionProfile {
        target_metric_complexity: 4,
        metric_weight: 1,
        target_son_distance_sq: 0,
        distance_weight: 1,
        preferred_symmetry: SYMMETRY_ANY,
        symmetry_penalty: 0,
    };
    let result = generate_profiled_son_family_timeline(7, profile);
    assert(result.preset_id == NO_PRESET, 'profiled no preset');
    assert(validate_timeline_mask(16, 5, result.onset_mask), 'profiled valid');
}

#[test]
fn test_cyclic_distance_symmetric() {
    let son = known_timeline(PRESET_SON).unwrap();
    let gahu = known_timeline(PRESET_GAHU).unwrap();
    let d1 = cyclic_interval_distance_sq(@son, @gahu).unwrap();
    let d2 = cyclic_interval_distance_sq(@gahu, @son).unwrap();
    assert(d1 == d2, 'distance symmetric');
}

#[test]
fn test_cyclic_distance_rotation_invariant() {
    let son = known_timeline(PRESET_SON).unwrap();
    let rotated = TimelineRhythm {
        n: son.n,
        onset_mask: rotate_mask(16, son.onset_mask, 3),
        onset_count: son.onset_count,
        family_id: son.family_id,
        variant_id: son.variant_id,
        rotation: 3,
        preset_id: NO_PRESET,
        source_kind: SOURCE_INTERVAL_VARIANT,
    };
    let d_self = cyclic_interval_distance_sq(@son, @son).unwrap();
    let d_rot = cyclic_interval_distance_sq(@son, @rotated).unwrap();
    assert(d_rot == d_self, 'rotation invariant distance');
}

#[test]
fn test_son_family_candidate_index_roundtrip() {
    let mut i: u32 = 0;
    loop {
        if i >= SON_FAMILY_CANDIDATES {
            break;
        }
        let rhythm = son_family_candidate_at_index(i);
        let idx = rhythm.variant_id.into() * 16 + rhythm.rotation.into();
        assert(idx == i, 'candidate index');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Morph graph and phrasing adapters
// ──────────────────────────────────────────────────────────

#[test]
fn test_single_onset_displacement_presets() {
    let son = known_timeline(PRESET_SON).unwrap();
    let shiko = known_timeline(PRESET_SHIKO).unwrap();
    let rumba = known_timeline(PRESET_RUMBA).unwrap();
    let bossa = known_timeline(PRESET_BOSSA_NOVA).unwrap();
    let gahu = known_timeline(PRESET_GAHU).unwrap();
    assert(single_onset_displacement(16, son.onset_mask, shiko.onset_mask).unwrap() == 1, 'son shiko');
    assert(single_onset_displacement(16, son.onset_mask, rumba.onset_mask).unwrap() == 1, 'son rumba');
    assert(
        single_onset_displacement(16, bossa.onset_mask, gahu.onset_mask).unwrap() == 1, 'bossa gahu',
    );
}

#[test]
fn test_single_onset_displacement_two_moves_none() {
    let shiko = known_timeline(PRESET_SHIKO).unwrap();
    let gahu = known_timeline(PRESET_GAHU).unwrap();
    assert(
        single_onset_displacement(16, shiko.onset_mask, gahu.onset_mask).is_none(), 'two moves',
    );
}

#[test]
fn test_known_morph_graph_five_edges() {
    assert(known_morph_edges(1).len() == 5, 'five morph edges');
}

#[test]
fn test_next_known_morph_from_son() {
    let next = next_known_morph(0, PRESET_SON, 1).unwrap();
    assert(next.source_kind == SOURCE_MORPH, 'morph source');
    assert(next.preset_id != PRESET_SON, 'different preset');
    assert(next.preset_id != NO_PRESET, 'named preset kept');
}

#[test]
fn test_timeline_gate_and_accent() {
    let son = known_timeline(PRESET_SON).unwrap();
    assert(timeline_gate(@son, 0), 'onset at 0');
    assert(timeline_gate(@son, 16), 'onset cycle wrap');
    assert(!timeline_gate(@son, 1), 'rest at 1');
    assert(timeline_accent(@son, 0, 100, 40) == 100, 'accent on');
    assert(timeline_accent(@son, 1, 100, 40) == 40, 'accent off');
}

#[test]
fn test_timeline_to_events() {
    let son = known_timeline(PRESET_SON).unwrap();
    let events = timeline_to_events(@son, 2, 7, 90);
    assert(events.len() == 10, 'two cycles five onsets');
    assert(*events.at(0).time == 0, 'first event time');
    assert(*events.at(5).time == 16, 'second cycle start');
    assert(*events.at(0).voice_id == 7, 'voice id');
    assert(*events.at(0).velocity == 90, 'velocity');
}

// ──────────────────────────────────────────────────────────
// Fuzz / property guards (acceptance)
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_fuzz_son_generation_invariants() {
    let mut seed: felt252 = 0;
    let mut count: u32 = 0;
    loop {
        if count >= 96 {
            break;
        }
        let rhythm = generate_son_family_timeline(seed);
        assert(rhythm.n == TIMELINE_N, 'fuzz n');
        assert(rhythm.onset_count == TIMELINE_ONSETS, 'fuzz onsets');
        assert(validate_timeline_mask(16, 5, rhythm.onset_mask), 'fuzz valid');
        assert(rhythm.preset_id == NO_PRESET, 'fuzz no preset');
        assert(rhythm.source_kind == SOURCE_INTERVAL_VARIANT, 'fuzz source');
        assert(mask_to_ioi(16, rhythm.onset_mask).is_some(), 'fuzz ioi total');
        seed += 1;
        count += 1;
    };
}

#[test]
fn test_generated_never_named_even_when_mask_matches_preset() {
    let son = known_timeline(PRESET_SON).unwrap();
    let generated = TimelineRhythm {
        n: son.n,
        onset_mask: son.onset_mask,
        onset_count: son.onset_count,
        family_id: son.family_id,
        variant_id: son.variant_id,
        rotation: son.rotation,
        preset_id: NO_PRESET,
        source_kind: SOURCE_INTERVAL_VARIANT,
    };
    assert(generated.preset_id == NO_PRESET, 'no false preset');
    let traits = timeline_traits(@generated);
    assert(!traits.has_pressing_score, 'no pressing when unnamed');
}

#[test]
#[available_gas(1000000000000)]
fn test_fuzz_phase_plan_renderable() {
    let son = known_timeline(PRESET_SON).unwrap();
    let mut shift: u8 = 1;
    loop {
        if shift >= 8 {
            break;
        }
        let plan = PhaseRhythmPlan {
            base: son,
            repeats_per_shift: 1,
            shift_step: shift,
            phase_count: 2,
            static_voice_id: 0,
            rotating_voice_id: 1,
            static_velocity: 90,
            rotating_velocity: 70,
        };
        assert(phase_orbit_length(16, shift.into()).is_some(), 'orbit some');
        let events = render_phase_plan(@plan);
        let event_count: u32 = events.len();
        assert(event_count == 20, 'phase events');
        let mut i: u32 = 0;
        loop {
            if i >= event_count {
                break;
            }
            let e = *events.at(i);
            assert(e.time >= 0, 'time nn');
            i += 1;
        };
        shift += 1;
    };
}

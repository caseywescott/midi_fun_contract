use core::array::ArrayTrait;
use koji::composition::canon_rules::is_consonant_class;
use koji::composition::aesthetic_profile::{
    PROFILE_RENAISSANCE_INVERTIBLE_ID, profile_by_id, profile_renaissance,
};
use koji::composition::melodic_canon::{
    NoteEvent, BandEnvelope, constant_band, walk_leader_banded_ic,
};
use koji::composition::jazz_harmony::turnaround_plan_default;

// ── canon_inversion ───────────────────────────────────────────
use koji::composition::canon_inversion::{
    FollowerSpec, follower_degree_for_spec, follower_degree_retrograde,
    inversion_vertical_class, inversion_step_consonant,
    generate_inversion_canon, inversion_canon_to_note_events,
    inversion_canon_clash_free, strict_melodic_inversion, pivot_at_fifth, pivot_at_third,
    pivot_at_unison, walk_leader_for_inversion,
    realize_retrograde_follower, realize_augmented_follower, realize_diminuted_follower,
    retrograde_follower_clash_free, augmented_follower_clash_free,
    apply_follower_spec_events,
};

// ── invertible_counterpoint ───────────────────────────────────
use koji::composition::invertible_counterpoint::{
    semitone_class, is_perfect_fifth_class, ic_pair_safe, is_invertible_at_octave, count_fifths,
    raise_octave, lower_octave, octave_invert_pair, is_diatonic_fifth,
    diatonic_ic_safe, lattice_interval_class, lattice_fifth_class, lattice_ic_safe,
    vertical_ok_invertible, all_pairs_octave_invertible, all_pairs_convertible_counterpoint,
    generate_invertible_melodic_canon,
    InvertibleVerticalPolicy, vertical_ok_with_policy, renaissance_ic_policy, ic_policy_from_id,
};

// ── stretto ───────────────────────────────────────────────────
use koji::composition::stretto::{
    StrettoPlan, default_stretto_plan, renaissance_stretto_plan, stretto_lag,
    voice_entry_time, stretto_entry_times, kills_to_lag, stretto_intensity,
    stretto_plan_valid, entries_ordered, is_genuine_stretto,
};

// ── countersubject ────────────────────────────────────────────
use koji::composition::countersubject::{
    CountersubjectConfig, default_countersubject_config, below_countersubject_config,
    generate_countersubject, countersubject_to_note_events, countersubject_consonant,
    countersubject_invertible, countersubject_conjunct, canon_with_countersubject,
};

// ── compound_melody ───────────────────────────────────────────
use koji::composition::compound_melody::{
    CompoundMelodyConfig, default_compound_config,
    generate_compound_melody, split_compound_voices, compound_high_voice, compound_low_voice,
    merge_voices, compound_has_both_registers, compound_pitches_valid,
};

// ═══════════════════════════════════════════════════════════════
// § 1 — Canon by Inversion
// ═══════════════════════════════════════════════════════════════

#[test]
#[available_gas(1000000000000)]
fn test_follower_spec_transposition() {
    let spec = FollowerSpec::Transposition(4_i32);
    assert(follower_degree_for_spec(spec, 0) == 4, 'T: 0+4');
    assert(follower_degree_for_spec(spec, 3) == 7, 'T: 3+4');
    assert(follower_degree_for_spec(spec, -2) == 2, 'T: -2+4');
}

#[test]
#[available_gas(1000000000000)]
fn test_follower_spec_inversion() {
    let spec = FollowerSpec::Inversion(4_i32);
    // pivot=4: follower = 4 - leader_deg
    assert(follower_degree_for_spec(spec, 0) == 4, 'Inv: pivot-0');
    assert(follower_degree_for_spec(spec, 3) == 1, 'Inv: pivot-3');
    assert(follower_degree_for_spec(spec, 4) == 0, 'Inv: pivot-4');
}

#[test]
#[available_gas(1000000000000)]
fn test_follower_spec_inversion_negates_steps() {
    // Step from deg=1 to deg=3 is +2; inverted follower step must be -2.
    let spec = FollowerSpec::Inversion(0_i32);
    let f0 = follower_degree_for_spec(spec, 1);  // 0 - 1 = -1
    let f1 = follower_degree_for_spec(spec, 3);  // 0 - 3 = -3
    assert(f1 - f0 == -2, 'inversion negates step');
}

#[test]
#[available_gas(1000000000000)]
fn test_pivot_helpers() {
    assert(pivot_at_fifth() == 4, 'pivot fifth');
    assert(pivot_at_third() == 2, 'pivot third');
    assert(pivot_at_unison() == 0, 'pivot unison');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_vertical_class_zero_overlap() {
    // cur=0, m=2, prev=0, pivot=4 → vertical=(0+2)+0-4 = -2 → cls = 2
    let cls = inversion_vertical_class(0, 2, 0, 4);
    assert(cls == 2, 'cls should be 2 (third)');
    assert(is_consonant_class(cls), 'third is consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_step_not_in_overlap_always_consonant() {
    // Before the follower enters, any step is OK
    assert(inversion_step_consonant(0, -7, 0, 4, false), 'no overlap = ok');
    assert(inversion_step_consonant(3, 5, 2, 4, false), 'no overlap = ok 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_step_in_overlap_filters_dissonant() {
    // pivot=0: vertical = (cur+m) + prev_at_lag - 0 = cur+m+prev
    // cur=0, prev=0: vertical = m. For m=1 (2nd), cls=1, dissonant.
    assert(!inversion_step_consonant(0, 1, 0, 0, true), 'second: dissonant');
    // m=2 (3rd), cls=2, consonant
    assert(inversion_step_consonant(0, 2, 0, 0, true), 'third: consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_for_inversion_length() {
    let (degs, steps) = walk_leader_for_inversion(42, 8, 4, 1);
    assert(degs.len() == 8, 'degrees length');
    assert(steps.len() == 7, 'steps length');
}

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_starts_on_zero() {
    let (degs, _) = walk_leader_for_inversion(42, 6, 4, 1);
    assert(*degs.at(0) == 0, 'starts on 0');
}

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_deterministic() {
    let (d1, _) = walk_leader_for_inversion(99, 8, 4, 1);
    let (d2, _) = walk_leader_for_inversion(99, 8, 4, 1);
    let mut i: u32 = 0;
    loop {
        if i >= 8 { break; }
        assert(*d1.at(i) == *d2.at(i), 'deterministic');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_inversion_canon_smoke() {
    let canon = generate_inversion_canon(123, 8, 4, 1, 7, 5, 60, 480, 0, 1);
    assert(canon.leader_degrees.len() == 8, 'len');
    assert(canon.pivot == 4, 'pivot');
    assert(canon.lag == 1, 'lag');
    assert(*canon.leader_degrees.at(0) == 0, 'starts 0');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_canon_clash_free_pivot4_lag1() {
    // Pivot at fifth (4), lag 1: should be clash-free by construction.
    let canon = generate_inversion_canon(7, 10, 4, 1, 7, 5, 60, 480, 0, 1);
    assert(inversion_canon_clash_free(@canon), 'clash free pivot=4 lag=1');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_canon_clash_free_pivot2_lag1() {
    let canon = generate_inversion_canon(77, 10, 2, 1, 7, 5, 60, 480, 0, 1);
    assert(inversion_canon_clash_free(@canon), 'clash free pivot=2 lag=1');
}

#[test]
#[available_gas(1000000000000)]
fn test_strict_melodic_inversion_holds() {
    let canon = generate_inversion_canon(55, 8, 4, 1, 7, 5, 60, 480, 0, 1);
    // Every leader step must be negated in the follower.
    assert(strict_melodic_inversion(@canon), 'strict inversion');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_canon_event_count() {
    // len=8 degrees: leader emits 8 events, follower emits 8 events → 16 total
    let canon = generate_inversion_canon(1, 8, 4, 1, 7, 5, 60, 480, 0, 1);
    let events = inversion_canon_to_note_events(@canon);
    assert(events.len() == 16, 'event count 2x len');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_canon_voice_ids_separate() {
    let canon = generate_inversion_canon(1, 6, 4, 1, 7, 5, 60, 480, 0, 1);
    let events = inversion_canon_to_note_events(@canon);
    let mut has0 = false;
    let mut has1 = false;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() { break; }
        if (*events.at(i)).voice_id == 0 { has0 = true; }
        if (*events.at(i)).voice_id == 1 { has1 = true; }
        i += 1;
    };
    assert(has0, 'has leader events');
    assert(has1, 'has follower events');
}

// ═══════════════════════════════════════════════════════════════
// § 2 — Invertible Counterpoint
// ═══════════════════════════════════════════════════════════════

#[test]
#[available_gas(1000000000000)]
fn test_semitone_class_basic() {
    assert(semitone_class(60, 67) == 7, 'C4-G4 = P5 = 7');
    assert(semitone_class(60, 64) == 4, 'C4-E4 = M3 = 4');
    assert(semitone_class(60, 60) == 0, 'unison = 0');
    assert(semitone_class(60, 72) == 0, 'octave = 0 mod 12');
}

#[test]
#[available_gas(1000000000000)]
fn test_semitone_class_symmetric() {
    assert(semitone_class(67, 60) == 7, 'symmetric P5');
    assert(semitone_class(64, 60) == 4, 'symmetric M3');
}

#[test]
#[available_gas(1000000000000)]
fn test_is_perfect_fifth_class() {
    assert(is_perfect_fifth_class(60, 67), 'C4-G4 is P5');
    assert(is_perfect_fifth_class(60, 79), 'C4-G5 is P12 (compound fifth)');
    assert(!is_perfect_fifth_class(60, 64), 'C4-E4 not P5');
    assert(!is_perfect_fifth_class(60, 65), 'C4-F4 not P5 (P4)');
}

#[test]
#[available_gas(1000000000000)]
fn test_ic_pair_safe() {
    assert(ic_pair_safe(60, 64), 'third is IC safe');
    assert(ic_pair_safe(60, 63), 'minor third IC safe');
    assert(!ic_pair_safe(60, 67), 'P5 not IC safe');
    assert(ic_pair_safe(255, 64), 'rest is always safe');
    assert(ic_pair_safe(60, 255), 'rest is always safe 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_is_invertible_at_octave_no_fifths() {
    let a = array![60_u8, 62, 64];
    let b = array![64_u8, 65, 67]; // G4 is a fifth above C4 at idx 2
    // Actually: 64-to-67 = 3 semitones (minor third), not a fifth. All safe.
    assert(is_invertible_at_octave(a.span(), b.span()), 'no fifths = invertible');
}

#[test]
#[available_gas(1000000000000)]
fn test_is_invertible_at_octave_has_fifth() {
    let a = array![60_u8, 62];
    let b = array![67_u8, 69]; // C-G = P5, D-A = P5
    assert(!is_invertible_at_octave(a.span(), b.span()), 'fifth = not invertible');
}

#[test]
#[available_gas(1000000000000)]
fn test_count_fifths_zero() {
    let a = array![60_u8, 64, 67];
    let b = array![64_u8, 67, 71];
    assert(count_fifths(a.span(), b.span()) == 0, 'no fifths');
}

#[test]
#[available_gas(1000000000000)]
fn test_count_fifths_two() {
    let a = array![60_u8, 62, 64];
    let b = array![67_u8, 69, 71]; // C-G, D-A, E-B: all thirds?
    // C(60)-G(67)=7 semitones = P5, D(62)-A(69)=7 = P5, E(64)-B(71)=7 = P5
    assert(count_fifths(a.span(), b.span()) == 3, 'three fifths');
}

#[test]
#[available_gas(1000000000000)]
fn test_raise_octave_basic() {
    let v = array![60_u8, 64, 67];
    let raised = raise_octave(v.span());
    assert(*raised.at(0) == 72, 'C4 -> C5');
    assert(*raised.at(1) == 76, 'E4 -> E5');
    assert(*raised.at(2) == 79, 'G4 -> G5');
}

#[test]
#[available_gas(1000000000000)]
fn test_raise_octave_passes_rest() {
    let v = array![255_u8, 64];
    let raised = raise_octave(v.span());
    assert(*raised.at(0) == 255, 'rest unchanged');
    assert(*raised.at(1) == 76, 'note raised');
}

#[test]
#[available_gas(1000000000000)]
fn test_raise_octave_saturates_at_midi_top() {
    let v = array![120_u8, 127];
    let raised = raise_octave(v.span());
    assert(*raised.at(0) == 127, '120 saturates');
    assert(*raised.at(1) == 127, '127 saturates');
}

#[test]
#[available_gas(1000000000000)]
fn test_lower_octave_basic() {
    let v = array![72_u8, 76];
    let lowered = lower_octave(v.span());
    assert(*lowered.at(0) == 60, 'C5 -> C4');
    assert(*lowered.at(1) == 64, 'E5 -> E4');
}

#[test]
#[available_gas(1000000000000)]
fn test_lower_octave_clamps_at_bottom() {
    let v = array![5_u8]; // too low to lower
    let lowered = lower_octave(v.span());
    assert(*lowered.at(0) == 5, 'clamps at bottom');
}

#[test]
#[available_gas(1000000000000)]
fn test_octave_invert_pair_raises_a() {
    let a = array![60_u8, 62];
    let b = array![64_u8, 65];
    let (new_a, new_b) = octave_invert_pair(a.span(), b.span());
    assert(*new_a.at(0) == 72, 'a raised by 12');
    assert(*new_b.at(0) == 64, 'b unchanged');
}

#[test]
#[available_gas(1000000000000)]
fn test_diatonic_class_fifth() {
    // Step of 4 diatonic degrees = class 4 = fifth
    assert(is_diatonic_fifth(4), 'diatonic step 4 is fifth');
    assert(is_diatonic_fifth(-4), 'diatonic step -4 is fifth');
    assert(!is_diatonic_fifth(2), 'diatonic step 2 is third');
}

#[test]
#[available_gas(1000000000000)]
fn test_diatonic_ic_safe() {
    assert(diatonic_ic_safe(0, 2), 'third is safe');
    assert(diatonic_ic_safe(0, 5), 'sixth is safe');
    assert(!diatonic_ic_safe(0, 4), 'fifth is not safe');
    assert(!diatonic_ic_safe(4, 0), 'fifth down is not safe');
}

#[test]
#[available_gas(1000000000000)]
fn test_lattice_ic_safe_supports_diatonic_and_chromatic() {
    assert(lattice_interval_class(7, 0, 4) == 4, 'dia fifth class');
    assert(lattice_fifth_class(7) == 4, 'dia fifth');
    assert(lattice_fifth_class(12) == 7, 'chrom fifth');
    assert(!lattice_ic_safe(7, 0, 4), 'dia P5 unsafe');
    assert(!lattice_ic_safe(12, 0, 7), 'chrom P5 unsafe');
    assert(lattice_ic_safe(7, 0, 2), 'dia third safe');
    assert(lattice_ic_safe(12, 0, 4), 'chrom third safe');
}

#[test]
#[available_gas(1000000000000)]
fn test_invertible_profile_rejects_fifth_but_keeps_thirds() {
    let profile = profile_by_id(PROFILE_RENAISSANCE_INVERTIBLE_ID);
    assert(vertical_ok_invertible(@profile, 0, 2), 'third accepted');
    assert(vertical_ok_invertible(@profile, 0, 5), 'sixth accepted');
    assert(!vertical_ok_invertible(@profile, 0, 4), 'fifth rejected');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_invertible_melodic_canon() {
    let canon = generate_invertible_melodic_canon(2026, 0, 12);
    let profile = profile_by_id(PROFILE_RENAISSANCE_INVERTIBLE_ID);
    assert(all_pairs_octave_invertible(@canon), 'generated IC');
    assert(all_pairs_convertible_counterpoint(@canon, @profile), 'generated convertible');
}

// ═══════════════════════════════════════════════════════════════
// § 3 — Stretto
// ═══════════════════════════════════════════════════════════════

#[test]
#[available_gas(1000000000000)]
fn test_stretto_plan_valid() {
    assert(stretto_plan_valid(@default_stretto_plan()), 'default plan valid');
    assert(stretto_plan_valid(@renaissance_stretto_plan()), 'ren plan valid');
    let bad = StrettoPlan { base_lag: 2, min_lag: 3 }; // base < min → invalid
    assert(!stretto_plan_valid(@bad), 'bad plan invalid');
    let zero = StrettoPlan { base_lag: 4, min_lag: 0 }; // min_lag=0 → invalid
    assert(!stretto_plan_valid(@zero), 'zero min invalid');
}

#[test]
#[available_gas(1000000000000)]
fn test_stretto_lag_bucket_0_is_base() {
    let plan = default_stretto_plan();
    assert(stretto_lag(@plan, 0) == plan.base_lag, 'bucket 0 = base');
}

#[test]
#[available_gas(1000000000000)]
fn test_stretto_lag_bucket_7_is_min() {
    let plan = default_stretto_plan();
    assert(stretto_lag(@plan, 7) == plan.min_lag, 'bucket 7 = min');
}

#[test]
#[available_gas(1000000000000)]
fn test_stretto_lag_monotone() {
    let plan = default_stretto_plan();
    let mut prev = stretto_lag(@plan, 0);
    let mut k: u8 = 1;
    loop {
        if k > 7 { break; }
        let cur = stretto_lag(@plan, k);
        assert(cur <= prev, 'lag decreases with kills');
        prev = cur;
        k += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_voice_entry_time_formula() {
    assert(voice_entry_time(0, 3) == 0, 'voice 0 always at 0');
    assert(voice_entry_time(1, 3) == 3, 'voice 1 at 3');
    assert(voice_entry_time(2, 3) == 6, 'voice 2 at 6');
    assert(voice_entry_time(3, 3) == 9, 'voice 3 at 9');
}

#[test]
#[available_gas(1000000000000)]
fn test_stretto_entry_times_length() {
    let plan = default_stretto_plan();
    let entries = stretto_entry_times(@plan, 3, 4);
    assert(entries.len() == 4, 'four voices');
}

#[test]
#[available_gas(1000000000000)]
fn test_stretto_entry_times_ordered() {
    let plan = default_stretto_plan();
    let entries = stretto_entry_times(@plan, 7, 4); // max compression
    assert(entries_ordered(entries.span()), 'entries ordered');
}

#[test]
#[available_gas(1000000000000)]
fn test_stretto_entry_times_voice0_at_0() {
    let plan = default_stretto_plan();
    let entries = stretto_entry_times(@plan, 4, 3);
    assert(*entries.at(0) == 0, 'voice 0 at beat 0');
}

#[test]
#[available_gas(1000000000000)]
fn test_kills_to_lag_extremes() {
    assert(kills_to_lag(0) == 4, 'kills=0 lag=4');
    assert(kills_to_lag(7) == 1, 'kills=7 lag=1');
}

#[test]
#[available_gas(1000000000000)]
fn test_stretto_intensity_labels() {
    assert(stretto_intensity(4) == 'exposition', 'lag 4 = exposition');
    assert(stretto_intensity(3) == 'close_stretto', 'lag 3');
    assert(stretto_intensity(2) == 'tight_stretto', 'lag 2');
    assert(stretto_intensity(1) == 'extreme_stretto', 'lag 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_entries_ordered_basic() {
    let ok = array![0_u32, 2, 4, 6];
    assert(entries_ordered(ok.span()), 'ascending ok');
    let bad = array![0_u32, 4, 2, 6];
    assert(!entries_ordered(bad.span()), 'non-ascending bad');
}

#[test]
#[available_gas(1000000000000)]
fn test_entries_ordered_single() {
    let single = array![5_u32];
    assert(entries_ordered(single.span()), 'single entry ok');
}

#[test]
#[available_gas(1000000000000)]
fn test_is_genuine_stretto_rejects_default_spacing() {
    let entries = array![0_u32, 4, 8];
    assert(!is_genuine_stretto(entries.span()), 'default spacing not stretto');
}

#[test]
#[available_gas(1000000000000)]
fn test_is_genuine_stretto_accepts_compressed_spacing() {
    let entries = array![0_u32, 2, 4];
    assert(is_genuine_stretto(entries.span()), 'compressed spacing stretto');
}

// ═══════════════════════════════════════════════════════════════
// § 4 — Countersubject
// ═══════════════════════════════════════════════════════════════

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_length_matches_subject() {
    let subject = array![0_i32, 2, 4, 3, 2, 1, 0];
    let cfg = default_countersubject_config();
    let cs = generate_countersubject(subject.span(), @cfg, 42, 7, 5, 60, 480);
    assert(cs.degrees.len() == subject.len(), 'cs length matches');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_starts_at_offset() {
    let subject = array![0_i32, 2, 4, 3, 2];
    let cfg = default_countersubject_config(); // start_offset = +2
    let cs = generate_countersubject(subject.span(), @cfg, 7, 7, 5, 60, 480);
    assert(*cs.degrees.at(0) == 2, 'cs starts at offset');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_consonant_against_subject() {
    let subject = array![0_i32, 2, 4, 5, 4, 2, 0];
    let cfg = default_countersubject_config();
    let cs = generate_countersubject(subject.span(), @cfg, 42, 7, 5, 60, 480);
    assert(countersubject_consonant(subject.span(), @cs), 'cs consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_invertible_no_fifths() {
    let subject = array![0_i32, 2, 4, 5, 4, 2, 0];
    let cfg = default_countersubject_config();
    let cs = generate_countersubject(subject.span(), @cfg, 42, 7, 5, 60, 480);
    assert(countersubject_invertible(subject.span(), @cs), 'cs no diatonic fifths');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_conjunct() {
    let subject = array![0_i32, 2, 4, 3, 2, 1, 0];
    let cfg = default_countersubject_config(); // max_step = 3
    let cs = generate_countersubject(subject.span(), @cfg, 99, 7, 5, 60, 480);
    assert(countersubject_conjunct(@cs, 3), 'cs conjunct');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_deterministic() {
    let subject = array![0_i32, 1, 2, 3, 2, 1, 0];
    let cfg = default_countersubject_config();
    let cs1 = generate_countersubject(subject.span(), @cfg, 555, 7, 5, 60, 480);
    let cs2 = generate_countersubject(subject.span(), @cfg, 555, 7, 5, 60, 480);
    let mut i: u32 = 0;
    loop {
        if i >= cs1.degrees.len() { break; }
        assert(*cs1.degrees.at(i) == *cs2.degrees.at(i), 'deterministic');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_below_config() {
    let subject = array![0_i32, 2, 4, 5, 4, 2, 0];
    let cfg = below_countersubject_config(); // start_offset = -2
    let cs = generate_countersubject(subject.span(), @cfg, 42, 7, 5, 60, 480);
    assert(*cs.degrees.at(0) == -2, 'below: starts at -2');
    assert(countersubject_consonant(subject.span(), @cs), 'below: consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_event_count() {
    let subject = array![0_i32, 2, 4, 3, 2];
    let cfg = default_countersubject_config();
    let cs = generate_countersubject(subject.span(), @cfg, 1, 7, 5, 60, 480);
    let events = countersubject_to_note_events(@cs, 0, 2);
    assert(events.len() == 5, 'event count = subject len');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_event_voice_id() {
    let subject = array![0_i32, 2, 4];
    let cfg = default_countersubject_config();
    let cs = generate_countersubject(subject.span(), @cfg, 1, 7, 5, 60, 480);
    let events = countersubject_to_note_events(@cs, 0, 7);
    let mut i: u32 = 0;
    loop {
        if i >= events.len() { break; }
        assert((*events.at(i)).voice_id == 7, 'voice id = 7');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_repairs_unsafe_start_offset() {
    let subject = array![0_i32, 2, 4];
    let cfg = CountersubjectConfig {
        start_offset: 4,
        max_step: 3,
        enforce_invertible: true,
    };
    let cs = generate_countersubject(subject.span(), @cfg, 4, 7, 5, 60, 480);
    assert(*cs.degrees.at(0) != 4, 'unsafe P5 start repaired');
    assert(countersubject_consonant(subject.span(), @cs), 'repaired consonant');
    assert(countersubject_invertible(subject.span(), @cs), 'repaired invertible');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_preserves_ic_when_step_limit_too_tight() {
    let subject = array![0_i32, 6];
    let cfg = CountersubjectConfig {
        start_offset: 2,
        max_step: 0,
        enforce_invertible: true,
    };
    let cs = generate_countersubject(subject.span(), @cfg, 5, 7, 5, 60, 480);
    assert(countersubject_consonant(subject.span(), @cs), 'tight consonant');
    assert(countersubject_invertible(subject.span(), @cs), 'tight still IC');
}

// ═══════════════════════════════════════════════════════════════
// § 5 — Compound Melody
// ═══════════════════════════════════════════════════════════════

#[test]
#[available_gas(1000000000000)]
fn test_compound_melody_interleaved_count() {
    let degrees = array![0_i32, 2, 4, 5];
    let cfg = default_compound_config(); // interleave = true
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 60, 480, 0);
    // 4 beats × 2 sub-notes = 8 events
    assert(events.len() == 8, 'interleaved: 2x per beat');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_melody_non_interleaved_count() {
    let degrees = array![0_i32, 2, 4, 5];
    let cfg = CompoundMelodyConfig {
        high_octave_shift: 12,
        split_keynum: 60,
        interleave: false,
        high_velocity: 90,
        low_velocity: 70,
    };
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 60, 480, 0);
    assert(events.len() == 4, 'non-interleaved: 1 per beat');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_melody_empty_degrees() {
    let degrees: Array<i32> = array![];
    let cfg = default_compound_config();
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 60, 480, 0);
    assert(events.len() == 0, 'empty = no events');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_melody_has_both_registers() {
    let degrees = array![0_i32, 2, 4];
    // Use tonic=48 (C3): low notes ~48, high notes ~60.
    let cfg2 = CompoundMelodyConfig {
        high_octave_shift: 12, split_keynum: 60, interleave: true,
        high_velocity: 90, low_velocity: 70,
    };
    let events2 = generate_compound_melody(degrees.span(), @cfg2, 7, 5, 48, 480, 0);
    // low notes around 48 (C3 area), high notes around 60 (C4 area)
    assert(compound_has_both_registers(events2.span(), 60), 'both registers present');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_pitches_valid() {
    let degrees = array![0_i32, 2, 4, 5];
    let cfg = default_compound_config();
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 60, 480, 0);
    assert(compound_pitches_valid(events.span()), 'pitches in range');
}

#[test]
#[available_gas(1000000000000)]
fn test_split_compound_voices_by_register() {
    let events = array![
        NoteEvent { time: 0, duration: 240, pitch: 55, velocity: 70, voice_id: 0 },
        NoteEvent { time: 240, duration: 240, pitch: 67, velocity: 90, voice_id: 0 },
        NoteEvent { time: 480, duration: 240, pitch: 53, velocity: 70, voice_id: 0 },
        NoteEvent { time: 720, duration: 240, pitch: 65, velocity: 90, voice_id: 0 },
    ];
    let (high, low) = split_compound_voices(events.span(), 60);
    assert(high.len() == 2, 'two high events');
    assert(low.len() == 2, 'two low events');
    assert((*high.at(0)).pitch == 67, 'high[0] = G4');
    assert((*low.at(0)).pitch == 55, 'low[0] = G3');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_high_voice() {
    let events = array![
        NoteEvent { time: 0, duration: 240, pitch: 48, velocity: 70, voice_id: 0 },
        NoteEvent { time: 240, duration: 240, pitch: 72, velocity: 90, voice_id: 0 },
    ];
    let high = compound_high_voice(events.span(), 60);
    assert(high.len() == 1, 'one high event');
    assert((*high.at(0)).pitch == 72, 'high pitch = 72');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_low_voice() {
    let events = array![
        NoteEvent { time: 0, duration: 240, pitch: 48, velocity: 70, voice_id: 0 },
        NoteEvent { time: 240, duration: 240, pitch: 72, velocity: 90, voice_id: 0 },
    ];
    let low = compound_low_voice(events.span(), 60);
    assert(low.len() == 1, 'one low event');
    assert((*low.at(0)).pitch == 48, 'low pitch = 48');
}

#[test]
#[available_gas(1000000000000)]
fn test_merge_voices_combines() {
    let a = array![
        NoteEvent { time: 0, duration: 480, pitch: 60, velocity: 80, voice_id: 0 },
    ];
    let b = array![
        NoteEvent { time: 0, duration: 480, pitch: 72, velocity: 80, voice_id: 1 },
        NoteEvent { time: 480, duration: 480, pitch: 74, velocity: 80, voice_id: 1 },
    ];
    let merged = merge_voices(a.span(), b.span());
    assert(merged.len() == 3, 'merged count');
    assert((*merged.at(0)).pitch == 60, 'first from a');
    assert((*merged.at(1)).pitch == 72, 'second from b');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_high_octave_shift_applied() {
    // Tonic C3 (48), degree 0 → low pitch = 48, high = 48 + 12 = 60.
    let degrees = array![0_i32];
    let cfg = default_compound_config();
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 48, 480, 0);
    // events: [low=48 at t=0, high=60 at t=240]
    assert((*events.at(0)).pitch == 48, 'low note at tonic');
    assert((*events.at(1)).pitch == 60, 'high note = tonic + 12');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_high_pitch_saturates_at_midi_top() {
    let degrees = array![0_i32];
    let cfg = CompoundMelodyConfig {
        high_octave_shift: 12,
        split_keynum: 100,
        interleave: true,
        high_velocity: 90,
        low_velocity: 70,
    };
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 120, 480, 0);
    assert((*events.at(0)).pitch == 120, 'low high tonic');
    assert((*events.at(1)).pitch == 127, 'high saturates');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_sub_duration() {
    // time_unit=480, interleave=true → sub_dur=240
    let degrees = array![0_i32, 2];
    let cfg = default_compound_config();
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 48, 480, 0);
    assert((*events.at(0)).duration == 240, 'sub dur = unit/2');
    assert((*events.at(1)).duration == 240, 'sub dur = unit/2');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_voice_id_passthrough() {
    let degrees = array![0_i32, 2];
    let cfg = default_compound_config();
    let events = generate_compound_melody(degrees.span(), @cfg, 7, 5, 60, 480, 5);
    let mut i: u32 = 0;
    loop {
        if i >= events.len() { break; }
        assert((*events.at(i)).voice_id == 5, 'voice_id = 5');
        i += 1;
    };
}

// ═══════════════════════════════════════════════════════════════
// § 6 — IC Walk, InvertibleVerticalPolicy, Time-Aware Followers
// ═══════════════════════════════════════════════════════════════

// ── follower_degree_retrograde ────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_follower_degree_retrograde_basic() {
    let degs = array![10_i32, 20, 30, 40];
    // pos=0 → degs[3]=40; pos=1 → degs[2]=30; pos=3 → degs[0]=10
    assert(follower_degree_retrograde(degs.span(), 0) == 40, 'retro pos 0');
    assert(follower_degree_retrograde(degs.span(), 1) == 30, 'retro pos 1');
    assert(follower_degree_retrograde(degs.span(), 3) == 10, 'retro pos 3');
}

#[test]
#[available_gas(1000000000000)]
fn test_follower_degree_retrograde_single() {
    let degs = array![7_i32];
    assert(follower_degree_retrograde(degs.span(), 0) == 7, 'single = itself');
}

// ── realize_retrograde_follower ───────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_retrograde_follower_event_count() {
    let degs = array![0_i32, 2, 4, 5];
    let events = realize_retrograde_follower(degs.span(), 0, 0, 7, 5, 60, 480, 3);
    assert(events.len() == 4, 'retro: same count as leader');
}

#[test]
#[available_gas(1000000000000)]
fn test_retrograde_follower_first_is_last_leader() {
    // Follower starts by playing the last leader degree reversed.
    let degs = array![0_i32, 2, 4];
    let events = realize_retrograde_follower(degs.span(), 0, 0, 7, 5, 60, 480, 1);
    // pos=0 → degs[2]=4, pos=2 → degs[0]=0
    let first_pitch = (*events.at(0)).pitch;
    let last_pitch = (*events.at(2)).pitch;
    // degs[2]=4 (5th above final in diatonic), degs[0]=0 (final)
    // just verify they differ (first = high, last = low for ascending leader)
    assert(first_pitch != last_pitch, 'retro first != last');
}

#[test]
#[available_gas(1000000000000)]
fn test_retrograde_follower_timing() {
    let degs = array![0_i32, 2, 4];
    let events = realize_retrograde_follower(degs.span(), 0, 960, 7, 5, 60, 480, 1);
    // entry_time=960, each note is 480 long
    assert((*events.at(0)).time == 960, 'retro t0 = entry');
    assert((*events.at(1)).time == 1440, 'retro t1 = entry+480');
    assert((*events.at(0)).duration == 480, 'retro dur = time_unit');
}

// ── realize_augmented_follower ────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_augmented_follower_event_count() {
    let degs = array![0_i32, 2, 4];
    let events = realize_augmented_follower(degs.span(), 0, 2, 0, 7, 5, 60, 480, 2);
    assert(events.len() == 3, 'aug: same count as leader');
}

#[test]
#[available_gas(1000000000000)]
fn test_augmented_follower_duration_doubled() {
    let degs = array![0_i32, 2];
    // factor=2 → each note lasts 2 * 480 = 960
    let events = realize_augmented_follower(degs.span(), 0, 2, 0, 7, 5, 60, 480, 2);
    assert((*events.at(0)).duration == 960, 'aug dur = 2*480');
    assert((*events.at(1)).time == 960, 'aug second note at 960');
}

#[test]
#[available_gas(1000000000000)]
fn test_augmented_follower_entry_time_respected() {
    let degs = array![0_i32, 2];
    let events = realize_augmented_follower(degs.span(), 0, 3, 1440, 7, 5, 60, 480, 2);
    // entry_time=1440, factor=3, aug_unit=1440; first note at 1440, second at 1440+1440=2880
    assert((*events.at(0)).time == 1440, 'aug entry respected');
    assert((*events.at(1)).time == 2880, 'aug second note offset');
}

// ── realize_diminuted_follower ────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_diminuted_follower_event_count() {
    let degs = array![0_i32, 2, 4];
    let events = realize_diminuted_follower(degs.span(), 0, 2, 0, 7, 5, 60, 480, 3);
    assert(events.len() == 3, 'dim: same count as leader');
}

#[test]
#[available_gas(1000000000000)]
fn test_diminuted_follower_duration_halved() {
    let degs = array![0_i32, 2];
    // factor=2 → each note lasts 480/2 = 240
    let events = realize_diminuted_follower(degs.span(), 0, 2, 0, 7, 5, 60, 480, 3);
    assert((*events.at(0)).duration == 240, 'dim dur = 480/2');
    assert((*events.at(1)).time == 240, 'dim second note at 240');
}

#[test]
#[available_gas(1000000000000)]
fn test_diminuted_follower_entry_time_respected() {
    let degs = array![0_i32, 2, 4];
    let events = realize_diminuted_follower(degs.span(), 0, 2, 480, 7, 5, 60, 480, 3);
    // entry_time=480, dim_unit=240; notes at 480, 720, 960
    assert((*events.at(0)).time == 480, 'dim entry respected');
    assert((*events.at(2)).time == 960, 'dim third note at 960');
}

// ── retrograde_follower_clash_free ────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_retrograde_clash_free_palindrome() {
    // A palindromic sequence is trivially clash-free at lag=0 (each deg pairs with itself).
    let degs = array![0_i32, 2, 0];
    // At lag=1: leader[1]=2 vs retro[0]=degs[2]=0; vertical = 2-0 = 2 (third, consonant).
    //           leader[2]=0 vs retro[1]=degs[1]=2; vertical = 0-2 = -2, class=2 (consonant).
    assert(retrograde_follower_clash_free(degs.span(), 0, 1), 'palindrome lag=1 safe');
}

#[test]
#[available_gas(1000000000000)]
fn test_retrograde_clash_free_no_overlap() {
    // lag >= len → no overlap → always safe
    let degs = array![0_i32, 3, 1];
    assert(retrograde_follower_clash_free(degs.span(), 0, 3), 'no overlap = safe');
    assert(retrograde_follower_clash_free(degs.span(), 0, 10), 'far lag = safe');
}

// ── augmented_follower_clash_free ─────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_augmented_clash_free_unison_transposition() {
    // Follower is augmented unison (same degrees, factor=2, entry_beat=0).
    // At leader beat 0: follower plays degs[0]+0 = 0, vertical = 0 (unison, consonant).
    // At leader beat 1: follower plays degs[0]+0 = 0 (still on first note), vertical = 2-0=2 (third).
    // At leader beat 2: follower plays degs[1]+0 = 2, vertical = 4-2=2 (third).
    let degs = array![0_i32, 2, 4];
    assert(augmented_follower_clash_free(degs.span(), 0, 2, 0), 'aug unison safe');
}

#[test]
#[available_gas(1000000000000)]
fn test_augmented_clash_free_entry_after_start() {
    // Follower (factor=1) enters at beat 2. Overlap beats 2,3,4 check:
    //   beat 2: leader[2]=2 vs follower[0]=degs[0]=0 → vertical=2 (third) ✓
    //   beat 3: leader[3]=2 vs follower[1]=degs[1]=2 → vertical=0 (unison) ✓
    //   beat 4: leader[4]=0 vs follower[2]=degs[2]=2 → vertical=-2, class=2 (third) ✓
    let degs = array![0_i32, 2, 2, 2, 0];
    assert(augmented_follower_clash_free(degs.span(), 0, 1, 2), 'delayed entry safe');
}

// ── apply_follower_spec_events ────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_apply_spec_transposition_matches_direct() {
    let degs = array![0_i32, 2, 4];
    // Spec: Transposition(2), entry at 480
    let spec_events = apply_follower_spec_events(degs.span(), FollowerSpec::Transposition(2), 480, 7, 5, 60, 480, 1);
    // All events should be at time 480, 960, 1440 with duration 480
    assert(spec_events.len() == 3, 'transpo: 3 events');
    assert((*spec_events.at(0)).time == 480, 'transpo t0');
    assert((*spec_events.at(0)).duration == 480, 'transpo dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_apply_spec_retrograde_reversal() {
    let degs = array![0_i32, 2, 5];
    let retro_events = apply_follower_spec_events(degs.span(), FollowerSpec::Retrograde, 0, 7, 5, 60, 480, 2);
    let direct_events = realize_retrograde_follower(degs.span(), 0, 0, 7, 5, 60, 480, 2);
    // Pitches should match
    assert((*retro_events.at(0)).pitch == (*direct_events.at(0)).pitch, 'retro spec matches direct');
    assert((*retro_events.at(2)).pitch == (*direct_events.at(2)).pitch, 'retro spec last matches');
}

#[test]
#[available_gas(1000000000000)]
fn test_apply_spec_augmentation_duration() {
    let degs = array![0_i32, 2];
    let aug_events = apply_follower_spec_events(degs.span(), FollowerSpec::Augmentation(3), 0, 7, 5, 60, 480, 2);
    // factor=3 → duration = 3*480 = 1440
    assert((*aug_events.at(0)).duration == 1440, 'aug spec dur = 1440');
    assert((*aug_events.at(1)).time == 1440, 'aug spec t1 = 1440');
}

#[test]
#[available_gas(1000000000000)]
fn test_apply_spec_diminution_duration() {
    let degs = array![0_i32, 2, 4];
    let dim_events = apply_follower_spec_events(degs.span(), FollowerSpec::Diminution(2), 0, 7, 5, 60, 480, 2);
    // factor=2 → duration = 480/2 = 240
    assert((*dim_events.at(0)).duration == 240, 'dim spec dur = 240');
    assert((*dim_events.at(1)).time == 240, 'dim spec t1 = 240');
}

// ── InvertibleVerticalPolicy ──────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_vertical_ok_with_policy_renaissance_ic_rejects_fifth() {
    let policy = renaissance_ic_policy(); // profile 25 + require_ic_safe=true
    // Third (2) is consonant and IC-safe
    assert(vertical_ok_with_policy(@policy, 0, 2), 'third accepted');
    // Sixth (5) is consonant and IC-safe
    assert(vertical_ok_with_policy(@policy, 0, 5), 'sixth accepted');
    // Diatonic fifth (4) is IC-unsafe → rejected regardless of style
    assert(!vertical_ok_with_policy(@policy, 0, 4), 'fifth rejected');
}

#[test]
#[available_gas(1000000000000)]
fn test_vertical_ok_with_policy_no_ic_passes_fifth() {
    // Profile 0 (Renaissance) is consonance-aware but does NOT bake in IC.
    // With require_ic_safe=false, a diatonic fifth should pass the policy.
    let policy = ic_policy_from_id(0, false);
    assert(vertical_ok_with_policy(@policy, 0, 2), 'third: no-ic pass');
    assert(vertical_ok_with_policy(@policy, 0, 4), 'fifth: no-ic passes');
}

#[test]
#[available_gas(1000000000000)]
fn test_vertical_ok_with_policy_ic_flag_rejects_fifth_any_profile() {
    // Even with a non-IC profile, require_ic_safe=true should reject diatonic fifths.
    let policy = ic_policy_from_id(0, true);
    assert(vertical_ok_with_policy(@policy, 0, 2), 'third ok with ic flag');
    assert(!vertical_ok_with_policy(@policy, 0, 4), 'fifth rejected by ic flag');
}

// ── walk_leader_banded_ic ─────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_banded_ic_length_and_start() {
    let profile = profile_renaissance();
    let offsets = array![0_i32, 2_i32];
    let env = constant_band(@profile);
    let (degs, steps) = walk_leader_banded_ic(
        0, 1, offsets.span(), @profile, 10, false, env, turnaround_plan_default(),
    );
    assert(degs.len() == 10, 'ic walk: len 10');
    assert(steps.len() == 9, 'ic walk: 9 steps');
    assert(*degs.at(0) == 0, 'ic walk: starts at 0');
}

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_banded_ic_no_diatonic_fifths() {
    // For offsets [0, 2] with lag=1: constraint {w:1, d:2}.
    // IC check: at each step m, abs(m − 2) % 7 must not equal 4.
    // Steps violating this: m=6 (6−2=4) or m=−2 (|−2−2|=4). These should be absent.
    let profile = profile_renaissance();
    let offsets = array![0_i32, 2_i32];
    let env = constant_band(@profile);
    let (_, steps) = walk_leader_banded_ic(
        0, 1, offsets.span(), @profile, 12, false, env, turnaround_plan_default(),
    );
    let mut i: u32 = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        let m = *steps.at(i);
        let diff = m - 2_i32;
        let abs_diff: u32 = if diff < 0 {
            (-diff).try_into().unwrap()
        } else {
            diff.try_into().unwrap()
        };
        assert(abs_diff % 7 != 4, 'no diatonic fifth step');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_banded_ic_deterministic() {
    let profile = profile_renaissance();
    let offsets = array![0_i32, 2_i32];
    let env = constant_band(@profile);
    let (d1, _) = walk_leader_banded_ic(
        42, 7, offsets.span(), @profile, 8, false, env, turnaround_plan_default(),
    );
    let (d2, _) = walk_leader_banded_ic(
        42, 7, offsets.span(), @profile, 8, false, env, turnaround_plan_default(),
    );
    let mut i: u32 = 0;
    loop {
        if i >= 8 {
            break;
        }
        assert(*d1.at(i) == *d2.at(i), 'ic walk deterministic');
        i += 1;
    };
}

// ── canon_with_countersubject ─────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_canon_with_countersubject_event_count() {
    let leader = array![0_i32, 2, 4, 5, 4, 2, 0];
    let cfg = default_countersubject_config();
    let events = canon_with_countersubject(
        leader.span(), @cfg, 42, 0, 7, 5, 60, 480, 0, 1,
    );
    // leader emits 7 events, CS emits 7 events → 14 total
    assert(events.len() == 14, 'leader + cs = 2*len');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_with_countersubject_voice_ids() {
    let leader = array![0_i32, 2, 4, 5];
    let cfg = default_countersubject_config();
    let events = canon_with_countersubject(
        leader.span(), @cfg, 1, 0, 7, 5, 60, 480, 0, 1,
    );
    let mut has_leader = false;
    let mut has_cs = false;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        if (*events.at(i)).voice_id == 0 {
            has_leader = true;
        }
        if (*events.at(i)).voice_id == 1 {
            has_cs = true;
        }
        i += 1;
    };
    assert(has_leader, 'has leader events');
    assert(has_cs, 'has cs events');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_with_countersubject_ic_property() {
    // CS generated with enforce_invertible=true should have no diatonic fifths.
    let leader = array![0_i32, 2, 4, 5, 4, 2, 0];
    let cfg = default_countersubject_config(); // enforce_invertible=true
    let cs = generate_countersubject(leader.span(), @cfg, 99, 7, 5, 60, 480);
    assert(countersubject_invertible(leader.span(), @cs), 'cs is IC-safe');
    assert(countersubject_consonant(leader.span(), @cs), 'cs is consonant');
}

//! Tests for entry-lag canon rules and generation.

use koji::composition::canon_rules::{
    config_fifth_above, generic_class, is_consonant_class,
};
use koji::composition::canon_entry_rules::{
    entries_stacked, entries_uniform_lag, entries_stacked_lag, validate_entries,
    pair_constraints_from_entries, pair_constraints_match_stacked, config_fifth_above_lag2,
    config_three_voice_5b_8va_lag2, ENTRY_LAG_CONFIG_ID_BASE,
};
use koji::composition::entry_lag_canon::{
    walk_leader_with_entries, generate_entry_lag_canon, generate_entry_lag_canon_uniform,
    generate_entry_lag_canon_from_seed, entry_lag_canon_traits, entries_fingerprint,
};
use koji::composition::melodic_canon::{
    generate_melodic_canon_with_params, all_pairs_consonant, exact_imitation,
    build_mensuration_voices,
};
use koji::composition::aesthetic_profile::profile_renaissance;
use koji::composition::jazz_harmony::turnaround_plan_default;

#[test]
#[available_gas(1000000000000)]
fn test_validate_entries_stacked() {
    let offsets = array![0_i32, 4].span();
    let entries = entries_stacked(2).span();
    assert(validate_entries(offsets, entries), 'stacked valid');
}

#[test]
#[available_gas(1000000000000)]
fn test_validate_entries_rejects_bad_leader() {
    let offsets = array![0_i32, 4].span();
    let entries = array![1_u32, 2].span();
    assert(!validate_entries(offsets, entries), 'leader must be 0');
}

#[test]
#[available_gas(1000000000000)]
fn test_pair_constraints_match_stacked_two_voice() {
    assert(pair_constraints_match_stacked(array![0_i32, 4].span()), '2v stacked');
}

#[test]
#[available_gas(1000000000000)]
fn test_pair_constraints_match_stacked_three_voice() {
    assert(
        pair_constraints_match_stacked(array![0_i32, -4, 3].span()), '3v stacked match',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_pair_constraints_lag2_window() {
    let offsets = array![0_i32, 4].span();
    let entries = entries_uniform_lag(2, 2).span();
    let pcs = pair_constraints_from_entries(offsets, entries);
    assert(pcs.len() == 1, 'one pair');
    assert((*pcs.at(0)).d == 4, 'fifth above');
    assert((*pcs.at(0)).w == 2, 'window 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_entries_uniform_lag_two_voice() {
    let e = entries_uniform_lag(2, 2);
    assert(*e.at(0) == 0, 'leader 0');
    assert(*e.at(1) == 2, 'follower lag 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_entries_stacked_lag_three_voice() {
    let e = entries_stacked_lag(3, 2);
    assert(*e.at(0) == 0, 'v0');
    assert(*e.at(1) == 2, 'v1');
    assert(*e.at(2) == 4, 'v2');
}

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_with_entries_lag2() {
    let cfg = config_fifth_above_lag2();
    let profile = profile_renaissance();
    let plan = turnaround_plan_default();
    let (degs, steps) = walk_leader_with_entries(
        0, 42, cfg.offsets, cfg.entries, @profile, 16, false, plan,
    );
    assert(degs.len() == 16, 'len');
    assert(steps.len() == 15, 'steps');
}

#[test]
#[available_gas(1000000000000)]
fn test_lag2_step_constrained_by_two_note_span() {
    let cfg = config_fifth_above_lag2();
    let profile = profile_renaissance();
    let plan = turnaround_plan_default();
    let (_degs, steps) = walk_leader_with_entries(
        0, 99, cfg.offsets, cfg.entries, @profile, 20, false, plan,
    );
    let mut i: u32 = 1;
    loop {
        if i >= steps.len() {
            break;
        }
        let m = *steps.at(i);
        let prev = *steps.at(i - 1);
        let span = m + prev;
        assert(
            is_consonant_class(generic_class(4, span)), '2-note span consonant',
        );
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_entry_lag_canon_lag2_consonant() {
    let mut seed: felt252 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= 32 {
            break;
        }
        let canon = generate_entry_lag_canon(seed * 17, config_fifth_above_lag2(), 16);
        assert(all_pairs_consonant(@canon), 'consonant');
        assert(exact_imitation(@canon), 'imitation');
        assert((*canon.voices.at(1)).entry == 2, 'entry 2');
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_uniform_lag1_matches_legacy_voices() {
    let base = config_fifth_above();
    let canon = generate_entry_lag_canon_uniform(12345, base, 1, 16);
    let legacy = generate_melodic_canon_with_params(12345, 0, 16);
    assert((*canon.voices.at(0)).entry == (*legacy.voices.at(0)).entry, 'v0 entry');
    assert((*canon.voices.at(1)).entry == (*legacy.voices.at(1)).entry, 'v1 entry');
    assert(all_pairs_consonant(@canon), 'lag1 consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_entry_lag_config_id_space() {
    let cfg = config_fifth_above_lag2();
    assert(cfg.config_id >= ENTRY_LAG_CONFIG_ID_BASE, 'id base');
}

#[test]
#[available_gas(1000000000000)]
fn test_entry_lag_traits() {
    let canon = generate_entry_lag_canon_from_seed(777);
    let traits = entry_lag_canon_traits(@canon);
    assert(traits.primary_entry_lag == 2, 'lag 2');
    assert(traits.base.config_id >= ENTRY_LAG_CONFIG_ID_BASE, 'config id');
}

#[test]
#[available_gas(1000000000000)]
fn test_entries_fingerprint_differs_by_lag() {
    let a = entries_fingerprint(entries_stacked(2).span());
    let b = entries_fingerprint(entries_uniform_lag(2, 2).span());
    assert(a != b, 'fingerprints differ');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_three_voice_lag2_ornamented() {
    let cfg = config_three_voice_5b_8va_lag2();
    let canon = generate_entry_lag_canon(4343, cfg, 36);
    assert(all_pairs_consonant(@canon), '3v lag2 consonant');
    assert((*canon.voices.at(0)).entry == 0, 'v0');
    assert((*canon.voices.at(1)).entry == 2, 'v1 lag2');
    assert((*canon.voices.at(2)).entry == 4, 'v2 lag4');
}

#[test]
#[available_gas(1000000000000)]
fn test_mensuration_voices_custom_entry() {
    let offsets = array![0_i32, 4].span();
    let entries = entries_uniform_lag(2, 2).span();
    let dilations = array![1_u32, 1].span();
    let voices = build_mensuration_voices(offsets, entries, dilations);
    assert((*voices.at(1)).entry == 2, 'custom entry');
}

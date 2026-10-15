//! Invertible counterpoint, stretto and the countersubject: interval classes and the invertibility
//! checks, the stretto lag per kill bucket, and countersubjects that stay consonant, conjunct and
//! invertible against the subject.

use crate::composition::canon_rules::{abs_i32, generic_class, is_consonant_class};
use crate::composition::countersubject::{
    Countersubject, CountersubjectConfig, countersubject_invertible, countersubject_to_note_events,
    default_countersubject_config, generate_countersubject,
};
use crate::composition::invertible_counterpoint::{
    diatonic_ic_safe, ic_pair_safe, is_diatonic_fifth, is_perfect_fifth_class, semitone_class,
};
use crate::composition::stretto::{default_stretto_plan, stretto_lag};

/// True iff every CS degree is consonant against the corresponding subject degree.
fn countersubject_consonant(subject: Span<i32>, cs: @Countersubject) -> bool {
    assert(subject.len() == cs.degrees.len(), 'subject/cs len mismatch');
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= subject.len() || !ok {
            break;
        }
        let cls = generic_class(*cs.degrees.at(i), *subject.at(i));
        if !is_consonant_class(cls) {
            ok = false;
        }
        i += 1;
    }
    ok
}

/// True iff every CS melodic step stays within `max_step` diatonic degrees.
fn countersubject_conjunct(cs: @Countersubject, max_step: u32) -> bool {
    let degs = @cs.degrees;
    if degs.len() < 2 {
        return true;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i + 1 >= degs.len() || !ok {
            break;
        }
        let step = abs_i32(*degs.at(i + 1) - *degs.at(i));
        if step > max_step {
            ok = false;
        }
        i += 1;
    }
    ok
}

/// Countersubject that starts a third below — fits under the subject.
fn below_countersubject_config() -> CountersubjectConfig {
    CountersubjectConfig { start_offset: -2, max_step: 3, enforce_invertible: true }
}

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
        if k > 7 {
            break;
        }
        let cur = stretto_lag(@plan, k);
        assert(cur <= prev, 'lag decreases with kills');
        prev = cur;
        k += 1;
    };
}

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
        if i >= cs1.degrees.len() {
            break;
        }
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
        if i >= events.len() {
            break;
        }
        assert((*events.at(i)).voice_id == 7, 'voice id = 7');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_repairs_unsafe_start_offset() {
    let subject = array![0_i32, 2, 4];
    let cfg = CountersubjectConfig { start_offset: 4, max_step: 3, enforce_invertible: true };
    let cs = generate_countersubject(subject.span(), @cfg, 4, 7, 5, 60, 480);
    assert(*cs.degrees.at(0) != 4, 'unsafe P5 start repaired');
    assert(countersubject_consonant(subject.span(), @cs), 'repaired consonant');
    assert(countersubject_invertible(subject.span(), @cs), 'repaired invertible');
}

#[test]
#[available_gas(1000000000000)]
fn test_countersubject_preserves_ic_when_step_limit_too_tight() {
    let subject = array![0_i32, 6];
    let cfg = CountersubjectConfig { start_offset: 2, max_step: 0, enforce_invertible: true };
    let cs = generate_countersubject(subject.span(), @cfg, 5, 7, 5, 60, 480);
    assert(countersubject_consonant(subject.span(), @cs), 'tight consonant');
    assert(countersubject_invertible(subject.span(), @cs), 'tight still IC');
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

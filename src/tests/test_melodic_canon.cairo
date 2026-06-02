//! Tests for the melodic-canon generator: realization, the leader walk, validators, end-to-end
//! determinism, ornamentation, and the lag-difference identity under fuzzing.

use koji::composition::canon_rules::{config_fifth_above, allowed_leader_steps, contains_i32};
use koji::composition::melodic_canon::{
    mode_scale, degree_to_keynum, walk_leader, all_pairs_consonant, exact_imitation,
    canon_to_note_events, generate_melodic_canon, canon_traits, subdivide, ornament_tone_is_legal,
    build_canon_for_test, cadence_formula, cadence_lands_on_final,
};
use koji::composition::canon_rules::step_set_eq;

// ──────────────────────────────────────────────────────────
// Realization
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_degree_to_keynum_ionian() {
    let scale = mode_scale(0); // Ionian
    assert(degree_to_keynum(0, 60, scale) == 60, 'deg 0 == tonic');
    assert(degree_to_keynum(7, 60, scale) == 72, 'deg +7 == octave up');
    assert(degree_to_keynum(-7, 60, scale) == 48, 'deg -7 == octave down');
    assert(degree_to_keynum(2, 60, scale) == 64, 'deg +2 == major 3rd');
    assert(degree_to_keynum(4, 60, scale) == 67, 'deg +4 == 5th');
}

#[test]
#[available_gas(1000000000000)]
fn test_degree_to_keynum_negative_below_tonic() {
    let scale = mode_scale(0);
    // degree -1 from C = B below = 59
    assert(degree_to_keynum(-1, 60, scale) == 59, 'deg -1 == 7th below');
}

// ──────────────────────────────────────────────────────────
// Leader walk
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_starts_on_final() {
    let cfg = config_fifth_above();
    let (degs, steps) = walk_leader(7, @cfg, 12, false);
    assert(*degs.at(0) == 0, 'starts on final');
    assert(degs.len() == 12, 'right length');
    assert(steps.len() == 11, 'steps = len-1');
}

#[test]
#[available_gas(1000000000000)]
fn test_walk_leader_steps_in_alphabet_fifth_above() {
    // Every chosen leader step must be in the fifth-above permitted alphabet.
    let cfg = config_fifth_above();
    let (_degs, steps) = walk_leader(42, @cfg, 16, false);
    let alphabet = allowed_leader_steps(4);
    let mut i: u32 = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        assert(contains_i32(alphabet.span(), *steps.at(i)), 'step in alphabet');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Validators on hand-built canons
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_all_pairs_consonant_fifth_above() {
    // leader degrees using only fifth-above alphabet steps: 0, +2, +4, -1, ...
    let degs = array![0_i32, 2, 4, 3, 0, 2];
    let canon = build_canon_for_test(0, 'fifth_above', array![0_i32, 4].span(), degs.span(), 0);
    assert(all_pairs_consonant(@canon), 'fifth-above frame consonant');
    assert(exact_imitation(@canon), 'imitation holds');
}

#[test]
#[available_gas(1000000000000)]
fn test_all_pairs_consonant_detects_dissonance() {
    // +1 (up a step) is NOT in the fifth-above alphabet → produces a dissonant 4th.
    let degs = array![0_i32, 1, 2, 3];
    let canon = build_canon_for_test(0, 'bad', array![0_i32, 4].span(), degs.span(), 0);
    assert(!all_pairs_consonant(@canon), 'detects the dissonance');
}

// ──────────────────────────────────────────────────────────
// Lag-difference identity, fuzzed over many seeds
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_generated_canon_always_consonant_fifth_above() {
    let mut seed: felt252 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= 24 {
            break;
        }
        // Force the fifth-above config (config index 0) by keeping low nibble 0.
        let canon = generate_melodic_canon(seed * 16);
        assert(all_pairs_consonant(@canon), 'generated canon consonant');
        assert(exact_imitation(@canon), 'generated imitation holds');
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_generated_canon_three_voice_consonant() {
    // config index 4 (three-voice 5b+8va): low nibble == 4.
    let mut base: felt252 = 4;
    let mut i: u32 = 0;
    loop {
        if i >= 16 {
            break;
        }
        let seed = base + (i.into()) * 16; // keep low nibble 4
        let canon = generate_melodic_canon(seed);
        assert((canon.voices).len() == 3, 'three voices');
        assert(all_pairs_consonant(@canon), '3-voice consonant');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// End-to-end determinism & variety
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_determinism() {
    let a = generate_melodic_canon(123456);
    let b = generate_melodic_canon(123456);
    assert(a.leader_degrees.len() == b.leader_degrees.len(), 'same length');
    let mut i: u32 = 0;
    loop {
        if i >= a.leader_degrees.len() {
            break;
        }
        assert(*a.leader_degrees.at(i) == *b.leader_degrees.at(i), 'identical degrees');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_different_seeds_differ() {
    // Both keep config nibble 0 (fifth above) but differ in the leader-walk state bits (19+),
    // so the generated leader lines must differ. 0x80000 = 2^19.
    let a = generate_melodic_canon(0x80000);
    let b = generate_melodic_canon(0x180000);
    let mut differ = a.leader_degrees.len() != b.leader_degrees.len();
    if !differ {
        let mut i: u32 = 0;
        loop {
            if i >= a.leader_degrees.len() {
                break;
            }
            if *a.leader_degrees.at(i) != *b.leader_degrees.at(i) {
                differ = true;
                break;
            }
            i += 1;
        };
    }
    assert(differ, 'different seeds differ');
}

// ──────────────────────────────────────────────────────────
// Note events
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_note_events_structure() {
    let canon = generate_melodic_canon(98765);
    let events = canon_to_note_events(@canon);
    let nvoices = (canon.voices).len();
    let len = canon.leader_degrees.len();
    assert(events.len() == nvoices * len, 'one event per voice-note');
    // all pitches in a sane MIDI register
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        assert(e.pitch >= 24 && e.pitch <= 108, 'pitch in register');
        assert(e.duration > 0, 'positive duration');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_traits() {
    let canon = generate_melodic_canon(555 * 16); // config 0 fifth above
    let tr = canon_traits(@canon);
    assert(tr.voice_count == 2, '2 voices');
    assert(tr.interval_of_imitation == 4, 'imitation = +4');
    assert(tr.melodic_alphabet_size == 8, 'fifth-above alphabet = 8');
}

// ──────────────────────────────────────────────────────────
// Ornamentation
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_subdivide_passing_tones() {
    // "subdivide that note into four" filling a leap of a third (0 → 2)
    let got = subdivide(0, 2, 4);
    // first note is structural; then steps up toward 2 and holds
    assert(*got.at(0) == 0, 'first == structural');
    assert(got.len() == 4, 'four notes');
    assert(*got.at(3) == 2, 'reaches target');
}

#[test]
#[available_gas(1000000000000)]
fn test_subdivide_single() {
    let got = subdivide(3, 5, 1);
    assert(got.len() == 1, 'single note');
    assert(*got.at(0) == 3, 'is structural');
}

// ──────────────────────────────────────────────────────────
// Cadence
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_cadence_formula_fifth_above() {
    // "down a step, then up a fourth; follower goes down a step, then down another."
    let cf = cadence_formula(0);
    assert(step_set_eq(cf.leader_tail, array![-1_i32, 3].span()), 'leader: down step, up 4th');
    assert(step_set_eq(cf.comes_tail, array![-1_i32, -1].span()), 'comes: down step x2');
}

#[test]
#[available_gas(1000000000000)]
fn test_cadence_formula_fifth_below() {
    // "up a step, then up a third mid-measure, prepare the suspension."
    let cf = cadence_formula(1);
    assert(step_set_eq(cf.leader_tail, array![1_i32, 2].span()), 'leader: up step, up 3rd');
    assert(cf.suspension, 'suspension prepared');
}

#[test]
#[available_gas(1000000000000)]
fn test_generated_two_voice_ends_on_final() {
    // The steered cadence lands the leader on the modal final (degree 0) and a perfect close.
    let canon = generate_melodic_canon(0x80000); // config 0, fifth above
    let degs = canon.leader_degrees;
    assert(*degs.at(degs.len() - 1) == 0, 'leader ends on final');
    assert(cadence_lands_on_final(@canon), 'cadence resolves');
}

#[test]
#[available_gas(1000000000000)]
fn test_generated_fifth_below_ends_on_final() {
    // config index 1 (fifth below): low nibble 1.
    let canon = generate_melodic_canon(0x80000 + 1);
    let degs = canon.leader_degrees;
    assert(*degs.at(degs.len() - 1) == 0, 'fifth-below ends on final');
    assert(all_pairs_consonant(@canon), 'still consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_ornament_legality() {
    // a consonant added tone is always fine
    assert(ornament_tone_is_legal(2, 0, false, false), 'consonance ok');
    // a dissonant tone (a 2nd) is fine only on a weak beat approached by step
    assert(ornament_tone_is_legal(1, 0, true, true), 'weak passing ok');
    assert(!ornament_tone_is_legal(1, 0, false, true), 'strong dissonance bad');
    assert(!ornament_tone_is_legal(1, 0, true, false), 'leapt dissonance bad');
}

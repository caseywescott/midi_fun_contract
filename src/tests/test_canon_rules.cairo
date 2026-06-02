//! Tests for the Renaissance canon rules engine — the lag-difference identity, Table 1, and the
//! conversation-derived acceptance tests (Schubert / Cumming / Collins).

use koji::composition::canon_rules::{
    abs_i32, generic_class, is_consonant_class, is_perfect_class, step_is_consonant,
    allowed_leader_steps, stylistic_subset, negate_steps, intersect_steps, step_set_eq,
    contains_i32, allowed_steps_multivoice, stylistic_multivoice, pair_constraints,
    step_satisfies_constraints, config_three_voice_5b_8va,
};

// ──────────────────────────────────────────────────────────
// Consonance classes
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_consonant_classes() {
    assert(is_consonant_class(0), 'unison consonant');
    assert(is_consonant_class(2), '3rd consonant');
    assert(is_consonant_class(4), '5th consonant');
    assert(is_consonant_class(5), '6th consonant');
    assert(!is_consonant_class(1), '2nd dissonant');
    assert(!is_consonant_class(3), '4th dissonant');
    assert(!is_consonant_class(6), '7th dissonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_perfect_classes() {
    assert(is_perfect_class(0), 'unison/oct perfect');
    assert(is_perfect_class(4), '5th perfect');
    assert(!is_perfect_class(2), '3rd imperfect');
    assert(!is_perfect_class(5), '6th imperfect');
}

#[test]
#[available_gas(1000000000000)]
fn test_compound_reduction() {
    // 11th = 10 diatonic steps → 4th → dissonant; 12th = 11 → 5th → consonant.
    assert(generic_class(0, 10) == 3, '11th reduces to 4th');
    assert(!is_consonant_class(generic_class(0, 10)), '11th dissonant');
    assert(generic_class(0, 11) == 4, '12th reduces to 5th');
    assert(is_consonant_class(generic_class(0, 11)), '12th consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_abs_i32() {
    assert(abs_i32(-4) == 4, 'abs -4');
    assert(abs_i32(7) == 7, 'abs 7');
    assert(abs_i32(0) == 0, 'abs 0');
}

// ──────────────────────────────────────────────────────────
// Table 1 — fifth above (Schubert / Collins)
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_fifth_above_stylistic_subset() {
    // Schubert: stay / up 3rd / up 5th / down 2nd / down 4th.
    let got = stylistic_subset(4);
    let want = array![0_i32, 2, 4, -1, -3];
    assert(step_set_eq(got.span(), want.span()), 'fifth above == Schubert set');
}

#[test]
#[available_gas(1000000000000)]
fn test_fifth_above_full_alphabet() {
    // Collins: unison, ↑3rd ↑5th ↑7th, ↓2nd ↓4th ↓6th ↓8ve.
    let got = allowed_leader_steps(4);
    let want = array![-7_i32, -5, -3, -1, 0, 2, 4, 6];
    assert(step_set_eq(got.span(), want.span()), 'fifth above full alphabet');
}

#[test]
#[available_gas(1000000000000)]
fn test_fifth_above_forbids_up_second_and_down_third() {
    assert(!step_is_consonant(4, 1), 'up 2nd forbidden 5th-above');
    assert(!step_is_consonant(4, -2), 'down 3rd forbidden 5th-above');
    assert(step_is_consonant(4, 2), 'up 3rd ok');
    assert(step_is_consonant(4, -1), 'down 2nd ok');
}

// ──────────────────────────────────────────────────────────
// Table 1 — fifth below (Cumming) and inversion symmetry
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_fifth_below_stylistic_subset() {
    // Cumming: "thirds and fifths down, seconds and fourths up, and unisons."
    let got = stylistic_subset(-4);
    let want = array![0_i32, -2, -4, 1, 3];
    assert(step_set_eq(got.span(), want.span()), 'fifth below == Cumming set');
}

#[test]
#[available_gas(1000000000000)]
fn test_inversion_symmetry_all_intervals() {
    // allowed(−T) == negate(allowed(+T)) for every interval of imitation.
    let mut t: i32 = 0;
    loop {
        if t > 7 {
            break;
        }
        let pos = allowed_leader_steps(t);
        let neg = allowed_leader_steps(-t);
        let neg_of_pos = negate_steps(pos.span());
        assert(step_set_eq(neg.span(), neg_of_pos.span()), 'inversion symmetry');
        t += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Octave forbids "up a step"
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_octave_forbids_up_a_step() {
    // |7 − 1| % 7 = 6 → a seventh.
    assert(!step_is_consonant(7, 1), 'octave forbids up-a-step');
}

// ──────────────────────────────────────────────────────────
// Three-voice canon (the conversation's derivation)
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_three_voice_5b_8va_rule() {
    // leader, fifth below, octave above that → "down a 3rd or 5th, up a 4th, or same note".
    let cfg = config_three_voice_5b_8va();
    let got = stylistic_multivoice(cfg.offsets);
    let want = array![0_i32, 3, -2, -4];
    assert(step_set_eq(got.span(), want.span()), 'three-voice == conversation');
}

#[test]
#[available_gas(1000000000000)]
fn test_three_voice_removes_up_a_step() {
    // The octave relationship (V2→V3) removes the "+1" the fifth-below alphabet would allow.
    let cfg = config_three_voice_5b_8va();
    let alpha = allowed_steps_multivoice(cfg.offsets);
    assert(!contains_i32(alpha.span(), 1), 'up-a-step removed');
    assert(contains_i32(alpha.span(), -2), 'down 3rd kept');
    assert(contains_i32(alpha.span(), 3), 'up 4th kept');
}

// ──────────────────────────────────────────────────────────
// Set operations
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_intersect_steps() {
    let a = array![0_i32, 1, 2, 3];
    let b = array![2_i32, 3, 4, 5];
    let got = intersect_steps(a.span(), b.span());
    let want = array![2_i32, 3];
    assert(step_set_eq(got.span(), want.span()), 'intersection');
}

// ──────────────────────────────────────────────────────────
// Window constraints
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_pair_constraints_three_voice() {
    let cfg = config_three_voice_5b_8va(); // offsets [0,-4,3]
    let pcs = pair_constraints(cfg.offsets);
    // pairs: (0,1) d=-4 w=1 ; (0,2) d=3 w=2 ; (1,2) d=7 w=1
    assert(pcs.len() == 3, '3 pairs');
}

#[test]
#[available_gas(1000000000000)]
fn test_window_constraint_blocks_two_fourths() {
    // For the (0,2) pair, d=3, w=2: two consecutive +3 steps sum to 6 → |3−6|=3 → 4th, dissonant.
    let cfg = config_three_voice_5b_8va();
    let pcs = pair_constraints(cfg.offsets);
    let prev = array![3_i32]; // one +3 already committed
    assert(!step_satisfies_constraints(pcs.span(), prev.span(), 3), 'two +3 blocked by w=2');
}

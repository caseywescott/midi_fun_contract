use core::array::ArrayTrait;
use koji::composition::barry_harris::{
    barry_phrase_to_harmonic_timeline, barry_phrase_to_note_events, barry_traits_from_phrase,
    contains_pc, dominant_7_dim_scale, generate_barry_phrase, initial_harmonic_state,
    major_6_dim_scale, minor_6_dim_scale, normalize_pc, pc_add, pc_sub, phrase_state_tonic_at,
    scales_equal, stable_chord_tones, state_hash, BARRY_HARRIS_V1_PLAN_ID,
};
use koji::composition::barry_profiles::{
    barry_lcg_from_seed, pick_rule, rule_histogram_skew_diminished, BarryRuleProfile,
};
use koji::composition::barry_rules::{
    allowed_rules_for_beat, apply_rule, beat_role, melody_constraints_for_state,
};
use koji::composition::barry_harris::{
    BarryRule, BeatRole, ChordFamily,
};
use koji::lcg::LCG;

fn expect_major_c_scale() -> Array<u8> {
    array![0_u8, 2, 4, 5, 7, 8, 9, 11]
}

fn expect_minor_c_scale() -> Array<u8> {
    array![0_u8, 2, 3, 5, 7, 8, 9, 11]
}

fn expect_dom_c_scale() -> Array<u8> {
    array![0_u8, 1, 3, 4, 6, 7, 9, 10]
}

#[test]
fn test_pc_add() {
    assert(pc_add(0, 4) == 4, 'C to E');
    assert(pc_sub(0, 1) == 11, 'C down B');
    assert(normalize_pc(13) == 1, 'normalize');
}

#[test]
fn test_major_6_dim_scale_c() {
    let s = major_6_dim_scale(0);
    assert(scales_equal(s.span(), expect_major_c_scale().span()), 'major C');
}

#[test]
fn test_minor_6_dim_scale_c() {
    let s = minor_6_dim_scale(0);
    assert(scales_equal(s.span(), expect_minor_c_scale().span()), 'minor C');
}

#[test]
fn test_dominant_7_dim_scale_c() {
    let s = dominant_7_dim_scale(0);
    assert(scales_equal(s.span(), expect_dom_c_scale().span()), 'dom C');
}

#[test]
fn test_major_6_dim_scale_g() {
    let c = major_6_dim_scale(0);
    let g = major_6_dim_scale(7);
    let mut i: usize = 0;
    loop {
        if i >= c.len() {
            break;
        }
        let expected = pc_add(*c.at(i), 7);
        assert(*g.at(i) == expected, 'G transposition');
        i += 1;
    };
}

#[test]
fn test_initial_major6_state() {
    let st = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let stable = stable_chord_tones(@st);
    assert(contains_pc(stable.span(), 0), 'has C');
    assert(contains_pc(stable.span(), 4), 'has E');
    assert(contains_pc(stable.span(), 7), 'has G');
    assert(contains_pc(stable.span(), 9), 'has A');
}

#[test]
fn test_strong_beat_melody_constraints() {
    let st = initial_harmonic_state(0, ChordFamily::Major6Dim);
    assert(beat_role(0) == BeatRole::Strong, 'beat 0 strong');
    let mc = melody_constraints_for_state(@st);
    let stable = stable_chord_tones(@st);
    let mut i: usize = 0;
    loop {
        if i >= stable.len() {
            break;
        }
        assert(contains_pc(mc.span(), *stable.at(i)), 'stable on strong');
        i += 1;
    };
}

#[test]
fn test_pick_rule_deterministic() {
    let rng = LCG { state: 42, multiplier: 5, increment: 3, modulus: 256 };
    let allowed = array![
        BarryRule::Stay,
        BarryRule::ScaleStepUp,
        BarryRule::DiminishedInterpolation,
    ]
        .span();
    let (r1, _) = pick_rule(rng, BarryRuleProfile::Conservative, allowed);
    let (r2, _) = pick_rule(rng, BarryRuleProfile::Conservative, allowed);
    assert(r1 == r2, 'same rule');
    assert(rule_histogram_skew_diminished(BarryRuleProfile::DiminishedHeavy), 'dim profile');
}

#[test]
fn test_tension_forces_resolve() {
    let allowed = allowed_rules_for_beat(BeatRole::Weak, 10, 8);
    assert(allowed.len() == 1, 'only resolve');
    assert(*allowed.at(0) == BarryRule::ResolveToStable, 'resolve rule');
}

#[test]
fn test_diminished_interpolation_cycle() {
    let st = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let dim = apply_rule(st, BarryRule::DiminishedInterpolation);
    assert(contains_pc(dim.active_pcs.span(), 2), 'D dim connector');
    assert(contains_pc(dim.active_pcs.span(), 5), 'F dim connector');
}

#[test]
fn test_generate_barry_phrase_deterministic() {
    let a = generate_barry_phrase(12345, 0, ChordFamily::Major6Dim, 16, BarryRuleProfile::BebopLine, 48, 72);
    let b = generate_barry_phrase(12345, 0, ChordFamily::Major6Dim, 16, BarryRuleProfile::BebopLine, 48, 72);
    assert(a.states.len() == b.states.len(), 'same len');
    let mut i: usize = 0;
    loop {
        if i >= a.states.len() {
            break;
        }
        assert(
            phrase_state_tonic_at(@a, i) == phrase_state_tonic_at(@b, i), 'same tonic walk',
        );
        i += 1;
    };
}

#[test]
fn test_different_seeds_differ() {
    let a = generate_barry_phrase(111, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::BebopLine, 48, 72);
    let b = generate_barry_phrase(222, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::BebopLine, 48, 72);
    let mut differs = false;
    let mut i: usize = 1;
    loop {
        if i >= a.states.len() {
            break;
        }
        if state_hash(a.states.at(i)) != state_hash(b.states.at(i)) {
            differs = true;
            break;
        }
        i += 1;
    };
    assert(differs, 'seeds differ');
}

#[test]
fn test_voicing_register_bounds() {
    let phrase = generate_barry_phrase(
        999, 0, ChordFamily::Major6Dim, 12, BarryRuleProfile::Conservative, 48, 72,
    );
    let mut i: usize = 0;
    loop {
        if i >= phrase.voicings.len() {
            break;
        }
        let v = phrase.voicings.at(i);
        let mut j: usize = 0;
        loop {
            if j >= v.notes.len() {
                break;
            }
            let kn = *v.notes.at(j);
            assert(kn >= 48, 'lo bound');
            assert(kn <= 72, 'hi bound');
            j += 1;
        };
        i += 1;
    };
}

#[test]
fn test_barry_timeline_and_events() {
    let phrase = generate_barry_phrase(
        4242, 0, ChordFamily::Major6Dim, 4, BarryRuleProfile::MediaLoop, 48, 72,
    );
    let tl = barry_phrase_to_harmonic_timeline(@phrase);
    assert(tl.targets.len() == phrase.states.len(), 'timeline len');
    let events = barry_phrase_to_note_events(@phrase, 4);
    assert(events.len() > 0, 'note events');
    let traits = barry_traits_from_phrase(@phrase, BarryRuleProfile::MediaLoop);
    assert(traits.tonic_pc == 0, 'traits tonic');
}

#[test]
fn test_barry_lcg_domain_separated() {
    let lcg = barry_lcg_from_seed(12345);
    assert(lcg.state > 0, 'lcg init');
    assert(BARRY_HARRIS_V1_PLAN_ID != 0, 'plan id');
}

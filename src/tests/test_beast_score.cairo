use koji::composition::beast_score::{
    BEAST_SCORE_VERSION, build_beast_form, build_beast_form_from_traits, build_beast_theme,
    derive_beast_sound_seeds, first_two_voices_invertible, note_events_valid, walk_leader_hashed,
};
use koji::composition::beast_trait_map::{
    VISUAL_ANIMATED, VISUAL_COMMON, BeastCompositionParams, BeastLiveStats,
    map_beast_traits_to_composition_params,
};

fn baseline_stats() -> BeastLiveStats {
    BeastLiveStats {
        level: 1,
        health: 10,
        adventurers_defeated: 0,
        times_defeated: 0,
        encounter_count: 0,
        species_rank: 1243,
        is_crown: false,
    }
}

fn high_history_stats() -> BeastLiveStats {
    BeastLiveStats {
        level: 128,
        health: 999,
        adventurers_defeated: 64,
        times_defeated: 8,
        encounter_count: 32,
        species_rank: 1,
        is_crown: true,
    }
}

fn params_for(species_id: u8, name_variant_id: u32, visual: u8, stats: BeastLiveStats) -> BeastCompositionParams {
    map_beast_traits_to_composition_params(species_id, name_variant_id, visual, 4242, stats)
}

#[test]
fn beast_subseeds_are_stable_and_distinct() {
    let a = derive_beast_sound_seeds(99);
    let b = derive_beast_sound_seeds(99);
    assert(a.motif_seed == b.motif_seed, 'motif stable');
    assert(a.canon_seed == b.canon_seed, 'canon stable');
    assert(a.motif_seed != a.canon_seed, 'motif != canon');
    assert(a.ornament_seed != a.orchestration_seed, 'orn != orch');
}

#[test]
fn hashed_walk_is_deterministic_and_bounded() {
    let (d1, s1) = walk_leader_hashed(123, 16, 7);
    let (d2, s2) = walk_leader_hashed(123, 16, 7);
    assert(d1.len() == 16, 'degree len');
    assert(s1.len() == 15, 'step len');
    let mut i: u32 = 0;
    loop {
        if i >= d1.len() {
            break;
        }
        assert(*d1.at(i) == *d2.at(i), 'deterministic degrees');
        assert(*d1.at(i) >= -7 && *d1.at(i) <= 7, 'degree bound');
        i += 1;
    };
    let mut j: u32 = 0;
    loop {
        if j >= s1.len() {
            break;
        }
        assert(*s1.at(j) == *s2.at(j), 'deterministic steps');
        assert(*s1.at(j) >= -2 && *s1.at(j) <= 2, 'step bound');
        j += 1;
    };
}

#[test]
fn theme_hash_is_independent_of_live_state_when_identity_is_same() {
    let calm = params_for(12, 20, VISUAL_COMMON, baseline_stats());
    let evolved = params_for(12, 20, VISUAL_COMMON, high_history_stats());
    let seeds = derive_beast_sound_seeds(777);
    let calm_theme = build_beast_theme(calm, seeds.motif_seed);
    let evolved_theme = build_beast_theme(evolved, seeds.motif_seed);
    assert(calm_theme.theme_hash == evolved_theme.theme_hash, 'theme stable');
}

#[test]
fn single_section_common_beast_emits_valid_events() {
    let params = params_for(74, 0, VISUAL_COMMON, baseline_stats());
    let form = build_beast_form(params, 4444);
    assert(form.section_count == 1, 'single section');
    assert(form.events.len() >= 12, 'notes emitted');
    assert(note_events_valid(form.events.span()), 'events valid');
}

#[test]
fn high_history_beast_emits_multi_section_form() {
    let params = params_for(0, 1242, VISUAL_ANIMATED, high_history_stats());
    let form = build_beast_form(params, 4444);
    assert(form.section_count == 5, 'five sections');
    assert(form.events.len() > 100, 'dense form');
    assert(note_events_valid(form.events.span()), 'events valid');
    assert(form.score_hash != 0, 'score hash');
}

#[test]
fn live_history_changes_score_hash() {
    let calm = params_for(0, 1242, VISUAL_ANIMATED, baseline_stats());
    let evolved = params_for(0, 1242, VISUAL_ANIMATED, high_history_stats());
    let calm_form = build_beast_form(calm, 8080);
    let evolved_form = build_beast_form(evolved, 8080);
    assert(calm_form.score_hash != evolved_form.score_hash, 'score evolves');
}

#[test]
fn score_builder_from_traits_is_valid() {
    let form = build_beast_form_from_traits(30, 19, VISUAL_COMMON, 1212, high_history_stats());
    assert(note_events_valid(form.events.span()), 'trait form valid');
    assert(form.section_count >= 3, 'trait section count');
}

#[test]
fn tier_one_crown_uses_invertible_front_pair_when_possible() {
    let params = params_for(0, 1242, VISUAL_ANIMATED, high_history_stats());
    let form = build_beast_form(params, 9090);
    assert(note_events_valid(form.events.span()), 'crown valid');
    // This can fail musically for some seeds if later render policies change; keep it as a
    // canary for the current countersubject/inversion routing.
    assert(first_two_voices_invertible(form.events.span()), 'front pair invertible');
}

#[test]
fn params_version_matches_score_version() {
    let params = params_for(74, 0, VISUAL_COMMON, baseline_stats());
    assert(params.score_version == BEAST_SCORE_VERSION, 'version');
}

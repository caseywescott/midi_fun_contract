//! Tests for the aesthetic-profile abstraction: the parameterized vertical predicate, each
//! profile's by-construction guarantees (maj7 / quartal / planing canons clash-free), the
//! parsimonious seventh-chord progression, and backward compatibility with the Renaissance engine.

use koji::composition::aesthetic_profile::{
    profile_renaissance, profile_jazz, profile_quartal, profile_by_id, vertical_class,
    unfolded_distance_class, vertical_ok, vertical_tier, allowed_leader_steps_p, is_avoid_note,
    CLASH, COLOR, SOFT, num_profiles, PAR_FORBID, PAR_LIMIT, PAR_ALLOW,
};
use koji::composition::canon_rules::{
    is_consonant_class, contains_i32, num_profiled_configs, abs_i32,
};
use koji::composition::melodic_canon::{
    generate_maj7_canon, generate_min7_canon, generate_quartal_canon, generate_planing_canon,
    generate_dom9_planing_canon, generate_lydian_maj9_canon, generate_dominant_altered_canon,
    generate_whole_tone_planing_canon, generate_octatonic_axis_canon, generate_sus_quartal_canon,
    generate_pandiatonic_canon, generate_spectral_canon, generate_bartok_axis_canon,
    generate_cluster_soft_canon, generate_canon_per_tonos, generate_profiled_canon,
    generate_impressionist_added6_canon, generate_bitonal_split_canon,
    generate_phrygian_cadential_canon, generate_pentatonic_open_canon,
    generate_neo_riemannian_canon,
    generate_impressionist_added6_smooth_canon, generate_pentatonic_open_smooth_canon,
    generate_jazz_improv_canon,
    generate_pentatonic_smooth_ornamented_canon,
    plan_ornament_subdivisions_for_profile, plan_ornament_subdivisions_dense,
    subdivide_for_profile, canon_to_ornamented_note_events_with_fill,
    generate_melodic_canon, no_minor_ninth, all_pairs_clash_free, exact_imitation,
    canon_to_note_events, canon_traits, NoteEvent, MelodicCanon,
};
use koji::composition::parsimonious_progression::{
    generate_parsimonious_progression, voice_leading_smooth, no_minor_ninth_in_chords,
};
use koji::composition::melodic_motion::ORN_FILL_MATERIAL;

// ──────────────────────────────────────────────────────────
// The crux: m2 (clash) vs M7 (color) on the chromatic lattice
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_chromatic_class_distinguishes_m2_from_M7() {
    let jazz = profile_jazz();
    assert(vertical_class(@jazz, 0, 1) == 1, 'm2 is class 1');
    assert(unfolded_distance_class(@jazz, 0, 1) == 1, 'unfolded m2 class');
    assert(vertical_class(@jazz, 0, 11) == 11, 'M7 is class 11');
    // minor 9th folds onto class 1 (still a clash); major 9th onto class 2 (a usable color)
    assert(vertical_class(@jazz, 0, 13) == 1, 'm9 folds to 1');
    assert(vertical_class(@jazz, 0, 14) == 2, 'M9 folds to 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_allows_maj7_forbids_m2() {
    let jazz = profile_jazz();
    assert(vertical_tier(@jazz, 0, 1) == CLASH, 'm2 is a clash');
    assert(vertical_tier(@jazz, 0, 11) == COLOR, 'M7 is color');
    assert(!vertical_ok(@jazz, 0, 1), 'm2 not ok');
    assert(vertical_ok(@jazz, 0, 11), 'M7 ok');
    assert(!vertical_ok(@jazz, 0, 13), 'm9 not ok');
    assert(vertical_ok(@jazz, 0, 7), 'P5 ok');
}

// ──────────────────────────────────────────────────────────
// Backward compatibility: Renaissance profile == is_consonant_class
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_renaissance_profile_matches_legacy() {
    let ren = profile_renaissance();
    let mut c: i32 = 0;
    loop {
        if c > 6 {
            break;
        }
        let cu: u32 = c.try_into().unwrap();
        assert(vertical_ok(@ren, 0, c) == is_consonant_class(cu), 'matches legacy consonance');
        c += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_num_profiles() {
    assert(num_profiles() == 25, 'twenty-five profiles');
    assert(num_profiled_configs() == 43, 'forty-three configs');
    assert(profile_by_id(0).id == 0, 'renaissance id');
    assert(profile_by_id(1).name == 'jazz', 'jazz name');
    assert(profile_by_id(2).name == 'quartal', 'quartal name');
    assert(profile_by_id(5).name == 'ligeti_white', 'ligeti white name');
    assert(profile_by_id(6).name == 'ligeti_micro', 'ligeti micro name');
    assert(profile_by_id(7).name == 'lydian_maj9', 'lydian name');
    assert(profile_by_id(16).name == 'per_tonos', 'per tonos name');
    assert(profile_by_id(21).name == 'neo_riem', 'neo-riemannian name');
    assert(profile_by_id(24).name == 'jazz_improv', 'jazz improv name');
}

#[test]
#[available_gas(1000000000000)]
fn test_parallel_policies_are_distinct() {
    assert(profile_by_id(0).par_policy == PAR_FORBID, 'renaissance forbids');
    assert(profile_by_id(1).par_policy == PAR_LIMIT, 'jazz limits');
    assert(profile_by_id(3).par_policy == PAR_ALLOW, 'planing allows');
}

// ──────────────────────────────────────────────────────────
// Alphabet derivation under a profile
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_jazz_alphabet_excludes_clash_steps() {
    // For imitation at a major third (T=4), a step m that makes (4 - m) a m2/m9 must be excluded.
    let jazz = profile_jazz();
    let alpha = allowed_leader_steps_p(@jazz, 4);
    // m = 5 → vertical |4-5|=1 → m2 → excluded; m = -7 → |4-(-7)|=11 → M7 → allowed
    assert(!contains_i32(alpha.span(), 5), 'm2-producing step excluded');
    assert(contains_i32(alpha.span(), -7), 'M7-producing step allowed');
    assert(contains_i32(alpha.span(), 0), 'unison step allowed');
}

#[test]
#[available_gas(1000000000000)]
fn test_quartal_perfect_fourth_stable() {
    let q = profile_quartal();
    assert(vertical_ok(@q, 0, 5), 'P4 ok in quartal');
    assert(vertical_ok(@q, 0, 7), 'P5 ok in quartal');
    assert(!vertical_ok(@q, 0, 1), 'm2 clash in quartal');
}

// ──────────────────────────────────────────────────────────
// Major-seventh canon: the headline guarantee
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_maj7_canon_clash_free() {
    let jazz = profile_jazz();
    let mut seed: felt252 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= 16 {
            break;
        }
        let canon = generate_maj7_canon(seed * 7 + 3);
        assert(canon.voices.len() == 4, 'four voices');
        assert(canon.octave == 12, 'chromatic lattice');
        assert(no_minor_ninth(@canon), 'no m2/m9 clash');
        assert(all_pairs_clash_free(@canon, @jazz), 'clash-free under jazz');
        assert(exact_imitation(@canon), 'is a canon');
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(2000000000000)]
fn test_maj7_canon_renders_in_register() {
    let canon = generate_maj7_canon(20255);
    let events = canon_to_note_events(@canon);
    assert(events.len() > 0, 'produced events');
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        assert(e.pitch >= 24 && e.pitch <= 108, 'pitch in register');
        i += 1;
    };
}

#[test]
#[available_gas(2000000000000)]
fn test_maj7_canon_deterministic() {
    let a = generate_maj7_canon(424242);
    let b = generate_maj7_canon(424242);
    assert(a.leader_degrees.len() == b.leader_degrees.len(), 'same length');
    let mut i: u32 = 0;
    loop {
        if i >= a.leader_degrees.len() {
            break;
        }
        assert(*a.leader_degrees.at(i) == *b.leader_degrees.at(i), 'identical');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Other chromatic profiles
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_min7_canon_clash_free() {
    let jazz = profile_jazz();
    let canon = generate_min7_canon(777);
    assert(canon.voices.len() == 4, 'four voices');
    assert(no_minor_ninth(@canon), 'no clash');
    assert(all_pairs_clash_free(@canon, @jazz), 'clash-free');
}

#[test]
#[available_gas(2000000000000)]
fn test_quartal_canon_clash_free() {
    let q = profile_quartal();
    let canon = generate_quartal_canon(909);
    assert(canon.voices.len() == 3, 'three voices');
    assert(no_minor_ninth(@canon), 'no clash');
    assert(all_pairs_clash_free(@canon, @q), 'clash-free quartal');
}

#[test]
#[available_gas(2000000000000)]
fn test_planing_canon_clash_free() {
    let planing = profile_by_id(3);
    let canon = generate_planing_canon(1234);
    assert(canon.voices.len() == 4, 'four voices');
    assert(no_minor_ninth(@canon), 'no clash within block');
    assert(all_pairs_clash_free(@canon, @planing), 'clash-free planing');
}

// ──────────────────────────────────────────────────────────
// Expanded profile catalogue
// ──────────────────────────────────────────────────────────

fn pitch_pc(pitch: u8) -> u8 {
    pitch % 12
}

fn pc_in(set: Span<u8>, pc: u8) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    loop {
        if i >= set.len() {
            break;
        }
        if *set.at(i) == pc {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

fn degree_pc(degree: i32) -> u8 {
    let d: i32 = degree + 120;
    let du: u32 = d.try_into().unwrap();
    (du % 12).try_into().unwrap()
}

fn events_cover_pcs(events: Span<NoteEvent>, required: Span<u8>) -> bool {
    let mut r: u32 = 0;
    let mut ok = true;
    loop {
        if r >= required.len() {
            break;
        }
        let need = *required.at(r);
        let mut found = false;
        let mut i: u32 = 0;
        loop {
            if i >= events.len() {
                break;
            }
            if pitch_pc(*events.at(i).pitch) == need {
                found = true;
                break;
            }
            i += 1;
        };
        if !found {
            ok = false;
            break;
        }
        r += 1;
    };
    ok
}

fn leader_degrees_in_pc_set(canon: @MelodicCanon, pcs: Span<u8>) -> bool {
    let degs = *canon.leader_degrees;
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= degs.len() {
            break;
        }
        if !pc_in(pcs, degree_pc(*degs.at(i))) {
            ok = false;
            break;
        }
        i += 1;
    };
    ok
}

fn events_in_pc_set(events: Span<NoteEvent>, pcs: Span<u8>) -> bool {
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= events.len() {
            break;
        }
        if !pc_in(pcs, pitch_pc(*events.at(i).pitch)) {
            ok = false;
            break;
        }
        i += 1;
    };
    ok
}

#[test]
#[available_gas(2000000000000)]
fn test_expanded_profiles_have_expected_tables() {
    let lyd = profile_by_id(7);
    let dom = profile_by_id(8);
    let wt = profile_by_id(9);
    let spectral = profile_by_id(13);
    let cluster = profile_by_id(15);
    let impr = profile_by_id(17);
    let bito = profile_by_id(18);
    let phry = profile_by_id(19);
    let penta = profile_by_id(20);
    let neo = profile_by_id(21);
    assert(vertical_tier(@lyd, 0, 6) == SOFT, 'lydian tritone color');
    assert(vertical_ok(@dom, 0, 13), 'dominant b9 admitted');
    assert(!vertical_ok(@wt, 0, 1), 'whole tone rejects odd class');
    assert(!vertical_ok(@spectral, 0, 6), 'spectral gates tritone');
    assert(vertical_ok(@cluster, 0, 1), 'soft cluster admits m2');
    assert(!vertical_ok(@impr, 0, 1), 'impressionist gates m2');
    assert(vertical_ok(@bito, 0, 1), 'bitonal admits cross m2');
    assert(vertical_ok(@phry, 0, 1), 'phrygian admits b2 color');
    assert(!vertical_ok(@penta, 0, 1), 'pentatonic gates m2');
    assert(!vertical_ok(@penta, 0, 11), 'pentatonic gates maj7');
    assert(!vertical_ok(@neo, 0, 1), 'neo-riem gates m2');
    assert(vertical_ok(@neo, 0, 4), 'neo-riem allows M3');
    let impr_s = profile_by_id(23);
    let penta_s = profile_by_id(22);
    assert(!vertical_ok(@impr_s, 0, 1), 'smooth impr gates m2');
    assert(!vertical_ok(@penta_s, 0, 1), 'smooth penta gates m2');
}

fn max_leader_degree_run(canon: @MelodicCanon) -> u32 {
    let degs = *canon.leader_degrees;
    if degs.len() == 0 {
        return 0;
    }
    let mut max_run: u32 = 1;
    let mut run: u32 = 1;
    let mut prev = *degs.at(0);
    let mut i: u32 = 1;
    loop {
        if i >= degs.len() {
            break;
        }
        let d = *degs.at(i);
        if d == prev {
            run += 1;
        } else {
            if run > max_run {
                max_run = run;
            }
            run = 1;
            prev = d;
        }
        i += 1;
    };
    if run > max_run {
        max_run = run;
    }
    max_run
}

#[test]
#[available_gas(8000000000000)]
fn test_profiled_canons_no_long_static_degree_runs() {
    // Early chromatic stacked profiles (1–7 family via configs 7–17)
    assert(max_leader_degree_run(@generate_maj7_canon(88014)) < 8, 'maj7');
    assert(max_leader_degree_run(@generate_min7_canon(88016)) < 8, 'min7');
    assert(max_leader_degree_run(@generate_quartal_canon(88017)) < 8, 'quartal');
    assert(max_leader_degree_run(@generate_planing_canon(88018)) < 8, 'planing');
    assert(max_leader_degree_run(@generate_lydian_maj9_canon(88015)) < 8, 'lydian');
    assert(max_leader_degree_run(@generate_dominant_altered_canon(88019)) < 8, 'dom alt');
    // Complementary + neo-Riemannian (17–21) and jazz improv (24)
    assert(max_leader_degree_run(@generate_impressionist_added6_canon(88010)) < 8, 'impr add6');
    assert(max_leader_degree_run(@generate_bitonal_split_canon(88011)) < 8, 'bitonal');
    assert(max_leader_degree_run(@generate_phrygian_cadential_canon(88012)) < 8, 'phrygian');
    assert(max_leader_degree_run(@generate_pentatonic_open_canon(88013)) < 8, 'penta');
    assert(max_leader_degree_run(@generate_neo_riemannian_canon(310631)) < 8, 'neo riem');
    assert(max_leader_degree_run(@generate_jazz_improv_canon(770707)) < 8, 'jazz improv');
}

#[test]
#[available_gas(3000000000000)]
fn test_complementary_profiles_no_semitone_structural_steps() {
    let impr = generate_impressionist_added6_canon(88010);
    let penta = generate_pentatonic_open_canon(88011);
    let mut i: u32 = 0;
    loop {
        if i >= impr.leader_steps.len() {
            break;
        }
        assert(abs_i32(*impr.leader_steps.at(i)) != 1, 'impr no m2 step');
        i += 1;
    };
    i = 0;
    loop {
        if i >= penta.leader_steps.len() {
            break;
        }
        assert(abs_i32(*penta.leader_steps.at(i)) != 1, 'penta no m2 step');
        i += 1;
    };
    let fill = subdivide_for_profile(0, 7, 4, 17);
    let mut j: u32 = 0;
    loop {
        if j + 1 >= fill.len() {
            break;
        }
        assert(abs_i32(*fill.at(j + 1) - *fill.at(j)) != 1, 'impr fill no m2');
        j += 1;
    };
}

#[test]
#[available_gas(3000000000000)]
fn test_smooth_profiles_no_semitone_melodic_steps() {
    let penta = generate_pentatonic_open_smooth_canon(88001);
    let impr = generate_impressionist_added6_smooth_canon(88002);
    let mut i: u32 = 0;
    loop {
        if i >= penta.leader_steps.len() {
            break;
        }
        let s = *penta.leader_steps.at(i);
        assert(abs_i32(s) != 1, 'penta smooth no m2 step');
        i += 1;
    };
    i = 0;
    loop {
        if i >= impr.leader_steps.len() {
            break;
        }
        let s = *impr.leader_steps.at(i);
        assert(abs_i32(s) != 1, 'impr smooth no m2 step');
        i += 1;
    };
    let subs = plan_ornament_subdivisions_for_profile(22, 1, penta.leader_steps, 4);
    let mut j: u32 = 0;
    loop {
        if j >= subs.len() {
            break;
        }
        assert(*subs.at(j) == 1, 'penta plain ornaments');
        j += 1;
    };
}

#[test]
#[available_gas(3000000000000)]
fn test_pentatonic_smooth_ornamented_has_rhythm_and_motion() {
    let (canon, subs) = generate_pentatonic_smooth_ornamented_canon(482639, 39, 48);
    assert(max_leader_degree_run(@canon) < 8, 'penta orn static');
    let mut has_subdiv: bool = false;
    let mut i: u32 = 0;
    loop {
        if i >= subs.len() {
            break;
        }
        if *subs.at(i) > 1 {
            has_subdiv = true;
        }
        i += 1;
    };
    assert(has_subdiv, 'penta orn dense subs');
    let events = canon_to_ornamented_note_events_with_fill(@canon, subs.span(), ORN_FILL_MATERIAL);
    assert(events.len() > canon.leader_degrees.len() * canon.voices.len(), 'penta orn events');
}

#[test]
#[available_gas(4000000000000)]
fn test_expanded_catalogue_smoke_generates() {
    let ids = array![
        16_u32, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 37, 38, 39, 40,
    ];
    let mut i: u32 = 0;
    loop {
        if i >= ids.len() {
            break;
        }
        let id = *ids.at(i);
        let canon = generate_profiled_canon(1000 + id.into(), id);
        let profile = profile_by_id(canon.profile_id);
        assert(exact_imitation(@canon), 'catalogue canon');
        assert(all_pairs_clash_free(@canon, @profile), 'catalogue clash-free');
        i += 1;
    };
}

#[test]
#[available_gas(3000000000000)]
fn test_material_filters_are_audible() {
    let wt = generate_whole_tone_planing_canon(20260602);
    let wte = canon_to_note_events(@wt);
    assert(events_in_pc_set(wte.span(), array![0_u8, 2, 4, 6, 8, 10].span()), 'whole tone pcs');

    let oct = generate_octatonic_axis_canon(20260603);
    let octe = canon_to_note_events(@oct);
    assert(
        events_in_pc_set(octe.span(), array![0_u8, 1, 3, 4, 6, 7, 9, 10].span()),
        'octatonic pcs',
    );
}

#[test]
#[available_gas(3000000000000)]
fn test_complementary_material_filters_are_audible() {
    let add6 = generate_impressionist_added6_canon(20260617);
    assert(
        leader_degrees_in_pc_set(@add6, array![0_u8, 2, 3, 4, 7, 9, 11].span()),
        'impressionist leader pcs',
    );
    let add6e = canon_to_note_events(@add6);
    assert(events_cover_pcs(add6e.span(), array![9_u8, 2].span()), 'impressionist has 6 and 9');

    let bito = generate_bitonal_split_canon(20260618);
    assert(
        leader_degrees_in_pc_set(@bito, array![0_u8, 1, 4, 6, 7, 10].span()),
        'bitonal leader pcs',
    );

    let phry = generate_phrygian_cadential_canon(20260619);
    assert(
        leader_degrees_in_pc_set(@phry, array![0_u8, 1, 3, 5, 7, 8, 10].span()),
        'phrygian leader pcs',
    );

    let penta = generate_pentatonic_open_canon(20260620);
    assert(
        leader_degrees_in_pc_set(@penta, array![0_u8, 2, 4, 7, 9].span()),
        'pentatonic leader pcs',
    );

    let neo = generate_neo_riemannian_canon(20260621);
    assert(
        leader_degrees_in_pc_set(
            @neo, array![0_u8, 4, 5, 7, 9, 11].span(),
        ),
        'neo-riemannian leader pcs',
    );
}

#[test]
#[available_gas(3000000000000)]
fn test_neo_riemannian_leader_has_motion() {
    let neo = generate_neo_riemannian_canon(310631);
    let steps = neo.leader_steps;
    let mut nonzero: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= steps.len() {
            break;
        }
        if *steps.at(i) != 0 {
            nonzero += 1;
        }
        i += 1;
    };
    assert(nonzero >= 2, 'neo leader should move');
    let degs = neo.leader_degrees;
    let mut pcs_seen: u32 = 0;
    let mut p: u32 = 0;
    loop {
        if p >= degs.len() {
            break;
        }
        let d = *degs.at(p);
        let pc: u8 = ((d + 120) % 12).try_into().unwrap();
        if pc == 0 || pc == 4 || pc == 5 || pc == 7 || pc == 9 || pc == 11 {
            pcs_seen += 1;
        }
        p += 1;
    };
    assert(pcs_seen >= degs.len(), 'neo degrees on triad pcs');
}

#[test]
#[available_gas(3000000000000)]
fn test_new_convenience_generators_and_traits() {
    let lyd = generate_lydian_maj9_canon(4242);
    let tr = canon_traits(@lyd);
    assert(tr.config_id == 17, 'lydian config');
    assert(tr.profile_id == 7, 'lydian profile');
    assert(tr.profile_name == 'lydian_maj9', 'profile name');
    assert(tr.octave == 12, 'chromatic trait');
    assert(tr.chord_quality == 'lydian_maj9', 'quality trait');
    assert(tr.max_tier_used <= profile_by_id(7).max_tier, 'tier budget');

    assert(generate_dom9_planing_canon(1).profile_id == 3, 'dom9 planing');
    assert(generate_dominant_altered_canon(2).profile_id == 8, 'dominant altered');
    assert(generate_sus_quartal_canon(3).profile_id == 11, 'sus quartal');
    assert(generate_pandiatonic_canon(4).profile_id == 12, 'pandiatonic');
    assert(generate_spectral_canon(5).profile_id == 13, 'spectral');
    assert(generate_bartok_axis_canon(6).profile_id == 14, 'bartok');
    assert(generate_cluster_soft_canon(7).profile_id == 15, 'cluster soft');
    assert(generate_canon_per_tonos(8).profile_id == 16, 'per tonos');
}

#[test]
#[available_gas(4000000000000)]
fn test_complementary_generators_clash_free() {
    let add6 = generate_impressionist_added6_canon(11);
    assert(add6.profile_id == 17, 'added6 profile');
    assert(add6.config_id == 27, 'added6 config');
    assert(all_pairs_clash_free(@add6, @profile_by_id(17)), 'added6 clash-free');
    assert(exact_imitation(@add6), 'added6 canon');

    let bito = generate_bitonal_split_canon(22);
    assert(bito.profile_id == 18, 'bitonal profile');
    assert(all_pairs_clash_free(@bito, @profile_by_id(18)), 'bitonal clash-free');
    assert(exact_imitation(@bito), 'bitonal canon');

    let phry = generate_phrygian_cadential_canon(33);
    assert(phry.profile_id == 19, 'phrygian profile');
    assert(all_pairs_clash_free(@phry, @profile_by_id(19)), 'phrygian clash-free');
    assert(exact_imitation(@phry), 'phrygian canon');

    let penta = generate_pentatonic_open_canon(44);
    assert(penta.profile_id == 20, 'penta profile');
    assert(all_pairs_clash_free(@penta, @profile_by_id(20)), 'penta clash-free');
    assert(exact_imitation(@penta), 'penta canon');

    let neo = generate_neo_riemannian_canon(55);
    assert(neo.profile_id == 21, 'neo profile');
    assert(all_pairs_clash_free(@neo, @profile_by_id(21)), 'neo clash-free');
    assert(exact_imitation(@neo), 'neo canon');
}

// ──────────────────────────────────────────────────────────
// Avoid notes (chord-scale)
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_avoid_note_fourth_over_major() {
    // Cmaj7 = {0,4,7,11}. F (5) sits a half-step above E (4) → avoid note. F# (6) does not.
    let chord = array![0_u8, 4, 7, 11];
    assert(is_avoid_note(chord.span(), 5), 'F is avoid over Cmaj7');
    assert(!is_avoid_note(chord.span(), 6), 'F# not avoid (Lydian)');
    assert(!is_avoid_note(chord.span(), 9), 'A (13) not avoid');
}

// ──────────────────────────────────────────────────────────
// Parsimonious seventh-chord progression (Profile 5)
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_parsimonious_smooth_and_clash_free() {
    let mut seed: felt252 = 5;
    let mut i: u32 = 0;
    loop {
        if i >= 16 {
            break;
        }
        let events = generate_parsimonious_progression(seed * 13 + 1, 12);
        assert(events.len() == 48, 'twelve 4-voice chords');
        assert(voice_leading_smooth(events.span(), 2), 'every voice moves <= 2');
        assert(no_minor_ninth_in_chords(events.span()), 'no m2/m9 in chords');
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(2000000000000)]
fn test_parsimonious_deterministic() {
    let a = generate_parsimonious_progression(98765, 10);
    let b = generate_parsimonious_progression(98765, 10);
    assert(a.len() == b.len(), 'same length');
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        assert(*a.at(i).pitch == *b.at(i).pitch, 'identical pitch');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// The legacy generator is untouched
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_legacy_generator_still_works() {
    let canon = generate_melodic_canon(0x80000); // config 0, fifth above (diatonic)
    assert(canon.octave == 7, 'diatonic lattice');
    assert(canon.profile_id == 0, 'renaissance profile');
    assert(exact_imitation(@canon), 'still a canon');
}

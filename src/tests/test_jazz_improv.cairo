//! Jazz improvised canon — turnaround timeline, profile 24 generation, validators.

use core::array::ArrayTrait;
use koji::composition::aesthetic_profile::{profile_by_id, profile_jazz_improv};
use koji::composition::jazz_harmony::{
    TURNAROUND_REGIONS, DominantKind, TurnaroundPlan, turnaround_region_at,
    turnaround_scale_pcs_for_plan, turnaround_chord_pcs_for_plan,
    turnaround_plan_default, turnaround_plan_from_harmony_seed, turnaround_plan_from_canon_seed,
    turnaround_has_tritone_sub,
    jazz_timeline_material_ok,
    jazz_scale_degree_ok_for_plan, jazz_chord_tone_ok_for_plan, jazz_timeline_material_ok_for_plan,
    jazz_material_ok_with_walk,
};
use koji::composition::harmonic_walk::{
    canon_seed_enable_harmonic_walk, harmonic_walk_enabled_from_seed,
    harmonic_walk_plan_from_seed, timeline_from_harmonic_walk,
};
use koji::composition::canon_rules::{abs_i32, num_profiled_configs};
use koji::composition::melodic_canon::{
    generate_jazz_improv_canon, generate_jazz_improv_3v_canon,
    generate_jazz_improv_ornamented_canon,
    generate_profiled_ornamented_canon, plan_ornament_subdivisions_for_profile,
    all_pairs_clash_free, exact_imitation, no_minor_ninth,
};

fn pc12(degree: i32) -> u8 {
    let bias: i32 = 120;
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    (du % 12).try_into().unwrap()
}

fn contains_u8(set: Span<u8>, v: u8) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    loop {
        if i >= set.len() {
            break;
        }
        if *set.at(i) == v {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

#[test]
#[available_gas(1000000000000)]
fn test_turnaround_region_partition() {
    let len: u32 = 32;
    assert(turnaround_region_at(0, len) == 0, 'start region 0');
    assert(turnaround_region_at(7, len) == 0, 'still region 0');
    assert(turnaround_region_at(8, len) == 1, 'region 1');
    assert(turnaround_region_at(23, len) == 2, 'region 2');
    assert(turnaround_region_at(24, len) == 3, 'region 3');
    assert(TURNAROUND_REGIONS == 4, 'four regions');
}

#[test]
#[available_gas(1000000000000)]
fn test_tritone_sub_region3_chord_and_scale() {
    let plan = TurnaroundPlan { dominant: DominantKind::TritoneSub };
    let chord = turnaround_chord_pcs_for_plan(plan, 3);
    assert(chord.len() == 4, 'Db7 four tones');
    assert(contains_u8(chord, 1), 'Db root');
    assert(contains_u8(chord, 5), 'Db7 third');
    assert(contains_u8(chord, 8), 'Db7 fifth');
    assert(contains_u8(chord, 11), 'Db7 seventh');
    let scale = turnaround_scale_pcs_for_plan(plan, 3);
    assert(contains_u8(scale, 1), 'Db mix root');
    assert(contains_u8(scale, 3), 'Db mix second');
    assert(!contains_u8(scale, 7), 'G not in Db mix');
}

#[test]
#[available_gas(1000000000000)]
fn test_tritone_sub_material_gate() {
    let plan = TurnaroundPlan { dominant: DominantKind::TritoneSub };
    let len: u32 = 32;
    let pos: u32 = 24;
    assert(jazz_chord_tone_ok_for_plan(plan, 1, 3), 'Db strong beat');
    assert(!jazz_chord_tone_ok_for_plan(plan, 7, 3), 'G not Db7 tone');
    assert(jazz_scale_degree_ok_for_plan(plan, 3, 3), 'Eb weak Db mix');
    assert(
        jazz_timeline_material_ok_for_plan(plan, 1, pos, len, true),
        'Db strong at region 3',
    );
    assert(
        !jazz_timeline_material_ok_for_plan(plan, 7, pos, len, true),
        'G barred strong r3 sub',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_harmony_seed_selects_tritone_sub() {
    let vanilla = turnaround_plan_from_harmony_seed(1);
    let sub = turnaround_plan_from_harmony_seed(0);
    assert(vanilla.dominant == DominantKind::V7, 'seed 1 is V7');
    assert(sub.dominant == DominantKind::TritoneSub, 'seed 0 is tritone');
    assert(turnaround_plan_default().dominant == DominantKind::V7, 'default V7');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_improv_profile_matches_jazz_verticals() {
    let jazz = profile_by_id(1);
    let improv = profile_jazz_improv();
    assert(improv.id == 24, 'profile id 24');
    assert(improv.name == 'jazz_improv', 'name');
    assert(improv.octave == jazz.octave, 'chromatic lattice');
    assert(improv.table.len() == jazz.table.len(), 'table len');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_improv_catalogue_ids() {
    assert(num_profiled_configs() == 43, 'config count');
    assert(profile_by_id(24).id == 24, 'profile lookup');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_improv_canon_generates_clash_free() {
    let c4 = generate_jazz_improv_canon(99001);
    let c3 = generate_jazz_improv_3v_canon(99002);
    let p = profile_jazz_improv();
    assert(exact_imitation(@c4), '4v imitation');
    assert(all_pairs_clash_free(@c4, @p), '4v clash free');
    assert(exact_imitation(@c3), '3v imitation');
    assert(all_pairs_clash_free(@c3, @p), '3v clash free');
    assert(no_minor_ninth(@c4), '4v no m9');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_improv_no_semitone_structural_steps() {
    let canon = generate_jazz_improv_canon(99003);
    let mut i: u32 = 0;
    loop {
        if i >= canon.leader_steps.len() {
            break;
        }
        let s = *canon.leader_steps.at(i);
        assert(abs_i32(s) != 1, 'no semitone step');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_improv_ornaments_structural_only() {
    let (_, subs) = generate_profiled_ornamented_canon(99004, 41, 32);
    let mut i: u32 = 0;
    loop {
        if i >= subs.len() {
            break;
        }
        assert(*subs.at(i) == 1, 'subdivisions are 1');
        i += 1;
    };
    let direct = plan_ornament_subdivisions_for_profile(24, 7, array![2_i32, 4].span(), 4);
    assert(direct.len() == 2, 'two steps');
    assert(*direct.at(0) == 1, 'profile 24 no chromatic fill');
    assert(*direct.at(1) == 1, 'profile 24 no chromatic fill');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_improv_leader_respects_turnaround_scales() {
    let seed: felt252 = 99005;
    let plan = turnaround_plan_from_canon_seed(seed);
    let canon = generate_jazz_improv_canon(seed);
    let len = canon.leader_degrees.len();
    let mut p: u32 = 0;
    loop {
        if p >= len {
            break;
        }
        let d = *canon.leader_degrees.at(p);
        let r = turnaround_region_at(p, len);
        let strong = p % 4 == 0;
        if strong {
            assert(jazz_chord_tone_ok_for_plan(plan, d, r), 'strong beat chord tone');
        } else {
            assert(jazz_scale_degree_ok_for_plan(plan, d, r), 'weak beat scale tone');
        }
        let pc = pc12(d);
        assert(contains_u8(turnaround_scale_pcs_for_plan(plan, r), pc), 'pc in region scale');
        p += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_improv_tritone_sub_canon_generates() {
    let mut found_sub = false;
    let mut found_v7 = false;
    let mut seed: u32 = 0;
    loop {
        if seed >= 64 {
            break;
        }
        let plan = turnaround_plan_from_harmony_seed(seed);
        if turnaround_has_tritone_sub(plan) {
            found_sub = true;
        } else {
            found_v7 = true;
        }
        let s: felt252 = seed.into();
        let canon = generate_jazz_improv_canon(s);
        let p = profile_jazz_improv();
        assert(exact_imitation(@canon), 'sub seed imitation');
        assert(all_pairs_clash_free(@canon, @p), 'sub seed clash free');
        seed += 1;
    };
    assert(found_sub, 'harmony seeds include sub');
    assert(found_v7, 'harmony seeds include V7');
}

#[test]
#[available_gas(5000000000000)]
fn test_jazz_improv_no_long_static_runs() {
    let (canon, _) = generate_jazz_improv_ornamented_canon(770707, 41, 48);
    let degs = canon.leader_degrees;
    let mut max_run: u32 = 1;
    let mut run: u32 = 1;
    let mut prev = *degs.at(0);
    let mut i: u32 = 0;
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
    assert(max_run < 8, 'jazz static run');
}

#[test]
#[available_gas(1000000000000)]
fn test_harmonic_walk_disabled_by_default() {
    let seed: felt252 = 881881;
    assert(!harmonic_walk_enabled_from_seed(seed), 'walk off default');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_material_ok_with_walk_non_regression() {
    let seed: felt252 = 99005;
    let plan = turnaround_plan_from_canon_seed(seed);
    let len: u32 = 32;
    let pos: u32 = 8;
    let degree: i32 = 2;
    assert(
        jazz_material_ok_with_walk(seed, false, plan, degree, pos, len, true)
            == jazz_timeline_material_ok_for_plan(plan, degree, pos, len, true),
        'walk off matches turnaround',
    );
}

#[test]
#[available_gas(5000000000000)]
fn test_jazz_improv_harmonic_walk_canon_generates() {
    let walk_seed = canon_seed_enable_harmonic_walk(881881);
    let canon = generate_jazz_improv_canon(walk_seed);
    let p = profile_jazz_improv();
    assert(exact_imitation(@canon), 'walk canon imitation');
    assert(all_pairs_clash_free(@canon, @p), 'walk canon clash free');
    assert(no_minor_ninth(@canon), 'walk canon no m9');
    let plan = harmonic_walk_plan_from_seed(walk_seed);
    let tl = timeline_from_harmonic_walk(walk_seed, plan);
    let len = canon.leader_degrees.len();
    let mut pos: u32 = 0;
    loop {
        if pos >= len {
            break;
        }
        let d = *canon.leader_degrees.at(pos);
        assert(
            jazz_material_ok_with_walk(
                walk_seed, true, turnaround_plan_default(), d, pos, len, pos % 4 == 0,
            ),
            'leader on walk material',
        );
        pos += 1;
    };
    assert(tl.targets.len() > 0, 'walk timeline');
}

#[test]
#[available_gas(1000000000000)]
fn test_jazz_timeline_material_gate() {
    let len: u32 = 32;
    assert(jazz_timeline_material_ok(0, 0, len, true), 'I chord root strong');
    assert(!jazz_timeline_material_ok(1, 0, len, true), 'b2 not I chord tone');
    assert(jazz_timeline_material_ok(2, 0, len, false), 'D weak on I lydian');
}

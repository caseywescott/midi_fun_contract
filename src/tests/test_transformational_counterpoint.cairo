use koji::composition::aesthetic_profile::profile_renaissance;
use koji::composition::transformational_counterpoint::{
    CanonTransformKind, CanonTransformPlan, TransformFailure, TransformRole, TimeRatio,
    axis_invert_line, augment_line, crab_identity_holds, degree_events_to_note_events,
    degree_line_from_degrees, delay_line, diminish_line, events_overlap, exact_identity_holds,
    hocket_partition, hocket_part, hocket_reconstructs, invert_line, isorhythm_line,
    isorhythm_period, no_same_voice_overlaps, overlaps_consonant, retrograde_inversion_line,
    retrograde_line, rhythm_valid, simple_third_harmonized_composition, standalone_harmonized_transform,
    strict_transformed_follower, permissive_transformed_follower, seeded_canon_transform_plan,
    canon_transform_descriptor, canon_transform_kind_from_id, canon_transform_kind_id,
    texture_ic_safe, texture_profile_ok, time_scale_line, transformed_canon_texture,
    transformed_follower, transform_failure_for_pair, transpose_line, transpose_repair_profile,
    voice_exchange_by_index, voice_exchange_material_by_index,
};

#[test]
#[available_gas(1000000000000)]
fn test_pitch_transform_laws() {
    let line = degree_line_from_degrees(array![0_i32, 2, 4, 5].span(), 10, 0);

    let twice_retro = retrograde_line(retrograde_line(line.span()).span());
    assert(twice_retro.len() == line.len(), 'retro len');
    assert((*twice_retro.at(0)).degree == (*line.at(0)).degree, 'retro id deg0');
    assert((*twice_retro.at(3)).time == (*line.at(3)).time, 'retro id time3');

    let twice_inv = invert_line(invert_line(line.span(), 4).span(), 4);
    assert((*twice_inv.at(0)).degree == 0, 'inv id 0');
    assert((*twice_inv.at(2)).degree == 4, 'inv id 2');

    let axis = axis_invert_line(line.span(), 2);
    assert((*axis.at(0)).degree == 4, 'axis inv 0');
    assert((*axis.at(2)).degree == 0, 'axis inv 2');

    let ri = retrograde_inversion_line(line.span(), 4);
    assert((*ri.at(0)).degree == -1, 'ri first');
    assert((*ri.at(3)).degree == 4, 'ri last');
}

#[test]
#[available_gas(1000000000000)]
fn test_time_transform_laws() {
    let line = degree_line_from_degrees(array![0_i32, 2, 4].span(), 12, 0);

    let aug = augment_line(line.span(), 2);
    assert((*aug.at(1)).time == 24, 'aug time');
    assert((*aug.at(1)).duration == 24, 'aug dur');

    let dim = diminish_line(aug.span(), 2);
    assert((*dim.at(1)).time == (*line.at(1)).time, 'dim time');
    assert((*dim.at(2)).duration == (*line.at(2)).duration, 'dim dur');

    let delayed = delay_line(line.span(), 7);
    assert((*delayed.at(0)).time == 7, 'delay');

    let scaled = time_scale_line(line.span(), TimeRatio { num: 3, den: 2 });
    assert((*scaled.at(1)).time == 18, 'scale time');
    assert((*scaled.at(0)).duration == 18, 'scale dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_mirror_canon_follower_identity_and_validation() {
    let leader = degree_line_from_degrees(array![0_i32, 2, 4, 2].span(), 10, 0);
    let plan = CanonTransformPlan {
        kind: CanonTransformKind::Mirror(()),
        entry_time: 10,
        transposition: 0,
        pivot: 4,
        factor: 1,
        follower_voice_id: 1,
    };
    let follower = transformed_follower(leader.span(), plan);
    assert((*follower.at(0)).degree == 4, 'mirror first');
    assert((*follower.at(0)).time == 10, 'mirror delay');
    assert((*follower.at(1)).degree == 2, 'mirror second');
    assert(overlaps_consonant(leader.span(), follower.span()), 'mirror consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_crab_canon_identity() {
    let leader = degree_line_from_degrees(array![0_i32, 2, 4, 5].span(), 10, 0);
    let plan = CanonTransformPlan {
        kind: CanonTransformKind::Crab(()),
        entry_time: 20,
        transposition: 0,
        pivot: 0,
        factor: 1,
        follower_voice_id: 1,
    };
    let follower = transformed_follower(leader.span(), plan);
    assert((*follower.at(0)).degree == 5, 'crab first degree');
    assert((*follower.at(0)).time == 20, 'crab first time');
    assert(crab_identity_holds(leader.span(), follower.span(), 0, 20), 'crab id');
}

#[test]
#[available_gas(1000000000000)]
fn test_exact_augmented_diminished_followers() {
    let leader = degree_line_from_degrees(array![0_i32, 2, 4].span(), 12, 0);

    let exact_plan = CanonTransformPlan {
        kind: CanonTransformKind::Exact(()),
        entry_time: 12,
        transposition: 4,
        pivot: 0,
        factor: 1,
        follower_voice_id: 1,
    };
    let exact = transformed_follower(leader.span(), exact_plan);
    assert(exact_identity_holds(leader.span(), exact.span(), 4, 12), 'exact id');

    let aug_plan = CanonTransformPlan {
        kind: CanonTransformKind::Augmentation(()),
        entry_time: 0,
        transposition: 0,
        pivot: 0,
        factor: 2,
        follower_voice_id: 2,
    };
    let aug = transformed_follower(leader.span(), aug_plan);
    assert((*aug.at(1)).time == 24, 'aug follower time');
    assert((*aug.at(1)).duration == 24, 'aug follower dur');

    let dim_plan = CanonTransformPlan {
        kind: CanonTransformKind::Diminution(()),
        entry_time: 0,
        transposition: 0,
        pivot: 0,
        factor: 2,
        follower_voice_id: 3,
    };
    let dim = transformed_follower(leader.span(), dim_plan);
    assert((*dim.at(1)).time == 6, 'dim follower time');
    assert((*dim.at(1)).duration == 6, 'dim follower dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_voice_exchange_variants() {
    let a = degree_line_from_degrees(array![0_i32, 2, 4].span(), 10, 0);
    let b = degree_line_from_degrees(array![4_i32, 5, 7].span(), 10, 1);

    let (pa, pb) = voice_exchange_by_index(a.span(), b.span(), 1, 3);
    assert((*pa.at(0)).degree == 0, 'pitch ex keep');
    assert((*pa.at(1)).degree == 5, 'pitch ex swap a');
    assert((*pb.at(2)).degree == 4, 'pitch ex swap b');

    let (ma, mb) = voice_exchange_material_by_index(a.span(), b.span(), 0, 1);
    assert((*ma.at(0)).degree == 4, 'mat ex a');
    assert((*ma.at(0)).voice_id == 0, 'mat ex keeps voice a');
    assert((*mb.at(0)).degree == 0, 'mat ex b');
    assert((*mb.at(0)).voice_id == 1, 'mat ex keeps voice b');
}

#[test]
#[available_gas(1000000000000)]
fn test_hocket_partition_and_reconstruction() {
    let line = degree_line_from_degrees(array![0_i32, 2, 4, 5, 7].span(), 10, 0);
    let hocket = hocket_partition(line.span(), 2, 10);
    assert(hocket.len() == line.len(), 'hocket len');
    assert((*hocket.at(0)).voice_id == 10, 'hocket v0');
    assert((*hocket.at(1)).voice_id == 11, 'hocket v1');
    assert(hocket_reconstructs(line.span(), hocket.span()), 'hocket reconstructs');
    assert(no_same_voice_overlaps(hocket.span()), 'hocket no overlap');

    let part = hocket_part(line.span(), 2, 1, 20);
    assert(part.len() == 2, 'hocket part len');
    assert((*part.at(0)).degree == 2, 'hocket part deg');
    assert((*part.at(0)).voice_id == 20, 'hocket part voice');
}

#[test]
#[available_gas(1000000000000)]
fn test_isorhythm_period_and_line() {
    assert(isorhythm_period(3, 2) == 6, 'lcm');
    let line = isorhythm_line(array![0_i32, 2, 4].span(), array![3_u32, 5].span(), 1, 0);
    assert(line.len() == 6, 'isorhythm len');
    assert((*line.at(0)).degree == 0, 'iso degree 0');
    assert((*line.at(1)).degree == 2, 'iso degree 1');
    assert((*line.at(2)).degree == 4, 'iso degree 2');
    assert((*line.at(3)).degree == 0, 'iso degree cycle');
    assert((*line.at(2)).time == 8, 'iso time');
}

#[test]
#[available_gas(1000000000000)]
fn test_standalone_harmonized_composition_validates() {
    let subject = degree_line_from_degrees(array![0_i32, 2, 4, 5].span(), 10, 0);
    let plan = simple_third_harmonized_composition(subject.span(), 1);
    let texture = koji::composition::transformational_counterpoint::composition_to_events(@plan);
    let profile = profile_renaissance();
    assert(texture_profile_ok(texture.span(), @profile), 'third profile ok');
    assert(texture_ic_safe(texture.span(), 7), 'third ic ok');

    let notes = degree_events_to_note_events(texture.span(), 7, 60, 0);
    assert(notes.len() == 8, 'notes len');
    assert((*notes.at(0)).voice_id == 0, 'note voice 0');
}

#[test]
#[available_gas(1000000000000)]
fn test_validation_failure_categories() {
    let a = degree_line_from_degrees(array![0_i32].span(), 10, 0);
    let b = degree_line_from_degrees(array![1_i32].span(), 10, 1);
    let profile = profile_renaissance();
    let failure = transform_failure_for_pair(a.span(), b.span(), @profile, false);
    match failure {
        TransformFailure::VerticalClash(_) => assert(true, 'vertical clash'),
        _ => assert(false, 'expected clash'),
    }

    let c = degree_line_from_degrees(array![4_i32].span(), 10, 1);
    let ic_failure = transform_failure_for_pair(a.span(), c.span(), @profile, true);
    match ic_failure {
        TransformFailure::ICSafetyClash(_) => assert(true, 'ic clash'),
        _ => assert(false, 'expected ic clash'),
    }
}

#[test]
#[available_gas(1000000000000)]
fn test_seeded_plan_and_descriptors() {
    let kind = canon_transform_kind_from_id(1);
    assert(canon_transform_kind_id(kind) == 1, 'kind id');
    assert(canon_transform_descriptor(kind) == 'MirrorCanon', 'descriptor');

    let p1 = seeded_canon_transform_plan(12345, 10, 4);
    let p2 = seeded_canon_transform_plan(12345, 10, 4);
    assert(canon_transform_kind_id(p1.kind) == canon_transform_kind_id(p2.kind), 'seed kind det');
    assert(p1.entry_time == p2.entry_time, 'seed entry det');
    assert(p1.follower_voice_id == 4, 'seed voice');
    assert(p1.factor >= 1 && p1.factor <= 2, 'seed factor bounded');
}

#[test]
#[available_gas(1000000000000)]
fn test_repair_and_strict_generation_policies() {
    let leader = degree_line_from_degrees(array![0_i32, 0].span(), 10, 0);
    let bad = degree_line_from_degrees(array![1_i32, 1].span(), 10, 1);
    let profile = profile_renaissance();

    let repair = transpose_repair_profile(leader.span(), bad.span(), @profile, -4, 4);
    assert(repair.found, 'repair found');
    assert(repair.transposition == -3, 'repair chooses first safe');

    let plan = CanonTransformPlan {
        kind: CanonTransformKind::Mirror(()),
        entry_time: 0,
        transposition: 0,
        pivot: 1,
        factor: 1,
        follower_voice_id: 1,
    };
    let strict = strict_transformed_follower(leader.span(), plan, @profile);
    assert(!strict.found, 'strict rejects');

    let permissive = permissive_transformed_follower(leader.span(), plan, @profile);
    assert(permissive.found, 'permissive repairs');
}

#[test]
#[available_gas(1000000000000)]
fn test_transformed_canon_texture_renders() {
    let leader = degree_line_from_degrees(array![0_i32, 2, 4].span(), 10, 0);
    let plan = CanonTransformPlan {
        kind: CanonTransformKind::RetrogradeInversion(()),
        entry_time: 10,
        transposition: 0,
        pivot: 4,
        factor: 1,
        follower_voice_id: 1,
    };
    let texture = transformed_canon_texture(leader.span(), plan);
    assert(texture.len() == 6, 'texture len');
    assert(rhythm_valid(texture.span()), 'texture rhythm');
    let notes = degree_events_to_note_events(texture.span(), 7, 60, 0);
    assert(notes.len() == 6, 'render notes');
}

#[test]
#[available_gas(1000000000000)]
fn test_standalone_explicit_plan() {
    let subject = degree_line_from_degrees(array![0_i32, 2, 4].span(), 10, 0);
    let companion = transpose_line(subject.span(), 2);
    let companion_v = koji::composition::transformational_counterpoint::assign_voice_id(companion.span(), 2);
    let plan = standalone_harmonized_transform(
        subject.span(), companion_v.span(), TransformRole::Countersubject(()),
    );
    let texture = koji::composition::transformational_counterpoint::composition_to_events(@plan);
    assert(texture.len() == 6, 'explicit plan len');
    assert(events_overlap(*texture.at(0), *texture.at(3)), 'voices overlap');
}

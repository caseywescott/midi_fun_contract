use core::array::ArrayTrait;
use koji::composition::counterpoint::{
    Contour, CounterpointParams, ModeSpec, MotionKind, REST_PITCH, VoicePlacement,
    build_mode_timeline, build_mode_timeline_full, classify_motion, encode_contour,
    expand_onset_pitches, extract_onset_pitches, fixed_mode_spec, generate_counterpoint,
    generate_counterpoint_sparse, generate_n_voice_counterpoint, count_onsets, is_mode_boundary,
    is_forbidden_vertical_interval_class, is_rest_pitch, mode_from_id, mode_to_id,
    motion_bias_contrary, motion_contour, resolve_mode_at, score_counter_candidate,
    tonic_at_timeline, violates_forbidden_interval, violates_voice_placement,
    would_create_parallel_perfect, would_create_similar_motion_perfect,
};
use koji::composition::counterpoint_canon::{
    harmony_plan_is_rest, lydian_pitch_world_mask, pitch_from_harmony_plan,
    plan_lydian_canon_harmony, plan_lydian_canon_harmony_sparse, uniform_mode_timeline,
};
use koji::composition::symmetry_engine::has_pitch;
use koji::midi::types::{Modes, PitchClass};

fn lydian_params(seed: felt252, lo: u8, hi: u8, bias: koji::composition::counterpoint::MotionBias) -> CounterpointParams {
    CounterpointParams {
        seed,
        tonic: PitchClass { note: 0, octave: 4 },
        mode_spec: fixed_mode_spec(Modes::Lydian(()), 0),
        register_lo: lo,
        register_hi: hi,
        max_melodic_leap: 12,
        motion_bias: bias,
        voice_placement: VoicePlacement::Free(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
    }
}

#[test]
#[available_gas(1000000000000)]
fn test_encode_contour_known_melody() {
    let notes = array![60_u8, 62_u8, 62_u8, 57_u8];
    let contour = encode_contour(notes.span());
    assert(contour.len() == 3, 'contour len');
    assert(*contour.at(0) == Contour::Up(()), 'c0 up');
    assert(*contour.at(1) == Contour::Repeat(()), 'c1 repeat');
    assert(*contour.at(2) == Contour::Down(()), 'c2 down');
}

#[test]
#[available_gas(1000000000000)]
fn test_motion_contour() {
    assert(motion_contour(60, 62) == Contour::Up(()), 'up');
    assert(motion_contour(62, 60) == Contour::Down(()), 'down');
    assert(motion_contour(60, 60) == Contour::Repeat(()), 'repeat');
}

#[test]
#[available_gas(1000000000000)]
fn test_mode_id_roundtrip() {
    assert(mode_to_id(Modes::Lydian(())) == 2, 'lydian id');
    assert(mode_to_id(Modes::Mixolydian(())) == 3, 'mixo id');
    assert(mode_to_id(mode_from_id(2)) == 2, 'lydian back');
    assert(mode_to_id(mode_from_id(3)) == 3, 'mixo back');
}

#[test]
#[available_gas(1000000000000)]
fn test_tonic_timeline() {
    let mode_ids = array![2_u8, 2_u8];
    let tonics = array![0_u8, 5_u8];
    let octaves = array![4_u8, 4_u8];
    let timeline = build_mode_timeline_full(mode_ids, array![], array![], tonics, octaves);
    let t0 = tonic_at_timeline(@timeline, 0, PitchClass { note: 0, octave: 3 });
    let t1 = tonic_at_timeline(@timeline, 1, PitchClass { note: 0, octave: 3 });
    assert(t0.note == 0, 't0 note');
    assert(t1.note == 5, 't1 note');
}

#[test]
#[available_gas(1000000000000)]
fn test_resolve_mode_timeline() {
    let mode_ids = array![2_u8, 2_u8, 3_u8, 3_u8];
    let timeline = build_mode_timeline(mode_ids, array![], array![]);
    let spec = ModeSpec::Timeline(timeline);

    let r0 = resolve_mode_at(@spec, 0);
    let r2 = resolve_mode_at(@spec, 2);
    assert(mode_to_id(r0.mode) == 2, 'idx0 lydian');
    assert(mode_to_id(r2.mode) == 3, 'idx2 mixo');
    assert(!is_mode_boundary(@spec, 1), 'idx1 not boundary');
    assert(is_mode_boundary(@spec, 2), 'idx2 is boundary');
}

#[test]
#[available_gas(1000000000000)]
fn test_voice_placement_veto() {
    assert(violates_voice_placement(58, 60, VoicePlacement::AboveCantus(())), 'above fail');
    assert(!violates_voice_placement(65, 60, VoicePlacement::AboveCantus(())), 'above ok');
    assert(violates_voice_placement(62, 60, VoicePlacement::BelowCantus(())), 'below fail');
}

#[test]
#[available_gas(1000000000000)]
fn test_similar_motion_perfect() {
    // Both rise into octave
    assert(would_create_similar_motion_perfect(60, 60, 72, 72), 'similar octave');
}

#[test]
#[available_gas(1000000000000)]
fn test_classify_motion_pairs() {
    assert(
        classify_motion(Contour::Up(()), Contour::Up(())) == MotionKind::Parallel(()),
        'parallel up',
    );
    assert(
        classify_motion(Contour::Up(()), Contour::Down(())) == MotionKind::Contrary(()),
        'contrary',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_parallel_fifth_veto() {
    assert(would_create_parallel_perfect(62, 67, 67, 72), 'parallel fifth');
    assert(!would_create_parallel_perfect(62, 67, 64, 72), 'not parallel');
}

#[test]
#[available_gas(1000000000000)]
fn test_parallel_veto_blocks_bad_candidate() {
    let params = lydian_params(42, 48, 79, motion_bias_contrary());
    let empty: Array<u8> = array![];
    let bad = score_counter_candidate(
        67, 62, 67, 72, Contour::Up(()), @params, 0, false, false, empty.span(), empty.span(),
    );
    assert(bad == 0, 'parallel fifth blocked');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_counterpoint_length() {
    let cantus = array![60_u8, 62_u8, 64_u8, 65_u8, 67_u8];
    let params = lydian_params(7, 48, 79, motion_bias_contrary());
    let result = generate_counterpoint(cantus.span(), params);
    assert(result.counter.len() == cantus.len(), 'counter len');
    assert(result.contrary_count + result.parallel_count + result.oblique_count == cantus.len() - 1, 'motion sum');
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_stays_in_register() {
    let cantus = array![60_u8, 62_u8, 64_u8, 67_u8, 69_u8, 71_u8, 72_u8];
    let lo: u8 = 48;
    let hi: u8 = 79;
    let params = lydian_params(99, lo, hi, motion_bias_contrary());
    let result = generate_counterpoint(cantus.span(), params);
    let mut i: usize = 0;
    loop {
        if i >= result.counter.len() {
            break;
        }
        let n = *result.counter.at(i);
        assert(n >= lo, 'below register');
        assert(n <= hi, 'above register');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_deterministic() {
    let cantus = array![60_u8, 62_u8, 64_u8, 65_u8, 67_u8, 69_u8];
    let a = generate_counterpoint(cantus.span(), lydian_params(12345, 48, 79, motion_bias_contrary()));
    let b = generate_counterpoint(cantus.span(), lydian_params(12345, 48, 79, motion_bias_contrary()));
    assert(*a.counter.at(5) == *b.counter.at(5), 'deterministic');
}

#[test]
#[available_gas(1000000000000)]
fn test_contrary_bias_produces_contrary_motion() {
    let cantus = array![60_u8, 62_u8, 64_u8, 62_u8, 60_u8, 62_u8, 64_u8];
    let result = generate_counterpoint(cantus.span(), lydian_params(555, 48, 79, motion_bias_contrary()));
    assert(result.contrary_count >= 1, 'some contrary motion');
}

#[test]
#[available_gas(1000000000000)]
fn test_n_voice_same_side_ordering() {
    let cantus = array![60_u8, 62_u8, 64_u8, 65_u8, 67_u8, 69_u8];
    let base = lydian_params(42, 48, 84, motion_bias_contrary());
    let voices = generate_n_voice_counterpoint(cantus.span(), @base, 8);
    assert(voices.len() == 8, '8 voices');
    let sounding = count_onsets(array![1_u32, 1_u32, 1_u32, 1_u32, 1_u32, 1_u32].span());
    let mut vi: u32 = 1;
    loop {
        if vi >= 8 {
            break;
        }
        let line = voices.at(vi.try_into().unwrap());
        assert(line.len() == cantus.len(), 'voice len');
        let mut notes: u32 = 0;
        let mut i: usize = 0;
        loop {
            if i >= line.len() {
                break;
            }
            if !is_rest_pitch(*line.at(i)) {
                notes += 1;
            }
            i += 1;
        };
        assert(notes == sounding, 'full melody each voice');
        vi += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_n_voice_counterpoint() {
    let cantus = array![60_u8, 62_u8, 64_u8, 65_u8, 67_u8, 69_u8];
    let base = lydian_params(42, 48, 84, motion_bias_contrary());
    let voices = generate_n_voice_counterpoint(cantus.span(), @base, 4);
    assert(voices.len() == 4, '4 voices');
    assert(voices.at(0).len() == cantus.len(), 'cantus len');
    assert(voices.at(3).len() == cantus.len(), 'v3 len');
}

#[test]
#[available_gas(1000000000000)]
fn test_lydian_pitch_world_mask_has_seven_tones() {
    let tonic = PitchClass { note: 0, octave: 4 };
    let mask = lydian_pitch_world_mask(tonic);
    assert(has_pitch(mask, 0), 'C');
    assert(has_pitch(mask, 6), 'F# lydian');
    assert(!has_pitch(mask, 5), 'no F natural');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_lydian_harmony_stays_in_collection() {
    let cantus = array![60_u8, 62_u8, 64_u8, 67_u8, 69_u8, 71_u8];
    let tonic = PitchClass { note: 0, octave: 4 };
    let mask = lydian_pitch_world_mask(tonic);
    let plan = plan_lydian_canon_harmony(123, cantus.span(), tonic, 0, 4);
    let mut vi: u32 = 0;
    loop {
        if vi >= plan.voices.len() {
            break;
        }
        let voice = plan.voices.at(vi);
        let mut i: usize = 0;
        loop {
            if i >= voice.len() {
                break;
            }
            let p = *voice.at(i);
            if !is_rest_pitch(p) {
                assert(has_pitch(mask, p % 12), 'lydian pitch');
            }
            i += 1;
        };
        vi += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_harmony_plan() {
    let cantus = array![60_u8, 62_u8, 64_u8, 67_u8, 69_u8, 71_u8];
    let tonic = PitchClass { note: 0, octave: 4 };
    let plan = plan_lydian_canon_harmony(77, cantus.span(), tonic, 0, 3);
    assert(plan.voices.len() == 3, 'plan voices');
    let p0 = pitch_from_harmony_plan(@plan, 0, 0);
    let p1 = pitch_from_harmony_plan(@plan, 1, 0);
    assert(p0 == 60, 'leader pitch');
    assert(p1 < p0, 'v1 below cantus');
}

#[test]
#[available_gas(1000000000000)]
fn test_uniform_mode_timeline_len() {
    let spec = uniform_mode_timeline(6, Modes::Lydian(()), 0, PitchClass { note: 0, octave: 4 });
    let cantus = array![60_u8, 62_u8, 64_u8, 65_u8, 67_u8, 69_u8];
    let params = CounterpointParams {
        seed: 1,
        tonic: PitchClass { note: 0, octave: 4 },
        mode_spec: spec,
        register_lo: 48,
        register_hi: 79,
        max_melodic_leap: 12,
        motion_bias: motion_bias_contrary(),
        voice_placement: VoicePlacement::Free(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
    };
    let result = generate_counterpoint(cantus.span(), params);
    assert(result.counter.len() == 6, 'uniform timeline ok');
}

fn timeline_params_6(seed: felt252) -> CounterpointParams {
    let mode_ids = array![2_u8, 2_u8, 2_u8, 3_u8, 3_u8, 3_u8];
    let timeline = build_mode_timeline(mode_ids, array![], array![]);
    CounterpointParams {
        seed,
        tonic: PitchClass { note: 0, octave: 4 },
        mode_spec: ModeSpec::Timeline(timeline),
        register_lo: 48,
        register_hi: 79,
        max_melodic_leap: 12,
        motion_bias: motion_bias_contrary(),
        voice_placement: VoicePlacement::Free(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
    }
}

fn timeline_params(seed: felt252) -> CounterpointParams {
    let mode_ids = array![2_u8, 2_u8, 3_u8, 3_u8, 3_u8];
    let timeline = build_mode_timeline(mode_ids, array![], array![]);
    CounterpointParams {
        seed,
        tonic: PitchClass { note: 0, octave: 4 },
        mode_spec: ModeSpec::Timeline(timeline),
        register_lo: 48,
        register_hi: 79,
        max_melodic_leap: 12,
        motion_bias: motion_bias_contrary(),
        voice_placement: VoicePlacement::Free(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
    }
}

#[test]
#[available_gas(1000000000000)]
fn test_generate_with_mode_timeline() {
    let cantus = array![60_u8, 62_u8, 64_u8, 65_u8, 67_u8, 69_u8];
    let result = generate_counterpoint(cantus.span(), timeline_params_6(808));
    assert(result.counter.len() == 6, 'timeline counter len');
}

#[test]
#[available_gas(1000000000000)]
fn test_timeline_deterministic() {
    let cantus = array![60_u8, 62_u8, 64_u8, 65_u8, 67_u8];
    let a = generate_counterpoint(cantus.span(), timeline_params(999));
    let b = generate_counterpoint(cantus.span(), timeline_params(999));
    assert(*a.counter.at(4) == *b.counter.at(4), 'timeline deterministic');
}

#[test]
#[available_gas(1000000000000)]
fn test_sparse_extract_expand_roundtrip() {
    let tile = array![60_u8, REST_PITCH, 64_u8, REST_PITCH, 67_u8];
    let mask = array![1_u32, 0_u32, 1_u32, 0_u32, 1_u32];
    let sparse = extract_onset_pitches(tile.span(), mask.span());
    assert(sparse.len() == 3, '3 onsets');
    let expanded = expand_onset_pitches(sparse.span(), mask.span());
    assert(expanded.len() == 5, 'tile len');
    assert(*expanded.at(1) == REST_PITCH, 'rest slot');
    assert(*expanded.at(2) == 64, 'onset pitch');
}

#[test]
#[available_gas(1000000000000)]
fn test_sparse_counterpoint_rests_on_grid() {
    let tile = array![60_u8, REST_PITCH, 64_u8, REST_PITCH, 67_u8, REST_PITCH];
    let mask = array![1_u32, 0_u32, 1_u32, 0_u32, 1_u32, 0_u32];
    let params = lydian_params(321, 48, 79, motion_bias_contrary());
    let result = generate_counterpoint_sparse(tile.span(), mask.span(), params);
    assert(result.counter.len() == 6, 'tile counter len');
    assert(*result.counter.at(1) == REST_PITCH, 'rest at idx 1');
    assert(*result.counter.at(3) == REST_PITCH, 'rest at idx 3');
    assert(!is_rest_pitch(*result.counter.at(0)), 'sounds at 0');
    assert(!is_rest_pitch(*result.counter.at(2)), 'sounds at 2');
}

#[test]
#[available_gas(1000000000000)]
fn test_pairwise_parallel_veto_vs_lower() {
    let params = lydian_params(42, 48, 79, motion_bias_contrary());
    let lower_now = array![55_u8];
    let lower_prev = array![53_u8];
    let bad = score_counter_candidate(
        60, 58, 67, 69, Contour::Up(()), @params, 1, false, false,
        lower_now.span(), lower_prev.span(),
    );
    assert(bad == 0, 'pairwise parallel blocked');
}

#[test]
#[available_gas(1000000000000)]
fn test_n_voice_sparse_plan() {
    let tile = array![60_u8, REST_PITCH, 64_u8, REST_PITCH, 67_u8];
    let mask = array![1_u32, 0_u32, 1_u32, 0_u32, 1_u32];
    let tonic = PitchClass { note: 0, octave: 4 };
    let plan = plan_lydian_canon_harmony_sparse(88, tile.span(), mask.span(), tonic, 0, 3);
    assert(plan.voices.len() == 3, '3 voices');
    assert(harmony_plan_is_rest(@plan, 1, 1), 'harmony rest tile');
    let p1 = pitch_from_harmony_plan(@plan, 1, 0);
    assert(p1 < 60, 'v1 below cantus at 0');
    let mut vi: u32 = 1;
    loop {
        if vi >= plan.voices.len() {
            break;
        }
        let line = plan.voices.at(vi);
        let mut notes: u32 = 0;
        let mut i: usize = 0;
        loop {
            if i >= line.len() {
                break;
            }
            if !harmony_plan_is_rest(@plan, vi, i.try_into().unwrap()) {
                notes += 1;
            }
            i += 1;
        };
        assert(notes >= 2, 'sparse voice has melody');
        vi += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_timeline_with_world_ids() {
    let cantus = array![60_u8, 62_u8, 64_u8, 67_u8];
    let mode_ids = array![2_u8, 2_u8, 2_u8, 2_u8];
    let world_ids = array![0_u16, 0_u16, 3_u16, 3_u16];
    let timeline = build_mode_timeline(mode_ids, world_ids, array![]);
    let spec = ModeSpec::Timeline(timeline);
    assert(is_mode_boundary(@spec, 2), 'world boundary at 2');
    let params = CounterpointParams {
        seed: 314,
        tonic: PitchClass { note: 0, octave: 4 },
        mode_spec: spec,
        register_lo: 48,
        register_hi: 79,
        max_melodic_leap: 12,
        motion_bias: motion_bias_contrary(),
        voice_placement: VoicePlacement::Free(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
    };
    let result = generate_counterpoint(cantus.span(), params);
    assert(result.counter.len() == 4, 'world timeline len');
}

#[test]
#[available_gas(1000000000000)]
fn test_forbidden_vertical_interval_classes() {
    assert(is_forbidden_vertical_interval_class(1), 'minor second');
    assert(is_forbidden_vertical_interval_class(2), 'major second');
    assert(is_forbidden_vertical_interval_class(6), 'tritone');
    assert(!is_forbidden_vertical_interval_class(3), 'minor third ok');
    assert(!is_forbidden_vertical_interval_class(4), 'major third ok');
    assert(!is_forbidden_vertical_interval_class(5), 'fourth ok');
    assert(!is_forbidden_vertical_interval_class(7), 'fifth ok');
    assert(!is_forbidden_vertical_interval_class(8), 'minor sixth ok');
    assert(!is_forbidden_vertical_interval_class(9), 'major sixth ok');
    assert(violates_forbidden_interval(66, 64), 'E-F# second');
    assert(!violates_forbidden_interval(67, 64), 'E-G third');
}

#[test]
#[available_gas(1000000000000)]
fn test_contrary_demo_cantus_has_no_seconds() {
    let cantus = array![60_u8, 64, 67, 72, 67, 64, 60, 55];
    let strong_contrary = koji::composition::counterpoint::MotionBias {
        parallel: 5, contrary: 95, oblique: 15,
    };
    let tonic = PitchClass { note: 0, octave: 4 };
    let mode_spec = uniform_mode_timeline(
        cantus.len().try_into().unwrap(),
        Modes::Lydian(()),
        lydian_pitch_world_mask(tonic),
        tonic,
    );
    let params = CounterpointParams {
        seed: 101,
        tonic,
        mode_spec,
        register_lo: 48,
        register_hi: 84,
        max_melodic_leap: 12,
        motion_bias: strong_contrary,
        voice_placement: VoicePlacement::AboveCantus(()),
        forbid_parallel_perfects: true,
        forbid_similar_perfects: true,
    };
    let result = generate_counterpoint(cantus.span(), params);
    let mut i: usize = 0;
    loop {
        if i >= cantus.len() {
            break;
        }
        let c = *cantus.at(i);
        let h = *result.counter.at(i);
        assert(!violates_forbidden_interval(h, c), 'no seconds');
        i += 1;
    };
}

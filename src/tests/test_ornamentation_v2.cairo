//! Tests for v2 melodic ornamentation engine (§18).

use core::array::ArrayTrait;
use koji::composition::melodic_canon::{
    build_canon_for_test, generate_melodic_canon,
};
use koji::composition::ornamentation_v2::engine::{
    default_config, ornament_canon, ornament_phrase,
};
use koji::composition::ornamentation_v2::encoding::{
    encode_ornament_event, expand_ornament_event, rule_mode_matches_expanded,
};
use koji::composition::ornamentation_v2::ornaments::{
    ornament_can_apply, ornament_generate,
};
use koji::composition::ornamentation_v2::pitch::{
    interval_above_bass, scale_step_distance,
};
use koji::composition::ornamentation_v2::profiles::profile_modal_canon;
use koji::composition::ornamentation_v2::selection::{advance_seed, deterministic_choice_u8};
use koji::composition::ornamentation_v2::types::{
    all_enabled_ornaments, default_constraints, HarmonyEvent, minimal_viable_ornaments,
    OrnamentConfig, OrnamentContext, OUTPUT_ONCHAIN_COMPACT, OUTPUT_SYMBOLIC, ORN_NEIGHBOR_UPPER,
    ORN_PASSING_ASC, ORN_SUSPENSION_43, ORN_TRILL_UPPER, ROLE_NEIGHBOR, ROLE_STRUCTURAL,
    ROLE_SUSPENSION, SELECTION_SEEDED, structural_event, V2NoteEvent, WORKFLOW_CANON_FIRST,
};
use koji::composition::ornamentation_v2::validation::{
    validate_melodic_local, validate_neighbor_contour, validate_retardation_resolution,
    validate_suspension_resolution,
};

fn test_phrase_c_major() -> (Array<V2NoteEvent>, Array<i32>) {
    let tonic: u8 = 60;
    let unit: u32 = 4;
    let mut phrase: Array<V2NoteEvent> = ArrayTrait::new();
    let mut degrees: Array<i32> = ArrayTrait::new();
    let degs = array![0_i32, 2, 4, 7];
    let mut i: u32 = 0;
    loop {
        if i >= degs.len() {
            break;
        }
        let d = *degs.at(i);
        let midi = koji::composition::ornamentation_v2::pitch::degree_to_midi(d, tonic, 0, 7);
        phrase.append(
            structural_event(
                koji::composition::ornamentation_v2::pitch::midi_to_pitch(midi, d),
                i * unit,
                unit,
                0,
            ),
        );
        degrees.append(d);
        i += 1;
    };
    (phrase, degrees)
}

fn test_harmony_c_major() -> Array<HarmonyEvent> {
    let mut h: Array<HarmonyEvent> = ArrayTrait::new();
    h.append(HarmonyEvent { root_pc: 0, bass_pc: 0, start: 0, duration: 16, function_label: 0 });
    h
}

#[test]
#[available_gas(1000000000000)]
fn test_passing_can_apply_third_fill() {
    let ctx = OrnamentContext {
        anchor_index: 1,
        metric_position: 4,
        beat_strength: 80,
        available_duration: 4,
        subdivision: 1,
        scale_len: 7,
        voice_index: 0,
        canon_voice_index: 0,
        seed_state: 7,
        mode_id: 0,
        key_pc: 0,
        has_prev_anchor: true,
        has_next_anchor: true,
        has_current_harmony: false,
        has_prev_harmony: false,
        has_next_harmony: false,
        has_applied_transform: false,
        has_tile: false,
        sounding_voice_count: 0,
    };
    let chord = array![0_u8, 4, 7];
    assert(scale_step_distance(0, 2) == 2, 'distance 2');
    assert(
        ornament_can_apply(ORN_PASSING_ASC, ctx, 1, 0, 2, 4, chord.span(), 0, chord.span()),
        'passing should apply',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_neighbor_first_last_equals_anchor() {
    let ctx = OrnamentContext {
        anchor_index: 0,
        metric_position: 0,
        beat_strength: 80,
        available_duration: 4,
        subdivision: 1,
        scale_len: 7,
        voice_index: 0,
        canon_voice_index: 0,
        seed_state: 7,
        mode_id: 0,
        key_pc: 0,
        has_prev_anchor: false,
        has_next_anchor: true,
        has_current_harmony: false,
        has_prev_harmony: false,
        has_next_harmony: false,
        has_applied_transform: false,
        has_tile: false,
        sounding_voice_count: 0,
    };
    let chord = array![0_u8, 4, 7];
    let events = ornament_generate(
        ORN_NEIGHBOR_UPPER, ctx, 4, 2, 7, 8, 4, 60, chord.span(), 0, chord.span(), chord.span(), 1,
    );
    assert(events.len() == 3, 'neighbor 3 notes');
    assert(validate_neighbor_contour(events.span(), 67), 'neighbor contour');
}

#[test]
#[available_gas(1000000000000)]
fn test_suspension_43_interval_above_bass() {
    assert(interval_above_bass(5, 0) == 5, 'ivl 5'); // F above C — not 4-3 test
    assert(interval_above_bass(5, 1) == 4, 'ivl 4-3');
    let chord = array![0_u8, 4, 7];
    let mut events: Array<V2NoteEvent> = ArrayTrait::new();
    events.append(
        structural_event(
            koji::composition::ornamentation_v2::pitch::midi_to_pitch(69, 2), 0, 1, 0,
        ),
    );
    events.append(
        V2NoteEvent {
            pitch: koji::composition::ornamentation_v2::pitch::midi_to_pitch(69, 2),
            start: 1,
            duration: 1,
            velocity: 90,
            role: ROLE_SUSPENSION,
            ornament_id: 1,
            voice_index: 0,
        },
    );
    events.append(
        structural_event(
            koji::composition::ornamentation_v2::pitch::midi_to_pitch(67, 1), 2, 1, 0,
        ),
    );
    assert(validate_suspension_resolution(events.span(), 0, chord.span(), false), 'susp 43');
}

#[test]
#[available_gas(1000000000000)]
fn test_retardation_resolves_up() {
    let mut events: Array<V2NoteEvent> = ArrayTrait::new();
    events.append(structural_event(koji::composition::ornamentation_v2::pitch::midi_to_pitch(67, 1), 0, 1, 0));
    events.append(
        V2NoteEvent {
            pitch: koji::composition::ornamentation_v2::pitch::midi_to_pitch(67, 1),
            start: 1,
            duration: 1,
            velocity: 90,
            role: ROLE_SUSPENSION,
            ornament_id: 1,
            voice_index: 0,
        },
    );
    events.append(structural_event(koji::composition::ornamentation_v2::pitch::midi_to_pitch(69, 2), 2, 1, 0));
    assert(validate_retardation_resolution(events.span()), 'retardation up');
}

#[test]
#[available_gas(1000000000000)]
fn test_seed_threading_advances() {
    let s0: u32 = 7;
    let s1 = advance_seed(s0);
    let s2 = advance_seed(s1);
    assert(s0 != s1, 'seed advances 1');
    assert(s1 != s2, 'seed advances 2');
    let items = array![1_u8, 2_u8, 3_u8];
    let (v1, ns1) = deterministic_choice_u8(items.span(), s0);
    let (v2, ns2) = deterministic_choice_u8(items.span(), ns1);
    assert(ns1 != s0, 'choice advances');
    assert(ns2 != ns1, 'choice advances again');
}

#[test]
#[available_gas(1000000000000)]
fn test_ornament_phrase_deterministic() {
    let (phrase, degrees) = test_phrase_c_major();
    let harmony = test_harmony_c_major();
    let enabled = minimal_viable_ornaments();
    let mut cfg = default_config(42);
    cfg.style = profile_modal_canon();
    let r1 = ornament_phrase(
        phrase.span(), harmony.span(), cfg, enabled.span(), degrees.span(), 60, 0,
    );
    let r2 = ornament_phrase(
        phrase.span(), harmony.span(), cfg, enabled.span(), degrees.span(), 60, 0,
    );
    assert(r1.events.len() == r2.events.len(), 'same event count');
    assert(r1.final_seed_state == r2.final_seed_state, 'same final seed');
}

#[test]
#[available_gas(1000000000000)]
fn test_trill_upper_has_alternation() {
    let ctx = OrnamentContext {
        anchor_index: 0,
        metric_position: 0,
        beat_strength: 80,
        available_duration: 8,
        subdivision: 2,
        scale_len: 7,
        voice_index: 0,
        canon_voice_index: 0,
        seed_state: 7,
        mode_id: 0,
        key_pc: 0,
        has_prev_anchor: false,
        has_next_anchor: true,
        has_current_harmony: false,
        has_prev_harmony: false,
        has_next_harmony: false,
        has_applied_transform: false,
        has_tile: false,
        sounding_voice_count: 0,
    };
    let chord = array![0_u8, 4, 7];
    let events = ornament_generate(
        ORN_TRILL_UPPER, ctx, 4, 2, 7, 0, 8, 60, chord.span(), 0, chord.span(), chord.span(), 1,
    );
    assert(events.len() >= 3, 'trill has notes');
    let e0 = *events.at(0);
    let e1 = *events.at(1);
    assert(e0.pitch.midi != e1.pitch.midi, 'trill alternates');
}

#[test]
#[available_gas(1000000000000)]
fn test_ornament_canon_canon_first() {
    let degs = array![0_i32, 2, 4, 3, 0, 2];
    let canon = build_canon_for_test(0, 'fifth_above', array![0_i32, 4].span(), degs.span(), 0);
    let harmony = test_harmony_c_major();
    let enabled = minimal_viable_ornaments();
    let mut cfg = default_config(99);
    cfg.canon_workflow = WORKFLOW_CANON_FIRST;
    let result = ornament_canon(@canon, harmony.span(), cfg, enabled.span());
    assert(result.voices.len() >= 2, 'has voices');
    assert(result.events.len() >= canon.leader_degrees.len(), 'has events');
}

#[test]
#[available_gas(1000000000000)]
fn test_rule_mode_expand_equivalence() {
    let ctx = OrnamentContext {
        anchor_index: 1,
        metric_position: 4,
        beat_strength: 80,
        available_duration: 4,
        subdivision: 1,
        scale_len: 7,
        voice_index: 0,
        canon_voice_index: 0,
        seed_state: 7,
        mode_id: 0,
        key_pc: 0,
        has_prev_anchor: true,
        has_next_anchor: true,
        has_current_harmony: false,
        has_prev_harmony: false,
        has_next_harmony: false,
        has_applied_transform: false,
        has_tile: false,
        sounding_voice_count: 0,
    };
    let chord = array![0_u8, 4, 7];
    let expanded = ornament_generate(
        ORN_PASSING_ASC, ctx, 2, 0, 4, 4, 4, 60, chord.span(), 0, chord.span(), chord.span(), 1,
    );
    let rule = encode_ornament_event(ORN_PASSING_ASC, 1, 0, 0, 0);
    let rules = array![rule];
    let degrees = array![0_i32, 2, 4, 7];
    let starts = array![0_u32, 4_u32, 8_u32, 12_u32];
    let durs = array![4_u32, 4_u32, 4_u32, 4_u32];
    assert(
        rule_mode_matches_expanded(
            rules.span(),
            expanded.span(),
            ctx,
            degrees.span(),
            starts.span(),
            durs.span(),
            60,
            chord.span(),
            0,
            chord.span(),
            chord.span(),
        ),
        'rule expand eq',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_all_durations_positive() {
    let (phrase, degrees) = test_phrase_c_major();
    let harmony = test_harmony_c_major();
    let enabled = all_enabled_ornaments();
    let cfg = default_config(77);
    let result = ornament_phrase(
        phrase.span(), harmony.span(), cfg, enabled.span(), degrees.span(), 60, 0,
    );
    let scale = koji::composition::ornamentation_v2::pitch::mode_scale_pcs(0, 0);
    assert(
        validate_melodic_local(result.events.span(), 4, false, scale.span(), false, 24),
        'durations positive',
    );
}

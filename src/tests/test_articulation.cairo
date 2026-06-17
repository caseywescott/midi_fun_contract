use core::array::ArrayTrait;
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::transform::{assemble, MusicalObject};
use koji::composition::articulation::{
    ART_NORMAL, ART_STACCATO, ART_TENUTO, ART_ACCENT, ART_SFORZANDO, ART_PORTATO, ART_MAX,
    ArticulationPlan, articulation_duration, articulation_velocity, apply_articulation_plan,
    apply_articulation_per_voice, assemble_articulated, articulation_pattern_for_profile,
    articulation_pattern_from_seed, plan_for_profile, plan_uniform_normal, plan_uniform_staccato,
    plan_uniform_tenuto, plan_uniform_portato, plan_accent_every_n, strong_beat_accent_plan,
    staccato_long_notes, normal_is_identity, staccato_reduces_duration, accent_raises_velocity,
    velocity_ceiling_respected, articulation_output_valid,
};

fn make_event(time: u32, duration: u32, pitch: u8, velocity: u8) -> NoteEvent {
    NoteEvent { time, duration, pitch, velocity, voice_id: 0 }
}

fn make_event_v(time: u32, duration: u32, pitch: u8, velocity: u8, voice_id: u32) -> NoteEvent {
    NoteEvent { time, duration, pitch, velocity, voice_id }
}

// ──────────────────────────────────────────────────────────
// Validator smoke tests
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_normal_is_identity() {
    assert(normal_is_identity(), 'NORMAL must be identity');
}

#[test]
#[available_gas(1000000000000)]
fn test_staccato_reduces_duration() {
    assert(staccato_reduces_duration(), 'STACCATO must reduce dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_accent_raises_velocity() {
    assert(accent_raises_velocity(), 'ACCENT must raise vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_ceiling_respected() {
    assert(velocity_ceiling_respected(), 'ceiling must be respected');
}

// ──────────────────────────────────────────────────────────
// articulation_duration
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_duration_normal_unchanged() {
    assert(articulation_duration(480, ART_NORMAL, 1) == 480, 'NORMAL changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_tenuto_unchanged() {
    assert(articulation_duration(480, ART_TENUTO, 1) == 480, 'TENUTO changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_half() {
    assert(articulation_duration(480, ART_STACCATO, 1) == 240, 'STACCATO not half');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_portato_three_quarters() {
    assert(articulation_duration(480, ART_PORTATO, 1) == 360, 'PORTATO not 3/4');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_odd_length() {
    // 481 / 2 = 240 (integer division)
    assert(articulation_duration(481, ART_STACCATO, 1) == 240, 'STACCATO odd floor');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_min_clamp() {
    // written=480, staccato → 240, but min_duration=300 clamps to 300
    assert(articulation_duration(480, ART_STACCATO, 300) == 300, 'min clamp failed');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_portato_min_clamp() {
    // written=4, portato → 3, min_duration=4 → clamped to 4
    assert(articulation_duration(4, ART_PORTATO, 4) == 4, 'portato min clamp');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_staccato_tiny_input() {
    // written=1, staccato guard: 1 < 2 → returns 1 (min guard inside fn)
    assert(articulation_duration(1, ART_STACCATO, 1) == 1, 'tiny staccato guard');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_accent_unchanged() {
    // ART_ACCENT only changes velocity, not duration
    assert(articulation_duration(480, ART_ACCENT, 1) == 480, 'ACCENT changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_sforzando_unchanged() {
    assert(articulation_duration(480, ART_SFORZANDO, 1) == 480, 'SFZ changes dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_duration_unknown_code_falls_through() {
    // Codes above ART_MAX are handled in apply_articulation_plan (normalized to NORMAL);
    // articulation_duration itself just falls through to written duration.
    assert(articulation_duration(200, 99, 1) == 200, 'unknown code fallthrough');
}

// ──────────────────────────────────────────────────────────
// articulation_velocity
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_velocity_normal_unchanged() {
    assert(articulation_velocity(80, ART_NORMAL, 127) == 80, 'NORMAL changes vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_tenuto_unchanged() {
    assert(articulation_velocity(80, ART_TENUTO, 127) == 80, 'TENUTO changes vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_accent_plus20() {
    assert(articulation_velocity(60, ART_ACCENT, 127) == 80, 'ACCENT not +20');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_sforzando_plus40() {
    assert(articulation_velocity(60, ART_SFORZANDO, 127) == 100, 'SFZ not +40');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_accent_ceiling_clamp() {
    // 120 + 20 = 140 > ceiling 127 → clamped to 127
    assert(articulation_velocity(120, ART_ACCENT, 127) == 127, 'accent ceiling');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_sforzando_ceiling_custom() {
    // 100 + 40 = 140 > ceiling 110 → clamped to 110
    assert(articulation_velocity(100, ART_SFORZANDO, 110) == 110, 'sfz custom ceiling');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_ceiling_zero_defaults_127() {
    // ceiling=0 is treated as 127
    assert(articulation_velocity(60, ART_ACCENT, 0) == 80, 'ceiling 0 default');
}

#[test]
#[available_gas(1000000000000)]
fn test_velocity_staccato_unchanged() {
    // ART_STACCATO only changes duration, not velocity
    assert(articulation_velocity(80, ART_STACCATO, 127) == 80, 'STACCATO changes vel');
}

// ──────────────────────────────────────────────────────────
// apply_articulation_plan
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_plan_normal_event_count_preserved() {
    let events = array![
        make_event(0, 480, 60, 80),
        make_event(480, 480, 62, 80),
        make_event(960, 480, 64, 80),
    ];
    let plan = plan_uniform_normal();
    let out = apply_articulation_plan(events.span(), @plan);
    assert(out.len() == 3, 'count changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_normal_events_unchanged() {
    let events = array![make_event(0, 480, 60, 80), make_event(480, 240, 62, 90)];
    let plan = plan_uniform_normal();
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).duration == 480, 'normal dur 0 changed');
    assert(*out.at(0).velocity == 80, 'normal vel 0 changed');
    assert(*out.at(1).duration == 240, 'normal dur 1 changed');
    assert(*out.at(1).velocity == 90, 'normal vel 1 changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_staccato_halves_duration() {
    let events = array![make_event(0, 480, 60, 80), make_event(480, 480, 62, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).duration == 240, 'staccato dur 0');
    assert(*out.at(1).duration == 240, 'staccato dur 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_staccato_velocity_unchanged() {
    let events = array![make_event(0, 480, 60, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).velocity == 80, 'staccato vel changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_accent_raises_velocity() {
    let events = array![make_event(0, 480, 60, 60)];
    let plan = ArticulationPlan { pattern: array![ART_ACCENT], velocity_ceiling: 127, min_duration: 1 };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).velocity == 80, 'accent vel wrong');
    assert(*out.at(0).duration == 480, 'accent dur changed');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_tenuto_unchanged() {
    let events = array![make_event(0, 480, 60, 80)];
    let plan = plan_uniform_tenuto();
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).duration == 480, 'tenuto dur wrong');
    assert(*out.at(0).velocity == 80, 'tenuto vel wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_empty_pattern_is_normal() {
    let events = array![make_event(0, 480, 60, 80), make_event(480, 360, 62, 70)];
    let plan = ArticulationPlan { pattern: array![], velocity_ceiling: 127, min_duration: 1 };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).duration == 480, 'empty pat dur 0');
    assert(*out.at(1).duration == 360, 'empty pat dur 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_pattern_cycles() {
    // pattern [ACCENT, NORMAL] over 4 events: idx 0,2 → accent; idx 1,3 → normal
    let v: u8 = 60;
    let events = array![
        make_event(0, 480, 60, v),
        make_event(480, 480, 62, v),
        make_event(960, 480, 64, v),
        make_event(1440, 480, 65, v),
    ];
    let plan = ArticulationPlan {
        pattern: array![ART_ACCENT, ART_NORMAL], velocity_ceiling: 127, min_duration: 1,
    };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).velocity == 80, 'cycle idx0 accent');
    assert(*out.at(1).velocity == 60, 'cycle idx1 normal');
    assert(*out.at(2).velocity == 80, 'cycle idx2 accent');
    assert(*out.at(3).velocity == 60, 'cycle idx3 normal');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_unknown_code_treated_as_normal() {
    // code 99 > ART_MAX → normalized to ART_NORMAL
    let events = array![make_event(0, 480, 60, 80)];
    let plan = ArticulationPlan { pattern: array![99_u8], velocity_ceiling: 127, min_duration: 1 };
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).duration == 480, 'unknown code dur');
    assert(*out.at(0).velocity == 80, 'unknown code vel');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_time_passthrough() {
    // time field must not be altered
    let events = array![make_event(777, 480, 60, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).time == 777, 'time mutated');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_pitch_passthrough() {
    let events = array![make_event(0, 480, 64, 80)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).pitch == 64, 'pitch mutated');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_voice_id_passthrough() {
    let events = array![make_event_v(0, 480, 60, 80, 3)];
    let plan = plan_uniform_staccato(127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).voice_id == 3, 'voice_id mutated');
}

// ──────────────────────────────────────────────────────────
// plan_accent_every_n
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_accent_every_2() {
    let plan = plan_accent_every_n(2, 127);
    let events = array![
        make_event(0, 480, 60, 60),
        make_event(480, 480, 62, 60),
        make_event(960, 480, 64, 60),
        make_event(1440, 480, 65, 60),
    ];
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).velocity == 80, 'every2 idx0 accent');
    assert(*out.at(1).velocity == 60, 'every2 idx1 normal');
    assert(*out.at(2).velocity == 80, 'every2 idx2 accent');
    assert(*out.at(3).velocity == 60, 'every2 idx3 normal');
}

#[test]
#[available_gas(1000000000000)]
fn test_accent_every_3() {
    let plan = plan_accent_every_n(3, 127);
    let events = array![
        make_event(0, 480, 60, 60),
        make_event(480, 480, 62, 60),
        make_event(960, 480, 64, 60),
    ];
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).velocity == 80, 'every3 idx0 accent');
    assert(*out.at(1).velocity == 60, 'every3 idx1 normal');
    assert(*out.at(2).velocity == 60, 'every3 idx2 normal');
}

// ──────────────────────────────────────────────────────────
// Convenience constructors — structure checks
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_plan_uniform_normal_code() {
    let plan = plan_uniform_normal();
    assert(plan.pattern.len() == 1, 'normal plan len');
    assert(*plan.pattern.at(0) == ART_NORMAL, 'normal plan code');
    assert(plan.velocity_ceiling == 127, 'normal ceiling');
    assert(plan.min_duration == 1, 'normal min_dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_uniform_staccato_code() {
    let plan = plan_uniform_staccato(110, 4);
    assert(*plan.pattern.at(0) == ART_STACCATO, 'staccato code');
    assert(plan.velocity_ceiling == 110, 'staccato ceiling');
    assert(plan.min_duration == 4, 'staccato min_dur');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_uniform_tenuto_code() {
    let plan = plan_uniform_tenuto();
    assert(*plan.pattern.at(0) == ART_TENUTO, 'tenuto code');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_uniform_portato_code() {
    let plan = plan_uniform_portato(120);
    assert(*plan.pattern.at(0) == ART_PORTATO, 'portato code');
    assert(plan.velocity_ceiling == 120, 'portato ceiling');
}

// ──────────────────────────────────────────────────────────
// Profile patterns
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_profile_0_renaissance_tenuto() {
    let p = articulation_pattern_for_profile(0);
    assert(p.len() == 4, 'ren len');
    assert(*p.at(0) == ART_TENUTO, 'ren[0] tenuto');
    assert(*p.at(3) == ART_TENUTO, 'ren[3] tenuto');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_1_jazz_offbeat_accent() {
    let p = articulation_pattern_for_profile(1);
    // [NORMAL, ACCENT, NORMAL, ACCENT]
    assert(*p.at(0) == ART_NORMAL, 'jazz[0] normal');
    assert(*p.at(1) == ART_ACCENT, 'jazz[1] accent');
    assert(*p.at(3) == ART_ACCENT, 'jazz[3] accent');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_5_ligeti_staccato() {
    let p = articulation_pattern_for_profile(5);
    assert(*p.at(0) == ART_STACCATO, 'ligeti5[0] staccato');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_6_ligeti_staccato() {
    let p = articulation_pattern_for_profile(6);
    assert(*p.at(0) == ART_STACCATO, 'ligeti6[0] staccato');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_10_octatonic_alternating() {
    let p = articulation_pattern_for_profile(10);
    assert(*p.at(0) == ART_STACCATO, 'oct[0] staccato');
    assert(*p.at(1) == ART_NORMAL, 'oct[1] normal');
    assert(*p.at(2) == ART_STACCATO, 'oct[2] staccato');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_14_bartok_accent_portato() {
    let p = articulation_pattern_for_profile(14);
    assert(*p.at(0) == ART_ACCENT, 'bartok[0] accent');
    assert(*p.at(1) == ART_PORTATO, 'bartok[1] portato');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_19_phrygian_first_accent() {
    let p = articulation_pattern_for_profile(19);
    assert(*p.at(0) == ART_ACCENT, 'phryg[0] accent');
    assert(*p.at(1) == ART_NORMAL, 'phryg[1] normal');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_22_penta_smooth_portato() {
    let p = articulation_pattern_for_profile(22);
    assert(*p.at(0) == ART_PORTATO, 'penta[0] portato');
}

#[test]
#[available_gas(1000000000000)]
fn test_profile_unknown_is_normal() {
    let p = articulation_pattern_for_profile(99);
    assert(*p.at(0) == ART_NORMAL, 'unknown[0] normal');
}

#[test]
#[available_gas(1000000000000)]
fn test_plan_for_profile_defaults() {
    let plan = plan_for_profile(0);
    assert(plan.velocity_ceiling == 120, 'profile ceiling');
    assert(plan.min_duration == 1, 'profile min_dur');
    assert(*plan.pattern.at(0) == ART_TENUTO, 'profile[0] code');
}

// ──────────────────────────────────────────────────────────
// Seed-driven patterns
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_seed_pattern_empty_length() {
    let p = articulation_pattern_from_seed(12345, 0, 0);
    assert(p.len() == 0, 'seed empty len');
}

#[test]
#[available_gas(1000000000000)]
fn test_seed_pattern_length_4() {
    let p = articulation_pattern_from_seed(12345, 4, 0);
    assert(p.len() == 4, 'seed len 4');
}

#[test]
#[available_gas(1000000000000)]
fn test_seed_pattern_codes_in_range() {
    let p = articulation_pattern_from_seed(99999, 8, 0);
    let mut i: u32 = 0;
    loop {
        if i >= p.len() {
            break;
        }
        assert(*p.at(i) <= ART_MAX, 'code out of range');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_seed_pattern_high_density_mostly_normal() {
    // density=7 → threshold = 7*30 = 210; most raw values < 210 → NORMAL
    let p = articulation_pattern_from_seed(0, 16, 7);
    let mut normal_count: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= p.len() {
            break;
        }
        if *p.at(i) == ART_NORMAL {
            normal_count += 1;
        }
        i += 1;
    };
    // With seed=0 and density=7 at least half should be NORMAL
    assert(normal_count >= 8, 'density=7 not mostly normal');
}

#[test]
#[available_gas(1000000000000)]
fn test_seed_pattern_deterministic() {
    let p1 = articulation_pattern_from_seed(42, 4, 3);
    let p2 = articulation_pattern_from_seed(42, 4, 3);
    let mut i: u32 = 0;
    loop {
        if i >= 4 {
            break;
        }
        assert(*p1.at(i) == *p2.at(i), 'not deterministic');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// staccato_long_notes
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_staccato_long_notes_only_long() {
    // threshold=240: note of 480 gets staccato, note of 120 stays unchanged
    let events = array![make_event(0, 480, 60, 80), make_event(480, 120, 62, 80)];
    let out = staccato_long_notes(events.span(), 240, 127);
    assert(*out.at(0).duration == 240, 'long note staccato');
    assert(*out.at(1).duration == 120, 'short note unchanged');
}

#[test]
#[available_gas(1000000000000)]
fn test_staccato_long_notes_count_preserved() {
    let events = array![make_event(0, 480, 60, 80), make_event(480, 120, 62, 80)];
    let out = staccato_long_notes(events.span(), 240, 127);
    assert(out.len() == 2, 'count changed');
}

// ──────────────────────────────────────────────────────────
// strong_beat_accent_plan
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_strong_beat_accent_bar1() {
    // time_unit=480, beats_per_bar=4, bar=1920
    // event at time=0 → 0 % 1920 == 0 → accent
    // event at time=480 → not zero → normal
    let events = array![make_event(0, 480, 60, 60), make_event(480, 480, 62, 60)];
    let plan = strong_beat_accent_plan(events.span(), 480, 4, 127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).velocity == 80, 'beat1 accent');
    assert(*out.at(1).velocity == 60, 'beat2 normal');
}

#[test]
#[available_gas(1000000000000)]
fn test_strong_beat_accent_bar2() {
    // time=1920 → 1920 % 1920 == 0 → accent (start of bar 2)
    let events = array![make_event(1920, 480, 60, 60)];
    let plan = strong_beat_accent_plan(events.span(), 480, 4, 127, 1);
    let out = apply_articulation_plan(events.span(), @plan);
    assert(*out.at(0).velocity == 80, 'bar2 beat1 accent');
}

// ──────────────────────────────────────────────────────────
// assemble_articulated
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_assemble_articulated_same_count_as_assemble() {
    let obj = MusicalObject {
        pitches: array![0_i32, 2, 4],
        lengths: array![480_u32, 480, 480],
        velocities: array![80_u8],
        articulations: array![ART_NORMAL],
        octave: 5,
    };
    let raw = assemble(@obj, 0, 60, 0);
    let art = assemble_articulated(@obj, 0, 60, 0, 127, 1);
    assert(art.len() == raw.len(), 'articulated count differs');
}

#[test]
#[available_gas(1000000000000)]
fn test_assemble_articulated_normal_matches_raw() {
    // With ART_NORMAL articulations the output should be identical to assemble
    let obj = MusicalObject {
        pitches: array![0_i32, 2],
        lengths: array![480_u32, 480],
        velocities: array![80_u8],
        articulations: array![ART_NORMAL],
        octave: 5,
    };
    let raw = assemble(@obj, 0, 60, 0);
    let art = assemble_articulated(@obj, 0, 60, 0, 127, 1);
    assert(*art.at(0).duration == *raw.at(0).duration, 'normal dur 0 differs');
    assert(*art.at(0).velocity == *raw.at(0).velocity, 'normal vel 0 differs');
}

#[test]
#[available_gas(1000000000000)]
fn test_assemble_articulated_staccato_shorter() {
    // With ART_STACCATO articulations, durations must be shorter than raw output
    let obj = MusicalObject {
        pitches: array![0_i32, 2, 4],
        lengths: array![480_u32, 480, 480],
        velocities: array![80_u8],
        articulations: array![ART_STACCATO],
        octave: 5,
    };
    let raw = assemble(@obj, 0, 60, 0);
    let art = assemble_articulated(@obj, 0, 60, 0, 127, 1);
    // Every note should be shorter (480 → 240)
    let mut i: u32 = 0;
    loop {
        if i >= raw.len() {
            break;
        }
        assert(*art.at(i).duration < *raw.at(i).duration, 'staccato not shorter');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// apply_articulation_per_voice
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_per_voice_different_plans() {
    // voice 0 → staccato, voice 1 → normal
    let events = array![
        make_event_v(0, 480, 60, 80, 0),
        make_event_v(0, 480, 67, 80, 1),
        make_event_v(480, 480, 62, 80, 0),
    ];
    let plan0 = plan_uniform_staccato(127, 1);
    let plan1 = plan_uniform_normal();
    let plans = array![plan0, plan1];
    let out = apply_articulation_per_voice(events.span(), plans.span(), 127, 1);
    assert(*out.at(0).duration == 240, 'v0 staccato');
    assert(*out.at(1).duration == 480, 'v1 normal');
    assert(*out.at(2).duration == 240, 'v0 staccato 2nd');
}

#[test]
#[available_gas(1000000000000)]
fn test_per_voice_exceeds_plans_gets_normal() {
    // voice 2 but only 2 plans (indices 0,1) → global_velocity_ceiling applies
    let events = array![make_event_v(0, 480, 60, 60, 2)];
    let plan0 = plan_uniform_staccato(127, 1);
    let plan1 = plan_uniform_staccato(127, 1);
    let plans = array![plan0, plan1];
    let out = apply_articulation_per_voice(events.span(), plans.span(), 127, 1);
    // voice 2 → ART_NORMAL (exceeds plans)
    assert(*out.at(0).duration == 480, 'overflow voice dur');
    assert(*out.at(0).velocity == 60, 'overflow voice vel');
}

// ──────────────────────────────────────────────────────────
// articulation_output_valid
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_output_valid_normal_events() {
    let events = array![
        make_event(0, 240, 60, 80),
        make_event(240, 240, 62, 80),
    ];
    assert(articulation_output_valid(events.span(), 1), 'valid events fail');
}

#[test]
#[available_gas(1000000000000)]
fn test_output_valid_rejects_zero_duration() {
    let events = array![make_event(0, 0, 60, 80)];
    // min_duration=1 → duration 0 < 1 → invalid
    assert(!articulation_output_valid(events.span(), 1), 'zero dur accepted');
}

#[test]
#[available_gas(1000000000000)]
fn test_output_valid_rejects_zero_velocity() {
    // velocity=0 is treated as invalid (floor is 1)
    let events = array![NoteEvent { time: 0, duration: 480, pitch: 60, velocity: 0, voice_id: 0 }];
    assert(!articulation_output_valid(events.span(), 1), 'zero vel accepted');
}

#[test]
#[available_gas(1000000000000)]
fn test_output_valid_rejects_over_127_velocity() {
    // velocity=128 exceeds MIDI max
    let events = array![
        NoteEvent { time: 0, duration: 480, pitch: 60, velocity: 128, voice_id: 0 },
    ];
    assert(!articulation_output_valid(events.span(), 1), 'v>127 accepted');
}

#[test]
#[available_gas(1000000000000)]
fn test_output_valid_empty_span() {
    let events: Array<NoteEvent> = array![];
    assert(articulation_output_valid(events.span(), 1), 'empty span invalid');
}

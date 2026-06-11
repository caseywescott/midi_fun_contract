use koji::composition::barry_borrowing::{BarryBorrowKind, borrow_neighbor_state};
use koji::composition::barry_elevators::{ElevatorDirection, generate_elevator_path};
use koji::composition::barry_harmonization::{
    barry_block_chord_pcs, barry_block_lower_voices_with_style, harmonization_motion_from_states,
    harmonization_motion_step, harmonize_barry_block_chords,
    harmonize_barry_block_chords_with_motion, regular_downbeat_plan, rhythmic_comping_plan,
    with_harmonization_voicing_style,
};
use koji::composition::barry_harris::{ChordFamily, contains_pc, initial_harmonic_state};
use koji::composition::barry_v2_types::BarryVoicingStyle;
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::timeline_rhythm::TimelineRhythm;

fn eight_note_melody() -> Array<NoteEvent> {
    let mut out = array![];
    let pitches = array![72_u8, 73, 74, 75, 76, 77, 78, 79];
    let mut i: u32 = 0;
    loop {
        if i >= pitches.len() {
            break;
        }
        out
            .append(
                NoteEvent {
                    time: i, duration: 1, pitch: *pitches.at(i), velocity: 96, voice_id: 0,
                },
            );
        i += 1;
    }
    out
}

#[test]
fn test_regular_downbeats_are_sparse_and_sustained() {
    let melody = eight_note_melody();
    let plan = regular_downbeat_plan(4, 0, 64, 1);
    let comp = harmonize_barry_block_chords(melody.span(), @plan);
    assert(comp.len() == 6, 'two three-note chords');
    assert(*comp.at(0).time == 0, 'first downbeat');
    assert(*comp.at(0).duration == 4, 'sustain four');
    assert(*comp.at(3).time == 4, 'second downbeat');
    assert(*comp.at(3).duration == 4, 'sustain to end');
}

#[test]
fn test_rhythmic_comping_uses_timeline_onsets() {
    let melody = eight_note_melody();
    let rhythm = TimelineRhythm {
        n: 8,
        onset_mask: 0x49_u32,
        onset_count: 3,
        family_id: 0,
        variant_id: 0,
        rotation: 0,
        preset_id: 0,
        source_kind: 2,
    };
    let plan = rhythmic_comping_plan(rhythm, 1, 0, 64, 1);
    let comp = harmonize_barry_block_chords(melody.span(), @plan);
    assert(comp.len() == 9, 'three comp hits');
    assert(*comp.at(0).time == 0, 'hit zero');
    assert(*comp.at(3).time == 3, 'hit three');
    assert(*comp.at(6).time == 6, 'hit six');
    assert(*comp.at(0).duration == 1, 'short gate');
}

#[test]
fn test_each_comp_attack_contains_sounding_melody_pitch() {
    let melody = eight_note_melody();
    let plan = regular_downbeat_plan(2, 0, 64, 1);
    let comp = harmonize_barry_block_chords(melody.span(), @plan);
    let attack_times = array![0_u32, 2, 4, 6];
    let mut i: u32 = 0;
    loop {
        if i >= attack_times.len() {
            break;
        }
        let time = *attack_times.at(i);
        let melody_pc = *melody.at(time).pitch % 12;
        let chord = barry_block_chord_pcs(0, melody_pc);
        assert(contains_pc(chord.span(), melody_pc), 'melody in chord');
        i += 1;
    }
    assert(comp.len() == 12, 'four attacks');
}

#[test]
fn test_comping_can_harmonize_a_sustained_melody_note() {
    let melody = array![NoteEvent { time: 0, duration: 4, pitch: 72, velocity: 96, voice_id: 0 }];
    let plan = regular_downbeat_plan(2, 0, 64, 1);
    let comp = harmonize_barry_block_chords(melody.span(), @plan);
    assert(comp.len() == 6, 'two attacks under held note');
    assert(*comp.at(3).time == 2, 'held note selected');
}

#[test]
fn test_drop_two_lowers_second_highest_beneath_melody() {
    let close = barry_block_lower_voices_with_style(0, 72, BarryVoicingStyle::FourWayClose);
    let drop_two = barry_block_lower_voices_with_style(0, 72, BarryVoicingStyle::DropTwo);
    assert(*close.at(2) == 69, 'close second highest');
    assert(*drop_two.at(0) == 57, 'drop two lowered octave');
    assert(*drop_two.at(1) == 64, 'third retained');
    assert(*drop_two.at(2) == 67, 'fifth retained');
}

#[test]
fn test_drop_two_plan_preserves_sparse_rhythm() {
    let melody = eight_note_melody();
    let close_plan = regular_downbeat_plan(4, 0, 64, 1);
    let drop_two_plan = with_harmonization_voicing_style(close_plan, BarryVoicingStyle::DropTwo);
    let comp = harmonize_barry_block_chords(melody.span(), @drop_two_plan);
    assert(comp.len() == 6, 'same attack count');
    assert(*comp.at(0).time == 0, 'same first attack');
    assert(*comp.at(0).duration == 4, 'same sustain');
    assert(*comp.at(0).pitch == 57, 'first chord drop two');
}

#[test]
fn test_elevator_states_become_stable_and_diminished_motion_steps() {
    let start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let elevator = generate_elevator_path(start, ElevatorDirection::Up, 3);
    let motion = harmonization_motion_from_states(elevator.span());
    assert(motion.len() == 3, 'motion len');
    assert(!*motion.at(0).diminished_phase, 'stable first');
    assert(*motion.at(1).diminished_phase, 'connector second');
    assert(!*motion.at(2).diminished_phase, 'stable third');
}

#[test]
fn test_neighbor_key_motion_preserves_sparse_attacks() {
    let melody = array![
        NoteEvent { time: 0, duration: 2, pitch: 64, velocity: 96, voice_id: 0 },
        NoteEvent { time: 2, duration: 2, pitch: 65, velocity: 96, voice_id: 0 },
    ];
    let base = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let borrowed = borrow_neighbor_state(
        initial_harmonic_state(0, ChordFamily::Major6Dim), BarryBorrowKind::BorrowUpperNeighbor, 2,
    );
    let motion = array![
        harmonization_motion_step(@base), harmonization_motion_step(@borrowed.harmonic_state),
    ];
    let plan = regular_downbeat_plan(2, 0, 64, 1);
    let comp = harmonize_barry_block_chords_with_motion(melody.span(), @plan, motion.span());
    assert(comp.len() == 6, 'two sparse attacks');
    assert(*comp.at(0).time == 0, 'base attack');
    assert(*comp.at(3).time == 2, 'neighbor attack');
    assert(*comp.at(0).pitch == 60, 'base tonic present');
    assert(*comp.at(3).pitch == 61, 'neighbor tonic present');
}

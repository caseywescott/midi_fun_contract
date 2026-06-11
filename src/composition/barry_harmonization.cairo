//! Sparse Barry Harris block-chord harmonization.
//!
//! Harmony attacks are scheduled by the existing `TimelineRhythm` layer. At each
//! selected onset, the highest sounding melody note becomes the top of a Barry
//! block chord; only the lower voices are emitted.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_elevators::is_stable_state;
use koji::composition::barry_harris::{
    ChordFamily, HarmonicState, contains_pc, diminished_connector_tones, initial_harmonic_state,
    stable_chord_tones_for,
};
use koji::composition::barry_v2_types::BarryVoicingStyle;
use koji::composition::barry_voicing_styles::apply_drop_two;
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::timeline_rhythm::{
    NO_PRESET, SOURCE_INTERVAL_VARIANT, TimelineRhythm, timeline_gate, validate_timeline_mask,
};

#[derive(Copy, Drop, PartialEq)]
pub enum BarryChordDurationMode {
    FixedGate,
    UntilNextCompOnset,
}

#[derive(Copy, Drop)]
pub struct BarryHarmonizationPlan {
    pub rhythm: TimelineRhythm,
    pub duration_mode: BarryChordDurationMode,
    pub gate_steps: u32,
    pub tonic_pc: u8,
    pub velocity: u8,
    pub first_voice_id: u32,
    pub voicing_style: BarryVoicingStyle,
}

/// One harmonic color used at a sparse harmony attack.
///
/// Elevator states map their stable/diminished phase into `diminished_phase`;
/// borrowed states carry their local tonic and family into the same structure.
#[derive(Copy, Drop)]
pub struct BarryHarmonicMotionStep {
    pub tonic_pc: u8,
    pub family: ChordFamily,
    pub diminished_phase: bool,
}

fn is_diminished_motion_state(state: @HarmonicState) -> bool {
    let connector = diminished_connector_tones(state);
    if state.active_pcs.len() != connector.len() {
        return false;
    }
    let mut i: usize = 0;
    loop {
        if i >= connector.len() {
            break;
        }
        if !contains_pc(state.active_pcs.span(), *connector.at(i)) {
            return false;
        }
        i += 1;
    }
    true
}

pub fn harmonization_motion_step(state: @HarmonicState) -> BarryHarmonicMotionStep {
    BarryHarmonicMotionStep {
        tonic_pc: *state.tonic_pc,
        family: *state.family,
        diminished_phase: !is_stable_state(state) && is_diminished_motion_state(state),
    }
}

pub fn harmonization_motion_from_states(
    states: Span<HarmonicState>,
) -> Array<BarryHarmonicMotionStep> {
    let mut out: Array<BarryHarmonicMotionStep> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= states.len() {
            break;
        }
        out.append(harmonization_motion_step(states.at(i)));
        i += 1;
    }
    out
}

/// Sustained chords on a regular pulse. A period of 4 means beats 0, 4, 8, ...
pub fn regular_downbeat_plan(
    period_steps: u32, tonic_pc: u8, velocity: u8, first_voice_id: u32,
) -> BarryHarmonizationPlan {
    BarryHarmonizationPlan {
        rhythm: TimelineRhythm {
            n: period_steps,
            onset_mask: 1,
            onset_count: 1,
            family_id: 0,
            variant_id: 0,
            rotation: 0,
            preset_id: NO_PRESET,
            source_kind: SOURCE_INTERVAL_VARIANT,
        },
        duration_mode: BarryChordDurationMode::UntilNextCompOnset,
        gate_steps: period_steps,
        tonic_pc,
        velocity,
        first_voice_id,
        voicing_style: BarryVoicingStyle::FourWayClose,
    }
}

/// Short chord hits scheduled by any existing timeline rhythm.
pub fn rhythmic_comping_plan(
    rhythm: TimelineRhythm, gate_steps: u32, tonic_pc: u8, velocity: u8, first_voice_id: u32,
) -> BarryHarmonizationPlan {
    BarryHarmonizationPlan {
        rhythm,
        duration_mode: BarryChordDurationMode::FixedGate,
        gate_steps,
        tonic_pc,
        velocity,
        first_voice_id,
        voicing_style: BarryVoicingStyle::FourWayClose,
    }
}

pub fn with_harmonization_voicing_style(
    plan: BarryHarmonizationPlan, voicing_style: BarryVoicingStyle,
) -> BarryHarmonizationPlan {
    BarryHarmonizationPlan { voicing_style, ..plan }
}

pub fn valid_harmonization_plan(plan: @BarryHarmonizationPlan) -> bool {
    let rhythm = *plan.rhythm;
    validate_timeline_mask(rhythm.n, rhythm.onset_count, rhythm.onset_mask)
        && *plan.gate_steps > 0
        && *plan.tonic_pc < 12
}

/// Pitch classes for the block chord whose top note is `melody_pc`.
///
/// Stable tones use the tonic major-sixth chord. Other tones use the
/// diminished-seventh chord that contains the melody note.
pub fn barry_block_chord_pcs(tonic_pc: u8, melody_pc: u8) -> Array<u8> {
    barry_block_chord_pcs_for_motion(
        BarryHarmonicMotionStep {
            tonic_pc, family: ChordFamily::Major6Dim, diminished_phase: false,
        },
        melody_pc,
    )
}

/// Reconcile a harmonic-motion color with a melody top note.
///
/// Stable/elevator-connector chords are retained when they contain the melody.
/// Otherwise the melody's own diminished seventh chord is used, preserving the
/// existing guarantee that every sparse harmony attack contains its top note.
pub fn barry_block_chord_pcs_for_motion(
    motion: BarryHarmonicMotionStep, melody_pc: u8,
) -> Array<u8> {
    let local = if motion.diminished_phase {
        let state = initial_harmonic_state(motion.tonic_pc, motion.family);
        diminished_connector_tones(@state)
    } else {
        stable_chord_tones_for(motion.tonic_pc, motion.family)
    };
    if contains_pc(local.span(), melody_pc % 12) {
        return local;
    }
    let base = melody_pc % 3;
    array![base, base + 3, base + 6, base + 9]
}

fn nearest_below(pc: u8, ceiling: i16) -> i16 {
    let mut keynum: i16 = pc.into();
    loop {
        if keynum <= ceiling {
            break;
        }
        keynum -= 12;
    }
    loop {
        if keynum + 12 > ceiling {
            break;
        }
        keynum += 12;
    }
    keynum
}

/// Lower voices for a Barry block chord beneath `melody_pitch`.
pub fn barry_block_lower_voices(tonic_pc: u8, melody_pitch: u8) -> Array<i16> {
    let chord = barry_block_chord_pcs(tonic_pc, melody_pitch % 12);
    lower_voices_for_chord(chord.span(), melody_pitch)
}

fn lower_voices_for_chord(chord: Span<u8>, melody_pitch: u8) -> Array<i16> {
    let melody_pc = melody_pitch % 12;
    let melody_keynum: i16 = melody_pitch.into();
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= chord.len() {
            break;
        }
        let pc = *chord.at(i);
        if pc != melody_pc {
            out.append(nearest_below(pc, melody_keynum - 1));
        }
        i += 1;
    }
    out
}

fn apply_harmonization_voicing_style(
    close: Array<i16>, melody_pitch: u8, voicing_style: BarryVoicingStyle,
) -> Array<i16> {
    if voicing_style != BarryVoicingStyle::DropTwo {
        return close;
    }

    let melody_keynum: i16 = melody_pitch.into();
    let mut full = close;
    full.append(melody_keynum);

    let dropped = apply_drop_two(full.span());
    let mut lower: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= dropped.len() {
            break;
        }
        let pitch = *dropped.at(i);
        if pitch != melody_keynum {
            lower.append(pitch);
        }
        i += 1;
    }
    lower
}

/// Lower voices with the selected sparse-harmonization voicing treatment.
///
/// Drop two operates on the complete four-note block, then removes the unchanged
/// melody top note so callers can continue rendering the leader separately.
pub fn barry_block_lower_voices_with_style(
    tonic_pc: u8, melody_pitch: u8, voicing_style: BarryVoicingStyle,
) -> Array<i16> {
    let close = barry_block_lower_voices(tonic_pc, melody_pitch);
    apply_harmonization_voicing_style(close, melody_pitch, voicing_style)
}

pub fn barry_block_lower_voices_for_motion(
    motion: BarryHarmonicMotionStep, melody_pitch: u8, voicing_style: BarryVoicingStyle,
) -> Array<i16> {
    let chord = barry_block_chord_pcs_for_motion(motion, melody_pitch % 12);
    let close = lower_voices_for_chord(chord.span(), melody_pitch);
    apply_harmonization_voicing_style(close, melody_pitch, voicing_style)
}

fn melody_end(melody: Span<NoteEvent>) -> u32 {
    let mut end: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= melody.len() {
            break;
        }
        let event = melody.at(i);
        let event_end = *event.time + *event.duration;
        if event_end > end {
            end = event_end;
        }
        i += 1;
    }
    end
}

/// Highest melody pitch sounding at `time`.
fn melody_pitch_at(melody: Span<NoteEvent>, time: u32) -> Option<u8> {
    let mut found = false;
    let mut highest: u8 = 0;
    let mut i: usize = 0;
    loop {
        if i >= melody.len() {
            break;
        }
        let event = melody.at(i);
        if *event.time <= time && time < *event.time
            + *event.duration && (!found || *event.pitch > highest) {
            highest = *event.pitch;
            found = true;
        }
        i += 1;
    }
    if found {
        Option::Some(highest)
    } else {
        Option::None
    }
}

fn steps_to_next_comp_onset(rhythm: @TimelineRhythm, time: u32) -> u32 {
    let mut distance: u32 = 1;
    loop {
        if distance > *rhythm.n {
            break;
        }
        if timeline_gate(rhythm, time + distance) {
            return distance;
        }
        distance += 1;
    }
    0
}

fn chord_duration(plan: @BarryHarmonizationPlan, time: u32, end: u32) -> u32 {
    let rhythm = *plan.rhythm;
    let until_next = steps_to_next_comp_onset(@rhythm, time);
    let requested = match plan.duration_mode {
        BarryChordDurationMode::FixedGate => {
            if *plan.gate_steps < until_next {
                *plan.gate_steps
            } else {
                until_next
            }
        },
        BarryChordDurationMode::UntilNextCompOnset => until_next,
    };
    let remaining = end - time;
    if requested < remaining {
        requested
    } else {
        remaining
    }
}

/// Harmonize a melody sparsely according to `plan`.
///
/// The melody may contain rests or sustained notes. At each comping onset, the
/// highest sounding melody pitch is used; if no melody note sounds, no chord is
/// emitted.
pub fn harmonize_barry_block_chords(
    melody: Span<NoteEvent>, plan: @BarryHarmonizationPlan,
) -> Array<NoteEvent> {
    let motion = array![
        BarryHarmonicMotionStep {
            tonic_pc: *plan.tonic_pc, family: ChordFamily::Major6Dim, diminished_phase: false,
        },
    ];
    harmonize_barry_block_chords_with_motion(melody, plan, motion.span())
}

/// Harmonize sparsely while cycling through elevator/borrowing-derived colors.
pub fn harmonize_barry_block_chords_with_motion(
    melody: Span<NoteEvent>, plan: @BarryHarmonizationPlan, motion: Span<BarryHarmonicMotionStep>,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    if melody.len() == 0 || motion.len() == 0 || !valid_harmonization_plan(plan) {
        return out;
    }
    let rhythm = *plan.rhythm;
    let end = melody_end(melody);
    let mut time: u32 = 0;
    let mut motion_i: usize = 0;
    loop {
        if time >= end {
            break;
        }
        if timeline_gate(@rhythm, time) {
            match melody_pitch_at(melody, time) {
                Option::Some(melody_pitch) => {
                    let duration = chord_duration(plan, time, end);
                    let lower = barry_block_lower_voices_for_motion(
                        *motion.at(motion_i), melody_pitch, *plan.voicing_style,
                    );
                    let mut voice: usize = 0;
                    loop {
                        if voice >= lower.len() {
                            break;
                        }
                        let pitch = *lower.at(voice);
                        if pitch >= 0 && pitch <= 127 && duration > 0 {
                            out
                                .append(
                                    NoteEvent {
                                        time,
                                        duration,
                                        pitch: pitch.try_into().unwrap(),
                                        velocity: *plan.velocity,
                                        voice_id: *plan.first_voice_id + voice.try_into().unwrap(),
                                    },
                                );
                        }
                        voice += 1;
                    }
                    motion_i = (motion_i + 1) % motion.len();
                },
                Option::None => {},
            }
        }
        time += 1;
    }
    out
}

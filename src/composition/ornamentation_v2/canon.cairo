//! Canon port adapter — wires existing canon code into v2 (§8).

use core::array::ArrayTrait;
use koji::composition::melodic_canon::{
    canon_to_note_events, MelodicCanon, NoteEvent, realize_degree,
};
use koji::composition::ornamentation_v2::pitch::midi_to_pitch;
use koji::composition::ornamentation_v2::types::pitch_from_midi;
use koji::composition::ornamentation_v2::types::{
    AppliedTransform, PITCH_MAP_IDENTITY, PITCH_MAP_TRANSPOSE, V2NoteEvent, V2Voice,
};

pub fn describe_transform_for_voice(canon: @MelodicCanon, voice_index: u32) -> AppliedTransform {
    let voices = *canon.voices;
    let mut i: u32 = 0;
    let mut offset: i32 = 0;
    let mut entry: u32 = 0;
    let mut dilation: u32 = 1;
    loop {
        if i >= voices.len() {
            break;
        }
        let v = *voices.at(i);
        if v.voice_id == voice_index {
            offset = v.offset;
            entry = v.entry;
            dilation = v.dilation;
            break;
        }
        i += 1;
    };
    let pitch_map = if offset == 0 && entry == 0 {
        PITCH_MAP_IDENTITY
    } else {
        PITCH_MAP_TRANSPOSE
    };
    AppliedTransform {
        delay: entry * *canon.time_unit,
        pitch_map,
        transpose_in_pc_space: *canon.octave == 12,
        inversion_axis_pc: *canon.tonic_keynum % 12,
        rhythmic_num: dilation,
        rhythmic_den: 1,
    }
}

pub fn legacy_note_to_v2(e: NoteEvent) -> V2NoteEvent {
    V2NoteEvent {
        pitch: pitch_from_midi(e.pitch),
        start: e.time,
        duration: e.duration,
        velocity: e.velocity,
        role: 0,
        ornament_id: 0,
        voice_index: e.voice_id,
    }
}

pub fn v2_note_to_legacy(e: V2NoteEvent) -> NoteEvent {
    NoteEvent {
        time: e.start,
        duration: e.duration,
        pitch: e.pitch.midi,
        velocity: e.velocity,
        voice_id: e.voice_index,
    }
}

pub fn derive_voices_from_canon(canon: @MelodicCanon) -> Array<V2Voice> {
    let voices = *canon.voices;
    let mut out: Array<V2Voice> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= voices.len() {
            break;
        }
        let v = *voices.at(i);
        out.append(
            V2Voice {
                voice_index: v.voice_id,
                applied: describe_transform_for_voice(canon, v.voice_id),
            },
        );
        i += 1;
    };
    out
}

pub fn derive_structural_events(canon: @MelodicCanon) -> Array<V2NoteEvent> {
    let legacy = canon_to_note_events(canon);
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= legacy.len() {
            break;
        }
        out.append(legacy_note_to_v2(*legacy.at(i)));
        i += 1;
    };
    out
}

pub fn degrees_from_canon(canon: @MelodicCanon, voice_index: u32) -> Array<i32> {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    let mut offset: i32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= voices.len() {
            break;
        }
        let v = *voices.at(i);
        if v.voice_id == voice_index {
            offset = v.offset;
            break;
        }
        i += 1;
    };
    let mut out: Array<i32> = ArrayTrait::new();
    i = 0;
    loop {
        if i >= degs.len() {
            break;
        }
        out.append(*degs.at(i) + offset);
        i += 1;
    };
    out
}

pub fn structural_phrase_for_voice(
    canon: @MelodicCanon, voice_index: u32,
) -> Array<V2NoteEvent> {
    let degs = degrees_from_canon(canon, voice_index);
    let unit = *canon.time_unit;
    let tonic = *canon.tonic_keynum;
    let mode = *canon.mode_id;
    let octave = *canon.octave;
    let mut entry: u32 = 0;
    let voices = *canon.voices;
    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let v = *voices.at(vi);
        if v.voice_id == voice_index {
            entry = v.entry;
            break;
        }
        vi += 1;
    };
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= degs.len() {
            break;
        }
        let deg = *degs.at(i);
        let midi = realize_degree(octave, deg, tonic, mode);
        out.append(
            V2NoteEvent {
                pitch: midi_to_pitch(midi, deg),
                start: (i + entry) * unit,
                duration: unit,
                velocity: 90,
                role: 0,
                ornament_id: 0,
                voice_index,
            },
        );
        i += 1;
    };
    out
}

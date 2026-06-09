//! Pitch and scale-step utilities for v2 ornamentation.

use core::array::ArrayTrait;
use koji::composition::melodic_canon::{mode_scale, realize_degree};
use koji::composition::ornamentation_v2::types::{DEGREE_SENTINEL, V2NoteEvent, V2Pitch};

pub fn pc_mod12(x: i32) -> u8 {
    let bias: i32 = 120;
    let d = x + bias;
    let du: u32 = d.try_into().unwrap();
    (du % 12).try_into().unwrap()
}

pub fn interval_above_bass(voice_pc: u8, bass_pc: u8) -> u8 {
    let v: u32 = voice_pc.into();
    let b: u32 = bass_pc.into();
    let ivl = if v >= b {
        v - b
    } else {
        v + 12 - b
    };
    ivl.try_into().unwrap()
}

pub fn scale_step_distance(a_deg: i32, b_deg: i32) -> u32 {
    let d = if b_deg >= a_deg {
        b_deg - a_deg
    } else {
        a_deg - b_deg
    };
    d.try_into().unwrap()
}

pub fn degree_to_midi(degree: i32, tonic_keynum: u8, mode_id: u8, octave_lattice: u32) -> u8 {
    realize_degree(octave_lattice, degree, tonic_keynum, mode_id)
}

pub fn midi_to_pitch(midi: u8, degree: i32) -> V2Pitch {
    V2Pitch {
        pc: midi % 12,
        octave: midi / 12,
        degree,
        midi,
    }
}

pub fn step_degree(degree: i32, steps: i32) -> i32 {
    degree + steps
}

pub fn chromatic_approach_pc(target_pc: u8, from_above: bool) -> u8 {
    if from_above {
        if target_pc == 0 {
            11_u8
        } else {
            target_pc - 1
        }
    } else if target_pc == 11 {
        0_u8
    } else {
        target_pc + 1
    }
}

pub fn pc_in_scale(pc: u8, scale_pcs: Span<u8>) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    loop {
        if i >= scale_pcs.len() {
            break;
        }
        if *scale_pcs.at(i) == pc {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

pub fn chord_contains_pc(chord_pcs: Span<u8>, pc: u8) -> bool {
    pc_in_scale(pc, chord_pcs)
}

pub fn common_tone_pcs(
    prev_chord: Span<u8>, curr_chord: Span<u8>, next_chord: Span<u8>,
) -> u8 {
    let mut i: u32 = 0;
    loop {
        if i >= prev_chord.len() {
            break;
        }
        let pc = *prev_chord.at(i);
        if pc_in_scale(pc, curr_chord) && pc_in_scale(pc, next_chord) {
            return pc;
        }
        i += 1;
    };
    if prev_chord.len() > 0 {
        *prev_chord.at(0)
    } else {
        0_u8
    }
}

pub fn mode_scale_pcs(mode_id: u8, key_pc: u8) -> Array<u8> {
    let scale = mode_scale(mode_id);
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= scale.len() {
            break;
        }
        let semis: u32 = (*scale.at(i)).into();
        let pc = (key_pc.into() + semis) % 12;
        out.append(pc.try_into().unwrap());
        i += 1;
    };
    out
}

pub fn subdivide_duration(total: u32, parts: u32) -> u32 {
    if parts == 0 {
        return total;
    }
    total / parts
}

pub fn sum_durations(events: Span<V2NoteEvent>) -> u32 {
    let mut s: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        s += (*events.at(i)).duration;
        i += 1;
    };
    s
}

pub fn leap_semitones(a_midi: u8, b_midi: u8) -> u32 {
    let a: u32 = a_midi.into();
    let b: u32 = b_midi.into();
    if a >= b {
        a - b
    } else {
        b - a
    }
}

pub fn degree_sentinel_pitch(midi: u8) -> V2Pitch {
    V2Pitch { pc: midi % 12, octave: midi / 12, degree: DEGREE_SENTINEL, midi }
}

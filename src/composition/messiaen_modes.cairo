//! Messiaen modes of limited transposition, chord generation, and quantization.
//!
//! See `docs/Messaein_Modes.md` for the full specification.

use core::array::ArrayTrait;
use core::traits::{Into, TryInto};
use koji::lcg::{LCG, LCGImpl};
use koji::rng::bounded;

// ──────────────────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────────────────

#[derive(Copy, Drop, Serde)]
pub struct MessiaenMode {
    pub id: u8,
    pub size: u8,
    pub transposition_count: u8,
}

#[derive(Copy, Drop, Serde)]
pub struct MessiaenChordParams {
    pub mode_id: u8,
    pub transposition: u8,
    pub start_index: u8,
    pub skip: u8,
    pub chord_size: u8,
}

#[derive(Drop, Serde)]
pub struct GeneratedMessiaenMaterial {
    pub mode_id: u8,
    pub transposition: u8,
    pub melody_pitch_classes: Array<u8>,
    pub chord_pitch_classes: Array<u8>,
}

const NUM_MODES: u8 = 7;

fn assert_valid_mode_id(mode_id: u8) {
    assert(mode_id >= 1 && mode_id <= NUM_MODES, 'invalid mode_id');
}

fn pow2(n: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        r = r * 2;
        i += 1;
    };
    r
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

fn seed_u256(seed: felt252) -> u256 {
    seed.into()
}

// ──────────────────────────────────────────────────────────
// Mode metadata
// ──────────────────────────────────────────────────────────

pub fn get_mode_size(mode_id: u8) -> u8 {
    assert_valid_mode_id(mode_id);
    if mode_id == 1 {
        6
    } else if mode_id == 2 {
        8
    } else if mode_id == 3 {
        9
    } else if mode_id == 4 {
        8
    } else if mode_id == 5 {
        6
    } else if mode_id == 6 {
        8
    } else {
        10
    }
}

pub fn get_transposition_count(mode_id: u8) -> u8 {
    assert_valid_mode_id(mode_id);
    if mode_id == 1 {
        2
    } else if mode_id == 2 {
        3
    } else if mode_id == 3 {
        4
    } else {
        6
    }
}

fn mode1_pitch_at(index: u8) -> u8 {
    match index % 6 {
        0 => 0,
        1 => 2,
        2 => 4,
        3 => 6,
        4 => 8,
        _ => 10,
    }
}

fn mode2_pitch_at(index: u8) -> u8 {
    match index % 8 {
        0 => 0,
        1 => 1,
        2 => 3,
        3 => 4,
        4 => 6,
        5 => 7,
        6 => 9,
        _ => 10,
    }
}

fn mode3_pitch_at(index: u8) -> u8 {
    match index % 9 {
        0 => 0,
        1 => 2,
        2 => 3,
        3 => 4,
        4 => 6,
        5 => 7,
        6 => 8,
        7 => 10,
        _ => 11,
    }
}

fn mode4_pitch_at(index: u8) -> u8 {
    match index % 8 {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 5,
        4 => 6,
        5 => 7,
        6 => 8,
        _ => 11,
    }
}

fn mode5_pitch_at(index: u8) -> u8 {
    match index % 6 {
        0 => 0,
        1 => 1,
        2 => 5,
        3 => 6,
        4 => 7,
        _ => 11,
    }
}

fn mode6_pitch_at(index: u8) -> u8 {
    match index % 8 {
        0 => 0,
        1 => 2,
        2 => 4,
        3 => 5,
        4 => 6,
        5 => 8,
        6 => 10,
        _ => 11,
    }
}

fn mode7_pitch_at(index: u8) -> u8 {
    match index % 10 {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        4 => 5,
        5 => 6,
        6 => 7,
        7 => 8,
        8 => 9,
        _ => 11,
    }
}

pub fn get_mode_pitch_at(mode_id: u8, index: u8) -> u8 {
    assert_valid_mode_id(mode_id);
    let size = get_mode_size(mode_id);
    let idx = index % size;
    if mode_id == 1 {
        mode1_pitch_at(idx)
    } else if mode_id == 2 {
        mode2_pitch_at(idx)
    } else if mode_id == 3 {
        mode3_pitch_at(idx)
    } else if mode_id == 4 {
        mode4_pitch_at(idx)
    } else if mode_id == 5 {
        mode5_pitch_at(idx)
    } else if mode_id == 6 {
        mode6_pitch_at(idx)
    } else {
        mode7_pitch_at(idx)
    }
}

pub fn transpose_pitch(pc: u8, transposition: u8) -> u8 {
    let sum: u32 = pc.into() + transposition.into();
    (sum % 12).try_into().unwrap()
}

pub fn get_transposed_mode_pitch_at(mode_id: u8, transposition: u8, index: u8) -> u8 {
    let t_count = get_transposition_count(mode_id);
    let wrapped_t = transposition % t_count;
    let base = get_mode_pitch_at(mode_id, index);
    transpose_pitch(base, wrapped_t)
}

// ──────────────────────────────────────────────────────────
// Chords
// ──────────────────────────────────────────────────────────

pub fn generate_chord(
    mode_id: u8,
    transposition: u8,
    start_index: u8,
    skip: u8,
    chord_size: u8,
) -> Array<u8> {
    assert_valid_mode_id(mode_id);
    assert(skip > 0, 'skip must be > 0');
    let mode_size = get_mode_size(mode_id);
    let t_count = get_transposition_count(mode_id);
    let wrapped_t = transposition % t_count;
    let mut chord: Array<u8> = ArrayTrait::new();
    let mut i: u8 = 0;
    loop {
        if i >= chord_size {
            break;
        }
        let idx_u32: u32 = (start_index.into() + i.into() * skip.into()) % mode_size.into();
        let idx: u8 = idx_u32.try_into().unwrap();
        let pc = get_mode_pitch_at(mode_id, idx);
        chord.append(transpose_pitch(pc, wrapped_t));
        i += 1;
    };
    chord
}

fn forward_steps(from_pc: u8, to_pc: u8) -> u8 {
    (to_pc + 12 - from_pc) % 12
}

fn circular_distance(a: u8, b: u8) -> u8 {
    let d = if a >= b { a - b } else { b - a };
    if d <= 6 {
        d
    } else {
        12 - d
    }
}

pub fn quantize_pitch_to_mode(pitch: u8, mode_id: u8, transposition: u8) -> u8 {
    let pc = pitch % 12;
    if is_pitch_in_mode(pc, mode_id, transposition) {
        return pc;
    }
    let size = get_mode_size(mode_id);
    let mut best = get_transposed_mode_pitch_at(mode_id, transposition, 0);
    let mut best_dist: u8 = 12;
    let mut i: u8 = 0;
    loop {
        if i >= size {
            break;
        }
        let m = get_transposed_mode_pitch_at(mode_id, transposition, i);
        let dist = circular_distance(pc, m);
        if dist < best_dist {
            best_dist = dist;
            best = m;
        } else if dist == best_dist {
            if forward_steps(pc, m) < forward_steps(pc, best) {
                best = m;
            }
        }
        i += 1;
    };
    best
}

pub fn is_pitch_in_mode(pitch: u8, mode_id: u8, transposition: u8) -> bool {
    let pc = pitch % 12;
    let size = get_mode_size(mode_id);
    let mut i: u8 = 0;
    loop {
        if i >= size {
            break false;
        }
        if get_transposed_mode_pitch_at(mode_id, transposition, i) == pc {
            break true;
        }
        i += 1;
    }
}

// ──────────────────────────────────────────────────────────
// RNG helpers (deterministic from felt252 seed)
// ──────────────────────────────────────────────────────────

pub fn rng_choose_mode(seed: felt252) -> u8 {
    let s = seed_u256(seed);
    ((extract_bits(s, 0, 8) % NUM_MODES.into()) + 1).try_into().unwrap()
}

pub fn rng_generate_chord_params(seed: felt252) -> MessiaenChordParams {
    let s = seed_u256(seed);
    let mode_id = rng_choose_mode(seed);
    let t_count = get_transposition_count(mode_id);
    let mode_size = get_mode_size(mode_id);
    let transposition: u8 = extract_bits(s, 8, 8).try_into().unwrap() % t_count;
    let start_index: u8 = extract_bits(s, 16, 8).try_into().unwrap() % mode_size;
    let skip_raw: u32 = extract_bits(s, 24, 8);
    let skip: u8 = if mode_size <= 2 {
        1
    } else {
        (skip_raw % (mode_size.into() - 1) + 1).try_into().unwrap()
    };
    let chord_size_raw = extract_bits(s, 32, 8);
    let chord_size: u8 = (chord_size_raw % 4 + 3).try_into().unwrap(); // 3..6
    MessiaenChordParams { mode_id, transposition, start_index, skip, chord_size }
}

// ──────────────────────────────────────────────────────────
// Presets
// ──────────────────────────────────────────────────────────

pub fn generate_diminished_symmetry_chord(transposition: u8, start_index: u8) -> Array<u8> {
    generate_chord(2, transposition, start_index, 2, 4)
}

pub fn generate_dense_color_chord(
    mode_id: u8, transposition: u8, start_index: u8,
) -> Array<u8> {
    let mode_size = get_mode_size(mode_id);
    let skip: u8 = if mode_size % 2 == 0 { 2 } else { 1 };
    let chord_size: u8 = if mode_size >= 7 { 7 } else { mode_size };
    generate_chord(mode_id, transposition, start_index, skip, chord_size)
}

pub fn generate_resonance_chord(root: u8) -> Array<u8> {
    let r = root % 12;
    array![
        r,
        transpose_pitch(r, 4),
        transpose_pitch(r, 7),
        transpose_pitch(r, 10),
        transpose_pitch(r, 2),
        transpose_pitch(r, 6),
        transpose_pitch(r, 9),
    ]
}

// ──────────────────────────────────────────────────────────
// High-level material generator
// ──────────────────────────────────────────────────────────

/// Map a mode pitch class to MIDI in octave 4–5 (centered around C4).
pub fn mode_pc_to_midi(pc: u8, octave: u8) -> u8 {
    let base: u32 = 60; // C4
    let oct_offset: u32 = if octave >= 4 { (octave - 4).into() * 12 } else { 0 };
    (base + oct_offset + (pc % 12).into()).try_into().unwrap()
}

/// Build melody pitch classes by walking the mode with LCG-driven indices.
pub fn generate_melody_pitch_classes(
    mode_id: u8,
    transposition: u8,
    length: u32,
    lcg_state: u32,
) -> Array<u8> {
    let mode_size: u32 = get_mode_size(mode_id).into();
    let mut lcg = LCG { state: lcg_state, multiplier: 5, increment: 3, modulus: 256 };
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= length {
            break;
        }
        let raw = lcg.value();
        lcg = lcg.next();
        let idx: u8 = bounded(raw, mode_size).try_into().unwrap();
        out.append(get_transposed_mode_pitch_at(mode_id, transposition, idx));
        i += 1;
    };
    out
}

pub fn generate_messiaen_material(seed: felt252) -> GeneratedMessiaenMaterial {
    let s = seed_u256(seed);
    let mode_id = rng_choose_mode(seed);
    let t_count = get_transposition_count(mode_id);
    let transposition: u8 = extract_bits(s, 40, 8).try_into().unwrap() % t_count;
    let melody_len: u32 = (extract_bits(s, 48, 8) % 32) + 16; // 16..47
    let lcg_state: u32 = extract_bits(s, 56, 16);
    let melody_pitch_classes = generate_melody_pitch_classes(
        mode_id, transposition, melody_len, lcg_state,
    );
    let params = rng_generate_chord_params(seed);
    let chord_pitch_classes = generate_chord(
        params.mode_id,
        params.transposition,
        params.start_index,
        params.skip,
        params.chord_size,
    );
    GeneratedMessiaenMaterial {
        mode_id,
        transposition,
        melody_pitch_classes,
        chord_pitch_classes,
    }
}

/// Voice a chord across octaves as MIDI keynums (root in octave 3, upper tones in 4–5).
pub fn chord_pcs_to_midi(chord: Span<u8>) -> Array<u8> {
    let mut notes: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= chord.len() {
            break;
        }
        let pc = *chord.at(i);
        let octave: u8 = if i == 0 { 3 } else { 4 };
        notes.append(mode_pc_to_midi(pc, octave));
        i += 1;
    };
    notes
}

//! Symmetric Pitch Worlds — transpositionally symmetric pitch collections in Z12.
//!
//! Generalizes Messiaen modes of limited transposition into a broader symmetry engine
//! using 12-bit pitch-class masks. See `docs/PRD_SYMMETRY_ENGINE.md`.

use core::array::ArrayTrait;
use core::traits::{Into, TryInto};
use koji::composition::known_symmetric_worlds::{REGISTRY_SIZE, registry_entry};
use koji::composition::rhythmic_tiling::{
    RhythmicCanon, generate_rhythmic_canon, generate_rhythmic_canon_for_cycle,
};
use koji::composition::known_tilings::gen_supported_n;
use koji::rng::bounded;

// ──────────────────────────────────────────────────────────
// Family IDs
// ──────────────────────────────────────────────────────────

pub const FAMILY_MESSIAEN: u8 = 1;
pub const FAMILY_DIMINISHED: u8 = 2;
pub const FAMILY_AUGMENTED: u8 = 3;
pub const FAMILY_WHOLE_TONE: u8 = 4;
pub const FAMILY_TRITONE: u8 = 5;
pub const FAMILY_CHROMATIC: u8 = 6;
pub const FAMILY_GENERATED: u8 = 7;
pub const FAMILY_USER_DEFINED: u8 = 8;

const NUM_MESSIAEN_MODES: u8 = 7;

// ──────────────────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────────────────

#[derive(Copy, Drop, Serde)]
pub struct PitchWorld {
    pub id: u16,
    pub mask: u16,
    pub symmetry_step: u8,
    pub pitch_count: u8,
    pub unique_transpositions: u8,
    pub family_id: u8,
    pub default_transposition: u8,
}

#[derive(Copy, Drop, Serde)]
pub struct ChordParams {
    pub start_index: u8,
    pub skip: u8,
    pub chord_size: u8,
}

#[derive(Copy, Drop, Serde)]
pub struct SymmetryCompositionParams {
    pub seed: felt252,
    pub world_id: u16,
    pub world_transposition: u8,
    pub motif_length: u8,
    pub chord_start_index: u8,
    pub chord_skip: u8,
    pub chord_size: u8,
    pub rhythmic_cycle_length: u8,
}

#[derive(Drop, Serde)]
pub struct GeneratedSymmetryMaterial {
    pub world_id: u16,
    pub world_mask: u16,
    pub world_transposition: u8,
    pub melody_pitch_classes: Array<u8>,
    pub chord_pitch_classes: Array<u8>,
}

#[derive(Drop)]
pub struct SymmetryComposition {
    pub rhythmic_cycle_length: u32,
    pub pitch_material: GeneratedSymmetryMaterial,
    pub voice_motifs: Array<Array<u8>>,
    pub canon: RhythmicCanon,
}

fn pow2(n: u32) -> u16 {
    let mut r: u16 = 1;
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

fn seed_u256(seed: felt252) -> u256 {
    seed.into()
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let mut p: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= shift {
            break;
        }
        p = p * 2;
        i += 1;
    };
    let mut w: u256 = 1;
    i = 0;
    loop {
        if i >= width {
            break;
        }
        w = w * 2;
        i += 1;
    };
    let v = (s / p) % w;
    v.try_into().unwrap()
}

// ──────────────────────────────────────────────────────────
// Low-level bitmask operations
// ──────────────────────────────────────────────────────────

pub fn mod12(x: u8) -> u8 {
    x % 12
}

pub fn pitch_to_bit(pc: u8) -> u16 {
    pow2(mod12(pc).into())
}

pub fn has_pitch(mask: u16, pc: u8) -> bool {
    mask & pitch_to_bit(pc) != 0
}

pub fn add_pitch(mask: u16, pc: u8) -> u16 {
    mask | pitch_to_bit(pc)
}

pub fn count_pitches(mask: u16) -> u8 {
    let mut count: u8 = 0;
    let mut pc: u8 = 0;
    loop {
        if pc >= 12 {
            break;
        }
        if has_pitch(mask, pc) {
            count += 1;
        }
        pc += 1;
    };
    count
}

pub fn transpose_mask(mask: u16, t: u8) -> u16 {
    let trans = mod12(t);
    let mut out: u16 = 0;
    let mut pc: u8 = 0;
    loop {
        if pc >= 12 {
            break;
        }
        if has_pitch(mask, pc) {
            out = add_pitch(out, mod12(pc + trans));
        }
        pc += 1;
    };
    out
}

pub fn is_symmetric_under(mask: u16, step: u8) -> bool {
    if step == 0 {
        return true;
    }
    transpose_mask(mask, step) == mask
}

pub fn find_min_symmetry_step(mask: u16) -> u8 {
    if is_symmetric_under(mask, 1) {
        return 1;
    }
    if is_symmetric_under(mask, 2) {
        return 2;
    }
    if is_symmetric_under(mask, 3) {
        return 3;
    }
    if is_symmetric_under(mask, 4) {
        return 4;
    }
    if is_symmetric_under(mask, 6) {
        return 6;
    }
    0
}

pub fn unique_transposition_count(mask: u16) -> u8 {
    let step = find_min_symmetry_step(mask);
    if step == 0 {
        12
    } else {
        step
    }
}

// ──────────────────────────────────────────────────────────
// Orbit generation
// ──────────────────────────────────────────────────────────

pub fn generate_orbit(start: u8, step: u8) -> u16 {
    assert(step > 0, 'step must be > 0');
    let s = mod12(start);
    let st = mod12(step);
    let mut mask: u16 = 0;
    let mut pc: u8 = s;
    loop {
        mask = add_pitch(mask, pc);
        pc = mod12(pc + st);
        if pc == s {
            break;
        }
    };
    mask
}

pub fn generate_world_from_orbits(step: u8, orbit_starts: Array<u8>) -> u16 {
    assert(step > 0, 'step must be > 0');
    let mut world: u16 = 0;
    let mut i: usize = 0;
    loop {
        if i >= orbit_starts.len() {
            break;
        }
        let start = *orbit_starts.at(i);
        world = world | generate_orbit(start, step);
        i += 1;
    };
    world
}

// ──────────────────────────────────────────────────────────
// Named preset masks
// ──────────────────────────────────────────────────────────

pub fn world_diminished_seventh() -> u16 {
    585
}

pub fn world_augmented_triad() -> u16 {
    273
}

pub fn world_whole_tone() -> u16 {
    1365
}

pub fn world_tritone_pair() -> u16 {
    65
}

pub fn world_chromatic() -> u16 {
    4095
}

pub fn messiaen_mode_mask(mode_id: u8) -> u16 {
    assert(mode_id >= 1 && mode_id <= NUM_MESSIAEN_MODES, 'invalid mode_id');
    if mode_id == 1 {
        1365
    } else if mode_id == 2 {
        1755
    } else if mode_id == 3 {
        3549
    } else if mode_id == 4 {
        2535
    } else if mode_id == 5 {
        2275
    } else if mode_id == 6 {
        3445
    } else {
        3055
    }
}

// ──────────────────────────────────────────────────────────
// User-defined world validation
// ──────────────────────────────────────────────────────────

pub fn is_valid_world_mask(mask: u16) -> bool {
    mask != 0 && count_pitches(mask) <= 12
}

pub fn validate_symmetric_mask(mask: u16) -> bool {
    is_valid_world_mask(mask) && find_min_symmetry_step(mask) != 0
}

pub fn build_pitch_world_from_mask(mask: u16, family_id: u8) -> PitchWorld {
    assert(is_valid_world_mask(mask), 'invalid mask');
    PitchWorld {
        id: 0,
        mask,
        symmetry_step: find_min_symmetry_step(mask),
        pitch_count: count_pitches(mask),
        unique_transpositions: unique_transposition_count(mask),
        family_id,
        default_transposition: 0,
    }
}

// ──────────────────────────────────────────────────────────
// Curated world registry
// ──────────────────────────────────────────────────────────

pub fn get_world_by_id(world_id: u16) -> PitchWorld {
    let entry = registry_entry(world_id);
    let base_mask = transpose_mask(entry.mask, entry.default_transposition);
    PitchWorld {
        id: world_id,
        mask: base_mask,
        symmetry_step: find_min_symmetry_step(base_mask),
        pitch_count: count_pitches(base_mask),
        unique_transpositions: unique_transposition_count(base_mask),
        family_id: entry.family_id,
        default_transposition: entry.default_transposition,
    }
}

pub fn registry_size() -> u16 {
    REGISTRY_SIZE
}

// ──────────────────────────────────────────────────────────
// Musical quality filters
// ──────────────────────────────────────────────────────────

pub fn is_world_musically_useful(world: PitchWorld, allow_sparse: bool) -> bool {
    let count = world.pitch_count;
    if !allow_sparse && count < 3 {
        return false;
    }
    if count > 10 && world.family_id != FAMILY_CHROMATIC {
        return false;
    }
    true
}

fn is_rng_eligible(world: PitchWorld, allow_sparse: bool, allow_color: bool) -> bool {
    if !allow_color && world.family_id == FAMILY_USER_DEFINED {
        return false;
    }
    is_world_musically_useful(world, allow_sparse)
}

fn count_rng_eligible_worlds(allow_sparse: bool, allow_color: bool) -> u16 {
    let mut count: u16 = 0;
    let mut id: u16 = 1;
    loop {
        if id > REGISTRY_SIZE {
            break;
        }
        if is_rng_eligible(get_world_by_id(id), allow_sparse, allow_color) {
            count += 1;
        }
        id += 1;
    };
    count
}

fn nth_rng_eligible_world_id(n: u16, allow_sparse: bool, allow_color: bool) -> u16 {
    let mut seen: u16 = 0;
    let mut id: u16 = 1;
    loop {
        if id > REGISTRY_SIZE {
            break 1;
        }
        if is_rng_eligible(get_world_by_id(id), allow_sparse, allow_color) {
            if seen == n {
                break id;
            }
            seen += 1;
        }
        id += 1;
    }
}

pub fn classify_density(pitch_count: u8) -> u8 {
    if pitch_count <= 2 {
        1
    } else if pitch_count == 3 {
        2
    } else if pitch_count == 4 {
        3
    } else if pitch_count <= 6 {
        4
    } else if pitch_count <= 8 {
        5
    } else if pitch_count <= 10 {
        6
    } else {
        7
    }
}

// ──────────────────────────────────────────────────────────
// World transposition and pitch access
// ──────────────────────────────────────────────────────────

pub fn transpose_world(world: PitchWorld, transposition: u8) -> PitchWorld {
    let wrapped = if world.unique_transpositions == 0 {
        mod12(transposition)
    } else {
        transposition % world.unique_transpositions
    };
    PitchWorld {
        id: world.id,
        mask: transpose_mask(world.mask, wrapped),
        symmetry_step: world.symmetry_step,
        pitch_count: world.pitch_count,
        unique_transpositions: world.unique_transpositions,
        family_id: world.family_id,
        default_transposition: world.default_transposition,
    }
}

pub fn get_pitch_at_index(mask: u16, index: u8) -> u8 {
    let size = count_pitches(mask);
    assert(size > 0, 'empty mask');
    let idx = index % size;
    let mut seen: u8 = 0;
    let mut pc: u8 = 0;
    loop {
        if pc >= 12 {
            break 0;
        }
        if has_pitch(mask, pc) {
            if seen == idx {
                break pc;
            }
            seen += 1;
        }
        pc += 1;
    }
}

pub fn transpose_pitch_classes(pcs: Span<u8>, transposition: u8) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        out.append(mod12(*pcs.at(i) + transposition));
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Chord generation
// ──────────────────────────────────────────────────────────

fn chord_contains(chord: Span<u8>, pc: u8) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= chord.len() {
            break false;
        }
        if *chord.at(i) == pc {
            break true;
        }
        i += 1;
    }
}

pub fn generate_world_chord(
    mask: u16, start_index: u8, skip: u8, chord_size: u8, allow_duplicates: bool,
) -> Array<u8> {
    assert(skip > 0, 'skip must be > 0');
    let mut chord: Array<u8> = ArrayTrait::new();
    let mut i: u8 = 0;
    let mut attempts: u8 = 0;
    let max_attempts: u8 = chord_size * 4;
    loop {
        if i >= chord_size {
            break;
        }
        if attempts >= max_attempts {
            break;
        }
        let idx_u32: u32 = start_index.into() + attempts.into() * skip.into();
        let idx: u8 = idx_u32.try_into().unwrap();
        let pc = get_pitch_at_index(mask, idx);
        attempts += 1;
        if !allow_duplicates && chord_contains(chord.span(), pc) {
            continue;
        }
        chord.append(pc);
        i += 1;
    };
    chord
}

// ──────────────────────────────────────────────────────────
// Quantization
// ──────────────────────────────────────────────────────────

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

pub fn quantize_pitch_to_world(mask: u16, pitch: u8) -> u8 {
    let pc = mod12(pitch);
    if has_pitch(mask, pc) {
        return pc;
    }
    let size = count_pitches(mask);
    let mut best = get_pitch_at_index(mask, 0);
    let mut best_dist: u8 = 12;
    let mut i: u8 = 0;
    loop {
        if i >= size {
            break;
        }
        let m = get_pitch_at_index(mask, i);
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

// ──────────────────────────────────────────────────────────
// Motif generation
// ──────────────────────────────────────────────────────────

fn motif_hash(seed: felt252, index: u8) -> u32 {
    let s = seed_u256(seed);
    let i: u256 = index.into();
    let golden: u256 = 0x9E3779B9;
    let mixed = s + i * golden;
    extract_bits(mixed, 0, 32)
}

pub fn generate_world_motif(seed: felt252, mask: u16, length: u8) -> Array<u8> {
    let pitch_count = count_pitches(mask);
    assert(pitch_count > 0, 'empty mask');
    let mut motif: Array<u8> = ArrayTrait::new();
    let mut i: u8 = 0;
    loop {
        if i >= length {
            break;
        }
        let raw = motif_hash(seed, i);
        let idx: u8 = bounded(raw, pitch_count.into()).try_into().unwrap();
        motif.append(get_pitch_at_index(mask, idx));
        i += 1;
    };
    motif
}

pub fn place_motif_on_canon_voices(
    canon: @RhythmicCanon, base_motif: Span<u8>,
) -> Array<Array<u8>> {
    let voices = *canon.voices;
    let mut out: Array<Array<u8>> = ArrayTrait::new();
    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let voice = *voices.at(vi);
        if voice.tiling_participant {
            let t: u8 = (voice.translation % 12).try_into().unwrap();
            out.append(transpose_pitch_classes(base_motif, t));
        }
        vi += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// RNG helpers
// ──────────────────────────────────────────────────────────

pub fn rng_choose_world_id(seed: felt252) -> u16 {
    rng_choose_world_id_filtered(seed, false, false)
}

pub fn rng_choose_world_id_filtered(
    seed: felt252, allow_sparse: bool, allow_color: bool,
) -> u16 {
    let eligible = count_rng_eligible_worlds(allow_sparse, allow_color);
    assert(eligible > 0, 'no eligible worlds');
    let s = seed_u256(seed);
    let pick: u16 = extract_bits(s, 0, 8).try_into().unwrap() % eligible;
    nth_rng_eligible_world_id(pick, allow_sparse, allow_color)
}

pub fn rng_choose_world_transposition(seed: felt252, world: PitchWorld) -> u8 {
    let s = seed_u256(seed);
    let t_count = if world.unique_transpositions == 0 {
        12
    } else {
        world.unique_transpositions
    };
    extract_bits(s, 8, 8).try_into().unwrap() % t_count
}

pub fn rng_choose_chord_params(seed: felt252, world: PitchWorld) -> ChordParams {
    let s = seed_u256(seed);
    let pitch_count = world.pitch_count;
    let start_index: u8 = extract_bits(s, 16, 8).try_into().unwrap() % pitch_count;
    let skip_raw: u32 = extract_bits(s, 24, 8);
    let skip: u8 = if pitch_count <= 2 {
        1
    } else {
        (skip_raw % (pitch_count.into() - 1) + 1).try_into().unwrap()
    };
    let chord_size_raw = extract_bits(s, 32, 8);
    let max_size: u8 = if pitch_count < 7 {
        pitch_count
    } else {
        7
    };
    let min_size: u8 = if pitch_count < 3 { pitch_count } else { 3 };
    let range: u8 = max_size - min_size + 1;
    let chord_size: u8 = (chord_size_raw % range.into() + min_size.into()).try_into().unwrap();
    ChordParams { start_index, skip, chord_size }
}

pub fn rng_choose_motif_length(seed: felt252) -> u8 {
    let s = seed_u256(seed);
    let choice = extract_bits(s, 40, 8) % 4;
    if choice == 0 {
        4
    } else if choice == 1 {
        8
    } else if choice == 2 {
        12
    } else {
        16
    }
}

fn resolve_rhythmic_cycle(seed: felt252, override_len: u8) -> u32 {
    if override_len == 0 {
        let ns = gen_supported_n();
        let s = seed_u256(seed);
        *ns.at(extract_bits(s, 56, 4) % ns.len())
    } else {
        override_len.into()
    }
}

// ──────────────────────────────────────────────────────────
// High-level material generator
// ──────────────────────────────────────────────────────────

pub fn generate_symmetry_material(
    params: SymmetryCompositionParams,
) -> GeneratedSymmetryMaterial {
    let world = get_world_by_id(params.world_id);
    let transposed = transpose_world(world, params.world_transposition);
    let mask = transposed.mask;
    let motif_length = if params.motif_length == 0 {
        rng_choose_motif_length(params.seed)
    } else {
        params.motif_length
    };
    let melody_pitch_classes = generate_world_motif(params.seed, mask, motif_length);
    let chord_pitch_classes = generate_world_chord(
        mask,
        params.chord_start_index,
        params.chord_skip,
        params.chord_size,
        true,
    );
    GeneratedSymmetryMaterial {
        world_id: params.world_id,
        world_mask: mask,
        world_transposition: params.world_transposition % world.unique_transpositions,
        melody_pitch_classes,
        chord_pitch_classes,
    }
}

pub fn generate_symmetry_material_from_seed(seed: felt252) -> GeneratedSymmetryMaterial {
    let world_id = rng_choose_world_id(seed);
    let world = get_world_by_id(world_id);
    let world_transposition = rng_choose_world_transposition(seed, world);
    let chord = rng_choose_chord_params(seed, world);
    let motif_length = rng_choose_motif_length(seed);
    generate_symmetry_material(
        SymmetryCompositionParams {
            seed,
            world_id,
            world_transposition,
            motif_length,
            chord_start_index: chord.start_index,
            chord_skip: chord.skip,
            chord_size: chord.chord_size,
            rhythmic_cycle_length: 0,
        },
    )
}

pub fn generate_symmetry_composition(
    params: SymmetryCompositionParams,
) -> SymmetryComposition {
    let n = resolve_rhythmic_cycle(params.seed, params.rhythmic_cycle_length);
    let canon = if params.rhythmic_cycle_length == 0 {
        generate_rhythmic_canon(params.seed)
    } else {
        generate_rhythmic_canon_for_cycle(params.seed, n)
    };
    let pitch_material = generate_symmetry_material(params);
    let voice_motifs = place_motif_on_canon_voices(
        @canon, pitch_material.melody_pitch_classes.span(),
    );
    SymmetryComposition {
        rhythmic_cycle_length: canon.n,
        pitch_material,
        voice_motifs,
        canon,
    }
}

pub fn generate_symmetry_composition_from_seed(seed: felt252) -> SymmetryComposition {
    let world_id = rng_choose_world_id(seed);
    let world = get_world_by_id(world_id);
    let world_transposition = rng_choose_world_transposition(seed, world);
    let chord = rng_choose_chord_params(seed, world);
    let motif_length = rng_choose_motif_length(seed);
    generate_symmetry_composition(
        SymmetryCompositionParams {
            seed,
            world_id,
            world_transposition,
            motif_length,
            chord_start_index: chord.start_index,
            chord_skip: chord.skip,
            chord_size: chord.chord_size,
            rhythmic_cycle_length: 0,
        },
    )
}

// ──────────────────────────────────────────────────────────
// MIDI voicing helpers
// ──────────────────────────────────────────────────────────

pub fn world_pc_to_midi(pc: u8, octave: u8) -> u8 {
    let base: u32 = 60;
    let oct_offset: u32 = if octave >= 4 { (octave - 4).into() * 12 } else { 0 };
    (base + oct_offset + mod12(pc).into()).try_into().unwrap()
}

pub fn chord_pcs_to_midi(chord: Span<u8>) -> Array<u8> {
    let mut notes: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= chord.len() {
            break;
        }
        let pc = *chord.at(i);
        let octave: u8 = if i == 0 { 3 } else { 4 };
        notes.append(world_pc_to_midi(pc, octave));
        i += 1;
    };
    notes
}

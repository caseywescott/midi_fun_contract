//! Seeded Baroque cadential improvisation.
//!
//! This module turns a seed into a small partimento-style keyboard texture: a schema-aware
//! melody, a bass/figure plan, tagged suspensions and sequence cells, and a `NoteEvent` stream.
//!
//! See `docs/baroque_cadential_improvisation_spec.md`.

use core::array::ArrayTrait;
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::transform::{
    EveryNthOp, PlaneOp, Selector, map_where_i32,
};

// ──────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────

pub const FAMILY_CADENTIAL_STUDY: u8 = 0;
pub const FAMILY_SEQUENCE_STUDY: u8 = 1;
pub const FAMILY_MODULAR_ETUDE: u8 = 2;

pub const MODULE_CADENCE_43: u32 = 0;
pub const MODULE_CADENCE_3451: u32 = 1;
pub const MODULE_CADENCE_FRENCH_LONG5: u32 = 2;
pub const MODULE_CADENCE_DESC_3451: u32 = 3;
pub const MODULE_CADENCE_DESC_4251: u32 = 4;
pub const MODULE_CADENZA_DOPPIA: u32 = 5;
pub const MODULE_FAUXBOURDON_76: u32 = 10;
pub const MODULE_CIRCLE_5THS: u32 = 11;
pub const MODULE_ROMANESCA: u32 = 12;
pub const MODULE_ASCENDING_5THS: u32 = 13;

pub const TEXTURE_PLAIN: u8 = 0;
pub const TEXTURE_STEP_FILL_BASS: u8 = 1;
pub const TEXTURE_BROKEN_STYLE: u8 = 2;
pub const TEXTURE_STYLE_BRISE: u8 = 3;
pub const TEXTURE_SCALAR_DESCENT: u8 = 4;
pub const TEXTURE_SUSPENSION_CHAIN: u8 = 5;
pub const TEXTURE_DENSE: u8 = 6;

pub const MODE_MAJOR: u8 = 0;
pub const MODE_NATURAL_MINOR: u8 = 1;
pub const MODE_HARMONIC_MINOR: u8 = 2;

pub const TAG_NONE: u8 = 0;
pub const TAG_SUSPENSION_43: u8 = 1;
pub const TAG_CHAIN_76: u8 = 2;
pub const TAG_PASSING: u8 = 3;
pub const TAG_CADENTIAL_64: u8 = 4;
pub const TAG_RAISED_4: u8 = 5;

pub const ROLE_MELODY: u32 = 0;
pub const ROLE_BASS: u32 = 1;
pub const ROLE_ALTO_FILL: u32 = 2;
pub const ROLE_TENOR_FILL: u32 = 3;

pub const DEFAULT_UNIT: u32 = 4;
pub const DEFAULT_DURATION: u32 = 4;
pub const BRISER_DURATION: u32 = 2;

// ──────────────────────────────────────────────────────────
// Data structures
// ──────────────────────────────────────────────────────────

#[derive(Copy, Drop)]
pub struct ScaleDegree {
    /// Internal diatonic degree: 0 = scale degree 1, 1 = scale degree 2, etc.
    pub degree0: i32,
    /// Local chromatic alteration in semitones: -1 flat, 0 natural, +1 sharp.
    pub alter: i32,
}

#[derive(Copy, Drop)]
pub struct LocalKey {
    pub tonic_pc: u8,
    /// `MODE_MAJOR`, `MODE_NATURAL_MINOR`, or `MODE_HARMONIC_MINOR`.
    pub mode_id: u8,
    pub degree_offset: i32,
}

#[derive(Copy, Drop)]
pub struct MelodyAnchor {
    pub position: u32,
    pub target_degree: ScaleDegree,
    pub anchor_kind: u8,
}

#[derive(Drop)]
pub struct BaroqueMelody {
    pub degrees: Span<ScaleDegree>,
    pub anchors: Span<MelodyAnchor>,
    pub anchor_adjustments: u32,
    pub mode_policy: u8,
}

#[derive(Copy, Drop)]
pub struct BaroqueModule {
    pub id: u32,
    pub name: felt252,
    pub kind: u8,
    pub length_units: u32,
    pub cadence_target_degree0: i32,
    pub default_texture: u8,
}

#[derive(Copy, Drop)]
pub struct FiguredSonority {
    pub time_index: u32,
    pub bass_degree: ScaleDegree,
    /// Figured interval number above the bass, e.g. 3, 4, 6, 7.
    pub primary_interval: i32,
    /// Optional second figure. 0 means none.
    pub secondary_interval: i32,
    pub dissonance_tag: u8,
}

#[derive(Drop)]
pub struct BaroquePlan {
    pub phrase_family: u8,
    pub modules: Span<u32>,
    pub local_keys: Span<LocalKey>,
    pub transpositions: Span<i32>,
    pub texture_ids: Span<u8>,
    pub cadence_positions: Span<u32>,
    pub modulation_target: i32,
}

#[derive(Drop)]
pub struct BaroqueRealization {
    pub seed: felt252,
    pub plan: BaroquePlan,
    pub melody: Span<ScaleDegree>,
    pub bass: Span<ScaleDegree>,
    pub figures: Span<FiguredSonority>,
    pub events: Span<NoteEvent>,
    pub anchor_adjustments: u32,
}

#[derive(Copy, Drop)]
pub struct BaroqueTraits {
    pub phrase_family: u8,
    pub primary_module: u32,
    pub cadence_type: u32,
    pub sequence_type: u32,
    pub texture: u8,
    pub minor_scale_policy: u8,
    pub modulation_target: i32,
    pub anchor_adjustments: u32,
    pub event_count: u32,
}

// ──────────────────────────────────────────────────────────
// Seed helpers
// ──────────────────────────────────────────────────────────

fn pow2(p: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= p {
            break;
        }
        r *= 2;
        i += 1;
    };
    r
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

fn abs_i32(x: i32) -> u32 {
    if x < 0 {
        (-x).try_into().unwrap()
    } else {
        x.try_into().unwrap()
    }
}

fn sd(degree0: i32, alter: i32) -> ScaleDegree {
    ScaleDegree { degree0, alter }
}

fn transpose_sd(d: ScaleDegree, t: i32) -> ScaleDegree {
    ScaleDegree { degree0: d.degree0 + t, alter: d.alter }
}

fn scale_for_mode(mode_id: u8) -> Span<u8> {
    if mode_id == MODE_NATURAL_MINOR {
        array![0_u8, 2, 3, 5, 7, 8, 10].span()
    } else if mode_id == MODE_HARMONIC_MINOR {
        array![0_u8, 2, 3, 5, 7, 8, 11].span()
    } else {
        array![0_u8, 2, 4, 5, 7, 9, 11].span()
    }
}

fn degree_to_keynum_baroque(degree: ScaleDegree, tonic_keynum: u8, mode_id: u8) -> u8 {
    let bias: i32 = 70;
    let d: i32 = degree.degree0 + bias;
    let du: u32 = d.try_into().unwrap();
    let oct: u32 = du / 7;
    let idx: u32 = du % 7;
    let scale = scale_for_mode(mode_id);
    let semis: u32 = (*scale.at(idx)).into();
    let base: u32 = tonic_keynum.into();
    let mut total: u32 = base + 12 * oct + semis - 120;
    if degree.alter < 0 {
        total -= abs_i32(degree.alter);
    } else {
        let alt: u32 = degree.alter.try_into().unwrap();
        total += alt;
    }
    total.try_into().unwrap()
}

fn diatonic_offset_to_semitones(offset: i32, mode_id: u8) -> i32 {
    let bias: i32 = 70;
    let d: i32 = offset + bias;
    let du: u32 = d.try_into().unwrap();
    let oct: i32 = (du / 7).try_into().unwrap();
    let idx: u32 = du % 7;
    let scale = scale_for_mode(mode_id);
    let semis: i32 = (*scale.at(idx)).into();
    semis + 12 * oct - 120
}

fn pc_for_degree_offset(tonic_pc: u8, offset: i32, mode_id: u8) -> u8 {
    let base: i32 = tonic_pc.into();
    let shifted = base + diatonic_offset_to_semitones(offset, mode_id) + 1200;
    (shifted % 12).try_into().unwrap()
}

fn tonic_for_voice(pc: u8, voice_id: u32) -> u8 {
    let p: u32 = pc.into();
    if voice_id == ROLE_BASS {
        (48 + p).try_into().unwrap()
    } else if voice_id == ROLE_MELODY {
        (72 + p).try_into().unwrap()
    } else {
        (60 + p).try_into().unwrap()
    }
}

// ──────────────────────────────────────────────────────────
// Module catalogue
// ──────────────────────────────────────────────────────────

pub fn module_by_id(id: u32) -> BaroqueModule {
    if id == MODULE_CADENCE_43 {
        BaroqueModule {
            id,
            name: 'cadence_43',
            kind: 0,
            length_units: 3,
            cadence_target_degree0: 0,
            default_texture: TEXTURE_PLAIN,
        }
    } else if id == MODULE_CADENCE_3451 {
        BaroqueModule {
            id,
            name: 'cadence_3451',
            kind: 0,
            length_units: 4,
            cadence_target_degree0: 0,
            default_texture: TEXTURE_BROKEN_STYLE,
        }
    } else if id == MODULE_CADENCE_FRENCH_LONG5 {
        BaroqueModule {
            id,
            name: 'cadence_french_long5',
            kind: 0,
            length_units: 5,
            cadence_target_degree0: 0,
            default_texture: TEXTURE_STYLE_BRISE,
        }
    } else if id == MODULE_CADENCE_DESC_3451 {
        BaroqueModule {
            id,
            name: 'desc_scale_3451',
            kind: 0,
            length_units: 4,
            cadence_target_degree0: 0,
            default_texture: TEXTURE_SCALAR_DESCENT,
        }
    } else if id == MODULE_CADENCE_DESC_4251 {
        BaroqueModule {
            id,
            name: 'desc_scale_4251',
            kind: 0,
            length_units: 4,
            cadence_target_degree0: 0,
            default_texture: TEXTURE_SCALAR_DESCENT,
        }
    } else if id == MODULE_CADENZA_DOPPIA {
        BaroqueModule {
            id,
            name: 'cadenza_doppia',
            kind: 2,
            length_units: 4,
            cadence_target_degree0: 4,
            default_texture: TEXTURE_SUSPENSION_CHAIN,
        }
    } else if id == MODULE_FAUXBOURDON_76 {
        BaroqueModule {
            id,
            name: 'fauxbourdon_76',
            kind: 1,
            length_units: 8,
            cadence_target_degree0: 4,
            default_texture: TEXTURE_SUSPENSION_CHAIN,
        }
    } else if id == MODULE_CIRCLE_5THS {
        BaroqueModule {
            id,
            name: 'circle_fifths',
            kind: 1,
            length_units: 8,
            cadence_target_degree0: 4,
            default_texture: TEXTURE_STEP_FILL_BASS,
        }
    } else if id == MODULE_ROMANESCA {
        BaroqueModule {
            id,
            name: 'romanesca',
            kind: 1,
            length_units: 9,
            cadence_target_degree0: 4,
            default_texture: TEXTURE_SUSPENSION_CHAIN,
        }
    } else {
        BaroqueModule {
            id: MODULE_ASCENDING_5THS,
            name: 'ascending_fifths',
            kind: 1,
            length_units: 8,
            cadence_target_degree0: 5,
            default_texture: TEXTURE_STEP_FILL_BASS,
        }
    }
}

pub fn num_baroque_modules() -> u32 {
    10
}

pub fn module_exists(id: u32) -> bool {
    id == MODULE_CADENCE_43 || id == MODULE_CADENCE_3451
        || id == MODULE_CADENCE_FRENCH_LONG5
        || id == MODULE_CADENCE_DESC_3451
        || id == MODULE_CADENCE_DESC_4251
        || id == MODULE_CADENZA_DOPPIA
        || id == MODULE_FAUXBOURDON_76
        || id == MODULE_CIRCLE_5THS
        || id == MODULE_ROMANESCA
        || id == MODULE_ASCENDING_5THS
}

// ──────────────────────────────────────────────────────────
// Melody and plan selection
// ──────────────────────────────────────────────────────────

pub fn generate_baroque_melody(
    seed: felt252, key: LocalKey, length_units: u32, anchors: Span<MelodyAnchor>,
) -> BaroqueMelody {
    let s: u256 = seed.into();
    let start: i32 = if extract_bits(s, 12, 1) == 0 {
        7
    } else {
        9
    };
    let contour_bias = extract_bits(s, 14, 2);
    let mut degrees: Array<ScaleDegree> = ArrayTrait::new();
    let mut adjustments: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= length_units {
            break;
        }
        let mut degree: i32 = start - i.try_into().unwrap();
        if contour_bias == 1 && i % 3 == 1 {
            degree += 1;
        } else if contour_bias == 2 && i % 4 == 2 {
            degree -= 1;
        }

        let mut alter: i32 = 0;
        if key.mode_id == MODE_HARMONIC_MINOR && (degree % 7 == 6 || degree % 7 == -1) {
            alter = 1;
        }

        let mut ai: u32 = 0;
        loop {
            if ai >= anchors.len() {
                break;
            }
            let a = *anchors.at(ai);
            if a.position == i {
                if degree != a.target_degree.degree0 || alter != a.target_degree.alter {
                    adjustments += 1;
                }
                degree = a.target_degree.degree0;
                alter = a.target_degree.alter;
            }
            ai += 1;
        };
        degrees.append(sd(degree, alter));
        i += 1;
    };

    BaroqueMelody {
        degrees: degrees.span(), anchors, anchor_adjustments: adjustments, mode_policy: key.mode_id,
    }
}

fn plan_modules_for_family(
    family: u8, variant: u32,
) -> (Array<u32>, Array<i32>, Array<u8>, Array<u32>, i32) {
    let mut modules: Array<u32> = ArrayTrait::new();
    let mut trans: Array<i32> = ArrayTrait::new();
    let mut textures: Array<u8> = ArrayTrait::new();
    let mut cadences: Array<u32> = ArrayTrait::new();
    let mut modulation_target: i32 = 0;

    if family == FAMILY_CADENTIAL_STUDY {
        let cadence = if variant % 5 == 0 {
            MODULE_CADENCE_43
        } else if variant % 5 == 1 {
            MODULE_CADENCE_3451
        } else if variant % 5 == 2 {
            MODULE_CADENCE_FRENCH_LONG5
        } else if variant % 5 == 3 {
            MODULE_CADENCE_DESC_3451
        } else {
            MODULE_CADENCE_DESC_4251
        };
        let m = module_by_id(cadence);
        modules.append(cadence);
        trans.append(0);
        textures.append(m.default_texture);
        cadences.append(0);
    } else if family == FAMILY_SEQUENCE_STUDY {
        let seq = if variant % 4 == 0 {
            MODULE_FAUXBOURDON_76
        } else if variant % 4 == 1 {
            MODULE_CIRCLE_5THS
        } else if variant % 4 == 2 {
            MODULE_ROMANESCA
        } else {
            MODULE_ASCENDING_5THS
        };
        modules.append(seq);
        trans.append(0);
        textures.append(module_by_id(seq).default_texture);
        modules.append(MODULE_CADENCE_FRENCH_LONG5);
        trans.append(0);
        textures.append(TEXTURE_STYLE_BRISE);
        cadences.append(1);
    } else {
        modules.append(MODULE_ROMANESCA);
        trans.append(0);
        textures.append(TEXTURE_SUSPENSION_CHAIN);
        modules.append(MODULE_CADENZA_DOPPIA);
        trans.append(0);
        textures.append(TEXTURE_SUSPENSION_CHAIN);
        modules.append(MODULE_ROMANESCA);
        trans.append(4);
        textures.append(TEXTURE_SUSPENSION_CHAIN);
        modules.append(MODULE_CADENCE_FRENCH_LONG5);
        trans.append(4);
        textures.append(TEXTURE_STYLE_BRISE);
        cadences.append(3);
        modulation_target = 4;
    }
    (modules, trans, textures, cadences, modulation_target)
}

pub fn select_baroque_plan(seed: felt252, melody: @BaroqueMelody) -> BaroquePlan {
    let s: u256 = seed.into();
    let family: u8 = (extract_bits(s, 0, 2) % 3).try_into().unwrap();
    let variant = extract_bits(s, 4, 6);
    let (modules, trans, textures, cadences, modulation_target) = plan_modules_for_family(
        family, variant,
    );

    let mut keys: Array<LocalKey> = ArrayTrait::new();
    let tonic_pc: u8 = (extract_bits(s, 6, 4) % 12).try_into().unwrap();
    let mode_id = *melody.mode_policy;
    let mut i: u32 = 0;
    loop {
        if i >= modules.len() {
            break;
        }
        let t = *trans.at(i);
        let pc = pc_for_degree_offset(tonic_pc, t, mode_id);
        keys.append(LocalKey { tonic_pc: pc, mode_id, degree_offset: t });
        i += 1;
    };

    BaroquePlan {
        phrase_family: family,
        modules: modules.span(),
        local_keys: keys.span(),
        transpositions: trans.span(),
        texture_ids: textures.span(),
        cadence_positions: cadences.span(),
        modulation_target,
    }
}

fn default_key_from_seed(seed: felt252) -> LocalKey {
    let s: u256 = seed.into();
    let tonic_pc: u8 = (extract_bits(s, 6, 4) % 12).try_into().unwrap();
    let mode_pick = extract_bits(s, 10, 2);
    let mode_id = if mode_pick == 0 {
        MODE_NATURAL_MINOR
    } else if mode_pick == 1 {
        MODE_HARMONIC_MINOR
    } else {
        MODE_MAJOR
    };
    LocalKey { tonic_pc, mode_id, degree_offset: 0 }
}

fn anchors_for_family(family: u8, length: u32, mode_id: u8) -> Array<MelodyAnchor> {
    let mut out: Array<MelodyAnchor> = ArrayTrait::new();
    let target = if family == FAMILY_CADENTIAL_STUDY {
        sd(0, 0)
    } else {
        sd(4, 0)
    };
    let last = if length > 0 {
        length - 1
    } else {
        0
    };
    out.append(MelodyAnchor { position: last, target_degree: target, anchor_kind: 0 });
    if mode_id == MODE_HARMONIC_MINOR && length > 2 {
        out.append(MelodyAnchor { position: length - 2, target_degree: sd(6, 1), anchor_kind: 1 });
    }
    out
}

fn total_plan_length(modules: Span<u32>) -> u32 {
    let mut n: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= modules.len() {
            break;
        }
        n += module_by_id(*modules.at(i)).length_units;
        i += 1;
    };
    n
}

// ──────────────────────────────────────────────────────────
// Realization helpers
// ──────────────────────────────────────────────────────────

fn append_structural_note(
    ref events: Array<NoteEvent>,
    d: ScaleDegree,
    key: LocalKey,
    voice_id: u32,
    time: u32,
    duration: u32,
    velocity: u8,
) {
    let tonic = tonic_for_voice(key.tonic_pc, voice_id);
    let pitch = degree_to_keynum_baroque(d, tonic, key.mode_id);
    events.append(NoteEvent { time, duration, pitch, velocity, voice_id });
}

fn append_sonority(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    time_index: u32,
    bass_d: ScaleDegree,
    melody_d: ScaleDegree,
    primary: i32,
    secondary: i32,
    tag: u8,
    texture: u8,
) {
    let time = time_index * DEFAULT_UNIT;
    let dur = if texture == TEXTURE_STYLE_BRISE {
        BRISER_DURATION
    } else {
        DEFAULT_DURATION
    };
    bass.append(bass_d);
    melody.append(melody_d);
    figures.append(
        FiguredSonority {
            time_index, bass_degree: bass_d, primary_interval: primary, secondary_interval: secondary,
            dissonance_tag: tag,
        },
    );

    append_structural_note(ref events, bass_d, key, ROLE_BASS, time, DEFAULT_DURATION, 76);
    append_structural_note(ref events, melody_d, key, ROLE_MELODY, time, dur, 92);

    let alto = sd(bass_d.degree0 + 2, bass_d.alter);
    let tenor = sd(bass_d.degree0 + 4, bass_d.alter);
    append_structural_note(ref events, alto, key, ROLE_ALTO_FILL, time, DEFAULT_DURATION, 66);
    append_structural_note(ref events, tenor, key, ROLE_TENOR_FILL, time, DEFAULT_DURATION, 60);

    if texture == TEXTURE_STYLE_BRISE {
        append_structural_note(ref events, sd(bass_d.degree0 + 6, bass_d.alter), key, ROLE_MELODY, time + 2, 2, 84);
    } else if texture == TEXTURE_STEP_FILL_BASS {
        append_structural_note(ref events, sd(bass_d.degree0 + 1, bass_d.alter), key, ROLE_BASS, time + 2, 2, 62);
    }
}

fn append_cadence_43(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    texture: u8,
    trans: i32,
) {
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(4 + trans, 0), sd(7 + trans, 0), 4, 0, TAG_SUSPENSION_43, texture);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(4 + trans, 0), sd(6 + trans, 0), 3, 0, TAG_NONE, texture);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(0 + trans, 0), sd(0 + trans, 0), 8, 3, TAG_NONE, texture);
    cursor += 1;
}

fn append_cadence_3451(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    texture: u8,
    trans: i32,
    long_five: bool,
) {
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(2 + trans, 0), sd(9 + trans, 0), 6, 0, TAG_NONE, texture);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(3 + trans, 0), sd(7 + trans, 0), 6, 5, TAG_NONE, texture);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(4 + trans, 0), sd(7 + trans, 0), 6, 4, TAG_CADENTIAL_64, texture);
    cursor += 1;
    if long_five {
        append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(4 + trans, 0), sd(6 + trans, 0), 5, 3, TAG_NONE, texture);
        cursor += 1;
    }
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(0 + trans, 0), sd(0 + trans, 0), 8, 3, TAG_NONE, texture);
    cursor += 1;
}

fn append_descending_scale_cadence(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    bass4251: bool,
    trans: i32,
) {
    let b0 = if bass4251 {
        sd(3 + trans, 0)
    } else {
        sd(2 + trans, 0)
    };
    let b1 = if bass4251 {
        sd(1 + trans, 0)
    } else {
        sd(3 + trans, 0)
    };
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, b0, sd(9 + trans, 0), 6, 0, TAG_NONE, TEXTURE_SCALAR_DESCENT);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, b1, sd(8 + trans, 0), 6, 0, TAG_PASSING, TEXTURE_SCALAR_DESCENT);
    cursor += 1;
    let lead = if key.mode_id == MODE_HARMONIC_MINOR {
        sd(6 + trans, 1)
    } else {
        sd(7 + trans, 0)
    };
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(4 + trans, 0), lead, 5, 3, TAG_NONE, TEXTURE_SCALAR_DESCENT);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(0 + trans, 0), sd(0 + trans, 0), 8, 3, TAG_NONE, TEXTURE_SCALAR_DESCENT);
    cursor += 1;
}

fn append_fauxbourdon_76(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    trans: i32,
) {
    let starts = array![0_i32, 1, 2, 3];
    let mut i: u32 = 0;
    loop {
        if i >= starts.len() {
            break;
        }
        let b = *starts.at(i) + trans;
        append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(b, 0), sd(b + 6, 0), 7, 0, TAG_CHAIN_76, TEXTURE_SUSPENSION_CHAIN);
        cursor += 1;
        append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(b, 0), sd(b + 5, 0), 6, 0, TAG_NONE, TEXTURE_SUSPENSION_CHAIN);
        cursor += 1;
        i += 1;
    };
}

fn append_circle_fifths(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    trans: i32,
) {
    let basses = array![0_i32, -2, -1, -3, -2, -4, -3, -5];
    let mut i: u32 = 0;
    loop {
        if i >= basses.len() {
            break;
        }
        let b = *basses.at(i) + trans;
        let tag = if i % 2 == 0 {
            TAG_SUSPENSION_43
        } else {
            TAG_NONE
        };
        let fig = if tag == TAG_SUSPENSION_43 {
            4
        } else {
            3
        };
        append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(b, 0), sd(b + fig - 1, 0), fig, 0, tag, TEXTURE_STEP_FILL_BASS);
        cursor += 1;
        i += 1;
    };
}

fn append_romanesca(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    trans: i32,
) {
    let cells = array![0_i32, -2, -4];
    let mut i: u32 = 0;
    loop {
        if i >= cells.len() {
            break;
        }
        let t = *cells.at(i) + trans;
        append_cadence_43(ref events, ref melody, ref bass, ref figures, key, ref cursor, TEXTURE_SUSPENSION_CHAIN, t);
        i += 1;
    };
}

fn append_cadenza_doppia(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    trans: i32,
) {
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(0 + trans, 0), sd(3 + trans, 1), 4, 2, TAG_RAISED_4, TEXTURE_SUSPENSION_CHAIN);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(1 + trans, 0), sd(4 + trans, 0), 6, 0, TAG_NONE, TEXTURE_SUSPENSION_CHAIN);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(4 + trans, 0), sd(6 + trans, 0), 5, 3, TAG_NONE, TEXTURE_SUSPENSION_CHAIN);
    cursor += 1;
    append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(4 + trans, 0), sd(4 + trans, 0), 8, 3, TAG_NONE, TEXTURE_SUSPENSION_CHAIN);
    cursor += 1;
}

fn append_ascending_fifths(
    ref events: Array<NoteEvent>,
    ref melody: Array<ScaleDegree>,
    ref bass: Array<ScaleDegree>,
    ref figures: Array<FiguredSonority>,
    key: LocalKey,
    ref cursor: u32,
    trans: i32,
) {
    let basses = array![3_i32, 7, 4, 8, 5, 9, 6, 10];
    let mut i: u32 = 0;
    loop {
        if i >= basses.len() {
            break;
        }
        let b = *basses.at(i) + trans;
        append_sonority(ref events, ref melody, ref bass, ref figures, key, cursor, sd(b, 0), sd(b + 4, 0), 5, 0, TAG_NONE, TEXTURE_STEP_FILL_BASS);
        cursor += 1;
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Realization and public generation
// ──────────────────────────────────────────────────────────

pub fn realize_baroque_plan(
    seed: felt252, melody_in: @BaroqueMelody, plan: @BaroquePlan,
) -> BaroqueRealization {
    let mut events: Array<NoteEvent> = ArrayTrait::new();
    let mut melody: Array<ScaleDegree> = ArrayTrait::new();
    let mut bass: Array<ScaleDegree> = ArrayTrait::new();
    let mut figures: Array<FiguredSonority> = ArrayTrait::new();

    let mut cursor: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= plan.modules.len() {
            break;
        }
        let module_id = *plan.modules.at(i);
        let key = *plan.local_keys.at(i);
        let texture = *plan.texture_ids.at(i);
        let trans = *plan.transpositions.at(i);
        if module_id == MODULE_CADENCE_43 {
            append_cadence_43(ref events, ref melody, ref bass, ref figures, key, ref cursor, texture, trans);
        } else if module_id == MODULE_CADENCE_3451 {
            append_cadence_3451(ref events, ref melody, ref bass, ref figures, key, ref cursor, texture, trans, false);
        } else if module_id == MODULE_CADENCE_FRENCH_LONG5 {
            append_cadence_3451(ref events, ref melody, ref bass, ref figures, key, ref cursor, texture, trans, true);
        } else if module_id == MODULE_CADENCE_DESC_3451 {
            append_descending_scale_cadence(ref events, ref melody, ref bass, ref figures, key, ref cursor, false, trans);
        } else if module_id == MODULE_CADENCE_DESC_4251 {
            append_descending_scale_cadence(ref events, ref melody, ref bass, ref figures, key, ref cursor, true, trans);
        } else if module_id == MODULE_CADENZA_DOPPIA {
            append_cadenza_doppia(ref events, ref melody, ref bass, ref figures, key, ref cursor, trans);
        } else if module_id == MODULE_FAUXBOURDON_76 {
            append_fauxbourdon_76(ref events, ref melody, ref bass, ref figures, key, ref cursor, trans);
        } else if module_id == MODULE_CIRCLE_5THS {
            append_circle_fifths(ref events, ref melody, ref bass, ref figures, key, ref cursor, trans);
        } else if module_id == MODULE_ROMANESCA {
            append_romanesca(ref events, ref melody, ref bass, ref figures, key, ref cursor, trans);
        } else {
            append_ascending_fifths(ref events, ref melody, ref bass, ref figures, key, ref cursor, trans);
        }
        i += 1;
    };

    let real = BaroqueRealization {
        seed,
        plan: BaroquePlan {
            phrase_family: *plan.phrase_family,
            modules: *plan.modules,
            local_keys: *plan.local_keys,
            transpositions: *plan.transpositions,
            texture_ids: *plan.texture_ids,
            cadence_positions: *plan.cadence_positions,
            modulation_target: *plan.modulation_target,
        },
        melody: melody.span(),
        bass: bass.span(),
        figures: figures.span(),
        events: events.span(),
        anchor_adjustments: *melody_in.anchor_adjustments,
    };
    assert(validate_baroque_realization(@real), 'baroque invalid');
    real
}

pub fn generate_baroque_cadential_improvisation(seed: felt252) -> BaroqueRealization {
    let key = default_key_from_seed(seed);
    let s: u256 = seed.into();
    let family: u8 = (extract_bits(s, 0, 2) % 3).try_into().unwrap();
    let variant = extract_bits(s, 4, 6);
    let (modules, _trans, _textures, _cadences, _target) = plan_modules_for_family(family, variant);
    let length = total_plan_length(modules.span());
    let anchors = anchors_for_family(family, length, key.mode_id);
    let melody = generate_baroque_melody(seed, key, length, anchors.span());
    let plan = select_baroque_plan(seed, @melody);
    realize_baroque_plan(seed, @melody, @plan)
}

/// Apply anchor-safe stepwise development to the seeded scaffold (EveryNth positions only).
pub fn develop_scaffold_melody(seed: felt252, melody_in: @BaroqueMelody) -> Array<ScaleDegree> {
    let mut plane: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= melody_in.degrees.len() {
            break;
        }
        plane.append((*melody_in.degrees.at(i)).degree0);
        i += 1;
    };
    if plane.len() == 0 {
        return ArrayTrait::new();
    }

    let s: u256 = seed.into();
    let delta: i32 = if extract_bits(s, 20, 1) == 0 {
        -1
    } else {
        1
    };
    let step_op = PlaneOp::EveryNth(EveryNthOp { n: 2, delta });
    let developed_plane = map_where_i32(plane.span(), Selector::EveryNth(2), @step_op);
    degrees_from_plane_with_anchors(@developed_plane, melody_in)
}

fn degrees_from_plane_with_anchors(
    plane: @Array<i32>, melody_in: @BaroqueMelody,
) -> Array<ScaleDegree> {
    let mut out: Array<ScaleDegree> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= plane.len() {
            break;
        }
        let mut degree0 = *plane.at(i);
        let mut alter = (*melody_in.degrees.at(i)).alter;
        let mut ai: u32 = 0;
        loop {
            if ai >= melody_in.anchors.len() {
                break;
            }
            let a = *melody_in.anchors.at(ai);
            if a.position == i {
                degree0 = a.target_degree.degree0;
                alter = a.target_degree.alter;
            }
            ai += 1;
        };
        out.append(sd(degree0, alter));
        i += 1;
    };
    out
}

fn degree_strictly_between(a: ScaleDegree, b: ScaleDegree, mid: ScaleDegree) -> bool {
    let lo = if a.degree0 < b.degree0 {
        a.degree0
    } else {
        b.degree0
    };
    let hi = if a.degree0 > b.degree0 {
        a.degree0
    } else {
        b.degree0
    };
    mid.degree0 > lo && mid.degree0 < hi
}

/// Insert short passing tones from the developed scaffold between stable structural beats.
fn append_passing_tones_from_developed(
    ref events: Array<NoteEvent>,
    structural: Span<ScaleDegree>,
    developed: Span<ScaleDegree>,
    figures: Span<FiguredSonority>,
    key: LocalKey,
) {
    let mut i: u32 = 0;
    loop {
        if i + 1 >= figures.len() || i >= developed.len() || i >= structural.len() {
            break;
        }
        let f0 = *figures.at(i);
        let f1 = *figures.at(i + 1);
        if f0.dissonance_tag != TAG_NONE || f1.dissonance_tag != TAG_NONE {
            i += 1;
            continue;
        }
        let sa = *structural.at(i);
        let sb = *structural.at(i + 1);
        let da = *developed.at(i);
        if da.degree0 == sa.degree0 && da.alter == sa.alter {
            i += 1;
            continue;
        }
        if !degree_strictly_between(sa, sb, da) {
            i += 1;
            continue;
        }
        let time = f0.time_index * DEFAULT_UNIT + 2;
        append_structural_note(ref events, da, key, ROLE_MELODY, time, 2, 72);
        i += 1;
    };
}

fn clone_note_events(events: Span<NoteEvent>) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        out.append(*events.at(i));
        i += 1;
    };
    out
}

/// Cadential improvisation with transform-developed scaffold passing tones on the upper voice.
pub fn generate_baroque_cadential_improvisation_with_transforms(seed: felt252) -> BaroqueRealization {
    let key = default_key_from_seed(seed);
    let s: u256 = seed.into();
    let family: u8 = (extract_bits(s, 0, 2) % 3).try_into().unwrap();
    let variant = extract_bits(s, 4, 6);
    let (modules, _trans, _textures, _cadences, _target) = plan_modules_for_family(family, variant);
    let length = total_plan_length(modules.span());
    let anchors = anchors_for_family(family, length, key.mode_id);
    let melody = generate_baroque_melody(seed, key, length, anchors.span());
    let developed = develop_scaffold_melody(seed, @melody);
    let plan = select_baroque_plan(seed, @melody);
    let base = realize_baroque_plan(seed, @melody, @plan);
    let mut events = clone_note_events(base.events);
    append_passing_tones_from_developed(
        ref events, base.melody, developed.span(), base.figures, key,
    );
    BaroqueRealization {
        seed: base.seed,
        plan: base.plan,
        melody: base.melody,
        bass: base.bass,
        figures: base.figures,
        events: events.span(),
        anchor_adjustments: base.anchor_adjustments,
    }
}

pub fn baroque_to_note_events(realization: @BaroqueRealization) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= realization.events.len() {
            break;
        }
        out.append(*realization.events.at(i));
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Validation and traits
// ──────────────────────────────────────────────────────────

fn figured_interval_is_stable(interval_number: i32) -> bool {
    let dist = interval_number - 1;
    let cls = abs_i32(dist) % 7;
    cls == 0 || cls == 2 || cls == 4 || cls == 5
}

fn figure_has_resolution(figures: Span<FiguredSonority>, i: u32, from_interval: i32, to_interval: i32) -> bool {
    if i + 1 >= figures.len() {
        return false;
    }
    let a = *figures.at(i);
    let b = *figures.at(i + 1);
    a.primary_interval == from_interval && b.primary_interval == to_interval
}

fn plan_has_module(plan: @BaroquePlan, module_id: u32) -> bool {
    let mut found = false;
    let mut i: u32 = 0;
    loop {
        if i >= plan.modules.len() {
            break;
        }
        if *plan.modules.at(i) == module_id {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

pub fn validate_baroque_realization(realization: @BaroqueRealization) -> bool {
    if realization.events.len() == 0 || realization.bass.len() == 0 || realization.figures.len() == 0 {
        return false;
    }
    if realization.bass.len() != realization.figures.len() {
        return false;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i >= realization.plan.modules.len() {
            break;
        }
        if !module_exists(*realization.plan.modules.at(i)) {
            ok = false;
            break;
        }
        if i > 0 {
            let prev_key = *realization.plan.local_keys.at(i - 1);
            let key = *realization.plan.local_keys.at(i);
            if key.degree_offset != prev_key.degree_offset || key.tonic_pc != prev_key.tonic_pc {
                let prev_module = *realization.plan.modules.at(i - 1);
                if prev_module != MODULE_CADENZA_DOPPIA {
                    ok = false;
                    break;
                }
            }
        }
        i += 1;
    };
    let has_cadenza_doppia = plan_has_module(realization.plan, MODULE_CADENZA_DOPPIA);
    i = 0;
    loop {
        if i >= realization.figures.len() {
            break;
        }
        let f = *realization.figures.at(i);
        if figured_interval_is_stable(f.primary_interval) {
            // stable by default
        } else if f.dissonance_tag == TAG_SUSPENSION_43 {
            if !figure_has_resolution(*realization.figures, i, 4, 3) {
                ok = false;
                break;
            }
        } else if f.dissonance_tag == TAG_CHAIN_76 {
            if !figure_has_resolution(*realization.figures, i, 7, 6) {
                ok = false;
                break;
            }
        } else if f.dissonance_tag == TAG_PASSING || f.dissonance_tag == TAG_CADENTIAL_64 {
            // explicitly tagged Baroque dissonance / alteration.
        } else if f.dissonance_tag == TAG_RAISED_4 {
            if !has_cadenza_doppia {
                ok = false;
                break;
            }
        } else {
            ok = false;
            break;
        }
        i += 1;
    };
    let last_bass = *realization.bass.at(realization.bass.len() - 1);
    if (last_bass.degree0 % 7) != 0 && (last_bass.degree0 % 7) != 4 {
        ok = false;
    }
    ok
}

fn primary_cadence_type(plan: @BaroquePlan) -> u32 {
    let mut out = 0;
    let mut i: u32 = 0;
    loop {
        if i >= plan.modules.len() {
            break;
        }
        let m = *plan.modules.at(i);
        if m < 10 {
            out = m;
        }
        i += 1;
    };
    out
}

fn primary_sequence_type(plan: @BaroquePlan) -> u32 {
    let mut out = 0;
    let mut i: u32 = 0;
    loop {
        if i >= plan.modules.len() {
            break;
        }
        let m = *plan.modules.at(i);
        if m >= 10 {
            out = m;
            break;
        }
        i += 1;
    };
    out
}

pub fn baroque_traits(realization: @BaroqueRealization) -> BaroqueTraits {
    let first_module = if realization.plan.modules.len() > 0 {
        *realization.plan.modules.at(0)
    } else {
        0
    };
    let texture = if realization.plan.texture_ids.len() > 0 {
        *realization.plan.texture_ids.at(0)
    } else {
        TEXTURE_PLAIN
    };
    let mode = if realization.plan.local_keys.len() > 0 {
        (*realization.plan.local_keys.at(0)).mode_id
    } else {
        MODE_MAJOR
    };
    BaroqueTraits {
        phrase_family: *realization.plan.phrase_family,
        primary_module: first_module,
        cadence_type: primary_cadence_type(realization.plan),
        sequence_type: primary_sequence_type(realization.plan),
        texture,
        minor_scale_policy: mode,
        modulation_target: *realization.plan.modulation_target,
        anchor_adjustments: *realization.anchor_adjustments,
        event_count: realization.events.len(),
    }
}

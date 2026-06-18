//! Core data types for the v2 melodic ornamentation engine (§4–§6).

use core::array::ArrayTrait;

pub const DEGREE_SENTINEL: i32 = -999;
pub const DEFAULT_VELOCITY: u8 = 90;

// ── Melodic roles (§4.3) ──────────────────────────────────

pub const ROLE_STRUCTURAL: u8 = 0;
pub const ROLE_PASSING: u8 = 1;
pub const ROLE_NEIGHBOR: u8 = 2;
pub const ROLE_DOUBLE_NEIGHBOR: u8 = 3;
pub const ROLE_SUSPENSION: u8 = 4;
pub const ROLE_RETARDATION: u8 = 5;
pub const ROLE_ANTICIPATION: u8 = 6;
pub const ROLE_APPOGGIATURA: u8 = 7;
pub const ROLE_ESCAPE: u8 = 8;
pub const ROLE_ECHAPPEE: u8 = 9;
pub const ROLE_CAMBIATA: u8 = 10;
pub const ROLE_MORDENT: u8 = 11;
pub const ROLE_TURN: u8 = 12;
pub const ROLE_TRILL: u8 = 13;
pub const ROLE_GRACE: u8 = 14;
pub const ROLE_CHROMATIC_APPROACH: u8 = 15;
pub const ROLE_ENCLOSURE: u8 = 16;
pub const ROLE_ARPEGGIATION: u8 = 17;
pub const ROLE_PEDAL: u8 = 18;
pub const ROLE_GENERATED_SURFACE: u8 = 19;

// ── Ornament kinds (§6) ───────────────────────────────────

pub const ORN_NONE: u8 = 0;
pub const ORN_PASSING_ASC: u8 = 1;
pub const ORN_PASSING_DESC: u8 = 2;
pub const ORN_NEIGHBOR_UPPER: u8 = 3;
pub const ORN_NEIGHBOR_LOWER: u8 = 4;
pub const ORN_DOUBLE_NEIGHBOR_UF: u8 = 5;
pub const ORN_DOUBLE_NEIGHBOR_LF: u8 = 6;
pub const ORN_ANTICIPATION: u8 = 7;
pub const ORN_SUSPENSION_43: u8 = 8;
pub const ORN_SUSPENSION_76: u8 = 9;
pub const ORN_SUSPENSION_98: u8 = 10;
pub const ORN_SUSPENSION_65: u8 = 11;
pub const ORN_SUSPENSION_23_BASS: u8 = 12;
pub const ORN_RETARDATION: u8 = 13;
pub const ORN_APPOGGIATURA_UPPER: u8 = 14;
pub const ORN_APPOGGIATURA_LOWER: u8 = 15;
pub const ORN_ESCAPE_UPPER: u8 = 16;
pub const ORN_ESCAPE_LOWER: u8 = 17;
pub const ORN_ECHAPPEE_UPPER: u8 = 18;
pub const ORN_ECHAPPEE_LOWER: u8 = 19;
pub const ORN_CAMBIATA: u8 = 20;
pub const ORN_MORDENT_UPPER: u8 = 21;
pub const ORN_MORDENT_LOWER: u8 = 22;
pub const ORN_TURN_UPPER: u8 = 23;
pub const ORN_TURN_LOWER: u8 = 24;
pub const ORN_TRILL_UPPER: u8 = 25;
pub const ORN_TRILL_LOWER: u8 = 26;
pub const ORN_ACCIACCATURA_UPPER: u8 = 27;
pub const ORN_ACCIACCATURA_LOWER: u8 = 28;
pub const ORN_CHROMATIC_APPROACH_UPPER: u8 = 29;
pub const ORN_CHROMATIC_APPROACH_LOWER: u8 = 30;
pub const ORN_ENCLOSURE_UF: u8 = 31;
pub const ORN_ENCLOSURE_LF: u8 = 32;
pub const ORN_ARPEGGIATION_UP: u8 = 33;
pub const ORN_ARPEGGIATION_DOWN: u8 = 34;
pub const ORN_PEDAL_HOLD: u8 = 35;

pub const ORNAMENT_KIND_COUNT: u8 = 36;

// ── Ornament families (§5) ──────────────────────────────────

pub const FAMILY_STEPWISE_CONNECTOR: u8 = 0;
pub const FAMILY_NEIGHBOR_DECORATION: u8 = 1;
pub const FAMILY_DELAY_RESOLUTION: u8 = 2;
pub const FAMILY_EARLY_ARRIVAL: u8 = 3;
pub const FAMILY_DEPARTURE_GESTURE: u8 = 4;
pub const FAMILY_RAPID_SURFACE: u8 = 5;
pub const FAMILY_HARMONIC_UNFOLDING: u8 = 6;
pub const FAMILY_REPETITION_HOLD: u8 = 7;
pub const FAMILY_CHROMATIC_APPROACH: u8 = 8;
pub const FAMILY_CANON_AWARE: u8 = 9;

// ── Preservation levels (§9.2) ──────────────────────────────

pub const PRESERVE_EXACT: u8 = 0;
pub const PRESERVE_MIRRORED: u8 = 1;
pub const PRESERVE_PARTIAL: u8 = 2;
pub const PRESERVE_NO: u8 = 3;

// ── Pitch map for AppliedTransform (§8.2) ───────────────────

pub const PITCH_MAP_IDENTITY: u8 = 0;
pub const PITCH_MAP_TRANSPOSE: u8 = 1;
pub const PITCH_MAP_INVERT: u8 = 2;
pub const PITCH_MAP_RETROGRADE: u8 = 3;
pub const PITCH_MAP_RETRO_INV: u8 = 4;
pub const PITCH_MAP_AUGMENT: u8 = 5;
pub const PITCH_MAP_DIMINISH: u8 = 6;
pub const PITCH_MAP_MODAL_ROTATE: u8 = 7;
pub const PITCH_MAP_OTHER: u8 = 8;

// ── Boundary policy (§10.2) ───────────────────────────────

pub const BOUNDARY_PRESERVE_CELL: u8 = 0;
pub const BOUNDARY_ALLOW_PICKUP: u8 = 1;
pub const BOUNDARY_ALLOW_SUSPENSION: u8 = 2;
pub const BOUNDARY_ALLOW_EXPANSION: u8 = 3;

// ── Collision policy (§10.1) ────────────────────────────────

pub const COLLISION_PERFECT: u8 = 0;
pub const COLLISION_COVER_OVERLAP: u8 = 1;
pub const COLLISION_COVER_GAPS: u8 = 2;

// ── Output mode (§14) ───────────────────────────────────────

pub const OUTPUT_SYMBOLIC: u8 = 0;
pub const OUTPUT_MIDI: u8 = 1;
pub const OUTPUT_ONCHAIN_COMPACT: u8 = 2;

// ── Canon workflow (§8.3) ───────────────────────────────────

pub const WORKFLOW_CANON_FIRST: u8 = 0;
pub const WORKFLOW_ORNAMENT_FIRST: u8 = 1;

// ── Selection source (§12.4) ────────────────────────────────

pub const SELECTION_SEEDED: u8 = 0;
pub const SELECTION_LIVE: u8 = 1;

#[derive(Copy, Drop)]
pub struct V2Pitch {
    pub pc: u8,
    pub octave: u8,
    pub degree: i32,
    pub midi: u8,
}

#[derive(Copy, Drop)]
pub struct V2NoteEvent {
    pub pitch: V2Pitch,
    pub start: u32,
    pub duration: u32,
    pub velocity: u8,
    pub role: u8,
    pub ornament_id: u32,
    pub voice_index: u32,
}

#[derive(Copy, Drop)]
pub struct HarmonyEvent {
    pub root_pc: u8,
    pub bass_pc: u8,
    pub start: u32,
    pub duration: u32,
    pub function_label: u8,
}

#[derive(Copy, Drop)]
pub struct OrnamentTransformBehavior {
    pub transposition: u8,
    pub inversion: u8,
    pub retrograde: u8,
    pub augmentation: u8,
    pub diminution: u8,
}

#[derive(Copy, Drop)]
pub struct AppliedTransform {
    pub delay: u32,
    pub pitch_map: u8,
    pub transpose_in_pc_space: bool,
    pub inversion_axis_pc: u8,
    pub rhythmic_num: u32,
    pub rhythmic_den: u32,
}

#[derive(Copy, Drop)]
pub struct MusicalTile {
    pub start: u32,
    pub period: u32,
    pub voice_index: u32,
}

#[derive(Copy, Drop)]
pub struct TilingContext {
    pub period: u32,
    pub collision_policy: u8,
}

#[derive(Copy, Drop)]
pub struct VerticalIntervalPolicy {
    pub allow_unisons: bool,
    pub allow_seconds_on_weak: bool,
    pub allow_sevenths_on_weak: bool,
    pub allow_prepared_dissonance: bool,
    pub max_simultaneous_dissonances: u8,
    pub avoid_parallel_perfects: bool,
}

#[derive(Copy, Drop)]
pub struct OrnamentConstraintSet {
    pub strict_canon: bool,
    pub preserve_tile_boundary: bool,
    pub strict_diatonic: bool,
    pub vertical: VerticalIntervalPolicy,
}

#[derive(Copy, Drop)]
pub struct OrnamentStyleProfile {
    pub name: felt252,
    pub density: u8,
    pub chromaticism: u8,
    pub syncopation: u8,
    pub strict_counterpoint: u8,
    pub jazz_enclosure_bias: u8,
    pub baroque_ornament_bias: u8,
    pub suspension_bias: u8,
    pub neighbor_bias: u8,
    pub passing_bias: u8,
    pub grace_note_bias: u8,
    pub trill_bias: u8,
    pub turn_bias: u8,
    pub chromatic_approach_bias: u8,
    pub arpeggiation_bias: u8,
    pub pedal_bias: u8,
    pub max_ornaments_per_bar: u8,
    pub max_surface_notes_per_anchor: u8,
    /// Number of alternating anchor/aux note pairs in a trill (2 = one pair, 4 = two pairs, etc.).
    /// Must be even and >= 2.  Default 4. Values 6-12 produce faster trills.
    pub trill_subdivisions: u8,
    /// How many individual trill notes to emit before holding the anchor for the rest of the beat.
    /// 0 = fill the entire duration (current behaviour). 2 = one flick then hold. 4 = two flicks.
    pub trill_count: u8,
}

#[derive(Copy, Drop)]
pub struct OrnamentContext {
    pub anchor_index: u32,
    pub metric_position: u32,
    pub beat_strength: u8,
    pub available_duration: u32,
    pub subdivision: u32,
    pub scale_len: u32,
    pub voice_index: u32,
    pub canon_voice_index: u32,
    pub seed_state: u32,
    pub mode_id: u8,
    pub key_pc: u8,
    pub has_prev_anchor: bool,
    pub has_next_anchor: bool,
    pub has_current_harmony: bool,
    pub has_prev_harmony: bool,
    pub has_next_harmony: bool,
    pub has_applied_transform: bool,
    pub has_tile: bool,
    pub sounding_voice_count: u32,
    /// Trill subdivision count sourced from OrnamentStyleProfile.trill_subdivisions.
    pub trill_subdivisions: u8,
    /// Active trill note count before the anchor hold tail. 0 = fill all (same as trill_subdivisions).
    pub trill_count: u8,
}

#[derive(Copy, Drop)]
pub struct OrnamentConfig {
    pub selection_kind: u8,
    pub seed: felt252,
    pub canon_workflow: u8,
    pub boundary_policy: u8,
    pub output_mode: u8,
    pub style: OrnamentStyleProfile,
    pub constraints: OrnamentConstraintSet,
}

#[derive(Copy, Drop)]
pub struct V2Voice {
    pub voice_index: u32,
    pub applied: AppliedTransform,
}

#[derive(Copy, Drop)]
pub struct OrnamentEvent {
    pub kind: u8,
    pub anchor_index: u32,
    pub param_a: u32,
    pub param_b: u32,
    pub param_c: u32,
}

#[derive(Drop)]
pub struct OrnamentPhraseResult {
    pub events: Array<V2NoteEvent>,
    pub rules: Array<OrnamentEvent>,
    pub final_seed_state: u32,
}

#[derive(Drop)]
pub struct OrnamentCanonResult {
    pub voices: Array<V2Voice>,
    pub events: Array<V2NoteEvent>,
    pub final_seed_state: u32,
}

pub fn default_vertical_policy() -> VerticalIntervalPolicy {
    VerticalIntervalPolicy {
        allow_unisons: false,
        allow_seconds_on_weak: true,
        allow_sevenths_on_weak: false,
        allow_prepared_dissonance: true,
        max_simultaneous_dissonances: 1,
        avoid_parallel_perfects: true,
    }
}

pub fn default_constraints() -> OrnamentConstraintSet {
    OrnamentConstraintSet {
        strict_canon: false,
        preserve_tile_boundary: true,
        strict_diatonic: true,
        vertical: default_vertical_policy(),
    }
}

pub fn pitch_from_midi(midi: u8) -> V2Pitch {
    V2Pitch {
        pc: midi % 12,
        octave: midi / 12,
        degree: DEGREE_SENTINEL,
        midi,
    }
}

pub fn pitch_from_degree(degree: i32, midi: u8) -> V2Pitch {
    V2Pitch { pc: midi % 12, octave: midi / 12, degree, midi }
}

pub fn structural_event(
    pitch: V2Pitch, start: u32, duration: u32, voice_index: u32,
) -> V2NoteEvent {
    V2NoteEvent {
        pitch,
        start,
        duration,
        velocity: DEFAULT_VELOCITY,
        role: ROLE_STRUCTURAL,
        ornament_id: 0,
        voice_index,
    }
}

pub fn surface_event(
    pitch: V2Pitch,
    start: u32,
    duration: u32,
    role: u8,
    ornament_id: u32,
    voice_index: u32,
) -> V2NoteEvent {
    V2NoteEvent {
        pitch,
        start,
        duration,
        velocity: DEFAULT_VELOCITY,
        role,
        ornament_id,
        voice_index,
    }
}

pub fn family_for_kind(kind: u8) -> u8 {
    if kind == ORN_PASSING_ASC || kind == ORN_PASSING_DESC {
        FAMILY_STEPWISE_CONNECTOR
    } else if kind == ORN_NEIGHBOR_UPPER
        || kind == ORN_NEIGHBOR_LOWER
        || kind == ORN_DOUBLE_NEIGHBOR_UF
        || kind == ORN_DOUBLE_NEIGHBOR_LF
        || kind == ORN_MORDENT_UPPER
        || kind == ORN_MORDENT_LOWER
        || kind == ORN_TURN_UPPER
        || kind == ORN_TURN_LOWER {
        FAMILY_NEIGHBOR_DECORATION
    } else if kind == ORN_SUSPENSION_43
        || kind == ORN_SUSPENSION_76
        || kind == ORN_SUSPENSION_98
        || kind == ORN_SUSPENSION_65
        || kind == ORN_SUSPENSION_23_BASS
        || kind == ORN_RETARDATION {
        FAMILY_DELAY_RESOLUTION
    } else if kind == ORN_ANTICIPATION {
        FAMILY_EARLY_ARRIVAL
    } else if kind == ORN_APPOGGIATURA_UPPER
        || kind == ORN_APPOGGIATURA_LOWER
        || kind == ORN_ESCAPE_UPPER
        || kind == ORN_ESCAPE_LOWER
        || kind == ORN_ECHAPPEE_UPPER
        || kind == ORN_ECHAPPEE_LOWER
        || kind == ORN_CAMBIATA {
        FAMILY_DEPARTURE_GESTURE
    } else if kind == ORN_TRILL_UPPER
        || kind == ORN_TRILL_LOWER
        || kind == ORN_ACCIACCATURA_UPPER
        || kind == ORN_ACCIACCATURA_LOWER {
        FAMILY_RAPID_SURFACE
    } else if kind == ORN_ARPEGGIATION_UP || kind == ORN_ARPEGGIATION_DOWN {
        FAMILY_HARMONIC_UNFOLDING
    } else if kind == ORN_PEDAL_HOLD {
        FAMILY_REPETITION_HOLD
    } else if kind == ORN_CHROMATIC_APPROACH_UPPER
        || kind == ORN_CHROMATIC_APPROACH_LOWER
        || kind == ORN_ENCLOSURE_UF
        || kind == ORN_ENCLOSURE_LF {
        FAMILY_CHROMATIC_APPROACH
    } else {
        FAMILY_CANON_AWARE
    }
}

pub fn transform_behavior_for_kind(kind: u8) -> OrnamentTransformBehavior {
    if kind == ORN_PASSING_ASC || kind == ORN_PASSING_DESC {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_EXACT,
            retrograde: PRESERVE_EXACT,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_NEIGHBOR_UPPER
        || kind == ORN_NEIGHBOR_LOWER
        || kind == ORN_MORDENT_UPPER
        || kind == ORN_MORDENT_LOWER
        || kind == ORN_TRILL_UPPER
        || kind == ORN_TRILL_LOWER {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_MIRRORED,
            retrograde: PRESERVE_EXACT,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_DOUBLE_NEIGHBOR_UF || kind == ORN_DOUBLE_NEIGHBOR_LF {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_MIRRORED,
            retrograde: PRESERVE_EXACT,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_SUSPENSION_43
        || kind == ORN_SUSPENSION_76
        || kind == ORN_SUSPENSION_98
        || kind == ORN_SUSPENSION_65
        || kind == ORN_SUSPENSION_23_BASS {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_PARTIAL,
            retrograde: PRESERVE_NO,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_RETARDATION {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_PARTIAL,
            retrograde: PRESERVE_NO,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_ANTICIPATION {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_EXACT,
            retrograde: PRESERVE_NO,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_APPOGGIATURA_UPPER || kind == ORN_APPOGGIATURA_LOWER {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_MIRRORED,
            retrograde: PRESERVE_PARTIAL,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_ESCAPE_UPPER || kind == ORN_ESCAPE_LOWER {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_MIRRORED,
            retrograde: PRESERVE_PARTIAL,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_ECHAPPEE_UPPER || kind == ORN_ECHAPPEE_LOWER {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_MIRRORED,
            retrograde: PRESERVE_PARTIAL,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_CAMBIATA {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_MIRRORED,
            retrograde: PRESERVE_NO,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_TURN_UPPER || kind == ORN_TURN_LOWER {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_MIRRORED,
            retrograde: PRESERVE_EXACT,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    } else if kind == ORN_ARPEGGIATION_UP || kind == ORN_ARPEGGIATION_DOWN {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_PARTIAL,
            retrograde: PRESERVE_PARTIAL,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_EXACT,
        }
    } else {
        OrnamentTransformBehavior {
            transposition: PRESERVE_EXACT,
            inversion: PRESERVE_EXACT,
            retrograde: PRESERVE_EXACT,
            augmentation: PRESERVE_EXACT,
            diminution: PRESERVE_PARTIAL,
        }
    }
}

pub fn default_boundary_for_kind(kind: u8) -> u8 {
    if kind == ORN_ANTICIPATION {
        BOUNDARY_ALLOW_PICKUP
    } else if kind == ORN_SUSPENSION_43
        || kind == ORN_SUSPENSION_76
        || kind == ORN_SUSPENSION_98
        || kind == ORN_SUSPENSION_65
        || kind == ORN_SUSPENSION_23_BASS
        || kind == ORN_RETARDATION
        || kind == ORN_PEDAL_HOLD {
        BOUNDARY_ALLOW_SUSPENSION
    } else {
        BOUNDARY_PRESERVE_CELL
    }
}

pub fn all_enabled_ornaments() -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut k: u8 = 1;
    loop {
        if k >= ORNAMENT_KIND_COUNT {
            break;
        }
        out.append(k);
        k += 1;
    };
    out
}

pub fn minimal_viable_ornaments() -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    out.append(ORN_PASSING_ASC);
    out.append(ORN_PASSING_DESC);
    out.append(ORN_NEIGHBOR_UPPER);
    out.append(ORN_NEIGHBOR_LOWER);
    out.append(ORN_DOUBLE_NEIGHBOR_UF);
    out.append(ORN_ANTICIPATION);
    out.append(ORN_SUSPENSION_43);
    out.append(ORN_RETARDATION);
    out.append(ORN_APPOGGIATURA_UPPER);
    out.append(ORN_ESCAPE_UPPER);
    out.append(ORN_CHROMATIC_APPROACH_UPPER);
    out.append(ORN_ENCLOSURE_UF);
    out.append(ORN_ARPEGGIATION_UP);
    out
}

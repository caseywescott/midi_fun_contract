//! Curated single-ornament examples for demos, docs, and MIDI export.
//!
//! Each kind uses hand-tuned degrees, durations, and harmony stubs so
//! `ornament_generate` produces a representative contour in C Ionian.

use core::array::ArrayTrait;
use koji::composition::ornamentation_v2::ornaments::ornament_generate;
use koji::composition::ornamentation_v2::types::{
    OrnamentContext, V2NoteEvent, ORN_ACCIACCATURA_LOWER, ORN_ACCIACCATURA_UPPER,
    ORN_ANTICIPATION, ORN_APPOGGIATURA_LOWER, ORN_APPOGGIATURA_UPPER, ORN_ARPEGGIATION_DOWN,
    ORN_ARPEGGIATION_UP, ORN_CAMBIATA, ORN_CHROMATIC_APPROACH_LOWER,
    ORN_CHROMATIC_APPROACH_UPPER, ORN_DOUBLE_NEIGHBOR_LF, ORN_DOUBLE_NEIGHBOR_UF,
    ORN_ECHAPPEE_LOWER, ORN_ECHAPPEE_UPPER, ORN_ENCLOSURE_LF, ORN_ENCLOSURE_UF,
    ORN_ESCAPE_LOWER, ORN_ESCAPE_UPPER, ORN_MORDENT_LOWER, ORN_MORDENT_UPPER,
    ORN_NEIGHBOR_LOWER, ORN_NEIGHBOR_UPPER, ORN_PASSING_ASC, ORN_PASSING_DESC,
    ORN_PEDAL_HOLD, ORN_RETARDATION, ORN_SUSPENSION_23_BASS, ORN_SUSPENSION_43,
    ORN_SUSPENSION_65, ORN_SUSPENSION_76, ORN_SUSPENSION_98, ORN_TRILL_LOWER,
    ORN_TRILL_UPPER, ORN_TURN_LOWER, ORN_TURN_UPPER, ORNAMENT_KIND_COUNT,
};

const SHOWCASE_TONIC: u8 = 60;
const SHOWCASE_MODE: u8 = 0;

fn triad_c() -> Array<u8> {
    array![0_u8, 4, 7]
}

fn triad_f() -> Array<u8> {
    array![5_u8, 9, 0]
}

fn triad_g() -> Array<u8> {
    array![7_u8, 11, 2]
}

fn base_ctx(
    anchor_index: u32,
    dur: u32,
    has_prev: bool,
    has_next: bool,
    has_curr_h: bool,
    has_prev_h: bool,
    has_next_h: bool,
) -> OrnamentContext {
    OrnamentContext {
        anchor_index,
        metric_position: 0,
        beat_strength: 80,
        available_duration: dur,
        subdivision: dur / 4,
        scale_len: 7,
        voice_index: 0,
        canon_voice_index: 0,
        seed_state: 7,
        mode_id: SHOWCASE_MODE,
        key_pc: 0,
        has_prev_anchor: has_prev,
        has_next_anchor: has_next,
        has_current_harmony: has_curr_h,
        has_prev_harmony: has_prev_h,
        has_next_harmony: has_next_h,
        has_applied_transform: false,
        has_tile: false,
        sounding_voice_count: 0,
    }
}

fn gen(
    kind: u8,
    ctx: OrnamentContext,
    anchor_deg: i32,
    prev_deg: i32,
    next_deg: i32,
    dur: u32,
    bass_pc: u8,
    chord: Span<u8>,
    prev_chord: Span<u8>,
    next_chord: Span<u8>,
) -> Array<V2NoteEvent> {
    ornament_generate(
        kind,
        ctx,
        anchor_deg,
        prev_deg,
        next_deg,
        0,
        dur,
        SHOWCASE_TONIC,
        chord,
        bass_pc,
        prev_chord,
        next_chord,
        kind.into(),
    )
}

/// All showcase ornament kind ids (1..35).
pub fn showcase_kind_ids() -> Array<u8> {
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

/// Human-readable slug for filenames (ASCII felt252).
pub fn showcase_kind_slug(kind: u8) -> felt252 {
    if kind == ORN_PASSING_ASC {
        'passing_asc'
    } else if kind == ORN_PASSING_DESC {
        'passing_desc'
    } else if kind == ORN_NEIGHBOR_UPPER {
        'neighbor_upper'
    } else if kind == ORN_NEIGHBOR_LOWER {
        'neighbor_lower'
    } else if kind == ORN_DOUBLE_NEIGHBOR_UF {
        'double_neighbor_uf'
    } else if kind == ORN_DOUBLE_NEIGHBOR_LF {
        'double_neighbor_lf'
    } else if kind == ORN_ANTICIPATION {
        'anticipation'
    } else if kind == ORN_SUSPENSION_43 {
        'suspension_43'
    } else if kind == ORN_SUSPENSION_76 {
        'suspension_76'
    } else if kind == ORN_SUSPENSION_98 {
        'suspension_98'
    } else if kind == ORN_SUSPENSION_65 {
        'suspension_65'
    } else if kind == ORN_SUSPENSION_23_BASS {
        'suspension_23_bass'
    } else if kind == ORN_RETARDATION {
        'retardation'
    } else if kind == ORN_APPOGGIATURA_UPPER {
        'appoggiatura_upper'
    } else if kind == ORN_APPOGGIATURA_LOWER {
        'appoggiatura_lower'
    } else if kind == ORN_ESCAPE_UPPER {
        'escape_upper'
    } else if kind == ORN_ESCAPE_LOWER {
        'escape_lower'
    } else if kind == ORN_ECHAPPEE_UPPER {
        'echappee_upper'
    } else if kind == ORN_ECHAPPEE_LOWER {
        'echappee_lower'
    } else if kind == ORN_CAMBIATA {
        'cambiata'
    } else if kind == ORN_MORDENT_UPPER {
        'mordent_upper'
    } else if kind == ORN_MORDENT_LOWER {
        'mordent_lower'
    } else if kind == ORN_TURN_UPPER {
        'turn_upper'
    } else if kind == ORN_TURN_LOWER {
        'turn_lower'
    } else if kind == ORN_TRILL_UPPER {
        'trill_upper'
    } else if kind == ORN_TRILL_LOWER {
        'trill_lower'
    } else if kind == ORN_ACCIACCATURA_UPPER {
        'acciaccatura_upper'
    } else if kind == ORN_ACCIACCATURA_LOWER {
        'acciaccatura_lower'
    } else if kind == ORN_CHROMATIC_APPROACH_UPPER {
        'chromatic_approach_upper'
    } else if kind == ORN_CHROMATIC_APPROACH_LOWER {
        'chromatic_approach_lower'
    } else if kind == ORN_ENCLOSURE_UF {
        'enclosure_uf'
    } else if kind == ORN_ENCLOSURE_LF {
        'enclosure_lf'
    } else if kind == ORN_ARPEGGIATION_UP {
        'arpeggiation_up'
    } else if kind == ORN_ARPEGGIATION_DOWN {
        'arpeggiation_down'
    } else if kind == ORN_PEDAL_HOLD {
        'pedal_hold'
    } else {
        'unknown'
    }
}

/// Generate a single-ornament surface for one kind. Returns empty if kind is invalid.
pub fn showcase_events_for_kind(kind: u8) -> Array<V2NoteEvent> {
    let c = triad_c();
    let f = triad_f();
    let g = triad_g();
    if kind == ORN_PASSING_ASC {
        return gen(
            kind,
            base_ctx(1, 8, true, true, false, false, false),
            2,
            0,
            4,
            8,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_PASSING_DESC {
        return gen(
            kind,
            base_ctx(1, 8, true, true, false, false, false),
            2,
            4,
            0,
            8,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_NEIGHBOR_UPPER || kind == ORN_NEIGHBOR_LOWER {
        return gen(
            kind,
            base_ctx(0, 12, false, true, false, false, false),
            4,
            4,
            7,
            12,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_DOUBLE_NEIGHBOR_UF || kind == ORN_DOUBLE_NEIGHBOR_LF {
        return gen(
            kind,
            base_ctx(0, 16, false, true, false, false, false),
            4,
            4,
            7,
            16,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_ANTICIPATION {
        return gen(
            kind,
            base_ctx(1, 8, true, true, true, false, true),
            2,
            0,
            4,
            8,
            0,
            c.span(),
            c.span(),
            g.span(),
        );
    }
    if kind == ORN_SUSPENSION_43 {
        return gen(
            kind,
            base_ctx(1, 12, true, true, true, true, false),
            3,
            3,
            0,
            12,
            0,
            c.span(),
            c.span(),
            f.span(),
        );
    }
    if kind == ORN_SUSPENSION_76 {
        return gen(
            kind,
            base_ctx(1, 12, true, true, true, true, false),
            4,
            4,
            2,
            12,
            0,
            c.span(),
            c.span(),
            f.span(),
        );
    }
    if kind == ORN_SUSPENSION_98 {
        return gen(
            kind,
            base_ctx(1, 12, true, true, true, true, false),
            1,
            1,
            0,
            12,
            0,
            c.span(),
            c.span(),
            f.span(),
        );
    }
    if kind == ORN_SUSPENSION_65 {
        return gen(
            kind,
            base_ctx(1, 12, true, true, true, true, false),
            0,
            0,
            4,
            12,
            6,
            f.span(),
            c.span(),
            g.span(),
        );
    }
    if kind == ORN_SUSPENSION_23_BASS {
        return gen(
            kind,
            base_ctx(1, 12, true, true, true, true, false),
            0,
            0,
            2,
            12,
            0,
            c.span(),
            c.span(),
            g.span(),
        );
    }
    if kind == ORN_RETARDATION {
        return gen(
            kind,
            base_ctx(1, 12, true, true, true, true, false),
            4,
            4,
            7,
            12,
            0,
            f.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_APPOGGIATURA_UPPER || kind == ORN_APPOGGIATURA_LOWER {
        return gen(
            kind,
            base_ctx(0, 8, false, true, false, false, false),
            4,
            2,
            7,
            8,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_ESCAPE_UPPER || kind == ORN_ESCAPE_LOWER {
        return gen(
            kind,
            base_ctx(0, 12, false, true, false, false, false),
            4,
            4,
            7,
            12,
            0,
            c.span(),
            c.span(),
            g.span(),
        );
    }
    if kind == ORN_ECHAPPEE_UPPER || kind == ORN_ECHAPPEE_LOWER {
        return gen(
            kind,
            base_ctx(0, 12, false, true, false, false, false),
            4,
            2,
            7,
            12,
            0,
            c.span(),
            c.span(),
            g.span(),
        );
    }
    if kind == ORN_CAMBIATA {
        return gen(
            kind,
            base_ctx(0, 20, false, true, false, false, false),
            4,
            4,
            2,
            20,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_MORDENT_UPPER || kind == ORN_MORDENT_LOWER {
        return gen(
            kind,
            base_ctx(0, 12, false, true, false, false, false),
            4,
            4,
            7,
            12,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_TURN_UPPER || kind == ORN_TURN_LOWER {
        return gen(
            kind,
            base_ctx(0, 16, false, true, false, false, false),
            4,
            4,
            7,
            16,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_TRILL_UPPER || kind == ORN_TRILL_LOWER {
        return gen(
            kind,
            base_ctx(0, 16, false, true, false, false, false),
            4,
            4,
            7,
            16,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_ACCIACCATURA_UPPER || kind == ORN_ACCIACCATURA_LOWER {
        return gen(
            kind,
            base_ctx(0, 8, false, true, false, false, false),
            4,
            2,
            7,
            8,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_CHROMATIC_APPROACH_UPPER || kind == ORN_CHROMATIC_APPROACH_LOWER {
        return gen(
            kind,
            base_ctx(0, 8, false, true, false, false, false),
            4,
            2,
            7,
            8,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_ENCLOSURE_UF || kind == ORN_ENCLOSURE_LF {
        return gen(
            kind,
            base_ctx(0, 12, false, true, false, false, false),
            4,
            2,
            7,
            12,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_ARPEGGIATION_UP || kind == ORN_ARPEGGIATION_DOWN {
        return gen(
            kind,
            base_ctx(0, 12, false, true, true, false, false),
            4,
            0,
            7,
            12,
            0,
            c.span(),
            c.span(),
            c.span(),
        );
    }
    if kind == ORN_PEDAL_HOLD {
        return gen(
            kind,
            base_ctx(1, 12, true, true, true, true, true),
            0,
            0,
            0,
            12,
            0,
            c.span(),
            c.span(),
            g.span(),
        );
    }
    ArrayTrait::new()
}

/// Concatenate all showcase ornaments with a tick gap between each (for catalog MIDI).
pub fn showcase_catalog_events(gap_ticks: u32) -> Array<V2NoteEvent> {
    let kinds = showcase_kind_ids();
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let mut slot: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= kinds.len() {
            break;
        }
        let kind = *kinds.at(i);
        let chunk = showcase_events_for_kind(kind);
        let mut j: u32 = 0;
        loop {
            if j >= chunk.len() {
                break;
            }
            let mut e = *chunk.at(j);
            e.start = e.start + slot;
            out.append(e);
            j += 1;
        };
        if chunk.len() > 0 {
            let mut last = *chunk.at(chunk.len() - 1);
            slot = slot + last.start + last.duration + gap_ticks;
        } else {
            slot = slot + gap_ticks;
        }
        i += 1;
    };
    out
}

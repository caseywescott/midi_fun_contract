//! Ornament rule implementations: canApply + generate for every kind (§7).

use core::array::ArrayTrait;
use koji::composition::ornamentation_v2::pitch::{
    chord_contains_pc, chromatic_approach_midi, common_tone_pcs, degree_sentinel_pitch,
    degree_to_midi, interval_above_bass, midi_from_pc_in_tonic_octave, midi_to_pitch,
    pc_in_scale, scale_degree_for_pc, scale_step_distance, step_degree, subdivide_duration,
};
use koji::composition::ornamentation_v2::types::{
    OrnamentContext, ROLE_ANTICIPATION, ROLE_APPOGGIATURA, ROLE_CAMBIATA, ROLE_CHROMATIC_APPROACH,
    ROLE_DOUBLE_NEIGHBOR, ROLE_ECHAPPEE, ROLE_ENCLOSURE, ROLE_ESCAPE, ROLE_GRACE, ROLE_MORDENT,
    ROLE_NEIGHBOR, ROLE_PASSING, ROLE_PEDAL, ROLE_RETARDATION, ROLE_STRUCTURAL, ROLE_SUSPENSION,
    ROLE_TRILL, ROLE_TURN, surface_event, structural_event, V2NoteEvent, V2Pitch,
    ORN_ACCIACCATURA_LOWER, ORN_ACCIACCATURA_UPPER, ORN_ANTICIPATION, ORN_APPOGGIATURA_LOWER,
    ORN_APPOGGIATURA_UPPER, ORN_ARPEGGIATION_DOWN, ORN_ARPEGGIATION_UP, ORN_CAMBIATA,
    ORN_CHROMATIC_APPROACH_LOWER, ORN_CHROMATIC_APPROACH_UPPER, ORN_DOUBLE_NEIGHBOR_LF,
    ORN_DOUBLE_NEIGHBOR_UF, ORN_ECHAPPEE_LOWER, ORN_ECHAPPEE_UPPER, ORN_ENCLOSURE_LF,
    ORN_ENCLOSURE_UF, ORN_ESCAPE_LOWER, ORN_ESCAPE_UPPER, ORN_MORDENT_LOWER, ORN_MORDENT_UPPER,
    ORN_NEIGHBOR_LOWER, ORN_NEIGHBOR_UPPER, ORN_PASSING_ASC, ORN_PASSING_DESC, ORN_PEDAL_HOLD,
    ORN_RETARDATION, ORN_SUSPENSION_23_BASS, ORN_SUSPENSION_43, ORN_SUSPENSION_65,
    ORN_SUSPENSION_76, ORN_SUSPENSION_98, ORN_TRILL_LOWER, ORN_TRILL_UPPER, ORN_TURN_LOWER,
    ORN_TURN_UPPER,
};

pub fn requires_harmony(kind: u8) -> bool {
    kind >= 7 && kind <= 13 || kind == 35 || kind == 33 || kind == 34
}

pub fn requires_prev_anchor(kind: u8) -> bool {
    kind == 1 || kind == 2 || kind == 5 || kind == 6 || kind >= 8 && kind <= 13
        || kind == 35
}

pub fn requires_next_anchor(kind: u8) -> bool {
    kind == 1 || kind == 2 || kind == 7 || kind == 16 || kind == 17 || kind == 18
        || kind == 19 || kind == 20
}

pub fn ornament_can_apply(
    kind: u8,
    ctx: OrnamentContext,
    anchor_deg: i32,
    prev_deg: i32,
    next_deg: i32,
    anchor_dur: u32,
    chord_pcs: Span<u8>,
    bass_pc: u8,
    prev_chord: Span<u8>,
) -> bool {
    if requires_prev_anchor(kind) && !ctx.has_prev_anchor {
        return false;
    }
    if requires_next_anchor(kind) && !ctx.has_next_anchor {
        return false;
    }
    if anchor_dur < 2 {
        return false;
    }
    if kind == ORN_PASSING_ASC || kind == ORN_PASSING_DESC {
        if !ctx.has_prev_anchor || !ctx.has_next_anchor {
            return false;
        }
        let dist = scale_step_distance(prev_deg, next_deg);
        return dist == 2 || dist == 3;
    }
    if kind == ORN_NEIGHBOR_UPPER || kind == ORN_NEIGHBOR_LOWER {
        return anchor_dur >= 3;
    }
    if kind == ORN_DOUBLE_NEIGHBOR_UF || kind == ORN_DOUBLE_NEIGHBOR_LF {
        return anchor_dur >= 4;
    }
    if kind == ORN_ANTICIPATION {
        return ctx.has_next_anchor && chord_pcs.len() > 0;
    }
    if kind == ORN_SUSPENSION_43 || kind == ORN_SUSPENSION_76 || kind == ORN_SUSPENSION_98
        || kind == ORN_SUSPENSION_65 {
        if !ctx.has_prev_harmony || !ctx.has_current_harmony {
            return false;
        }
        let held_pc = degree_to_midi(prev_deg, ctx.key_pc + 60, ctx.mode_id, 7) % 12;
        let ivl = interval_above_bass(held_pc, bass_pc);
        if kind == ORN_SUSPENSION_43 {
            return ivl == 4;
        }
        if kind == ORN_SUSPENSION_76 {
            return ivl == 7;
        }
        if kind == ORN_SUSPENSION_98 {
            return ivl == 9 || ivl == 2;
        }
        return ivl == 6;
    }
    if kind == ORN_SUSPENSION_23_BASS {
        return ctx.has_prev_harmony && ctx.has_current_harmony;
    }
    if kind == ORN_RETARDATION {
        return ctx.has_prev_harmony && ctx.has_current_harmony;
    }
    if kind == ORN_APPOGGIATURA_UPPER || kind == ORN_APPOGGIATURA_LOWER {
        return anchor_dur >= 2;
    }
    if kind == ORN_ESCAPE_UPPER || kind == ORN_ESCAPE_LOWER {
        return ctx.has_next_anchor;
    }
    if kind == ORN_ECHAPPEE_UPPER || kind == ORN_ECHAPPEE_LOWER {
        return ctx.has_next_anchor;
    }
    if kind == ORN_CAMBIATA {
        return anchor_dur >= 5;
    }
    if kind == ORN_MORDENT_UPPER || kind == ORN_MORDENT_LOWER || kind == ORN_TURN_UPPER
        || kind == ORN_TURN_LOWER || kind == ORN_TRILL_UPPER || kind == ORN_TRILL_LOWER {
        return anchor_dur >= 3;
    }
    if kind == ORN_ACCIACCATURA_UPPER || kind == ORN_ACCIACCATURA_LOWER {
        return true;
    }
    if kind == ORN_CHROMATIC_APPROACH_UPPER || kind == ORN_CHROMATIC_APPROACH_LOWER {
        return true;
    }
    if kind == ORN_ENCLOSURE_UF || kind == ORN_ENCLOSURE_LF {
        return anchor_dur >= 3;
    }
    if kind == ORN_ARPEGGIATION_UP || kind == ORN_ARPEGGIATION_DOWN {
        return chord_pcs.len() >= 2;
    }
    if kind == ORN_PEDAL_HOLD {
        return ctx.has_prev_harmony && ctx.has_next_harmony;
    }
    false
}

fn emit_passing(
    kind: u8,
    anchor_deg: i32,
    prev_deg: i32,
    next_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let dist = scale_step_distance(prev_deg, next_deg);
    if dist == 2 {
        let mid = step_degree(prev_deg, if next_deg > prev_deg {
            1
        } else {
            -1
        });
        let d = subdivide_duration(dur, 2);
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(mid, tonic, mode_id, 7), mid),
                start,
                d,
                ROLE_PASSING,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
                start + d,
                dur - d,
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
    } else {
        let dir = if next_deg > prev_deg {
            1_i32
        } else {
            -1_i32
        };
        let d = subdivide_duration(dur, 3);
        let p1 = step_degree(prev_deg, dir);
        let p2 = step_degree(prev_deg, dir * 2);
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(p1, tonic, mode_id, 7), p1),
                start,
                d,
                ROLE_PASSING,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(p2, tonic, mode_id, 7), p2),
                start + d,
                d,
                ROLE_PASSING,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
                start + 2 * d,
                dur - 2 * d,
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
    }
    out
}

fn emit_neighbor(
    upper: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let dir = if upper {
        1_i32
    } else {
        -1_i32
    };
    let nb = step_degree(anchor_deg, dir);
    let d = subdivide_duration(dur, 3);
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start,
            d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(nb, tonic, mode_id, 7), nb),
            start + d,
            d,
            ROLE_NEIGHBOR,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start + 2 * d,
            dur - 2 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_double_neighbor(
    upper_first: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 4);
    let upper = step_degree(anchor_deg, 1);
    let lower = step_degree(anchor_deg, -1);
    let first = if upper_first {
        upper
    } else {
        lower
    };
    let second = if upper_first {
        lower
    } else {
        upper
    };
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start,
            d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(first, tonic, mode_id, 7), first),
            start + d,
            d,
            ROLE_DOUBLE_NEIGHBOR,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(second, tonic, mode_id, 7), second),
            start + 2 * d,
            d,
            ROLE_DOUBLE_NEIGHBOR,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start + 3 * d,
            dur - 3 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_suspension(
    kind: u8,
    anchor_deg: i32,
    prev_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
    bass_pc: u8,
    chord_pcs: Span<u8>,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 3);
    let held_deg = prev_deg;
    let res_deg = if kind == ORN_SUSPENSION_23_BASS {
        step_degree(anchor_deg, 1)
    } else {
        step_degree(held_deg, -1)
    };
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(held_deg, tonic, mode_id, 7), held_deg),
            start,
            d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(held_deg, tonic, mode_id, 7), held_deg),
            start + d,
            d,
            ROLE_SUSPENSION,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(res_deg, tonic, mode_id, 7), res_deg),
            start + 2 * d,
            dur - 2 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_retardation(
    prev_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 3);
    let res = step_degree(prev_deg, 1);
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(prev_deg, tonic, mode_id, 7), prev_deg),
            start,
            d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(prev_deg, tonic, mode_id, 7), prev_deg),
            start + d,
            d,
            ROLE_RETARDATION,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(res, tonic, mode_id, 7), res),
            start + 2 * d,
            dur - 2 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_anticipation(
    anchor_deg: i32,
    next_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 2);
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(next_deg, tonic, mode_id, 7), next_deg),
            start,
            d,
            ROLE_ANTICIPATION,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start + d,
            dur - d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_appoggiatura(
    upper: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let leap = if upper {
        2_i32
    } else {
        -2_i32
    };
    let dis = step_degree(anchor_deg, leap);
    let d = subdivide_duration(dur, 2);
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(dis, tonic, mode_id, 7), dis),
            start,
            d,
            ROLE_APPOGGIATURA,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start + d,
            dur - d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_escape(
    upper: bool,
    anchor_deg: i32,
    next_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let dir = if upper {
        1_i32
    } else {
        -1_i32
    };
    let step_note = step_degree(anchor_deg, dir);
    let leap_note = next_deg;
    let d = subdivide_duration(dur, 3);
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start,
            d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(step_note, tonic, mode_id, 7), step_note),
            start + d,
            d,
            ROLE_ESCAPE,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(leap_note, tonic, mode_id, 7), leap_note),
            start + 2 * d,
            dur - 2 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_echappee(
    upper: bool,
    anchor_deg: i32,
    next_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let dir = if upper {
        2_i32
    } else {
        -2_i32
    };
    let leap_note = step_degree(anchor_deg, dir);
    let d = subdivide_duration(dur, 3);
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start,
            d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(leap_note, tonic, mode_id, 7), leap_note),
            start + d,
            d,
            ROLE_ECHAPPEE,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(next_deg, tonic, mode_id, 7), next_deg),
            start + 2 * d,
            dur - 2 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_cambiata(
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 5);
    let n1 = anchor_deg;
    let n2 = step_degree(anchor_deg, -1);
    let n3 = step_degree(anchor_deg, -3);
    let n4 = step_degree(anchor_deg, -2);
    let n5 = step_degree(anchor_deg, -1);
    let notes = array![n1, n2, n3, n4, n5];
    let mut i: u32 = 0;
    loop {
        if i >= 5 {
            break;
        }
        let role = if i == 1 {
            ROLE_CAMBIATA
        } else if i == 0 || i == 4 {
            ROLE_STRUCTURAL
        } else {
            ROLE_CAMBIATA
        };
        out.append(
            surface_event(
                midi_to_pitch(
                    degree_to_midi(*notes.at(i), tonic, mode_id, 7), *notes.at(i),
                ),
                start + i * d,
                if i == 4 {
                    dur - 4 * d
                } else {
                    d
                },
                role,
                ornament_id,
                voice_index,
            ),
        );
        i += 1;
    };
    out
}

fn emit_mordent(
    upper: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let dir = if upper {
        1_i32
    } else {
        -1_i32
    };
    let aux = step_degree(anchor_deg, dir);
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 3);
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start,
            d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(aux, tonic, mode_id, 7), aux),
            start + d,
            d,
            ROLE_MORDENT,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start + 2 * d,
            dur - 2 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_turn(
    upper_first: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let upper = step_degree(anchor_deg, 1);
    let lower = step_degree(anchor_deg, -1);
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 4);
    if upper_first {
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(upper, tonic, mode_id, 7), upper),
                start,
                d,
                ROLE_TURN,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
                start + d,
                d,
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(lower, tonic, mode_id, 7), lower),
                start + 2 * d,
                d,
                ROLE_TURN,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
                start + 3 * d,
                dur - 3 * d,
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
    } else {
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(lower, tonic, mode_id, 7), lower),
                start,
                d,
                ROLE_TURN,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
                start + d,
                d,
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(upper, tonic, mode_id, 7), upper),
                start + 2 * d,
                d,
                ROLE_TURN,
                ornament_id,
                voice_index,
            ),
        );
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
                start + 3 * d,
                dur - 3 * d,
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
    }
    out
}

fn emit_trill(
    upper: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
    subdivisions: u32,
    count: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let aux_dir = if upper {
        1_i32
    } else {
        -1_i32
    };
    let aux = step_degree(anchor_deg, aux_dir);
    // Clamp subdivisions so each trill note is at least 1 tick; minimum 2.
    let n = if subdivisions < 2 {
        2_u32
    } else if subdivisions > dur {
        dur
    } else {
        subdivisions
    };
    let d = subdivide_duration(dur, n);
    // active = number of rapid alternating notes to emit before an anchor hold.
    // count == 0 → fill the entire duration (classic behaviour).
    let active = if count == 0 || count >= n {
        n
    } else if count < 2 {
        2_u32
    } else {
        count
    };
    let mut i: u32 = 0;
    loop {
        if i >= active {
            break;
        }
        let deg = if i % 2 == 0 {
            anchor_deg
        } else {
            aux
        };
        // In fill mode (active == n) the last note absorbs any rounding remainder.
        let this_dur = if active == n && i == active - 1 {
            dur - (n - 1) * d
        } else {
            d
        };
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(deg, tonic, mode_id, 7), deg),
                start + i * d,
                this_dur,
                ROLE_TRILL,
                ornament_id,
                voice_index,
            ),
        );
        i += 1;
    };
    // Partial-fill: append anchor hold tail so sum_durations == anchor_dur.
    if active < n {
        out.append(
            surface_event(
                midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
                start + active * d,
                dur - active * d,
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
    }
    out
}

fn emit_grace(
    upper: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let dir = if upper {
        1_i32
    } else {
        -1_i32
    };
    let grace_deg = step_degree(anchor_deg, dir);
    let grace_dur = if dur > 1 {
        1_u32
    } else {
        dur
    };
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(grace_deg, tonic, mode_id, 7), grace_deg),
            start,
            grace_dur,
            ROLE_GRACE,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start + grace_dur,
            dur - grace_dur,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_chromatic_approach(
    from_above: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let anchor_midi = degree_to_midi(anchor_deg, tonic, mode_id, 7);
    let approach_midi = chromatic_approach_midi(anchor_midi, from_above);
    let d = subdivide_duration(dur, 2);
    out.append(
        surface_event(
            degree_sentinel_pitch(approach_midi),
            start,
            d,
            ROLE_CHROMATIC_APPROACH,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(anchor_midi, anchor_deg),
            start + d,
            dur - d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_enclosure(
    upper_first: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let upper = step_degree(anchor_deg, 1);
    let lower = step_degree(anchor_deg, -1);
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let d = subdivide_duration(dur, 3);
    let first = if upper_first {
        upper
    } else {
        lower
    };
    let second = if upper_first {
        lower
    } else {
        upper
    };
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(first, tonic, mode_id, 7), first),
            start,
            d,
            ROLE_ENCLOSURE,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(second, tonic, mode_id, 7), second),
            start + d,
            d,
            ROLE_ENCLOSURE,
            ornament_id,
            voice_index,
        ),
    );
    out.append(
        surface_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, mode_id, 7), anchor_deg),
            start + 2 * d,
            dur - 2 * d,
            ROLE_STRUCTURAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

fn emit_arpeggiation(
    ascending: bool,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
    chord_pcs: Span<u8>,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let n = chord_pcs.len();
    if n == 0 {
        return out;
    }
    let d = subdivide_duration(dur, n);
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let idx = if ascending {
            i
        } else {
            n - 1 - i
        };
        let pc = *chord_pcs.at(idx);
        let key_pc = tonic % 12;
        let deg = scale_degree_for_pc(pc, key_pc, mode_id);
        let midi = midi_from_pc_in_tonic_octave(tonic, pc);
        out.append(
            surface_event(
                midi_to_pitch(midi, deg),
                start + i * d,
                if i == n - 1 {
                    dur - (n - 1) * d
                } else {
                    d
                },
                ROLE_STRUCTURAL,
                ornament_id,
                voice_index,
            ),
        );
        i += 1;
    };
    out
}

fn emit_pedal(
    prev_chord: Span<u8>,
    curr_chord: Span<u8>,
    next_chord: Span<u8>,
    anchor_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    mode_id: u8,
    voice_index: u32,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    let mut out: Array<V2NoteEvent> = ArrayTrait::new();
    let pc = common_tone_pcs(prev_chord, curr_chord, next_chord);
    let midi = midi_from_pc_in_tonic_octave(tonic, pc);
    out.append(
        surface_event(
            midi_to_pitch(midi, anchor_deg),
            start,
            dur,
            ROLE_PEDAL,
            ornament_id,
            voice_index,
        ),
    );
    out
}

pub fn ornament_generate(
    kind: u8,
    ctx: OrnamentContext,
    anchor_deg: i32,
    prev_deg: i32,
    next_deg: i32,
    start: u32,
    anchor_dur: u32,
    tonic: u8,
    chord_pcs: Span<u8>,
    bass_pc: u8,
    prev_chord: Span<u8>,
    next_chord: Span<u8>,
    ornament_id: u32,
) -> Array<V2NoteEvent> {
    if kind == ORN_PASSING_ASC || kind == ORN_PASSING_DESC {
        return emit_passing(
            kind, anchor_deg, prev_deg, next_deg, start, anchor_dur, tonic, ctx.mode_id,
            ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_NEIGHBOR_UPPER {
        return emit_neighbor(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_NEIGHBOR_LOWER {
        return emit_neighbor(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_DOUBLE_NEIGHBOR_UF {
        return emit_double_neighbor(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_DOUBLE_NEIGHBOR_LF {
        return emit_double_neighbor(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind >= ORN_SUSPENSION_43 && kind <= ORN_SUSPENSION_23_BASS {
        return emit_suspension(
            kind, anchor_deg, prev_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index,
            ornament_id, bass_pc, chord_pcs,
        );
    }
    if kind == ORN_RETARDATION {
        return emit_retardation(
            prev_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_ANTICIPATION {
        return emit_anticipation(
            anchor_deg, next_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index,
            ornament_id,
        );
    }
    if kind == ORN_APPOGGIATURA_UPPER {
        return emit_appoggiatura(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_APPOGGIATURA_LOWER {
        return emit_appoggiatura(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_ESCAPE_UPPER {
        return emit_escape(
            true, anchor_deg, next_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index,
            ornament_id,
        );
    }
    if kind == ORN_ESCAPE_LOWER {
        return emit_escape(
            false, anchor_deg, next_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index,
            ornament_id,
        );
    }
    if kind == ORN_ECHAPPEE_UPPER {
        return emit_echappee(
            true, anchor_deg, next_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index,
            ornament_id,
        );
    }
    if kind == ORN_ECHAPPEE_LOWER {
        return emit_echappee(
            false, anchor_deg, next_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index,
            ornament_id,
        );
    }
    if kind == ORN_CAMBIATA {
        return emit_cambiata(
            anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_MORDENT_UPPER {
        return emit_mordent(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_MORDENT_LOWER {
        return emit_mordent(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_TURN_UPPER {
        return emit_turn(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_TURN_LOWER {
        return emit_turn(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_TRILL_UPPER {
        return emit_trill(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
            ctx.trill_subdivisions.into(), ctx.trill_count.into(),
        );
    }
    if kind == ORN_TRILL_LOWER {
        return emit_trill(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
            ctx.trill_subdivisions.into(), ctx.trill_count.into(),
        );
    }
    if kind == ORN_ACCIACCATURA_UPPER {
        return emit_grace(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_ACCIACCATURA_LOWER {
        return emit_grace(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_CHROMATIC_APPROACH_UPPER {
        return emit_chromatic_approach(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_CHROMATIC_APPROACH_LOWER {
        return emit_chromatic_approach(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_ENCLOSURE_UF {
        return emit_enclosure(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_ENCLOSURE_LF {
        return emit_enclosure(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
        );
    }
    if kind == ORN_ARPEGGIATION_UP {
        return emit_arpeggiation(
            true, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
            chord_pcs,
        );
    }
    if kind == ORN_ARPEGGIATION_DOWN {
        return emit_arpeggiation(
            false, anchor_deg, start, anchor_dur, tonic, ctx.mode_id, ctx.voice_index, ornament_id,
            chord_pcs,
        );
    }
    if kind == ORN_PEDAL_HOLD {
        return emit_pedal(
            prev_chord, chord_pcs, next_chord, anchor_deg, start, anchor_dur, tonic, ctx.mode_id,
            ctx.voice_index, ornament_id,
        );
    }
    let mut fallback: Array<V2NoteEvent> = ArrayTrait::new();
    fallback.append(
        structural_event(
            midi_to_pitch(degree_to_midi(anchor_deg, tonic, ctx.mode_id, 7), anchor_deg),
            start,
            anchor_dur,
            ctx.voice_index,
        ),
    );
    fallback
}

pub fn filter_candidates(
    enabled: Span<u8>,
    ctx: OrnamentContext,
    anchor_deg: i32,
    prev_deg: i32,
    next_deg: i32,
    anchor_dur: u32,
    chord_pcs: Span<u8>,
    bass_pc: u8,
    prev_chord: Span<u8>,
) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= enabled.len() {
            break;
        }
        let kind = *enabled.at(i);
        if ornament_can_apply(
            kind, ctx, anchor_deg, prev_deg, next_deg, anchor_dur, chord_pcs, bass_pc, prev_chord,
        ) {
            out.append(kind);
        }
        i += 1;
    };
    out
}

pub fn fallback_kinds(primary: u8) -> Span<u8> {
    if primary >= 8 && primary <= 13 {
        array![3_u8, 1_u8].span()
    } else {
        array![3_u8, 1_u8].span()
    }
}

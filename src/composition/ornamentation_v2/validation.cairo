//! Layered validation passes (§13).

use core::array::ArrayTrait;
use koji::composition::ornamentation_v2::pitch::{
    chord_contains_pc, interval_above_bass, leap_semitones, pc_in_scale, sum_durations,
};
use koji::composition::ornamentation_v2::types::{
    BOUNDARY_ALLOW_EXPANSION, BOUNDARY_ALLOW_PICKUP, BOUNDARY_ALLOW_SUSPENSION,
    BOUNDARY_PRESERVE_CELL, COLLISION_PERFECT, OrnamentConstraintSet, OrnamentContext,
    ROLE_NEIGHBOR, ROLE_RETARDATION, ROLE_STRUCTURAL, ROLE_SUSPENSION, V2NoteEvent,
};

pub fn validate_melodic_local(
    events: Span<V2NoteEvent>,
    anchor_dur: u32,
    preserve_duration: bool,
    scale_pcs: Span<u8>,
    strict_diatonic: bool,
    max_leap: u32,
) -> bool {
    if events.len() == 0 {
        return false;
    }
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        if e.duration == 0 {
            return false;
        }
        if strict_diatonic && !pc_in_scale(e.pitch.pc, scale_pcs) {
            return false;
        }
        if i > 0 {
            let prev = *events.at(i - 1);
            if leap_semitones(prev.pitch.midi, e.pitch.midi) > max_leap {
                return false;
            }
        }
        i += 1;
    };
    if preserve_duration {
        return sum_durations(events) == anchor_dur;
    }
    true
}

pub fn validate_neighbor_contour(events: Span<V2NoteEvent>, anchor_midi: u8) -> bool {
    if events.len() < 3 {
        return false;
    }
    let first = *events.at(0);
    let last = *events.at(events.len() - 1);
    first.pitch.midi == anchor_midi && last.pitch.midi == anchor_midi
}

pub fn validate_suspension_resolution(
    events: Span<V2NoteEvent>, bass_pc: u8, chord_pcs: Span<u8>, bass_suspension: bool,
) -> bool {
    if events.len() < 3 {
        return false;
    }
    let held = *events.at(1);
    let res = *events.at(2);
    if bass_suspension {
        return res.pitch.midi > held.pitch.midi;
    }
    let ivl = interval_above_bass(held.pitch.pc, bass_pc);
    if ivl != 4 && ivl != 6 && ivl != 7 && ivl != 9 && ivl != 2 {
        return false;
    }
    res.pitch.midi < held.pitch.midi
        && chord_contains_pc(chord_pcs, res.pitch.pc)
}

pub fn validate_retardation_resolution(events: Span<V2NoteEvent>) -> bool {
    if events.len() < 3 {
        return false;
    }
    let held = *events.at(1);
    let res = *events.at(2);
    res.pitch.midi > held.pitch.midi
}

pub fn validate_harmonic(
    events: Span<V2NoteEvent>,
    chord_pcs: Span<u8>,
    bass_pc: u8,
    kind: u8,
) -> bool {
    if kind >= 8 && kind <= 12 {
        return validate_suspension_resolution(events, bass_pc, chord_pcs, kind == 12);
    }
    if kind == 13 {
        return validate_retardation_resolution(events);
    }
    true
}

pub fn validate_vertical_canon(
    events: Span<V2NoteEvent>,
    sounding: Span<V2NoteEvent>,
    constraints: OrnamentConstraintSet,
) -> bool {
    if !constraints.strict_canon {
        return true;
    }
    let mut dissonances: u8 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        let mut j: u32 = 0;
        loop {
            if j >= sounding.len() {
                break;
            }
            let other = *sounding.at(j);
            if other.voice_index != e.voice_index && other.start == e.start {
                let ivl = if e.pitch.midi >= other.pitch.midi {
                    e.pitch.midi - other.pitch.midi
                } else {
                    other.pitch.midi - e.pitch.midi
                };
                let ivl_mod = ivl % 12;
                if ivl_mod == 1 || ivl_mod == 2 || ivl_mod == 6 || ivl_mod == 7
                    || ivl_mod == 10 || ivl_mod == 11 {
                    dissonances += 1;
                }
            }
            j += 1;
        };
        i += 1;
    };
    dissonances <= constraints.vertical.max_simultaneous_dissonances
}

pub fn preserves_coverage(
    tile_start: u32,
    cell_len: u32,
    target_onsets: Span<u32>,
    ornamented: Span<V2NoteEvent>,
) -> bool {
    let mut i: u32 = 0;
    loop {
        if i >= target_onsets.len() {
            break;
        }
        let slot = *target_onsets.at(i);
        if slot >= tile_start && slot < tile_start + cell_len {
            let mut found = false;
            let mut j: u32 = 0;
            loop {
                if j >= ornamented.len() {
                    break;
                }
                if (*ornamented.at(j)).start == slot {
                    found = true;
                    break;
                }
                j += 1;
            };
            if !found {
                return false;
            }
        }
        i += 1;
    };
    true
}

pub fn preserves_no_collision(
    ornamented: Span<V2NoteEvent>,
    other_onsets: Span<u32>,
    voice_index: u32,
    collision_policy: u8,
) -> bool {
    if collision_policy != COLLISION_PERFECT {
        return true;
    }
    let mut i: u32 = 0;
    loop {
        if i >= ornamented.len() {
            break;
        }
        let e = *ornamented.at(i);
        let mut j: u32 = 0;
        loop {
            if j >= other_onsets.len() {
                break;
            }
            if *other_onsets.at(j) == e.start {
                return false;
            }
            j += 1;
        };
        i += 1;
    };
    true
}

pub fn validate_boundary_policy(
    events: Span<V2NoteEvent>,
    anchor_start: u32,
    anchor_dur: u32,
    boundary_policy: u8,
    kind_boundary: u8,
) -> bool {
    if kind_boundary == BOUNDARY_ALLOW_EXPANSION {
        return true;
    }
    if events.len() == 0 {
        return false;
    }
    let first = *events.at(0);
    let last = *events.at(events.len() - 1);
    if kind_boundary == BOUNDARY_PRESERVE_CELL {
        return first.start == anchor_start
            && last.start + last.duration <= anchor_start + anchor_dur;
    }
    if kind_boundary == BOUNDARY_ALLOW_PICKUP {
        return first.start >= anchor_start
            && last.start + last.duration <= anchor_start + anchor_dur;
    }
    if kind_boundary == BOUNDARY_ALLOW_SUSPENSION {
        return first.start >= anchor_start
            && last.start + last.duration <= anchor_start + anchor_dur;
    }
    true
}

pub fn validate_all(
    events: Span<V2NoteEvent>,
    ctx: OrnamentContext,
    anchor_start: u32,
    anchor_dur: u32,
    scale_pcs: Span<u8>,
    chord_pcs: Span<u8>,
    bass_pc: u8,
    kind: u8,
    constraints: OrnamentConstraintSet,
    boundary_policy: u8,
    kind_boundary: u8,
    sounding: Span<V2NoteEvent>,
    target_onsets: Span<u32>,
    tile_start: u32,
    cell_len: u32,
    other_onsets: Span<u32>,
    tiling_collision: u8,
) -> bool {
    if !validate_melodic_local(
        events, anchor_dur, true, scale_pcs, constraints.strict_diatonic, 12,
    ) {
        return false;
    }
    if !validate_harmonic(events, chord_pcs, bass_pc, kind) {
        return false;
    }
    if !validate_vertical_canon(events, sounding, constraints) {
        return false;
    }
    if !validate_boundary_policy(events, anchor_start, anchor_dur, boundary_policy, kind_boundary) {
        return false;
    }
    if ctx.has_tile {
        if !preserves_coverage(tile_start, cell_len, target_onsets, events) {
            return false;
        }
        if !preserves_no_collision(events, other_onsets, ctx.voice_index, tiling_collision) {
            return false;
        }
    }
    true
}

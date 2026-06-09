//! Onchain ornament encoding and rule-mode expansion (§15).

use core::array::ArrayTrait;
use koji::composition::ornamentation_v2::ornaments::ornament_generate;
use koji::composition::ornamentation_v2::pitch::{degree_to_midi, midi_to_pitch};
use koji::composition::ornamentation_v2::types::{
    OrnamentContext, OrnamentEvent, OrnamentPhraseResult, OUTPUT_ONCHAIN_COMPACT, OUTPUT_SYMBOLIC,
    structural_event, V2NoteEvent,
};

pub fn encode_ornament_event(
    kind: u8, anchor_index: u32, param_a: u32, param_b: u32, param_c: u32,
) -> OrnamentEvent {
    OrnamentEvent { kind, anchor_index, param_a, param_b, param_c }
}

pub fn expand_ornament_event(
    ev: OrnamentEvent,
    ctx: OrnamentContext,
    anchor_deg: i32,
    prev_deg: i32,
    next_deg: i32,
    start: u32,
    dur: u32,
    tonic: u8,
    chord_pcs: Span<u8>,
    bass_pc: u8,
    prev_chord: Span<u8>,
    next_chord: Span<u8>,
) -> Array<V2NoteEvent> {
    ornament_generate(
        ev.kind,
        ctx,
        anchor_deg,
        prev_deg,
        next_deg,
        start,
        dur,
        tonic,
        chord_pcs,
        bass_pc,
        prev_chord,
        next_chord,
        ev.anchor_index,
    )
}

pub fn events_equal(a: Span<V2NoteEvent>, b: Span<V2NoteEvent>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        let ea = *a.at(i);
        let eb = *b.at(i);
        if ea.start != eb.start
            || ea.duration != eb.duration
            || ea.pitch.midi != eb.pitch.midi
            || ea.role != eb.role {
            return false;
        }
        i += 1;
    };
    true
}

pub fn rule_mode_matches_expanded(
    rules: Span<OrnamentEvent>,
    expanded: Span<V2NoteEvent>,
    ctx: OrnamentContext,
    degrees: Span<i32>,
    starts: Span<u32>,
    durs: Span<u32>,
    tonic: u8,
    chord_pcs: Span<u8>,
    bass_pc: u8,
    prev_chord: Span<u8>,
    next_chord: Span<u8>,
) -> bool {
    let mut rebuilt: Array<V2NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= rules.len() {
            break;
        }
        let ev = *rules.at(i);
        let idx = ev.anchor_index;
        let prev = if idx > 0 {
            *degrees.at(idx - 1)
        } else {
            *degrees.at(0)
        };
        let next = if idx + 1 < degrees.len() {
            *degrees.at(idx + 1)
        } else {
            *degrees.at(idx)
        };
        let chunk = expand_ornament_event(
            ev,
            ctx,
            *degrees.at(idx),
            prev,
            next,
            *starts.at(idx),
            *durs.at(idx),
            tonic,
            chord_pcs,
            bass_pc,
            prev_chord,
            next_chord,
        );
        let mut j: u32 = 0;
        loop {
            if j >= chunk.len() {
                break;
            }
            rebuilt.append(*chunk.at(j));
            j += 1;
        };
        i += 1;
    };
    events_equal(rebuilt.span(), expanded)
}

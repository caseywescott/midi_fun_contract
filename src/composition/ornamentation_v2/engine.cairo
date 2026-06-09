//! v2 entrypoints: ornamentPhrase, ornamentCanon, ornamentTilingCell (§14).

use core::array::ArrayTrait;
use koji::composition::melodic_canon::MelodicCanon;
use koji::composition::ornamentation_v2::canon::{
    derive_structural_events, derive_voices_from_canon, structural_phrase_for_voice,
};
use koji::composition::ornamentation_v2::encoding::encode_ornament_event;
use koji::composition::ornamentation_v2::ornaments::{
    filter_candidates, ornament_can_apply, ornament_generate,
};
use koji::composition::ornamentation_v2::pitch::{
    mode_scale_pcs, subdivide_duration,
};
use koji::composition::ornamentation_v2::profiles::default_profile;
use koji::composition::ornamentation_v2::selection::{
    advance_seed, build_candidate_weights, deterministic_choice_u8, live_choice_u8,
    weighted_pick_u8,
};
use koji::composition::ornamentation_v2::types::{
    default_boundary_for_kind, default_constraints, HarmonyEvent, MusicalTile,
    OrnamentCanonResult, OrnamentConfig, OrnamentContext, OrnamentPhraseResult,
    OUTPUT_ONCHAIN_COMPACT, OUTPUT_SYMBOLIC, SELECTION_LIVE, SELECTION_SEEDED,
    WORKFLOW_CANON_FIRST, WORKFLOW_ORNAMENT_FIRST, structural_event, V2NoteEvent,
};
use koji::composition::ornamentation_v2::validation::validate_all;

fn default_triad(key_pc: u8) -> Array<u8> {
    let root = key_pc % 12;
    let mut out: Array<u8> = ArrayTrait::new();
    out.append(root);
    out.append((root + 4) % 12);
    out.append((root + 7) % 12);
    out
}

fn harmony_at(harmony: Span<HarmonyEvent>, time: u32) -> (Array<u8>, u8, bool) {
    let mut i: u32 = 0;
    loop {
        if i >= harmony.len() {
            break;
        }
        let h = *harmony.at(i);
        if time >= h.start && time < h.start + h.duration {
            let mut chord: Array<u8> = ArrayTrait::new();
            let root = h.root_pc;
            chord.append(root);
            chord.append((root + 4) % 12);
            chord.append((root + 7) % 12);
            return (chord, h.bass_pc, true);
        }
        i += 1;
    };
    let mut empty: Array<u8> = ArrayTrait::new();
    (empty, 0, false)
}

fn safe_generate(
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
    scale_pcs: Span<u8>,
    config: OrnamentConfig,
    sounding: Span<V2NoteEvent>,
    target_onsets: Span<u32>,
    tile_start: u32,
    cell_len: u32,
    other_onsets: Span<u32>,
    tiling_collision: u8,
    ornament_id: u32,
) -> (Array<V2NoteEvent>, u32) {
    let events = ornament_generate(
        kind,
        ctx,
        anchor_deg,
        prev_deg,
        next_deg,
        start,
        anchor_dur,
        tonic,
        chord_pcs,
        bass_pc,
        prev_chord,
        next_chord,
        ornament_id,
    );
    let kind_boundary = default_boundary_for_kind(kind);
    if validate_all(
        events.span(),
        ctx,
        start,
        anchor_dur,
        scale_pcs,
        chord_pcs,
        bass_pc,
        kind,
        config.constraints,
        config.boundary_policy,
        kind_boundary,
        sounding,
        target_onsets,
        tile_start,
        cell_len,
        other_onsets,
        tiling_collision,
    ) {
        return (events, advance_seed(ctx.seed_state));
    }
    let fallbacks = array![3_u8, 1_u8].span();
    let mut fi: u32 = 0;
    loop {
        if fi >= fallbacks.len() {
            break;
        }
        let fb = *fallbacks.at(fi);
        if ornament_can_apply(
            fb, ctx, anchor_deg, prev_deg, next_deg, anchor_dur, chord_pcs, bass_pc, prev_chord,
        ) {
            let fb_out = ornament_generate(
                fb,
                ctx,
                anchor_deg,
                prev_deg,
                next_deg,
                start,
                anchor_dur,
                tonic,
                chord_pcs,
                bass_pc,
                prev_chord,
                next_chord,
                ornament_id,
            );
            if validate_all(
                fb_out.span(),
                ctx,
                start,
                anchor_dur,
                scale_pcs,
                chord_pcs,
                bass_pc,
                fb,
                config.constraints,
                config.boundary_policy,
                default_boundary_for_kind(fb),
                sounding,
                target_onsets,
                tile_start,
                cell_len,
                other_onsets,
                tiling_collision,
            ) {
                return (fb_out, advance_seed(ctx.seed_state));
            }
        }
        fi += 1;
    };
    let mut anchor_only: Array<V2NoteEvent> = ArrayTrait::new();
    anchor_only.append(
        structural_event(
            koji::composition::ornamentation_v2::pitch::midi_to_pitch(
                koji::composition::ornamentation_v2::pitch::degree_to_midi(
                    anchor_deg, tonic, ctx.mode_id, 7,
                ),
                anchor_deg,
            ),
            start,
            anchor_dur,
            ctx.voice_index,
        ),
    );
    (anchor_only, advance_seed(ctx.seed_state))
}

pub fn ornament_phrase(
    phrase: Span<V2NoteEvent>,
    harmony: Span<HarmonyEvent>,
    config: OrnamentConfig,
    enabled: Span<u8>,
    degrees: Span<i32>,
    tonic_keynum: u8,
    mode_id: u8,
) -> OrnamentPhraseResult {
    let scale_pcs = mode_scale_pcs(mode_id, tonic_keynum % 12);
    let mut out_events: Array<V2NoteEvent> = ArrayTrait::new();
    let mut out_rules: Array<koji::composition::ornamentation_v2::types::OrnamentEvent> =
        ArrayTrait::new();
    let mut seed_state = if config.selection_kind == SELECTION_SEEDED {
        let s: u32 = config.seed.try_into().unwrap();
        if s == 0 {
            7_u32
        } else {
            s % 256
        }
    } else {
        19_u32
    };
    let mut i: u32 = 0;
    loop {
        if i >= phrase.len() {
            break;
        }
        let anchor = *phrase.at(i);
        let anchor_deg = if i < degrees.len() {
            *degrees.at(i)
        } else {
            0_i32
        };
        let prev_deg = if i > 0 && i - 1 < degrees.len() {
            *degrees.at(i - 1)
        } else {
            anchor_deg
        };
        let next_deg = if i + 1 < degrees.len() {
            *degrees.at(i + 1)
        } else {
            anchor_deg
        };
        let (chord, bass_pc, has_h) = harmony_at(harmony, anchor.start);
        let (prev_chord, _, has_prev_h) = if i > 0 {
            let t = (*phrase.at(i - 1)).start;
            harmony_at(harmony, t)
        } else {
            let mut e: Array<u8> = ArrayTrait::new();
            (e, 0_u8, false)
        };
        let (next_chord, _, has_next_h) = if i + 1 < phrase.len() {
            harmony_at(harmony, (*phrase.at(i + 1)).start)
        } else {
            let mut e: Array<u8> = ArrayTrait::new();
            (e, 0_u8, false)
        };
        let mut ctx = OrnamentContext {
            anchor_index: i,
            metric_position: anchor.start,
            beat_strength: 80,
            available_duration: anchor.duration,
            subdivision: subdivide_duration(anchor.duration, 4),
            scale_len: scale_pcs.len(),
            voice_index: anchor.voice_index,
            canon_voice_index: anchor.voice_index,
            seed_state,
            mode_id,
            key_pc: tonic_keynum % 12,
            has_prev_anchor: i > 0,
            has_next_anchor: i + 1 < phrase.len(),
            has_current_harmony: has_h,
            has_prev_harmony: has_prev_h,
            has_next_harmony: has_next_h,
            has_applied_transform: false,
            has_tile: false,
            sounding_voice_count: 0,
        };
        let candidates = filter_candidates(
            enabled,
            ctx,
            anchor_deg,
            prev_deg,
            next_deg,
            anchor.duration,
            chord.span(),
            bass_pc,
            prev_chord.span(),
        );
        if candidates.len() == 0 {
            out_events.append(anchor);
            seed_state = advance_seed(seed_state);
            i += 1;
            continue;
        }
        let weights = build_candidate_weights(candidates.span(), ctx, config.style);
        let (kind, next_seed) = if config.selection_kind == SELECTION_LIVE {
            let k = live_choice_u8(candidates.span(), seed_state);
            (k, advance_seed(seed_state))
        } else {
            weighted_pick_u8(candidates.span(), weights.span(), seed_state)
        };
        seed_state = next_seed;
        ctx.seed_state = seed_state;
        let (generated, final_seed) = safe_generate(
            kind,
            ctx,
            anchor_deg,
            prev_deg,
            next_deg,
            anchor.start,
            anchor.duration,
            tonic_keynum,
            chord.span(),
            bass_pc,
            prev_chord.span(),
            next_chord.span(),
            scale_pcs.span(),
            config,
            array![].span(),
            array![].span(),
            0,
            0,
            array![].span(),
            0,
            i,
        );
        seed_state = final_seed;
        if config.output_mode == OUTPUT_ONCHAIN_COMPACT {
            out_rules.append(encode_ornament_event(kind, i, 0, 0, anchor.voice_index));
        }
        let mut gi: u32 = 0;
        loop {
            if gi >= generated.len() {
                break;
            }
            out_events.append(*generated.at(gi));
            gi += 1;
        };
        i += 1;
    };
    OrnamentPhraseResult {
        events: out_events,
        rules: out_rules,
        final_seed_state: seed_state,
    }
}

pub fn ornament_canon(
    canon: @MelodicCanon,
    harmony: Span<HarmonyEvent>,
    config: OrnamentConfig,
    enabled: Span<u8>,
) -> OrnamentCanonResult {
    let voices = derive_voices_from_canon(canon);
    let mut all_events: Array<V2NoteEvent> = ArrayTrait::new();
    let mut seed_state = if config.selection_kind == SELECTION_SEEDED {
        let s: u32 = config.seed.try_into().unwrap();
        if s == 0 {
            7_u32
        } else {
            s % 256
        }
    } else {
        19_u32
    };
    if config.canon_workflow == WORKFLOW_ORNAMENT_FIRST {
        let leader = structural_phrase_for_voice(canon, 0);
        let degs = canon.leader_degrees;
        let mut cfg = config;
        cfg.seed = seed_state.into();
        let phrase_result = ornament_phrase(
            leader.span(),
            harmony,
            cfg,
            enabled,
            *degs,
            *canon.tonic_keynum,
            *canon.mode_id,
        );
        all_events = phrase_result.events;
        seed_state = phrase_result.final_seed_state;
    } else {
        let mut vi: u32 = 0;
        loop {
            if vi >= voices.len() {
                break;
            }
            let voice = *voices.at(vi);
            let phrase = structural_phrase_for_voice(canon, voice.voice_index);
            let degs = degrees_from_canon(canon, voice.voice_index);
            let mut cfg = config;
            cfg.seed = seed_state.into();
            let phrase_result = ornament_phrase(
                phrase.span(),
                harmony,
                cfg,
                enabled,
                degs.span(),
                *canon.tonic_keynum,
                *canon.mode_id,
            );
            seed_state = phrase_result.final_seed_state;
            let mut pi: u32 = 0;
            loop {
                if pi >= phrase_result.events.len() {
                    break;
                }
                all_events.append(*phrase_result.events.at(pi));
                pi += 1;
            };
            vi += 1;
        };
    }
    OrnamentCanonResult { voices, events: all_events, final_seed_state: seed_state }
}

fn degrees_from_canon(canon: @MelodicCanon, voice_index: u32) -> Array<i32> {
    koji::composition::ornamentation_v2::canon::degrees_from_canon(canon, voice_index)
}

pub fn ornament_tiling_cell(
    cell_phrase: Span<V2NoteEvent>,
    tile: MusicalTile,
    harmony: Span<HarmonyEvent>,
    config: OrnamentConfig,
    enabled: Span<u8>,
    degrees: Span<i32>,
    tonic_keynum: u8,
    mode_id: u8,
    target_onsets: Span<u32>,
    other_onsets: Span<u32>,
) -> OrnamentPhraseResult {
    let mut cfg = config;
    cfg.constraints.preserve_tile_boundary = true;
    let mut result = ornament_phrase(
        cell_phrase, harmony, cfg, enabled, degrees, tonic_keynum, mode_id,
    );
    result
}

pub fn default_config(seed: felt252) -> OrnamentConfig {
    OrnamentConfig {
        selection_kind: SELECTION_SEEDED,
        seed,
        canon_workflow: WORKFLOW_CANON_FIRST,
        boundary_policy: 0,
        output_mode: OUTPUT_SYMBOLIC,
        style: default_profile(),
        constraints: default_constraints(),
    }
}

//! Loot Survivor Beast score generation.
//!
//! This module turns bounded `BeastCompositionParams` into deterministic note events.  It keeps
//! the Beast identity stable via sub-seeds, then lets live stats alter form, stretto, texture,
//! articulation, and section key shifts.

use core::array::ArrayTrait;
use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;
use core::traits::TryInto;
use koji::composition::articulation::{
    ART_ACCENT, ART_NORMAL, ART_PORTATO, ART_STACCATO, ART_TENUTO, ArticulationPlan,
    apply_articulation_plan,
};
use koji::composition::beast_trait_map::{
    ARTICULATION_ACCENT, ARTICULATION_PORTATO, ARTICULATION_STACCATO, ARTICULATION_TENUTO,
    BeastCompositionParams, BeastLiveStats,
    map_beast_traits_to_composition_params, weakness_section_b_shift,
};
use koji::composition::countersubject::{
    default_countersubject_config, generate_countersubject, countersubject_invertible,
    countersubject_to_note_events,
};
use koji::composition::invertible_counterpoint::{
    ic_pair_safe, generate_invertible_melodic_canon_mode,
};
use koji::composition::ornamentation_v2::canon::v2_note_to_legacy;
use koji::composition::ornamentation_v2::engine::{default_config, ornament_canon};
use koji::composition::ornamentation_v2::profiles::{
    profile_baroque_ornament, profile_common_practice, profile_modal_canon,
};
use koji::composition::ornamentation_v2::types::{
    HarmonyEvent, OrnamentStyleProfile, WORKFLOW_CANON_FIRST, all_enabled_ornaments,
};
use koji::composition::melodic_canon::{
    MelodicCanon, NoteEvent, build_mensuration_voices, canon_to_ornamented_note_events,
    plan_ornament_subdivisions, realize_degree, CADENCE_LEN, DEFAULT_VELOCITY,
};
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

pub const BEAST_SCORE_VERSION: u32 = 1;
pub const BEAST_THEME_LEN: u32 = 12;
/// Sub-ticks per structural note for the 3-voice ornamented path.
/// Must divide evenly by 2 and 4 for Montanos subdivisions.
pub const BEAST_CANON_TIME_UNIT: u32 = 4;
pub const BEAST_TIME_UNIT: u32 = 480;
pub const BEAST_REST_PITCH: u8 = 255;

#[derive(Copy, Drop, Serde)]
pub struct BeastSoundSeeds {
    pub motif_seed: felt252,
    pub canon_seed: felt252,
    pub orchestration_seed: felt252,
    pub ornament_seed: felt252,
}

#[derive(Drop)]
pub struct BeastTheme {
    pub degrees: Array<i32>,
    pub steps: Array<i32>,
    pub theme_hash: felt252,
}

#[derive(Drop)]
pub struct BeastForm {
    pub events: Array<NoteEvent>,
    pub score_hash: felt252,
    pub section_count: u8,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastMusicState {
    pub species_id: u8,
    pub name_variant_id: u32,
    pub visual_rarity: u8,
    pub sound_seed: felt252,
    pub params_hash: felt252,
    pub score_hash: felt252,
    pub engine_version: u32,
}

pub fn derive_beast_sound_seeds(sound_seed: felt252) -> BeastSoundSeeds {
    BeastSoundSeeds {
        motif_seed: hash2(sound_seed, 'MOTIF'),
        canon_seed: hash2(sound_seed, 'CANON'),
        orchestration_seed: hash2(sound_seed, 'ORCHESTRATION'),
        ornament_seed: hash2(sound_seed, 'ORNAMENT'),
    }
}

fn hash2(a: felt252, b: felt252) -> felt252 {
    let mut h = PoseidonTrait::new();
    h = h.update(a);
    h = h.update(b);
    h.finalize()
}

fn hash5(a: felt252, b: felt252, c: felt252, d: felt252, e: felt252) -> felt252 {
    let mut h = PoseidonTrait::new();
    h = h.update(a);
    h = h.update(b);
    h = h.update(c);
    h = h.update(d);
    h = h.update(e);
    h.finalize()
}

pub fn beast_params_hash(params: BeastCompositionParams) -> felt252 {
    let mut h = PoseidonTrait::new();
    h = h.update(params.species_id.into());
    h = h.update(params.name_variant_id.into());
    h = h.update(params.mode_id.into());
    h = h.update(params.tonic_keynum.into());
    h = h.update(params.tier.into());
    h = h.update(params.weakness.into());
    h = h.update(params.canon_config_id.into());
    h = h.update(params.profile_id.into());
    h = h.update(params.voice_count.into());
    h = h.update(params.section_count.into());
    h = h.update(params.stretto_bucket.into());
    h = h.update(params.stretto_lag.into());
    h = h.update(params.ornament_density.into());
    h = h.update(params.articulation_profile.into());
    h.finalize()
}

fn degree_hash(seed: felt252, step_index: u32, leader_degree: i32, prior_hash: felt252) -> u32 {
    let d: felt252 = if leader_degree < 0 {
        (1000_i32 + leader_degree).try_into().unwrap()
    } else {
        leader_degree.try_into().unwrap()
    };
    let h = hash5(seed, 'LEADER_WALK_V2', step_index.into(), d, prior_hash);
    let hu: u256 = h.into();
    (hu % 0x100000000).try_into().unwrap()
}

fn theme_hash(degrees: Span<i32>) -> felt252 {
    let mut h = PoseidonTrait::new();
    h = h.update('BEAST_THEME_V1');
    let mut i: u32 = 0;
    loop {
        if i >= degrees.len() {
            break;
        }
        let d = *degrees.at(i);
        let enc: felt252 = if d < 0 {
            (1000_i32 + d).try_into().unwrap()
        } else {
            d.try_into().unwrap()
        };
        h = h.update(enc);
        i += 1;
    };
    h.finalize()
}

fn candidate_step_at(index: u32) -> i32 {
    if index == 0 {
        -2
    } else if index == 1 {
        -1
    } else if index == 2 {
        1
    } else {
        2
    }
}

pub fn walk_leader_hashed(seed: felt252, len: u32, register_band: i32) -> (Array<i32>, Array<i32>) {
    assert(len >= 2, 'beast len >=2');
    let mut degrees: Array<i32> = ArrayTrait::new();
    let mut steps: Array<i32> = ArrayTrait::new();
    degrees.append(0);
    let mut prior_hash = hash2(seed, 'BEAST_PRIOR');
    let mut p: u32 = 1;
    loop {
        if p >= len {
            break;
        }
        let cur = *degrees.at(degrees.len() - 1);
        let raw = degree_hash(seed, p, cur, prior_hash);
        let mut picked = 0_i32;
        let mut found = false;
        let mut tries: u32 = 0;
        loop {
            if tries >= 4 || found {
                break;
            }
            let idx = (raw + tries) % 4;
            let cand = candidate_step_at(idx);
            let next = cur + cand;
            if next >= -register_band && next <= register_band {
                picked = cand;
                found = true;
            }
            tries += 1;
        };
        if !found {
            if cur > 0 {
                picked = -1;
            } else if cur < 0 {
                picked = 1;
            } else {
                picked = 0;
            }
        }
        let next_degree = cur + picked;
        degrees.append(next_degree);
        steps.append(picked);
        let picked_enc: felt252 = if picked < 0 {
            (1000_i32 + picked).try_into().unwrap()
        } else {
            picked.try_into().unwrap()
        };
        prior_hash = hash2(prior_hash, picked_enc);
        p += 1;
    };
    (degrees, steps)
}

pub fn build_beast_theme(params: BeastCompositionParams, motif_seed: felt252) -> BeastTheme {
    let len = BEAST_THEME_LEN + if params.tier <= 2 { 4 } else { 0 };
    let band: i32 = if params.register_band == 0 {
        5
    } else {
        7
    };
    let (degrees, steps) = walk_leader_hashed(motif_seed, len, band);
    let th = theme_hash(degrees.span());
    BeastTheme { degrees, steps, theme_hash: th }
}

fn canonical_to_melodic_mode(mode_id: u8) -> u8 {
    if mode_id == 4 {
        1 // Dorian
    } else if mode_id == 5 {
        2 // Phrygian
    } else if mode_id == 7 {
        5 // Aeolian
    } else if mode_id == 8 {
        5 // Harmonic minor renders through natural-minor-safe canon mode.
    } else if mode_id == 6 {
        2 // Locrian leans into Phrygian for the existing diatonic renderer.
    } else if mode_id == 26 {
        1 // Dorian #4 keeps Dorian contour in v1 MIDI.
    } else {
        5
    }
}

fn transposed_tonic(tonic: u8, shift: i32) -> u8 {
    let raw: i32 = tonic.into() + shift;
    if raw < 24 {
        24
    } else if raw > 96 {
        96
    } else {
        raw.try_into().unwrap()
    }
}

fn voice_offset(voice_id: u32) -> i32 {
    if voice_id == 0 {
        0
    } else if voice_id == 1 {
        -4 // canon at the 5th below (renaissance imitation style)
    } else if voice_id == 2 {
        3 // 4th above leader (= octave above voice 1, as in config_three_voice_5b_8va)
    } else {
        -8 // bass: two 5ths below leader, deep foundation
    }
}

fn append_events(ref target: Array<NoteEvent>, src: Span<NoteEvent>) {
    let mut i: u32 = 0;
    loop {
        if i >= src.len() {
            break;
        }
        target.append(*src.at(i));
        i += 1;
    }
}

fn apply_section_offset(events: Span<NoteEvent>, section_offset: u32) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        out.append(
            NoteEvent {
                time: e.time + section_offset,
                duration: e.duration,
                pitch: e.pitch,
                velocity: e.velocity,
                voice_id: e.voice_id,
            },
        );
        i += 1;
    };
    out
}

fn plan_from_beast_articulation(profile: u8, ceiling: u8) -> ArticulationPlan {
    if profile == ARTICULATION_STACCATO {
        ArticulationPlan { pattern: array![ART_STACCATO], velocity_ceiling: ceiling, min_duration: 60 }
    } else if profile == ARTICULATION_TENUTO {
        ArticulationPlan { pattern: array![ART_TENUTO], velocity_ceiling: ceiling, min_duration: 60 }
    } else if profile == ARTICULATION_ACCENT {
        ArticulationPlan {
            pattern: array![ART_ACCENT, ART_NORMAL, ART_NORMAL, ART_NORMAL],
            velocity_ceiling: ceiling,
            min_duration: 60,
        }
    } else if profile == ARTICULATION_PORTATO {
        ArticulationPlan { pattern: array![ART_PORTATO], velocity_ceiling: ceiling, min_duration: 60 }
    } else {
        ArticulationPlan { pattern: array![ART_NORMAL], velocity_ceiling: ceiling, min_duration: 60 }
    }
}

pub fn build_beast_section(
    params: BeastCompositionParams,
    theme: @BeastTheme,
    section_id: u8,
    section_offset: u32,
) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let tonic = transposed_tonic(params.tonic_keynum, section_tonic_shift(params, section_id));
    let mode = canonical_to_melodic_mode(params.mode_id);
    let len = theme.degrees.len();
    let unit = BEAST_TIME_UNIT;
    let mut v: u32 = 0;
    loop {
        if v >= params.voice_count {
            break;
        }
        let entry = if v == 0 {
            0
        } else {
            v * params.stretto_lag
        };
        let offset = voice_offset(v);
        let mut p: u32 = 0;
        loop {
            if p >= len {
                break;
            }
            let base_degree = *theme.degrees.at(p);
            let mut deg = if params.use_inversion && v == 1 {
                4 - base_degree
            } else {
                base_degree + offset
            };
            if v == 1 && p + entry < len {
                let leader_degree = *theme.degrees.at(p + entry);
                let leader_pitch = realize_degree(7, leader_degree, tonic, mode);
                let follower_pitch = realize_degree(7, deg, tonic, mode);
                if !ic_pair_safe(leader_pitch, follower_pitch) {
                    deg += 1;
                    let repaired = realize_degree(7, deg, tonic, mode);
                    if !ic_pair_safe(leader_pitch, repaired) {
                        deg -= 2;
                    }
                }
            }
            out.append(
                NoteEvent {
                    time: section_offset + (entry + p) * unit,
                    duration: unit,
                    pitch: realize_degree(7, deg, tonic, mode),
                    velocity: DEFAULT_VELOCITY,
                    voice_id: v,
                },
            );
            p += 1;
        };
        v += 1;
    };
    if params.use_countersubject {
        let cs = generate_countersubject(
            theme.degrees.span(),
            @default_countersubject_config(),
            hash2(params.name_variant_id.into(), params.species_id.into()),
            7,
            mode,
            tonic,
            unit,
        );
        if countersubject_invertible(theme.degrees.span(), @cs) {
            let cs_events = countersubject_to_note_events(@cs, 0, params.voice_count);
            let shifted = apply_section_offset(cs_events.span(), section_offset);
            append_events(ref out, shifted.span());
        }
    }
    let plan = plan_from_beast_articulation(params.articulation_profile, params.velocity_ceiling);
    apply_articulation_plan(out.span(), @plan)
}

fn section_duration(theme_len: u32, params: BeastCompositionParams) -> u32 {
    (theme_len + params.stretto_lag * (params.voice_count + 1)) * BEAST_TIME_UNIT
}

pub fn build_beast_form(params: BeastCompositionParams, sound_seed: felt252) -> BeastForm {
    let seeds = derive_beast_sound_seeds(sound_seed);
    let theme = build_beast_theme(params, seeds.motif_seed);
    let mut events: Array<NoteEvent> = ArrayTrait::new();
    let dur = section_duration(theme.degrees.len(), params);
    let mut s: u8 = 0;
    loop {
        if s >= params.section_count {
            break;
        }
        let section = build_beast_section(params, @theme, s, s.into() * dur);
        append_events(ref events, section.span());
        s += 1;
    };
    let score_hash = hash5(
        beast_params_hash(params),
        theme.theme_hash,
        params.section_count.into(),
        params.stretto_bucket.into(),
        BEAST_SCORE_VERSION.into(),
    );
    BeastForm { events, score_hash, section_count: params.section_count }
}

pub fn build_beast_form_from_traits(
    species_id: u8,
    name_variant_id: u32,
    visual_rarity: u8,
    sound_seed: felt252,
    stats: BeastLiveStats,
) -> BeastForm {
    let params = map_beast_traits_to_composition_params(
        species_id, name_variant_id, visual_rarity, sound_seed, stats,
    );
    build_beast_form(params, sound_seed)
}

pub fn get_composition_params(
    species_id: u8,
    name_variant_id: u32,
    visual_rarity: u8,
    sound_seed: felt252,
    stats: BeastLiveStats,
) -> BeastCompositionParams {
    map_beast_traits_to_composition_params(
        species_id, name_variant_id, visual_rarity, sound_seed, stats,
    )
}

pub fn get_score_hash(params: BeastCompositionParams, sound_seed: felt252) -> felt252 {
    let form = build_beast_form(params, sound_seed);
    form.score_hash
}

pub fn get_music_state(
    species_id: u8,
    name_variant_id: u32,
    visual_rarity: u8,
    sound_seed: felt252,
    stats: BeastLiveStats,
) -> BeastMusicState {
    let params = get_composition_params(
        species_id, name_variant_id, visual_rarity, sound_seed, stats,
    );
    BeastMusicState {
        species_id,
        name_variant_id,
        visual_rarity,
        sound_seed,
        params_hash: beast_params_hash(params),
        score_hash: get_score_hash(params, sound_seed),
        engine_version: BEAST_SCORE_VERSION,
    }
}

pub fn get_music_state_hash(state: BeastMusicState) -> felt252 {
    let mut h = PoseidonTrait::new();
    h = h.update(state.species_id.into());
    h = h.update(state.name_variant_id.into());
    h = h.update(state.visual_rarity.into());
    h = h.update(state.sound_seed);
    h = h.update(state.params_hash);
    h = h.update(state.score_hash);
    h = h.update(state.engine_version.into());
    h.finalize()
}

pub fn note_events_valid(events: Span<NoteEvent>) -> bool {
    if events.len() == 0 {
        return false;
    }
    let mut ok = true;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() || !ok {
            break;
        }
        let e = *events.at(i);
        if e.pitch > 127 || e.duration == 0 || e.voice_id > 15 {
            ok = false;
        }
        i += 1;
    };
    ok
}

pub fn extract_voice_pitches(events: Span<NoteEvent>, voice_id: u32) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        if e.voice_id == voice_id {
            out.append(e.pitch);
        }
        i += 1;
    };
    out
}

pub fn first_two_voices_invertible(events: Span<NoteEvent>) -> bool {
    let mut saw_overlap = false;
    let mut ok = true;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() || !ok {
            break;
        }
        let a = *events.at(i);
        if a.voice_id == 0 {
            let mut j: u32 = 0;
            loop {
                if j >= events.len() || !ok {
                    break;
                }
                let b = *events.at(j);
                if b.voice_id == 1 && b.time == a.time {
                    saw_overlap = true;
                    if !ic_pair_safe(a.pitch, b.pitch) {
                        ok = false;
                    }
                }
                j += 1;
            };
        }
        i += 1;
    };
    saw_overlap && ok
}

pub fn beast_form_to_midi(form: @BeastForm, tempo_us: u32) -> Midi {
    // NoteOn/NoteOff.time is in microseconds; NoteEvent.time is in BEAST_TIME_UNIT ticks.
    // Convert: time_us = ticks * tempo_us / BEAST_TIME_UNIT
    let tempo: u64 = tempo_us.into();
    let unit: u64 = BEAST_TIME_UNIT.into();
    let mut messages: Array<Message> = ArrayTrait::new();
    messages.append(Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }));
    let mut i: u32 = 0;
    loop {
        if i >= form.events.len() {
            break;
        }
        let e = *form.events.at(i);
        let on_us: u64 = e.time.into() * tempo / unit;
        let off_us: u64 = (e.time + e.duration).into() * tempo / unit;
        messages.append(
            Message::NOTE_ON(
                koji::midi::types::NoteOn {
                    channel: e.voice_id.try_into().unwrap(),
                    note: e.pitch,
                    velocity: e.velocity,
                    time: on_us,
                },
            ),
        );
        messages.append(
            Message::NOTE_OFF(
                koji::midi::types::NoteOff {
                    channel: e.voice_id.try_into().unwrap(),
                    note: e.pitch,
                    velocity: 64,
                    time: off_us,
                },
            ),
        );
        i += 1;
    };
    Midi { events: messages.span() }
}

// ─────────────────────────────────────────────────────────────
// Three-voice ornamented beast canon (renaissance-style architecture)
// ─────────────────────────────────────────────────────────────

/// Per-section tonic shift in semitones. Shared by both render paths.
pub fn section_tonic_shift(params: BeastCompositionParams, section_id: u8) -> i32 {
    if section_id == 1 {
        weakness_section_b_shift(params.weakness)
    } else if section_id == 2 {
        if params.use_inversion {
            -3
        } else {
            3
        }
    } else if section_id >= 4 {
        2
    } else {
        0
    }
}

/// Extract an 8-bit LCG seed from a Poseidon felt252, matching the renaissance ornament seed
/// extraction pattern used in `generate_ornamented_canon`.
fn beast_orn_seed(ornament_seed: felt252) -> u32 {
    let s: u256 = ornament_seed.into();
    let s32: u32 = (s % 256).try_into().unwrap();
    if s32 == 0 {
        19
    } else {
        s32
    }
}

/// Build a `MelodicCanon` from the beast theme with three-voice renaissance offsets
/// [0, −4, +3] (leader → 5th below → 4th above) and stretto entry delays.
/// `time_unit = BEAST_CANON_TIME_UNIT = 4` so Montanos 2× and 4× subdivisions divide evenly.
pub fn beast_theme_to_melodic_canon(
    theme: @BeastTheme, mode_id: u8, tonic_keynum: u8, stretto_lag: u32,
) -> MelodicCanon {
    let offsets_span: Span<i32> = array![0_i32, -4, 3].span();
    let entries_span: Span<u32> = array![0_u32, stretto_lag, 2 * stretto_lag].span();
    let dilations_span: Span<u32> = array![1_u32, 1, 1].span();
    let voices = build_mensuration_voices(offsets_span, entries_span, dilations_span);
    MelodicCanon {
        config_id: 4,
        config_name: 'beast_3v_5b_8va',
        offsets: offsets_span,
        leader_degrees: theme.degrees.span(),
        leader_steps: theme.steps.span(),
        mode_id,
        tonic_keynum,
        time_unit: BEAST_CANON_TIME_UNIT,
        voices: voices.span(),
        octave: 7,
        profile_id: 0,
    }
}

/// Render the full beast multi-section form as a three-voice ornamented canon.
///
/// Each section uses the same hashed theme but a different tonic (shifted by weakness/scar/etc.).
/// Ornamentation uses Montanos "divided" passing tones, identical to
/// `renaissance_canon_long_3voice_ornamented_midi_test`.
///
/// `step_us = tempo_us / BEAST_CANON_TIME_UNIT`; each structural note = one quarter beat.
pub fn build_beast_ornamented_midi(
    params: BeastCompositionParams, sound_seed: felt252,
) -> Midi {
    let seeds = derive_beast_sound_seeds(sound_seed);
    let theme = build_beast_theme(params, seeds.motif_seed);
    let mode = canonical_to_melodic_mode(params.mode_id);
    let orn_seed = beast_orn_seed(seeds.ornament_seed);

    // step_us: microseconds per sub-tick (4 sub-ticks per structural note = quarter note)
    let step_us: u64 = params.tempo_us.into() / BEAST_CANON_TIME_UNIT.into();

    // section length in sub-ticks: theme_len notes + 2 stretto-lag tails for voices 1 and 2
    let theme_len = theme.degrees.len();
    let cycle_ticks: u32 = (theme_len + 2 * params.stretto_lag) * BEAST_CANON_TIME_UNIT;
    let cycle_us: u64 = cycle_ticks.into() * step_us;

    let mut messages: Array<Message> = ArrayTrait::new();
    messages.append(Message::SET_TEMPO(SetTempo { tempo: params.tempo_us, time: Option::Some(0) }));

    let mut section_us: u64 = 0;
    let mut s: u8 = 0;
    loop {
        if s >= params.section_count {
            break;
        }
        let shift = section_tonic_shift(params, s);
        let tonic = transposed_tonic(params.tonic_keynum, shift);
        let canon = beast_theme_to_melodic_canon(@theme, mode, tonic, params.stretto_lag);
        let subs = plan_ornament_subdivisions(orn_seed, canon.leader_steps, CADENCE_LEN);
        let events = canon_to_ornamented_note_events(@canon, subs.span());

        let n = events.len();
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *events.at(i);
            let on_us: u64 = section_us + e.time.into() * step_us;
            let off_us: u64 = on_us + e.duration.into() * step_us;
            let ch: u8 = e.voice_id.try_into().unwrap();
            messages.append(Message::NOTE_ON(NoteOn { channel: ch, note: e.pitch, velocity: e.velocity, time: on_us }));
            messages.append(Message::NOTE_OFF(NoteOff { channel: ch, note: e.pitch, velocity: 64, time: off_us }));
            i += 1;
        };

        section_us += cycle_us;
        s += 1;
    };
    Midi { events: messages.span() }
}

// ─────────────────────────────────────────────────────────────
// Beast IC canon with V2 baroque ornamentation
// ─────────────────────────────────────────────────────────────

/// Number of leader notes for the IC canon walk, scaled by beast tier.
/// Tier 1-2 (high-tier / formidable) get the longest phrase for maximum imitative complexity.
fn ic_canon_length_for_tier(tier: u8) -> u32 {
    if tier <= 2 {
        36
    } else if tier == 3 {
        28
    } else if tier == 4 {
        20
    } else {
        16
    }
}

/// Extract a non-zero 8-bit seed from the ornament sub-seed, per section.
fn beast_ic_orn_seed(ornament_seed: felt252, section_id: u8) -> felt252 {
    let base = hash2(ornament_seed, section_id.into());
    let s: u256 = base.into();
    let bits: u32 = (s % 256).try_into().unwrap();
    if bits == 0 {
        19_u32.into()
    } else {
        bits.into()
    }
}

/// Select V2 ornament style from beast ornament density.
/// High-density beasts get baroque surface; mid-density get modal canon; sparse get common practice.
fn ornament_style_for_density(density: u8) -> OrnamentStyleProfile {
    if density >= 5 {
        profile_baroque_ornament()
    } else if density >= 3 {
        profile_modal_canon()
    } else {
        profile_common_practice()
    }
}

/// Generate a fully-ornamented IC three-voice canon MIDI for a beast, mapping all beast qualities
/// to the IC canon parameters:
///
/// - `tier`            → phrase length (longer = more complex imitative structure)
/// - `mode_id`         → diatonic mode (Dorian, Phrygian, Aeolian, etc.)
/// - `tonic_keynum`    → root pitch, shifted per section by `weakness`/`use_inversion`
/// - `ornament_density`→ V2 style: ≥5=baroque, ≥3=modal_canon, else=common_practice
/// - `tempo_us`        → MIDI tempo (fast for ANIMATED, slow for COMMON)
/// - `use_countersubject` → adds IC-safe CS melody on channel 3 (above leader)
/// - `use_inversion`   → appends an extra IC octave-inversion section after normal sections
/// - `section_count`   → how many repetitions (with tonic shifts from weakness/scar)
/// - `velocity_ceiling`→ applied to ornament engine velocity cap
pub fn build_beast_ic_canon_midi(params: BeastCompositionParams, sound_seed: felt252) -> Midi {
    let seeds = derive_beast_sound_seeds(sound_seed);
    let mode = canonical_to_melodic_mode(params.mode_id);
    let step_us: u64 = params.tempo_us.into() / BEAST_CANON_TIME_UNIT.into();

    let length = ic_canon_length_for_tier(params.tier);
    // three_5b_8va: 3 voices entering at ticks 0, 1, 2 → tail = nv - 1 = 2
    let nv: u32 = 3;
    let unit = BEAST_CANON_TIME_UNIT;
    let cycle_ticks: u32 = (length + nv - 1) * unit;
    let cycle_us: u64 = cycle_ticks.into() * step_us;

    let mut messages: Array<Message> = ArrayTrait::new();
    messages
        .append(Message::SET_TEMPO(SetTempo { tempo: params.tempo_us, time: Option::Some(0) }));

    // Optional extra inversion pass appended after all normal sections.
    let total_sections: u8 = params.section_count + if params.use_inversion {
        1
    } else {
        0
    };

    let mut section_us: u64 = 0;
    let mut s: u8 = 0;
    loop {
        if s >= total_sections {
            break;
        }
        // The extra inversion section mirrors the final normal section's tonic.
        let is_inversion_pass = params.use_inversion && s == params.section_count;
        let base_section: u8 = if is_inversion_pass {
            params.section_count - 1
        } else {
            s
        };

        let shift = section_tonic_shift(params, base_section);
        let tonic = transposed_tonic(params.tonic_keynum, shift);

        let canon_seed = hash2(seeds.canon_seed, base_section.into());
        let canon = generate_invertible_melodic_canon_mode(canon_seed, 4, length, mode, tonic);

        // Single harmony event spanning the cycle for the V2 engine consonance checks.
        let tonic_pc = tonic % 12;
        let mut harmony: Array<HarmonyEvent> = ArrayTrait::new();
        harmony
            .append(
                HarmonyEvent {
                    root_pc: tonic_pc,
                    bass_pc: tonic_pc,
                    start: 0,
                    duration: cycle_ticks,
                    function_label: 0,
                },
            );

        let orn_seed_val = beast_ic_orn_seed(seeds.ornament_seed, base_section);
        let mut orn_cfg = default_config(orn_seed_val);
        orn_cfg.style = ornament_style_for_density(params.ornament_density);
        orn_cfg.canon_workflow = WORKFLOW_CANON_FIRST;
        let enabled = all_enabled_ornaments();
        let orn_result = ornament_canon(@canon, harmony.span(), orn_cfg, enabled.span());
        let orn_span = orn_result.events.span();
        let orn_n = orn_span.len();

        // Emit ornamented canon voices (channels 0-2).
        // Inversion pass: raise voice 1 by an octave to demonstrate IC invertibility.
        let mut i: u32 = 0;
        loop {
            if i >= orn_n {
                break;
            }
            let legacy = v2_note_to_legacy(*orn_span.at(i));
            let pitch: u8 = if is_inversion_pass
                && legacy.voice_id == 1
                && legacy.pitch <= 115 {
                legacy.pitch + 12
            } else {
                legacy.pitch
            };
            let on_us: u64 = section_us + legacy.time.into() * step_us;
            let off_us: u64 = on_us + legacy.duration.into() * step_us;
            let ch: u8 = legacy.voice_id.try_into().unwrap();
            messages
                .append(
                    Message::NOTE_ON(
                        NoteOn { channel: ch, note: pitch, velocity: legacy.velocity, time: on_us },
                    ),
                );
            messages
                .append(
                    Message::NOTE_OFF(NoteOff { channel: ch, note: pitch, velocity: 64, time: off_us }),
                );
            i += 1;
        };

        // Countersubject on channel 3 (one above the 3 IC canon voices).
        // Skipped during the inversion pass to keep the texture clean.
        if params.use_countersubject && !is_inversion_pass {
            let cs_config = default_countersubject_config();
            let cs_seed = hash2(seeds.motif_seed, base_section.into());
            let cs = generate_countersubject(
                canon.leader_degrees,
                @cs_config,
                cs_seed,
                7,
                mode,
                tonic,
                unit,
            );
            let cs_events = countersubject_to_note_events(@cs, 0, 3);
            let mut j: u32 = 0;
            loop {
                if j >= cs_events.len() {
                    break;
                }
                let e = *cs_events.at(j);
                let on_us: u64 = section_us + e.time.into() * step_us;
                let off_us: u64 = on_us + e.duration.into() * step_us;
                messages
                    .append(
                        Message::NOTE_ON(
                            NoteOn { channel: 3, note: e.pitch, velocity: e.velocity, time: on_us },
                        ),
                    );
                messages
                    .append(
                        Message::NOTE_OFF(
                            NoteOff { channel: 3, note: e.pitch, velocity: 64, time: off_us },
                        ),
                    );
                j += 1;
            };
        }

        section_us += cycle_us;
        s += 1;
    };

    Midi { events: messages.span() }
}

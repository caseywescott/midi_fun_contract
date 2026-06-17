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
use koji::composition::invertible_counterpoint::ic_pair_safe;
use koji::composition::melodic_canon::{NoteEvent, realize_degree, DEFAULT_VELOCITY};
use koji::midi::types::{Message, Midi, SetTempo};

pub const BEAST_SCORE_VERSION: u32 = 1;
pub const BEAST_THEME_LEN: u32 = 12;
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
        4
    } else if voice_id == 2 {
        -3
    } else {
        7
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
    let shift = if section_id == 1 {
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
    };
    let tonic = transposed_tonic(params.tonic_keynum, shift);
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
    let mut messages: Array<Message> = ArrayTrait::new();
    messages.append(Message::SET_TEMPO(SetTempo { tempo: tempo_us, time: Option::Some(0) }));
    let mut i: u32 = 0;
    loop {
        if i >= form.events.len() {
            break;
        }
        let e = *form.events.at(i);
        messages.append(
            Message::NOTE_ON(
                koji::midi::types::NoteOn {
                    channel: e.voice_id.try_into().unwrap(),
                    note: e.pitch,
                    velocity: e.velocity,
                    time: e.time.into(),
                },
            ),
        );
        messages.append(
            Message::NOTE_OFF(
                koji::midi::types::NoteOff {
                    channel: e.voice_id.try_into().unwrap(),
                    note: e.pitch,
                    velocity: 64,
                    time: (e.time + e.duration).into(),
                },
            ),
        );
        i += 1;
    };
    Midi { events: messages.span() }
}

//! Beast Sound engine v2: invertible-counterpoint canon with V2 ornaments, driven by the same
//! `BeastCompositionParams` as engine v1 (`beast_score::build_beast_form`, unchanged).
//!
//! Defaults and their alternatives are documented in docs/beasts/engine_v2_defaults.md. Each
//! default sits behind `EngineV2Options` so it can be A/B-rendered; production uses
//! `default_v2_options()`.

use core::poseidon::poseidon_hash_span;
use koji::composition::aesthetic_profile::{PROFILE_RENAISSANCE_INVERTIBLE_ID, profile_by_id};
use koji::composition::articulation::apply_articulation_plan;
use koji::composition::beast_score::{
    BeastForm, beast_params_hash, canonical_to_melodic_mode, derive_beast_sound_seeds,
    ornament_style_for_density, plan_from_beast_articulation,
    section_tonic_shift, theme_hash, transposed_tonic,
};
use koji::composition::beast_trait_map::{
    BeastCompositionParams, BeastOrnamentPolicy, prefix2_ornament_policy,
};
use koji::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, beast_form_to_smf_bytes, beast_sound_seed, is_genesis,
    map_v3_beast_to_composition_params, type_tier_family,
};
use koji::composition::countersubject::{
    countersubject_to_note_events, default_countersubject_config, generate_countersubject,
};
use koji::composition::invertible_counterpoint::all_pairs_octave_invertible;
use koji::composition::melodic_canon::{
    MelodicCanon, NoteEvent, all_pairs_clash_free, build_mensuration_voices, exact_imitation,
    ic_constraints_all_lags, walk_leader_constraints_ic_hashed,
};
use koji::composition::ornamentation_v2::canon::v2_note_to_legacy;
use koji::composition::ornamentation_v2::engine::{default_config, ornament_canon};
use koji::composition::ornamentation_v2::types::{
    HARMONY_FN_MINOR_TONIC, HarmonyEvent, ORNAMENT_KIND_COUNT, WORKFLOW_CANON_FIRST,
};

pub const BEAST_ENGINE_V2: u32 = 2;
/// Sub-ticks per structural note in the V2 ornament engine.
pub const V2_CANON_UNIT: u32 = 4;
/// Output ticks per V2 sub-tick (480 per structural note, one beat).
pub const V2_TICKS_PER_SUBTICK: u32 = 120;
pub const V2_TICKS_PER_NOTE: u32 = 480;
/// Canon at the sixth below and the third above: invertible at the octave for every entry lag
/// 1-4 at once, with a distinct melody per seed. (Config 4's [0, -4, +3] admits almost no
/// melodies once invertibility is enforced: a single one at lag 1.)
pub const V2_MAX_LAG: u32 = 4;
fn v2_offsets() -> Array<i32> {
    array![0, -5, 2]
}

/// D7: melody length by tier. 24 is the shortest length at which melodies stay distinct across a
/// whole tier (18,645 identities: 0.14% share a melody at 24 notes, 39% at 16).
pub fn v2_phrase_length(tier: u8) -> u32 {
    if tier <= 2 {
        36
    } else if tier == 3 {
        28
    } else {
        24
    }
}
/// Ornament kinds removed by the suffix policy (ornamentation_v2/types.cairo ids).
const ORN_SUSPENSION_FIRST: u8 = 8; // 8-12 suspensions, 13 retardation
const ORN_SUSPENSION_LAST: u8 = 13;
const ORN_TRILL_UPPER: u8 = 25;
const ORN_TRILL_LOWER: u8 = 26;
const ORN_CHROMATIC_FIRST: u8 = 29; // 29-30 chromatic approach, 31-32 enclosures
const ORN_CHROMATIC_LAST: u8 = 32;

#[derive(Copy, Drop, Serde)]
pub struct EngineV2Options {
    /// D1: one leader melody for the Beast, transposed per section.
    pub same_melody_each_section: bool,
    /// D2: entry lag follows `stretto_lag` (otherwise entries 0, 1, 2).
    pub stretto_entries: bool,
    /// D3: canon voices = min(voice_count, 3); voice_count 4 adds the countersubject.
    pub voices_follow_params: bool,
    /// D5: suffix policy filters ornament kinds (otherwise all kinds enabled).
    pub suffix_ornament_policy: bool,
    /// D6: minor tonic triad as ornament chord context (otherwise the engine's major triad).
    pub minor_harmony: bool,
}

pub fn default_v2_options() -> EngineV2Options {
    EngineV2Options {
        same_melody_each_section: true,
        stretto_entries: true,
        voices_follow_params: true,
        suffix_ornament_policy: true,
        minor_harmony: true,
    }
}

/// The ornament policy the V3 mapper used for this Beast (suffix policy, or the Genesis policy).
pub fn v3_ornament_policy(beast: PackableBeastV3) -> BeastOrnamentPolicy {
    if is_genesis(beast) {
        let family = type_tier_family(beast.beast_type, beast.tier);
        BeastOrnamentPolicy {
            profile_id: family.profile_id,
            density_cap: 1,
            allow_chromatic_approach: false,
            allow_suspension: beast.tier <= 3,
            allow_trill: false,
        }
    } else {
        prefix2_ornament_policy(beast.suffix - 1)
    }
}

/// D5: enabled V2 ornament kinds for a policy.
pub fn v2_enabled_ornaments(policy: BeastOrnamentPolicy, use_policy: bool) -> Array<u8> {
    let mut out: Array<u8> = array![];
    let mut k: u8 = 1;
    while k < ORNAMENT_KIND_COUNT {
        let suspension = k >= ORN_SUSPENSION_FIRST && k <= ORN_SUSPENSION_LAST;
        let trill = k == ORN_TRILL_UPPER || k == ORN_TRILL_LOWER;
        let chromatic = k >= ORN_CHROMATIC_FIRST && k <= ORN_CHROMATIC_LAST;
        let blocked = use_policy
            && ((suspension && !policy.allow_suspension)
                || (trill && !policy.allow_trill)
                || (chromatic && !policy.allow_chromatic_approach));
        if !blocked {
            out.append(k);
        }
        k += 1;
    }
    out
}

/// D3: number of canon voices.
pub fn v2_canon_voice_count(params: BeastCompositionParams, opts: EngineV2Options) -> u32 {
    if !opts.voices_follow_params {
        return 3;
    }
    if params.voice_count < 1 {
        1
    } else if params.voice_count > 3 {
        3
    } else {
        params.voice_count
    }
}

/// D2: structural notes between successive canon entries.
pub fn v2_entry_lag(params: BeastCompositionParams, opts: EngineV2Options) -> u32 {
    if opts.stretto_entries {
        params.stretto_lag
    } else {
        1
    }
}

fn felt_to_u32_low(f: felt252) -> u32 {
    let u: u256 = f.into();
    (u % 0x100000000).try_into().unwrap()
}

/// D8: 16-bit, never-zero seed for the V2 ornament LCG (mod 65536) in one section.
pub fn v2_ornament_seed(ornament_seed: felt252, section: u8) -> felt252 {
    let h = poseidon_hash_span(array![ornament_seed, 'V2_ORN', section.into()].span());
    (1 + felt_to_u32_low(h) % 65535).into()
}

fn leader_seed(canon_seed: felt252, same_melody: bool, section: u8) -> felt252 {
    if same_melody {
        poseidon_hash_span(array![canon_seed, 'V2_LEADER'].span())
    } else {
        poseidon_hash_span(array![canon_seed, 'V2_LEADER', section.into()].span())
    }
}

/// D10: hash of the complete event stream.
pub fn v2_events_hash(events: Span<NoteEvent>) -> felt252 {
    let mut packed: Array<felt252> = array!['BEAST_EVENTS_V2'];
    let mut i: u32 = 0;
    while i < events.len() {
        let e = *events.at(i);
        let word: u256 = e.time.into() * 0x10000000000000000
            + e.duration.into() * 0x100000000
            + e.pitch.into() * 0x10000
            + e.velocity.into() * 0x100
            + e.voice_id.into();
        packed.append(word.try_into().unwrap());
        i += 1;
    }
    poseidon_hash_span(packed.span())
}

/// Every voice's notes must be in time order without overlap (the MIDI and compact encoders
/// rely on it). Voices are 0..=4.
fn assert_voices_sequential(events: Span<NoteEvent>) {
    let mut last_end: Array<u32> = array![0, 0, 0, 0, 0];
    let mut i: u32 = 0;
    while i < events.len() {
        let e = *events.at(i);
        assert(e.voice_id < 5, 'v2 voice id');
        let prev = *last_end.at(e.voice_id);
        assert(e.time >= prev, 'v2 voice overlap');
        // rebuild with the updated slot (Cairo arrays are append-only)
        let mut next: Array<u32> = array![];
        let mut k: u32 = 0;
        while k < 5 {
            next.append(if k == e.voice_id {
                e.time + e.duration
            } else {
                *last_end.at(k)
            });
            k += 1;
        }
        last_end = next;
        i += 1;
    }
}

pub fn build_beast_form_v2(
    params: BeastCompositionParams,
    sound_seed: felt252,
    policy: BeastOrnamentPolicy,
    opts: EngineV2Options,
) -> BeastForm {
    let seeds = derive_beast_sound_seeds(sound_seed);
    let profile = profile_by_id(PROFILE_RENAISSANCE_INVERTIBLE_ID);
    let mode = canonical_to_melodic_mode(params.mode_id);
    let len = v2_phrase_length(params.tier);

    let nv = v2_canon_voice_count(params, opts);
    let lag = v2_entry_lag(params, opts);
    let all_offsets = v2_offsets();
    let mut offsets: Array<i32> = array![];
    let mut entries: Array<u32> = array![];
    let mut dilations: Array<u32> = array![];
    let mut v: u32 = 0;
    while v < nv {
        offsets.append(*all_offsets.at(v));
        entries.append(v * lag);
        dilations.append(1);
        v += 1;
    }
    let voices = build_mensuration_voices(offsets.span(), entries.span(), dilations.span());
    let max_entry = (nv - 1) * lag;
    let cycle_subticks = (len + max_entry) * V2_CANON_UNIT;
    let cycle_ticks = (len + max_entry) * V2_TICKS_PER_NOTE;

    let want_cs = params.use_countersubject
        || (opts.voices_follow_params && params.voice_count >= 4);
    let enabled = v2_enabled_ornaments(policy, opts.suffix_ornament_policy);
    let plan = plan_from_beast_articulation(params.articulation_profile, params.velocity_ceiling);
    let total_sections: u8 = params.section_count + if params.use_inversion {
        1
    } else {
        0
    };

    // D1: the Beast's melody, walked once under the constraints of every live state (3 voices,
    // entry lags 1-4), so history can change the arrangement but never the melody.
    let melody_constraints = ic_constraints_all_lags(all_offsets.span(), V2_MAX_LAG);
    let (motif_degrees, motif_steps) = walk_leader_constraints_ic_hashed(
        leader_seed(seeds.canon_seed, opts.same_melody_each_section, 0),
        all_offsets.span(),
        melody_constraints.span(),
        @profile,
        len,
    );
    let motif_hash = theme_hash(motif_degrees.span());

    let mut events: Array<NoteEvent> = array![];
    let mut s: u8 = 0;
    while s < total_sections {
        let is_inversion_pass = params.use_inversion && s == params.section_count;
        let base_section: u8 = if is_inversion_pass {
            params.section_count - 1
        } else {
            s
        };
        let tonic = transposed_tonic(params.tonic_keynum, section_tonic_shift(params, base_section));
        let (degrees, steps) = if opts.same_melody_each_section || base_section == 0 {
            (motif_degrees.clone(), motif_steps.clone())
        } else {
            walk_leader_constraints_ic_hashed(
                leader_seed(seeds.canon_seed, false, base_section),
                all_offsets.span(),
                melody_constraints.span(),
                @profile,
                len,
            )
        };
        let canon = MelodicCanon {
            config_id: 4,
            config_name: 'beast_v2',
            offsets: offsets.span(),
            leader_degrees: degrees.span(),
            leader_steps: steps.span(),
            mode_id: mode,
            tonic_keynum: tonic,
            time_unit: V2_CANON_UNIT,
            voices: voices.span(),
            octave: 7,
            profile_id: PROFILE_RENAISSANCE_INVERTIBLE_ID,
        };
        assert(exact_imitation(@canon), 'imitation broken');
        assert(all_pairs_clash_free(@canon, @profile), 'ic canon clash');
        assert(all_pairs_octave_invertible(@canon), 'canon not IC');

        let harmony: Array<HarmonyEvent> = array![
            HarmonyEvent {
                root_pc: tonic % 12,
                bass_pc: tonic % 12,
                start: 0,
                duration: cycle_subticks,
                function_label: if opts.minor_harmony {
                    HARMONY_FN_MINOR_TONIC
                } else {
                    0
                },
            },
        ];
        let mut cfg = default_config(v2_ornament_seed(seeds.ornament_seed, s));
        cfg.style = ornament_style_for_density(params.ornament_density);
        cfg.canon_workflow = WORKFLOW_CANON_FIRST;
        let ornamented = ornament_canon(@canon, harmony.span(), cfg, enabled.span());

        let section_start: u32 = s.into() * cycle_ticks;
        let mut section_events: Array<NoteEvent> = array![];
        let orn = ornamented.events.span();
        let mut i: u32 = 0;
        while i < orn.len() {
            let n = v2_note_to_legacy(*orn.at(i));
            let pitch: u8 = if is_inversion_pass && n.voice_id == 1 && n.pitch <= 115 {
                n.pitch + 12
            } else {
                n.pitch
            };
            section_events
                .append(
                    NoteEvent {
                        time: section_start + n.time * V2_TICKS_PER_SUBTICK,
                        duration: n.duration * V2_TICKS_PER_SUBTICK,
                        pitch,
                        velocity: n.velocity,
                        voice_id: n.voice_id,
                    },
                );
            i += 1;
        }
        if want_cs && !is_inversion_pass {
            let cs = generate_countersubject(
                degrees.span(),
                @default_countersubject_config(),
                poseidon_hash_span(array![seeds.motif_seed, 'V2_CS', base_section.into()].span()),
                7,
                mode,
                tonic,
                V2_TICKS_PER_NOTE,
            );
            let cs_events = countersubject_to_note_events(@cs, section_start, nv);
            let mut j: u32 = 0;
            while j < cs_events.len() {
                section_events.append(*cs_events.at(j));
                j += 1;
            }
        }
        let articulated = apply_articulation_plan(section_events.span(), @plan);
        let mut k: u32 = 0;
        while k < articulated.len() {
            events.append(*articulated.at(k));
            k += 1;
        }
        s += 1;
    }

    assert_voices_sequential(events.span());
    let score_hash = poseidon_hash_span(
        array![
            'BEAST_SCORE_V2', beast_params_hash(params), motif_hash,
            v2_events_hash(events.span()), BEAST_ENGINE_V2.into(),
        ]
            .span(),
    );
    let length_ticks: u32 = total_sections.into() * cycle_ticks;
    BeastForm { events, score_hash, section_count: total_sections, length_ticks }
}

pub fn build_v3_beast_form_v2_with(
    beast: PackableBeastV3, live: BeastV3LiveState, opts: EngineV2Options,
) -> BeastForm {
    let params = map_v3_beast_to_composition_params(beast, live);
    build_beast_form_v2(
        params, beast_sound_seed(beast.id, beast.prefix, beast.suffix), v3_ornament_policy(beast),
        opts,
    )
}

pub fn build_v3_beast_form_v2(beast: PackableBeastV3, live: BeastV3LiveState) -> BeastForm {
    build_v3_beast_form_v2_with(beast, live, default_v2_options())
}

/// Engine v2 score as a Standard MIDI File, packed `[byte_len, 31-byte chunks...]`.
pub fn v3_score_midi_v2(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252> {
    let params = map_v3_beast_to_composition_params(beast, live);
    let form = build_v3_beast_form_v2(beast, live);
    koji::midi::output::to_felt252_array(beast_form_to_smf_bytes(@form, params.tempo_us))
}

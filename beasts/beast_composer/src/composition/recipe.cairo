//! Pure normalized recipe construction and transient musical performance.
//! Edition clocks, purchases, births and hash availability are manager policy.
use beast_composer_inputs::{
    ArrangementInputs, BeastMusicalIdentity, ChannelPolicy, ComposerInputs,
    EditionCompositionConfig, GenerationInputs, MusicIdentity, ScoreInputs, SongInputs,
    SpecialArrangement, ThemeInputs, TreatmentInputs, validate_inputs, validate_performance,
};
use core::poseidon::poseidon_hash_span;
use crate::composition::beast_score::derive_beast_sound_seeds;
use crate::composition::beast_trait_map::{BeastCompositionParams, prefix2_ornament_policy};
use crate::composition::beast_v3_sound::{
    PackableBeastV3, beast_sound_seed, map_v3_beast_to_composition_params,
};
use crate::composition::genesis::{genesis_mode, genesis_theme, neutral_live};

pub fn score_params(x: SongInputs) -> BeastCompositionParams {
    let p = x.score;
    BeastCompositionParams {
        species_id: x.arrangement.identity.source_species_id,
        name_variant_id: x.arrangement.identity.name_variant_id.into(),
        mode_id: p.mode_id,
        tonic_keynum: p.tonic_keynum,
        register_band: x.theme.register_band,
        tier: p.tier,
        weakness: p.weakness,
        canon_config_id: 0,
        profile_id: 0,
        voice_count: p.voice_count.into(),
        section_count: p.section_count,
        stretto_bucket: 0,
        stretto_lag: p.stretto_lag.into(),
        use_inversion: p.use_inversion,
        use_countersubject: p.use_countersubject,
        use_compound_melody: false,
        ornament_density: p.ornament_density,
        articulation_profile: p.articulation_profile,
        velocity_ceiling: p.velocity_ceiling,
        tempo_us: p.tempo_us,
        score_version: 2,
    }
}

pub fn is_mega(sound_effects: u8) -> bool {
    validate_performance(sound_effects);
    sound_effects == 1 || sound_effects == 3
}

/// Performance never mutates the stored written recipe. Code0 is identity.
/// Apply integer microseconds/quarter subtraction before any staff interpretation.
pub fn apply_performance(x: ComposerInputs, sound_effects: u8) -> ComposerInputs {
    validate_inputs(x);
    validate_performance(sound_effects);
    if sound_effects == 0 {
        return x;
    }
    let (bump, lift, profile): (u32, u8, u8) = match sound_effects {
        1 => (25000, 12, 2),
        2 => (30000, 8, 5),
        _ => (45000, 15, 3),
    };
    match x {
        ComposerInputs::Song(mut song) => {
            let p = song.score;
            song
                .score =
                    ScoreInputs {
                        tempo_us: if p.tempo_us > bump {
                            p.tempo_us - bump
                        } else {
                            1
                        },
                        velocity_ceiling: cap_velocity(p.velocity_ceiling, lift),
                        articulation_profile: profile,
                        ..p,
                    };
            ComposerInputs::Song(song)
        },
        ComposerInputs::SoundCheck(mut check) => {
            check.tempo_us = if check.tempo_us > bump {
                check.tempo_us - bump
            } else {
                1
            };
            check.velocity_ceiling = cap_velocity(check.velocity_ceiling, lift);
            check.articulation_profile = profile;
            ComposerInputs::SoundCheck(check)
        },
    }
}

fn cap_velocity(base: u8, lift: u8) -> u8 {
    let n: u32 = base.into() + lift.into();
    if n > 127 {
        127
    } else {
        n.try_into().unwrap()
    }
}


/// Autonomous deterministic template factory. No clock/hash reads or sale policy.
/// Template predictability does not disclose future purchase/staff entropy.
pub fn get_generation_inputs(
    config: EditionCompositionConfig, edition_id: u64, identity: BeastMusicalIdentity,
) -> GenerationInputs {
    beast_composer_inputs::normalize_generation_identity(identity);
    let src = identity.species_id;
    let (prefix, suffix): (u8, u8) = if identity.name_variant_id == 0 {
        (0, 0)
    } else {
        let n = identity.name_variant_id - 1;
        ((n / 18 + 1).try_into().unwrap(), (n % 18 + 1).try_into().unwrap())
    };
    // This is initial musical derivation, never playback reconstruction. Public
    // recipes contain all results and direct composition consumes them unchanged.
    let g = PackableBeastV3 {
        id: src,
        prefix: 0,
        suffix: 0,
        level: 50,
        health: 200,
        shiny: 0,
        animated: 0,
        tier: identity.tier,
        beast_type: identity.family,
    };
    let motif = genesis_theme(src);
    let cb = if motif == 0 {
        g
    } else {
        PackableBeastV3 {
            prefix: ((motif - 1) / 18 + 1).try_into().unwrap(),
            suffix: ((motif - 1) % 18 + 1).try_into().unwrap(),
            ..g,
        }
    };
    let base = map_v3_beast_to_composition_params(cb, neutral_live());
    let bare = map_v3_beast_to_composition_params(g, neutral_live());
    let key_beast = if prefix == 0 {
        PackableBeastV3 {
            prefix: ((src - 1) % 69 + 1).try_into().unwrap(),
            suffix: ((src - 1) % 18 + 1).try_into().unwrap(),
            ..g,
        }
    } else {
        PackableBeastV3 { prefix, suffix, ..g }
    };
    let key = map_v3_beast_to_composition_params(key_beast, neutral_live());
    let mode_id = if prefix == 0 {
        genesis_mode(src, key.mode_id)
    } else {
        key.mode_id
    };
    let original_motif = derive_beast_sound_seeds(beast_sound_seed(src, cb.prefix, cb.suffix))
        .motif_seed;
    let motif_seed = if edition_id == 0 && config.composition_seed == 0 {
        original_motif
    } else {
        poseidon_hash_span(
            array!['BEAST_EDITION_V1', config.composition_seed, edition_id.into(), src.into(),]
                .span(),
        )
    };
    let song = SongInputs {
        theme: ThemeInputs { motif_seed, tier: identity.tier, register_band: base.register_band },
        score: ScoreInputs {
            mode_id,
            tonic_keynum: key.tonic_keynum,
            tier: identity.tier,
            weakness: base.weakness,
            voice_count: 4,
            section_count: if identity.tier <= 2 {
                4
            } else if identity.tier == 3 {
                3
            } else {
                2
            },
            stretto_lag: base.stretto_lag.try_into().unwrap(),
            use_inversion: base.use_inversion,
            use_countersubject: true,
            ornament_density: if prefix == 0 {
                bare.ornament_density
            } else {
                key.ornament_density
            },
            articulation_profile: 0,
            velocity_ceiling: 112,
            tempo_us: if src == 68 {
                342857
            } else {
                500000
            },
        },
        treatment: TreatmentInputs {
            rhythm_seed: motif_seed,
            flip_side: false,
            development: 0,
            direction: 0,
            spacing: 1,
            trill: prefix != 0 && prefix2_ornament_policy(suffix - 1).allow_trill,
            prominence: 2,
            section_rhythm: false,
        },
        arrangement: ArrangementInputs {
            family: identity.family,
            identity: MusicIdentity { source_species_id: src, name_variant_id: 0 },
            channel_count: if identity.tier <= 2 {
                5
            } else if identity.tier == 3 {
                4
            } else {
                3
            },
            channel_policy: ChannelPolicy::Genesis,
            special: if src == 68 {
                SpecialArrangement::Yeti(identity.name_variant_id)
            } else {
                SpecialArrangement::None
            },
            top_lead: true,
            balanced: true,
            weak_ties: true,
        },
    };
    validate_inputs(ComposerInputs::Song(song));
    GenerationInputs { base_song: song }
}

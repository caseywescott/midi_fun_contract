//! Independent normalized JS score parity, including direct field consumption.
use beast_composer_inputs::{
    ArrangementInputs, ChannelPolicy, ComposerInputs, MusicIdentity, ScoreInputs, SongInputs,
    SpecialArrangement, ThemeInputs, TreatmentInputs,
};
use crate::composition::beast_v11::build_v11_score_from_inputs;

fn normalized_case(index: u32) -> SongInputs {
    let mut x = SongInputs {
        theme: ThemeInputs { motif_seed: 2, tier: 2, register_band: 1 },
        score: ScoreInputs {
            mode_id: 4,
            tonic_keynum: 60,
            tier: 3,
            weakness: 2,
            voice_count: 4,
            section_count: 3,
            stretto_lag: 2,
            use_inversion: true,
            use_countersubject: true,
            ornament_density: 3,
            articulation_profile: 0,
            velocity_ceiling: 109,
            tempo_us: 500000,
        },
        treatment: TreatmentInputs {
            rhythm_seed: 47,
            flip_side: true,
            development: 1,
            direction: 2,
            spacing: 0,
            trill: true,
            prominence: 2,
            section_rhythm: false,
        },
        arrangement: ArrangementInputs {
            family: 0,
            identity: MusicIdentity { source_species_id: 1, name_variant_id: 37 },
            channel_count: 4,
            channel_policy: ChannelPolicy::Seeded(17),
            special: SpecialArrangement::None,
            top_lead: true,
            balanced: false,
            weak_ties: true,
        },
    };
    if index == 1 {
        x.theme.motif_seed = 12;
    }
    if index == 2 {
        x.theme.tier = 5;
    }
    if index == 3 {
        x.theme.register_band = 0;
    }
    if index == 4 {
        x.score.mode_id = 5;
    }
    if index == 5 {
        x.score.tonic_keynum = 65;
    }
    if index == 6 {
        x.score.tier = 1;
    }
    if index == 7 {
        x.score.weakness = 1;
    }
    if index == 8 {
        x.score.voice_count = 3;
    }
    if index == 9 {
        x.score.section_count = 2;
    }
    if index == 10 {
        x.score.stretto_lag = 4;
    }
    if index == 11 {
        x.score.use_inversion = false;
    }
    if index == 12 {
        x.score.use_countersubject = false;
    }
    if index == 13 {
        x.score.ornament_density = 7;
    }
    if index == 14 {
        x.score.articulation_profile = 1;
    }
    if index == 15 {
        x.score.articulation_profile = 2;
    }
    if index == 16 {
        x.score.articulation_profile = 3;
    }
    if index == 17 {
        x.score.articulation_profile = 5;
    }
    if index == 18 {
        x.score.velocity_ceiling = 72;
    }
    if index == 19 {
        x.score.tempo_us = 400001;
    }
    if index == 20 {
        x.treatment.rhythm_seed = 27;
    }
    if index == 21 {
        x.treatment.flip_side = false;
    }
    if index == 22 {
        x.treatment.development = 2;
    }
    if index == 23 {
        x.treatment.direction = 1;
    }
    if index == 24 {
        x.treatment.spacing = 2;
    }
    if index == 25 {
        x.treatment.trill = false;
    }
    if index == 26 {
        x.treatment.prominence = 0;
    }
    if index == 27 {
        x.arrangement.identity.source_species_id = 2;
    }
    if index == 28 {
        x.arrangement.identity.name_variant_id = 38;
    }
    if index >= 29 && index < 41 {
        x.score.mode_id = *array![4_u8, 5, 6, 7, 8, 26].at((index - 29) % 6);
        x.score.tonic_keynum = if index < 35 {
            24
        } else {
            96
        };
    }
    if index >= 41 {
        x.treatment.section_rhythm = true;
        if index == 42 {
            x.treatment.rhythm_seed = 0;
        }
        if index == 43 {
            x.theme.tier = 5;
        }
        if index == 44 {
            x.score.ornament_density = 7;
        }
        if index == 45 {
            x.score.voice_count = 2;
            x.score.use_countersubject = false;
            x.arrangement.channel_count = 3;
        }
    }
    assert(index < 46, 'unknown normalized case');
    x
}
fn parity_range(lo: u32, hi: u32) {
    let mut index = lo;
    while index < hi {
        let x = normalized_case(index);
        let score = build_v11_score_from_inputs(x);
        let mut flat: Array<felt252> = array![];
        let mut voice: u32 = 0;
        while voice <= 4 {
            for e in score.events.span() {
                assert(e.pitch >= 24 && e.pitch <= 108, 'normalized pitch');
                assert(
                    e.velocity >= 1 && e.velocity <= x.score.velocity_ceiling,
                    'normalized velocity',
                );
                let total: u32 = x.score.section_count.into() * score.section_ticks;
                assert(e.duration >= 60 && e.time + e.duration <= total, 'normalized time');
                if e.voice_id == voice {
                    flat.append(e.time.into());
                    flat.append(e.duration.into());
                    flat.append(e.pitch.into());
                    flat.append(e.velocity.into());
                    flat.append(e.voice_id.into());
                }
            }
            voice += 1;
        }
        println!(
            "INPUT_SCORE case={} notes={} ticks={} events={} wire={} tempo={}",
            index,
            score.events.len(),
            score.section_ticks,
            core::poseidon::poseidon_hash_span(flat.span()),
            core::poseidon::poseidon_hash_span(
                beast_composer_inputs::encode_inputs(ComposerInputs::Song(x)).span()
            ),
            score.params.tempo_us
        );
        index += 1;
    }
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_00() {
    parity_range(0, 4);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_01() {
    parity_range(4, 8);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_02() {
    parity_range(8, 12);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_03() {
    parity_range(12, 16);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_04() {
    parity_range(16, 20);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_05() {
    parity_range(20, 24);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_06() {
    parity_range(24, 28);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_07() {
    parity_range(28, 32);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_08() {
    parity_range(32, 36);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_09() {
    parity_range(36, 40);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_10() {
    parity_range(40, 44);
}

#[test]
#[available_gas(1000000000)]
fn normalized_score_parity_11() {
    parity_range(44, 46);
}

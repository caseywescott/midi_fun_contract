//! `pack_inputs` / `unpack_inputs` round trips over every species, bare and named, normal, shiny
//! and animated, and a spread of live states; plus the rejections (a field too wide, a foreign
//! layout).
use crate::composition::beast_trait_map::BeastCompositionParams;
use crate::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, map_v3_beast_to_composition_params,
};
use crate::composition::genesis::{species_tier, species_type};
use crate::composition::params_pack::{ComposerInputs, composer_inputs, pack_inputs, unpack_inputs};
use crate::composition::tracks::{beast_of, track_smf_bytes};

fn same(a: BeastCompositionParams, b: BeastCompositionParams) -> bool {
    a.species_id == b.species_id
        && a.name_variant_id == b.name_variant_id
        && a.mode_id == b.mode_id
        && a.tonic_keynum == b.tonic_keynum
        && a.register_band == b.register_band
        && a.tier == b.tier
        && a.weakness == b.weakness
        && a.canon_config_id == b.canon_config_id
        && a.profile_id == b.profile_id
        && a.voice_count == b.voice_count
        && a.section_count == b.section_count
        && a.stretto_bucket == b.stretto_bucket
        && a.stretto_lag == b.stretto_lag
        && a.use_inversion == b.use_inversion
        && a.use_countersubject == b.use_countersubject
        && a.use_compound_melody == b.use_compound_melody
        && a.ornament_density == b.ornament_density
        && a.articulation_profile == b.articulation_profile
        && a.velocity_ceiling == b.velocity_ceiling
        && a.tempo_us == b.tempo_us
        && a.score_version == b.score_version
}

fn live(kills: u64, scars: u64, rank: u16) -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: kills, scars, summit_held_seconds: 0, rank, species_count: 400,
    }
}

#[test]
#[available_gas(100000000000)]
fn params_round_trip_every_species() {
    let names: Array<(u8, u8)> = array![(0, 0), (1, 1), (11, 6), (12, 12), (35, 17), (69, 18)];
    let states: Array<BeastV3LiveState> = array![
        live(0, 0, 0), live(3, 0, 1), live(40, 9, 7), live(5000, 300, 399),
    ];
    let mut id: u64 = 1;
    let mut n: u32 = 0;
    while id <= 75 {
        for (prefix, suffix) in names.span() {
            let mut vis: u8 = 0;
            while vis < 3 {
                let b = PackableBeastV3 {
                    id,
                    prefix: *prefix,
                    suffix: *suffix,
                    level: if vis == 0 {
                        1
                    } else {
                        90
                    },
                    health: if vis == 1 {
                        300
                    } else {
                        100
                    },
                    shiny: if vis == 1 {
                        1
                    } else {
                        0
                    },
                    animated: if vis == 2 {
                        1
                    } else {
                        0
                    },
                    tier: species_tier(id),
                    beast_type: species_type(id),
                };
                for s in states.span() {
                    let x = composer_inputs(b, *s);
                    let y = unpack_inputs(pack_inputs(x));
                    assert(same(y.params, x.params), 'round trip');
                    assert(y.shiny == (b.shiny == 1) && y.animated == (b.animated == 1), 'flags');
                    n += 1;
                }
                vis += 1;
            }
        }
        id += 1;
    }
    assert(n == 75 * 6 * 3 * 4, 'case count');
}

#[test]
fn params_round_trip_extremes() {
    let b = PackableBeastV3 {
        id: 0xffffffffffffffff,
        prefix: 69,
        suffix: 18,
        level: 65535,
        health: 65535,
        shiny: 1,
        animated: 1,
        tier: 1,
        beast_type: 2,
    };
    let mut p = map_v3_beast_to_composition_params(b, live(1000000, 1000000, 1));
    p.tempo_us = 1048575;
    p.score_version = 65535;
    p.mode_id = 30;
    p.tonic_keynum = 127;
    let packed = pack_inputs(ComposerInputs { params: p, shiny: true, animated: true });
    let y = unpack_inputs(packed);
    assert(same(y.params, p) && y.shiny && y.animated, 'extremes');
    let wide: u256 = packed.into();
    assert(wide < 0x200000000000000000000000000000000000000000000, 'fits in 177 bits');
}

#[test]
#[should_panic(expected: 'param too wide')]
fn params_reject_wide_field() {
    let b = PackableBeastV3 {
        id: 1,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 0,
        animated: 0,
        tier: 1,
        beast_type: 0,
    };
    let mut p = map_v3_beast_to_composition_params(b, live(0, 0, 0));
    p.tempo_us = 1048576;
    pack_inputs(ComposerInputs { params: p, shiny: false, animated: false });
}

#[test]
#[should_panic(expected: 'unknown params layout')]
fn params_reject_foreign_layout() {
    unpack_inputs(2);
}

#[test]
#[should_panic(expected: 'unknown params bits')]
fn params_reject_stray_bits() {
    let b = PackableBeastV3 {
        id: 1,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 0,
        animated: 0,
        tier: 1,
        beast_type: 0,
    };
    let packed: u256 = pack_inputs(composer_inputs(b, live(0, 0, 0))).into();
    let stray: felt252 = (packed + 0x200000000000000000000000000000000000000000000)
        .try_into()
        .unwrap();
    unpack_inputs(stray);
}

#[test]
#[available_gas(10000000000)]
fn beast_of_rebuilds_the_beast() {
    let mut id: u64 = 1;
    while id <= 75 {
        let nv: u32 = (id * 17 % 1243).try_into().unwrap();
        let (prefix, suffix): (u8, u8) = if nv == 0 {
            (0, 0)
        } else {
            (((nv - 1) / 18 + 1).try_into().unwrap(), ((nv - 1) % 18 + 1).try_into().unwrap())
        };
        let b = PackableBeastV3 {
            id,
            prefix,
            suffix,
            level: 1,
            health: 100,
            shiny: (id % 2).try_into().unwrap(),
            animated: if id % 3 == 0 {
                1
            } else {
                0
            },
            tier: species_tier(id),
            beast_type: species_type(id),
        };
        let r = beast_of(unpack_inputs(pack_inputs(composer_inputs(b, live(0, 0, 0)))));
        assert(r.id == b.id && r.prefix == b.prefix && r.suffix == b.suffix, 'identity');
        assert(r.tier == b.tier && r.beast_type == b.beast_type, 'tier and type');
        assert(r.shiny == b.shiny && r.animated == b.animated, 'flags');
        id += 1;
    }
}

fn warlock() -> felt252 {
    let b = PackableBeastV3 {
        id: 1,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 0,
        animated: 0,
        tier: 1,
        beast_type: 0,
    };
    pack_inputs(composer_inputs(b, live(0, 0, 0)))
}

#[test]
#[should_panic(expected: 'bought track needs a seed')]
fn track_bought_needs_a_seed() {
    track_smf_bytes(warlock(), 3, 0);
}

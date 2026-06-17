//! Loot Survivor Beast trait mapping for canonical Beast sound params.
//!
//! Dev source-of-truth:
//!   full name = {prefix_part1} {prefix_part2} {species}
//!   name_variant 0 is bare species, then 69 * 18 prefixed combinations.

use koji::composition::counterpoint::mode_to_id;
use koji::composition::stretto::{default_stretto_plan, stretto_lag};
use koji::midi::types::Modes;

pub const BEAST_PREFIX_COUNT: u8 = 69;
pub const BEAST_PREFIX1_COUNT: u8 = 69;
pub const BEAST_PREFIX2_COUNT: u8 = 18;
pub const BEAST_NAME_VARIANT_COUNT: u32 = 1243;
pub const BEAST_SPECIES_COUNT: u8 = 75;

pub const REGISTER_LOW: u8 = 0;
pub const REGISTER_MID: u8 = 1;
pub const REGISTER_HIGH: u8 = 2;

pub const WEAKNESS_BLADE: u8 = 0;
pub const WEAKNESS_BLUDGEON: u8 = 1;
pub const WEAKNESS_MAGIC: u8 = 2;

pub const ARTICULATION_NORMAL: u8 = 0;
pub const ARTICULATION_STACCATO: u8 = 1;
pub const ARTICULATION_TENUTO: u8 = 2;
pub const ARTICULATION_ACCENT: u8 = 3;
pub const ARTICULATION_PORTATO: u8 = 5;

pub const VISUAL_COMMON: u8 = 0;
pub const VISUAL_SPECIAL: u8 = 1;
pub const VISUAL_SHINY: u8 = 2;
pub const VISUAL_ANIMATED: u8 = 3;

#[derive(Copy, Drop, Serde)]
pub struct BeastNameParts {
    pub has_prefixes: bool,
    pub prefix1_id: u8,
    pub prefix2_id: u8,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastKeyCell {
    pub canonical_mode_id: u8,
    pub mode: Modes,
    pub tonic_pc: u8,
    pub register_band: u8,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastSpeciesRow {
    pub species_id: u8,
    pub tier: u8,
    pub weakness: u8,
    pub canon_config_id: u32,
    pub profile_id: u32,
    pub base_voice_count: u32,
    pub allows_exotic_mode: bool,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastOrnamentPolicy {
    pub profile_id: u32,
    pub density_cap: u8,
    pub allow_chromatic_approach: bool,
    pub allow_suspension: bool,
    pub allow_trill: bool,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastVisualPerformance {
    pub tempo_bump: u32,
    pub velocity_ceiling: u8,
    pub articulation_profile: u8,
    pub mensuration_flag: bool,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastLiveStats {
    pub level: u32,
    pub health: u32,
    pub adventurers_defeated: u32,
    pub times_defeated: u32,
    pub encounter_count: u32,
    pub species_rank: u32,
    pub is_crown: bool,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastLiveBuckets {
    pub level_bucket: u8,
    pub health_bucket: u8,
    pub kill_bucket: u8,
    pub defeat_bucket: u8,
    pub encounter_bucket: u8,
    pub rank_tier: u8,
    pub is_crown: bool,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastCompositionParams {
    pub species_id: u8,
    pub name_variant_id: u32,
    pub mode_id: u8,
    pub tonic_keynum: u8,
    pub register_band: u8,
    pub tier: u8,
    pub weakness: u8,
    pub canon_config_id: u32,
    pub profile_id: u32,
    pub voice_count: u32,
    pub section_count: u8,
    pub stretto_bucket: u8,
    pub stretto_lag: u32,
    pub use_inversion: bool,
    pub use_countersubject: bool,
    pub use_compound_melody: bool,
    pub ornament_density: u8,
    pub articulation_profile: u8,
    pub velocity_ceiling: u8,
    pub tempo_us: u32,
    pub score_version: u32,
}

pub fn decode_name_variant(name_variant_id: u32) -> BeastNameParts {
    assert(name_variant_id < BEAST_NAME_VARIANT_COUNT, 'invalid name variant');
    if name_variant_id == 0 {
        return BeastNameParts { has_prefixes: false, prefix1_id: 0, prefix2_id: 0 };
    }
    let idx = name_variant_id - 1;
    BeastNameParts {
        has_prefixes: true,
        prefix1_id: (idx / BEAST_PREFIX2_COUNT.into()).try_into().unwrap(),
        prefix2_id: (idx % BEAST_PREFIX2_COUNT.into()).try_into().unwrap(),
    }
}

fn familiar_dark_mode_at(index: u8) -> Modes {
    let m = index % 4;
    if m == 0 {
        Modes::Aeolian(())
    } else if m == 1 {
        Modes::Phrygian(())
    } else if m == 2 {
        Modes::Dorian(())
    } else {
        Modes::HarmonicMinor(())
    }
}

fn tier_allows_exotic(tier: u8) -> bool {
    tier <= 2
}

fn mode_for_prefix_and_tier(prefix1_id: u8, tier: u8) -> Modes {
    let base = familiar_dark_mode_at(prefix1_id);
    if tier_allows_exotic(tier) {
        let gate = prefix1_id % 12;
        if gate == 10 {
            return Modes::Locrian(());
        }
        if gate == 11 {
            return Modes::DorianSharp4(());
        }
    }
    base
}

/// Map name prefix part 1 to a Beast dark key cell using familiar modes for lower tiers.
pub fn prefix1_to_beast_key(prefix1_id: u8, tier: u8) -> BeastKeyCell {
    assert(prefix1_id < BEAST_PREFIX1_COUNT, 'invalid prefix1');
    assert(tier >= 1 && tier <= 5, 'invalid beast tier');
    let mode = mode_for_prefix_and_tier(prefix1_id, tier);
    BeastKeyCell {
        canonical_mode_id: mode_to_id(mode),
        mode,
        tonic_pc: prefix1_id % 12,
        register_band: (prefix1_id / 12) % 3,
    }
}

/// Backward-compatible name for the earlier mapper.
pub fn prefix_to_dark_key(prefix_id: u8) -> BeastKeyCell {
    prefix1_to_beast_key(prefix_id, 5)
}

/// Bare-name Beasts keep the Phrygian default and derive a bounded register from tier.
pub fn bare_name_dark_key(species_id: u8, tier: u8) -> BeastKeyCell {
    assert(species_id < BEAST_SPECIES_COUNT, 'invalid beast species');
    assert(tier >= 1 && tier <= 5, 'invalid beast tier');
    let mode = Modes::Phrygian(());
    let register_band = if tier <= 2 {
        REGISTER_LOW
    } else if tier <= 4 {
        REGISTER_MID
    } else {
        REGISTER_HIGH
    };
    BeastKeyCell {
        canonical_mode_id: mode_to_id(mode),
        mode,
        tonic_pc: species_id % 12,
        register_band,
    }
}

pub fn species_row(species_id: u8) -> BeastSpeciesRow {
    assert(species_id < BEAST_SPECIES_COUNT, 'invalid species');
    let tier = if species_id < 5 {
        1
    } else if species_id < 15 {
        2
    } else if species_id < 35 {
        3
    } else if species_id < 55 {
        4
    } else {
        5
    };
    let weakness = species_id % 3;
    let base_voice_count: u32 = if tier <= 2 {
        3
    } else if tier == 3 {
        2
    } else {
        1
    };
    let canon_config_id: u32 = if tier == 1 {
        28 + (species_id.into() % 10)
    } else if tier == 2 {
        17 + (species_id.into() % 11)
    } else if tier == 3 {
        7 + (species_id.into() % 10)
    } else {
        species_id.into() % 7
    };
    let profile_id: u32 = if tier <= 2 {
        17 + (species_id.into() % 8)
    } else if tier == 3 {
        species_id.into() % 5
    } else {
        0
    };
    BeastSpeciesRow {
        species_id,
        tier,
        weakness,
        canon_config_id,
        profile_id,
        base_voice_count,
        allows_exotic_mode: tier <= 2,
    }
}

pub fn prefix2_ornament_policy(prefix2_id: u8) -> BeastOrnamentPolicy {
    assert(prefix2_id < BEAST_PREFIX2_COUNT, 'invalid prefix2');
    let family = prefix2_id % 6;
    BeastOrnamentPolicy {
        profile_id: family.into(),
        density_cap: 1 + (prefix2_id % 5),
        allow_chromatic_approach: prefix2_id >= 6,
        allow_suspension: family == 2 || family == 3 || prefix2_id >= 12,
        allow_trill: family == 4 || family == 5,
    }
}

pub fn visual_performance_layer(visual_rarity: u8) -> BeastVisualPerformance {
    if visual_rarity >= VISUAL_ANIMATED {
        BeastVisualPerformance {
            tempo_bump: 45000,
            velocity_ceiling: 127,
            articulation_profile: ARTICULATION_ACCENT,
            mensuration_flag: true,
        }
    } else if visual_rarity == VISUAL_SHINY {
        BeastVisualPerformance {
            tempo_bump: 25000,
            velocity_ceiling: 124,
            articulation_profile: ARTICULATION_TENUTO,
            mensuration_flag: false,
        }
    } else if visual_rarity == VISUAL_SPECIAL {
        BeastVisualPerformance {
            tempo_bump: 10000,
            velocity_ceiling: 118,
            articulation_profile: ARTICULATION_PORTATO,
            mensuration_flag: false,
        }
    } else {
        BeastVisualPerformance {
            tempo_bump: 0,
            velocity_ceiling: 112,
            articulation_profile: ARTICULATION_NORMAL,
            mensuration_flag: false,
        }
    }
}

pub fn bucket_log2(n: u32) -> u8 {
    let mut x = n + 1;
    let mut b: u8 = 0;
    loop {
        if x <= 1 || b >= 7 {
            break;
        }
        x = x / 2;
        b += 1;
    };
    b
}

pub fn rank_to_rank_tier(rank: u32) -> u8 {
    assert(rank >= 1 && rank <= 1243, 'invalid species rank');
    if rank == 1 {
        0
    } else if rank <= 10 {
        1
    } else if rank <= 50 {
        2
    } else if rank <= 250 {
        3
    } else {
        4
    }
}

pub fn live_buckets(stats: BeastLiveStats) -> BeastLiveBuckets {
    BeastLiveBuckets {
        level_bucket: bucket_log2(stats.level),
        health_bucket: bucket_log2(stats.health),
        kill_bucket: bucket_log2(stats.adventurers_defeated),
        defeat_bucket: bucket_log2(stats.times_defeated),
        encounter_bucket: bucket_log2(stats.encounter_count),
        rank_tier: rank_to_rank_tier(stats.species_rank),
        is_crown: stats.is_crown,
    }
}

fn sections_for_kill_bucket(kill_bucket: u8) -> u8 {
    if kill_bucket == 0 {
        1
    } else if kill_bucket == 1 {
        2
    } else if kill_bucket <= 3 {
        3
    } else if kill_bucket <= 5 {
        4
    } else {
        5
    }
}

fn tonic_keynum_for_cell(cell: BeastKeyCell) -> u8 {
    let base = if cell.register_band == REGISTER_LOW {
        48
    } else if cell.register_band == REGISTER_MID {
        60
    } else {
        72
    };
    base + cell.tonic_pc
}

fn clamp_u8(v: u32, hi: u8) -> u8 {
    if v > hi.into() {
        hi
    } else {
        v.try_into().unwrap()
    }
}

pub fn map_beast_traits_to_composition_params(
    species_id: u8,
    name_variant_id: u32,
    visual_rarity: u8,
    _sound_seed: felt252,
    stats: BeastLiveStats,
) -> BeastCompositionParams {
    let row = species_row(species_id);
    let name = decode_name_variant(name_variant_id);
    let key = if name.has_prefixes {
        prefix1_to_beast_key(name.prefix1_id, row.tier)
    } else {
        bare_name_dark_key(species_id, row.tier)
    };
    let ornament = if name.has_prefixes {
        prefix2_ornament_policy(name.prefix2_id)
    } else {
        BeastOrnamentPolicy {
            profile_id: row.profile_id,
            density_cap: 1,
            allow_chromatic_approach: false,
            allow_suspension: row.tier <= 3,
            allow_trill: false,
        }
    };
    let perf = visual_performance_layer(visual_rarity);
    let buckets = live_buckets(stats);
    let crown_bump: u8 = if buckets.is_crown && buckets.kill_bucket < 7 {
        1
    } else {
        0
    };
    let stretto_bucket = buckets.kill_bucket + crown_bump;
    let extra_voice: u32 = if buckets.kill_bucket >= 4 && row.tier <= 3 {
        1
    } else {
        0
    };
    let rank_voice: u32 = if buckets.rank_tier <= 1 && row.tier <= 2 {
        1
    } else {
        0
    };
    let max_voice: u32 = if row.tier <= 2 {
        4
    } else if row.tier == 3 {
        3
    } else {
        2
    };
    let raw_voice = row.base_voice_count + extra_voice + rank_voice;
    let voice_count = if raw_voice > max_voice {
        max_voice
    } else {
        raw_voice
    };
    let density_raw: u32 = ornament.density_cap.into() + buckets.kill_bucket.into()
        + if buckets.is_crown { 1 } else { 0 };
    let tempo_us = 500000 - perf.tempo_bump;
    BeastCompositionParams {
        species_id,
        name_variant_id,
        mode_id: key.canonical_mode_id,
        tonic_keynum: tonic_keynum_for_cell(key),
        register_band: key.register_band,
        tier: row.tier,
        weakness: row.weakness,
        canon_config_id: row.canon_config_id,
        profile_id: row.profile_id,
        voice_count,
        section_count: sections_for_kill_bucket(buckets.kill_bucket),
        stretto_bucket,
        stretto_lag: stretto_lag(@default_stretto_plan(), stretto_bucket),
        use_inversion: buckets.defeat_bucket >= 3 || (row.tier <= 2 && buckets.encounter_bucket >= 4),
        use_countersubject: row.tier <= 2 || (row.tier == 3 && buckets.rank_tier <= 1),
        use_compound_melody: row.tier >= 4,
        ornament_density: clamp_u8(density_raw, 7),
        articulation_profile: if buckets.is_crown {
            ARTICULATION_ACCENT
        } else {
            perf.articulation_profile
        },
        velocity_ceiling: perf.velocity_ceiling,
        tempo_us,
        score_version: 1,
    }
}

pub fn weakness_section_b_shift(weakness: u8) -> i32 {
    if weakness == WEAKNESS_BLADE {
        7
    } else if weakness == WEAKNESS_BLUDGEON {
        -5
    } else {
        6
    }
}

use koji::composition::beast_trait_map::{
    ARTICULATION_ACCENT, ARTICULATION_NORMAL, BEAST_NAME_VARIANT_COUNT, BEAST_PREFIX1_COUNT,
    BEAST_PREFIX2_COUNT, BEAST_PREFIX_COUNT, BEAST_SPECIES_COUNT, REGISTER_HIGH, REGISTER_LOW,
    REGISTER_MID, VISUAL_ANIMATED, VISUAL_COMMON, VISUAL_SHINY, WEAKNESS_BLADE,
    WEAKNESS_BLUDGEON, WEAKNESS_MAGIC, bare_name_dark_key, bucket_log2, decode_name_variant,
    live_buckets, map_beast_traits_to_composition_params, prefix1_to_beast_key,
    prefix2_ornament_policy, prefix_to_dark_key, rank_to_rank_tier, species_row,
    visual_performance_layer, weakness_section_b_shift, BeastLiveStats,
};
use koji::composition::counterpoint::mode_to_id;
use koji::midi::modes::is_dark_mode;
use koji::midi::types::Modes;

fn baseline_stats() -> BeastLiveStats {
    BeastLiveStats {
        level: 1,
        health: 10,
        adventurers_defeated: 0,
        times_defeated: 0,
        encounter_count: 0,
        species_rank: 1243,
        is_crown: false,
    }
}

fn crown_stats() -> BeastLiveStats {
    BeastLiveStats {
        level: 128,
        health: 999,
        adventurers_defeated: 64,
        times_defeated: 8,
        encounter_count: 32,
        species_rank: 1,
        is_crown: true,
    }
}

#[test]
fn name_variant_count_matches_dev_name_parts() {
    assert(BEAST_NAME_VARIANT_COUNT == 1 + 69 * 18, 'name variant count');
}

#[test]
fn decode_name_variant_edges() {
    let bare = decode_name_variant(0);
    assert(!bare.has_prefixes, 'bare has no prefixes');

    let first = decode_name_variant(1);
    assert(first.has_prefixes, 'first has prefixes');
    assert(first.prefix1_id == 0, 'first p1');
    assert(first.prefix2_id == 0, 'first p2');

    let last_first_prefix = decode_name_variant(18);
    assert(last_first_prefix.prefix1_id == 0, '18 p1');
    assert(last_first_prefix.prefix2_id == 17, '18 p2');

    let next_prefix = decode_name_variant(19);
    assert(next_prefix.prefix1_id == 1, '19 p1');
    assert(next_prefix.prefix2_id == 0, '19 p2');

    let last = decode_name_variant(1242);
    assert(last.prefix1_id == 68, 'last p1');
    assert(last.prefix2_id == 17, 'last p2');
}

#[test]
fn prefix_key_cells_use_dark_modes_and_bounds() {
    let mut prefix_id = 0_u8;
    loop {
        if prefix_id >= BEAST_PREFIX_COUNT {
            break;
        }
        let key = prefix_to_dark_key(prefix_id);
        assert(is_dark_mode(key.mode), 'prefix mode must be dark');
        assert(key.tonic_pc < 12, 'tonic pc bound');
        assert(key.register_band <= REGISTER_HIGH, 'register bound');
        prefix_id += 1;
    };
}

#[test]
fn prefix1_tier_policy_blocks_exotic_for_common_beasts() {
    let mut prefix_id = 0_u8;
    loop {
        if prefix_id >= BEAST_PREFIX1_COUNT {
            break;
        }
        let tier5 = prefix1_to_beast_key(prefix_id, 5);
        assert(tier5.canonical_mode_id != mode_to_id(Modes::MelodicMinor(())), 'no melodic minor');
        assert(tier5.canonical_mode_id != mode_to_id(Modes::Locrian(())), 'tier5 no locrian');
        assert(tier5.canonical_mode_id != mode_to_id(Modes::DorianSharp4(())), 'tier5 no d#4');
        prefix_id += 1;
    };
}

#[test]
fn apex_prefix_can_use_exotic_dark_colors() {
    let locrian = prefix1_to_beast_key(10, 1);
    assert(locrian.canonical_mode_id == mode_to_id(Modes::Locrian(())), 'apex locrian');
    let sharp4 = prefix1_to_beast_key(11, 1);
    assert(sharp4.canonical_mode_id == mode_to_id(Modes::DorianSharp4(())), 'apex d#4');
}

#[test]
fn bare_name_key_cells_are_bounded_phrygian() {
    let apex = bare_name_dark_key(8, 1);
    assert(apex.canonical_mode_id == mode_to_id(Modes::Phrygian(())), 'bare phrygian');
    assert(apex.tonic_pc == 8, 'Dragon tonic Ab');
    assert(apex.register_band == REGISTER_LOW, 'apex register low');

    let dangerous = bare_name_dark_key(30, 3);
    assert(dangerous.register_band == REGISTER_MID, 'dangerous register mid');

    let common = bare_name_dark_key(74, 5);
    assert(common.register_band == REGISTER_HIGH, 'common register high');
}

#[test]
fn all_species_rows_are_bounded() {
    let mut species_id = 0_u8;
    loop {
        if species_id >= BEAST_SPECIES_COUNT {
            break;
        }
        let row = species_row(species_id);
        assert(row.species_id == species_id, 'species id stable');
        assert(row.tier >= 1 && row.tier <= 5, 'tier bounds');
        assert(row.weakness <= WEAKNESS_MAGIC, 'weakness bounds');
        assert(row.base_voice_count >= 1 && row.base_voice_count <= 3, 'voice bounds');
        if row.tier >= 4 {
            assert(!row.allows_exotic_mode, 'common no exotic');
        }
        species_id += 1;
    };
}

#[test]
fn all_prefix2_policies_are_bounded() {
    let mut prefix2_id = 0_u8;
    loop {
        if prefix2_id >= BEAST_PREFIX2_COUNT {
            break;
        }
        let policy = prefix2_ornament_policy(prefix2_id);
        assert(policy.density_cap >= 1 && policy.density_cap <= 5, 'density cap');
        assert(policy.profile_id <= 5, 'policy profile');
        prefix2_id += 1;
    };
}

#[test]
fn visual_layers_affect_performance_only() {
    let common = visual_performance_layer(VISUAL_COMMON);
    assert(common.tempo_bump == 0, 'common tempo');
    assert(common.articulation_profile == ARTICULATION_NORMAL, 'common art');

    let shiny = visual_performance_layer(VISUAL_SHINY);
    assert(shiny.velocity_ceiling > common.velocity_ceiling, 'shiny ceiling');

    let animated = visual_performance_layer(VISUAL_ANIMATED);
    assert(animated.mensuration_flag, 'animated mensuration');
}

#[test]
fn bucket_log2_is_bounded_and_monotone_examples() {
    assert(bucket_log2(0) == 0, 'bucket 0');
    assert(bucket_log2(1) == 1, 'bucket 1');
    assert(bucket_log2(3) == 2, 'bucket 3');
    assert(bucket_log2(7) == 3, 'bucket 7');
    assert(bucket_log2(1024) == 7, 'bucket clamp');
}

#[test]
fn rank_tiers_are_species_local() {
    assert(rank_to_rank_tier(1) == 0, 'rank 1');
    assert(rank_to_rank_tier(10) == 1, 'rank 10');
    assert(rank_to_rank_tier(50) == 2, 'rank 50');
    assert(rank_to_rank_tier(250) == 3, 'rank 250');
    assert(rank_to_rank_tier(1243) == 4, 'rank 1243');
}

#[test]
fn live_buckets_preserve_crown() {
    let buckets = live_buckets(crown_stats());
    assert(buckets.kill_bucket == 6, 'kill bucket 64');
    assert(buckets.defeat_bucket == 3, 'defeat bucket 8');
    assert(buckets.rank_tier == 0, 'rank tier');
    assert(buckets.is_crown, 'crown kept');
}

#[test]
fn params_are_bounded_for_representative_beasts() {
    let bare_common = map_beast_traits_to_composition_params(74, 0, VISUAL_COMMON, 99, baseline_stats());
    assert(bare_common.tier == 5, 'common tier');
    assert(bare_common.voice_count <= 2, 'common voices');
    assert(bare_common.section_count == 1, 'common sections');
    assert(bare_common.use_compound_melody, 'common compound');

    let apex = map_beast_traits_to_composition_params(0, 1242, VISUAL_ANIMATED, 99, crown_stats());
    assert(apex.tier == 1, 'apex tier');
    assert(apex.voice_count <= 4, 'apex voices');
    assert(apex.section_count == 5, 'apex sections');
    assert(apex.stretto_bucket == 7, 'crown tight bucket');
    assert(apex.use_inversion, 'scar inversion');
    assert(apex.use_countersubject, 'apex countersubject');
    assert(apex.articulation_profile == ARTICULATION_ACCENT, 'crown accent');
    assert(apex.ornament_density <= 7, 'orn density bound');
}

#[test]
fn live_stats_change_adaptation_not_base_identity_fields() {
    let calm = map_beast_traits_to_composition_params(12, 20, VISUAL_COMMON, 123, baseline_stats());
    let evolved = map_beast_traits_to_composition_params(12, 20, VISUAL_COMMON, 123, crown_stats());
    assert(calm.species_id == evolved.species_id, 'species stable');
    assert(calm.name_variant_id == evolved.name_variant_id, 'name stable');
    assert(calm.mode_id == evolved.mode_id, 'mode stable');
    assert(calm.tonic_keynum == evolved.tonic_keynum, 'tonic stable');
    assert(evolved.section_count > calm.section_count, 'form evolves');
    assert(evolved.stretto_lag < calm.stretto_lag, 'stretto tightens');
}

#[test]
fn weakness_section_b_shifts_are_stable() {
    assert(weakness_section_b_shift(WEAKNESS_BLADE) == 7, 'blade fifth');
    assert(weakness_section_b_shift(WEAKNESS_BLUDGEON) == -5, 'bludgeon fourth down');
    assert(weakness_section_b_shift(WEAKNESS_MAGIC) == 6, 'magic tritone');
}

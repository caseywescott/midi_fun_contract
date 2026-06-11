//! Entry-lag melodic canon generator — parallel pipeline to stacked stretto generation.
//!
//! Followers may enter after an arbitrary number of leader structural notes. Correctness is still
//! by construction via `pair_constraints_from_entries` and the existing validators/renderers.
//!
//! See `docs/entry_lag_canon_spec.md`.

use core::array::ArrayTrait;
use koji::composition::canon_rules::{CanonConfig, profiled_config_by_id};
use koji::composition::canon_entry_rules::{
    EntryLagCanonConfig, entries_are_stacked, entries_stacked, pair_constraints_from_entries,
    entry_lag_config_from_canon, validate_entries, ENTRY_LAG_CONFIG_ID_BASE,
    config_fifth_above_lag2,
};
use koji::composition::aesthetic_profile::{
    AestheticProfile, profile_by_id, allowed_steps_multivoice_p,
};
use koji::composition::jazz_harmony::{
    turnaround_plan_default, turnaround_plan_from_canon_seed, TurnaroundPlan,
};
use koji::composition::melodic_canon::{
    MelodicCanon, MelodicCanonTraits, MIN_LEN, MAX_LEN, CADENCE_LEN,
    walk_leader_banded_with_constraints, constant_band, build_mensuration_voices,
    exact_imitation, all_pairs_clash_free, cadence_lands_on_final,
    num_modes, plan_ornament_subdivisions, plan_ornament_subdivisions_for_profile,
    max_vertical_tier_used, no_minor_ninth,
};

fn pow2(p: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= p {
            break;
        }
        r *= 2;
        i += 1;
    };
    r
}

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

/// Onchain metadata for entry-lag canons (extends the base trait fields).
#[derive(Copy, Drop)]
pub struct EntryLagCanonTraits {
    pub base: MelodicCanonTraits,
    pub primary_entry_lag: u32,
    pub entries_fingerprint: u32,
}

/// Fingerprint of the entry vector for metadata (weighted sum of entries).
pub fn entries_fingerprint(entries: Span<u32>) -> u32 {
    let mut fp: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= entries.len() {
            break;
        }
        fp += *entries.at(i) * (i + 1);
        i += 1;
    };
    fp
}

/// Primary lag: max entry among followers.
pub fn primary_entry_lag(entries: Span<u32>) -> u32 {
    let mut max_lag: u32 = 0;
    let mut i: u32 = 1;
    loop {
        if i >= entries.len() {
            break;
        }
        if *entries.at(i) > max_lag {
            max_lag = *entries.at(i);
        }
        i += 1;
    };
    max_lag
}

/// Structural time units until the last voice finishes (max entry + leader length).
pub fn canon_texture_span(canon: @MelodicCanon) -> u32 {
    let len = (*canon.leader_degrees).len();
    let voices = *canon.voices;
    let mut span = len;
    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let end = (*voices.at(vi)).entry + len;
        if end > span {
            span = end;
        }
        vi += 1;
    };
    span
}

fn unit_dilations(n_voices: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n_voices {
            break;
        }
        out.append(1);
        i += 1;
    };
    out
}

/// Walk the leader under entry-lag pairwise constraints.
pub fn walk_leader_with_entries(
    canon_seed: felt252,
    seed_state: u32,
    offsets: Span<i32>,
    entries: Span<u32>,
    profile: @AestheticProfile,
    len: u32,
    cadence: bool,
    turnaround_plan: TurnaroundPlan,
) -> (Array<i32>, Array<i32>) {
    assert(validate_entries(offsets, entries), 'bad entries');
    let constraints = pair_constraints_from_entries(offsets, entries);
    walk_leader_banded_with_constraints(
        canon_seed,
        seed_state,
        offsets,
        constraints.span(),
        profile,
        len,
        cadence,
        constant_band(profile),
        turnaround_plan,
    )
}

/// Build a `MelodicCanon` from walked leader material and an entry-lag config.
pub fn assemble_entry_lag_canon(
    config: EntryLagCanonConfig,
    degrees: Span<i32>,
    steps: Span<i32>,
    mode_id: u8,
    tonic_keynum: u8,
    time_unit: u32,
) -> MelodicCanon {
    let dilations = unit_dilations(config.offsets.len());
    let voices = build_mensuration_voices(config.offsets, config.entries, dilations.span());
    MelodicCanon {
        config_id: config.config_id,
        config_name: config.name,
        offsets: config.offsets,
        leader_degrees: degrees,
        leader_steps: steps,
        mode_id,
        tonic_keynum,
        time_unit,
        voices: voices.span(),
        octave: config.octave,
        profile_id: config.profile_id,
    }
}

/// Offline fitter ingress: validated entry-lag canon from external leader degrees + entries.
pub fn assemble_entry_lag_canon_from_leader(
    base_config_id: u32,
    entries: Span<u32>,
    mode_id: u8,
    tonic_keynum: u8,
    leader_degrees: Span<i32>,
) -> MelodicCanon {
    let base = profiled_config_by_id(base_config_id);
    let el = entry_lag_config_from_canon(
        base.config_id, base.name, base.offsets, entries, base.octave, base.profile_id,
    );
    let mut steps: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 1;
    loop {
        if i >= leader_degrees.len() {
            break;
        }
        steps.append(*leader_degrees.at(i) - *leader_degrees.at(i - 1));
        i += 1;
    };
    let canon = assemble_entry_lag_canon(
        el, leader_degrees, steps.span(), mode_id, tonic_keynum, 4,
    );
    let profile = profile_by_id(base.profile_id);
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_clash_free(@canon, @profile), 'canon not consonant');
    canon
}

/// Generate a contrapuntally correct entry-lag canon. Cadence steering is enabled only for
/// stacked stretto entries (legacy-equivalent layout).
pub fn generate_entry_lag_canon(
    seed: felt252, config: EntryLagCanonConfig, length: u32,
) -> MelodicCanon {
    let s: u256 = seed.into();
    let profile = profile_by_id(config.profile_id);
    let len = if length >= MIN_LEN {
        length
    } else {
        MIN_LEN
    };
    let mut seed_state = extract_bits(s, 19, 8) % 256;
    if seed_state == 0 {
        seed_state = 7;
    }
    let turnaround_plan = if config.profile_id == 24 {
        turnaround_plan_from_canon_seed(seed)
    } else {
        turnaround_plan_default()
    };
    let cadence = entries_are_stacked(config.entries);
    let (degrees, steps) = walk_leader_with_entries(
        seed,
        seed_state,
        config.offsets,
        config.entries,
        @profile,
        len,
        cadence,
        turnaround_plan,
    );
    let chromatic = config.octave == 12;
    let tonic: u8 = if chromatic {
        60
    } else {
        65
    };
    let mode_id: u8 = if chromatic {
        0
    } else {
        (extract_bits(s, 7, 3) % num_modes()).try_into().unwrap()
    };
    let canon = assemble_entry_lag_canon(
        config, degrees.span(), steps.span(), mode_id, tonic, 4,
    );
    assert(exact_imitation(@canon), 'imitation broken');
    assert(all_pairs_clash_free(@canon, @profile), 'canon has a clash');
    if config.offsets.len() == 2 && cadence {
        assert(cadence_lands_on_final(@canon), 'cadence not resolved');
    }
    canon
}

/// Uniform lag preset: reuse offsets/profile/octave from a legacy config; every follower enters
/// after `lag` leader structural notes. `lag == 1` uses stacked stretto entries.
pub fn generate_entry_lag_canon_uniform(
    seed: felt252, base: CanonConfig, lag: u32, length: u32,
) -> MelodicCanon {
    assert(lag >= 1, 'lag >= 1');
    let entries = if lag == 1 {
        entries_stacked(base.offsets.len())
    } else {
        let mut e: Array<u32> = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= base.offsets.len() {
                break;
            }
            if i == 0 {
                e.append(0);
            } else {
                e.append(lag);
            }
            i += 1;
        };
        e
    };
    let config = entry_lag_config_from_canon(
        base.config_id,
        base.name,
        base.offsets,
        entries.span(),
        base.octave,
        base.profile_id,
    );
    generate_entry_lag_canon(seed, config, length)
}

/// Entry-lag canon plus ornament subdivision plan (Montanos divided style).
pub fn generate_entry_lag_ornamented_canon(
    seed: felt252, config: EntryLagCanonConfig, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let canon = generate_entry_lag_canon(seed, config, length);
    let mut orn_seed = extract_bits(seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions_for_profile(
        canon.profile_id, orn_seed, canon.leader_steps, CADENCE_LEN,
    );
    (canon, subs)
}

/// Uniform-lag ornamented canon from a legacy base config.
pub fn generate_entry_lag_ornamented_canon_uniform(
    seed: felt252, base: CanonConfig, lag: u32, length: u32,
) -> (MelodicCanon, Array<u32>) {
    let canon = generate_entry_lag_canon_uniform(seed, base, lag, length);
    let mut orn_seed = extract_bits(seed.into(), 51, 8) % 256;
    if orn_seed == 0 {
        orn_seed = 19;
    }
    let subs = plan_ornament_subdivisions(orn_seed, canon.leader_steps, CADENCE_LEN);
    (canon, subs)
}

/// Deterministic entry-lag canon from seed (lag-2 fifth-above preset).
pub fn generate_entry_lag_canon_from_seed(seed: felt252) -> MelodicCanon {
    let s: u256 = seed.into();
    let span = MAX_LEN - MIN_LEN + 1;
    let len = MIN_LEN + (extract_bits(s, 14, 5) % span);
    generate_entry_lag_canon(seed, config_fifth_above_lag2(), len)
}

pub fn entry_lag_canon_traits(canon: @MelodicCanon) -> EntryLagCanonTraits {
    let profile = profile_by_id(*canon.profile_id);
    let alphabet = allowed_steps_multivoice_p(@profile, *canon.offsets);
    let interval = if (*canon.offsets).len() > 1 {
        *(*canon.offsets).at(1)
    } else {
        0
    };
    let voices = *canon.voices;
    let mut e: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= voices.len() {
            break;
        }
        e.append((*voices.at(i)).entry);
        i += 1;
    };
    let entries = e.span();
    let base = MelodicCanonTraits {
        config_id: *canon.config_id,
        profile_id: *canon.profile_id,
        profile_name: profile.name,
        voice_count: voices.len(),
        interval_of_imitation: interval,
        mode_id: *canon.mode_id,
        octave: *canon.octave,
        length: (*canon.leader_degrees).len(),
        time_unit: *canon.time_unit,
        melodic_alphabet_size: alphabet.len(),
        max_tier_used: max_vertical_tier_used(canon, @profile),
        contains_minor_second: !no_minor_ninth(canon),
        chord_quality: if *canon.config_id >= ENTRY_LAG_CONFIG_ID_BASE {
            'entry_lag'
        } else {
            'canon'
        },
    };
    EntryLagCanonTraits {
        base,
        primary_entry_lag: primary_entry_lag(entries),
        entries_fingerprint: entries_fingerprint(entries),
    }
}

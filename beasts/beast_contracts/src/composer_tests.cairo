//! BeastSoundComposer's views: the music state and score hash are stable for the same inputs, live
//! stats change them without changing the Beast's identity, and `get_score_hash` is the score hash
//! of the form built from `get_composition_params`.
//!
//! These are the music-state and score-hash checks of the composer's earlier library API (a species
//! index, name variant, visual rarity, sound seed and live stats), on the views' inputs: a Beasts
//! V3 token and its live state. Level and health are token traits in V3, so the token keeps them
//! while the live state carries the history; the sound seed comes from the token
//! (`beast_sound_seed(id, prefix, suffix)`), and no view returns it.
use beast_composer::composition::beast_score::{beast_params_hash, build_beast_form};
use beast_composer::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, beast_sound_seed, encode_v3_token_id,
};
use beast_composer::composition::genesis::{species_tier, species_type};
use starknet::syscalls::deploy_syscall;
use crate::{BeastSoundComposer, IBeastSoundComposerDispatcher, IBeastSoundComposerDispatcherTrait};

fn composer() -> IBeastSoundComposerDispatcher {
    let (address, _) = deploy_syscall(
        BeastSoundComposer::TEST_CLASS_HASH, 0, array!['salt', 500].span(), false,
    )
        .unwrap();
    IBeastSoundComposerDispatcher { contract_address: address }
}

fn beast(
    id: u64, prefix: u8, suffix: u8, level: u16, health: u16, animated: u8,
) -> PackableBeastV3 {
    PackableBeastV3 {
        id,
        prefix,
        suffix,
        level,
        health,
        shiny: 0,
        animated,
        tier: species_tier(id),
        beast_type: species_type(id),
    }
}

/// No history, last place in a full species.
fn baseline_stats() -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 1243, species_count: 1243,
    }
}

/// 64 kills, 8 scars, rank 1 (the crown).
fn high_history_stats() -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: 64, scars: 8, summit_held_seconds: 0, rank: 1, species_count: 1243,
    }
}

#[test]
fn canonical_music_state_is_stable_for_same_inputs() {
    let c = composer();
    let token = encode_v3_token_id(beast(13, 2, 2, 1, 10, 0));
    let a_params = beast_params_hash(c.get_composition_params(token, baseline_stats()));
    let b_params = beast_params_hash(c.get_composition_params(token, baseline_stats()));
    assert(a_params == b_params, 'params hash stable');
    assert(
        c.get_score_hash(token, baseline_stats()) == c.get_score_hash(token, baseline_stats()),
        'score hash stable',
    );
    assert(
        c
            .get_music_state_hash(token, baseline_stats()) == c
            .get_music_state_hash(token, baseline_stats()),
        'state hash stable',
    );
}

#[test]
fn live_stats_change_state_hash_without_changing_identity() {
    let c = composer();
    let token = encode_v3_token_id(beast(13, 2, 2, 1, 10, 0));
    let calm = c.get_composition_params(token, baseline_stats());
    let evolved = c.get_composition_params(token, high_history_stats());
    assert(calm.species_id == evolved.species_id, 'species identity');
    assert(calm.name_variant_id == evolved.name_variant_id, 'name identity');
    assert(
        c.get_score_hash(token, baseline_stats()) != c.get_score_hash(token, high_history_stats()),
        'score changes',
    );
    assert(
        c
            .get_music_state_hash(token, baseline_stats()) != c
            .get_music_state_hash(token, high_history_stats()),
        'state changes',
    );
}

#[test]
fn score_hash_api_matches_form_hash() {
    let c = composer();
    let b = beast(1, 69, 18, 128, 999, 1);
    let token = encode_v3_token_id(b);
    let params = c.get_composition_params(token, high_history_stats());
    let form = build_beast_form(params, beast_sound_seed(b.id, b.prefix, b.suffix));
    assert(c.get_score_hash(token, high_history_stats()) == form.score_hash, 'score hash api');
}

//! Bought tracks through the shared musical inputs: a Beast's edition base (`GenerationInputs`) and
//! a purchase's variation of it. No clock, hash reads or sale policy: the manager snapshots the
//! base and supplies the variation seed (a block hash).
//!
//! The base is the Beast's own song as written (`genesis::beast_song_inputs`); edition 0 of the
//! default config keeps the species' chosen theme, so a purchase of it is the bought track of
//! `genesis::seeded_track_smf_bytes`. Any other edition or config composes a new theme for the
//! species, the same for every Beast of it (the Beasts reference manager's 'BEAST_EDITION_V1').

use core::poseidon::poseidon_hash_span;
use crate::composition::beast_v3_sound::PackableBeastV3;
use crate::composition::genesis::{beast_song_inputs, bought_song_inputs};
use crate::inputs::{
    BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig, GenerationInputs,
    normalize_generation_identity, validate_generation_inputs, validate_inputs,
};

pub fn get_generation_inputs(
    config: EditionCompositionConfig, edition_id: u64, identity: BeastMusicalIdentity,
) -> GenerationInputs {
    normalize_generation_identity(identity);
    let nv = identity.name_variant_id;
    let (prefix, suffix): (u8, u8) = if nv == 0 {
        (0, 0)
    } else {
        (((nv - 1) / 18 + 1).try_into().unwrap(), ((nv - 1) % 18 + 1).try_into().unwrap())
    };
    // species 1..=75 compose with their own tier and type; level and health are the Genesis ones
    let beast = PackableBeastV3 {
        id: identity.species_id,
        prefix,
        suffix,
        level: 50,
        health: 200,
        shiny: 0,
        animated: 0,
        tier: identity.tier,
        beast_type: identity.family,
    };
    let mut song = beast_song_inputs(beast, prefix, suffix);
    if edition_id != 0 || config.composition_seed != 0 {
        let motif_seed = poseidon_hash_span(
            array![
                'BEAST_EDITION_V1', config.composition_seed, edition_id.into(),
                identity.species_id.into(),
            ]
                .span(),
        );
        song.theme.motif_seed = motif_seed;
        song.treatment.rhythm_seed = motif_seed;
    }
    let base = GenerationInputs { base_song: song };
    validate_generation_inputs(base);
    base
}

pub fn generate_inputs(base: GenerationInputs, variation_identity: felt252) -> ComposerInputs {
    validate_generation_inputs(base);
    let x = ComposerInputs::Song(bought_song_inputs(base.base_song, variation_identity));
    validate_inputs(x);
    x
}

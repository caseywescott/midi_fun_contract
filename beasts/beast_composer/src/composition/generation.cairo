//! Bought tracks through the shared musical inputs: a Beast's edition base (`GenerationInputs`) and
//! a purchase's variation of it. No clock, hash reads or sale policy: the manager snapshots the
//! base and supplies the variation seed (a block hash).
//!
//! The base is the Beast's own song as written (`genesis::beast_song_inputs`), with its species'
//! chosen theme in every edition and config: the Warlocks' tracks keep the Warlocks' theme. A
//! purchase in edition 0 is the seed's bought track in a shape of its own
//! (`genesis::purchase_song_inputs`); from edition 1, the edition's style engine playing the
//! species'
//! theme (`editions.cairo`, species 1..=75; later species keep the bought Song).

use crate::composition::beast_v3_sound::PackableBeastV3;
use crate::composition::genesis::{beast_song_inputs, purchase_song_inputs};
use crate::inputs::{
    BeastMusicalIdentity, ComposerInputs, EDITION_SPECIES_MAX, EditionCompositionConfig,
    EditionInputs, GenerationInputs, normalize_generation_identity, validate_generation_inputs,
    validate_inputs,
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
        id: identity.species_id.into(),
        prefix,
        suffix,
        level: 50,
        health: 200,
        shiny: 0,
        animated: 0,
        tier: identity.tier,
        beast_type: identity.family,
    };
    // the edition and its config pick no music of their own: the manager's edition clock and sale
    // the edition and its config pick no music of their own: every edition keeps the species' song,
    // and the purchase's edition picks its engine (`generate_inputs`)
    let _ = (config, edition_id);
    let base = GenerationInputs { base_song: beast_song_inputs(beast, prefix, suffix) };
    validate_generation_inputs(base);
    base
}

pub fn generate_inputs(
    base: GenerationInputs, edition_id: u64, variation_identity: felt252,
) -> ComposerInputs {
    validate_generation_inputs(base);
    let identity = base.base_song.arrangement.identity;
    let x = if edition_id >= 1 && identity.source_species_id <= EDITION_SPECIES_MAX {
        let seed: u256 = variation_identity.into();
        ComposerInputs::Edition(
            EditionInputs {
                identity,
                edition: edition_id.try_into().expect('edition too large'),
                seed: (seed % 0x10000000000000000).try_into().unwrap(),
            },
        )
    } else {
        ComposerInputs::Song(purchase_song_inputs(base.base_song, variation_identity))
    };
    validate_inputs(x);
    x
}

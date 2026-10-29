//! The Genesis engine through the shared musical inputs: a song's `SongInputs`, sent over the wire
//! (`encode_inputs` / `decode_inputs`), composes the same file as the Beast it came from. Two
//! compositions per test (memory).
use crate::composition::beast_v3_sound::PackableBeastV3;
use crate::composition::drift::DriftClock;
use crate::composition::genesis::{
    genesis_song_inputs, song_inputs_smf_bytes, song_smf_bytes, species_tier, species_type,
};
use crate::inputs::{
    ChannelPolicy, ComposerInputs, SpecialArrangement, decode_inputs, encode_inputs,
};

fn beast(id: u64, prefix: u8, suffix: u8, shiny: u8) -> PackableBeastV3 {
    let (tier, beast_type) = if id <= 75 {
        (species_tier(id), species_type(id))
    } else {
        (2, 1)
    };
    PackableBeastV3 {
        id, prefix, suffix, level: 1, health: 100, shiny, animated: 0, tier, beast_type,
    }
}

/// The song's inputs survive the wire codec and compose the Beast's file, byte for byte.
fn same_song(b: PackableBeastV3, seed: felt252, drift: Option<DriftClock>) {
    let x = genesis_song_inputs(b, b.prefix, b.suffix, seed, drift);
    let wire = encode_inputs(ComposerInputs::Song(x));
    let y = match decode_inputs(wire.span()) {
        ComposerInputs::Song(y) => y,
        ComposerInputs::SoundCheck(_) => core::panic_with_felt252('not a song'),
    };
    assert(y == x, 'wire changed the song');
    assert(
        song_inputs_smf_bytes(
            y, b.shiny == 1,
        ) == song_smf_bytes(b, b.prefix, b.suffix, seed, drift),
        'inputs compose another file',
    );
}

#[test]
fn genesis_track_through_inputs() {
    same_song(beast(1, 0, 0, 0), 0, Option::None);
}

#[test]
fn shiny_name_track_through_inputs() {
    same_song(beast(12, 41, 7, 1), 0, Option::None);
}

#[test]
fn bought_track_through_inputs() {
    same_song(beast(33, 0, 0, 0), 'block hash', Option::None);
}

#[test]
fn yeti_named_bought_track_through_inputs() {
    same_song(beast(68, 5, 3, 1), 'another hash', Option::None);
}

#[test]
fn community_species_through_inputs() {
    same_song(beast(76, 0, 0, 0), 0, Option::None);
}

#[test]
fn drifted_day_through_inputs() {
    let clock = DriftClock { day: 9, day_hash: 'day', week_hash: 'week', month_hash: 'month' };
    same_song(beast(20, 2, 9, 0), 0, Option::Some(clock));
}

#[test]
fn inputs_resolve_species_swap_channels_and_special() {
    // Harpy plays Pegasus' Genesis Track; a bought track plays its own species
    let swapped = genesis_song_inputs(beast(39, 0, 0, 0), 0, 0, 0, Option::None);
    assert(swapped.arrangement.identity.source_species_id == 40, 'genesis swap');
    assert(swapped.arrangement.channel_policy == ChannelPolicy::Genesis, 'genesis channels');
    let bought = genesis_song_inputs(beast(39, 0, 0, 0), 0, 0, 'h', Option::None);
    assert(bought.arrangement.identity.source_species_id == 39, 'no swap when bought');
    assert(bought.arrangement.channel_policy == ChannelPolicy::Seeded('h'), 'seeded channels');
    // the Yeti's special carries the track's name; score/program identity stays name 0
    let yeti = genesis_song_inputs(beast(68, 5, 3, 0), 5, 3, 0, Option::None);
    assert(yeti.arrangement.special == SpecialArrangement::Yeti(4 * 18 + 3), 'yeti name');
    assert(yeti.arrangement.identity.name_variant_id == 0, 'name 0 identity');
}

fn identity_of(b: PackableBeastV3) -> crate::inputs::BeastMusicalIdentity {
    let nv: u16 = if b.prefix == 0 {
        0
    } else {
        (b.prefix.into() - 1) * 18 + b.suffix.into()
    };
    crate::inputs::BeastMusicalIdentity {
        species_id: b.id, name_variant_id: nv, tier: b.tier, family: b.beast_type,
    }
}

/// Edition 0 of the default config, varied by a seed, is the Beast's bought track (no default
/// swap: Harpy plays its own; named, Yeti and community Beasts as well).
#[test]
fn default_edition_purchase_is_the_bought_track() {
    let config = crate::inputs::EditionCompositionConfig { composition_seed: 0 };
    let cases = array![
        (beast(39, 0, 0, 0), 'hash a'), (beast(12, 41, 7, 0), 'hash b'),
        (beast(68, 5, 3, 0), 'hash c'), (beast(76, 0, 0, 0), 'hash d'), (beast(1, 69, 18, 0), 0),
    ];
    for (b, seed) in cases {
        let base = crate::composition::generation::get_generation_inputs(config, 0, identity_of(b));
        let generated = crate::composition::generation::generate_inputs(base, seed);
        let expected = if seed == 0 {
            // zero is ordinary seed data here, not the Genesis sentinel
            crate::composition::genesis::bought_song_inputs(base.base_song, 0)
        } else {
            genesis_song_inputs(b, b.prefix, b.suffix, seed, Option::None)
        };
        assert(generated == ComposerInputs::Song(expected), 'not the bought track');
    }
}

#[test]
fn other_editions_change_only_the_theme() {
    let b = beast(12, 41, 7, 0);
    let config = crate::inputs::EditionCompositionConfig { composition_seed: 0 };
    let first = crate::composition::generation::get_generation_inputs(config, 0, identity_of(b));
    let third = crate::composition::generation::get_generation_inputs(config, 3, identity_of(b));
    assert(third.base_song.theme.motif_seed != first.base_song.theme.motif_seed, 'same theme');
    let mut back = third.base_song;
    back.theme.motif_seed = first.base_song.theme.motif_seed;
    back.treatment.rhythm_seed = first.base_song.treatment.rhythm_seed;
    assert(back == first.base_song, 'more than the theme changed');
    // every Beast of the species shares the edition's theme
    let other = crate::composition::generation::get_generation_inputs(
        config, 3, identity_of(beast(12, 2, 9, 0)),
    );
    assert(other.base_song.theme.motif_seed == third.base_song.theme.motif_seed, 'species theme');
}

#[test]
fn every_species_purchase_is_its_bought_track() {
    let config = crate::inputs::EditionCompositionConfig { composition_seed: 0 };
    let mut id: u64 = 1;
    while id <= 76 {
        let prefix: u8 = ((id * 7) % 69 + 1).try_into().unwrap();
        let suffix: u8 = ((id * 5) % 18 + 1).try_into().unwrap();
        for b in array![beast(id, 0, 0, 0), beast(id, prefix, suffix, 0)] {
            let seed = core::poseidon::poseidon_hash_span(
                array![id.into(), b.prefix.into()].span(),
            );
            let base = crate::composition::generation::get_generation_inputs(
                config, 0, identity_of(b),
            );
            assert(
                crate::composition::generation::generate_inputs(
                    base, seed,
                ) == ComposerInputs::Song(
                    genesis_song_inputs(b, b.prefix, b.suffix, seed, Option::None),
                ),
                'not the bought track',
            );
        }
        id += 1;
    }
}

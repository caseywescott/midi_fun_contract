//! BeastPureComposer as the Sound Manager calls it: a library call to the declared class, with a
//! song's or Sound Check's shared inputs and a token's `sound_effects`. One or two compositions per
//! test (memory).
use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::editions::edition_byte_array;
use beast_composer::composition::genesis::{
    genesis_byte_array, genesis_song_inputs, purchase_song_inputs, song_tracks, species_tier,
    species_type,
};
use beast_composer::composition::performance::apply_performance;
use beast_composer::composition::sound_check::{sound_check_inputs, sound_check_smf_bytes};
use beast_composer::inputs::evolution::{
    EvolutionConfig, EvolutionInputs, MilestoneHash, milestone_blocks,
};
use beast_composer::inputs::{
    BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig, EditionInputs, MusicIdentity,
};
use midi::pack::bytes_to_byte_array;
use snforge_std::{DeclareResultTrait, declare};
use crate::pure_composer::{
    IBeastPureComposerDispatcherTrait, IBeastPureComposerLibraryDispatcher, compose_sound,
    compose_staff_sound,
};
use crate::pure_generator::{
    IBeastPureGeneratorDispatcherTrait, IBeastPureGeneratorLibraryDispatcher,
};
use crate::synth_settings::{beast_synth_settings, yeti_synth_settings};

fn composer() -> IBeastPureComposerLibraryDispatcher {
    let class_hash = declare("BeastPureComposer").unwrap().contract_class().class_hash;
    IBeastPureComposerLibraryDispatcher { class_hash }
}

fn beast(id: u64, prefix: u8, suffix: u8, shiny: u8) -> PackableBeastV3 {
    PackableBeastV3 {
        id,
        prefix,
        suffix,
        level: 1,
        health: 100,
        shiny,
        animated: 0,
        tier: species_tier(id),
        beast_type: species_type(id),
    }
}

fn genesis(b: PackableBeastV3) -> ComposerInputs {
    ComposerInputs::Song(genesis_song_inputs(b, 0, 0, 0, Option::None))
}

#[test]
fn written_genesis_track_is_the_providers() {
    let b = beast(5, 0, 0, 0);
    let sound = composer().compose(genesis(b), 0);
    assert(sound.midi == genesis_byte_array(b), 'not the Genesis Track');
    assert(sound.settings == beast_synth_settings(species_type(5), false), 'not the settings');
}

#[test]
fn yeti_genesis_track_and_settings() {
    let b = beast(68, 0, 0, 0);
    let sound = composer().compose(genesis(b), 0);
    assert(sound.midi == genesis_byte_array(b), 'not the Yeti Genesis Track');
    assert(sound.settings == yeti_synth_settings(false), 'not the Yeti settings');
}

#[test]
fn sound_check_as_written() {
    let b = beast(30, 12, 4, 0);
    let sound = composer().compose(ComposerInputs::SoundCheck(sound_check_inputs(b)), 0);
    assert(sound.midi == bytes_to_byte_array(sound_check_smf_bytes(b).span()), 'not the check');
}

#[test]
fn mega_performance_is_the_mega_sound_of_the_performed_song() {
    // code 1: mega, 25000 us faster, ceiling +12, tenuto
    let b = beast(5, 0, 0, 0);
    let x = genesis(b);
    let sound = compose_sound(x, 1);
    let performed = match apply_performance(x, 1) {
        ComposerInputs::Song(song) => song,
        _ => core::panic_with_felt252('not a song'),
    };
    let song = match x {
        ComposerInputs::Song(song) => song,
        _ => core::panic_with_felt252('not a song'),
    };
    assert(performed.score.tempo_us == song.score.tempo_us - 25000, 'tempo');
    assert(performed.score.articulation_profile == 2, 'articulation');
    assert(
        sound.midi == midi::smf::smf_byte_array(1, 480, song_tracks(performed, true).span()),
        'not the mega performance',
    );
    assert(sound.settings == beast_synth_settings(species_type(5), true), 'not mega settings');
}

#[test]
fn mega_performance_of_the_sound_check() {
    // code 3: the mega presets, and the accented, faster check is not the written one
    let b = beast(30, 0, 0, 1);
    let x = sound_check_inputs(b);
    let check = compose_sound(ComposerInputs::SoundCheck(x), 3);
    assert(check.settings == beast_synth_settings(species_type(30), true), 'not mega settings');
    assert(check.midi != bytes_to_byte_array(sound_check_smf_bytes(b).span()), 'not performed');
}

#[test]
#[should_panic(expected: 'invalid sound effects')]
fn rejects_unassigned_sound_effects() {
    compose_sound(ComposerInputs::SoundCheck(sound_check_inputs(beast(1, 0, 0, 0))), 4);
}

/// The manager's purchase path: the generator's edition base and variation, then the composer.
/// The purchase is the seed's bought track in its own shape, on the species' theme.
#[test]
fn generated_purchase_composes_the_shaped_bought_track() {
    let generator = IBeastPureGeneratorLibraryDispatcher {
        class_hash: declare("BeastPureGenerator").unwrap().contract_class().class_hash,
    };
    let b = beast(12, 41, 7, 0);
    let identity = BeastMusicalIdentity {
        species_id: 12, name_variant_id: 40 * 18 + 7, tier: b.tier, family: b.beast_type,
    };
    let base = generator
        .get_generation_inputs(EditionCompositionConfig { composition_seed: 0 }, 0, identity);
    assert(
        generator
            .get_generation_inputs(
                EditionCompositionConfig { composition_seed: 'other' }, 9, identity,
            )
            .base_song == base
            .base_song,
        'editions keep the species song',
    );
    let inputs = generator.generate_inputs(base, 0, 'block hash');
    let song = match inputs {
        ComposerInputs::Song(song) => song,
        _ => core::panic_with_felt252('not a song'),
    };
    assert(song == purchase_song_inputs(base.base_song, 'block hash'), 'not the purchase');
    let sound = composer().compose(inputs, 0);
    assert(
        sound.midi == midi::smf::smf_byte_array(1, 480, song_tracks(song, false).span()),
        'not the purchase file',
    );
}

fn evolution_config(unlock_bps: u16) -> EvolutionConfig {
    EvolutionConfig {
        first_milestone_age: 10,
        initial_unlock_bps: unlock_bps,
        unlock_step_bps: 0,
        max_extra_channels: 5,
        max_tempo_delta_bpm: 2,
        max_velocity_delta: 6,
        ornament_chance_bps: 800,
    }
}

/// The manager's resolved context: every milestone from birth to the staff, with its hash.
fn staff_context(config: EvolutionConfig, birth: u64, staff: u64) -> EvolutionInputs {
    let mut milestones = array![];
    for block in milestone_blocks(config, birth, staff) {
        milestones.append(MilestoneHash { block_number: block, block_hash: block.into() + 'h' });
    }
    EvolutionInputs {
        birth_block: birth,
        staff_block: staff,
        drift_group: 'group',
        staff_hash: 'staff',
        milestones: milestones.span(),
    }
}

#[test]
fn staff_unlocks_the_next_written_roles_and_performs() {
    // a tier 5 Genesis Track keeps 3 of its 6 roles; every milestone unlocks, so all 6 play
    let b = beast(25, 0, 0, 0);
    let x = genesis(b);
    let config = evolution_config(10000);
    let staff = compose_staff_sound(x, 0, config, staff_context(config, 100, 200));
    let song = match x {
        ComposerInputs::Song(song) => song,
        _ => core::panic_with_felt252('not a song'),
    };
    assert(song.arrangement.channel_count == 3, 'tier 5 keeps 3');
    // the header's track count (byte 11): the tempo track, then one per voice and the drums
    let written = genesis_byte_array(b);
    assert(staff.midi != written, 'staff changed nothing');
    assert(staff.midi.at(11).unwrap() > written.at(11).unwrap(), 'no channel unlocked');
    assert(staff.settings == beast_synth_settings(species_type(25), false), 'not the settings');
}

#[test]
fn sound_check_has_no_staff() {
    let x = ComposerInputs::SoundCheck(sound_check_inputs(beast(30, 0, 0, 0)));
    let config = evolution_config(5000);
    assert(
        compose_staff_sound(x, 2, config, staff_context(config, 100, 300)) == compose_sound(x, 2),
        'a staff changed the check',
    );
}

#[test]
#[should_panic(expected: 'staff before birth')]
fn rejects_a_staff_before_birth() {
    let config = evolution_config(5000);
    let mut context = staff_context(config, 100, 100);
    context.birth_block = 101;
    compose_staff_sound(genesis(beast(1, 0, 0, 0)), 0, config, context);
}

/// From edition 1 a purchase is the edition's style engine on the species' theme, its seed the
/// purchase's low 64 bits; the composer plays it with the species' family settings.
#[test]
fn edition_purchase_composes_the_style_engine() {
    let generator = IBeastPureGeneratorLibraryDispatcher {
        class_hash: declare("BeastPureGenerator").unwrap().contract_class().class_hash,
    };
    let b = beast(40, 3, 9, 0);
    let identity = BeastMusicalIdentity {
        species_id: 40, name_variant_id: 2 * 18 + 9, tier: b.tier, family: b.beast_type,
    };
    let base = generator
        .get_generation_inputs(EditionCompositionConfig { composition_seed: 0 }, 3, identity);
    let seed: felt252 = 0x1234_0000000000000000 + 0xfedcba9876543210;
    let inputs = generator.generate_inputs(base, 3, seed);
    let expected = EditionInputs {
        identity: MusicIdentity { source_species_id: 40, name_variant_id: 0 },
        edition: 3,
        seed: 0xfedcba9876543210,
    };
    assert(inputs == ComposerInputs::Edition(expected), 'not the edition');
    let plain = composer().compose(inputs, 0);
    assert(plain.midi == edition_byte_array(40, false, 3, 0xfedcba9876543210), 'not the style');
    assert(plain.settings == beast_synth_settings(1, false), 'not the family');
    // sound effect 1 (old shiny) brings the mega leads
    let mega = composer().compose(inputs, 1);
    assert(mega.midi == edition_byte_array(40, true, 3, 0xfedcba9876543210), 'not the mega style');
    assert(mega.settings == beast_synth_settings(1, true), 'not the mega family');
    // an edition has no staff: compose_staff plays it as written
    let config = evolution_config(5000);
    assert(
        compose_staff_sound(inputs, 0, config, staff_context(config, 100, 300)) == plain,
        'a staff changed the edition',
    );
}

/// Species past the style engine's 75 keep the bought Song in every edition.
#[test]
fn later_species_buy_songs_in_every_edition() {
    let identity = BeastMusicalIdentity { species_id: 80, name_variant_id: 0, tier: 2, family: 1 };
    let base = beast_composer::composition::generation::get_generation_inputs(
        EditionCompositionConfig { composition_seed: 0 }, 5, identity,
    );
    match beast_composer::composition::generation::generate_inputs(base, 5, 'h') {
        ComposerInputs::Song(_) => {},
        _ => core::panic_with_felt252('not a song'),
    }
}

//! BeastPureComposer as the Sound Manager calls it: a library call to the declared class, with a
//! song's or Sound Check's shared inputs and a token's `sound_effects`. One or two compositions per
//! test (memory).
use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::drift::{DriftClock, drift_of};
use beast_composer::composition::editions::edition_byte_array;
use beast_composer::composition::genesis::{
    genesis_byte_array, genesis_song_inputs, purchase_song_inputs, song_smf_bytes, song_tracks,
    species_tier, species_type,
};
use beast_composer::composition::performance::apply_performance;
use beast_composer::composition::sound_check::{sound_check_inputs, sound_check_smf_bytes};
use beast_composer::inputs::drift::DriftInputs;
use beast_composer::inputs::{
    BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig, EditionInputs, MusicIdentity,
};
use midi::pack::bytes_to_byte_array;
use snforge_std::{DeclareResultTrait, declare};
use crate::pure_composer::{
    IBeastPureComposerDispatcherTrait, IBeastPureComposerLibraryDispatcher, compose_drift_sound,
    compose_sound,
};
use crate::pure_generator::{
    IBeastPureGeneratorDispatcherTrait, IBeastPureGeneratorLibraryDispatcher,
};
use crate::synth_settings::{beast_synth_settings, edition_synth_settings, yeti_synth_settings};

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
        sound
            .midi == midi::smf::smf_byte_array(
                1, 480, song_tracks(performed, true, false, 0).span(),
            ),
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
        sound.midi == midi::smf::smf_byte_array(1, 480, song_tracks(song, false, false, 0).span()),
        'not the purchase file',
    );
}

/// From edition 1 a purchase is the edition's style engine on the species' theme, its seed the
/// purchase's low 64 bits; the composer plays it with the style's presets for the species' type.
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
    assert(
        plain.midi == edition_byte_array(40, false, 3, 0xfedcba9876543210, Option::None, false),
        'not the style',
    );
    // edition 3 is the lullaby (style 2); species 40 is a Hunter (type 1)
    assert(plain.settings == edition_synth_settings(2, 1, false), 'not the edition presets');
    // sound effect 1 (old shiny) brings the mega leads
    let mega = composer().compose(inputs, 1);
    assert(
        mega.midi == edition_byte_array(40, true, 3, 0xfedcba9876543210, Option::None, false),
        'not the mega style',
    );
    assert(mega.settings == edition_synth_settings(2, 1, true), 'not the mega edition presets');
    // on a day of drift: the edition's layers, keyed by the species and the drift's name
    let d = day(2 * 18 + 9, 45);
    let drifted = compose_drift_sound(inputs, 0, d);
    assert(drifted.midi != plain.midi, 'the day changed nothing');
    assert(
        drifted
            .midi == edition_byte_array(
                40, false, 3, 0xfedcba9876543210, Option::Some(drift_of(40, d)), false,
            ),
        'not the edition on that day',
    );
    assert(drifted.settings == plain.settings, 'the day changed the presets');
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

/// Every Monthly Track Edition settings value (4 styles x 3 types x mega) serializes as the
/// generator's (synth_settings.mjs editionSynthSettings) and passes onchain-midi-player's checks,
/// AM routes included (Ring Mod Bell 78, AY Buzzer Bass 88).
#[test]
fn edition_settings_serialize_as_generated_and_validate() {
    let hashes = crate::synth_settings::EDITION_SERDE_HASHES.span();
    let mut style: u32 = 0;
    while style < 4 {
        let mut t: u32 = 0;
        while t < 3 {
            for mega in array![false, true] {
                let s = crate::synth_settings::edition_synth_settings(style, t, mega);
                let mut out: Array<felt252> = array![];
                s.serialize(ref out);
                let i = (style * 3 + t) * 2 + if mega {
                    1
                } else {
                    0
                };
                assert(
                    core::poseidon::poseidon_hash_span(out.span()) == *hashes.at(i),
                    'edition settings differ',
                );
                midi::settings::validate(@s);
            }
            t += 1;
        }
        style += 1;
    }
}

/// Day `d` of drift for special name `name`, with stand-in hashes for its first blocks.
fn day(name: u16, d: u64) -> DriftInputs {
    DriftInputs {
        name_variant_id: name,
        day: d,
        day_hash: 'day' + d.into(),
        week_hash: 'week' + ((d - 1) / 7).into(),
        month_hash: 'month' + ((d - 1) / 30).into(),
    }
}

/// compose_drift on a track's stored inputs plays what song_smf_bytes plays with the same day of
/// drift (the Beast's drift: its species and special name; a Species Song's, its species').
fn same_drift(b: PackableBeastV3, prefix: u8, suffix: u8, seed: felt252, d: u64) {
    let x = genesis_song_inputs(b, prefix, suffix, seed, Option::None);
    let name: u16 = if prefix == 0 {
        0
    } else {
        (prefix.into() - 1) * 18 + suffix.into()
    };
    let inputs = day(name, d);
    let clock = DriftClock {
        day: d,
        day_hash: inputs.day_hash,
        week_hash: inputs.week_hash,
        month_hash: inputs.month_hash,
    };
    assert(
        compose_drift_sound(ComposerInputs::Song(x), 0, inputs)
            .midi == bytes_to_byte_array(
                song_smf_bytes(b, prefix, suffix, seed, Option::Some(clock)).span(),
            ),
        'not the song on that day',
    );
}

#[test]
fn species_song_drifts_as_casey_drift() {
    same_drift(beast(21, 0, 0, 0), 0, 0, 0, 45);
}

#[test]
fn swapped_species_song_drifts_with_its_source() {
    same_drift(beast(39, 0, 0, 0), 0, 0, 0, 100);
}

#[test]
fn name_track_drifts_by_its_name() {
    same_drift(beast(12, 41, 7, 0), 41, 7, 0, 200);
}

#[test]
fn bought_track_drifts() {
    same_drift(beast(33, 0, 0, 0), 0, 0, 'block hash', 75);
}

#[test]
fn yeti_bought_track_drifts() {
    same_drift(beast(68, 5, 3, 0), 5, 3, 'another hash', 130);
}

#[test]
fn community_species_song_drifts() {
    same_drift(
        PackableBeastV3 {
            id: 76,
            prefix: 0,
            suffix: 0,
            level: 1,
            health: 100,
            shiny: 0,
            animated: 0,
            tier: 2,
            beast_type: 1,
        },
        0,
        0,
        0,
        300,
    );
}

#[test]
fn sound_check_does_not_drift() {
    let x = ComposerInputs::SoundCheck(sound_check_inputs(beast(30, 0, 0, 0)));
    assert(compose_drift_sound(x, 2, day(0, 77)) == compose_sound(x, 2), 'a sound check drifted');
}

#[test]
#[should_panic(expected: 'days count from 1')]
fn rejects_day_zero() {
    let zero = DriftInputs { name_variant_id: 0, day: 0, day_hash: 1, week_hash: 1, month_hash: 1 };
    compose_drift_sound(genesis(beast(1, 0, 0, 0)), 0, zero);
}

/// A future Beast (species past 75, family and tier from its token) through the manager's path:
/// the base song, a bought track in edition 0 and a later edition, and its Sound Check, each with
/// a sound effect.
fn future_beast(species: u32, family: u8, tier: u8) -> beast_composer::inputs::GenerationInputs {
    beast_composer::composition::generation::get_generation_inputs(
        EditionCompositionConfig { composition_seed: 0 },
        0,
        BeastMusicalIdentity { species_id: species, name_variant_id: 0, tier, family },
    )
}

fn sounds(x: ComposerInputs, fx: u8) {
    let sound = composer().compose(x, fx);
    assert(sound.midi.len() > 100, 'no music');
}

#[test]
fn future_species_76_song() {
    sounds(ComposerInputs::Song(future_beast(76, 0, 1).base_song), 1);
}

#[test]
fn future_species_max_song() {
    sounds(ComposerInputs::Song(future_beast(0xffffffff, 2, 5).base_song), 2);
}

#[test]
fn future_species_bought_tracks() {
    let base = future_beast(150, 1, 3);
    let g = IBeastPureGeneratorLibraryDispatcher {
        class_hash: declare("BeastPureGenerator").unwrap().contract_class().class_hash,
    };
    sounds(g.generate_inputs(base, 0, 'purchase'), 3);
    sounds(g.generate_inputs(base, 9, 'purchase'), 0);
}

#[test]
fn future_species_sound_check() {
    let b = PackableBeastV3 {
        id: 1000,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 0,
        animated: 0,
        tier: 4,
        beast_type: 2,
    };
    sounds(ComposerInputs::SoundCheck(sound_check_inputs(b)), 1);
}

/// A Song a species owner can publish: valid, with four voices spread wide on the lowest tonic.
/// Through the class, as the Sound Manager plays it, it composes (it panicked with
/// 'u32_sub Overflow'): the bass the composer realizes below MIDI 0 is raised by octaves.
#[test]
fn low_tonic_wide_song_plays() {
    let mut x = genesis_song_inputs(beast(4, 0, 0, 0), 0, 0, 0, Option::None);
    x.score.tonic_keynum = 24;
    x.treatment.spacing = 0;
    let sound = composer().compose(ComposerInputs::Song(x), 0);
    assert(
        sound.midi == midi::smf::smf_byte_array(1, 480, song_tracks(x, false, false, 0).span()),
        'not the low song',
    );
    assert(sound.settings == beast_synth_settings(species_type(4), false), 'not the settings');
}

fn performed_song(x: ComposerInputs, fx: u8) -> beast_composer::inputs::SongInputs {
    match apply_performance(x, fx) {
        ComposerInputs::Song(song) => song,
        _ => core::panic_with_felt252('not a song'),
    }
}

#[test]
fn echo_performance_of_a_song() {
    // code 2: the chip echo on the performed song, the family's settings
    let x = genesis(beast(21, 0, 0, 0));
    let sound = compose_sound(x, 2);
    assert(
        sound
            .midi == midi::smf::smf_byte_array(
                1, 480, song_tracks(performed_song(x, 2), false, true, 0).span(),
            ),
        'not the echo performance',
    );
    assert(sound.settings == beast_synth_settings(species_type(21), false), 'not the settings');
}

#[test]
fn mega_echo_performance_of_a_song() {
    // code 3: mega and the chip echo
    let x = genesis(beast(45, 0, 0, 0));
    let sound = compose_sound(x, 3);
    assert(
        sound
            .midi == midi::smf::smf_byte_array(
                1, 480, song_tracks(performed_song(x, 3), true, true, 0).span(),
            ),
        'not the mega echo performance',
    );
    assert(sound.settings == beast_synth_settings(species_type(45), true), 'not mega settings');
}

#[test]
fn echo_on_editions() {
    let e = ComposerInputs::Edition(
        EditionInputs {
            identity: MusicIdentity { source_species_id: 40, name_variant_id: 0 },
            edition: 3,
            seed: 0xfedcba9876543210,
        },
    );
    assert(
        compose_sound(e, 2)
            .midi == edition_byte_array(40, false, 3, 0xfedcba9876543210, Option::None, true),
        'not the echoed edition',
    );
    assert(
        compose_sound(e, 3)
            .midi == edition_byte_array(40, true, 3, 0xfedcba9876543210, Option::None, true),
        'not the mega echoed edition',
    );
}

fn written_song(x: ComposerInputs) -> beast_composer::inputs::SongInputs {
    match x {
        ComposerInputs::Song(song) => song,
        _ => core::panic_with_felt252('not a song'),
    }
}

#[test]
fn no_grace_notes_on_drift_day_1() {
    let x = genesis(beast(20, 0, 0, 0));
    let d = day(0, 1);
    let drifted = beast_composer::composition::genesis::drifted_song_inputs(
        written_song(x), drift_of(20, d),
    );
    assert(
        compose_drift_sound(x, 0, d)
            .midi == midi::smf::smf_byte_array(
                1, 480, song_tracks(drifted, false, false, 1).span(),
            ),
        'grace notes on day 1',
    );
}

#[test]
fn grace_notes_from_drift_day_2() {
    let x = genesis(beast(20, 0, 0, 0));
    let d = day(0, 2);
    let drifted = beast_composer::composition::genesis::drifted_song_inputs(
        written_song(x), drift_of(20, d),
    );
    assert(
        compose_drift_sound(x, 0, d)
            .midi == midi::smf::smf_byte_array(
                1, 480, song_tracks(drifted, false, false, 2).span(),
            ),
        'no grace notes on day 2',
    );
}

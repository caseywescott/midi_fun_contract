//! Low-tonic Songs. `validate_song` accepts tonics 24..=96 and one to four voices; spread voices on
//! a low tonic are placed far below hearing, and four of them spread wide or normal realize the
//! bass under MIDI 0 ('u32_sub Overflow'). A Song whose lowest voice would be placed under C1 is
//! now composed whole octaves up, every voice together (`beast_v11::register_tonic`): it plays as
//! the same recipe on that higher tonic. The recipes are Genesis Tracks (`genesis_song_inputs`)
//! moved to a low tonic and spread, which the JS reference plays the same way:
//! `low_tonic_parity_fixture_*`
//! (ignored) prints them for scripts/low_tonic_parity.mjs. A test run keeps what it allocates: at
//! most six compositions per test.
use crate::composition::beast_v3_sound::PackableBeastV3;
use crate::composition::genesis::{genesis_song_inputs, song_tracks, species_tier, species_type};
use crate::inputs::{ComposerInputs, SongInputs, validate_inputs};

/// A species' Genesis Track recipe (four voices and the countersubject) on `tonic`, spread by
/// `spacing`.
fn low_song(species: u64, tonic: u8, spacing: u8) -> SongInputs {
    let b = PackableBeastV3 {
        id: species,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 0,
        animated: 0,
        tier: species_tier(species),
        beast_type: species_type(species),
    };
    let mut x = genesis_song_inputs(b, 0, 0, 0, Option::None);
    x.score.tonic_keynum = tonic;
    x.treatment.spacing = spacing;
    x
}

/// The Song's file as the composer plays it (written: sound preset 0), from valid inputs.
fn low_midi(x: SongInputs) -> Array<u8> {
    validate_inputs(ComposerInputs::Song(x));
    midi::smf::smf_bytes(1, 480, song_tracks(x, false, false, 0).span())
}

fn hash(midi: Span<u8>) -> felt252 {
    core::poseidon::poseidon_hash_span(midi::pack::to_felt252_array(midi).span())
}

/// The repro: species 4's Genesis Track (Harmonic minor, four voices, the countersubject) on tonic
/// 24, spread wide. Its bass panicked with 'u32_sub Overflow'; its lowest voice (offset -11) is
/// placed under C1 until two octaves up, so it plays as the recipe on tonic 48, the file the JS
/// reference makes.
#[test]
fn low_tonic_wide_song_plays_two_octaves_up() {
    let x = low_song(4, 24, 0);
    assert(x.score.voice_count == 4 && x.score.mode_id == 8, 'not the repro recipe');
    let midi = low_midi(x);
    assert(midi == low_midi(low_song(4, 48, 0)), 'not the song on tonic 48');
    assert(
        hash(
            midi.span(),
        ) == 2554819762683534091194791980860849534186583105597775267446668339692500298361,
        'not the reference file',
    );
}

/// The boundary, spread normal (offset -8): tonic 43 places the lowest voice at C1 and plays as on
/// v1.0.0; tonic 42 would place it a step under, so it plays one octave up, as tonic 54.
#[test]
fn low_tonic_normal_song_moves_one_octave_under_c1() {
    let kept = low_midi(low_song(4, 43, 1));
    assert(
        hash(
            kept.span(),
        ) == 3047849054565007533258417120693415813547776177921163231900534199304074594889,
        'tonic 43 changed',
    );
    assert(low_midi(low_song(4, 42, 1)) == low_midi(low_song(4, 54, 1)), 'not one octave up');
}

/// Every tonic of `lo..=hi`, spread wide and normal, composes a file.
fn sweep(species: u64, lo: u8, hi: u8) {
    let mut tonic = lo;
    while tonic <= hi {
        for spacing in array![0_u8, 1] {
            let midi = low_midi(low_song(species, tonic, spacing));
            assert(midi.len() > 1000 && *midi.at(0) == 'M' && *midi.at(1) == 'T', 'no file');
        }
        tonic += 1;
    }
}

// Tonics 24..=48, wide and normal, for three recipes: species 4 (Harmonic minor), 33 (Phrygian) and
// 60 (Dorian #4), each its own theme and seeds. On v1.0.0 four-voice Songs panicked up to tonic 39
// (wide) and 34 (normal); the lowest voice is placed at C1 from tonic 42-48 (wide) and 38-43
// (normal), and from 48 for every recipe.

#[test]
fn low_tonic_sweep_harmonic_minor_24_to_26() {
    sweep(4, 24, 26);
}

#[test]
fn low_tonic_sweep_harmonic_minor_27_to_29() {
    sweep(4, 27, 29);
}

#[test]
fn low_tonic_sweep_harmonic_minor_30_to_32() {
    sweep(4, 30, 32);
}

#[test]
fn low_tonic_sweep_harmonic_minor_33_to_35() {
    sweep(4, 33, 35);
}

#[test]
fn low_tonic_sweep_harmonic_minor_36_to_38() {
    sweep(4, 36, 38);
}

#[test]
fn low_tonic_sweep_harmonic_minor_39_to_41() {
    sweep(4, 39, 41);
}

#[test]
fn low_tonic_sweep_harmonic_minor_42_to_44() {
    sweep(4, 42, 44);
}

#[test]
fn low_tonic_sweep_harmonic_minor_45_to_46() {
    sweep(4, 45, 46);
}

#[test]
fn low_tonic_sweep_harmonic_minor_47_to_48() {
    sweep(4, 47, 48);
}

#[test]
fn low_tonic_sweep_phrygian_24_to_26() {
    sweep(33, 24, 26);
}

#[test]
fn low_tonic_sweep_phrygian_27_to_29() {
    sweep(33, 27, 29);
}

#[test]
fn low_tonic_sweep_phrygian_30_to_32() {
    sweep(33, 30, 32);
}

#[test]
fn low_tonic_sweep_phrygian_33_to_35() {
    sweep(33, 33, 35);
}

#[test]
fn low_tonic_sweep_phrygian_36_to_38() {
    sweep(33, 36, 38);
}

#[test]
fn low_tonic_sweep_phrygian_39_to_41() {
    sweep(33, 39, 41);
}

#[test]
fn low_tonic_sweep_phrygian_42_to_44() {
    sweep(33, 42, 44);
}

#[test]
fn low_tonic_sweep_phrygian_45_to_46() {
    sweep(33, 45, 46);
}

#[test]
fn low_tonic_sweep_phrygian_47_to_48() {
    sweep(33, 47, 48);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_24_to_26() {
    sweep(60, 24, 26);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_27_to_29() {
    sweep(60, 27, 29);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_30_to_32() {
    sweep(60, 30, 32);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_33_to_35() {
    sweep(60, 33, 35);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_36_to_38() {
    sweep(60, 36, 38);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_39_to_41() {
    sweep(60, 39, 41);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_42_to_44() {
    sweep(60, 42, 44);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_45_to_46() {
    sweep(60, 45, 46);
}

#[test]
fn low_tonic_sweep_dorian_sharp_four_47_to_48() {
    sweep(60, 47, 48);
}

/// One recipe at tonics 24, 30, 36 and 42, wide, normal and close: a LOW line each (the file's
/// felts: length and hash) for scripts/low_tonic_parity.mjs.
fn low_tonic_parity(species: u64) {
    for tonic in array![24_u8, 30, 36, 42] {
        for spacing in array![0_u8, 1, 2] {
            let midi = midi::pack::to_felt252_array(
                low_midi(low_song(species, tonic, spacing)).span(),
            );
            println!(
                "LOW case={} tonic={} spacing={} midi_len={} midi={}",
                species,
                tonic,
                spacing,
                *midi.at(0),
                core::poseidon::poseidon_hash_span(midi.span()),
            );
        }
    }
}

// One species per mode the Songs play: 4 Harmonic minor, 33 Phrygian, 60 Dorian #4, 3 Dorian,
// 59 Locrian, 1 Aeolian.

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn low_tonic_parity_fixture_0() {
    low_tonic_parity(4);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn low_tonic_parity_fixture_1() {
    low_tonic_parity(33);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn low_tonic_parity_fixture_2() {
    low_tonic_parity(60);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn low_tonic_parity_fixture_3() {
    low_tonic_parity(3);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn low_tonic_parity_fixture_4() {
    low_tonic_parity(59);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn low_tonic_parity_fixture_5() {
    low_tonic_parity(1);
}

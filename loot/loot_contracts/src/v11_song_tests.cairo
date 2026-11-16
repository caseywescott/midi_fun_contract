// Loot songs through the v1.1 BeastPureComposer path (compose / compose_drift on ComposerInputs::Song)
// against the Loot lab's songs (genesis::song_smf_bytes).
use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::drift::DriftClock;
use beast_composer::composition::genesis::{genesis_song_inputs, song_smf_bytes};
use beast_composer::inputs::ComposerInputs;
use beast_composer::inputs::drift::DriftInputs;
use beast_composer::composition::drift::drift_of;
use beast_composer::composition::genesis::{drifted_song_inputs, song_tracks};
use beast_composer::composition::performance::apply_performance;
use midi::smf::smf_byte_array;

// v1.1.0 beast_contracts::pure_composer::compose_with, Song branch, verbatim in effect.
fn v11_song(inputs: ComposerInputs, sound_effects: u8, drift: Option<DriftInputs>) -> ByteArray {
    let drifted = match (inputs, drift) {
        (ComposerInputs::Song(song), Option::Some(d)) => ComposerInputs::Song(
            drifted_song_inputs(song, drift_of(song.arrangement.identity.source_species_id, d)),
        ),
        _ => inputs,
    };
    let performed = apply_performance(drifted, sound_effects);
    let (echo_bit, mega_bit) = DivRem::div_rem(sound_effects, 2);
    let day = match drift {
        Option::Some(d) => d.day,
        Option::None => 0,
    };
    match performed {
        ComposerInputs::Song(song) => smf_byte_array(1, 480, song_tracks(song, mega_bit != 0, echo_bit != 0, day).span()),
        _ => panic!("song"),
    }
}
use loot_composer::songs::name_from_variant;
use loot_composer::species::loot_species;
use midi::pack::bytes_to_byte_array;

fn beast(species: u32, mega: bool, prefix: u8, suffix: u8) -> PackableBeastV3 {
    let s = loot_species(species);
    PackableBeastV3 {
        id: species.into(), prefix, suffix, level: 1, health: 100, shiny: if mega { 1 } else { 0 },
        animated: 0, tier: s.tier, beast_type: s.beast_type,
    }
}

fn same(species: u32, mega: bool, name: u16, drift: Option<DriftInputs>) -> bool {
    let (p, q) = name_from_variant(name);
    let b = beast(species, mega, p, q);
    let se: u8 = if mega { 1 } else { 0 };
    let (lab, v11) = match drift {
        Option::None => (
            song_smf_bytes(b, p, q, 0, Option::None),
            v11_song(ComposerInputs::Song(genesis_song_inputs(b, p, q, 0, Option::None)), se, Option::None),
        ),
        Option::Some(d) => {
            let c = DriftClock { day: d.day, day_hash: d.day_hash, week_hash: d.week_hash, month_hash: d.month_hash };
            (
                song_smf_bytes(b, p, q, 0, Option::Some(c)),
                v11_song(ComposerInputs::Song(genesis_song_inputs(b, p, q, 0, Option::None)), se, Option::Some(d)),
            )
        },
    };
    bytes_to_byte_array(lab.span()) == v11
}

#[test]
#[ignore]
fn v11_species_songs() {
    assert!(same(76, false, 0, Option::None), "76");
    assert!(same(90, false, 0, Option::None), "90");
    assert!(same(105, false, 0, Option::None), "105");
}

#[test]
#[ignore]
fn v11_name_songs() {
    assert!(same(83, false, 1242, Option::None), "83 name");
    assert!(same(97, false, 7, Option::None), "97 name");
}

#[test]
#[ignore]
fn v11_drift_songs() {
    assert!(same(86, false, 0, Option::Some(DriftInputs { name_variant_id: 0, day: 45, day_hash: 0x2956ffbf266d21c7d5e01968335e1bab126495564d8dcf5a92c5b14507e72c6, week_hash: 0x52e10e4521547a4ed4aa421ffc96e651368b640e0f5998520234a674eb594dc, month_hash: 0x3b2372967bbbc009fcabee385f9fd3a22c32d4f5cd9f29b6b424a25ea8b9ec3 })), "86 drift");
    assert!(same(93, false, 300, Option::Some(DriftInputs { name_variant_id: 300, day: 45, day_hash: 0x2956ffbf266d21c7d5e01968335e1bab126495564d8dcf5a92c5b14507e72c6, week_hash: 0x52e10e4521547a4ed4aa421ffc96e651368b640e0f5998520234a674eb594dc, month_hash: 0x3b2372967bbbc009fcabee385f9fd3a22c32d4f5cd9f29b6b424a25ea8b9ec3 })), "93 name drift");
}

#[test]
#[ignore]
fn v11_mega_is_not_the_labs_mega() {
    // v1.1's mega (sound_effects 1) also plays faster, louder and tenuto; the lab's Mega does not
    assert!(!same(80, true, 0, Option::None), "80 mega");
}

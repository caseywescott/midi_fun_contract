//! Actual production declared classes, not a fake MIDI provider.
use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::genesis::genesis_byte_array;
use beast_composer::inputs::{BeastMusicalIdentity, ComposerInputs, EditionCompositionConfig};
use core::dict::{Felt252Dict, Felt252DictTrait};
use midi::types::TinySynthSound;
use snforge_std::{DeclareResultTrait, declare};
use crate::pure_composer::{IBeastPureComposerDispatcherTrait, IBeastPureComposerLibraryDispatcher};
use crate::pure_generator::{
    IBeastPureGeneratorDispatcherTrait, IBeastPureGeneratorLibraryDispatcher,
};

fn assert_sound(sound: @TinySynthSound) {
    assert(sound.midi.len() > 14, 'empty SMF');
    assert(sound.midi.at(0) == Option::Some(77), 'SMF M');
    assert(sound.midi.at(1) == Option::Some(84), 'SMF T');
    assert(sound.midi.at(2) == Option::Some(104), 'SMF h');
    assert(sound.midi.at(3) == Option::Some(100), 'SMF d');
    midi::settings::validate(@sound.settings);
    assert(sound.settings.timbres.len() > 0, 'missing timbres');
    midi_role_mask(sound);
}

fn targets() -> (IBeastPureGeneratorLibraryDispatcher, IBeastPureComposerLibraryDispatcher) {
    let generator = declare("BeastPureGenerator").unwrap().contract_class().class_hash;
    let composer = declare("BeastPureComposer").unwrap().contract_class().class_hash;
    (
        IBeastPureGeneratorLibraryDispatcher { class_hash: generator },
        IBeastPureComposerLibraryDispatcher { class_hash: composer },
    )
}

#[test]
#[available_gas(1000000000)]
fn test_actual_pure_light_original_smoke() {
    let (generator, composer) = targets();
    let base = generator
        .get_generation_inputs(
            EditionCompositionConfig { composition_seed: 0 },
            0,
            BeastMusicalIdentity { species_id: 21, name_variant_id: 0, tier: 5, family: 0 },
        );
    let sound = composer.compose(ComposerInputs::Song(base.base_song), 0);
    assert_sound(@sound);
    let legacy = genesis_byte_array(
        PackableBeastV3 {
            id: 21,
            prefix: 0,
            suffix: 0,
            level: 1,
            health: 100,
            shiny: 0,
            animated: 0,
            tier: 5,
            beast_type: 0,
        },
    );
    assert(sound.midi == legacy, 'legacy normal parity');
}

#[test]
#[available_gas(1000000000)]
fn test_actual_pure_yeti_original_smoke() {
    let (generator, composer) = targets();
    let base = generator
        .get_generation_inputs(
            EditionCompositionConfig { composition_seed: 0 },
            0,
            BeastMusicalIdentity { species_id: 68, name_variant_id: 0, tier: 4, family: 2 },
        );
    let sound = composer.compose(ComposerInputs::Song(base.base_song), 0);
    assert_sound(@sound);
    let legacy = genesis_byte_array(
        PackableBeastV3 {
            id: 68,
            prefix: 0,
            suffix: 0,
            level: 1,
            health: 100,
            shiny: 0,
            animated: 0,
            tier: 4,
            beast_type: 2,
        },
    );
    assert(sound.midi == legacy, 'legacy Yeti parity');
}

#[test]
#[available_gas(1000000000)]
fn test_actual_pure_staff_smoke_and_replay() {
    use beast_composer::inputs::evolution::{EvolutionConfig, EvolutionInputs, MilestoneHash};
    let (generator, composer) = targets();
    let base = generator
        .get_generation_inputs(
            EditionCompositionConfig { composition_seed: 0 },
            0,
            BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 },
        );
    let inputs = generator.generate_inputs(base, 123);
    let config = EvolutionConfig {
        first_milestone_age: 10,
        initial_unlock_bps: 10000,
        unlock_step_bps: 0,
        max_extra_channels: 3,
        max_tempo_delta_bpm: 2,
        max_velocity_delta: 8,
        ornament_chance_bps: 1000,
    };
    let hashes = array![MilestoneHash { block_number: 110, block_hash: 9 }];
    let context = EvolutionInputs {
        birth_block: 100,
        staff_block: 110,
        drift_group: 37,
        staff_hash: 999,
        milestones: hashes.span(),
    };
    let sound = composer.compose_staff(inputs, 3, config, context);
    assert_sound(@sound);
    let replay = composer.compose_staff(inputs, 3, config, context);
    assert(sound.midi == replay.midi && sound.settings == replay.settings, 'actual staff replay');
}

// Parse actual emitted SMF rather than counting internal masks. Every channel
// message is bounded and every sounding program/drum has a matching timbre in
// the very same returned TinySynthSound.
fn be32(bytes: @ByteArray, at: u32) -> u32 {
    let mut result: u32 = 0;
    let mut i = 0;
    while i < 4 {
        result = result * 256 + bytes.at(at + i).unwrap().into();
        i += 1;
    }
    result
}
fn vlq(bytes: @ByteArray, start: u32) -> (u32, u32) {
    let mut at = start;
    let mut value: u32 = 0;
    loop {
        let b = bytes.at(at).unwrap();
        value = value * 128 + (b % 128).into();
        at += 1;
        assert(at - start <= 4, 'invalid MIDI VLQ');
        if b < 128 {
            break;
        }
    }
    (at, value)
}
fn has_timbre(sound: @TinySynthSound, drum: bool, slot: u8) -> bool {
    for t in sound.settings.timbres {
        if t.drum == drum && t.slot == slot {
            return true;
        }
    }
    false
}
fn midi_role_mask(sound: @TinySynthSound) -> u16 {
    let bytes = @sound.midi;
    let mut programs: Felt252Dict<u8> = Default::default();
    let mut mask: u16 = 0;
    let mut chunk: u32 = 14;
    while chunk < bytes.len() {
        assert(
            bytes.at(chunk) == Option::Some(77)
                && bytes.at(chunk + 1) == Option::Some(84)
                && bytes.at(chunk + 2) == Option::Some(114)
                && bytes.at(chunk + 3) == Option::Some(107),
            'MTrk',
        );
        let end = chunk + 8 + be32(bytes, chunk + 4);
        let mut at = chunk + 8;
        let mut running: u8 = 0;
        while at < end {
            let (next, _) = vlq(bytes, at);
            at = next;
            let first = bytes.at(at).unwrap();
            let status = if first >= 128 {
                at += 1;
                first
            } else {
                running
            };
            if status == 255 {
                at += 1; // meta type
                let (next, len) = vlq(bytes, at);
                at = next + len;
                running = 0;
                continue;
            }
            assert(status >= 128 && status < 240, 'channel status');
            running = status;
            let channel = status % 16;
            let kind = status / 16;
            let a = bytes.at(at).unwrap();
            at += 1;
            assert(a < 128, 'MIDI first data');
            if kind == 12 {
                programs.insert(channel.into(), a);
            }
            if kind != 12 && kind != 13 {
                let b = bytes.at(at).unwrap();
                at += 1;
                assert(b < 128, 'MIDI second data');
                if kind == 9 && b > 0 {
                    assert(
                        has_timbre(
                            sound,
                            channel == 9,
                            if channel == 9 {
                                a
                            } else {
                                programs.get(channel.into())
                            },
                        ),
                        'MIDI settings coverage',
                    );
                    let mut bit: u16 = 1;
                    let mut c: u8 = 0;
                    while c < channel {
                        bit *= 2;
                        c += 1;
                    }
                    mask = mask | bit;
                }
            }
        }
        assert(at == end, 'track boundary');
        chunk = end;
    }
    assert(chunk == bytes.len(), 'file boundary');
    mask
}
fn authored_song() -> ComposerInputs {
    let base = beast_composer::composition::recipe::get_generation_inputs(
        EditionCompositionConfig { composition_seed: 0 },
        0,
        BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 },
    );
    ComposerInputs::Song(base.base_song)
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_song_all_four_presets() {
    let (_, composer) = targets();
    let x = authored_song();
    let original_wire = beast_composer::inputs::encode_inputs(x);
    let mut hashes = array![];
    for code in array![0_u8, 1, 2, 3].span() {
        let sound = composer.compose(x, *code);
        assert_sound(@sound);
        let mut serial = array![];
        Serde::serialize(@sound.midi, ref serial);
        hashes.append(core::poseidon::poseidon_hash_span(serial.span()));
    }
    assert(
        *hashes.at(0) != *hashes.at(1)
            && *hashes.at(0) != *hashes.at(2)
            && *hashes.at(0) != *hashes.at(3)
            && *hashes.at(1) != *hashes.at(3),
        'preset output consumption',
    );
    assert(beast_composer::inputs::encode_inputs(x) == original_wire, 'stored recipe unchanged');
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_sound_check_all_presets_and_no_temporal_hashes() {
    use beast_composer::inputs::{MusicIdentity, SoundCheckInputs};
    use beast_composer::inputs::evolution::{EvolutionConfig, EvolutionInputs};
    let (_, composer) = targets();
    let x = ComposerInputs::SoundCheck(
        SoundCheckInputs {
            identity: MusicIdentity {
                source_species_id: 0xffffffffffffffff, name_variant_id: 1242,
            },
            mode_id: 26,
            tonic_keynum: 103,
            family: 1,
            tempo_us: 500000,
            velocity_ceiling: 112,
            articulation_profile: 0,
        },
    );
    let invalid_unused_config = EvolutionConfig {
        first_milestone_age: 0,
        initial_unlock_bps: 0,
        unlock_step_bps: 0,
        max_extra_channels: 0,
        max_tempo_delta_bpm: 0,
        max_velocity_delta: 0,
        ornament_chance_bps: 0,
    };
    let context = EvolutionInputs {
        birth_block: 100,
        staff_block: 100,
        drift_group: 0,
        staff_hash: 0,
        milestones: array![].span(),
    };
    for code in array![0_u8, 1, 2, 3].span() {
        let normal = composer.compose(x, *code);
        assert_sound(@normal);
        let temporal = composer.compose_staff(x, *code, invalid_unused_config, context);
        assert(
            normal.midi == temporal.midi && normal.settings == temporal.settings,
            'Sound Check never drifts',
        );
    }
}
fn unlock_witness(cfg: beast_composer::inputs::evolution::EvolutionConfig) -> (felt252, felt252) {
    use beast_composer::inputs::evolution::{EvolutionInputs, MilestoneHash};
    let mut a: u64 = 1;
    while a <= 64 {
        let one = array![MilestoneHash { block_number: 110, block_hash: a.into() }];
        let first = beast_composer::composition::evolution::resolve_evolution(
            cfg,
            EvolutionInputs {
                birth_block: 100,
                staff_block: 110,
                drift_group: 9,
                staff_hash: 123,
                milestones: one.span(),
            },
            3,
        )
            .unlocked_extra_mask;
        if first / 4 % 2 == 1 && first % 2 == 0 {
            let mut b: u64 = 1;
            while b <= 64 {
                let two = array![
                    MilestoneHash { block_number: 110, block_hash: a.into() },
                    MilestoneHash { block_number: 120, block_hash: b.into() }
                ];
                let later = beast_composer::composition::evolution::resolve_evolution(
                    cfg,
                    EvolutionInputs {
                        birth_block: 100,
                        staff_block: 120,
                        drift_group: 9,
                        staff_hash: 456,
                        milestones: two.span(),
                    },
                    3,
                )
                    .unlocked_extra_mask;
                if later % 2 == 1 {
                    return (a.into(), b.into());
                }
                b += 1;
            }
        }
        a += 1;
    }
    panic!("missing out of order witness")
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_unlocked_role_survives_lower_unlock_and_new_staff_preset() {
    use beast_composer::inputs::evolution::{EvolutionConfig, EvolutionInputs, MilestoneHash};
    let (_, composer) = targets();
    let ComposerInputs::Song(mut song) = authored_song() else {
        panic!("fixture");
    };
    song.arrangement.channel_count = 1;
    let x = ComposerInputs::Song(song);
    let config = EvolutionConfig {
        first_milestone_age: 10,
        initial_unlock_bps: 5000,
        unlock_step_bps: 0,
        max_extra_channels: 3,
        max_tempo_delta_bpm: 2,
        max_velocity_delta: 8,
        ornament_chance_bps: 1000,
    };
    let (a, b) = unlock_witness(config);
    let one = array![MilestoneHash { block_number: 110, block_hash: a }];
    let early = composer
        .compose_staff(
            x,
            0,
            config,
            EvolutionInputs {
                birth_block: 100,
                staff_block: 110,
                drift_group: 9,
                staff_hash: 123,
                milestones: one.span(),
            },
        );
    let two = array![
        MilestoneHash { block_number: 110, block_hash: a },
        MilestoneHash { block_number: 120, block_hash: b }
    ];
    let later = composer
        .compose_staff(
            x,
            3,
            config,
            EvolutionInputs {
                birth_block: 100,
                staff_block: 120,
                drift_group: 9,
                staff_hash: 456,
                milestones: two.span(),
            },
        );
    assert_sound(@early);
    assert_sound(@later);
    let earlier_roles = midi_role_mask(@early);
    let later_roles = midi_role_mask(@later);
    assert(earlier_roles & later_roles == earlier_roles, 'emitted role permanence');
    assert(earlier_roles != later_roles, 'new structural role audible');
    assert(early.midi != later.midi, 'new staff interpretation');
}

fn rich_song() -> beast_composer::inputs::SongInputs {
    let wire = array![
        4, 1, 2, 2, 1, 4, 60, 3, 2, 4, 3, 2, 1, 1, 3, 0, 109, 500000, 47, 1, 1, 2, 0, 1, 2, 0, 0, 1,
        37, 6, 1, 17, 0, 1, 0, 1
    ];
    let ComposerInputs::Song(x) = beast_composer::inputs::decode_inputs(wire.span()) else {
        panic!("fixture");
    };
    x
}
fn assert_changed(
    composer: IBeastPureComposerLibraryDispatcher,
    base: @TinySynthSound,
    song: beast_composer::inputs::SongInputs,
) {
    let changed = composer.compose(ComposerInputs::Song(song), 0);
    assert_sound(@changed);
    assert(PartialEq::ne(@changed.midi, @base.midi), 'authored arrangement discarded');
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_arrangement_family_topline_and_mix_are_consumed() {
    let (_, composer) = targets();
    let x = rich_song();
    let base = composer.compose(ComposerInputs::Song(x), 0);
    assert_sound(@base);
    let mut family = x;
    family.arrangement.family = 2;
    assert_changed(composer, @base, family);
    let mut top = x;
    top.arrangement.top_lead = false;
    assert_changed(composer, @base, top);
    let mut mix = x;
    mix.arrangement.balanced = true;
    assert_changed(composer, @base, mix);
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_channel_policy_count_and_weak_ties_are_consumed() {
    use beast_composer::inputs::ChannelPolicy;
    let (_, composer) = targets();
    let x = rich_song();
    let base = composer.compose(ComposerInputs::Song(x), 0);
    assert_sound(@base);
    let mut ties = x;
    ties.arrangement.weak_ties = false;
    assert_changed(composer, @base, ties);
    let mut sparse = x;
    sparse.arrangement.channel_count = 3;
    assert_changed(composer, @base, sparse);
    let seeded = composer.compose(ComposerInputs::Song(sparse), 0);
    sparse.arrangement.channel_policy = ChannelPolicy::Genesis;
    assert_changed(composer, @seeded, sparse);
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_special_yeti_identity_and_other_family_settings_are_consumed() {
    use beast_composer::inputs::SpecialArrangement;
    let (_, composer) = targets();
    let mut x = rich_song();
    x.arrangement.family = 1;
    let base = composer.compose(ComposerInputs::Song(x), 0);
    x.arrangement.special = SpecialArrangement::Yeti(9);
    assert_changed(composer, @base, x);
    let named = composer.compose(ComposerInputs::Song(x), 0);
    assert_sound(@named);
    assert(has_timbre(@named, false, 13), 'cross family avalanche settings');
    x.arrangement.special = SpecialArrangement::Yeti(1242);
    assert_changed(composer, @named, x);
}
fn boundary_modes(modes: Span<u8>, tonic: u8) {
    let (_, composer) = targets();
    let mut x = rich_song();
    x.arrangement.identity.source_species_id = 0xffffffffffffffff;
    x.arrangement.identity.name_variant_id = 1242;
    x.score.tonic_keynum = tonic;
    for mode in modes {
        x.score.mode_id = *mode;
        let sound = composer.compose(ComposerInputs::Song(x), 3);
        assert_sound(@sound);
    }
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_low_tonic_modal_and_u64_identity_bounds() {
    boundary_modes(array![4_u8, 5, 6].span(), 24);
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_high_tonic_modal_and_mega_pitch_bounds() {
    boundary_modes(array![7_u8, 8, 26].span(), 96);
}

fn production_targets() -> (
    IBeastPureGeneratorLibraryDispatcher, IBeastPureComposerLibraryDispatcher,
) {
    let generator = snforge_std::declare_from_file(
        "../../target/dev/beast_contracts_BeastPureGenerator.contract_class.json",
    )
        .unwrap()
        .contract_class()
        .class_hash;
    let composer = snforge_std::declare_from_file(
        "../../target/dev/beast_contracts_BeastPureComposer.contract_class.json",
    )
        .unwrap()
        .contract_class()
        .class_hash;
    let generator_felt: felt252 = generator.into();
    let composer_felt: felt252 = composer.into();
    println!("PURE_SAMPLE_TARGETS generator={} composer={}", generator_felt, composer_felt);
    (
        IBeastPureGeneratorLibraryDispatcher { class_hash: generator },
        IBeastPureComposerLibraryDispatcher { class_hash: composer },
    )
}
fn emit_sample(name: ByteArray, inputs: ComposerInputs, sound: @TinySynthSound) {
    assert_sound(sound);
    let mut serial = array![];
    Serde::serialize(sound, ref serial);
    println!(
        "PURE_SAMPLE name={} recipe={:?} sound={:?}",
        name,
        beast_composer::inputs::encode_inputs(inputs).span(),
        serial.span()
    );
}
// Explicit offline evidence capture only; no account/RPC/deployment access.
// One rendition per test keeps serialization/printing below the normal1Bgas cap.
fn sample_original(code: u8) {
    let (generator, composer) = production_targets();
    let base = generator
        .get_generation_inputs(
            EditionCompositionConfig { composition_seed: 9 },
            2,
            BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 },
        );
    let inputs = generator.generate_inputs(base, 2);
    let sound = composer.compose(inputs, code);
    let name = match code {
        0 => "original",
        1 => "preset1",
        2 => "preset2",
        _ => "preset3",
    };
    emit_sample(name, inputs, @sound);
}
#[test]
#[ignore]
#[available_gas(1000000000)]
fn actual_sound_sample_original() {
    sample_original(0);
}
#[test]
#[ignore]
#[available_gas(1000000000)]
fn actual_sound_sample_preset1() {
    sample_original(1);
}
#[test]
#[ignore]
#[available_gas(1000000000)]
fn actual_sound_sample_preset2() {
    sample_original(2);
}
#[test]
#[ignore]
#[available_gas(1000000000)]
fn actual_sound_sample_preset3() {
    sample_original(3);
}
fn sample_staff(index: u8) {
    use beast_composer::inputs::evolution::{EvolutionConfig, EvolutionInputs, MilestoneHash};
    let (generator, composer) = production_targets();
    let base = generator
        .get_generation_inputs(
            EditionCompositionConfig { composition_seed: 9 },
            2,
            BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 },
        );
    let inputs = generator.generate_inputs(base, 2);
    let config = EvolutionConfig {
        first_milestone_age: 10,
        initial_unlock_bps: 5000,
        unlock_step_bps: 0,
        max_extra_channels: 3,
        max_tempo_delta_bpm: 2,
        max_velocity_delta: 8,
        ornament_chance_bps: 1000,
    };
    let (a, b) = unlock_witness(config);
    let mut milestones = array![];
    if index >= 1 {
        milestones.append(MilestoneHash { block_number: 110, block_hash: a });
    }
    if index >= 2 {
        milestones.append(MilestoneHash { block_number: 120, block_hash: b });
    }
    let (name, staff_block, staff_hash) = match index {
        0 => ("early-live", 109_u64, 123_felt252),
        1 => ("post-unlock", 110, 999),
        _ => ("later-live", 120, 456),
    };
    let sound = composer
        .compose_staff(
            inputs,
            0,
            config,
            EvolutionInputs {
                birth_block: 100,
                staff_block,
                drift_group: 9,
                staff_hash,
                milestones: milestones.span(),
            },
        );
    emit_sample(name, inputs, @sound);
    println!("PURE_SAMPLE_CONTEXT first_hash={} second_hash={}", a, b);
}
#[test]
#[ignore]
#[available_gas(1000000000)]
fn actual_sound_sample_early_live() {
    sample_staff(0);
}
#[test]
#[ignore]
#[available_gas(1000000000)]
fn actual_sound_sample_post_unlock() {
    sample_staff(1);
}
#[test]
#[ignore]
#[available_gas(1000000000)]
fn actual_sound_sample_later_live() {
    sample_staff(2);
}

#[test]
#[available_gas(1000000000)]
fn test_actual_pure_repeat_purchase_and_adjacent_edition_outputs() {
    let (generator, composer) = targets();
    let config = EditionCompositionConfig { composition_seed: 9 };
    let identity = BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 };
    let base = generator.get_generation_inputs(config, 2, identity);
    // Exact manager purchase_seed domain/order, same manager/token/hash and
    // purchase block, differing only the append ID. No global deduplication.
    let first_seed = core::poseidon::poseidon_hash_span(
        array!['beasts_sound_purchase_v1', 1234, 5678, 1, 777].span(),
    );
    let second_seed = core::poseidon::poseidon_hash_span(
        array!['beasts_sound_purchase_v1', 1234, 5678, 2, 777].span(),
    );
    assert(first_seed != second_seed, 'same block append entropy');
    let first = generator.generate_inputs(base, first_seed);
    let second = generator.generate_inputs(base, second_seed);
    assert(first != second, 'distinct fixed sample recipes');
    let first_sound = composer.compose(first, 0);
    let second_sound = composer.compose(second, 0);
    assert_sound(@first_sound);
    assert_sound(@second_sound);
    assert(first_sound.midi != second_sound.midi, 'distinct actual purchase music');
    let next_base = generator.get_generation_inputs(config, 3, identity);
    assert(next_base.base_song.theme != base.base_song.theme, 'adjacent edition template');
    let next = generator.generate_inputs(next_base, first_seed);
    let next_sound = composer.compose(next, 0);
    assert_sound(@next_sound);
    assert(next_sound.midi != first_sound.midi, 'adjacent edition actual music');
}

// Conservative order-independent note-on/off multiset. Ignores channel IDs,
// velocity, tempo, program changes, pan, volume and all non-note metadata.
fn structural_note_fingerprint(sound: @TinySynthSound) -> felt252 {
    let bytes = @sound.midi;
    let mut digest: felt252 = 0;
    let mut chunk: u32 = 14;
    while chunk < bytes.len() {
        let end = chunk + 8 + be32(bytes, chunk + 4);
        let mut at = chunk + 8;
        let mut time: u32 = 0;
        let mut running: u8 = 0;
        while at < end {
            let (next, delta) = vlq(bytes, at);
            at = next;
            time += delta;
            let first = bytes.at(at).unwrap();
            let status = if first >= 128 {
                at += 1;
                first
            } else {
                running
            };
            if status == 255 {
                at += 1;
                let (next, len) = vlq(bytes, at);
                at = next + len;
                running = 0;
                continue;
            }
            running = status;
            let kind = status / 16;
            let pitch = bytes.at(at).unwrap();
            at += 1;
            if kind != 12 && kind != 13 {
                let velocity = bytes.at(at).unwrap();
                at += 1;
                if kind == 8 || kind == 9 {
                    let on: felt252 = if kind == 9 && velocity > 0 {
                        1
                    } else {
                        0
                    };
                    let drum: felt252 = if status % 16 == 9 {
                        1
                    } else {
                        0
                    };
                    digest +=
                        core::poseidon::poseidon_hash_span(
                            array![time.into(), pitch.into(), on, drum].span(),
                        );
                }
            }
        }
        chunk = end;
    }
    digest
}
#[test]
#[available_gas(1000000000)]
fn test_actual_pure_shape_separates_known_audible_collision_without_dynamics() {
    let (generator, composer) = targets();
    let base = generator
        .get_generation_inputs(
            EditionCompositionConfig { composition_seed: 9 },
            2,
            BeastMusicalIdentity { species_id: 21, name_variant_id: 37, tier: 5, family: 0 },
        );
    let a = core::poseidon::poseidon_hash_span(
        array!['beasts_sound_purchase_v1', 1234, 5678, 3, 777].span(),
    );
    let b = core::poseidon::poseidon_hash_span(
        array!['beasts_sound_purchase_v1', 1234, 5678, 122, 777].span(),
    );
    // At5045 these exact purchased samples have byte-identical3309-byte MIDI
    // (SHA2564f3aab70a2d6a2367848c8f5661778c3661a50b38b202369ff853bd4d3b5f304).
    let x = generator.generate_inputs(base, a);
    let y = generator.generate_inputs(base, b);
    let ComposerInputs::Song(xs) = x else {
        panic!("fixture");
    };
    let ComposerInputs::Song(ys) = y else {
        panic!("fixture");
    };
    assert(
        xs.theme == ys.theme
            && xs.score.tonic_keynum == ys.score.tonic_keynum
            && xs.score.mode_id == ys.score.mode_id
            && xs.arrangement.identity == ys.arrangement.identity,
        'shared edition identity',
    );
    let first = composer.compose(x, 0);
    let second = composer.compose(y, 0);
    assert_sound(@first);
    assert_sound(@second);
    assert(
        structural_note_fingerprint(@first) != structural_note_fingerprint(@second),
        'audible shape distinction',
    );
}

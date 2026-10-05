use crate::composition::beast_score::{
    build_beast_theme, derive_beast_sound_seeds, note_events_valid,
};
use crate::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, beast_has_sound, beast_sound_seed, build_v3_beast_form,
    decode_v3_token_id, encode_v3_token_id, genesis_token_id, map_v3_beast_to_composition_params,
    standalone_sound_seed, type_tier_family, v3_music_state_hash, v3_name_variant_id,
    v3_params_hash, v3_rank_tier, v3_score_full_midi, v3_score_full_smf_bytes,
    v3_score_instructions, v3_score_midi, v3_score_notes, v3_score_smf_bytes,
};

// "Sorrow Peak Warlock": live mainnet rank-1 Warlock (legacy token #52918).
fn sorrow_peak_warlock() -> PackableBeastV3 {
    PackableBeastV3 {
        id: 1,
        prefix: 57,
        suffix: 15,
        level: 126,
        health: 229,
        shiny: 0,
        animated: 0,
        tier: 1,
        beast_type: 0,
    }
}

fn calm() -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954,
    }
}

fn veteran() -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: 40, scars: 9, summit_held_seconds: 90000, rank: 1, species_count: 954,
    }
}

#[test]
fn v3_token_id_round_trips() {
    let b = sorrow_peak_warlock();
    let decoded = decode_v3_token_id(encode_v3_token_id(b));
    assert(decoded == b, 'round trip');
}

#[test]
#[should_panic(expected: ('invalid affix combo',))]
fn v3_rejects_mixed_zero_affix() {
    let mut b = sorrow_peak_warlock();
    b.suffix = 0;
    decode_v3_token_id(encode_v3_token_id(b));
}

#[test]
fn v3_name_variant_matches_vault_encoding() {
    assert(v3_name_variant_id(0, 0) == 0, 'genesis');
    assert(v3_name_variant_id(1, 1) == 1, 'first');
    assert(v3_name_variant_id(1, 18) == 18, 'first row end');
    assert(v3_name_variant_id(2, 1) == 19, 'second row');
    assert(v3_name_variant_id(69, 18) == 1242, 'last');
}

#[test]
fn v3_every_type_tier_family_resolves() {
    let mut t: u8 = 0;
    while t < 3 {
        let mut tier: u8 = 1;
        while tier <= 5 {
            let f = type_tier_family(t, tier);
            assert(f.base_voice_count >= 1 && f.base_voice_count <= 3, 'voices');
            tier += 1;
        }
        t += 1;
    }
}

#[test]
fn v3_rank_tier_is_relative_to_species() {
    assert(v3_rank_tier(1, 954) == 0, 'crown');
    assert(v3_rank_tier(0, 954) == 1, 'genesis');
    assert(v3_rank_tier(9, 954) == 1, 'top 1%');
    assert(v3_rank_tier(40, 954) == 2, 'top 5%');
    assert(v3_rank_tier(150, 954) == 3, 'top 20%');
    assert(v3_rank_tier(954, 954) == 4, 'tail');
}

#[test]
fn v3_living_state_keeps_motif_but_changes_form() {
    let b = sorrow_peak_warlock();
    let p_calm = map_v3_beast_to_composition_params(b, calm());
    let p_vet = map_v3_beast_to_composition_params(b, veteran());
    let seeds = derive_beast_sound_seeds(beast_sound_seed(b.id, b.prefix, b.suffix));
    assert(
        build_beast_theme(p_calm, seeds.motif_seed)
            .theme_hash == build_beast_theme(p_vet, seeds.motif_seed)
            .theme_hash,
        'motif stable',
    );
    assert(p_vet.section_count > p_calm.section_count, 'kills add sections');
    assert(p_vet.stretto_lag < p_calm.stretto_lag, 'kills tighten stretto');
    assert(v3_music_state_hash(b, calm()) != v3_music_state_hash(b, veteran()), 'state hash');
}

#[test]
fn v3_genesis_always_has_sound() {
    let g = PackableBeastV3 {
        id: 29,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 1,
        animated: 1,
        tier: 1,
        beast_type: 1,
    };
    assert(beast_has_sound('salt', 0, g), 'genesis sound');
    assert(!beast_has_sound('salt', 0, sorrow_peak_warlock()), 'zero bps');
    assert(beast_has_sound('salt', 10000, sorrow_peak_warlock()), 'full bps');
}

#[test]
fn v3_community_species_render() {
    // Species 76 is the first community id; only type/tier/name/affixes are known.
    let b = PackableBeastV3 {
        id: 76,
        prefix: 12,
        suffix: 4,
        level: 30,
        health: 80,
        shiny: 1,
        animated: 0,
        tier: 3,
        beast_type: 2,
    };
    let form = build_v3_beast_form(b, calm());
    assert(note_events_valid(form.events.span()), 'valid events');
}

#[test]
fn v3_genesis_token_id_matches_sepolia_deployment() {
    // Warlock Genesis Beast as minted by the Beasts V3 Sepolia constructor.
    assert(genesis_token_id(1, 1, 0) == 0x7006400010000000000000000001, 'warlock genesis');
}

#[test]
fn v3_agony_bane_gloomfang_matches_sepolia_token() {
    // First community dungeon mint on Sepolia: species 76, Hunter, Tier 3.
    let b = PackableBeastV3 {
        id: 76,
        prefix: 1,
        suffix: 1,
        level: 10,
        health: 100,
        shiny: 0,
        animated: 1,
        tier: 3,
        beast_type: 1,
    };
    assert(encode_v3_token_id(b) == 0x2e0064000a081000000000000004c, 'gloomfang token');
}

#[test]
fn v3_standalone_seed_differs_from_v3_seed() {
    assert(standalone_sound_seed('BLACK_SHUCK', 1, 0, 0) != beast_sound_seed(1, 0, 0), 'domain');
}

#[test]
fn v3_summit_scars_trigger_inversion_and_glory() {
    let b = sorrow_peak_warlock();
    let scarred = BeastV3LiveState {
        adventurers_killed: 2, scars: 25, summit_held_seconds: 0, rank: 1, species_count: 954,
    };
    let glorious = BeastV3LiveState {
        adventurers_killed: 2,
        scars: 0,
        summit_held_seconds: 20 * 3600,
        rank: 1,
        species_count: 954,
    };
    let fresh = BeastV3LiveState {
        adventurers_killed: 2, scars: 0, summit_held_seconds: 0, rank: 1, species_count: 954,
    };
    assert(map_v3_beast_to_composition_params(b, scarred).use_inversion, 'scars invert');
    assert(
        build_v3_beast_form(b, scarred).score_hash != build_v3_beast_form(b, fresh).score_hash,
        'inversion changes score hash',
    );
    let d_fresh = map_v3_beast_to_composition_params(b, fresh).ornament_density;
    let d_glory = map_v3_beast_to_composition_params(b, glorious).ornament_density;
    assert(d_glory == d_fresh + 1 || d_fresh == 7, 'summit glory');
}

#[test]
fn v3_score_midi_is_a_standard_midi_file() {
    let midi = v3_score_midi(sorrow_peak_warlock(), calm());
    let len: u32 = (*midi.at(0)).try_into().unwrap();
    assert(len > 100, 'midi length');
    assert(midi.len() == 1 + (len + 30) / 31, 'packing');
    // First felt starts with "MThd" + chunk length 6 + format 1.
    let first: u256 = (*midi.at(1)).into();
    let shift: u256 = 0x1000000000000000000000000000000000000000000; // 2^(8*(31-10))
    assert(first / shift == 0x4D546864000000060001, 'smf header');
}

#[test]
fn v3_score_full_smf_adds_setup_and_drums() {
    let b = sorrow_peak_warlock();
    let bare = v3_score_smf_bytes(b, calm());
    let full = v3_score_full_smf_bytes(b, calm());
    assert(full.len() > bare.len(), 'full not larger');
    // Same header except the track count: one more track (the drums on channel 10).
    let mut i: u32 = 0;
    while i < 11 {
        assert(*full.at(i) == *bare.at(i), 'header');
        i += 1;
    }
    assert(*full.at(11) == *bare.at(11) + 1, 'drum track');
    // The first voice track opens with a program change and CC10 pan at tick 0.
    let tempo_trk_len: u32 = (*full.at(18)).into() * 0x1000000
        + (*full.at(19)).into() * 0x10000
        + (*full.at(20)).into() * 0x100
        + (*full.at(21)).into();
    let v = 22 + tempo_trk_len + 8;
    assert(*full.at(v) == 0 && *full.at(v + 1) & 0xf0 == 0xc0, 'program change');
    assert(*full.at(v + 3) == 0 && *full.at(v + 4) & 0xf0 == 0xb0, 'cc');
    assert(*full.at(v + 5) == 10, 'pan');
    // A note-on on channel 10 somewhere in the file.
    let mut found = false;
    let mut j: u32 = 0;
    while j < full.len() {
        if *full.at(j) == 0x99 {
            found = true;
            break;
        }
        j += 1;
    }
    assert(found, 'no drums');
}

#[test]
fn v3_score_notes_is_much_smaller_than_midi() {
    let b = sorrow_peak_warlock();
    let live = veteran();
    let midi = v3_score_midi(b, live);
    let notes = v3_score_notes(b, live);
    let midi_len: u32 = (*midi.at(0)).try_into().unwrap();
    let notes_len: u32 = (*notes.at(0)).try_into().unwrap();
    // 320 notes: 81 header bits + runs * 24 + 320 * 7 bits.
    assert(notes_len * 6 < midi_len, 'bsn not compact');
    assert(notes.len() == 1 + (notes_len + 30) / 31, 'bsn packing');
}

/// Parity fixture: prints the canonical values the browser engine must reproduce.
/// Run: scarb test -- --include-ignored --filter beast_v3_parity_fixture
#[test]
#[ignore]
fn beast_v3_parity_fixture() {
    let cases: Array<(PackableBeastV3, BeastV3LiveState)> = array![
        (sorrow_peak_warlock(), calm()),
        (sorrow_peak_warlock(), veteran()),
        (
            PackableBeastV3 {
                id: 29,
                prefix: 0,
                suffix: 0,
                level: 1,
                health: 100,
                shiny: 1,
                animated: 1,
                tier: 1,
                beast_type: 1,
            },
            BeastV3LiveState {
                adventurers_killed: 3,
                scars: 0,
                summit_held_seconds: 0,
                rank: 0,
                species_count: 1200,
            },
        ),
        (
            PackableBeastV3 {
                id: 47,
                prefix: 13,
                suffix: 6,
                level: 22,
                health: 60,
                shiny: 0,
                animated: 1,
                tier: 5,
                beast_type: 1,
            },
            BeastV3LiveState {
                adventurers_killed: 1,
                scars: 4,
                summit_held_seconds: 7200,
                rank: 300,
                species_count: 1100,
            },
        ),
        (
            PackableBeastV3 {
                id: 76,
                prefix: 12,
                suffix: 4,
                level: 30,
                health: 80,
                shiny: 1,
                animated: 0,
                tier: 3,
                beast_type: 2,
            },
            BeastV3LiveState {
                adventurers_killed: 100,
                scars: 20,
                summit_held_seconds: 1642000,
                rank: 2,
                species_count: 40,
            },
        ),
    ];
    let mut i: u32 = 0;
    while i < cases.len() {
        let (b, live) = *cases.at(i);
        let form = build_v3_beast_form(b, live);
        let mut checksum: u64 = 0;
        let mut j: u32 = 0;
        while j < form.events.len() {
            let e = *form.events.at(j);
            let term: u64 = (e.time.into() * 31
                + e.duration.into() * 7
                + e.pitch.into() * 131
                + e.velocity.into() * 17
                + e.voice_id.into()
                + 1)
                * (j.into() + 1);
            checksum = (checksum + term) % 1000000007;
            j += 1;
        }
        let midi = v3_score_midi(b, live);
        let midi_hash = core::poseidon::poseidon_hash_span(midi.span());
        let bsn = v3_score_notes(b, live);
        let bsn_hash = core::poseidon::poseidon_hash_span(bsn.span());
        let bsi = v3_score_instructions(b, live);
        let bsi_hash = core::poseidon::poseidon_hash_span(bsi.span());
        println!(
            "PARITY case={} seed={} params={} score={} state={} events={} checksum={} midi_len={} midi_hash={} bsn_len={} bsn_hash={} bsi_len={} bsi_hash={}",
            i,
            beast_sound_seed(b.id, b.prefix, b.suffix),
            v3_params_hash(b, live),
            form.score_hash,
            v3_music_state_hash(b, live),
            form.events.len(),
            checksum,
            *midi.at(0),
            midi_hash,
            *bsn.at(0),
            bsn_hash,
            bsi.len(),
            bsi_hash,
        );
        i += 1;
    }
}

/// Full-MIDI parity fixture: the self-contained file (programs, pan, drums) for Beasts covering
/// every tier's fill and 1 to 5 voices. Compared with offchain/beast-sound/src/full_midi.js by
/// scripts/full_midi_parity.mjs.
/// Run: scarb test -- --include-ignored --filter full_midi_parity_fixture
#[test]
#[ignore]
fn full_midi_parity_fixture() {
    let cases: Array<(PackableBeastV3, BeastV3LiveState)> = array![
        (sorrow_peak_warlock(), calm()),
        (sorrow_peak_warlock(), veteran()),
        (
            PackableBeastV3 {
                id: 6,
                prefix: 10,
                suffix: 3,
                level: 40,
                health: 300,
                shiny: 0,
                animated: 0,
                tier: 2,
                beast_type: 0,
            },
            BeastV3LiveState {
                adventurers_killed: 20,
                scars: 2,
                summit_held_seconds: 0,
                rank: 4,
                species_count: 300,
            },
        ),
        (
            PackableBeastV3 {
                id: 11,
                prefix: 30,
                suffix: 9,
                level: 70,
                health: 120,
                shiny: 1,
                animated: 0,
                tier: 3,
                beast_type: 0,
            },
            BeastV3LiveState {
                adventurers_killed: 5,
                scars: 9,
                summit_held_seconds: 0,
                rank: 50,
                species_count: 900,
            },
        ),
        (
            PackableBeastV3 {
                id: 16,
                prefix: 44,
                suffix: 12,
                level: 12,
                health: 80,
                shiny: 0,
                animated: 1,
                tier: 4,
                beast_type: 0,
            },
            BeastV3LiveState {
                adventurers_killed: 1, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 0,
            },
        ),
        (
            PackableBeastV3 {
                id: 21,
                prefix: 0,
                suffix: 0,
                level: 3,
                health: 40,
                shiny: 0,
                animated: 0,
                tier: 5,
                beast_type: 0,
            },
            BeastV3LiveState {
                adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 0,
            },
        ),
        (
            PackableBeastV3 {
                id: 53,
                prefix: 69,
                suffix: 18,
                level: 255,
                health: 1023,
                shiny: 1,
                animated: 1,
                tier: 1,
                beast_type: 2,
            },
            BeastV3LiveState {
                adventurers_killed: 500,
                scars: 63,
                summit_held_seconds: 0,
                rank: 1,
                species_count: 1243,
            },
        ),
    ];
    let mut i: u32 = 0;
    while i < cases.len() {
        let (b, live) = *cases.at(i);
        let midi = crate::composition::beast_v3_sound::v3_score_full_midi(b, live);
        println!(
            "FULL case={} len={} hash={}",
            i,
            *midi.at(0),
            core::poseidon::poseidon_hash_span(midi.span()),
        );
        i += 1;
    }
}

/// Every byte both SMF writers produce, pinned: 50 Beasts (every third species, tiers, types and
/// rarity flags varied) in two live states, bare and self-contained. Guards refactors of the
/// writers (the `midi` package) and the composer.
#[test]
#[ignore]
#[available_gas(100000000000)]
fn smf_golden() {
    let mut acc: Array<felt252> = array![];
    let mut id: u64 = 1;
    while id <= 75 {
        let named = id % 4 != 0; // every fourth unnamed (no prefix or suffix)
        let b = PackableBeastV3 {
            id,
            prefix: if named {
                (id % 69 + 1).try_into().unwrap()
            } else {
                0
            },
            suffix: if named {
                (id % 18 + 1).try_into().unwrap()
            } else {
                0
            },
            level: (id * 3).try_into().unwrap(),
            health: (id * 13).try_into().unwrap(),
            shiny: (id % 2).try_into().unwrap(),
            animated: if id % 3 == 1 {
                1
            } else {
                0
            },
            tier: (((id - 1) / 5) % 5 + 1).try_into().unwrap(),
            beast_type: (((id - 1) / 25) % 3).try_into().unwrap(),
        };
        for live in array![calm(), veteran()] {
            acc.append(core::poseidon::poseidon_hash_span(v3_score_midi(b, live).span()));
            acc.append(core::poseidon::poseidon_hash_span(v3_score_full_midi(b, live).span()));
        }
        id += 3;
    }
    assert_eq!(acc.len(), 100);
    assert_eq!(
        core::poseidon::poseidon_hash_span(acc.span()),
        3137908298401046002331382199627435306166740134066761377290858018804337104822,
    );
}

/// v1.1 parity cases, mirrored in scripts/v11_parity.mjs: every species, its live state rotating
/// through six that reach every history branch (calm; kills ahead; defeats ahead; heavy; even with
/// no species count; a four-section sequence), names, level, health and rarity flags varied.
fn v11_case(id: u64) -> (PackableBeastV3, BeastV3LiveState) {
    let named = id % 3 != 0;
    let levels: Array<u16> = array![5, 40, 120, 255];
    let healths: Array<u16> = array![80, 150, 600, 1023];
    let b = PackableBeastV3 {
        id,
        prefix: if named {
            (id % 69 + 1).try_into().unwrap()
        } else {
            0
        },
        suffix: if named {
            (id % 18 + 1).try_into().unwrap()
        } else {
            0
        },
        level: *levels.at((id % 4).try_into().unwrap()),
        health: *healths.at(((id / 3) % 4).try_into().unwrap()),
        shiny: (id % 2).try_into().unwrap(),
        animated: ((id / 5) % 2).try_into().unwrap(),
        tier: (((id - 1) % 25) / 5 + 1).try_into().unwrap(),
        beast_type: ((id - 1) / 25).try_into().unwrap(),
    };
    let k = id % 6;
    let live = if k == 0 {
        BeastV3LiveState {
            adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954,
        }
    } else if k == 1 {
        BeastV3LiveState {
            adventurers_killed: 40, scars: 9, summit_held_seconds: 0, rank: 1, species_count: 954,
        }
    } else if k == 2 {
        BeastV3LiveState {
            adventurers_killed: 3, scars: 30, summit_held_seconds: 0, rank: 50, species_count: 954,
        }
    } else if k == 3 {
        BeastV3LiveState {
            adventurers_killed: 500,
            scars: 63,
            summit_held_seconds: 0,
            rank: 0,
            species_count: 1243,
        }
    } else if k == 4 {
        BeastV3LiveState {
            adventurers_killed: 7, scars: 7, summit_held_seconds: 0, rank: 2, species_count: 0,
        }
    } else {
        BeastV3LiveState {
            adventurers_killed: 8, scars: 20, summit_held_seconds: 0, rank: 10, species_count: 954,
        }
    };
    (b, live)
}

/// Prints the V11 lines for cases `lo..=hi`. One Cairo VM run keeps everything it allocates until
/// it ends, so the fixture runs in batches of 4 (about 3 GB each; 75 cases in one run needed about
/// 41 GB).
fn v11_parity_range(lo: u64, hi: u64) {
    let mut id: u64 = lo;
    while id <= hi {
        let (b, live) = v11_case(id);
        let score = crate::composition::beast_v11::build_v11_score(b, live);
        // voice by voice (each voice is chronological), so the hash does not depend on how voices
        // interleave
        let mut max_voice: u32 = 0;
        for e in score.events.span() {
            if e.voice_id > max_voice {
                max_voice = e.voice_id;
            }
        }
        let mut flat: Array<felt252> = array![];
        let mut v: u32 = 0;
        while v <= max_voice {
            for e in score.events.span() {
                if e.voice_id == v {
                    flat.append(e.time.into());
                    flat.append(e.duration.into());
                    flat.append(e.pitch.into());
                    flat.append(e.velocity.into());
                    flat.append(e.voice_id.into());
                }
            }
            v += 1;
        }
        let midi = crate::composition::beast_v11::v11_score_full_midi(b, live);
        println!(
            "V11 case={} notes={} ticks={} events={} midi_len={} midi={}",
            id,
            score.events.len(),
            score.section_ticks,
            core::poseidon::poseidon_hash_span(flat.span()),
            *midi.at(0),
            core::poseidon::poseidon_hash_span(midi.span()),
        );
        id += 1;
    }
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_00() {
    v11_parity_range(1, 4);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_01() {
    v11_parity_range(5, 8);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_02() {
    v11_parity_range(9, 12);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_03() {
    v11_parity_range(13, 16);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_04() {
    v11_parity_range(17, 20);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_05() {
    v11_parity_range(21, 24);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_06() {
    v11_parity_range(25, 28);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_07() {
    v11_parity_range(29, 32);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_08() {
    v11_parity_range(33, 36);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_09() {
    v11_parity_range(37, 40);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_10() {
    v11_parity_range(41, 44);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_11() {
    v11_parity_range(45, 48);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_12() {
    v11_parity_range(49, 52);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_13() {
    v11_parity_range(53, 56);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_14() {
    v11_parity_range(57, 60);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_15() {
    v11_parity_range(61, 64);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_16() {
    v11_parity_range(65, 68);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_17() {
    v11_parity_range(69, 72);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn v11_parity_fixture_18() {
    v11_parity_range(73, 75);
}

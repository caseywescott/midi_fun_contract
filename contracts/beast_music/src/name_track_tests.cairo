//! Name-track parity fixture: the Beast Special Song (track 2) of two special names per species,
//! one normal and one shiny, composed from the packed composer inputs (`tracks::track_midi`), as
//! hashes that scripts/name_parity.mjs compares with the lab's `sampleTrackMidi` at that name, seed
//! 0.
//! Ignored (heavy): run in batches with scripts/genesis_parity_cairo.sh
//! (FIXTURE=name_parity_fixture_).
use crate::composition::beast_v3_sound::{BeastV3LiveState, PackableBeastV3};
use crate::composition::genesis::{species_tier, species_type};
use crate::composition::params_pack::{composer_inputs, pack_inputs};
use crate::composition::tracks::{TRACK_SPECIAL_SONG, track_midi};

/// Special name k (0 or 1) of species `id` as a name variant 1..=1242.
fn name_of(id: u64, k: u64) -> u32 {
    (1 + (id * 37 + k * 611) % 1242).try_into().unwrap()
}

fn name_parity_range(lo: u64, hi: u64) {
    let live = BeastV3LiveState {
        adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1,
    };
    let mut id: u64 = lo;
    while id <= hi {
        let mut k: u64 = 0;
        while k <= 1 {
            let nv = name_of(id, k);
            let b = PackableBeastV3 {
                id,
                prefix: ((nv - 1) / 18 + 1).try_into().unwrap(),
                suffix: ((nv - 1) % 18 + 1).try_into().unwrap(),
                level: 1,
                health: 100,
                shiny: k.try_into().unwrap(),
                animated: 0,
                tier: species_tier(id),
                beast_type: species_type(id),
            };
            let midi = track_midi(pack_inputs(composer_inputs(b, live)), TRACK_SPECIAL_SONG);
            println!(
                "NAME case={} name={} shiny={} midi_len={} midi={}",
                id,
                nv,
                k,
                *midi.at(0),
                core::poseidon::poseidon_hash_span(midi.span()),
            );
            k += 1;
        }
        id += 1;
    }
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_00() {
    name_parity_range(1, 4);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_01() {
    name_parity_range(5, 8);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_02() {
    name_parity_range(9, 12);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_03() {
    name_parity_range(13, 16);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_04() {
    name_parity_range(17, 20);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_05() {
    name_parity_range(21, 24);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_06() {
    name_parity_range(25, 28);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_07() {
    name_parity_range(29, 32);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_08() {
    name_parity_range(33, 36);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_09() {
    name_parity_range(37, 40);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_10() {
    name_parity_range(41, 44);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_11() {
    name_parity_range(45, 48);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_12() {
    name_parity_range(49, 52);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_13() {
    name_parity_range(53, 56);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_14() {
    name_parity_range(57, 60);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_15() {
    name_parity_range(61, 64);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_16() {
    name_parity_range(65, 68);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_17() {
    name_parity_range(69, 72);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn name_parity_fixture_18() {
    name_parity_range(73, 75);
}

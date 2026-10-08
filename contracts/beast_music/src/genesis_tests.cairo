//! Genesis parity fixture: the Genesis Track of every species, normal and shiny, as hashes that
//! scripts/genesis_parity.mjs compares with `genesisMidi` (offchain/beast-sound/src/lab.js).
//! Ignored (heavy): run in batches with scripts/genesis_parity_cairo.sh.
use crate::composition::beast_v3_sound::PackableBeastV3;
use crate::composition::genesis::{genesis_midi, species_tier, species_type};

fn genesis_parity_range(lo: u64, hi: u64) {
    let mut id: u64 = lo;
    while id <= hi {
        let mut shiny: u8 = 0;
        while shiny <= 1 {
            let b = PackableBeastV3 {
                id,
                prefix: 0,
                suffix: 0,
                level: 1,
                health: 100,
                shiny,
                animated: 0,
                tier: species_tier(id),
                beast_type: species_type(id),
            };
            let midi = genesis_midi(b);
            println!(
                "GEN case={} shiny={} midi_len={} midi={}",
                id,
                shiny,
                *midi.at(0),
                core::poseidon::poseidon_hash_span(midi.span()),
            );
            shiny += 1;
        }
        id += 1;
    }
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_00() {
    genesis_parity_range(1, 4);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_01() {
    genesis_parity_range(5, 8);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_02() {
    genesis_parity_range(9, 12);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_03() {
    genesis_parity_range(13, 16);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_04() {
    genesis_parity_range(17, 20);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_05() {
    genesis_parity_range(21, 24);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_06() {
    genesis_parity_range(25, 28);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_07() {
    genesis_parity_range(29, 32);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_08() {
    genesis_parity_range(33, 36);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_09() {
    genesis_parity_range(37, 40);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_10() {
    genesis_parity_range(41, 44);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_11() {
    genesis_parity_range(45, 48);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_12() {
    genesis_parity_range(49, 52);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_13() {
    genesis_parity_range(53, 56);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_14() {
    genesis_parity_range(57, 60);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_15() {
    genesis_parity_range(61, 64);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_16() {
    genesis_parity_range(65, 68);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_17() {
    genesis_parity_range(69, 72);
}

#[test]
#[ignore]
#[available_gas(1000000000000)]
fn genesis_parity_fixture_18() {
    genesis_parity_range(73, 75);
}

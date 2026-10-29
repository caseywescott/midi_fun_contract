//! Parity of the Monthly Track Editions port (composition/editions.cairo) with
//! offchain/beast-sound/src/editions.js: each `#[ignore]`d batch prints one ED line per case (the
//! whole file in hex); scripts/editions_parity.mjs composes the same cases in JS and compares.
//!   sh scripts/editions_parity_cairo.sh /tmp/ed.txt && node scripts/editions_parity.mjs
//!   /tmp/ed.txt
use crate::composition::editions::{edition_engine, edition_smf_bytes, hash32};

// from editions.js: hash32('TRACK', 1, 1, 'seed:1'), hash32('EDITION', 13), and the engines of
// editions 0-59 (ENGINE_LIST indices; 255 = the canon)
const HASH_TRACK: u32 = 4107909763;
const HASH_EDITION: u32 = 914946597;
const ENGINES: [u8; 60] = [
    255, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 5, 9, 12, 6, 7, 0, 11, 6, 9, 5, 2, 3, 7, 4, 0, 3,
    9, 2, 10, 8, 5, 6, 12, 9, 3, 6, 8, 7, 10, 5, 11, 6, 1, 2, 4, 6, 11, 8, 7, 5, 12, 6, 7, 2, 11, 5,
];

const HEX: [u8; 16] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
];

fn hex(bytes: Span<u8>) -> ByteArray {
    let mut out: ByteArray = "";
    for b in bytes {
        out.append_byte(*HEX.span().at((*b / 16).into()));
        out.append_byte(*HEX.span().at((*b % 16).into()));
    }
    out
}

/// The fixture's three cases of edition `e`: two species and seeds, the second shiny.
fn parity_edition(e: u32) {
    let cases: [(u32, bool, u64); 3] = [
        ((e * 7) % 75 + 1, false, e.into()), ((e * 13 + 5) % 75 + 1, true, (e + 100).into()),
        ((e * 29 + 40) % 75 + 1, e % 2 == 0, (e * 1000 + 7).into()),
    ];
    for c in cases.span() {
        let (sp, shiny, seed) = *c;
        let midi = edition_smf_bytes(sp, shiny, e, seed);
        println!(
            "ED e={} sp={} shiny={} seed={} len={} hex={}",
            e,
            sp,
            if shiny {
                1
            } else {
                0
            },
            seed,
            midi.len(),
            hex(midi.span()),
        );
    }
}

#[test]
fn hash32_matches_the_source() {
    // hash32('TRACK', 1, 1, 'seed:1') and hash32('EDITION', 13) in editions.js
    assert_eq!(hash32(@"TRACK|1|1|seed:1"), HASH_TRACK);
    assert_eq!(hash32(@"EDITION|13"), HASH_EDITION);
}

#[test]
fn the_calendar_matches_the_source() {
    let expected = ENGINES.span();
    let mut e: u32 = 0;
    for x in expected {
        assert_eq!(edition_engine(e), *x);
        e += 1;
    }
}

#[test]
#[ignore]
fn editions_parity_fixture_01() {
    parity_edition(1);
}

#[test]
#[ignore]
fn editions_parity_fixture_02() {
    parity_edition(2);
}

#[test]
#[ignore]
fn editions_parity_fixture_03() {
    parity_edition(3);
}

#[test]
#[ignore]
fn editions_parity_fixture_04() {
    parity_edition(4);
}

#[test]
#[ignore]
fn editions_parity_fixture_05() {
    parity_edition(5);
}

#[test]
#[ignore]
fn editions_parity_fixture_06() {
    parity_edition(6);
}

#[test]
#[ignore]
fn editions_parity_fixture_07() {
    parity_edition(7);
}

#[test]
#[ignore]
fn editions_parity_fixture_08() {
    parity_edition(8);
}

#[test]
#[ignore]
fn editions_parity_fixture_09() {
    parity_edition(9);
}

#[test]
#[ignore]
fn editions_parity_fixture_10() {
    parity_edition(10);
}

#[test]
#[ignore]
fn editions_parity_fixture_11() {
    parity_edition(11);
}

#[test]
#[ignore]
fn editions_parity_fixture_12() {
    parity_edition(12);
}

#[test]
#[ignore]
fn editions_parity_fixture_13() {
    parity_edition(13);
}

#[test]
#[ignore]
fn editions_parity_fixture_14() {
    parity_edition(14);
}

#[test]
#[ignore]
fn editions_parity_fixture_15() {
    parity_edition(15);
}

#[test]
#[ignore]
fn editions_parity_fixture_16() {
    parity_edition(16);
}

#[test]
#[ignore]
fn editions_parity_fixture_17() {
    parity_edition(17);
}

#[test]
#[ignore]
fn editions_parity_fixture_18() {
    parity_edition(18);
}

#[test]
#[ignore]
fn editions_parity_fixture_19() {
    parity_edition(19);
}

#[test]
#[ignore]
fn editions_parity_fixture_20() {
    parity_edition(20);
}

#[test]
#[ignore]
fn editions_parity_fixture_21() {
    parity_edition(21);
}

#[test]
#[ignore]
fn editions_parity_fixture_22() {
    parity_edition(22);
}

#[test]
#[ignore]
fn editions_parity_fixture_23() {
    parity_edition(23);
}

#[test]
#[ignore]
fn editions_parity_fixture_24() {
    parity_edition(24);
}

#[test]
#[ignore]
fn editions_parity_fixture_25() {
    parity_edition(25);
}

#[test]
#[ignore]
fn editions_parity_fixture_26() {
    parity_edition(26);
}

#[test]
#[ignore]
fn editions_parity_fixture_27() {
    parity_edition(27);
}

#[test]
#[ignore]
fn editions_parity_fixture_28() {
    parity_edition(28);
}

#[test]
#[ignore]
fn editions_parity_fixture_29() {
    parity_edition(29);
}

#[test]
#[ignore]
fn editions_parity_fixture_30() {
    parity_edition(30);
}

#[test]
#[ignore]
fn editions_parity_fixture_31() {
    parity_edition(31);
}

#[test]
#[ignore]
fn editions_parity_fixture_32() {
    parity_edition(32);
}

#[test]
#[ignore]
fn editions_parity_fixture_33() {
    parity_edition(33);
}

#[test]
#[ignore]
fn editions_parity_fixture_34() {
    parity_edition(34);
}

#[test]
#[ignore]
fn editions_parity_fixture_35() {
    parity_edition(35);
}

#[test]
#[ignore]
fn editions_parity_fixture_36() {
    parity_edition(36);
}

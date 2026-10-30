//! Parity of the Monthly Track Editions port (composition/editions.cairo) with
//! offchain/beast-sound/src/editions_lite.js: each `#[ignore]`d batch prints one ED line per case
//! (the whole file in hex); scripts/editions_parity.mjs composes the same cases in JS and compares.
//!   sh scripts/editions_parity_cairo.sh /tmp/ed.txt && node scripts/editions_parity.mjs
//!   /tmp/ed.txt
use crate::composition::editions::{edition_genome, edition_smf_bytes};

// from editions_lite.js: editionGenome(e).style for editions 1-8
const STYLES: [u32; 46] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 0, 1, 2, 3, 4,
    5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
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
fn the_calendar_cycles_the_four_styles() {
    let mut e: u32 = 1;
    for x in STYLES.span() {
        let (st, _, _) = edition_genome(e);
        assert_eq!(st, *x);
        e += 1;
    }
}

#[test]
#[should_panic(expected: ('editions: 0 is the canon',))]
fn edition_0_is_the_canon() {
    edition_genome(0);
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

/// Full-width purchase seeds (the generator passes a purchase hash's low 64 bits), one per style,
/// shiny and not: the same ED lines, checked by scripts/editions_parity.mjs.
#[test]
#[ignore]
fn editions_parity_fixture_wide_seeds() {
    let cases: [(u32, u32, bool, u64); 4] = [
        (1, 3, false, 0xffffffffffffffff), (2, 40, true, 0xfedcba9876543210),
        (3, 52, false, 0x8000000000000001), (4, 75, true, 0x123456789abcdef0),
    ];
    for c in cases.span() {
        let (e, sp, shiny, seed) = *c;
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

/// Drifted editions: one EDD line per case (the day's drift and the whole file in hex), which
/// scripts/editions_drift_parity.mjs replays through editions_lite.js with the same drift. The days
/// cover every knob, months with and without new melodies and weeks with and without a rotation.
#[test]
#[ignore]
fn editions_drift_parity_fixture() {
    let mut i: u32 = 0;
    while i < 30 {
        let e = i % 8 + 1;
        let sp = (i * 11) % 75 + 1;
        let day: u64 = 1 + (i * 23).into();
        let clock = crate::composition::drift::DriftClock {
            day,
            day_hash: 'day' + day.into(),
            week_hash: 'week' + ((day - 1) / 7).into(),
            month_hash: 'month' + ((day - 1) / 30).into(),
        };
        let d = crate::composition::drift::layered_drift(sp.into(), 0, 0, clock);
        let midi = crate::composition::editions::edition_tracks_on(
            sp, i % 3 == 0, e, (i * 977).into(), Option::Some(d), i % 2 == 1,
        );
        let bytes = midi::smf::smf_bytes(1, 480, midi.span());
        let rhythm: felt252 = match d.rhythm {
            Option::Some(h) => h,
            Option::None => 0,
        };
        let rotate: felt252 = match d.rotate {
            Option::Some(h) => h,
            Option::None => 0,
        };
        println!(
            "EDD e={} sp={} shiny={} echo={} seed={} day={} rhythm={} rotate={} knob={} delta={} len={} hex={}",
            e,
            sp,
            if i % 3 == 0 {
                1
            } else {
                0
            },
            i % 2,
            i * 977,
            day,
            rhythm,
            rotate,
            d.day_knob,
            d.delta_bpm,
            bytes.len(),
            hex(bytes.span()),
        );
        i += 1;
    }
}

//! Gas of one Loot edition (editions.cairo), no printing: the smallest, a typical and the largest
//! file of the parity cases (scripts/editions_cases.json cases 66, 0, 73). #[ignore]d: run one at a
//! time through scripts/cairo_run.sh (`-- editions_gas --include-ignored`).
use beast_composer::composition::drift::Drift;
use crate::common::purchase_seed;
use crate::editions::{edition_byte_array, edition_smf_bytes};

#[test]
#[ignore]
fn editions_gas_smallest() {
    let d = Drift {
        rhythm: Option::None,
        rotate: Option::Some(
            3513230466277515358528724425961644787620258267375471301093534828525907721667,
        ),
        day_knob: 0,
        delta_bpm: 0,
        day: 100,
    };
    assert_eq!(edition_smf_bytes(92, false, 7, purchase_seed(43), Option::Some(d)).len(), 2115);
}

#[test]
#[ignore]
fn editions_gas_typical() {
    assert_eq!(edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None).len(), 7767);
}

#[test]
#[ignore]
fn editions_gas_largest() {
    let d = Drift {
        rhythm: Option::None,
        rotate: Option::Some(
            1147422815910452994485634882020033426917366410028677254731739025631363638739,
        ),
        day_knob: 2,
        delta_bpm: -4,
        day: 100,
    };
    assert_eq!(edition_byte_array(81, true, 14, purchase_seed(102), Option::Some(d)).len(), 13557);
}

/// The typical file again, orchestrated and packed as LootEditionComposer returns it: the cost of
/// `orchestrate` + `bytes_to_byte_array` is the difference from editions_gas_typical.
#[test]
#[ignore]
fn editions_gas_typical_played() {
    let midi = edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None);
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    let played = crate::orchestra::orchestrate(midi.span(), b.span(), 0, array![].span(), 0);
    let fast = crate::orchestra::orchestrate_byte_array(midi.span(), b.span(), 0, array![].span(), 0);
    assert!(fast == midi::pack::bytes_to_byte_array(played.span()));
}

#[test]
#[ignore]
fn editions_gas_typical_played_fast() {
    let midi = edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None);
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    assert_eq!(crate::orchestra::orchestrate_byte_array(midi.span(), b.span(), 0, array![].span(), 0).len(), 7767);
}

#[test]
#[ignore]
fn editions_gas_typical_played_inline() {
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    let x = crate::editions::edition_played_byte_array(78, false, 1, purchase_seed(1), Option::None, b.span(), 1);
    // the lab's playback (loot-lab.mjs track0: the band, the low accompaniment instrument, the volumes)
    let mut h: u32 = 0;
    let mut i: u32 = 0;
    while i != x.len() {
        h = core::num::traits::WrappingAdd::wrapping_add(
            core::num::traits::WrappingMul::wrapping_mul(h, 31), x.at(i).unwrap().into(),
        );
        i += 1;
    }
    assert_eq!((x.len(), h), (7767, 3295417665));
}

#[test]
#[ignore]
fn editions_gas_typical_inline_only() {
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    assert_eq!(crate::editions::edition_played_byte_array(78, false, 1, purchase_seed(1), Option::None, b.span(), 1).len(), 7767);
}

#[test]
#[ignore]
fn editions_gas_typical_bytes_only() {
    let midi = edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None);
    assert_eq!(midi::pack::bytes_to_byte_array(midi.span()).len(), 7767);
}

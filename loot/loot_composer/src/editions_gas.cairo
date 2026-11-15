//! Gas of one Loot edition (editions.cairo), no printing: the preserved small, typical and large
//! file of the parity cases (scripts/editions_cases.json cases 49, 0, 13). #[ignore]d: run one at a
//! time through scripts/cairo_run.sh (`-- editions_gas --include-ignored`).
use beast_composer::composition::drift::Drift;
use crate::common::purchase_seed;
use crate::editions::{edition_byte_array, edition_smf_bytes};

#[test]
#[ignore]
fn editions_gas_smallest() {
    let d = Drift {
        rhythm: Option::Some(
            2746213876644746020052073419710752723869996316995050430318032382673721143941,
        ),
        rotate: Option::Some(
            1777443051047505738702378846517467593115000503829565941652518847992894103636,
        ),
        day_knob: 1,
        delta_bpm: 0,
        day: 45,
    };
    assert_eq!(edition_smf_bytes(92, false, 20, purchase_seed(14), Option::Some(d)).len(), 2163);
}

#[test]
#[ignore]
fn editions_gas_typical() {
    assert_eq!(edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None).len(), 6346);
}

#[test]
#[ignore]
fn editions_gas_largest() {
    assert_eq!(edition_byte_array(79, true, 14, purchase_seed(82), Option::None).len(), 12491);
}

/// The typical file again, orchestrated and packed as LootEditionComposer returns it: the cost of
/// `orchestrate` + `bytes_to_byte_array` is the difference from editions_gas_typical.
#[test]
#[ignore]
fn editions_gas_typical_played() {
    let midi = edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None);
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    let played = crate::orchestra::orchestrate(midi.span(), b.span(), 0);
    let fast = crate::orchestra::orchestrate_byte_array(midi.span(), b.span(), 0);
    assert!(fast == midi::pack::bytes_to_byte_array(played.span()));
}

#[test]
#[ignore]
fn editions_gas_typical_played_fast() {
    let midi = edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None);
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    assert_eq!(crate::orchestra::orchestrate_byte_array(midi.span(), b.span(), 0).len(), 6346);
}

#[test]
#[ignore]
fn editions_gas_typical_played_inline() {
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    let x = crate::editions::edition_played_byte_array(78, false, 1, purchase_seed(1), Option::None, b.span());
    let midi = edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None);
    assert!(x == crate::orchestra::orchestrate_byte_array(midi.span(), b.span(), 0));
}

#[test]
#[ignore]
fn editions_gas_typical_inline_only() {
    let b = crate::orchestra::band(0, 78, 1, 1, Option::None);
    assert_eq!(crate::editions::edition_played_byte_array(78, false, 1, purchase_seed(1), Option::None, b.span()).len(), 6346);
}

#[test]
#[ignore]
fn editions_gas_typical_bytes_only() {
    let midi = edition_smf_bytes(78, false, 1, purchase_seed(1), Option::None);
    assert_eq!(midi::pack::bytes_to_byte_array(midi.span()).len(), 6346);
}

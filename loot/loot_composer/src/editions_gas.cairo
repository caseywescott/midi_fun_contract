//! Gas of one Loot edition (editions.cairo), no printing: the smallest, a typical and the largest
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
    assert_eq!(edition_smf_bytes(90, false, 20, purchase_seed(14), Option::Some(d)).len(), 2163);
}

#[test]
#[ignore]
fn editions_gas_typical() {
    assert_eq!(edition_smf_bytes(76, false, 1, purchase_seed(1), Option::None).len(), 6346);
}

#[test]
#[ignore]
fn editions_gas_largest() {
    assert_eq!(edition_byte_array(77, true, 14, purchase_seed(82), Option::None).len(), 12491);
}

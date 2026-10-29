//! BeastEditionComposer: its views against the library, and one call per style engine for its gas
//! (`#[ignore]`d probes: `scarb test -p beast_contracts -- edition_gas --include-ignored`; each
//! test is one deploy and one `get_edition_midi`, the heaviest Beast: tier 1, shiny).

use beast_composer::composition::editions::edition_smf_bytes;
use midi::pack::bytes_to_byte_array;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use crate::editions::{IBeastEditionComposerDispatcher, IBeastEditionComposerDispatcherTrait};

fn composer() -> IBeastEditionComposerDispatcher {
    let (address, _) = declare("BeastEditionComposer")
        .unwrap()
        .contract_class()
        .deploy(@array![])
        .unwrap();
    IBeastEditionComposerDispatcher { contract_address: address }
}

#[test]
fn serves_the_library_track() {
    let c = composer();
    assert_eq!(
        c.get_edition_midi(21, false, 2, 7),
        bytes_to_byte_array(edition_smf_bytes(21, false, 2, 7).span())
    );
    assert_eq!(c.get_edition_engine(1), 0);
    assert_eq!(c.get_edition_engine(16), 12);
}

#[test]
#[ignore]
fn edition_gas_deploy_only() {
    composer();
}

#[test]
#[ignore]
fn edition_gas_01() {
    composer().get_edition_midi(1, true, 1, 1);
}

#[test]
#[ignore]
fn edition_gas_02() {
    composer().get_edition_midi(1, true, 2, 1);
}

#[test]
#[ignore]
fn edition_gas_03() {
    composer().get_edition_midi(1, true, 3, 1);
}

#[test]
#[ignore]
fn edition_gas_04() {
    composer().get_edition_midi(1, true, 4, 1);
}

#[test]
#[ignore]
fn edition_gas_05() {
    composer().get_edition_midi(1, true, 5, 1);
}

#[test]
#[ignore]
fn edition_gas_06() {
    composer().get_edition_midi(1, true, 6, 1);
}

#[test]
#[ignore]
fn edition_gas_07() {
    composer().get_edition_midi(1, true, 7, 1);
}

#[test]
#[ignore]
fn edition_gas_08() {
    composer().get_edition_midi(1, true, 8, 1);
}

#[test]
#[ignore]
fn edition_gas_09() {
    composer().get_edition_midi(1, true, 9, 1);
}

#[test]
#[ignore]
fn edition_gas_10() {
    composer().get_edition_midi(1, true, 10, 1);
}

#[test]
#[ignore]
fn edition_gas_11() {
    composer().get_edition_midi(1, true, 11, 1);
}

#[test]
#[ignore]
fn edition_gas_12() {
    composer().get_edition_midi(1, true, 12, 1);
}

#[test]
#[ignore]
fn edition_gas_16() {
    composer().get_edition_midi(1, true, 16, 1);
}

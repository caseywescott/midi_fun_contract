use starknet::ContractAddress;
use starknet::syscalls::deploy_syscall;
use crate::examples::scale::ScaleMidiProvider;
use crate::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};

fn collection() -> ContractAddress {
    'COLLECTION'.try_into().unwrap()
}

fn deploy_scale() -> IMidiProviderDispatcher {
    let (address, _) = deploy_syscall(
        ScaleMidiProvider::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        array![collection().into()].span(),
        false,
    )
        .unwrap();
    IMidiProviderDispatcher { contract_address: address }
}

#[test]
fn scale_provider_returns_a_midi_file() {
    let midi = deploy_scale().get_midi(7);
    assert_eq!(midi[0], 'M');
    assert_eq!(midi[1], 'T');
    assert_eq!(midi[2], 'h');
    assert_eq!(midi[3], 'd');
    // Format 0, one track, 480 PPQN.
    assert_eq!(midi[9], 0);
    assert_eq!(midi[11], 1);
    assert_eq!(midi[12], 0x01);
    assert_eq!(midi[13], 0xE0);
    // It chooses its own instruments: program changes right after the tempo (MThd 14 bytes,
    // MTrk header 8, tempo meta 7).
    assert_eq!(midi[30], 0xC0);
    assert_eq!(midi[31], 12); // marimba
    assert_eq!(midi[33], 0xC1);
    assert_eq!(midi[34], 33); // fingered bass
}

#[test]
fn scale_provider_differs_per_token() {
    let p = deploy_scale();
    assert!(p.get_midi(1) != p.get_midi(2));
    assert_eq!(p.get_midi(1), p.get_midi(1));
}

#[test]
fn scale_provider_get_midi_for_is_get_midi_with_the_collection_checked() {
    let p = deploy_scale();
    assert_eq!(p.get_midi_for(collection(), 5), p.get_midi(5));
}

#[test]
#[should_panic(expected: ('unsupported collection', 'ENTRYPOINT_FAILED'))]
fn scale_provider_rejects_other_collections() {
    deploy_scale().get_midi_for('OTHER'.try_into().unwrap(), 1);
}

/// ScaleMidiProvider's bytes for 20 tokens, pinned (guards the `midi` package refactor).
#[test]
fn scale_provider_golden() {
    let mut acc: Array<felt252> = array![];
    let mut id: u256 = 0;
    while id < 20 {
        let mut felts: Array<felt252> = array![];
        crate::examples::scale::ScaleMidiProvider::scale_smf(
            core::poseidon::poseidon_hash_span(array![collection().into(), id.low.into()].span())
                .into(),
        )
            .serialize(ref felts);
        acc.append(core::poseidon::poseidon_hash_span(felts.span()));
        id += 1;
    }
    assert_eq!(
        core::poseidon::poseidon_hash_span(acc.span()),
        726557155786871684621583427530199419803863225234542968548791562625825227122,
    );
}

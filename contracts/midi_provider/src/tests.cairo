use starknet::ContractAddress;
use starknet::syscalls::deploy_syscall;
use crate::examples::scale::ScaleMidiProvider;
use crate::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait, bytes_to_byte_array};

fn byte_at(i: usize) -> u8 {
    ((i * 37 + 11) % 256).try_into().unwrap()
}

#[test]
fn bytes_to_byte_array_matches_append_byte() {
    // Every pending length (0..30) and the full-word boundaries around 31 and 62.
    let mut n: usize = 0;
    while n <= 100 {
        let mut bytes: Array<u8> = array![];
        let mut expected: ByteArray = Default::default();
        let mut i: usize = 0;
        while i < n {
            bytes.append(byte_at(i));
            expected.append_byte(byte_at(i));
            i += 1;
        }
        assert_eq!(bytes_to_byte_array(bytes.span()), expected);
        n += 1;
    }
}

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
    let midi = deploy_scale().get_midi(collection(), 7);
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
    assert!(p.get_midi(collection(), 1) != p.get_midi(collection(), 2));
    assert_eq!(p.get_midi(collection(), 1), p.get_midi(collection(), 1));
}

#[test]
#[should_panic(expected: ('unsupported collection', 'ENTRYPOINT_FAILED'))]
fn scale_provider_rejects_other_collections() {
    deploy_scale().get_midi('OTHER'.try_into().unwrap(), 1);
}

//! MidiSoundPage with real and mock providers: the page passes the two identifiers through and
//! embeds exactly the provider's MIDI.

use midi_provider::examples::scale::ScaleMidiProvider;
use midi_provider::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
use starknet::syscalls::deploy_syscall;
use starknet::{ClassHash, ContractAddress};
use super::{IMidiSoundPageDispatcher, IMidiSoundPageDispatcherTrait, MidiSoundPage, token_uri};

/// Returns `token_id % 97` synthetic bytes, and only for its one collection.
#[starknet::contract]
mod MockProvider {
    use midi_provider::IMidiProvider;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl Provider of IMidiProvider<ContractState> {
        fn get_midi(self: @ContractState, token_id: u256) -> ByteArray {
            super::synthetic((token_id % 97).try_into().unwrap())
        }

        fn get_midi_for(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            assert(token_address == super::collection(), 'unsupported collection');
            super::synthetic((token_id % 97).try_into().unwrap())
        }
    }
}

fn collection() -> ContractAddress {
    'BEASTS'.try_into().unwrap()
}

fn synthetic(n: usize) -> ByteArray {
    let mut s: ByteArray = Default::default();
    let mut i: usize = 0;
    while i < n {
        s.append_byte(((i * 37 + 11) % 256).try_into().unwrap());
        i += 1;
    }
    s
}

fn deploy(class_hash: ClassHash, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = deploy_syscall(class_hash, 0, calldata.span(), false).unwrap();
    address
}

fn page_for(provider: ContractAddress) -> IMidiSoundPageDispatcher {
    IMidiSoundPageDispatcher {
        contract_address: deploy(MidiSoundPage::TEST_CLASS_HASH, array![provider.into()]),
    }
}

fn members() -> ByteArray {
    "\"name\":\"Test\",\"attributes\":[]"
}

fn svg_b64() -> ByteArray {
    "PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnLz4="
}

#[test]
fn page_embeds_the_providers_midi() {
    let provider = deploy(MockProvider::TEST_CLASS_HASH, array![]);
    let page = page_for(provider);
    assert_eq!(page.get_midi_provider(), provider);
    let mut id: u256 = 0;
    while id < 5 {
        let uri = page.token_uri(members(), svg_b64(), collection(), id * 31 + 2);
        let midi = synthetic(((id * 31 + 2) % 97).try_into().unwrap());
        assert_eq!(uri, token_uri(@members(), @svg_b64(), @midi));
        id += 1;
    }
}

#[test]
fn page_works_with_a_second_provider() {
    // ScaleMidiProvider knows nothing about Beasts; the page does not care.
    let provider = deploy(ScaleMidiProvider::TEST_CLASS_HASH, array![collection().into()]);
    let uri = page_for(provider).token_uri(members(), svg_b64(), collection(), 42);
    let midi = IMidiProviderDispatcher { contract_address: provider }.get_midi_for(collection(), 42);
    assert_eq!(uri, token_uri(@members(), @svg_b64(), @midi));
}

#[test]
#[should_panic(expected: ('unsupported collection', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn provider_rejections_propagate() {
    let provider = deploy(MockProvider::TEST_CLASS_HASH, array![]);
    page_for(provider).token_uri(members(), svg_b64(), 'OTHER'.try_into().unwrap(), 1);
}

#[test]
fn page_needs_a_provider() {
    let result = deploy_syscall(MidiSoundPage::TEST_CLASS_HASH, 0, array![0].span(), false);
    assert_eq!(result.unwrap_err(), array!['zero midi provider', 'CONSTRUCTOR_FAILED']);
}

/// Gas for a whole page call (small members and SVG, MIDI from ScaleMidiProvider) without the
/// test's own comparison work. `bench_*` in tests.cairo measures assembly with the real Warlock.
#[test]
fn bench_page_call_scale_provider() {
    let provider = deploy(ScaleMidiProvider::TEST_CLASS_HASH, array![collection().into()]);
    let uri = page_for(provider).token_uri(members(), svg_b64(), collection(), 42);
    assert!(uri.len() > 0);
}

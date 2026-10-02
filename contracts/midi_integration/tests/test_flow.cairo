use beast_sound::provider::packed_midi_bytes;
use beast_sound_page::{IMidiPageDispatcher, IMidiPageDispatcherTrait};
use core::poseidon::poseidon_hash_span;
use koji::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, encode_v3_token_id, v3_score_midi,
};
use midi_integration::{
    IMockNftDispatcher, IMockNftDispatcherTrait, IMockStateDispatcher, IMockStateDispatcherTrait,
};
use midi_interfaces::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
fn deploy(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = declare(name).unwrap().contract_class().deploy(@calldata).unwrap();
    address
}
fn warlock() -> PackableBeastV3 {
    PackableBeastV3 {
        id: 1,
        prefix: 57,
        suffix: 15,
        level: 126,
        health: 229,
        shiny: 0,
        animated: 0,
        tier: 1,
        beast_type: 0,
    }
}
fn calm() -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954,
    }
}
pub fn setup(
    beast: PackableBeastV3, live: BeastV3LiveState, collects: u64,
) -> (IMidiProviderDispatcher, IMockStateDispatcher, IMockStateDispatcher, u256) {
    let nft = deploy("MockBeasts", array![]);
    let source = deploy("MockDeathMountain", array![]);
    let n = IMockStateDispatcher { contract_address: nft };
    let d = IMockStateDispatcher { contract_address: source };
    let token = encode_v3_token_id(beast);
    n.set_source(source);
    n.set_state(token, live.adventurers_killed, live.rank, live.species_count, true);
    d
        .set_collects(
            poseidon_hash_span(
                array![beast.id.into(), beast.prefix.into(), beast.suffix.into()].span(),
            ),
            collects,
        );
    let p = deploy("BeastMidiProvider", array![nft.into(), source.into()]);
    (IMidiProviderDispatcher { contract_address: p }, n, d, token)
}
#[test]
fn provider_matches_composer_and_reads_changes() {
    let beast = warlock();
    let live = calm();
    let (p, n, d, id) = setup(beast, live, 1);
    let initial = p.get_midi(n.contract_address, id);
    assert!(initial == packed_midi_bytes(v3_score_midi(beast, live)));
    let veteran = BeastV3LiveState {
        adventurers_killed: 40, scars: 9, summit_held_seconds: 0, rank: 1, species_count: 954,
    };
    n.set_state(id, 40, 1, 954, true);
    d.set_collects(poseidon_hash_span(array![1, 57, 15].span()), 10);
    let changed = p.get_midi(n.contract_address, id);
    assert!(initial != changed);
    assert!(changed == packed_midi_bytes(v3_score_midi(beast, veteran)));
}
#[test]
fn provider_genesis_zero_collects_is_zero() {
    let beast = PackableBeastV3 {
        id: 1,
        prefix: 0,
        suffix: 0,
        level: 1,
        health: 100,
        shiny: 1,
        animated: 1,
        tier: 1,
        beast_type: 0,
    };
    let live = BeastV3LiveState {
        adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1243,
    };
    let (p, n, _, id) = setup(beast, live, 0);
    assert!(p.get_midi(n.contract_address, id) == packed_midi_bytes(v3_score_midi(beast, live)));
}
#[test]
fn packed_bytes_all_remainders() {
    let mut n: usize = 0;
    while n < 95 {
        let mut bytes = array![];
        let mut expected: ByteArray = Default::default();
        let mut i: usize = 0;
        while i < n {
            let value: u8 = (i % 256).try_into().unwrap();
            bytes.append(value);
            expected.append_byte(value);
            i += 1;
        }
        assert!(packed_midi_bytes(koji::midi::output::to_felt252_array(bytes)) == expected);
        n += 1;
    }
}
#[test]
#[should_panic(expected: ('unsupported collection',))]
fn wrong_collection_reverts() {
    let (p, _, _, id) = setup(warlock(), calm(), 1);
    p.get_midi(0x123.try_into().unwrap(), id);
}
#[test]
#[should_panic(expected: ('unminted token',))]
fn nonexistent_token_reverts() {
    let (p, n, _, id) = setup(warlock(), calm(), 1);
    n.set_state(id, 0, 500, 954, false);
    p.get_midi(n.contract_address, id);
}
#[test]
#[should_panic(expected: ('defeat source mismatch',))]
fn source_drift_reverts() {
    let (p, n, _, id) = setup(warlock(), calm(), 1);
    n.set_source(0x123.try_into().unwrap());
    p.get_midi(n.contract_address, id);
}
#[test]
fn missing_source_reverts() {
    let class = declare("BeastMidiProvider").unwrap().contract_class();
    let result = class.deploy(@array![1, 0]);
    match result {
        Result::Err(data) => {
            assert!(data.span() == array!['defeat source unavailable'].span());
        },
        Result::Ok(_) => { panic!("missing source accepted"); },
    }
}
#[test]
#[should_panic(expected: ('invalid token id',))]
fn newer_180_bit_token_reverts() {
    let (p, n, _, id) = setup(warlock(), calm(), 1);
    p.get_midi(n.contract_address, id + 0x1000000000000000000000000000000);
}
#[test]
#[should_panic(expected: ('unsupported defeat source',))]
fn community_source_reverts() {
    let mut beast = warlock();
    beast.id = 76;
    let (p, n, _, id) = setup(beast, calm(), 1);
    p.get_midi(n.contract_address, id);
}
#[test]
fn page_accepts_non_beast_provider() {
    let provider = deploy("FixedMidiProvider", array![]);
    let page = deploy("MidiPage", array![provider.into()]);
    let collection = 0x123.try_into().unwrap();
    let midi = IMidiProviderDispatcher { contract_address: provider }.get_midi(collection, 42);
    let uri = IMidiPageDispatcher { contract_address: page }
        .token_uri("\"name\":\"Other\"", "PHN2Zy8+", collection, 42);
    assert!(uri == beast_sound_page::token_uri(@"\"name\":\"Other\"", @"PHN2Zy8+", @midi));
    println!("OTHER_URI {}", uri);
}
#[test]
fn full_nft_path_metadata_and_live_state() {
    let (p, n, d, id) = setup(warlock(), calm(), 1);
    let nft = IMockNftDispatcher {
        contract_address: deploy("MockNft", array![n.contract_address.into()]),
    };
    let off = nft.token_uri(id);
    println!("NFT_OFF {}", off);
    let page = deploy("MidiPage", array![p.contract_address.into()]);
    nft.set_page(page);
    let on = nft.token_uri(id);
    println!("NFT_ON {}", on);
    n.set_state(id, 40, 1, 954, true);
    d.set_collects(poseidon_hash_span(array![1, 57, 15].span()), 10);
    let changed = nft.token_uri(id);
    assert!(on != changed);
    println!("NFT_CHANGED {}", changed);
    nft.set_page(0.try_into().unwrap());
    assert!(nft.token_uri(id) == off);
}
#[test]
fn measure_setup() {
    let (p, n, _, _) = setup(warlock(), calm(), 1);
    let page = deploy("MidiPage", array![p.contract_address.into()]);
    let nft = IMockNftDispatcher {
        contract_address: deploy("MockNft", array![n.contract_address.into()]),
    };
    nft.set_page(page);
}
#[test]
fn measure_full_path() {
    let (p, n, _, id) = setup(warlock(), calm(), 1);
    let page = deploy("MidiPage", array![p.contract_address.into()]);
    let nft = IMockNftDispatcher {
        contract_address: deploy("MockNft", array![n.contract_address.into()]),
    };
    nft.set_page(page);
    let _ = nft.token_uri(id);
}

fn real_setup(beast: PackableBeastV3, live: BeastV3LiveState) -> (IMockNftDispatcher, u256) {
    let (p, n, _, id) = setup(beast, live, live.scars + 1);
    let page = deploy("MidiPage", array![p.contract_address.into()]);
    let nft = IMockNftDispatcher {
        contract_address: deploy("MockNft", array![n.contract_address.into()]),
    };
    nft.set_page(page);
    nft.use_real_art();
    (nft, id)
}
#[test]
fn measure_real_setup() {
    let _ = real_setup(warlock(), calm());
}
#[test]
fn measure_real_named_path() {
    let (nft, id) = real_setup(warlock(), calm());
    let uri = nft.token_uri(id);
    println!("REAL_NAMED_LEN {}", uri.len());
}
#[test]
fn measure_real_heaviest_setup() {
    let beast = PackableBeastV3 {
        id: 53,
        prefix: 69,
        suffix: 18,
        level: 255,
        health: 1023,
        shiny: 1,
        animated: 1,
        tier: 1,
        beast_type: 2,
    };
    let live = BeastV3LiveState {
        adventurers_killed: 200, scars: 63, summit_held_seconds: 0, rank: 1, species_count: 1243,
    };
    let _ = real_setup(beast, live);
}
#[test]
fn measure_real_heaviest_path() {
    let beast = PackableBeastV3 {
        id: 53,
        prefix: 69,
        suffix: 18,
        level: 255,
        health: 1023,
        shiny: 1,
        animated: 1,
        tier: 1,
        beast_type: 2,
    };
    let live = BeastV3LiveState {
        adventurers_killed: 200, scars: 63, summit_held_seconds: 0, rank: 1, species_count: 1243,
    };
    let (nft, id) = real_setup(beast, live);
    let uri = nft.token_uri(id);
    println!("REAL_HEAVIEST_LEN {}", uri.len());
}

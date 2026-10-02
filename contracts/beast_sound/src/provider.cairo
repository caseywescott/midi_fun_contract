//! Beast provider for the 116-bit V3 format and original Death Mountain species 1–75.
use starknet::ContractAddress;

#[starknet::interface]
pub trait IBeastState<T> {
    fn owner_of(self: @T, token_id: u256) -> ContractAddress;
    fn get_adventurers_killed(self: @T, token_id: u256) -> u64;
    fn get_beast_rank(self: @T, token_id: u256) -> u16;
    fn get_species_count(self: @T, beast_id: u64) -> u16;
    fn get_death_mountain_address(self: @T) -> ContractAddress;
}

#[starknet::interface]
pub trait IDeathMountainState<T> {
    fn get_collectable_count(self: @T, dungeon: ContractAddress, entity_hash: felt252) -> u64;
}

/// Convert the composer's [length, 31-byte big-endian chunks] without touching individual bytes.
pub fn packed_midi_bytes(mut packed: Array<felt252>) -> ByteArray {
    let length: usize = packed.pop_front().unwrap().try_into().unwrap();
    assert(packed.len() == (length + 30) / 31, 'invalid MIDI chunks');
    let mut out: ByteArray = Default::default();
    let mut remaining = length;
    while let Option::Some(word) = packed.pop_front() {
        let bytes = if remaining >= 31 {
            31
        } else {
            remaining
        };
        out.append_word(word, bytes);
        remaining -= bytes;
    }
    out
}

#[starknet::contract]
pub mod BeastMidiProvider {
    use core::num::traits::Zero;
    use core::poseidon::poseidon_hash_span;
    use koji::composition::beast_v3_sound::{BeastV3LiveState, decode_v3_token_id, v3_score_midi};
    use midi_interfaces::IMidiProvider;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::{
        IBeastStateDispatcher, IBeastStateDispatcherTrait, IDeathMountainStateDispatcher,
        IDeathMountainStateDispatcherTrait, packed_midi_bytes,
    };

    #[storage]
    struct Storage {
        collection: ContractAddress,
        death_mountain: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, collection: ContractAddress, death_mountain: ContractAddress,
    ) {
        assert(collection.is_non_zero(), 'collection unavailable');
        assert(death_mountain.is_non_zero(), 'defeat source unavailable');
        self.collection.write(collection);
        self.death_mountain.write(death_mountain);
    }

    #[abi(embed_v0)]
    impl MidiProviderImpl of IMidiProvider<ContractState> {
        fn get_midi(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            assert(token_address == self.collection.read(), 'unsupported collection');
            // Decoder rejects high bits, including subsequent 180-bit V3 token formats.
            let beast = decode_v3_token_id(token_id);
            assert(beast.id <= 75, 'unsupported defeat source');
            let nft = IBeastStateDispatcher { contract_address: token_address };
            assert(nft.owner_of(token_id).is_non_zero(), 'unminted token');
            // Fail closed if NFT configuration changes: never read a stale/other dungeon's state.
            assert(
                nft.get_death_mountain_address() == self.death_mountain.read(),
                'defeat source mismatch',
            );
            let entity_hash = poseidon_hash_span(
                array![beast.id.into(), beast.prefix.into(), beast.suffix.into()].span(),
            );
            // Pinned 116-bit NFT getters pass the Beast Systems contract itself as namespace.
            // Its _get_correct_dungeon shim maps this to the current gameplay namespace.
            let collects = IDeathMountainStateDispatcher {
                contract_address: self.death_mountain.read(),
            }
                .get_collectable_count(self.death_mountain.read(), entity_hash);
            let live = BeastV3LiveState {
                adventurers_killed: nft.get_adventurers_killed(token_id),
                scars: if collects > 0 {
                    collects - 1
                } else {
                    0
                },
                // Summit is retired. This is a versioned policy input, not a missing-state
                // fallback.
                summit_held_seconds: 0,
                rank: nft.get_beast_rank(token_id),
                species_count: nft.get_species_count(beast.id),
            };
            packed_midi_bytes(v3_score_midi(beast, live))
        }
    }
}

//! Integration doubles enforce the NFT/Death Mountain ABI and pinned self-address namespace.
use starknet::ContractAddress;
#[derive(Copy, Drop, Serde)]
pub struct EntityStats {
    pub dungeon: ContractAddress,
    pub entity_hash: felt252,
    pub adventurers_killed: u64,
}
#[starknet::interface]
pub trait IEntityState<T> {
    fn get_entity_stats(self: @T, dungeon: ContractAddress, entity_hash: felt252) -> EntityStats;
}
#[starknet::interface]
pub trait IMockState<T> {
    fn set_state(ref self: T, token_id: u256, kills: u64, rank: u16, count: u16, exists: bool);
    fn set_source(ref self: T, source: ContractAddress);
    fn set_collects(ref self: T, entity_hash: felt252, count: u64);
}
#[starknet::contract]
pub mod MockBeasts {
    use beast_sound::provider::IBeastState;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    #[storage]
    struct Storage {
        source: ContractAddress,
        kills: Map<u256, u64>,
        rank: Map<u256, u16>,
        count: u16,
        exists: Map<u256, bool>,
    }
    #[abi(embed_v0)]
    impl Setup of super::IMockState<ContractState> {
        fn set_state(
            ref self: ContractState,
            token_id: u256,
            kills: u64,
            rank: u16,
            count: u16,
            exists: bool,
        ) {
            self.kills.write(token_id, kills);
            self.rank.write(token_id, rank);
            self.count.write(count);
            self.exists.write(token_id, exists);
        }
        fn set_source(ref self: ContractState, source: ContractAddress) {
            self.source.write(source);
        }
        fn set_collects(ref self: ContractState, entity_hash: felt252, count: u64) {
            panic!("not defeat source");
        }
    }
    #[abi(embed_v0)]
    impl State of IBeastState<ContractState> {
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            assert(self.exists.read(token_id), 'unminted token');
            0x777.try_into().unwrap()
        }
        fn get_adventurers_killed(self: @ContractState, token_id: u256) -> u64 {
            self.kills.read(token_id)
        }
        fn get_beast_rank(self: @ContractState, token_id: u256) -> u16 {
            self.rank.read(token_id)
        }
        fn get_species_count(self: @ContractState, beast_id: u64) -> u16 {
            self.count.read()
        }
        fn get_death_mountain_address(self: @ContractState) -> ContractAddress {
            self.source.read()
        }
    }
}
#[starknet::contract]
pub mod MockDeathMountain {
    use beast_sound::provider::IDeathMountainState;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    #[storage]
    struct Storage {
        collects: Map<felt252, u64>,
    }
    #[abi(embed_v0)]
    impl Setup of super::IMockState<ContractState> {
        fn set_state(
            ref self: ContractState,
            token_id: u256,
            kills: u64,
            rank: u16,
            count: u16,
            exists: bool,
        ) {
            panic!("not NFT");
        }
        fn set_source(ref self: ContractState, source: ContractAddress) {
            panic!("not NFT");
        }
        fn set_collects(ref self: ContractState, entity_hash: felt252, count: u64) {
            self.collects.write(entity_hash, count);
        }
    }
    #[abi(embed_v0)]
    impl Entity of super::IEntityState<ContractState> {
        fn get_entity_stats(
            self: @ContractState, dungeon: ContractAddress, entity_hash: felt252,
        ) -> super::EntityStats {
            super::EntityStats { dungeon, entity_hash, adventurers_killed: 0 }
        }
    }
    #[abi(embed_v0)]
    impl State of IDeathMountainState<ContractState> {
        fn get_collectable_count(
            self: @ContractState, dungeon: ContractAddress, entity_hash: felt252,
        ) -> u64 {
            assert(dungeon == starknet::get_contract_address(), 'incorrect namespace');
            self.collects.read(entity_hash)
        }
    }
}
/// Non-Beast example provider. No composition or state is supplied by the page caller.
#[starknet::contract]
pub mod FixedMidiProvider {
    use midi_interfaces::IMidiProvider;
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl Provider of IMidiProvider<ContractState> {
        fn get_midi(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            assert(
                token_address == 0x123.try_into().unwrap() && token_id == 42,
                'wrong MIDI identifiers',
            );
            let mut bytes: ByteArray = Default::default();
            for byte in array![
                77_u8,
                84,
                104,
                100,
                0,
                0,
                0,
                6,
                0,
                0,
                0,
                1,
                1,
                224,
                77,
                84,
                114,
                107,
                0,
                0,
                0,
                20,
                0,
                255,
                81,
                3,
                7,
                161,
                33,
                0,
                144,
                60,
                100,
                131,
                96,
                128,
                60,
                0,
                0,
                255,
                47,
                0,
            ] {
                bytes.append_byte(byte);
            }
            bytes
        }
    }
}
#[starknet::interface]
pub trait IMockNft<T> {
    fn token_uri(self: @T, token_id: u256) -> ByteArray;
    fn set_page(ref self: T, page: ContractAddress);
    fn use_real_art(ref self: T);
}
/// Exercises NFT → page → provider → source contracts, retaining exact sound-off URI.
#[starknet::contract]
pub mod MockNft {
    use beast_sound_page::{IMidiPageDispatcher, IMidiPageDispatcherTrait};
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    #[storage]
    struct Storage {
        page: ContractAddress,
        collection: ContractAddress,
        real_art: bool,
    }
    #[constructor]
    fn constructor(ref self: ContractState, collection: ContractAddress) {
        self.collection.write(collection);
    }
    #[abi(embed_v0)]
    impl Nft of super::IMockNft<ContractState> {
        fn set_page(ref self: ContractState, page: ContractAddress) {
            self.page.write(page);
        }
        fn use_real_art(ref self: ContractState) {
            self.real_art.write(true);
        }
        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            let small_members: ByteArray =
                "\"name\":\"Test\",\"description\":\"Music collectible\",\"attributes\":[]";
            let small_art: ByteArray = "PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnLz4=";
            let (members, art) = if self.real_art.read() {
                super::real_art::presentation()
            } else {
                (small_members, small_art)
            };
            if self.page.read().is_zero() {
                return format!(
                    "data:application/json;base64,{}",
                    beast_sound_page::base64(
                        @format!("{{{},\"image\":\"data:image/svg+xml;base64,{}\"}}", members, art),
                    ),
                );
            }
            IMidiPageDispatcher { contract_address: self.page.read() }
                .token_uri(members, art, self.collection.read(), token_id)
        }
    }
}

pub mod real_art;

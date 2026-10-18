//! Mock Beasts V3 NFT and Death Mountain, copied from beasts/beast_contracts/src/tests.cairo with
//! the same semantics (`get_beast_rank` and `get_adventurers_killed` revert for an unminted token;
//! `token_uri` panics, the provider must never call it).
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockBeasts<T> {
    fn mint(ref self: T, token_id: u256, rank: u16);
    fn set_rank(ref self: T, token_id: u256, rank: u16);
    fn set_species_count(ref self: T, beast_id: u64, count: u16);
    fn set_kills(ref self: T, token_id: u256, kills: u64);
    fn set_cached_kills(ref self: T, token_id: u256, kills: u64);
    fn set_death_mountain(ref self: T, death_mountain: ContractAddress);
}

/// The Beasts V3 getters the provider uses, with the same owned-token checks. `token_uri` panics:
/// the provider must never call it.
#[starknet::contract]
pub mod MockBeasts {
    use beast_contracts::provider::{BeastCachedStats, IBeastsLiveState};
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        minted: Map<u256, bool>,
        rank: Map<u256, u16>,
        species_count: Map<u64, u16>,
        kills: Map<u256, u64>,
        cached_kills: Map<u256, u64>,
        death_mountain: ContractAddress,
    }

    #[abi(embed_v0)]
    impl LiveState of IBeastsLiveState<ContractState> {
        fn get_beast_rank(self: @ContractState, token_id: u256) -> u16 {
            assert(self.minted.read(token_id), 'ERC721: invalid token ID');
            self.rank.read(token_id)
        }
        fn get_species_count(self: @ContractState, beast_id: u64) -> u16 {
            self.species_count.read(beast_id)
        }
        fn get_adventurers_killed(self: @ContractState, token_id: u256) -> u64 {
            assert(self.minted.read(token_id), 'ERC721: invalid token ID');
            self.kills.read(token_id)
        }
        fn get_cached_stats(self: @ContractState, token_id: u256) -> BeastCachedStats {
            BeastCachedStats {
                adventurers_killed: self.cached_kills.read(token_id),
                last_killed_by: 0,
                last_killed_timestamp: 0,
            }
        }
        fn get_death_mountain_address(self: @ContractState) -> ContractAddress {
            self.death_mountain.read()
        }
    }

    #[abi(embed_v0)]
    impl Admin of super::IMockBeasts<ContractState> {
        fn mint(ref self: ContractState, token_id: u256, rank: u16) {
            self.minted.write(token_id, true);
            self.rank.write(token_id, rank);
        }
        fn set_rank(ref self: ContractState, token_id: u256, rank: u16) {
            self.rank.write(token_id, rank);
        }
        fn set_species_count(ref self: ContractState, beast_id: u64, count: u16) {
            self.species_count.write(beast_id, count);
        }
        fn set_kills(ref self: ContractState, token_id: u256, kills: u64) {
            self.kills.write(token_id, kills);
        }
        fn set_cached_kills(ref self: ContractState, token_id: u256, kills: u64) {
            self.cached_kills.write(token_id, kills);
        }
        fn set_death_mountain(ref self: ContractState, death_mountain: ContractAddress) {
            self.death_mountain.write(death_mountain);
        }
    }

    #[external(v0)]
    fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
        panic!("provider called token_uri")
    }
}

#[starknet::interface]
pub trait IMockDeathMountain<T> {
    fn set_collects(ref self: T, dungeon: ContractAddress, entity_hash: felt252, count: u64);
}

/// Collect counts keyed by (dungeon, entity hash), like Death Mountain's `CollectableCount`.
#[starknet::contract]
pub mod MockDeathMountain {
    use beast_contracts::provider::IDeathMountainCollects;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    struct Storage {
        collects: Map<(ContractAddress, felt252), u64>,
    }

    #[abi(embed_v0)]
    impl Collects of IDeathMountainCollects<ContractState> {
        fn get_collectable_count(
            self: @ContractState, dungeon: ContractAddress, entity_hash: felt252,
        ) -> u64 {
            self.collects.read((dungeon, entity_hash))
        }
    }

    #[abi(embed_v0)]
    impl Admin of super::IMockDeathMountain<ContractState> {
        fn set_collects(
            ref self: ContractState, dungeon: ContractAddress, entity_hash: felt252, count: u64,
        ) {
            self.collects.write((dungeon, entity_hash), count);
        }
    }
}

/// Work `BurnBeasts::get_beast_rank` adds on top of `MockBeasts`' (poseidon rounds).
pub const BURN_ROUNDS: u32 = 200;

/// `MockBeasts` whose `get_beast_rank` also does `BURN_ROUNDS` poseidon rounds. Only for the
/// measurement check (group M): with it, `get_midi`'s gas must grow by exactly what
/// `get_beast_rank`'s grows, which shows a call's gas includes its nested calls.
#[starknet::contract]
pub mod BurnBeasts {
    use beast_contracts::provider::{BeastCachedStats, IBeastsLiveState};
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        minted: Map<u256, bool>,
        rank: Map<u256, u16>,
        species_count: Map<u64, u16>,
        kills: Map<u256, u64>,
        cached_kills: Map<u256, u64>,
        death_mountain: ContractAddress,
    }

    #[abi(embed_v0)]
    impl LiveState of IBeastsLiveState<ContractState> {
        fn get_beast_rank(self: @ContractState, token_id: u256) -> u16 {
            assert(self.minted.read(token_id), 'ERC721: invalid token ID');
            let mut h: felt252 = 0;
            let mut i: u32 = 0;
            while i < super::BURN_ROUNDS {
                h = core::poseidon::poseidon_hash_span(array![h, i.into()].span());
                i += 1;
            }
            assert(h != 0, 'burn');
            self.rank.read(token_id)
        }
        fn get_species_count(self: @ContractState, beast_id: u64) -> u16 {
            self.species_count.read(beast_id)
        }
        fn get_adventurers_killed(self: @ContractState, token_id: u256) -> u64 {
            assert(self.minted.read(token_id), 'ERC721: invalid token ID');
            self.kills.read(token_id)
        }
        fn get_cached_stats(self: @ContractState, token_id: u256) -> BeastCachedStats {
            BeastCachedStats {
                adventurers_killed: self.cached_kills.read(token_id),
                last_killed_by: 0,
                last_killed_timestamp: 0,
            }
        }
        fn get_death_mountain_address(self: @ContractState) -> ContractAddress {
            self.death_mountain.read()
        }
    }

    #[abi(embed_v0)]
    impl Admin of super::IMockBeasts<ContractState> {
        fn mint(ref self: ContractState, token_id: u256, rank: u16) {
            self.minted.write(token_id, true);
            self.rank.write(token_id, rank);
        }
        fn set_rank(ref self: ContractState, token_id: u256, rank: u16) {
            self.rank.write(token_id, rank);
        }
        fn set_species_count(ref self: ContractState, beast_id: u64, count: u16) {
            self.species_count.write(beast_id, count);
        }
        fn set_kills(ref self: ContractState, token_id: u256, kills: u64) {
            self.kills.write(token_id, kills);
        }
        fn set_cached_kills(ref self: ContractState, token_id: u256, kills: u64) {
            self.cached_kills.write(token_id, kills);
        }
        fn set_death_mountain(ref self: ContractState, death_mountain: ContractAddress) {
            self.death_mountain.write(death_mountain);
        }
    }
}

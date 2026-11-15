//! THROWAWAY (CASM measurement only, not for deployment): classes exposing just the Rounds and
//! Sound Checks entry points, to measure their compiled size. Delete once the composer class exists.
use beast_composer::composition::drift::Drift;

fn drift_of(on: bool, rhythm: Option<felt252>, rotate: Option<felt252>, day_knob: u8, delta_bpm: i64, day: u64) -> Option<Drift> {
    if on {
        Option::Some(Drift { rhythm, rotate, day_knob, delta_bpm, day })
    } else {
        Option::None
    }
}

#[starknet::interface]
pub trait IRoundsProbe<T> {
    fn round(
        self: @T, species: u32, mega: bool, seed: u64, drift_on: bool, rhythm: Option<felt252>,
        rotate: Option<felt252>, day_knob: u8, delta_bpm: i64, day: u64,
    ) -> ByteArray;
}

#[starknet::interface]
pub trait IChecksProbe<T> {
    fn sound_check(self: @T, species: u32, mega: bool, take: u64) -> ByteArray;
}

#[starknet::contract]
pub mod RoundsProbe {
    use loot_composer::rounds::round_byte_array;
    use super::drift_of;
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl P of super::IRoundsProbe<ContractState> {
        fn round(
            self: @ContractState, species: u32, mega: bool, seed: u64, drift_on: bool,
            rhythm: Option<felt252>, rotate: Option<felt252>, day_knob: u8, delta_bpm: i64, day: u64,
        ) -> ByteArray {
            round_byte_array(species, mega, seed, drift_of(drift_on, rhythm, rotate, day_knob, delta_bpm, day))
        }
    }
}

#[starknet::contract]
pub mod ChecksProbe {
    use loot_composer::checks::sound_check_byte_array;
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl P of super::IChecksProbe<ContractState> {
        fn sound_check(self: @ContractState, species: u32, mega: bool, take: u64) -> ByteArray {
            sound_check_byte_array(species, mega, take)
        }
    }
}

#[starknet::contract]
pub mod RoundsChecksProbe {
    use loot_composer::checks::sound_check_byte_array;
    use loot_composer::rounds::round_byte_array;
    use super::drift_of;
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl P of super::IRoundsProbe<ContractState> {
        fn round(
            self: @ContractState, species: u32, mega: bool, seed: u64, drift_on: bool,
            rhythm: Option<felt252>, rotate: Option<felt252>, day_knob: u8, delta_bpm: i64, day: u64,
        ) -> ByteArray {
            round_byte_array(species, mega, seed, drift_of(drift_on, rhythm, rotate, day_knob, delta_bpm, day))
        }
    }
    #[abi(embed_v0)]
    impl C of super::IChecksProbe<ContractState> {
        fn sound_check(self: @ContractState, species: u32, mega: bool, take: u64) -> ByteArray {
            sound_check_byte_array(species, mega, take)
        }
    }
}

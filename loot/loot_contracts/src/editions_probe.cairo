//! THROWAWAY CASM probe: a contract exposing only the Loot editions entry point, to measure its
//! class size (target/dev/loot_contracts_EditionsProbe.compiled_contract_class.json). Not a
//! deployment target; remove once the composer class exists.
#[starknet::interface]
pub trait IEditionsProbe<T> {
    fn edition(
        self: @T,
        species: u32,
        mega: bool,
        e: u32,
        seed: u64,
        rhythm: Option<felt252>,
        rotate: Option<felt252>,
        day_knob: u8,
        delta_bpm: i64,
        day: u64,
        drift: bool,
    ) -> ByteArray;
}

#[starknet::contract]
pub mod EditionsProbe {
    use beast_composer::composition::drift::Drift;
    use loot_composer::editions::edition_byte_array;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl EditionsProbeImpl of super::IEditionsProbe<ContractState> {
        fn edition(
            self: @ContractState,
            species: u32,
            mega: bool,
            e: u32,
            seed: u64,
            rhythm: Option<felt252>,
            rotate: Option<felt252>,
            day_knob: u8,
            delta_bpm: i64,
            day: u64,
            drift: bool,
        ) -> ByteArray {
            let d = if drift {
                Option::Some(Drift { rhythm, rotate, day_knob, delta_bpm, day })
            } else {
                Option::None
            };
            edition_byte_array(species, mega, e, seed, d)
        }
    }
}

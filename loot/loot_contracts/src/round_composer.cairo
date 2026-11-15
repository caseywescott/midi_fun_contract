//! `LootRoundComposer`: Rounds and Sound Checks of the Loot Beasts, as the lab plays them (Rounds
//! lifted a fifth; each channel's instrument from the family's round band).
#[starknet::contract]
pub mod LootRoundComposer {
    use beast_composer::composition::drift::{DriftClock, layered_drift};
    use loot_composer::checks::sound_check_played_byte_array;
    use loot_composer::common::purchase_seed;
    use loot_composer::orchestra::round_band;
    use loot_composer::rounds::{Play, round_played_byte_array};
    use loot_composer::species::loot_species;
    use crate::interfaces::ILootRoundComposer;

    #[storage]
    struct Storage {}

    fn seed_of(purchase: u64) -> u64 {
        if purchase == 0 {
            0
        } else {
            purchase_seed(purchase)
        }
    }

    #[abi(embed_v0)]
    impl RoundImpl of ILootRoundComposer<ContractState> {
        fn round(
            self: @ContractState, species: u32, mega: bool, purchase: u64, drift: Option<DriftClock>,
        ) -> ByteArray {
            // the lab's drift: none on day 1
            let d = match drift {
                Option::Some(c) => if c.day >= 2 {
                    Option::Some(layered_drift(species.into(), 0, 0, c))
                } else {
                    Option::None
                },
                Option::None => Option::None,
            };
            let b = round_band(loot_species(species).beast_type, species, d);
            round_played_byte_array(species, mega, seed_of(purchase), d, Play { band: b.span(), lift: 7 })
        }

        fn sound_check(self: @ContractState, species: u32, mega: bool, take: u64) -> ByteArray {
            let b = round_band(loot_species(species).beast_type, species, Option::None);
            sound_check_played_byte_array(species, mega, seed_of(take), Play { band: b.span(), lift: 0 })
        }
    }
}

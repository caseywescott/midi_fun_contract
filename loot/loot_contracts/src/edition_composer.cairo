//! `LootEditionComposer`: Monthly Track Editions of the Loot Beasts, orchestrated with the lab's
//! band (a class of its own: the edition engine is about 37k CASM felts).
#[starknet::contract]
pub mod LootEditionComposer {
    use beast_composer::composition::drift::{DriftClock, layered_drift};
    use loot_composer::common::purchase_seed;
    use loot_composer::editions::edition_played_byte_array;
    use loot_composer::orchestra::band;
    use loot_composer::orchestra_data::STYLE_COUNT;
    use crate::interfaces::ILootEditionComposer;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl EditionImpl of ILootEditionComposer<ContractState> {
        fn edition(
            self: @ContractState,
            species: u32,
            mega: bool,
            edition: u32,
            purchase: u64,
            drift: Option<DriftClock>,
        ) -> ByteArray {
            assert(edition >= 1, 'editions start at 1');
            assert(purchase >= 1 && purchase < 0x100000000, 'purchase 1..2^32');
            // the lab's drift: none on day 1
            let d = match drift {
                Option::Some(c) => if c.day >= 2 {
                    Option::Some(layered_drift(species.into(), 0, 0, c))
                } else {
                    Option::None
                },
                Option::None => Option::None,
            };
            // the band's instruments are written in place (the same file as orchestrate, a third
            // less gas)
            let b = band((edition - 1) % STYLE_COUNT, species, edition, purchase.try_into().unwrap(), d);
            edition_played_byte_array(species, mega, edition, purchase_seed(purchase), d, b.span())
        }
    }
}

//! `LootSongComposer`: Species and Name Songs of the Loot Beasts, orchestrated (a class of its own:
//! the Beasts composer's Genesis path alone is most of a class).
#[starknet::contract]
pub mod LootSongComposer {
    use beast_composer::composition::drift::{DriftClock, layered_drift};
    use loot_composer::orchestra::{orchestrate, song_band};
    use loot_composer::songs::song_bytes;
    use loot_composer::species::loot_species;
    use midi::pack::bytes_to_byte_array;
    use crate::interfaces::ILootSongComposer;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl SongImpl of ILootSongComposer<ContractState> {
        fn song(
            self: @ContractState, species: u32, mega: bool, name: u16, drift: Option<DriftClock>,
        ) -> ByteArray {
            let midi = song_bytes(species, mega, name, drift);
            // the lab drifts a Species Song's band, not a Name Song's
            let d = match drift {
                Option::Some(c) => if name == 0 && c.day >= 2 {
                    Option::Some(layered_drift(species.into(), 0, 0, c))
                } else {
                    Option::None
                },
                Option::None => Option::None,
            };
            let band = song_band(loot_species(species).beast_type, species, d);
            let lift = if name == 0 {
                0
            } else {
                12
            };
            bytes_to_byte_array(orchestrate(midi.span(), band.span(), lift).span())
        }
    }
}

//! `LootPureComposer`: the Loot composer, one storage-free class in the pattern of Beast Sound v1.1.0's
//! `BeastPureComposer`. A provider (or manager) owns tokens, purchases and block hashes; this class
//! turns one track's inputs, played with a token's `sound_effects` (and with drift, the day), into
//! the file the Loot lab plays: Monthly Track Editions, Rounds and Sound Checks, each channel's
//! instrument from the lab's band (`loot_composer::orchestra`, the Loot analogue of v1.1's synth
//! settings) and Rounds lifted a fifth, all written in place. Songs are the Beast composer's: a
//! `Song` reverts here (`LootMidiProvider` plays them through the pinned `BeastPureComposer`).
use beast_composer::composition::drift::{Drift, DriftClock, layered_drift};
use beast_composer::inputs::drift::DriftInputs;
use loot_composer::checks::sound_check_played_byte_array;
use loot_composer::common::purchase_seed;
use loot_composer::editions::edition_played_byte_array;
use loot_composer::orchestra::{band, round_band};
use loot_composer::orchestra_data::STYLE_COUNT;
use loot_composer::rounds::{Play, round_played_byte_array};
use loot_composer::species::loot_species;
use crate::interfaces::LootInputs;

/// The mega sound of a token's `sound_effects` (v1.1: 1 and 3); 4 and up revert.
pub fn mega_of(sound_effects: u8) -> bool {
    assert(sound_effects <= 3, 'invalid sound effects');
    sound_effects == 1 || sound_effects == 3
}

/// The lab's drift of Loot Beast `species` on the day of `drift`: none on day 1 (as written).
#[inline(never)]
pub fn loot_drift(species: u32, drift: Option<DriftInputs>) -> Option<Drift> {
    match drift {
        Option::Some(d) => if d.day >= 2 {
            Option::Some(
                layered_drift(
                    species.into(),
                    0,
                    0,
                    DriftClock {
                        day: d.day, day_hash: d.day_hash, week_hash: d.week_hash, month_hash: d.month_hash,
                    },
                ),
            )
        } else {
            Option::None
        },
        Option::None => Option::None,
    }
}

fn seed_of(purchase: u64) -> u64 {
    if purchase == 0 {
        0
    } else {
        purchase_seed(purchase)
    }
}

/// A Round (with its day of drift) or a Sound Check (none) as the lab plays it: one body for both
/// (CASM size).
#[inline(never)]
fn round_or_check(species: u32, mega: bool, purchase: u64, d: Option<Drift>, round: bool) -> ByteArray {
    let b = round_band(loot_species(species).beast_type, species, d);
    if round {
        round_played_byte_array(species, mega, seed_of(purchase), d, Play { band: b.span(), lift: 7 })
    } else {
        sound_check_played_byte_array(species, mega, seed_of(purchase), Play { band: b.span(), lift: 0 })
    }
}

/// `compose`, and with a day `compose_drift`: one body for both (CASM size).
#[inline(never)]
pub fn compose_with(inputs: LootInputs, sound_effects: u8, drift: Option<DriftInputs>) -> ByteArray {
    let mega = mega_of(sound_effects);
    match inputs {
        LootInputs::Edition(x) => {
            assert(x.edition >= 1, 'editions start at 1');
            assert(x.purchase >= 1 && x.purchase < 0x100000000, 'purchase 1..2^32');
            let d = loot_drift(x.species, drift);
            let p: u32 = x.purchase.try_into().unwrap();
            let b = band((x.edition - 1) % STYLE_COUNT, x.species, x.edition, p, d);
            edition_played_byte_array(
                x.species, mega, x.edition, purchase_seed(x.purchase), d, b.span(), p,
            )
        },
        LootInputs::Round(x) => round_or_check(
            x.species, mega, x.purchase, loot_drift(x.species, drift), true,
        ),
        LootInputs::SoundCheck(x) => round_or_check(x.species, mega, x.take, Option::None, false),
        LootInputs::Song(_) => panic!("songs: BeastPureComposer"),
    }
}

#[starknet::contract]
pub mod LootPureComposer {
    use beast_composer::inputs::drift::DriftInputs;
    use crate::interfaces::{ILootPureComposer, LootInputs};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl PureComposerImpl of ILootPureComposer<ContractState> {
        fn compose(self: @ContractState, inputs: LootInputs, sound_effects: u8) -> ByteArray {
            super::compose_with(inputs, sound_effects, Option::None)
        }

        fn compose_drift(
            self: @ContractState, inputs: LootInputs, sound_effects: u8, drift: DriftInputs,
        ) -> ByteArray {
            super::compose_with(inputs, sound_effects, Option::Some(drift))
        }
    }
}

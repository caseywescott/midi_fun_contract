//! Bench-only contracts: a fixed-bytes MIDI provider for the sound page (group C) and `BenchLib`,
//! which calls library functions inside one entry point so their gas can be read per call
//! (group E). Nothing here is production code.

use beast_composer::composition::beast_v3_sound::PackableBeastV3;

/// An `IMidiProvider` that returns one of the fixed MIDI files in `crate::fixtures` (token ID 0 to
/// 3: 31, 1,406, 4,726 and 7,197 bytes) for any collection. Its bytes are code constants, not
/// storage, so its own cost inside `token_uri` is small and shows as the nested `get_midi_for`.
#[starknet::contract]
pub mod FixedMidiProvider {
    use midi::interfaces::IMidiProvider;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl Provider of IMidiProvider<ContractState> {
        fn get_midi(self: @ContractState, token_id: u256) -> ByteArray {
            crate::fixtures::midi_fixture(token_id)
        }

        fn get_midi_for(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            crate::fixtures::midi_fixture(token_id)
        }
    }
}

/// Library entry points for attribution (group E). Each probe builds its input inside the call and
/// returns the function's output (the test checks it against the expected table); `pack_input`
/// and `b64_input` build the same inputs and return only their length, so `probe - input` is the
/// function plus the serialization of its return value.
#[starknet::interface]
pub trait IBenchLib<T> {
    /// `synthetic(len)` (the bytes `(i * 37 + 11) % 256`), returning its length.
    fn pack_input(self: @T, len: u32) -> u32;
    /// `midi::pack::bytes_to_byte_array(synthetic(len))`.
    fn bytes_to_byte_array(self: @T, len: u32) -> ByteArray;
    /// `midi::pack::to_felt252_array(synthetic(len))`.
    fn to_felt252_array(self: @T, len: u32) -> Array<felt252>;
    /// MIDI fixture `index` (`crate::fixtures::midi_fixture`), returning its length.
    fn b64_input(self: @T, index: u32) -> u32;
    /// `midi_contracts::page::append_base64` of MIDI fixture `index` onto an empty ByteArray.
    fn append_base64(self: @T, index: u32) -> ByteArray;
    /// `midi_contracts::page::midi_html` of MIDI fixture `index`.
    fn midi_html(self: @T, index: u32) -> ByteArray;
    /// `synthetic(len)` returned as it is: `u8_output(len) - pack_input(len)` is the cost of
    /// returning `len` bytes as an `Array<u8>`, which the `genesis_smf_bytes` probe pays on top of
    /// the library.
    fn u8_output(self: @T, len: u32) -> Array<u8>;
    /// `[0, 1, ..., n - 1]` as felts, returning its length.
    fn felt_input(self: @T, n: u32) -> u32;
    /// The same array returned: `felt_output(n)` is what the `genesis_score` probe pays to build
    /// and return its `n`-felt result, `felt_output(n) - felt_input(n)` the return alone.
    fn felt_output(self: @T, n: u32) -> Array<felt252>;
}

/// Stage T0 (and the direct library cost of the Genesis Track): its own contract, as the
/// composer's CASM alone is close to Starknet's class size limit.
#[starknet::interface]
pub trait IBenchGenesis<T> {
    /// `beast_composer::composition::genesis::genesis_smf_bytes(beast)`: the whole Genesis Track,
    /// without the provider's token checks, rank call and packing.
    fn genesis_smf_bytes(self: @T, beast: PackableBeastV3) -> Array<u8>;
}

/// Stage T1.
#[starknet::interface]
pub trait IBenchScore<T> {
    /// The Genesis Track's composer parameters (a copy of the genesis branch of the private
    /// `genesis::compose`) and `beast_v11::build_v11_score_with`, returning the score as
    /// `[section_ticks, event_count, (time, duration, pitch, velocity, voice_id)..., params...]`.
    fn genesis_score(self: @T, beast: PackableBeastV3) -> Array<felt252>;
}

/// `[0, 1, ..., n - 1]`.
pub fn counting(n: u32) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    let mut i: u32 = 0;
    while i < n {
        out.append(i.into());
        i += 1;
    }
    out
}

/// `(i * 37 + 11) % 256` for i in 0..n, as in `midi_contracts`' page tests.
pub fn synthetic(n: u32) -> Array<u8> {
    let mut out: Array<u8> = array![];
    let mut i: u32 = 0;
    while i < n {
        out.append(((i * 37 + 11) % 256).try_into().unwrap());
        i += 1;
    }
    out
}

#[starknet::contract]
pub mod BenchLib {
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl BenchLibImpl of super::IBenchLib<ContractState> {
        fn pack_input(self: @ContractState, len: u32) -> u32 {
            super::synthetic(len).len()
        }

        fn bytes_to_byte_array(self: @ContractState, len: u32) -> ByteArray {
            midi::pack::bytes_to_byte_array(super::synthetic(len).span())
        }

        fn to_felt252_array(self: @ContractState, len: u32) -> Array<felt252> {
            midi::pack::to_felt252_array(super::synthetic(len).span())
        }

        fn b64_input(self: @ContractState, index: u32) -> u32 {
            crate::fixtures::midi_fixture(index.into()).len()
        }

        fn append_base64(self: @ContractState, index: u32) -> ByteArray {
            let input = crate::fixtures::midi_fixture(index.into());
            let mut out: ByteArray = Default::default();
            midi_contracts::page::append_base64(ref out, @input);
            out
        }

        fn midi_html(self: @ContractState, index: u32) -> ByteArray {
            midi_contracts::page::midi_html(@crate::fixtures::midi_fixture(index.into()))
        }

        fn u8_output(self: @ContractState, len: u32) -> Array<u8> {
            super::synthetic(len)
        }

        fn felt_input(self: @ContractState, n: u32) -> u32 {
            super::counting(n).len()
        }

        fn felt_output(self: @ContractState, n: u32) -> Array<felt252> {
            super::counting(n)
        }
    }
}

#[starknet::contract]
pub mod BenchGenesis {
    use beast_composer::composition::beast_v3_sound::PackableBeastV3;
    use beast_composer::composition::genesis::genesis_smf_bytes;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl BenchGenesisImpl of super::IBenchGenesis<ContractState> {
        fn genesis_smf_bytes(self: @ContractState, beast: PackableBeastV3) -> Array<u8> {
            genesis_smf_bytes(beast)
        }
    }
}

#[starknet::contract]
pub mod BenchScore {
    use beast_composer::composition::beast_v11::{V11Override, build_v11_score_with};
    use beast_composer::composition::beast_v3_sound::{
        PackableBeastV3, map_v3_beast_to_composition_params,
    };
    use beast_composer::composition::genesis::{
        genesis_mode, genesis_swap, genesis_theme, named_mode_scale, neutral_live, species_tier,
        species_type,
    };

    #[storage]
    struct Storage {}

    /// Copy of the private `genesis::tier_sections`.
    fn tier_sections(tier: u8) -> u8 {
        if tier <= 2 {
            4
        } else if tier == 3 {
            3
        } else {
            2
        }
    }

    #[abi(embed_v0)]
    impl BenchScoreImpl of super::IBenchScore<ContractState> {
        fn genesis_score(self: @ContractState, beast: PackableBeastV3) -> Array<felt252> {
            // `genesis::compose(beast, 0, 0, 0, None)` up to `build_v11_score_with`: no name, no
            // seed, no drift.
            let src = genesis_swap(beast.id);
            let (tier, beast_type) = if src >= 1 && src <= 75 {
                (species_tier(src), species_type(src))
            } else {
                (beast.tier, beast.beast_type)
            };
            let g = PackableBeastV3 {
                id: src,
                prefix: 0,
                suffix: 0,
                level: 50,
                health: 200,
                shiny: 0,
                animated: 0,
                tier,
                beast_type,
            };
            let live = neutral_live();
            let motif = genesis_theme(src);
            let cb = if motif > 0 {
                PackableBeastV3 {
                    prefix: ((motif - 1) / 18 + 1).try_into().unwrap(),
                    suffix: ((motif - 1) % 18 + 1).try_into().unwrap(),
                    ..g,
                }
            } else {
                g
            };
            let pg = map_v3_beast_to_composition_params(g, live);
            let spread = PackableBeastV3 {
                prefix: ((src - 1) % 69 + 1).try_into().unwrap(),
                suffix: ((src - 1) % 18 + 1).try_into().unwrap(),
                ..g,
            };
            let ks = map_v3_beast_to_composition_params(spread, live);
            let mode = genesis_mode(src, ks.mode_id);
            let ov = V11Override {
                voice_count: Option::Some(4),
                section_count: Option::Some(tier_sections(tier)),
                mode_id: Option::Some(mode),
                tonic_keynum: Option::Some(ks.tonic_keynum),
                register_band: Option::Some(ks.register_band),
                ornament_density: Option::Some(pg.ornament_density),
                name_variant_id: Option::Some(0),
                use_countersubject: Option::Some(true),
                scale: named_mode_scale(mode),
                trill: Option::Some(false),
                rhythm_seed: Option::None,
                flip_side: Option::None,
                development: Option::None,
                direction: Option::None,
                spacing: Option::None,
            };
            let score = build_v11_score_with(cb, live, ov);
            let mut out: Array<felt252> = array![
                score.section_ticks.into(), score.events.len().into(),
            ];
            for e in score.events.span() {
                out.append((*e).time.into());
                out.append((*e).duration.into());
                out.append((*e).pitch.into());
                out.append((*e).velocity.into());
                out.append((*e).voice_id.into());
            }
            score.params.serialize(ref out);
            out
        }
    }
}

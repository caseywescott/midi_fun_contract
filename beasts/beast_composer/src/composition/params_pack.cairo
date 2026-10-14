//! The composer inputs (`BeastCompositionParams` and the shiny and animated flags) packed into one
//! felt, so a Beast (or a track) can store what the composer needs and compose without decoding a
//! token ID.
//!
//! Lossless: `unpack_inputs(pack_inputs(x))` is `x` field for field, so a stored felt composes the
//! same bytes as the params it came from. `pack_inputs` rejects a field that does not fit its width
//! instead of truncating it.
//!
//! Layout v1, from the low bit (177 of the felt's 251 bits; the rest is free for later fields):
//!
//! | bits    | width | field                 | range today                               |
//! |---------|-------|-----------------------|-------------------------------------------|
//! | 0-3     | 4     | layout version (1)    |                                           |
//! | 4-67    | 64    | species_id            | the token's own width (V3 ids are u64)    |
//! | 68-78   | 11    | name_variant_id       | 0..1242                                   |
//! | 79-83   | 5     | mode_id               | 0..30 (`mode_to_id`)                      |
//! | 84-90   | 7     | tonic_keynum          | 0..127                                    |
//! | 91-92   | 2     | register_band         | 0..2                                      |
//! | 93-95   | 3     | tier                  | 1..5                                      |
//! | 96-97   | 2     | weakness              | 0..2                                      |
//! | 98-103  | 6     | canon_config_id       | 0..40                                     |
//! | 104-108 | 5     | profile_id            | 0..24                                     |
//! | 109-111 | 3     | voice_count           | 1..4                                      |
//! | 112-115 | 4     | section_count         | 1..5                                      |
//! | 116-118 | 3     | stretto_bucket        | 0..7                                      |
//! | 119-122 | 4     | stretto_lag           | 1..4                                      |
//! | 123     | 1     | use_inversion         |                                           |
//! | 124     | 1     | use_countersubject    |                                           |
//! | 125     | 1     | use_compound_melody   |                                           |
//! | 126-128 | 3     | ornament_density      | 0..7                                      |
//! | 129-131 | 3     | articulation_profile  | 0..5                                      |
//! | 132-138 | 7     | velocity_ceiling      | 0..127                                    |
//! | 139-158 | 20    | tempo_us              | up to 1048575 (57 BPM and faster)         |
//! | 159-174 | 16    | score_version         | set by us, never by callers               |
//! | 175     | 1     | shiny                 | picks the mega sound                      |
//! | 176     | 1     | animated              |                                           |

use crate::composition::beast_trait_map::BeastCompositionParams;
use crate::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, map_v3_beast_to_composition_params,
};

/// What the composer needs to compose a Beast's tracks, without its token ID.
#[derive(Copy, Drop, Serde)]
pub struct ComposerInputs {
    pub params: BeastCompositionParams,
    pub shiny: bool,
    pub animated: bool,
}

/// A Beast's composer inputs at a live state.
pub fn composer_inputs(beast: PackableBeastV3, live: BeastV3LiveState) -> ComposerInputs {
    ComposerInputs {
        params: map_v3_beast_to_composition_params(beast, live),
        shiny: beast.shiny == 1,
        animated: beast.animated == 1,
    }
}

pub const PARAMS_LAYOUT_VERSION: u8 = 1;

// field sizes (2^width)
const W1: u256 = 0x2;
const W2: u256 = 0x4;
const W3: u256 = 0x8;
const W4: u256 = 0x10;
const W5: u256 = 0x20;
const W6: u256 = 0x40;
const W7: u256 = 0x80;
const W11: u256 = 0x800;
const W16: u256 = 0x10000;
const W20: u256 = 0x100000;
const W64: u256 = 0x10000000000000000;
// the same as divisors for `take`
const NW1: NonZero<u256> = 0x2;
const NW2: NonZero<u256> = 0x4;
const NW3: NonZero<u256> = 0x8;
const NW4: NonZero<u256> = 0x10;
const NW5: NonZero<u256> = 0x20;
const NW6: NonZero<u256> = 0x40;
const NW7: NonZero<u256> = 0x80;
const NW11: NonZero<u256> = 0x800;
const NW16: NonZero<u256> = 0x10000;
const NW20: NonZero<u256> = 0x100000;
const NW64: NonZero<u256> = 0x10000000000000000;

/// Appends `value` in the next field, `size` = 2^width.
fn put(ref acc: u256, ref shift: u256, value: u256, size: u256) {
    assert(value < size, 'param too wide');
    acc += value * shift;
    shift *= size;
}

/// Takes the next field, `size` = 2^width.
// A NonZero size, so `take` cannot panic, and out of line: otherwise each of unpack_inputs' 24
// calls adds a panic exit there, and every exit writes the whole ComposerInputs (CASM size).
#[inline(never)]
fn take(ref rest: u256, size: NonZero<u256>) -> u256 {
    let (q, v) = DivRem::div_rem(rest, size);
    rest = q;
    v
}

fn bit(b: bool) -> u256 {
    if b {
        1
    } else {
        0
    }
}

pub fn pack_inputs(x: ComposerInputs) -> felt252 {
    let p = x.params;
    let mut acc: u256 = 0;
    let mut shift: u256 = 1;
    put(ref acc, ref shift, PARAMS_LAYOUT_VERSION.into(), W4);
    put(ref acc, ref shift, p.species_id.into(), W64);
    put(ref acc, ref shift, p.name_variant_id.into(), W11);
    put(ref acc, ref shift, p.mode_id.into(), W5);
    put(ref acc, ref shift, p.tonic_keynum.into(), W7);
    put(ref acc, ref shift, p.register_band.into(), W2);
    put(ref acc, ref shift, p.tier.into(), W3);
    put(ref acc, ref shift, p.weakness.into(), W2);
    put(ref acc, ref shift, p.canon_config_id.into(), W6);
    put(ref acc, ref shift, p.profile_id.into(), W5);
    put(ref acc, ref shift, p.voice_count.into(), W3);
    put(ref acc, ref shift, p.section_count.into(), W4);
    put(ref acc, ref shift, p.stretto_bucket.into(), W3);
    put(ref acc, ref shift, p.stretto_lag.into(), W4);
    put(ref acc, ref shift, bit(p.use_inversion), W1);
    put(ref acc, ref shift, bit(p.use_countersubject), W1);
    put(ref acc, ref shift, bit(p.use_compound_melody), W1);
    put(ref acc, ref shift, p.ornament_density.into(), W3);
    put(ref acc, ref shift, p.articulation_profile.into(), W3);
    put(ref acc, ref shift, p.velocity_ceiling.into(), W7);
    put(ref acc, ref shift, p.tempo_us.into(), W20);
    put(ref acc, ref shift, p.score_version.into(), W16);
    put(ref acc, ref shift, bit(x.shiny), W1);
    put(ref acc, ref shift, bit(x.animated), W1);
    acc.try_into().unwrap()
}

pub fn unpack_inputs(packed: felt252) -> ComposerInputs {
    let mut rest: u256 = packed.into();
    assert(take(ref rest, NW4) == PARAMS_LAYOUT_VERSION.into(), 'unknown params layout');
    let species_id = take(ref rest, NW64).try_into().unwrap();
    let name_variant_id = take(ref rest, NW11).try_into().unwrap();
    let mode_id = take(ref rest, NW5).try_into().unwrap();
    let tonic_keynum = take(ref rest, NW7).try_into().unwrap();
    let register_band = take(ref rest, NW2).try_into().unwrap();
    let tier = take(ref rest, NW3).try_into().unwrap();
    let weakness = take(ref rest, NW2).try_into().unwrap();
    let canon_config_id = take(ref rest, NW6).try_into().unwrap();
    let profile_id = take(ref rest, NW5).try_into().unwrap();
    let voice_count = take(ref rest, NW3).try_into().unwrap();
    let section_count = take(ref rest, NW4).try_into().unwrap();
    let stretto_bucket = take(ref rest, NW3).try_into().unwrap();
    let stretto_lag = take(ref rest, NW4).try_into().unwrap();
    let use_inversion = take(ref rest, NW1) == 1;
    let use_countersubject = take(ref rest, NW1) == 1;
    let use_compound_melody = take(ref rest, NW1) == 1;
    let ornament_density = take(ref rest, NW3).try_into().unwrap();
    let articulation_profile = take(ref rest, NW3).try_into().unwrap();
    let velocity_ceiling = take(ref rest, NW7).try_into().unwrap();
    let tempo_us = take(ref rest, NW20).try_into().unwrap();
    let score_version = take(ref rest, NW16).try_into().unwrap();
    let shiny = take(ref rest, NW1) == 1;
    let animated = take(ref rest, NW1) == 1;
    assert(rest == 0, 'unknown params bits');
    let params = BeastCompositionParams {
        species_id,
        name_variant_id,
        mode_id,
        tonic_keynum,
        register_band,
        tier,
        weakness,
        canon_config_id,
        profile_id,
        voice_count,
        section_count,
        stretto_bucket,
        stretto_lag,
        use_inversion,
        use_countersubject,
        use_compound_melody,
        ornament_density,
        articulation_profile,
        velocity_ceiling,
        tempo_us,
        score_version,
    };
    ComposerInputs { params, shiny, animated }
}

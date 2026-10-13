//! A Beast's tracks, composed from its stored composer inputs (`params_pack`), not its token ID.
//!
//! Track numbers (provisional, until the multi-track interface lands):
//!   0  Sound Check         the Beast's scale through each of its presets (one per Beast)
//!   1  Species Song        the Genesis Track: every Beast of a species shares it (default swaps)
//!   2  Beast Special Song  the name track: the species' theme in the name's key and style;
//!                          a Beast without a special name plays its Species Song
//!   3+ bought tracks       seeded by a block hash (not composed yet)
//! Shiny adds the mega sound to every track.

use crate::composition::beast_trait_map::{WEAKNESS_BLADE, WEAKNESS_MAGIC};
use crate::composition::beast_v3_sound::{
    BEAST_TYPE_BRUTE, BEAST_TYPE_HUNTER, BEAST_TYPE_MAGIC, PackableBeastV3,
};
use crate::composition::genesis::{genesis_smf_bytes, name_track_smf_bytes};
use crate::composition::params_pack::{ComposerInputs, unpack_inputs};
use crate::composition::sound_check::sound_check_smf_bytes;

pub const TRACK_SOUND_CHECK: u32 = 0;
pub const TRACK_SPECIES_SONG: u32 = 1;
pub const TRACK_SPECIAL_SONG: u32 = 2;

/// The Beast the composer sees, rebuilt from its inputs: species, special name, tier, type (the
/// params' weakness is the type's section relation) and the visual flags. Level and health are not
/// needed: the songs compose with the Genesis level and health.
pub fn beast_of(x: ComposerInputs) -> PackableBeastV3 {
    let p = x.params;
    let (prefix, suffix): (u8, u8) = if p.name_variant_id == 0 {
        (0, 0)
    } else {
        let i = p.name_variant_id - 1;
        ((i / 18 + 1).try_into().unwrap(), (i % 18 + 1).try_into().unwrap())
    };
    let beast_type = if p.weakness == WEAKNESS_MAGIC {
        BEAST_TYPE_MAGIC
    } else if p.weakness == WEAKNESS_BLADE {
        BEAST_TYPE_HUNTER
    } else {
        BEAST_TYPE_BRUTE
    };
    PackableBeastV3 {
        id: p.species_id,
        prefix,
        suffix,
        level: 1,
        health: 100,
        shiny: if x.shiny {
            1
        } else {
            0
        },
        animated: if x.animated {
            1
        } else {
            0
        },
        tier: p.tier,
        beast_type,
    }
}

/// Track `track` of the Beast whose composer inputs are `packed`, as a self-contained MIDI file.
pub fn track_smf_bytes(packed: felt252, track: u32) -> Array<u8> {
    let beast = beast_of(unpack_inputs(packed));
    if track == TRACK_SPECIES_SONG {
        return genesis_smf_bytes(beast);
    }
    if track == TRACK_SPECIAL_SONG {
        if beast.prefix == 0 {
            return genesis_smf_bytes(beast);
        }
        return name_track_smf_bytes(beast, beast.prefix, beast.suffix);
    }
    if track == TRACK_SOUND_CHECK {
        return sound_check_smf_bytes(beast);
    }
    panic!("bought tracks not composed yet")
}

/// The same, packed 31 bytes per felt after the byte length.
pub fn track_midi(packed: felt252, track: u32) -> Array<felt252> {
    midi::pack::to_felt252_array(track_smf_bytes(packed, track).span())
}

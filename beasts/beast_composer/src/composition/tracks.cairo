//! A Beast's tracks, composed from its stored composer inputs (`params_pack`), not its token ID.
//!
//! Track numbers (provisional, until the multi-track interface lands):
//!   0  Sound Check         the Beast's scale through each of its presets (one per Beast)
//!   1  Species Song        the Genesis Track: every Beast of a species shares it (default swaps)
//!   2  Beast Special Song  the name track: the species' theme in the name's key and style;
//!                          a Beast without a special name plays its Species Song
//!   3+ bought tracks       the track's seed (a block hash, stored with the track) on the Beast's
//!                          key and the species' theme
//! Shiny adds the mega sound to every track.

use crate::composition::beast_trait_map::{WEAKNESS_BLADE, WEAKNESS_MAGIC};
use crate::composition::beast_v3_sound::{
    BEAST_TYPE_BRUTE, BEAST_TYPE_HUNTER, BEAST_TYPE_MAGIC, PackableBeastV3,
};
use crate::composition::drift::DriftClock;
use crate::composition::genesis::song_smf_bytes;
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
/// `seed` is a bought track's seed (tracks 3+; ignored by tracks 0-2); `drift` the day of drift
/// to play (`drift.cairo`; none = as written; the Sound Check never drifts).
pub fn track_smf_bytes(
    packed: felt252, track: u32, seed: felt252, drift: Option<DriftClock>,
) -> Array<u8> {
    beast_track_smf_bytes(beast_of(unpack_inputs(packed)), track, seed, drift)
}

/// The same track of `beast` itself: `track_smf_bytes` of its composer inputs, without packing
/// them. The songs compose from the species, special name, tier, type and shiny flag alone, so a
/// Beast and its unpacked inputs (`beast_of`) give the same file.
pub fn beast_track_smf_bytes(
    beast: PackableBeastV3, track: u32, seed: felt252, drift: Option<DriftClock>,
) -> Array<u8> {
    if track == TRACK_SOUND_CHECK {
        return sound_check_smf_bytes(beast);
    }
    if track == TRACK_SPECIES_SONG || (track == TRACK_SPECIAL_SONG && beast.prefix == 0) {
        return song_smf_bytes(beast, 0, 0, 0, drift);
    }
    if track == TRACK_SPECIAL_SONG {
        return song_smf_bytes(beast, beast.prefix, beast.suffix, 0, drift);
    }
    assert(seed != 0, 'bought track needs a seed');
    song_smf_bytes(beast, beast.prefix, beast.suffix, seed, drift)
}

/// The same, packed 31 bytes per felt after the byte length.
pub fn track_midi(
    packed: felt252, track: u32, seed: felt252, drift: Option<DriftClock>,
) -> Array<felt252> {
    midi::pack::to_felt252_array(track_smf_bytes(packed, track, seed, drift).span())
}

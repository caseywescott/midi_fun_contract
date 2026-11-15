//! Species Songs and Name Songs of the Loot Beasts: the Beasts composer at midi_fun_contract v1.0.1,
//! unchanged (`genesis::song_smf_bytes`, which composes species past 75 with their own tier, family
//! and theme), called as the Loot lab calls `sampleTrackMidi` (level 1, health 100, the Genesis
//! defaults; a day of drift with block hashes from day 2).

use beast_composer::composition::beast_v3_sound::PackableBeastV3;
use beast_composer::composition::drift::DriftClock;
use beast_composer::composition::genesis::song_smf_bytes;
use crate::species::loot_species;

/// A special name's prefix and suffix from its variant number (lab.js `nameFromVariant`).
pub fn name_from_variant(n: u16) -> (u8, u8) {
    if n == 0 {
        (0, 0)
    } else {
        (((n - 1) / 18 + 1).try_into().unwrap(), ((n - 1) % 18 + 1).try_into().unwrap())
    }
}

fn beast(species: u32, mega: bool, prefix: u8, suffix: u8) -> PackableBeastV3 {
    let s = loot_species(species);
    PackableBeastV3 {
        id: species.into(),
        prefix,
        suffix,
        level: 1,
        health: 100,
        shiny: if mega {
            1
        } else {
            0
        },
        animated: 0,
        tier: s.tier,
        beast_type: s.beast_type,
    }
}

/// A Loot Beast's song: its Species Song (`name` 0) or a Name Song (special-name variant 1..1242),
/// as written (`drift` none) or on a day of drift (day >= 2: the lab plays day 1 as written).
pub fn song_bytes(species: u32, mega: bool, name: u16, drift: Option<DriftClock>) -> Array<u8> {
    let (prefix, suffix) = name_from_variant(name);
    let clock = match drift {
        Option::Some(c) => if c.day >= 2 {
            Option::Some(c)
        } else {
            Option::None
        },
        Option::None => Option::None,
    };
    song_smf_bytes(beast(species, mega, prefix, suffix), prefix, suffix, 0, clock)
}

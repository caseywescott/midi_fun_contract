//! Loot Survivor Beast trait mapping for canonical dark key cells.

use koji::composition::counterpoint::mode_to_id;
use koji::midi::modes::{dark_mode_at, dark_mode_count};
use koji::midi::types::Modes;

pub const BEAST_PREFIX_COUNT: u8 = 69;
pub const BEAST_SPECIES_COUNT: u8 = 75;
pub const REGISTER_LOW: u8 = 0;
pub const REGISTER_MID: u8 = 1;
pub const REGISTER_HIGH: u8 = 2;

#[derive(Copy, Drop, Serde)]
pub struct BeastKeyCell {
    pub canonical_mode_id: u8,
    pub mode: Modes,
    pub tonic_pc: u8,
    pub register_band: u8,
}

/// Map an affix prefix to the canonical dark palette, tonic pitch class, and register band.
pub fn prefix_to_dark_key(prefix_id: u8) -> BeastKeyCell {
    assert(prefix_id < BEAST_PREFIX_COUNT, 'invalid beast prefix');
    let mode = dark_mode_at(prefix_id % dark_mode_count());
    BeastKeyCell {
        canonical_mode_id: mode_to_id(mode),
        mode,
        tonic_pc: prefix_id % 12,
        register_band: (prefix_id / 12) % 3,
    }
}

/// Bare-name Beasts keep the Phrygian default and derive a bounded register from tier.
pub fn bare_name_dark_key(species_id: u8, tier: u8) -> BeastKeyCell {
    assert(species_id < BEAST_SPECIES_COUNT, 'invalid beast species');
    assert(tier >= 1 && tier <= 5, 'invalid beast tier');
    let mode = Modes::Phrygian(());
    let register_band = if tier <= 2 {
        REGISTER_LOW
    } else if tier <= 4 {
        REGISTER_MID
    } else {
        REGISTER_HIGH
    };
    BeastKeyCell {
        canonical_mode_id: mode_to_id(mode),
        mode,
        tonic_pc: species_id % 12,
        register_band,
    }
}

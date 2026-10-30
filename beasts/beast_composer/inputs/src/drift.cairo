//! A track's day of drift, as the manager reads it: the layered drift (`beast_composer`
//! `drift.cairo`) changes a track a little each day (the day's knob), week (its channel order) and
//! month (its rhythm cells), each seeded by the hash of its own first block, so a day cannot be
//! heard before its block exists. Nothing accumulates: a day's version is a pure function of the
//! track, the day and those three hashes.
//!
//! Days: day d is the epoch d - 1 of DRIFT_EPOCH_BLOCKS blocks; the day at block B is
//! (B - 10) / DRIFT_EPOCH_BLOCKS + 1, so its first block's hash is readable (get_block_hash reads
//! blocks at least 10 behind).

/// About a day at 2-second blocks (a placeholder until the chain's block time is confirmed).
pub const DRIFT_EPOCH_BLOCKS: u64 = 43200;

/// What `compose_drift` needs for one day: the special name the drift belongs to (0 for a Species
/// Song, whose drift all Beasts of the species share; the Beast's special name for its other
/// tracks), the day (from 1) and the hashes of the first blocks of its day, week and month
/// (`drift_anchor_blocks`).
#[derive(Copy, Drop, Debug, Serde, PartialEq)]
pub struct DriftInputs {
    pub name_variant_id: u16,
    pub day: u64,
    pub day_hash: felt252,
    pub week_hash: felt252,
    pub month_hash: felt252,
}

/// The day (from 1) at block `block`.
pub fn day_at_block(block: u64) -> u64 {
    if block < 10 {
        1
    } else {
        (block - 10) / DRIFT_EPOCH_BLOCKS + 1
    }
}

/// The blocks whose hashes day `day` needs: the first blocks of its day, its week and its month.
pub fn drift_anchor_blocks(day: u64) -> (u64, u64, u64) {
    assert(day >= 1, 'days count from 1');
    let week = (day - 1) / 7;
    let month = (day - 1) / 30;
    ((day - 1) * DRIFT_EPOCH_BLOCKS, week * 7 * DRIFT_EPOCH_BLOCKS, month * 30 * DRIFT_EPOCH_BLOCKS)
}

pub fn validate_drift(x: DriftInputs) {
    assert(x.day >= 1, 'days count from 1');
    assert(x.name_variant_id <= 1242, 'invalid drift name');
}

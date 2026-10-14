//! Drift: a track changes a little with time, seeded by block hashes so a future day cannot be
//! heard before its block exists. The layered drift of the lab (`drift2` with block hashes,
//! offchain/beast-sound/src/lab.js), byte-identical through `sampleTrackMidi`:
//!   month (30 days)  new rhythm cells, two months in three (the first month plays as written)
//!   week (7 days)    the channels that play rotate, three weeks in four (same count)
//!   day              one knob: the key plan the other way, the episodes' direction swapped, or the
//!                    tempo nudged -4, -2, +2 or +4 BPM
//! Each clock mixes in the hash of its own first block. Nothing accumulates: a day's version is a
//! pure function of the track, the day and those three hashes.
//!
//! Epochs: an epoch is DRIFT_EPOCH_BLOCKS blocks; epoch e starts at block e * N, and the epoch at
//! block B is (B - 10) / N, so its first block's hash is readable (get_block_hash reads blocks at
//! least 10 behind). Day d is epoch d - 1. The sound modes pick the block: live = the current
//! block, original = the block the track was produced in, a specific block = any block up to the
//! current one.

use core::poseidon::poseidon_hash_span;

/// About a day at 2-second blocks (a placeholder until the chain's block time is confirmed).
pub const DRIFT_EPOCH_BLOCKS: u64 = 43200;

/// The drift epoch at block `block`.
pub fn epoch_at_block(block: u64) -> u64 {
    if block < 10 {
        0
    } else {
        (block - 10) / DRIFT_EPOCH_BLOCKS
    }
}

pub fn epoch_first_block(epoch: u64) -> u64 {
    epoch * DRIFT_EPOCH_BLOCKS
}

/// The day (1-based) at block `block`.
pub fn day_at_block(block: u64) -> u64 {
    epoch_at_block(block) + 1
}

/// The blocks whose hashes day `day` needs: the first blocks of its day, week and month.
pub fn drift_anchor_blocks(day: u64) -> (u64, u64, u64) {
    assert(day >= 1, 'days count from 1');
    let week = (day - 1) / 7;
    let month = (day - 1) / 30;
    (epoch_first_block(day - 1), epoch_first_block(week * 7), epoch_first_block(month * 30))
}

/// A day of drift: the day and the hashes of the first blocks of its day, week and month
/// (`drift_anchor_blocks`).
#[derive(Copy, Drop, Serde)]
pub struct DriftClock {
    pub day: u64,
    pub day_hash: felt252,
    pub week_hash: felt252,
    pub month_hash: felt252,
}

/// What a day of drift changes.
#[derive(Copy, Drop)]
pub struct Drift {
    /// New rhythm cells (the month's), or none.
    pub rhythm: Option<felt252>,
    /// The seed that orders the channels (the week's), or none.
    pub rotate: Option<felt252>,
    /// 0 key plan the other way, 1 episodes swapped, 2-5 tempo -4, -2, +2, +4 BPM.
    pub day_knob: u8,
    pub delta_bpm: i64,
}

fn low32(x: felt252) -> u64 {
    let w: u256 = x.into();
    (w % 0x100000000).try_into().unwrap()
}

/// The layered drift of a Beast (species `id`, special name `prefix`/`suffix`) on a day.
pub fn layered_drift(id: u64, prefix: u8, suffix: u8, clock: DriftClock) -> Drift {
    assert(clock.day >= 1, 'days count from 1');
    let k = poseidon_hash_span(array![id.into(), prefix.into(), suffix.into()].span());
    let month: felt252 = ((clock.day - 1) / 30).into();
    let week: felt252 = ((clock.day - 1) / 7).into();
    let m = low32(poseidon_hash_span(array!['BEAST_DRIFT2_M', k, month, clock.month_hash].span()));
    let w = low32(poseidon_hash_span(array!['BEAST_DRIFT2_W', k, week, clock.week_hash].span()));
    let dk = low32(
        poseidon_hash_span(array!['BEAST_DRIFT2_D', k, clock.day.into(), clock.day_hash].span()),
    ) % 6;
    let rhythm = if month != 0 && m % 3 != 0 {
        Option::Some(
            poseidon_hash_span(array!['BEAST_DRIFT2_RHYTHM', k, month, clock.month_hash].span()),
        )
    } else {
        Option::None
    };
    let rotate = if w % 4 != 0 {
        Option::Some(
            poseidon_hash_span(array!['BEAST_DRIFT2_ROT', k, week, clock.week_hash].span()),
        )
    } else {
        Option::None
    };
    let delta_bpm: i64 = match dk {
        0 => 0,
        1 => 0,
        2 => -4,
        3 => -2,
        4 => 2,
        _ => 4,
    };
    Drift { rhythm, rotate, day_knob: dk.try_into().unwrap(), delta_bpm }
}

/// A tempo (microseconds per quarter) nudged by `delta` BPM: 60e6 / (60e6 / T + delta), rounded
/// half up.
pub fn nudge_tempo(tempo_us: u32, delta: i64) -> u32 {
    let t: i64 = tempo_us.into();
    let d = 60000000 + delta * t;
    ((2 * 60000000 * t + d) / (2 * d)).try_into().unwrap()
}

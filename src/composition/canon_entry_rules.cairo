//! Entry-lag canon rules — constraints from explicit voice entry delays.
//!
//! Generalizes stacked stretto (`entry = voice index`) to arbitrary lags while reusing the same
//! lag-difference identity. See `docs/entry_lag_canon_spec.md`.

use core::array::ArrayTrait;
use koji::composition::canon_rules::{PairConstraint, pair_constraints};

pub const ENTRY_LAG_CONFIG_ID_BASE: u32 = 1000;

/// A canon configuration with explicit per-voice entry delays (in structural notes).
#[derive(Drop, Copy)]
pub struct EntryLagCanonConfig {
    pub config_id: u32,
    pub offsets: Span<i32>,
    pub entries: Span<u32>,
    pub name: felt252,
    pub octave: u32,
    pub profile_id: u32,
}

/// Stacked stretto entries `[0, 1, …, n−1]` — equivalent to legacy `build_voices`.
pub fn entries_stacked(n_voices: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n_voices {
            break;
        }
        out.append(i);
        i += 1;
    };
    out
}

/// Every follower enters after `lag` leader structural notes: `[0, lag, lag, …]`.
pub fn entries_uniform_lag(n_voices: u32, lag: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n_voices {
            break;
        }
        if i == 0 {
            out.append(0);
        } else {
            out.append(lag);
        }
        i += 1;
    };
    out
}

/// Stacked spacing: voice `j` enters after `j * lag` leader notes — `[0, lag, 2·lag, …]`.
pub fn entries_stacked_lag(n_voices: u32, lag: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n_voices {
            break;
        }
        out.append(i * lag);
        i += 1;
    };
    out
}

/// True when `entries[i] == i` for all voices (legacy stacked stretto layout).
pub fn entries_are_stacked(entries: Span<u32>) -> bool {
    let mut i: u32 = 0;
    loop {
        if i >= entries.len() {
            break;
        }
        if *entries.at(i) != i {
            return false;
        }
        i += 1;
    };
    true
}

/// Validate entry vector against voice offsets.
pub fn validate_entries(offsets: Span<i32>, entries: Span<u32>) -> bool {
    if offsets.len() != entries.len() || entries.len() == 0 {
        return false;
    }
    if *entries.at(0) != 0 {
        return false;
    }
    let mut i: u32 = 1;
    loop {
        if i >= entries.len() {
            break;
        }
        if *entries.at(i) < *entries.at(i - 1) {
            return false;
        }
        i += 1;
    };
    true
}

/// Pairwise leader constraints from explicit entry lags: window `w = entries[j] − entries[i]`.
pub fn pair_constraints_from_entries(
    offsets: Span<i32>, entries: Span<u32>,
) -> Array<PairConstraint> {
    let mut out: Array<PairConstraint> = ArrayTrait::new();
    let n = offsets.len();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        let mut j: u32 = i + 1;
        loop {
            if j >= n {
                break;
            }
            let w = *entries.at(j) - *entries.at(i);
            if w > 0 {
                out.append(
                    PairConstraint { d: *offsets.at(j) - *offsets.at(i), w: w },
                );
            }
            j += 1;
        };
        i += 1;
    };
    out
}

/// True when stacked entries yield the same constraints as legacy `pair_constraints`.
pub fn pair_constraints_match_stacked(offsets: Span<i32>) -> bool {
    let stacked = entries_stacked(offsets.len());
    let from_entries = pair_constraints_from_entries(offsets, stacked.span());
    let legacy = pair_constraints(offsets);
    if from_entries.len() != legacy.len() {
        return false;
    }
    let mut i: u32 = 0;
    loop {
        if i >= legacy.len() {
            break;
        }
        let a = *from_entries.at(i);
        let b = *legacy.at(i);
        if a.d != b.d || a.w != b.w {
            return false;
        }
        i += 1;
    };
    true
}

/// Build an entry-lag config from a legacy `CanonConfig` and an explicit entry vector.
pub fn entry_lag_config_from_canon(
    base_config_id: u32,
    base_name: felt252,
    offsets: Span<i32>,
    entries: Span<u32>,
    octave: u32,
    profile_id: u32,
) -> EntryLagCanonConfig {
    assert(validate_entries(offsets, entries), 'bad entry vector');
    EntryLagCanonConfig {
        config_id: ENTRY_LAG_CONFIG_ID_BASE + base_config_id,
        offsets,
        entries,
        name: base_name,
        octave,
        profile_id,
    }
}

/// Two-voice fifth above; follower enters after two leader structural notes.
pub fn config_fifth_above_lag2() -> EntryLagCanonConfig {
    entry_lag_config_from_canon(
        0,
        'fifth_above_lag2',
        array![0_i32, 4].span(),
        entries_uniform_lag(2, 2).span(),
        7,
        0,
    )
}

/// Two-voice fifth below; follower enters after two leader structural notes.
pub fn config_fifth_below_lag2() -> EntryLagCanonConfig {
    entry_lag_config_from_canon(
        1,
        'fifth_below_lag2',
        array![0_i32, -4].span(),
        entries_uniform_lag(2, 2).span(),
        7,
        0,
    )
}

/// Three voices (5th below + octave stack); each voice enters two structural notes after the prior.
pub fn config_three_voice_5b_8va_lag2() -> EntryLagCanonConfig {
    entry_lag_config_from_canon(
        4,
        'three_5b_8va_lag2',
        array![0_i32, -4, 3].span(),
        entries_stacked_lag(3, 2).span(),
        7,
        0,
    )
}

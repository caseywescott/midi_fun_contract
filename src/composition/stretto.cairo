//! Stretto — compressed canon entry times.
//!
//! In a regular exposition, voice j enters at j × lag structural beats.
//! In stretto the lag shrinks, so entries pile on top of one another, creating
//! increasing harmonic density.  This is the sonic signature of "high kill count"
//! in the Beast engine: as `adventurers_defeated_bucket` rises from 0 → 7, the
//! entry lag compresses from `base_lag` down toward `min_lag`.
//!
//! The module provides:
//!   - `StrettoPlan` — parameters for adaptive compression
//!   - `stretto_lag` — bucket → lag (linear interpolation)
//!   - `stretto_entry_times` — per-voice entry times for any voice count
//!   - `stretto_to_note_events` — emits a MelodicCanon with overridden entries
//!   - Validators for the Beast integration layer

use core::array::ArrayTrait;
use koji::composition::melodic_canon::{
    MelodicCanon, NoteEvent, realize_degree, DEFAULT_VELOCITY,
};

// ─────────────────────────────────────────────────────────────
// Plan
// ─────────────────────────────────────────────────────────────

/// Parameters controlling how kill count compresses canon entries.
#[derive(Copy, Drop)]
pub struct StrettoPlan {
    /// Lag at kill bucket 0 (loosest, most like a regular canon).
    pub base_lag: u32,
    /// Lag at kill bucket 7 (tightest stretto; must be ≥ 1).
    pub min_lag: u32,
}

/// Default stretto plan: normal canon at 4-beat lag, compressed to 1-beat at max kills.
pub fn default_stretto_plan() -> StrettoPlan {
    StrettoPlan { base_lag: 4, min_lag: 1 }
}

/// Stretto plan for renaissance-style voice spacing (wider base lag).
pub fn renaissance_stretto_plan() -> StrettoPlan {
    StrettoPlan { base_lag: 6, min_lag: 2 }
}

// ─────────────────────────────────────────────────────────────
// Lag computation
// ─────────────────────────────────────────────────────────────

/// Compute the stretto entry lag from a kill bucket value (0–7).
/// Linearly interpolates base_lag → min_lag as bucket rises from 0 → 7.
pub fn stretto_lag(plan: @StrettoPlan, kill_bucket: u8) -> u32 {
    let base = *plan.base_lag;
    let min = *plan.min_lag;
    if base <= min {
        return min;
    }
    let range = base - min;
    let kb: u32 = kill_bucket.into();
    let reduction = range * kb / 7;
    if reduction >= range {
        min
    } else {
        base - reduction
    }
}

/// Entry time in structural beats for voice `voice_idx` with `lag` beats between entries.
/// Voice 0 (leader) always enters at beat 0.
pub fn voice_entry_time(voice_idx: u32, lag: u32) -> u32 {
    voice_idx * lag
}

/// Build the full entry-time array for `voice_count` voices.
pub fn stretto_entry_times(plan: @StrettoPlan, kill_bucket: u8, voice_count: u32) -> Array<u32> {
    let lag = stretto_lag(plan, kill_bucket);
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= voice_count {
            break;
        }
        out.append(voice_entry_time(i, lag));
        i += 1;
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Event emission with stretto entries
// ─────────────────────────────────────────────────────────────

/// Emit NoteEvents from a MelodicCanon but with overridden per-voice entry times.
/// `entries` must have the same length as `canon.voices`; entry times are in structural beats.
/// All other canon parameters (degrees, offsets, octave, etc.) are unchanged.
pub fn stretto_to_note_events(
    canon: @MelodicCanon, entries: Span<u32>,
) -> Array<NoteEvent> {
    let degs = *canon.leader_degrees;
    let voices = *canon.voices;
    assert(entries.len() == voices.len(), 'entries vs voices mismatch');
    let unit = *canon.time_unit;
    let octave = *canon.octave;
    let mode = *canon.mode_id;
    let tonic = *canon.tonic_keynum;
    let len = degs.len();
    let mut out: Array<NoteEvent> = ArrayTrait::new();

    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let v = *voices.at(vi);
        let entry_beats = *entries.at(vi);
        let mut p: u32 = 0;
        loop {
            if p >= len {
                break;
            }
            let deg = *degs.at(p) + v.offset;
            out.append(
                NoteEvent {
                    time: (entry_beats + p) * unit,
                    duration: unit,
                    pitch: realize_degree(octave, deg, tonic, mode),
                    velocity: DEFAULT_VELOCITY,
                    voice_id: v.voice_id,
                },
            );
            p += 1;
        };
        vi += 1;
    };
    out
}

/// Convenience: apply stretto directly from a kill bucket, using default voice entries.
pub fn apply_stretto(
    canon: @MelodicCanon, plan: @StrettoPlan, kill_bucket: u8,
) -> Array<NoteEvent> {
    let voice_count = (*canon.voices).len();
    let entries = stretto_entry_times(plan, kill_bucket, voice_count);
    stretto_to_note_events(canon, entries.span())
}

// ─────────────────────────────────────────────────────────────
// Beast integration helpers
// ─────────────────────────────────────────────────────────────

/// Convert `adventurers_defeated_bucket` (0–7) to a stretto lag using the default plan.
pub fn kills_to_lag(kill_bucket: u8) -> u32 {
    stretto_lag(@default_stretto_plan(), kill_bucket)
}

/// Human-readable intensity level for a given lag (for metadata / NFT traits).
pub fn stretto_intensity(lag: u32) -> felt252 {
    if lag >= 4 {
        'exposition'
    } else if lag == 3 {
        'close_stretto'
    } else if lag == 2 {
        'tight_stretto'
    } else {
        'extreme_stretto'
    }
}

// ─────────────────────────────────────────────────────────────
// Validators
// ─────────────────────────────────────────────────────────────

/// True iff lag compresses monotonically from bucket 0 to bucket 7.
pub fn stretto_plan_valid(plan: @StrettoPlan) -> bool {
    *plan.min_lag >= 1 && *plan.base_lag >= *plan.min_lag
}

/// True iff stretto entry times are strictly non-decreasing (voice 0 enters first).
pub fn entries_ordered(entries: Span<u32>) -> bool {
    if entries.len() < 2 {
        return true;
    }
    let mut i: u32 = 0;
    let mut ok = true;
    loop {
        if i + 1 >= entries.len() || !ok {
            break;
        }
        if *entries.at(i + 1) < *entries.at(i) {
            ok = false;
        }
        i += 1;
    };
    ok
}

/// True iff the stretto entries are strictly tighter than the default (non-stretto) spacing.
pub fn is_genuine_stretto(entries: Span<u32>) -> bool {
    if entries.len() < 2 {
        return false;
    }
    let mut i: u32 = 0;
    let mut tight = false;
    loop {
        if i + 1 >= entries.len() {
            break;
        }
        let cur = *entries.at(i);
        let next = *entries.at(i + 1);
        if next < cur {
            return false;
        }
        if next - cur < default_stretto_plan().base_lag {
            tight = true;
        }
        i += 1;
    };
    tight
}

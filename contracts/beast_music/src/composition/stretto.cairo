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

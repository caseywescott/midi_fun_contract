//! Melodic motion and ornament-fill policies (profile-aware).
//!
//! Separates three layers that were previously conflated:
//!   1. **Structural steps** — leader walk (`|m|` minimum, semitone forbidden or not)
//!   2. **Ornament density** — whether intervals are subdivided at all
//!   3. **Fill path** — how subdivisions connect `from_deg` to `to_deg` (chromatic ±1 vs
//!      minimum-step / material-aware)
//!
//! Chromatic `subdivide()` (±1 semitone per slice) is only used when `ORN_FILL_CHROMATIC`.
//! Complementary and smooth profiles use material or min-step fill instead.
//!
//! See `docs/renaissance_canon_improvisation_spec.md` (ornament layer) and complementary
//! profile notes in `docs/extended_harmony_canon_spec.md`.

// Ornament fill between consecutive structural degrees.
pub const ORN_FILL_CHROMATIC: u8 = 0;
pub const ORN_FILL_STRUCTURAL: u8 = 1;
pub const ORN_FILL_MIN_STEP: u8 = 2;
pub const ORN_FILL_MATERIAL: u8 = 3;

/// Sentinel: use [`ornament_fill_mode_for_profile`] for this profile.
pub const FILL_MODE_PROFILE: u8 = 255;

/// Minimum absolute leader step `|m|` on the structural path (1 = semitone allowed, 2 = skip m2).
pub fn min_melodic_step_for_profile(profile_id: u32) -> u32 {
    if profile_id == 19 {
        1
    } else if profile_id == 18 {
        1
    } else if profile_id >= 17 && profile_id <= 24 {
        2
    } else {
        1
    }
}

/// How ornament subdivisions connect two structural degrees in MIDI export.
pub fn ornament_fill_mode_for_profile(profile_id: u32) -> u8 {
    if profile_id == 22 || profile_id == 23 || profile_id == 24 {
        ORN_FILL_STRUCTURAL
    } else if profile_id >= 17 && profile_id <= 21 {
        ORN_FILL_MATERIAL
    } else if profile_id == 1 {
        ORN_FILL_MIN_STEP
    } else {
        ORN_FILL_CHROMATIC
    }
}

/// True when the leader walk must reject structural steps with `abs(m) == 1`.
pub fn forbids_semitone_structural_step(profile_id: u32) -> bool {
    min_melodic_step_for_profile(profile_id) >= 2
}

/// True when every exported subdivision count must be 1 (no rhythmic splitting).
pub fn ornament_structural_only(profile_id: u32) -> bool {
    ornament_fill_mode_for_profile(profile_id) == ORN_FILL_STRUCTURAL
}

/// Minimum |leader_step| before ornament planner may subdivide (avoid filling small motions).
pub fn min_step_for_ornament_subdivide(profile_id: u32) -> u32 {
    if ornament_structural_only(profile_id) {
        99
    } else if ornament_fill_mode_for_profile(profile_id) == ORN_FILL_CHROMATIC {
        1
    } else {
        3
    }
}

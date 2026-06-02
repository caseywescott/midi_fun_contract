//! Precomputed tiling templates, velocity patterns, and support tables.
//!
//! All `TilingTemplate` entries were enumerated offline as `R = AP(k, d, n)` with
//! `S = find_complement(n, R)`. Every entry must pass `is_direct_sum` and must satisfy
//! `legato_durations(r_base, n) == durations` (verified in tests).
//!
//! Entries with `|S| > MAX_VOICES` (e.g. the `k = 2` tilings for `n = 24`) are excluded.

use core::array::ArrayTrait;

/// A precomputed tiling template.
///
/// `s_base` is always the output of `find_complement(n, r_base)`. All entries must pass
/// `is_direct_sum` in tests, and `durations` must sum to `n`.
#[derive(Copy, Drop)]
pub struct TilingTemplate {
    pub n: u32,
    /// `|R|` — number of onsets per voice.
    pub k: u32,
    /// AP step used to generate `R`.
    pub d: u32,
    /// Precomputed `R = AP(k, d, n)`.
    pub r_base: Span<u32>,
    /// Precomputed `S = find_complement(n, r_base)`.
    pub s_base: Span<u32>,
    /// Precomputed `legato_durations(r_base, n)`.
    pub durations: Span<u32>,
    /// 0 = trivial block, 1 = one side is an AP, 2 = neither side is a pure AP.
    pub syncopation_class: u8,
    /// Higher = more rhythmically interesting.
    pub interest_score: u32,
}

/// Cycle lengths the generator may select. All have full template tables below.
pub fn gen_supported_n() -> Span<u32> {
    array![8_u32, 12, 16, 24].span()
}

/// The full set of cycle lengths the wider system recognises (used for metadata).
pub fn supported_n() -> Span<u32> {
    array![8_u32, 12, 16, 24, 36, 48, 60, 72, 96, 120].span()
}

/// Construct a template, taking ownership of the component arrays.
fn t(
    n: u32,
    k: u32,
    d: u32,
    r: Array<u32>,
    s: Array<u32>,
    durs: Array<u32>,
    cls: u8,
    score: u32,
) -> TilingTemplate {
    TilingTemplate {
        n,
        k,
        d,
        r_base: r.span(),
        s_base: s.span(),
        durations: durs.span(),
        syncopation_class: cls,
        interest_score: score,
    }
}

/// Precomputed valid AP tilings for `n`, ordered by interest score descending.
pub fn templates_for(n: u32) -> Array<TilingTemplate> {
    if n == 8 {
        templates_8()
    } else if n == 12 {
        templates_12()
    } else if n == 16 {
        templates_16()
    } else if n == 24 {
        templates_24()
    } else {
        ArrayTrait::new()
    }
}

fn templates_8() -> Array<TilingTemplate> {
    let mut out: Array<TilingTemplate> = ArrayTrait::new();
    out.append(t(8, 2, 2, array![0, 2], array![0, 1, 4, 5], array![2, 6], 2, 5));
    out.append(t(8, 2, 1, array![0, 1], array![0, 2, 4, 6], array![1, 7], 1, 4));
    out.append(t(8, 2, 4, array![0, 4], array![0, 1, 2, 3], array![4, 4], 1, 4));
    out.append(t(8, 4, 1, array![0, 1, 2, 3], array![0, 4], array![1, 1, 1, 5], 1, 4));
    out.append(t(8, 4, 2, array![0, 2, 4, 6], array![0, 1], array![2, 2, 2, 2], 1, 4));
    out
}

fn templates_12() -> Array<TilingTemplate> {
    let mut out: Array<TilingTemplate> = ArrayTrait::new();
    out.append(t(12, 2, 2, array![0, 2], array![0, 1, 4, 5, 8, 9], array![2, 10], 2, 5));
    out.append(t(12, 2, 3, array![0, 3], array![0, 1, 2, 6, 7, 8], array![3, 9], 2, 5));
    out.append(t(12, 3, 2, array![0, 2, 4], array![0, 1, 6, 7], array![2, 2, 8], 2, 5));
    out.append(t(12, 2, 1, array![0, 1], array![0, 2, 4, 6, 8, 10], array![1, 11], 1, 4));
    out.append(t(12, 2, 6, array![0, 6], array![0, 1, 2, 3, 4, 5], array![6, 6], 1, 4));
    out.append(t(12, 3, 4, array![0, 4, 8], array![0, 1, 2, 3], array![4, 4, 4], 1, 4));
    out.append(t(12, 4, 1, array![0, 1, 2, 3], array![0, 4, 8], array![1, 1, 1, 9], 1, 4));
    out.append(t(12, 4, 3, array![0, 3, 6, 9], array![0, 1, 2], array![3, 3, 3, 3], 1, 4));
    out.append(t(12, 6, 1, array![0, 1, 2, 3, 4, 5], array![0, 6], array![1, 1, 1, 1, 1, 7], 1, 4));
    out.append(t(12, 6, 2, array![0, 2, 4, 6, 8, 10], array![0, 1], array![2, 2, 2, 2, 2, 2], 1, 4));
    out
}

fn templates_16() -> Array<TilingTemplate> {
    let mut out: Array<TilingTemplate> = ArrayTrait::new();
    out.append(t(16, 2, 2, array![0, 2], array![0, 1, 4, 5, 8, 9, 12, 13], array![2, 14], 2, 5));
    out.append(t(16, 2, 4, array![0, 4], array![0, 1, 2, 3, 8, 9, 10, 11], array![4, 12], 2, 5));
    out.append(t(16, 4, 2, array![0, 2, 4, 6], array![0, 1, 8, 9], array![2, 2, 2, 10], 2, 5));
    out.append(t(16, 2, 1, array![0, 1], array![0, 2, 4, 6, 8, 10, 12, 14], array![1, 15], 1, 4));
    out.append(t(16, 2, 8, array![0, 8], array![0, 1, 2, 3, 4, 5, 6, 7], array![8, 8], 1, 4));
    out.append(t(16, 4, 1, array![0, 1, 2, 3], array![0, 4, 8, 12], array![1, 1, 1, 13], 1, 4));
    out.append(t(16, 4, 4, array![0, 4, 8, 12], array![0, 1, 2, 3], array![4, 4, 4, 4], 1, 4));
    out
        .append(
            t(
                16,
                8,
                1,
                array![0, 1, 2, 3, 4, 5, 6, 7],
                array![0, 8],
                array![1, 1, 1, 1, 1, 1, 1, 9],
                1,
                4,
            ),
        );
    out
        .append(
            t(
                16,
                8,
                2,
                array![0, 2, 4, 6, 8, 10, 12, 14],
                array![0, 1],
                array![2, 2, 2, 2, 2, 2, 2, 2],
                1,
                4,
            ),
        );
    out
}

fn templates_24() -> Array<TilingTemplate> {
    // k = 2 tilings are excluded for n = 24 because |S| = 12 > MAX_VOICES.
    let mut out: Array<TilingTemplate> = ArrayTrait::new();
    out.append(t(24, 3, 2, array![0, 2, 4], array![0, 1, 6, 7, 12, 13, 18, 19], array![2, 2, 20], 2, 5));
    out.append(t(24, 3, 4, array![0, 4, 8], array![0, 1, 2, 3, 12, 13, 14, 15], array![4, 4, 16], 2, 5));
    out.append(t(24, 4, 2, array![0, 2, 4, 6], array![0, 1, 8, 9, 16, 17], array![2, 2, 2, 18], 2, 5));
    out.append(t(24, 4, 3, array![0, 3, 6, 9], array![0, 1, 2, 12, 13, 14], array![3, 3, 3, 15], 2, 5));
    out
        .append(
            t(
                24,
                6,
                2,
                array![0, 2, 4, 6, 8, 10],
                array![0, 1, 12, 13],
                array![2, 2, 2, 2, 2, 14],
                2,
                5,
            ),
        );
    out
}

// ──────────────────────────────────────────────────────────
// Velocity pattern table
// ──────────────────────────────────────────────────────────

/// Number of velocity patterns available.
pub fn num_velocity_patterns() -> u32 {
    5
}

/// Velocity pattern for a curve index. `derive_velocity` indexes into the returned span by
/// `onset_index % len`. Unknown curves fall back to flat dynamics.
pub fn velocity_pattern(curve: u8) -> Span<u8> {
    if curve == 0 {
        array![100_u8].span() // flat
    } else if curve == 1 {
        array![120_u8, 80].span() // accent-first
    } else if curve == 2 {
        array![110_u8, 70].span() // alternating
    } else if curve == 3 {
        array![60_u8, 80, 100, 120].span() // crescendo
    } else if curve == 4 {
        array![120_u8, 100, 80, 60].span() // decrescendo
    } else {
        array![100_u8].span()
    }
}

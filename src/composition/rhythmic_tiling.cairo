//! Rhythmic Tiling Canon Generator.
//!
//! Deterministic rhythmic canon generation where correctness is guaranteed by algebraic
//! tiling: given a seed, the system produces a set of interlocking voice-onset patterns
//! that tile a cyclic timeline `Z_n` with no gaps and no collisions.
//!
//! Core invariant: `R ⊕ S = Z_n` — every position in `Z_n` is hit exactly once across all
//! voices, where `R` is the rhythm tile and `S` is the translation set.
//!
//! See `docs/rhythmic_tiling_canon_spec.md` for the full specification.

use core::array::ArrayTrait;
use core::dict::Felt252Dict;
use koji::composition::known_tilings::{
    TilingTemplate, templates_for, gen_supported_n, velocity_pattern, num_velocity_patterns,
};

// ──────────────────────────────────────────────────────────
// Cardinality bounds
// ──────────────────────────────────────────────────────────

/// Upper bound on the number of voices (|S|).
pub const MAX_VOICES: u32 = 8;
/// Lower bound on tile onsets (|R|); size 1 is trivially uninteresting.
pub const MIN_TILE_ONSETS: u32 = 2;

// ──────────────────────────────────────────────────────────
// Core data structures
// ──────────────────────────────────────────────────────────

/// A single note event: when a voice attacks, how long it sustains, and how loud.
#[derive(Copy, Drop)]
pub struct OnsetEvent {
    /// Position in `Z_n` where the note attacks.
    pub time: u32,
    /// Legato sustain (steps until this voice's next onset).
    pub duration: u32,
    pub voice_id: u32,
    pub velocity: u8,
}

/// One voice of a canon. No pitch information — that belongs to the pitch layer.
#[derive(Copy, Drop)]
pub struct RhythmicVoice {
    pub voice_id: u32,
    /// The `s` value (entry offset) for this voice.
    pub translation: u32,
    /// `false` for augmented/diminuted free voices excluded from the tiling guarantee.
    pub tiling_participant: bool,
    /// Index into the velocity-pattern table.
    pub velocity_curve: u8,
}

/// A complete rhythmic canon ready to be rendered into events.
#[derive(Drop)]
pub struct RhythmicCanon {
    pub n: u32,
    /// `R` (sorted onsets, after offset applied).
    pub rhythm_tile: Span<u32>,
    /// `S` (sorted offsets, after offset applied).
    pub translations: Span<u32>,
    /// Legato durations for the tile (aligned with `rhythm_tile`).
    pub durations: Span<u32>,
    pub template_index: u32,
    pub r_offset: u32,
    pub s_offset: u32,
    pub voices: Span<RhythmicVoice>,
}

/// Onchain metadata describing a canon's structural properties.
#[derive(Copy, Drop)]
pub struct CanonTraits {
    pub cycle_length: u32,
    pub tile_size: u32,
    pub voice_count: u32,
    pub syncopation_class: u8,
    pub interest_score: u32,
    pub distance_of_entrance: u32,
    pub gap_variety_r: u32,
    pub gap_variety_s: u32,
    pub template_index: u32,
}

// ──────────────────────────────────────────────────────────
// Small helpers
// ──────────────────────────────────────────────────────────

/// Insertion sort, ascending. Returns a fresh array.
pub fn sorted(values: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= values.len() {
            break;
        }
        let v = *values.at(i);
        // Build a new array with `v` inserted in order.
        let mut next: Array<u32> = ArrayTrait::new();
        let mut inserted = false;
        let mut j: u32 = 0;
        loop {
            if j >= out.len() {
                break;
            }
            let cur = *out.at(j);
            if !inserted && v < cur {
                next.append(v);
                inserted = true;
            }
            next.append(cur);
            j += 1;
        };
        if !inserted {
            next.append(v);
        }
        out = next;
        i += 1;
    };
    out
}

/// Largest value in a span (0 for empty).
fn max_span(s: Span<u32>) -> u32 {
    let mut m: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= s.len() {
            break;
        }
        let v = *s.at(i);
        if v > m {
            m = v;
        }
        i += 1;
    };
    m
}

/// Element-wise span equality.
pub fn span_eq(a: Span<u32>, b: Span<u32>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: u32 = 0;
    let mut res = true;
    loop {
        if i >= a.len() {
            break;
        }
        if *a.at(i) != *b.at(i) {
            res = false;
            break;
        }
        i += 1;
    };
    res
}

// ──────────────────────────────────────────────────────────
// Arithmetic progressions
// ──────────────────────────────────────────────────────────

/// `AP(k, d, n) = {0, d, 2d, ..., (k-1)·d} mod n`, sorted.
///
/// Returns `None` when the progression self-intersects (fewer than `k` distinct values).
pub fn ap_set(k: u32, d: u32, n: u32) -> Option<Array<u32>> {
    let mut raw: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= k {
            break;
        }
        raw.append((i * d) % n);
        i += 1;
    };
    let s = sorted(raw.span());
    // Detect duplicates among adjacent sorted entries.
    let mut distinct = true;
    let mut j: u32 = 0;
    loop {
        if j + 1 >= s.len() {
            break;
        }
        if *s.at(j) == *s.at(j + 1) {
            distinct = false;
            break;
        }
        j += 1;
    };
    if distinct && s.len() == k {
        Option::Some(s)
    } else {
        Option::None
    }
}

// ──────────────────────────────────────────────────────────
// Direct-sum validator
// ──────────────────────────────────────────────────────────

/// Correctness assertion: does `R ⊕ S = Z_n` hold (every position hit exactly once)?
pub fn is_direct_sum(n: u32, r: Span<u32>, s: Span<u32>) -> bool {
    if r.len() * s.len() != n {
        return false;
    }
    let mut hits: Felt252Dict<u32> = Default::default();
    let mut ok = true;
    let mut i: u32 = 0;
    loop {
        if i >= r.len() {
            break;
        }
        let ri = *r.at(i);
        if ri >= n {
            ok = false;
            break;
        }
        let mut j: u32 = 0;
        loop {
            if j >= s.len() {
                break;
            }
            let sj = *s.at(j);
            if sj >= n {
                ok = false;
                break;
            }
            let pos: u32 = (ri + sj) % n;
            if hits.get(pos.into()) == 1 {
                ok = false;
                break;
            }
            hits.insert(pos.into(), 1);
            j += 1;
        };
        if !ok {
            break;
        }
        i += 1;
    };
    if ok {
        // Verify there are no gaps.
        let mut p: u32 = 0;
        loop {
            if p >= n {
                break;
            }
            if hits.get(p.into()) != 1 {
                ok = false;
                break;
            }
            p += 1;
        };
    }
    ok
}

// ──────────────────────────────────────────────────────────
// Polynomial complement
// ──────────────────────────────────────────────────────────

/// Derive `S` analytically from `R` via polynomial division `S(x) = T_n(x) / R(x)` over Z[x],
/// where `T_n(x) = 1 + x + ... + x^(n-1)`.
///
/// Returns `Some(sorted S)` when `R` tiles `Z_n`, otherwise `None`.
pub fn find_complement(n: u32, r: Span<u32>) -> Option<Array<u32>> {
    let k = r.len();
    if k == 0 || n == 0 {
        return Option::None;
    }
    let deg_r = max_span(r);
    if deg_r >= n {
        return Option::None;
    }
    let deg_t = n - 1;
    let deg_s = deg_t - deg_r;

    // Remainder starts as the all-ones polynomial T_n(x).
    let mut rem: Felt252Dict<u32> = Default::default();
    let mut idx: u32 = 0;
    loop {
        if idx >= n {
            break;
        }
        rem.insert(idx.into(), 1);
        idx += 1;
    };

    let mut qpos: Array<u32> = ArrayTrait::new();
    let mut ok = true;
    let mut step: u32 = 0;
    loop {
        if step > deg_s {
            break;
        }
        let i = deg_s - step; // process quotient terms high → low
        let lead = i + deg_r;
        let coeff = rem.get(lead.into());
        if coeff != 0 {
            let mut underflow = false;
            let mut t: u32 = 0;
            loop {
                if t >= k {
                    break;
                }
                let p = *r.at(t);
                let ti = i + p;
                let cur = rem.get(ti.into());
                if cur < coeff {
                    underflow = true;
                    break;
                }
                rem.insert(ti.into(), cur - coeff);
                t += 1;
            };
            if underflow {
                ok = false;
                break;
            }
            // coeff is necessarily 1 here (coefficients only ever decrease from 1).
            qpos.append(i);
        }
        step += 1;
    };

    if !ok {
        return Option::None;
    }

    // Remainder must be identically zero for an exact division.
    let mut p2: u32 = 0;
    loop {
        if p2 >= n {
            break;
        }
        if rem.get(p2.into()) != 0 {
            ok = false;
            break;
        }
        p2 += 1;
    };
    if !ok {
        return Option::None;
    }

    Option::Some(sorted(qpos.span()))
}

// ──────────────────────────────────────────────────────────
// Legato durations
// ──────────────────────────────────────────────────────────

/// Each onset sustains until that voice's next onset (cyclically). `r` must be sorted.
/// The returned durations always sum to `n`.
pub fn legato_durations(r: Span<u32>, n: u32) -> Array<u32> {
    let k = r.len();
    let mut durs: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= k {
            break;
        }
        let start = *r.at(i);
        let end = *r.at((i + 1) % k);
        durs.append((end + n - start) % n);
        i += 1;
    };
    durs
}

// ──────────────────────────────────────────────────────────
// Rotation offsets
// ──────────────────────────────────────────────────────────

/// Rotate every element of `set` by `offset` (mod n) and return the sorted result.
/// Cyclic rotation preserves the direct-sum property.
pub fn apply_offset(set: Span<u32>, offset: u32, n: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= set.len() {
            break;
        }
        out.append((*set.at(i) + offset) % n);
        i += 1;
    };
    sorted(out.span())
}

// ──────────────────────────────────────────────────────────
// Gap analysis & classification
// ──────────────────────────────────────────────────────────

/// Cyclic gaps between consecutive sorted positions (wraps around `n`).
pub fn cyclic_gaps(n: u32, positions: Span<u32>) -> Array<u32> {
    let s = sorted(positions);
    let k = s.len();
    let mut gaps: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= k {
            break;
        }
        let a = *s.at(i);
        let b = *s.at((i + 1) % k);
        gaps.append((b + n - a) % n);
        i += 1;
    };
    gaps
}

/// Number of distinct gap sizes (cyclic) in `set`.
pub fn gap_variety(n: u32, set: Span<u32>) -> u32 {
    let gaps = cyclic_gaps(n, set);
    let mut count: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= gaps.len() {
            break;
        }
        let g = *gaps.at(i);
        // Count this gap only if it hasn't appeared earlier.
        let mut seen = false;
        let mut j: u32 = 0;
        loop {
            if j >= i {
                break;
            }
            if *gaps.at(j) == g {
                seen = true;
                break;
            }
            j += 1;
        };
        if !seen {
            count += 1;
        }
        i += 1;
    };
    count
}

/// True when consecutive (linear, non-wrapping) differences are all equal. Sets of size
/// <= 2 are trivially arithmetic progressions.
pub fn is_arithmetic_progression(set: Span<u32>, _n: u32) -> bool {
    let s = sorted(set);
    let k = s.len();
    if k <= 2 {
        return true;
    }
    let d0 = *s.at(1) - *s.at(0);
    let mut i: u32 = 1;
    let mut res = true;
    loop {
        if i + 1 >= k {
            break;
        }
        if *s.at(i + 1) - *s.at(i) != d0 {
            res = false;
            break;
        }
        i += 1;
    };
    res
}

/// A trivial block pattern: both `R` and `S` are pure arithmetic progressions.
pub fn is_trivial_block_pattern(n: u32, r: Span<u32>, s: Span<u32>) -> bool {
    is_arithmetic_progression(r, n) && is_arithmetic_progression(s, n)
}

/// Minimum nonzero element of `S` (the smallest gap before another voice enters).
pub fn distance_of_entrance(s: Span<u32>) -> u32 {
    let mut best: u32 = 0;
    let mut found = false;
    let mut i: u32 = 0;
    loop {
        if i >= s.len() {
            break;
        }
        let v = *s.at(i);
        if v > 0 {
            if !found || v < best {
                best = v;
                found = true;
            }
        }
        i += 1;
    };
    best
}

// ──────────────────────────────────────────────────────────
// Scoring
// ──────────────────────────────────────────────────────────

/// Heuristic rhythmic-interest score. Trivial block patterns score lowest; tilings whose
/// translation set has varied, non-AP structure score highest.
pub fn score_tiling(n: u32, r: Span<u32>, s: Span<u32>) -> u32 {
    let mut score: u32 = 0;
    if !is_trivial_block_pattern(n, r, s) {
        score += 10;
    }
    // The richness of the composite output comes primarily from S.
    score += gap_variety(n, r);
    score += gap_variety(n, s) * 2;
    score
}

// ──────────────────────────────────────────────────────────
// Periodicity
// ──────────────────────────────────────────────────────────

/// Distinct prime factors of `n`.
fn prime_factors(n: u32) -> Array<u32> {
    let mut res: Array<u32> = ArrayTrait::new();
    let mut m = n;
    let mut d: u32 = 2;
    loop {
        if d * d > m {
            break;
        }
        if m % d == 0 {
            res.append(d);
            loop {
                if m % d != 0 {
                    break;
                }
                m = m / d;
            };
        }
        d += 1;
    };
    if m > 1 {
        res.append(m);
    }
    res
}

/// True if `set` is invariant under rotation by `n/p` for some prime `p` dividing `n`.
pub fn is_periodic(set: Span<u32>, n: u32) -> bool {
    let primes = prime_factors(n);
    let base = sorted(set);
    let mut i: u32 = 0;
    let mut res = false;
    loop {
        if i >= primes.len() {
            break;
        }
        let p = *primes.at(i);
        let shift = n / p;
        let shifted = apply_offset(set, shift, n);
        if span_eq(base.span(), shifted.span()) {
            res = true;
            break;
        }
        i += 1;
    };
    res
}

/// True if neither `R` nor `S` is periodic (a Vuza canon candidate). For all currently
/// supported `n` this returns `false` (all are Hajós numbers).
pub fn is_candidate_prime_canon(n: u32, r: Span<u32>, s: Span<u32>) -> bool {
    !is_periodic(r, n) && !is_periodic(s, n)
}

// ──────────────────────────────────────────────────────────
// Augmentation / diminution
// ──────────────────────────────────────────────────────────

/// True if the scaled tile `factor·R` still tiles `Z_n` with `S`.
pub fn validate_scaled_tile(n: u32, r: Span<u32>, s: Span<u32>, factor: u32) -> bool {
    let mut scaled: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= r.len() {
            break;
        }
        scaled.append((*r.at(i) * factor) % n);
        i += 1;
    };
    let sr = sorted(scaled.span());
    is_direct_sum(n, sr.span(), s)
}

// ──────────────────────────────────────────────────────────
// Velocity
// ──────────────────────────────────────────────────────────

/// Read a velocity value from the pattern table by curve index and onset index.
pub fn derive_velocity(onset_index: u32, voice: RhythmicVoice) -> u8 {
    let pattern = velocity_pattern(voice.velocity_curve);
    let len = pattern.len();
    if len == 0 {
        return 100;
    }
    let idx = onset_index % len;
    let v: u8 = *pattern.at(idx);
    v
}

// ──────────────────────────────────────────────────────────
// Event generation
// ──────────────────────────────────────────────────────────

/// Insertion sort of events by ascending `time` (stable on ties via voice order).
fn sort_events_by_time(events: Array<OnsetEvent>) -> Array<OnsetEvent> {
    let span = events.span();
    let mut out: Array<OnsetEvent> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= span.len() {
            break;
        }
        let e = *span.at(i);
        let mut next: Array<OnsetEvent> = ArrayTrait::new();
        let mut inserted = false;
        let mut j: u32 = 0;
        loop {
            if j >= out.len() {
                break;
            }
            let cur = *out.at(j);
            if !inserted && e.time < cur.time {
                next.append(e);
                inserted = true;
            }
            next.append(cur);
            j += 1;
        };
        if !inserted {
            next.append(e);
        }
        out = next;
        i += 1;
    };
    out
}

/// Convert a canon into a time-sorted stream of onset events from its tiling-participant
/// voices.
pub fn canon_to_events(canon: @RhythmicCanon) -> Array<OnsetEvent> {
    let n = *canon.n;
    let tile = *canon.rhythm_tile;
    let durs = *canon.durations;
    let voices = *canon.voices;

    let mut events: Array<OnsetEvent> = ArrayTrait::new();
    let mut vi: u32 = 0;
    loop {
        if vi >= voices.len() {
            break;
        }
        let voice = *voices.at(vi);
        if voice.tiling_participant {
            let mut i: u32 = 0;
            loop {
                if i >= tile.len() {
                    break;
                }
                let r = *tile.at(i);
                let time = (r + voice.translation) % n;
                events
                    .append(
                        OnsetEvent {
                            time,
                            duration: *durs.at(i),
                            voice_id: voice.voice_id,
                            velocity: derive_velocity(i, voice),
                        },
                    );
                i += 1;
            };
        }
        vi += 1;
    };
    sort_events_by_time(events)
}

/// Events for a single free (augmented/diminuted) voice. These may collide with
/// tiling-participant onsets and are excluded from the direct-sum guarantee.
pub fn free_voice_events(canon: @RhythmicCanon, voice: RhythmicVoice, factor: u32) -> Array<OnsetEvent> {
    let n = *canon.n;
    let tile = *canon.rhythm_tile;
    let mut scaled: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= tile.len() {
            break;
        }
        scaled.append((*tile.at(i) * factor) % n);
        i += 1;
    };
    let sr = sorted(scaled.span());
    let durs = legato_durations(sr.span(), n);

    let mut events: Array<OnsetEvent> = ArrayTrait::new();
    let mut j: u32 = 0;
    loop {
        if j >= sr.len() {
            break;
        }
        let time = (*sr.at(j) + voice.translation) % n;
        events
            .append(
                OnsetEvent {
                    time,
                    duration: *durs.at(j),
                    voice_id: voice.voice_id,
                    velocity: derive_velocity(j, voice),
                },
            );
        j += 1;
    };
    events
}

// ──────────────────────────────────────────────────────────
// Seed decoding
// ──────────────────────────────────────────────────────────

fn pow2(e: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= e {
            break;
        }
        r = r * 2;
        i += 1;
    };
    r
}

/// Extract a `width`-bit field starting at bit `shift` from the seed.
fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

// ──────────────────────────────────────────────────────────
// Template selection
// ──────────────────────────────────────────────────────────

/// Distinct `k` (tile-size) values present in a template list, in first-seen order.
fn distinct_ks(templates: Span<TilingTemplate>) -> Array<u32> {
    let mut ks: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= templates.len() {
            break;
        }
        let k = *templates.at(i).k;
        let mut seen = false;
        let mut j: u32 = 0;
        loop {
            if j >= ks.len() {
                break;
            }
            if *ks.at(j) == k {
                seen = true;
                break;
            }
            j += 1;
        };
        if !seen {
            ks.append(k);
        }
        i += 1;
    };
    ks
}

/// Templates from `templates` whose tile-size equals `k`.
fn filter_by_k(templates: Span<TilingTemplate>, k: u32) -> Array<TilingTemplate> {
    let mut out: Array<TilingTemplate> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= templates.len() {
            break;
        }
        let t = *templates.at(i);
        if t.k == k {
            out.append(t);
        }
        i += 1;
    };
    out
}

/// Index of the first template matching `(k, d)` within the full list.
fn template_index_of(templates: Span<TilingTemplate>, k: u32, d: u32) -> u32 {
    let mut i: u32 = 0;
    loop {
        if i >= templates.len() {
            break;
        }
        let t = *templates.at(i);
        if t.k == k && t.d == d {
            break;
        }
        i += 1;
    };
    i
}

/// Select a tiling template for `n` from the precomputed table using seed bits.
pub fn select_template(seed: felt252, n: u32) -> TilingTemplate {
    let s: u256 = seed.into();
    let templates = templates_for(n);
    let ks = distinct_ks(templates.span());
    let k = *ks.at(extract_bits(s, 4, 4) % ks.len());
    let group = filter_by_k(templates.span(), k);
    *group.at(extract_bits(s, 8, 8) % group.len())
}

// ──────────────────────────────────────────────────────────
// Generator pipeline
// ──────────────────────────────────────────────────────────

fn build_rhythmic_canon(seed: felt252, n: u32) -> RhythmicCanon {
    let templates = templates_for(n);
    build_rhythmic_canon_from_pool(seed, n, templates.span(), templates.span())
}

fn templates_with_min_voices(
    templates: Span<TilingTemplate>, min_voices: u32,
) -> Array<TilingTemplate> {
    let mut out: Array<TilingTemplate> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= templates.len() {
            break;
        }
        let tmpl = *templates.at(i);
        let voice_count: u32 = tmpl.s_base.len().try_into().unwrap();
        if voice_count >= min_voices {
            out.append(tmpl);
        }
        i += 1;
    };
    out
}

fn build_rhythmic_canon_from_pool(
    seed: felt252,
    n: u32,
    pool: Span<TilingTemplate>,
    index_pool: Span<TilingTemplate>,
) -> RhythmicCanon {
    let s: u256 = seed.into();
    assert(pool.len() > 0, 'empty template pool');

    let ks = distinct_ks(pool);
    let k = *ks.at(extract_bits(s, 4, 4) % ks.len());
    let group = filter_by_k(pool, k);
    let tmpl = *group.at(extract_bits(s, 8, 8) % group.len());

    let r_offset = extract_bits(s, 16, 8) % n;
    let s_offset = extract_bits(s, 24, 8) % n;
    let r = apply_offset(tmpl.r_base, r_offset, n);
    let trans = apply_offset(tmpl.s_base, s_offset, n);

    assert(is_direct_sum(n, r.span(), trans.span()), 'tiling is not a direct sum');

    let durations = legato_durations(r.span(), n);
    let vcurve: u8 = (extract_bits(s, 32, 4) % num_velocity_patterns()).try_into().unwrap();
    let mut voices: Array<RhythmicVoice> = ArrayTrait::new();
    let mut vi: u32 = 0;
    loop {
        if vi >= trans.len() {
            break;
        }
        voices
            .append(
                RhythmicVoice {
                    voice_id: vi,
                    translation: *trans.at(vi),
                    tiling_participant: true,
                    velocity_curve: vcurve,
                },
            );
        vi += 1;
    };

    let template_index = template_index_of(index_pool, tmpl.k, tmpl.d);

    RhythmicCanon {
        n,
        rhythm_tile: r.span(),
        translations: trans.span(),
        durations: durations.span(),
        template_index,
        r_offset,
        s_offset,
        voices: voices.span(),
    }
}

/// Deterministically build a valid rhythmic tiling canon from a seed. No search, retry, or
/// fallback: every code path produces a tiling for which `is_direct_sum` holds.
pub fn generate_rhythmic_canon(seed: felt252) -> RhythmicCanon {
    let s: u256 = seed.into();
    let ns = gen_supported_n();
    let n = *ns.at(extract_bits(s, 0, 4) % ns.len());
    build_rhythmic_canon(seed, n)
}

/// Build a rhythmic canon for a fixed cycle length `n` (must be in `gen_supported_n()`).
pub fn generate_rhythmic_canon_for_cycle(seed: felt252, n: u32) -> RhythmicCanon {
    build_rhythmic_canon(seed, n)
}

/// Like [`generate_rhythmic_canon_for_cycle`] but only selects templates with at least
/// `min_voices` tiling participants (e.g. 8 for full SATB+ counterpoint on n=24).
pub fn generate_rhythmic_canon_for_cycle_min_voices(
    seed: felt252, n: u32, min_voices: u32,
) -> RhythmicCanon {
    let all = templates_for(n);
    let rich = templates_with_min_voices(all.span(), min_voices);
    assert(rich.len() > 0, 'no rich template');
    build_rhythmic_canon_from_pool(seed, n, rich.span(), all.span())
}

/// Derive onchain metadata traits for a generated canon.
pub fn canon_traits(canon: @RhythmicCanon) -> CanonTraits {
    let n = *canon.n;
    let r = *canon.rhythm_tile;
    let s = *canon.translations;
    let templates = templates_for(n);
    let ti = *canon.template_index;
    let tmpl = *templates.at(ti);
    CanonTraits {
        cycle_length: n,
        tile_size: r.len(),
        voice_count: s.len(),
        syncopation_class: tmpl.syncopation_class,
        interest_score: tmpl.interest_score,
        distance_of_entrance: distance_of_entrance(s),
        gap_variety_r: gap_variety(n, r),
        gap_variety_s: gap_variety(n, s),
        template_index: ti,
    }
}

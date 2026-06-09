//! Clave-derived timeline rhythm generator.
//!
//! Deterministic cyclic onset patterns based on Toussaint's clave analysis.
//! Independent from the rhythmic tiling canon — collisions with other lines are permitted.
//!
//! See `docs/clave_african_math_timeline_spec.md`.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::known_timeline_rhythms::{
    all_preset_ids, preset_record, son_family_canonical_ioi, son_family_canonical_mask,
};
use koji::composition::rhythmic_tiling::OnsetEvent;

// ──────────────────────────────────────────────────────────
// Constants and IDs
// ──────────────────────────────────────────────────────────

pub const TIMELINE_N: u32 = 16;
pub const TIMELINE_ONSETS: u8 = 5;
pub const NO_PRESET: u8 = 0;

pub const PRESET_SHIKO: u8 = 1;
pub const PRESET_SON: u8 = 2;
pub const PRESET_SOUKOUS: u8 = 3;
pub const PRESET_RUMBA: u8 = 4;
pub const PRESET_BOSSA_NOVA: u8 = 5;
pub const PRESET_GAHU: u8 = 6;

pub const FAMILY_SHIKO: u16 = 1;
pub const FAMILY_SON_RUMBA_GAHU: u16 = 2;
pub const FAMILY_SOUKOUS: u16 = 3;
pub const FAMILY_BOSSA_NOVA: u16 = 4;

pub const SYMMETRY_NONE: u8 = 0;
pub const SYMMETRY_WEAK: u8 = 1;
pub const SYMMETRY_STRONG: u8 = 2;
pub const SYMMETRY_ANY: u8 = 255;

pub const SOURCE_PRESET: u8 = 1;
pub const SOURCE_INTERVAL_VARIANT: u8 = 2;
pub const SOURCE_MORPH: u8 = 3;
pub const SOURCE_PHASE: u8 = 4;

// ──────────────────────────────────────────────────────────
// Core data structures
// ──────────────────────────────────────────────────────────

#[derive(Copy, Drop, Serde)]
pub struct TimelineRhythm {
    pub n: u32,
    pub onset_mask: u32,
    pub onset_count: u8,
    pub family_id: u16,
    pub variant_id: u16,
    pub rotation: u8,
    pub preset_id: u8,
    pub source_kind: u8,
}

#[derive(Copy, Drop, Serde)]
pub struct TimelineTraits {
    pub metric_complexity: u16,
    pub symmetry_class: u8,
    pub son_distance_sq: u16,
    pub pressing_complexity_x2: u16,
    pub has_pressing_score: bool,
}

#[derive(Copy, Drop, Serde)]
pub struct TimelineSelectionProfile {
    pub target_metric_complexity: u16,
    pub metric_weight: u16,
    pub target_son_distance_sq: u16,
    pub distance_weight: u16,
    pub preferred_symmetry: u8,
    pub symmetry_penalty: u16,
}

pub const SON_FAMILY_CANDIDATES: u32 = 96;

#[derive(Copy, Drop, Serde)]
pub struct MorphEdge {
    pub from_mask: u32,
    pub to_mask: u32,
    pub displacement: u8,
}

// ──────────────────────────────────────────────────────────
// Mask validation
// ──────────────────────────────────────────────────────────

fn pow2(p: u32) -> u32 {
    let mut r: u32 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= p {
            break;
        }
        r = r * 2;
        i += 1;
    };
    r
}

pub fn popcount_u32(mask: u32) -> u32 {
    let mut count: u32 = 0;
    let mut m = mask;
    loop {
        if m == 0 {
            break;
        }
        count += m & 1;
        m = m / 2;
    };
    count
}

pub fn is_onset(mask: u32, time: u32) -> bool {
    if time >= 32 {
        return false;
    }
    (mask / pow2(time)) & 1 != 0
}

fn mask_within_n(n: u32, mask: u32) -> bool {
    if n == 0 || n > 32 {
        return false;
    }
    if n == 32 {
        return true;
    }
    mask < pow2(n)
}

pub fn validate_timeline_mask(n: u32, onset_count: u8, mask: u32) -> bool {
    if n == 0 || n > 32 {
        return false;
    }
    if !mask_within_n(n, mask) {
        return false;
    }
    popcount_u32(mask) == onset_count.into()
}

// ──────────────────────────────────────────────────────────
// Onsets, masks, and IOIs
// ──────────────────────────────────────────────────────────

pub fn mask_to_onsets(n: u32, mask: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut t: u32 = 0;
    loop {
        if t >= n {
            break;
        }
        if is_onset(mask, t) {
            out.append(t);
        }
        t += 1;
    };
    out
}

pub fn onsets_to_mask(n: u32, onsets: Span<u32>) -> Option<u32> {
    if n == 0 || n > 32 {
        return Option::None;
    }
    let mut mask: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= onsets.len() {
            break;
        }
        let t = *onsets.at(i);
        if t >= n {
            return Option::None;
        }
        let bit = pow2(t);
        if mask & bit != 0 {
            return Option::None;
        }
        mask = mask | bit;
        i += 1;
    };
    Option::Some(mask)
}

pub fn mask_to_ioi(n: u32, mask: u32) -> Option<Array<u32>> {
    if n == 0 || n > 32 || !mask_within_n(n, mask) {
        return Option::None;
    }
    if popcount_u32(mask) == 0 {
        return Option::None;
    }
    let onsets = mask_to_onsets(n, mask);
    if onsets.len() == 0 {
        return Option::None;
    }
    let mut ioi: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= onsets.len() {
            break;
        }
        let cur = *onsets.at(i);
        let next = if i + 1 < onsets.len() {
            *onsets.at(i + 1)
        } else {
            *onsets.at(0)
        };
        let gap = if i + 1 < onsets.len() {
            next - cur
        } else {
            n - cur + next
        };
        if gap == 0 {
            return Option::None;
        }
        ioi.append(gap);
        i += 1;
    };
    Option::Some(ioi)
}

pub fn ioi_to_mask(n: u32, ioi: Span<u32>) -> Option<u32> {
    if n == 0 || n > 32 || ioi.len() == 0 {
        return Option::None;
    }
    let mut sum: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= ioi.len() {
            break;
        }
        let v = *ioi.at(i);
        if v == 0 {
            return Option::None;
        }
        sum += v;
        i += 1;
    };
    if sum != n {
        return Option::None;
    }
    let mut mask: u32 = 1;
    let mut pos: u32 = 0;
    i = 0;
    loop {
        if i >= ioi.len() {
            break;
        }
        if i > 0 {
            pos = (pos + *ioi.at(i)) % n;
            let bit = pow2(pos);
            if mask & bit != 0 {
                return Option::None;
            }
            mask = mask | bit;
        }
        i += 1;
    };
    Option::Some(mask)
}

// ──────────────────────────────────────────────────────────
// Rotation
// ──────────────────────────────────────────────────────────

pub fn rotate_mask(n: u32, mask: u32, amount: u32) -> u32 {
    if n == 0 {
        return 0;
    }
    let a = amount % n;
    let mut result: u32 = 0;
    let mut t: u32 = 0;
    loop {
        if t >= n {
            break;
        }
        if is_onset(mask, t) {
            let new_t = (t + a) % n;
            result = result | pow2(new_t);
        }
        t += 1;
    };
    result
}

pub fn rotate_ioi(ioi: Span<u32>, amount: u32) -> Array<u32> {
    let len = ioi.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let a = amount % len;
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= len {
            break;
        }
        out.append(*ioi.at((i + a) % len));
        i += 1;
    };
    out
}

// ──────────────────────────────────────────────────────────
// Canonicalization
// ──────────────────────────────────────────────────────────

fn ioi_lex_lt(a: Span<u32>, b: Span<u32>) -> bool {
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            return false;
        }
        let av = *a.at(i);
        let bv = *b.at(i);
        if av < bv {
            return true;
        }
        if av > bv {
            return false;
        }
        i += 1;
    }
}

pub fn canonical_ioi_rotation(ioi: Span<u32>) -> Array<u32> {
    let len = ioi.len();
    if len == 0 {
        return ArrayTrait::new();
    }
    let mut best = rotate_ioi(ioi, 0);
    let mut r: u32 = 1;
    loop {
        if r >= len {
            break;
        }
        let candidate = rotate_ioi(ioi, r);
        if ioi_lex_lt(candidate.span(), best.span()) {
            best = candidate;
        }
        r += 1;
    };
    best
}

fn sorted_ioi(ioi: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= ioi.len() {
            break;
        }
        let v = *ioi.at(i);
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

fn is_son_family_multiset(ioi: Span<u32>) -> bool {
    if ioi.len() != 5 {
        return false;
    }
    let sorted = sorted_ioi(ioi);
    *sorted.at(0) == 2
        && *sorted.at(1) == 3
        && *sorted.at(2) == 3
        && *sorted.at(3) == 4
        && *sorted.at(4) == 4
}

fn ioi_eq(a: Span<u32>, b: Span<u32>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        if *a.at(i) != *b.at(i) {
            return false;
        }
        i += 1;
    };
    true
}

pub fn identify_son_family_variant(ioi: Span<u32>) -> Option<u16> {
    if !is_son_family_multiset(ioi) {
        return Option::None;
    }
    let canonical = canonical_ioi_rotation(ioi);
    let mut vid: u16 = 0;
    loop {
        if vid >= 6 {
            break;
        }
        match son_family_canonical_ioi(vid) {
            Option::Some(ref_ioi) => {
                if ioi_eq(canonical.span(), ref_ioi.span()) {
                    return Option::Some(vid);
                }
            },
            Option::None => {},
        }
        vid += 1;
    };
    Option::None
}

// ──────────────────────────────────────────────────────────
// Preset construction
// ──────────────────────────────────────────────────────────

pub fn known_timeline(preset_id: u8) -> Option<TimelineRhythm> {
    match preset_record(preset_id) {
        Option::Some(rec) => {
            Option::Some(
                TimelineRhythm {
                    n: TIMELINE_N,
                    onset_mask: rec.mask,
                    onset_count: TIMELINE_ONSETS,
                    family_id: rec.family_id,
                    variant_id: rec.variant_id,
                    rotation: rec.rotation,
                    preset_id: rec.preset_id,
                    source_kind: SOURCE_PRESET,
                },
            )
        },
        Option::None => Option::None,
    }
}

pub fn known_timeline_name(preset_id: u8) -> felt252 {
    if preset_id == PRESET_SHIKO {
        'Shiko'
    } else if preset_id == PRESET_SON {
        'Son'
    } else if preset_id == PRESET_SOUKOUS {
        'Soukous'
    } else if preset_id == PRESET_RUMBA {
        'Rumba'
    } else if preset_id == PRESET_BOSSA_NOVA {
        'Bossa-Nova'
    } else if preset_id == PRESET_GAHU {
        'Gahu'
    } else {
        'unknown'
    }
}

pub fn known_pressing_complexity_x2(preset_id: u8) -> Option<u16> {
    match preset_record(preset_id) {
        Option::Some(rec) => Option::Some(rec.pressing_x2),
        Option::None => Option::None,
    }
}

// ──────────────────────────────────────────────────────────
// Cyclic interval distance
// ──────────────────────────────────────────────────────────

pub fn cyclic_interval_distance_sq(a: @TimelineRhythm, b: @TimelineRhythm) -> Option<u32> {
    if *a.n != *b.n || *a.onset_count != *b.onset_count {
        return Option::None;
    }
    let ioi_a = match mask_to_ioi(*a.n, *a.onset_mask) {
        Option::Some(v) => v,
        Option::None => { return Option::None; },
    };
    let ioi_b = match mask_to_ioi(*b.n, *b.onset_mask) {
        Option::Some(v) => v,
        Option::None => { return Option::None; },
    };
    let len = ioi_a.len();
    let mut min_dist: u32 = 0xFFFFFFFF;
    let mut r: u32 = 0;
    loop {
        if r >= len {
            break;
        }
        let rot_b = rotate_ioi(ioi_b.span(), r);
        let mut sum_sq: u32 = 0;
        let mut i: u32 = 0;
        loop {
            if i >= len {
                break;
            }
            let av = *ioi_a.at(i);
            let bv = *rot_b.at(i);
            let diff = if av >= bv {
                av - bv
            } else {
                bv - av
            };
            sum_sq += diff * diff;
            i += 1;
        };
        if sum_sq < min_dist {
            min_dist = sum_sq;
        }
        r += 1;
    };
    Option::Some(min_dist)
}

// ──────────────────────────────────────────────────────────
// Son-family generation
// ──────────────────────────────────────────────────────────

fn pow2_u256(e: u32) -> u256 {
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

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2_u256(shift)) % pow2_u256(width);
    v.try_into().unwrap()
}

fn build_generated_son_timeline(variant_id: u16, rotation: u8) -> TimelineRhythm {
    let base = son_family_canonical_mask(variant_id).unwrap();
    let final_mask = rotate_mask(TIMELINE_N, base, rotation.into());
    TimelineRhythm {
        n: TIMELINE_N,
        onset_mask: final_mask,
        onset_count: TIMELINE_ONSETS,
        family_id: FAMILY_SON_RUMBA_GAHU,
        variant_id,
        rotation,
        preset_id: NO_PRESET,
        source_kind: SOURCE_INTERVAL_VARIANT,
    }
}

pub fn son_family_candidate_at_index(index: u32) -> TimelineRhythm {
    let variant_id: u16 = (index / 16).try_into().unwrap();
    let rotation: u8 = (index % 16).try_into().unwrap();
    build_generated_son_timeline(variant_id, rotation)
}

pub fn generate_son_family_timeline(seed: felt252) -> TimelineRhythm {
    let s: u256 = seed.into();
    let variant_id: u16 = (extract_bits(s, 0, 3) % 6).try_into().unwrap();
    let rotation: u8 = (extract_bits(s, 3, 4) % 16).try_into().unwrap();
    build_generated_son_timeline(variant_id, rotation)
}

// ──────────────────────────────────────────────────────────
// Metric complexity
// ──────────────────────────────────────────────────────────

fn metric_weight_16(t: u32) -> u16 {
    if t == 0 {
        5
    } else if t == 4 {
        3
    } else if t == 8 {
        4
    } else if t == 12 {
        3
    } else if t == 2 || t == 6 || t == 10 || t == 14 {
        2
    } else {
        1
    }
}

pub fn metricity_16(mask: u32) -> u16 {
    let mut total: u16 = 0;
    let mut t: u32 = 0;
    loop {
        if t >= 16 {
            break;
        }
        if is_onset(mask, t) {
            total += metric_weight_16(t);
        }
        t += 1;
    };
    total
}

pub fn metric_complexity_5_on_16(mask: u32) -> Option<u16> {
    if !validate_timeline_mask(16, TIMELINE_ONSETS, mask) {
        return Option::None;
    }
    Option::Some(17 - metricity_16(mask))
}

// ──────────────────────────────────────────────────────────
// Symmetry
// ──────────────────────────────────────────────────────────

pub fn reverse_mask(n: u32, mask: u32) -> u32 {
    if n == 0 {
        return 0;
    }
    let mut result: u32 = 0;
    let mut t: u32 = 0;
    loop {
        if t >= n {
            break;
        }
        if is_onset(mask, t) {
            let rev_t = (n - t) % n;
            result = result | pow2(rev_t);
        }
        t += 1;
    };
    result
}

pub fn timeline_symmetry_class(n: u32, mask: u32) -> u8 {
    let rev = reverse_mask(n, mask);
    if rev == mask {
        return SYMMETRY_STRONG;
    }
    let mut r: u32 = 0;
    loop {
        if r >= n {
            break;
        }
        let rotated = rotate_mask(n, mask, r);
        let rev_rot = reverse_mask(n, rotated);
        if rev_rot == rotated {
            return SYMMETRY_WEAK;
        }
        r += 1;
    };
    SYMMETRY_NONE
}

// ──────────────────────────────────────────────────────────
// Traits
// ──────────────────────────────────────────────────────────

pub fn timeline_traits(rhythm: @TimelineRhythm) -> TimelineTraits {
    let metric = match metric_complexity_5_on_16(*rhythm.onset_mask) {
        Option::Some(v) => v,
        Option::None => 0,
    };
    let symmetry = timeline_symmetry_class(*rhythm.n, *rhythm.onset_mask);
    let son_ref = match known_timeline(PRESET_SON) {
        Option::Some(v) => v,
        Option::None => {
            return TimelineTraits {
                metric_complexity: metric,
                symmetry_class: symmetry,
                son_distance_sq: 0,
                pressing_complexity_x2: 0,
                has_pressing_score: false,
            };
        },
    };
    let son_dist: u16 = match cyclic_interval_distance_sq(rhythm, @son_ref) {
        Option::Some(v) => v.try_into().unwrap(),
        Option::None => 0,
    };
    let mut has_pressing = false;
    let mut pressing_x2: u16 = 0;
    if *rhythm.preset_id != NO_PRESET {
        match known_pressing_complexity_x2(*rhythm.preset_id) {
            Option::Some(px) => {
                match known_timeline(*rhythm.preset_id) {
                    Option::Some(ref_r) => {
                        if ref_r.onset_mask == *rhythm.onset_mask {
                            has_pressing = true;
                            pressing_x2 = px;
                        }
                    },
                    Option::None => {},
                }
            },
            Option::None => {},
        }
    }
    TimelineTraits {
        metric_complexity: metric,
        symmetry_class: symmetry,
        son_distance_sq: son_dist,
        pressing_complexity_x2: pressing_x2,
        has_pressing_score: has_pressing,
    }
}

fn abs_u16(a: u16, b: u16) -> u16 {
    if a >= b {
        a - b
    } else {
        b - a
    }
}

fn abs_u32(a: u32, b: u32) -> u32 {
    if a >= b {
        a - b
    } else {
        b - a
    }
}

fn profile_score(rhythm: @TimelineRhythm, profile: @TimelineSelectionProfile) -> u32 {
    let traits = timeline_traits(rhythm);
    let metric_term: u32 = abs_u16(traits.metric_complexity, *profile.target_metric_complexity)
        .into()
        * (*profile.metric_weight).into();
    let dist_term: u32 = abs_u32(traits.son_distance_sq.into(), (*profile.target_son_distance_sq).into())
        * (*profile.distance_weight).into();
    let sym_penalty: u32 = if *profile.preferred_symmetry == SYMMETRY_ANY
        || traits.symmetry_class == *profile.preferred_symmetry {
        0
    } else {
        (*profile.symmetry_penalty).into()
    };
    metric_term + dist_term + sym_penalty
}

pub fn generate_profiled_son_family_timeline(
    seed: felt252, profile: TimelineSelectionProfile,
) -> TimelineRhythm {
    let s: u256 = seed.into();
    let start_index = extract_bits(s, 0, 7) % SON_FAMILY_CANDIDATES;
    let mut best = son_family_candidate_at_index(start_index);
    let mut best_score = profile_score(@best, @profile);
    let mut i: u32 = 1;
    loop {
        if i >= SON_FAMILY_CANDIDATES {
            break;
        }
        let idx = (start_index + i) % SON_FAMILY_CANDIDATES;
        let candidate = son_family_candidate_at_index(idx);
        let score = profile_score(@candidate, @profile);
        if score < best_score {
            best = candidate;
            best_score = score;
        }
        i += 1;
    };
    best
}

// ──────────────────────────────────────────────────────────
// Morph graph
// ──────────────────────────────────────────────────────────

pub fn single_onset_displacement(n: u32, from_mask: u32, to_mask: u32) -> Option<u8> {
    if n == 0 {
        return Option::None;
    }
    let mut removed_pos: Option<u32> = Option::None;
    let mut added_pos: Option<u32> = Option::None;
    let mut t: u32 = 0;
    loop {
        if t >= n {
            break;
        }
        let in_from = is_onset(from_mask, t);
        let in_to = is_onset(to_mask, t);
        if in_from && !in_to {
            if removed_pos.is_some() {
                return Option::None;
            }
            removed_pos = Option::Some(t);
        }
        if in_to && !in_from {
            if added_pos.is_some() {
                return Option::None;
            }
            added_pos = Option::Some(t);
        }
        t += 1;
    };
    let a = match removed_pos {
        Option::Some(v) => v,
        Option::None => { return Option::None; },
    };
    let b = match added_pos {
        Option::Some(v) => v,
        Option::None => { return Option::None; },
    };
    let fwd = (b + n - a) % n;
    let rev = (a + n - b) % n;
    let d = if fwd <= rev {
        fwd
    } else {
        rev
    };
    Option::Some(d.try_into().unwrap())
}

fn preset_morph_neighbors(current_preset_id: u8, max_displacement: u8) -> Array<u8> {
    let cur = match known_timeline(current_preset_id) {
        Option::Some(v) => v,
        Option::None => { return ArrayTrait::new(); },
    };
    let ids = all_preset_ids();
    let mut out: Array<u8> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= ids.len() {
            break;
        }
        let pid = *ids.at(i);
        if pid != current_preset_id {
            let other = known_timeline(pid).unwrap();
            match single_onset_displacement(cur.n, cur.onset_mask, other.onset_mask) {
                Option::Some(d) => {
                    if d <= max_displacement {
                        out.append(pid);
                    }
                },
                Option::None => {},
            }
        }
        i += 1;
    };
    out
}

pub fn known_morph_edges(max_displacement: u8) -> Array<MorphEdge> {
    let ids = all_preset_ids();
    let mut edges: Array<MorphEdge> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= ids.len() {
            break;
        }
        let from_id = *ids.at(i);
        let from = known_timeline(from_id).unwrap();
        let mut j: u32 = i + 1;
        loop {
            if j >= ids.len() {
                break;
            }
            let to_id = *ids.at(j);
            let to = known_timeline(to_id).unwrap();
            match single_onset_displacement(from.n, from.onset_mask, to.onset_mask) {
                Option::Some(d) => {
                    if d <= max_displacement {
                        edges
                            .append(
                                MorphEdge {
                                    from_mask: from.onset_mask,
                                    to_mask: to.onset_mask,
                                    displacement: d,
                                },
                            );
                    }
                },
                Option::None => {},
            }
            j += 1;
        };
        i += 1;
    };
    edges
}

pub fn next_known_morph(
    seed: felt252, current_preset_id: u8, max_displacement: u8,
) -> Option<TimelineRhythm> {
    let neighbors = preset_morph_neighbors(current_preset_id, max_displacement);
    if neighbors.len() == 0 {
        return Option::None;
    }
    let s: u256 = seed.into();
    let pick = extract_bits(s, 0, 8) % neighbors.len();
    let target_id = *neighbors.at(pick);
    match preset_record(target_id) {
        Option::Some(rec) => {
            Option::Some(
                TimelineRhythm {
                    n: TIMELINE_N,
                    onset_mask: rec.mask,
                    onset_count: TIMELINE_ONSETS,
                    family_id: rec.family_id,
                    variant_id: rec.variant_id,
                    rotation: rec.rotation,
                    preset_id: rec.preset_id,
                    source_kind: SOURCE_MORPH,
                },
            )
        },
        Option::None => Option::None,
    }
}

// ──────────────────────────────────────────────────────────
// Phrasing adapters
// ──────────────────────────────────────────────────────────

pub fn timeline_gate(rhythm: @TimelineRhythm, absolute_time: u32) -> bool {
    if *rhythm.n == 0 {
        return false;
    }
    is_onset(*rhythm.onset_mask, absolute_time % *rhythm.n)
}

pub fn timeline_accent(
    rhythm: @TimelineRhythm, absolute_time: u32, onset_value: u8, rest_value: u8,
) -> u8 {
    if timeline_gate(rhythm, absolute_time) {
        onset_value
    } else {
        rest_value
    }
}

pub fn timeline_to_events(
    rhythm: @TimelineRhythm, cycles: u32, voice_id: u32, velocity: u8,
) -> Array<OnsetEvent> {
    let mut events: Array<OnsetEvent> = ArrayTrait::new();
    let mut cycle: u32 = 0;
    loop {
        if cycle >= cycles {
            break;
        }
        let base = cycle * *rhythm.n;
        let onsets = mask_to_onsets(*rhythm.n, *rhythm.onset_mask);
        let mut i: u32 = 0;
        loop {
            if i >= onsets.len() {
                break;
            }
            let t = *onsets.at(i);
            events
                .append(
                    OnsetEvent {
                        time: base + t,
                        duration: 1,
                        voice_id,
                        velocity,
                    },
                );
            i += 1;
        };
        cycle += 1;
    };
    events
}

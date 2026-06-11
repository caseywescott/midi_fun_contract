//! Grouping-boundary detection — the tractable local subset of GTTM's
//! Grouping Preference Rules, computed over a developed line's own contour.
//!
//! Implements GPR 2 (proximity: boundaries at long inter-onset gaps / long
//! durations) and GPR 3 (change: boundaries at large register leaps). These are
//! the two *local* GPRs — a single integer pass, no global optimization — which
//! is the subset that fits on-chain. The expensive rules (parallelism GPR 6,
//! symmetry GPR 5, global well-formedness) are deliberately omitted.
//!
//! Output: a list of boundary indices that partition a DevelopedMotif into
//! groups, replacing fixed-length section cuts with contour-derived ones.

use core::array::ArrayTrait;
use koji::composition::motif_algebra::DevelopedMotif;
use koji::composition::canon_rules::abs_i32;

// ──────────────────────────────────────────────────────────
// Tuning constants
// ──────────────────────────────────────────────────────────

/// Weight on a duration spike (GPR 2). Long notes / held onsets cue a boundary.
const W_PROXIMITY: u32 = 3;
/// Weight on a register-leap spike (GPR 3). Large intervals cue a boundary.
const W_CHANGE: u32 = 2;
/// A gap must score at least this much above the local baseline to count as a
/// boundary. Higher = fewer, stronger boundaries.
const PEAK_THRESHOLD: u32 = 4;
/// Minimum notes per group — prevents pathological one-note slivers.
const MIN_GROUP_LEN: u32 = 2;

// ──────────────────────────────────────────────────────────
// Per-gap boundary strength
// ──────────────────────────────────────────────────────────

/// Boundary strength at the gap *after* note i (i.e. between note i and i+1).
///
/// GPR 2 contribution: how much longer note i is than its neighbours — a held
/// note creates a gap. We use the duration of note i relative to the mean of its
/// immediate neighbours.
///
/// GPR 3 contribution: the size of the register leap from note i to note i+1
/// relative to the surrounding leaps.
///
/// Both contributions are "relative to local context" because GPRs detect
/// *local* maxima, not absolute magnitudes.
fn gap_strength(
    degrees: Span<i32>, durations: Span<u32>, i: u32,
) -> u32 {
    let n = degrees.len();
    // Need a note on each side of the gap.
    if i + 1 >= n {
        return 0;
    }

    // ---- GPR 2: proximity (duration spike at note i) ----
    let dur_here = if durations.len() > i {
        *durations.at(i)
    } else {
        1_u32
    };
    let dur_next = if durations.len() > i + 1 {
        *durations.at(i + 1)
    } else {
        1_u32
    };
    // Local baseline = previous duration if it exists, else current.
    let dur_prev = if i > 0 && durations.len() > i - 1 {
        *durations.at(i - 1)
    } else {
        dur_here
    };
    let local_dur_base = (dur_prev + dur_next) / 2;
    let prox = if dur_here > local_dur_base {
        (dur_here - local_dur_base) * W_PROXIMITY
    } else {
        0_u32
    };

    // ---- GPR 3: change (register leap at the gap i -> i+1) ----
    let leap_here: u32 = abs_i32(*degrees.at(i + 1) - *degrees.at(i))
        .try_into()
        .unwrap();
    // Compare to the leaps on either side.
    let leap_prev: u32 = if i > 0 {
        abs_i32(*degrees.at(i) - *degrees.at(i - 1)).try_into().unwrap()
    } else {
        leap_here
    };
    let leap_next: u32 = if i + 2 < n {
        abs_i32(*degrees.at(i + 2) - *degrees.at(i + 1)).try_into().unwrap()
    } else {
        leap_here
    };
    let local_leap_base = (leap_prev + leap_next) / 2;
    let change = if leap_here > local_leap_base {
        (leap_here - local_leap_base) * W_CHANGE
    } else {
        0_u32
    };

    prox + change
}

// ──────────────────────────────────────────────────────────
// Boundary selection
// ──────────────────────────────────────────────────────────

/// Compute boundary indices for a developed line. A returned index `b` means a
/// group ends *after* note b (so the next group starts at b+1). Indices are
/// strictly increasing; the final note is always an implicit boundary and is NOT
/// included (the caller closes the last group at the end of the array).
///
/// Selection: score every gap, then accept a gap as a boundary iff
///   (a) its strength >= PEAK_THRESHOLD, and
///   (b) it is a local maximum (>= both neighbouring gap strengths), and
///   (c) it is at least MIN_GROUP_LEN notes past the previous boundary.
pub fn grouping_boundaries(m: @DevelopedMotif) -> Array<u32> {
    let degrees = m.degrees.span();
    let durations = m.durations.span();
    let n = degrees.len();
    let mut boundaries: Array<u32> = ArrayTrait::new();
    if n < MIN_GROUP_LEN * 2 {
        return boundaries; // too short to split
    }

    // Precompute strengths into an array so we can test local-maximum cheaply.
    let mut strengths: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        strengths.append(gap_strength(degrees, durations, i));
        i += 1;
    };
    let s = strengths.span();

    let mut last_boundary_plus1: u32 = 0; // first allowed group start
    let mut g: u32 = 0;
    loop {
        // Only consider gaps that can have a note on each side and that leave a
        // viable final group.
        if g + 1 >= n {
            break;
        }
        let here = *s.at(g);
        if here >= PEAK_THRESHOLD {
            let left = if g > 0 {
                *s.at(g - 1)
            } else {
                0
            };
            let right = if g + 1 < n {
                *s.at(g + 1)
            } else {
                0
            };
            let is_local_max = here >= left && here >= right;
            let far_enough = g + 1 >= last_boundary_plus1 + MIN_GROUP_LEN;
            // Also ensure the remaining tail can form a full group.
            let tail_ok = (n - (g + 1)) >= MIN_GROUP_LEN;
            if is_local_max && far_enough && tail_ok {
                boundaries.append(g);
                last_boundary_plus1 = g + 1;
            }
        }
        g += 1;
    };
    boundaries
}

// ──────────────────────────────────────────────────────────
// Slicing a developed line at boundaries
// ──────────────────────────────────────────────────────────

fn slice_developed(m: @DevelopedMotif, start: u32, end_excl: u32) -> DevelopedMotif {
    let degrees = m.degrees.span();
    let durations = m.durations.span();
    let mut d: Array<i32> = ArrayTrait::new();
    let mut u: Array<u32> = ArrayTrait::new();
    let mut i = start;
    loop {
        if i >= end_excl {
            break;
        }
        d.append(*degrees.at(i));
        if durations.len() > i {
            u.append(*durations.at(i));
        } else {
            u.append(1);
        }
        i += 1;
    };
    DevelopedMotif {
        degrees: d,
        durations: u,
        octave: *m.octave,
        world_mask: *m.world_mask,
    }
}

/// Partition a developed line into groups at its detected boundaries. Returns the
/// groups in order; concatenating them reproduces the input exactly.
pub fn segment_into_groups(m: @DevelopedMotif) -> Array<DevelopedMotif> {
    let n = m.degrees.len();
    let bounds = grouping_boundaries(m);
    let bspan = bounds.span();
    let mut groups: Array<DevelopedMotif> = ArrayTrait::new();
    if n == 0 {
        return groups;
    }
    let mut start: u32 = 0;
    let mut bi: u32 = 0;
    loop {
        if bi >= bspan.len() {
            break;
        }
        let end_excl = *bspan.at(bi) + 1; // boundary ends the group *after* that note
        groups.append(slice_developed(m, start, end_excl));
        start = end_excl;
        bi += 1;
    };
    // Final group: start .. n
    if start < n {
        groups.append(slice_developed(m, start, n));
    }
    groups
}

// ──────────────────────────────────────────────────────────
// Section-length helper for form builders
// ──────────────────────────────────────────────────────────

/// Return just the group LENGTHS (note counts), which a form builder can use to
/// place A/B section cuts on the line's own grouping structure instead of fixed
/// lengths. Sum of returned lengths == m.degrees.len().
pub fn group_lengths(m: @DevelopedMotif) -> Array<u32> {
    let groups = segment_into_groups(m);
    let mut lens: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= groups.len() {
            break;
        }
        lens.append(groups.at(i).degrees.len());
        i += 1;
    };
    lens
}

// ──────────────────────────────────────────────────────────
// Smoke checks
// ──────────────────────────────────────────────────────────

/// Group lengths must sum to the original length (partition is exact, lossless).
pub fn groups_partition_exact(m: @DevelopedMotif) -> bool {
    let n = m.degrees.len();
    let lens = group_lengths(m);
    let mut total: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= lens.len() {
            break;
        }
        total += *lens.at(i);
        i += 1;
    };
    total == n
}

/// Every group respects the minimum length (no slivers).
pub fn groups_respect_min(m: @DevelopedMotif) -> bool {
    if m.degrees.len() < MIN_GROUP_LEN {
        return true;
    }
    let lens = group_lengths(m);
    if lens.len() == 0 {
        return true;
    }
    let mut i: u32 = 0;
    loop {
        if i >= lens.len() {
            break true;
        }
        if *lens.at(i) < MIN_GROUP_LEN {
            // The very last group can be shorter only if the whole line is short;
            // detector guarantees tail_ok otherwise.
            break false;
        }
        i += 1;
    }
}

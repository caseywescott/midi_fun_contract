//! Form assembly driven by grouping structure.
//!
//! Ties the local-GPR phrase detector (`grouping_boundaries`) into period
//! construction so section cuts fall on the line's own contour instead of a
//! fixed grid. Parallelism (the recurrence of A) is handled on the *generation*
//! side — we build the A material once and reuse it — so no expensive
//! parallelism detection runs on-chain. The grouping heuristic only places the
//! internal phrase boundaries within each section.
//!
//! Pipeline:
//!   theme + seed
//!     ├─ A statement : weighted_program_from_seed(seed)        -> develop -> A
//!     │                 grouping_boundaries(A) gives A's internal phrasing
//!     ├─ B contrast  : weighted_program_from_seed(seed ^ salt) -> develop -> B
//!     └─ assemble     : A · A · B · A   (A reused verbatim => true parallelism)

use core::array::ArrayTrait;

use koji::composition::motif_algebra::{
    DevelopedMotif, Motif, apply_program, motif_from_degrees,
};
use koji::composition::motif_form::{B_SALT, weighted_program_from_seed};
use koji::composition::grouping_boundaries::segment_into_groups;

// ──────────────────────────────────────────────────────────
// Concatenation (local; mirror of the algebra module's helpers)
// ──────────────────────────────────────────────────────────

fn concat_i32_local(a: Span<i32>, b: Span<i32>) -> Array<i32> {
    let mut out: Array<i32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    i = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

fn concat_u32_local(a: Span<u32>, b: Span<u32>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= a.len() {
            break;
        }
        out.append(*a.at(i));
        i += 1;
    };
    i = 0;
    loop {
        if i >= b.len() {
            break;
        }
        out.append(*b.at(i));
        i += 1;
    };
    out
}

fn append_developed(acc: DevelopedMotif, next: @DevelopedMotif) -> DevelopedMotif {
    DevelopedMotif {
        degrees: concat_i32_local(acc.degrees.span(), next.degrees.span()),
        durations: concat_u32_local(acc.durations.span(), next.durations.span()),
        octave: acc.octave,
        world_mask: acc.world_mask,
    }
}

fn clone_developed(m: @DevelopedMotif) -> DevelopedMotif {
    DevelopedMotif {
        degrees: concat_i32_local(m.degrees.span(), array![].span()),
        durations: concat_u32_local(m.durations.span(), array![].span()),
        octave: *m.octave,
        world_mask: *m.world_mask,
    }
}

// ──────────────────────────────────────────────────────────
// Phrase selection from grouping structure
// ──────────────────────────────────────────────────────────

/// Pick the "head phrase" of a developed line: the first complete group as
/// detected by the GPR heuristic. This is the A-material — the line's natural
/// opening phrase, ended where its own contour says it ends (a held note or a
/// register leap), not at an arbitrary bar count. Falls back to the whole line
/// if no boundary is found (line too short / too flat to split).
pub fn head_phrase(m: @DevelopedMotif) -> DevelopedMotif {
    let groups = segment_into_groups(m);
    if groups.len() == 0 {
        return clone_developed(m);
    }
    clone_developed(groups.at(0))
}

// ──────────────────────────────────────────────────────────
// Grouping-driven AABA period
// ──────────────────────────────────────────────────────────

/// Build an AABA period whose section lengths come from grouping structure.
///
/// 1. Develop A from `seed`, then extract its head phrase via the GPR detector —
///    this is the A-material, cut where the contour phrases it.
/// 2. Develop B from a salted seed and likewise take its head phrase, so B is a
///    self-contained contrasting phrase rather than a same-length restatement.
/// 3. Assemble A · A · B · A. The A phrase is reused verbatim, so the recurrence
///    is exact (parallelism guaranteed by construction, not detected).
///
/// Result reproduces the spirit of MeloForm's form layer but with phrase
/// boundaries derived from L&J grouping rules instead of hardcoded bar counts.
pub fn develop_period_grouped(
    theme: @Motif, durations: @Array<u32>, seed: felt252, max_ops: u32,
) -> DevelopedMotif {
    // A material: develop, then phrase by contour.
    let a_full = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    let a = head_phrase(@a_full);

    // B material: salted seed -> contrasting development -> contour phrase.
    let b_full = apply_program(
        theme, durations, weighted_program_from_seed(seed + B_SALT, max_ops),
    );
    let b = head_phrase(@b_full);

    // Assemble A A B A, reusing the A phrase verbatim each time.
    let acc = clone_developed(@a);
    let acc = append_developed(acc, @a);
    let acc = append_developed(acc, @b);
    append_developed(acc, @a)
}

/// Diagnostic: return the (A_len, B_len) the grouping chose for a given seed, so
/// you can inspect how contour drives section sizing without rendering audio.
pub fn period_section_lengths(
    theme: @Motif, durations: @Array<u32>, seed: felt252, max_ops: u32,
) -> (u32, u32) {
    let a_full = apply_program(theme, durations, weighted_program_from_seed(seed, max_ops));
    let a = head_phrase(@a_full);
    let b_full = apply_program(
        theme, durations, weighted_program_from_seed(seed + B_SALT, max_ops),
    );
    let b = head_phrase(@b_full);
    (a.degrees.len(), b.degrees.len())
}

// ──────────────────────────────────────────────────────────
// Smoke checks
// ──────────────────────────────────────────────────────────

/// The period length must equal 3·|A| + |B| (A appears three times, B once).
pub fn grouped_period_length_consistent(seed: felt252) -> bool {
    let theme = motif_from_degrees(array![0_i32, 2, 1, 4], 7, 0);
    let durs = array![1_u32, 1, 1, 1];
    let (a_len, b_len) = period_section_lengths(@theme, @durs, seed, 6);
    let period = develop_period_grouped(@theme, @durs, seed, 6);
    period.degrees.len() == a_len * 3 + b_len
}

/// The head phrase is never empty for a non-empty input and never longer than
/// the line it came from.
pub fn head_phrase_well_formed(seed: felt252) -> bool {
    let theme = motif_from_degrees(array![0_i32, 2, 4, 7, 4, 2], 7, 0);
    let durs = array![1_u32, 1, 1, 1, 1, 1];
    let full = apply_program(@theme, @durs, weighted_program_from_seed(seed, 6));
    let n = full.degrees.len();
    if n == 0 {
        return true;
    }
    let phrase = head_phrase(@full);
    let pn = phrase.degrees.len();
    pn > 0 && pn <= n
}

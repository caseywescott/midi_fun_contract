//! Jazz turnaround harmony for improvised melodic canons.
//!
//! Supplies a four-region I–vi–ii–V timeline on C and pitch-class sets for chord-scale filtering
//! during the leader walk. Region 3 may use a tritone substitution (Db7 for G7), chosen
//! deterministically from seed bits. See `docs/jazz_improvised_canon_spec.md`.

use core::traits::TryInto;

pub const TURNAROUND_REGIONS: u32 = 4;

/// Dominant chord for turnaround region 3 (V).
#[derive(Copy, Drop, PartialEq)]
pub enum DominantKind {
    V7,
    TritoneSub,
}

/// Per-canon reharm choices for the I–vi–ii–V skeleton (C tonic).
#[derive(Copy, Drop, PartialEq)]
pub struct TurnaroundPlan {
    pub dominant: DominantKind,
}

fn pow2(p: u32) -> u256 {
    let mut r: u256 = 1;
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

fn extract_bits(s: u256, shift: u32, width: u32) -> u32 {
    let v = (s / pow2(shift)) % pow2(width);
    v.try_into().unwrap()
}

/// Default rhythm-changes turnaround (G7 in region 3).
pub fn turnaround_plan_default() -> TurnaroundPlan {
    TurnaroundPlan { dominant: DominantKind::V7 }
}

/// ~20% tritone-sub turnarounds; mutually exclusive with vanilla V7.
pub fn turnaround_plan_from_harmony_seed(harmony_seed: u32) -> TurnaroundPlan {
    let dominant = if harmony_seed % 5 == 0 {
        DominantKind::TritoneSub
    } else {
        DominantKind::V7
    };
    TurnaroundPlan { dominant }
}

/// Harmony plan from canon seed bits 27..30 (independent of walk LCG state).
pub fn turnaround_plan_from_canon_seed(seed: felt252) -> TurnaroundPlan {
    let s: u256 = seed.into();
    turnaround_plan_from_harmony_seed(extract_bits(s, 27, 4))
}

/// Region index for structural position `pos` over length `len` (4 equal slices).
pub fn turnaround_region_at(pos: u32, len: u32) -> u32 {
    if len == 0 {
        return 0;
    }
    (pos * TURNAROUND_REGIONS) / len
}

fn dominant_chord_pcs(dominant: DominantKind) -> Span<u8> {
    match dominant {
        DominantKind::V7 => array![7_u8, 11, 2, 5].span(),
        DominantKind::TritoneSub => array![1_u8, 5, 8, 11].span(),
    }
}

fn dominant_scale_pcs(dominant: DominantKind) -> Span<u8> {
    match dominant {
        DominantKind::V7 => array![7_u8, 9, 10, 0, 2, 5].span(),
        DominantKind::TritoneSub => array![1_u8, 3, 5, 6, 8, 10, 11].span(),
    }
}

/// Chord-tone pitch classes for turnaround region `r` under `plan` (0=Imaj7, 1=vi7, 2=ii7, 3=V).
pub fn turnaround_chord_pcs_for_plan(plan: TurnaroundPlan, r: u32) -> Span<u8> {
    let k = r % TURNAROUND_REGIONS;
    if k == 0 {
        array![0_u8, 4, 7, 11].span()
    } else if k == 1 {
        array![9_u8, 0, 4, 7].span()
    } else if k == 2 {
        array![2_u8, 5, 9, 0].span()
    } else {
        dominant_chord_pcs(plan.dominant)
    }
}

/// Chord-tone pitch classes for turnaround region `r` (0=Imaj7, 1=vi7, 2=ii7, 3=V7), tonic C.
pub fn turnaround_chord_pcs(r: u32) -> Span<u8> {
    turnaround_chord_pcs_for_plan(turnaround_plan_default(), r)
}

/// Chord-scale pitch classes for region `r` under `plan` (weak-beat material).
pub fn turnaround_scale_pcs_for_plan(plan: TurnaroundPlan, r: u32) -> Span<u8> {
    let k = r % TURNAROUND_REGIONS;
    if k == 0 {
        array![0_u8, 2, 4, 6, 7, 9, 11].span()
    } else if k == 1 {
        array![9_u8, 11, 0, 2, 4, 7].span()
    } else if k == 2 {
        array![2_u8, 4, 5, 7, 9, 0].span()
    } else {
        dominant_scale_pcs(plan.dominant)
    }
}

/// Chord-scale pitch classes for region `r` (material the leader may use on weak beats).
pub fn turnaround_scale_pcs(r: u32) -> Span<u8> {
    turnaround_scale_pcs_for_plan(turnaround_plan_default(), r)
}

/// Guide tones (3rd and 7th) for avoid-note tests on region `r`.
pub fn turnaround_guide_pcs(_plan: TurnaroundPlan, r: u32) -> Span<u8> {
    let k = r % TURNAROUND_REGIONS;
    if k == 0 {
        array![4_u8, 11].span()
    } else if k == 1 {
        array![0_u8, 7].span()
    } else if k == 2 {
        array![5_u8, 0].span()
    } else {
        // G7 and Db7 share the same guide-tone pitch classes (F and B/Cb).
        array![11_u8, 5].span()
    }
}

pub fn turnaround_is_dominant(r: u32) -> bool {
    r % TURNAROUND_REGIONS == 3
}

pub fn turnaround_has_tritone_sub(plan: TurnaroundPlan) -> bool {
    plan.dominant == DominantKind::TritoneSub
}

fn pc12_from_degree(degree: i32) -> u8 {
    let bias: i32 = 120;
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    (du % 12).try_into().unwrap()
}

fn contains_u8(set: Span<u8>, v: u8) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    loop {
        if i >= set.len() {
            break;
        }
        if *set.at(i) == v {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

/// Leader degree pitch class allowed in region `r` (scale membership).
pub fn jazz_scale_degree_ok_for_plan(plan: TurnaroundPlan, degree: i32, r: u32) -> bool {
    contains_u8(turnaround_scale_pcs_for_plan(plan, r), pc12_from_degree(degree))
}

/// Strong-beat leader degree must be a chord tone of the region.
pub fn jazz_chord_tone_ok_for_plan(plan: TurnaroundPlan, degree: i32, r: u32) -> bool {
    contains_u8(turnaround_chord_pcs_for_plan(plan, r), pc12_from_degree(degree))
}

/// Leader degree pitch class allowed in region `r` (default G7 turnaround).
pub fn jazz_scale_degree_ok(degree: i32, r: u32) -> bool {
    jazz_scale_degree_ok_for_plan(turnaround_plan_default(), degree, r)
}

/// Strong-beat leader degree must be a chord tone of the region (default G7 turnaround).
pub fn jazz_chord_tone_ok(degree: i32, r: u32) -> bool {
    jazz_chord_tone_ok_for_plan(turnaround_plan_default(), degree, r)
}

/// Region-aware material check for position `pos` over canon length `len`.
pub fn jazz_timeline_material_ok_for_plan(
    plan: TurnaroundPlan, degree: i32, pos: u32, len: u32, strong_beat: bool,
) -> bool {
    let r = turnaround_region_at(pos, len);
    if strong_beat {
        jazz_chord_tone_ok_for_plan(plan, degree, r)
    } else {
        jazz_scale_degree_ok_for_plan(plan, degree, r)
    }
}

/// Region-aware material check (default G7 turnaround).
pub fn jazz_timeline_material_ok(degree: i32, pos: u32, len: u32, strong_beat: bool) -> bool {
    jazz_timeline_material_ok_for_plan(turnaround_plan_default(), degree, pos, len, strong_beat)
}

/// Optional harmonic-walk timeline: when `use_walk`, material follows walk slot PCs;
/// otherwise identical to `jazz_timeline_material_ok_for_plan` with `plan`.
pub fn jazz_material_ok_with_walk(
    seed: felt252,
    use_walk: bool,
    plan: TurnaroundPlan,
    degree: i32,
    pos: u32,
    len: u32,
    strong_beat: bool,
) -> bool {
    if !use_walk {
        return jazz_timeline_material_ok_for_plan(plan, degree, pos, len, strong_beat);
    }
    let plan = koji::composition::harmonic_walk::harmonic_walk_plan_from_seed(seed);
    let tl = koji::composition::harmonic_walk::timeline_from_harmonic_walk(seed, plan);
    if tl.targets.len() == 0 {
        return false;
    }
    let slot = koji::composition::harmonic_walk::harmonic_walk_region_at(
        pos, len, tl.targets.len(),
    );
    let vi: usize = slot.try_into().unwrap();
    let target = tl.targets.at(vi);
    let bias: i32 = 120;
    let d: i32 = degree + bias;
    let du: u32 = d.try_into().unwrap();
    let pc: u8 = (du % 12).try_into().unwrap();
    let mut i: usize = 0;
    loop {
        if i >= target.pcs.len() {
            break;
        }
        if *target.pcs.at(i) == pc {
            return true;
        }
        i += 1;
    };
    false
}

//! Neo-Riemannian PLR triad timeline for melodic canons (profile 21).
//!
//! Cycles major/minor triad pitch-class sets so the leader changes harmony by construction.
//! See `docs/extended_harmony_canon_spec.md` and `docs/jazz_improvised_canon_spec.md`.

pub const PLR_REGIONS: u32 = 4;

/// Region index for structural position `pos` over length `len` (four equal slices).
pub fn plr_region_at(pos: u32, len: u32) -> u32 {
    if len == 0 {
        return 0;
    }
    (pos * PLR_REGIONS) / len
}

/// Pitch classes for PLR region `r` on C (0=C major, 1=A minor, 2=F major, 3=E minor).
pub fn plr_triad_pcs(r: u32) -> Span<u8> {
    let k = r % PLR_REGIONS;
    if k == 0 {
        array![0_u8, 4, 7].span()
    } else if k == 1 {
        array![9_u8, 0, 4].span()
    } else if k == 2 {
        array![5_u8, 9, 0].span()
    } else {
        array![4_u8, 7, 11].span()
    }
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

/// Leader degree allowed in region `r` (triad membership).
pub fn plr_triad_degree_ok(degree: i32, r: u32) -> bool {
    contains_u8(plr_triad_pcs(r), pc12_from_degree(degree))
}

/// Region-aware material for profile 21.
pub fn neo_timeline_material_ok(degree: i32, pos: u32, len: u32, strong_beat: bool) -> bool {
    let r = plr_region_at(pos, len);
    plr_triad_degree_ok(degree, r)
}

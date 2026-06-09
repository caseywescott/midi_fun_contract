//! Exact reference timeline preset tables.
//!
//! See `docs/clave_african_math_timeline_spec.md` for masks, families, and attribution.

use core::array::ArrayTrait;

#[derive(Copy, Drop)]
pub struct PresetRecord {
    pub preset_id: u8,
    pub mask: u32,
    pub family_id: u16,
    pub variant_id: u16,
    pub rotation: u8,
    pub pressing_x2: u16,
}

pub fn preset_record(preset_id: u8) -> Option<PresetRecord> {
    if preset_id == 1 {
        Option::Some(
            PresetRecord {
                preset_id,
                mask: 0x1451_u32,
                family_id: 1,
                variant_id: 0,
                rotation: 4,
                pressing_x2: 12,
            },
        )
    } else if preset_id == 2 {
        Option::Some(
            PresetRecord {
                preset_id,
                mask: 0x1449_u32,
                family_id: 2,
                variant_id: 3,
                rotation: 10,
                pressing_x2: 29,
            },
        )
    } else if preset_id == 3 {
        Option::Some(
            PresetRecord {
                preset_id,
                mask: 0x0C49_u32,
                family_id: 3,
                variant_id: 0,
                rotation: 10,
                pressing_x2: 30,
            },
        )
    } else if preset_id == 4 {
        Option::Some(
            PresetRecord {
                preset_id,
                mask: 0x1489_u32,
                family_id: 2,
                variant_id: 4,
                rotation: 10,
                pressing_x2: 34,
            },
        )
    } else if preset_id == 5 {
        Option::Some(
            PresetRecord {
                preset_id,
                mask: 0x2449_u32,
                family_id: 4,
                variant_id: 0,
                rotation: 10,
                pressing_x2: 44,
            },
        )
    } else if preset_id == 6 {
        Option::Some(
            PresetRecord {
                preset_id,
                mask: 0x4449_u32,
                family_id: 2,
                variant_id: 0,
                rotation: 14,
                pressing_x2: 39,
            },
        )
    } else {
        Option::None
    }
}

/// Canonical Son-family IOI vectors (variant IDs 0..5).
pub fn son_family_canonical_ioi(variant_id: u16) -> Option<Array<u32>> {
    if variant_id == 0 {
        Option::Some(array![2_u32, 3, 3, 4, 4])
    } else if variant_id == 1 {
        Option::Some(array![2_u32, 3, 4, 3, 4])
    } else if variant_id == 2 {
        Option::Some(array![2_u32, 3, 4, 4, 3])
    } else if variant_id == 3 {
        Option::Some(array![2_u32, 4, 3, 3, 4])
    } else if variant_id == 4 {
        Option::Some(array![2_u32, 4, 3, 4, 3])
    } else if variant_id == 5 {
        Option::Some(array![2_u32, 4, 4, 3, 3])
    } else {
        Option::None
    }
}

/// Canonical Son-family onset masks (variant IDs 0..5).
pub fn son_family_canonical_mask(variant_id: u16) -> Option<u32> {
    if variant_id == 0 {
        Option::Some(0x1125_u32)
    } else if variant_id == 1 {
        Option::Some(0x1225_u32)
    } else if variant_id == 2 {
        Option::Some(0x2225_u32)
    } else if variant_id == 3 {
        Option::Some(0x1245_u32)
    } else if variant_id == 4 {
        Option::Some(0x2245_u32)
    } else if variant_id == 5 {
        Option::Some(0x2445_u32)
    } else {
        Option::None
    }
}

pub fn all_preset_ids() -> Array<u8> {
    array![1_u8, 2, 3, 4, 5, 6]
}

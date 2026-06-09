//! Curated transition continuations with surprise tiers (Pachet §3).
//!
//! Offline source: `fixtures/harmonic_continuations.json`.

use core::traits::TryInto;
use koji::composition::known_harmonic_skeletons::HarmonicSlot;

pub const CONTINUATION_COUNT: u16 = 16;
pub const MAX_CONT_CANDS: u8 = 8;

#[derive(Copy, Drop)]
pub struct TransitionContinuation {
    pub row_id: u16,
    pub prefix_from_q: u8,
    pub prefix_to_q: u8,
    pub prefix_to_root: u8,
    pub next_beats: u8,
    pub next_root_offset: u8,
    pub next_quality: u8,
    pub weight: u16,
    pub surprise_tier: u8,
}

pub fn continuation_at(row_id: u16) -> Option<TransitionContinuation> {
    if row_id == 0 {
        Option::Some(
            TransitionContinuation {
                row_id: 0,
                prefix_from_q: 2,
                prefix_to_q: 1,
                prefix_to_root: 5,
                next_beats: 4,
                next_root_offset: 10,
                next_quality: 2,
                weight: 100,
                surprise_tier: 0,
            },
        ) // after Cmin:F7 -> Bbmin (E)
    } else if row_id == 1 {
        Option::Some(
            TransitionContinuation {
                row_id: 1,
                prefix_from_q: 2,
                prefix_to_q: 1,
                prefix_to_root: 5,
                next_beats: 4,
                next_root_offset: 10,
                next_quality: 1,
                weight: 90,
                surprise_tier: 20,
            },
        )
    } else if row_id == 2 {
        Option::Some(
            TransitionContinuation {
                row_id: 2,
                prefix_from_q: 2,
                prefix_to_q: 1,
                prefix_to_root: 5,
                next_beats: 4,
                next_root_offset: 5,
                next_quality: 0,
                weight: 80,
                surprise_tier: 40,
            },
        )
    } else if row_id == 3 {
        Option::Some(
            TransitionContinuation {
                row_id: 3,
                prefix_from_q: 2,
                prefix_to_q: 1,
                prefix_to_root: 5,
                next_beats: 4,
                next_root_offset: 1,
                next_quality: 2,
                weight: 30,
                surprise_tier: 255,
            },
        ) // surprising A7 path
    } else if row_id == 4 {
        Option::Some(
            TransitionContinuation {
                row_id: 4,
                prefix_from_q: 1,
                prefix_to_q: 1,
                prefix_to_root: 0,
                next_beats: 4,
                next_root_offset: 5,
                next_quality: 0,
                weight: 95,
                surprise_tier: 0,
            },
        ) // C7:F7 -> F
    } else if row_id == 5 {
        Option::Some(
            TransitionContinuation {
                row_id: 5,
                prefix_from_q: 0,
                prefix_to_q: 0,
                prefix_to_root: 0,
                next_beats: 4,
                next_root_offset: 5,
                next_quality: 0,
                weight: 100,
                surprise_tier: 0,
            },
        ) // C:C -> F
    } else if row_id == 6 {
        Option::Some(
            TransitionContinuation {
                row_id: 6,
                prefix_from_q: 0,
                prefix_to_q: 1,
                prefix_to_root: 0,
                next_beats: 4,
                next_root_offset: 5,
                next_quality: 0,
                weight: 85,
                surprise_tier: 10,
            },
        )
    } else if row_id == 7 {
        Option::Some(
            TransitionContinuation {
                row_id: 7,
                prefix_from_q: 255,
                prefix_to_q: 255,
                prefix_to_root: 255,
                next_beats: 4,
                next_root_offset: 5,
                next_quality: 0,
                weight: 50,
                surprise_tier: 128,
            },
        ) // empty prefix fallback
    } else if row_id >= 8 && row_id < CONTINUATION_COUNT {
        Option::Some(
            TransitionContinuation {
                row_id,
                prefix_from_q: 1,
                prefix_to_q: 1,
                prefix_to_root: 0,
                next_beats: 4,
                next_root_offset: 7,
                next_quality: 1,
                weight: 70,
                surprise_tier: 60,
            },
        )
    } else {
        Option::None
    }
}

pub fn continuation_next_slot(row: TransitionContinuation, anchor: HarmonicSlot) -> HarmonicSlot {
    let r: u32 = anchor.root_pc.into();
    let o: u32 = row.next_root_offset.into();
    HarmonicSlot {
        beats: row.next_beats,
        root_pc: ((r + o) % 12).try_into().unwrap(),
        quality_id: row.next_quality,
        function_class: anchor.function_class,
    }
}

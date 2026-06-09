//! Curated chord-substitution rewrites (Pachet §2.4). Duration-preserving, bounded table.
//!
//! See `docs/harmonic_substitution_walk_spec.md` and `fixtures/harmonic_rewrites.json`.

use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::composition::known_harmonic_skeletons::{
    HarmonicSlot, RULE_ENRICHMENT, RULE_PREP_DOM, RULE_PREP_MINOR, RULE_RELATIVE_MINOR,
    RULE_REPETITION, RULE_TO_FOURTH, RULE_TRITONE_SUB, RULE_TWO_FIVE,
};

pub const REWRITE_COUNT: u16 = 10;
pub const MAX_APPLICABLE: u8 = 8;

#[derive(Copy, Drop)]
pub struct HarmonicRewrite {
    pub rule_id: u16,
    pub lhs_len: u8,
    pub rhs_len: u8,
    pub rule_kind: u8,
    pub weight: u16,
}

pub fn rewrite_meta(rule_id: u16) -> Option<HarmonicRewrite> {
    if rule_id >= REWRITE_COUNT {
        return Option::None;
    }
    if rule_id == 0 {
        Option::Some(HarmonicRewrite { rule_id: 0, lhs_len: 1, rhs_len: 2, rule_kind: RULE_REPETITION, weight: 100 })
    } else if rule_id == 1 {
        Option::Some(HarmonicRewrite { rule_id: 1, lhs_len: 1, rhs_len: 1, rule_kind: RULE_ENRICHMENT, weight: 90 })
    } else if rule_id == 2 {
        Option::Some(HarmonicRewrite { rule_id: 2, lhs_len: 1, rhs_len: 1, rule_kind: RULE_RELATIVE_MINOR, weight: 80 })
    } else if rule_id == 3 {
        Option::Some(HarmonicRewrite { rule_id: 3, lhs_len: 1, rhs_len: 1, rule_kind: RULE_TRITONE_SUB, weight: 85 })
    } else if rule_id == 4 {
        Option::Some(HarmonicRewrite { rule_id: 4, lhs_len: 1, rhs_len: 2, rule_kind: RULE_PREP_DOM, weight: 95 })
    } else if rule_id == 5 {
        Option::Some(HarmonicRewrite { rule_id: 5, lhs_len: 1, rhs_len: 2, rule_kind: RULE_PREP_MINOR, weight: 90 })
    } else if rule_id == 6 {
        Option::Some(HarmonicRewrite { rule_id: 6, lhs_len: 1, rhs_len: 2, rule_kind: RULE_TO_FOURTH, weight: 85 })
    } else if rule_id == 7 {
        Option::Some(HarmonicRewrite { rule_id: 7, lhs_len: 1, rhs_len: 2, rule_kind: RULE_TWO_FIVE, weight: 92 })
    } else if rule_id == 8 {
        Option::Some(HarmonicRewrite { rule_id: 8, lhs_len: 1, rhs_len: 1, rule_kind: RULE_TRITONE_SUB, weight: 75 })
    } else {
        Option::Some(HarmonicRewrite { rule_id: 9, lhs_len: 1, rhs_len: 1, rule_kind: RULE_ENRICHMENT, weight: 70 })
    }
}

/// LHS template slot `k` (root_offset from anchor root PC).
pub fn rewrite_lhs_template(rule_id: u16, k: u8) -> Option<(u8, u8, u8)> {
    if rule_id >= REWRITE_COUNT {
        return Option::None;
    }
    if k > 0 {
        return Option::None;
    }
    if rule_id == 0 {
        Option::Some((4, 0, 255)) // beats, root_offset, quality (255 = any triad/seventh)
    } else if rule_id == 1 {
        Option::Some((4, 0, 0)) // maj triad bar
    } else if rule_id == 2 {
        Option::Some((4, 0, 0))
    } else if rule_id == 3 {
        Option::Some((4, 0, 1)) // dom7
    } else if rule_id == 4 {
        Option::Some((4, 0, 0))
    } else if rule_id == 5 {
        Option::Some((4, 0, 1))
    } else if rule_id == 6 {
        Option::Some((4, 0, 1))
    } else if rule_id == 7 {
        Option::Some((4, 0, 0))
    } else if rule_id == 8 {
        Option::Some((4, 0, 2)) // min7
    } else {
        Option::Some((4, 0, 5)) // maj7 -> enrich to dom color
    }
}

/// RHS slot `k` (root_offset from anchor, quality, beats).
pub fn rewrite_rhs_template(rule_id: u16, k: u8) -> Option<(u8, u8, u8)> {
    if rule_id >= REWRITE_COUNT {
        return Option::None;
    }
    if rule_id == 0 {
        if k == 0 {
            Option::Some((2, 0, 255))
        } else if k == 1 {
            Option::Some((2, 0, 255))
        } else {
            Option::None
        }
    } else if rule_id == 1 {
        Option::Some((4, 0, 1))
    } else if rule_id == 2 {
        Option::Some((4, 9, 2)) // relative minor
    } else if rule_id == 3 {
        Option::Some((4, 6, 1)) // tritone sub F#7
    } else if rule_id == 4 {
        if k == 0 {
            Option::Some((2, 7, 1)) // G7
        } else {
            Option::Some((2, 0, 0)) // C
        }
    } else if rule_id == 5 {
        if k == 0 {
            Option::Some((2, 7, 2)) // Dmin7 before G7
        } else {
            Option::Some((2, 0, 1))
        }
    } else if rule_id == 6 {
        if k == 0 {
            Option::Some((2, 0, 1))
        } else {
            Option::Some((2, 5, 0)) // F
        }
    } else if rule_id == 7 {
        if k == 0 {
            Option::Some((2, 2, 2)) // Dmin7 from C
        } else {
            Option::Some((2, 7, 1))
        }
    } else if rule_id == 8 {
        Option::Some((4, 6, 1)) // min7 tritone to dom7
    } else {
        Option::Some((4, 0, 1))
    }
}

fn pc_add(root: u8, offset: u8) -> u8 {
    let r: u32 = root.into();
    let o: u32 = offset.into();
    ((r + o) % 12).try_into().unwrap()
}

fn slot_from_template(anchor: HarmonicSlot, beats: u8, root_offset: u8, quality_id: u8) -> HarmonicSlot {
    let q = if quality_id == 255 {
        anchor.quality_id
    } else {
        quality_id
    };
    HarmonicSlot {
        beats,
        root_pc: pc_add(anchor.root_pc, root_offset),
        quality_id: q,
        function_class: anchor.function_class,
    }
}

pub fn lhs_matches(rule_id: u16, anchor: HarmonicSlot, slots: Span<HarmonicSlot>, index: u32) -> bool {
    let meta = rewrite_meta(rule_id);
    if meta.is_none() {
        return false;
    }
    let meta = meta.unwrap();
    if index + meta.lhs_len.into() > slots.len() {
        return false;
    }
    let mut k: u8 = 0;
    loop {
        if k >= meta.lhs_len {
            break;
        }
        let tmpl = rewrite_lhs_template(rule_id, k);
        if tmpl.is_none() {
            return false;
        }
        let (t_beats, t_root_off, t_qual) = tmpl.unwrap();
        let actual = *slots.at(index + k.into());
        if actual.beats != t_beats {
            return false;
        }
        if t_qual != 255 && actual.quality_id != t_qual {
            return false;
        }
        if t_root_off != 0 && actual.root_pc != pc_add(anchor.root_pc, t_root_off) {
            return false;
        }
        k += 1;
    };
    true
}

pub fn build_rhs_slots(rule_id: u16, anchor: HarmonicSlot) -> Array<HarmonicSlot> {
    let mut out: Array<HarmonicSlot> = ArrayTrait::new();
    let meta = rewrite_meta(rule_id).unwrap();
    let mut k: u8 = 0;
    loop {
        if k >= meta.rhs_len {
            break;
        }
        let tmpl = rewrite_rhs_template(rule_id, k).unwrap();
        let (beats, root_off, qual) = tmpl;
        out.append(slot_from_template(anchor, beats, root_off, qual));
        k += 1;
    };
    out
}

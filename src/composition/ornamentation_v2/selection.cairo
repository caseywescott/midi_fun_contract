//! Deterministic and live rule selection (§12).

use core::array::ArrayTrait;
use koji::lcg::{LCG, RNGTrait};
use koji::rng::{bounded, LCGRandomSource, RandomSource};
use koji::composition::ornamentation_v2::types::{
    OrnamentContext, OrnamentStyleProfile, SELECTION_LIVE, SELECTION_SEEDED,
};

pub fn lcg_from_seed_state(state: u32) -> LCG {
    LCG {
        state: if state == 0 {
            1
        } else {
            state
        },
        multiplier: 5,
        increment: 3,
        modulus: 65536,
    }
}

pub fn advance_seed(state: u32) -> u32 {
    lcg_from_seed_state(state).next().state
}

pub fn deterministic_choice_u32(items: Span<u32>, seed_state: u32) -> (u32, u32) {
    if items.len() == 0 {
        return (0, advance_seed(seed_state));
    }
    let lcg = lcg_from_seed_state(seed_state);
    let (raw, next_lcg) = LCGRandomSource::draw(@lcg);
    let idx = bounded(raw, items.len());
    (*items.at(idx), next_lcg.state)
}

pub fn deterministic_choice_u8(items: Span<u8>, seed_state: u32) -> (u8, u32) {
    if items.len() == 0 {
        return (0, advance_seed(seed_state));
    }
    let lcg = lcg_from_seed_state(seed_state);
    let (raw, next_lcg) = LCGRandomSource::draw(@lcg);
    let idx = bounded(raw, items.len());
    (*items.at(idx), next_lcg.state)
}

pub fn weighted_pick_u8(
    kinds: Span<u8>, weights: Span<u32>, seed_state: u32,
) -> (u8, u32) {
    if kinds.len() == 0 {
        return (0, advance_seed(seed_state));
    }
    let mut total: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= weights.len() {
            break;
        }
        total += *weights.at(i);
        i += 1;
    };
    if total == 0 {
        return deterministic_choice_u8(kinds, seed_state);
    }
    let lcg = lcg_from_seed_state(seed_state);
    let (raw, next_lcg) = LCGRandomSource::draw(@lcg);
    let target = bounded(raw, total);
    let mut acc: u32 = 0;
    i = 0;
    loop {
        if i >= kinds.len() {
            break;
        }
        let w = if i < weights.len() {
            *weights.at(i)
        } else {
            1_u32
        };
        acc += w;
        if target < acc {
            return (*kinds.at(i), next_lcg.state);
        }
        i += 1;
    };
    (*kinds.at(0), next_lcg.state)
}

pub fn live_entropy_draw(entropy_slot: u32) -> u32 {
  // Placeholder live entropy: mixes wall-clock proxy with slot (non-reproducible by design).
    (entropy_slot * 17 + 13) % 256
}

pub fn live_choice_u8(items: Span<u8>, entropy_slot: u32) -> u8 {
    if items.len() == 0 {
        return 0;
    }
    let raw = live_entropy_draw(entropy_slot);
    *items.at(bounded(raw, items.len()))
}

pub fn base_weight_for_kind(kind: u8, style: OrnamentStyleProfile) -> u32 {
    if kind == 1 || kind == 2 {
        style.passing_bias.into()
    } else if kind == 3 || kind == 4 {
        style.neighbor_bias.into()
    } else if kind >= 8 && kind <= 12 {
        style.suspension_bias.into()
    } else if kind == 25 || kind == 26 {
        style.trill_bias.into()
    } else if kind == 23 || kind == 24 {
        style.turn_bias.into()
    } else if kind == 27 || kind == 28 {
        style.grace_note_bias.into()
    } else if kind == 29 || kind == 30 {
        style.chromatic_approach_bias.into()
    } else if kind == 33 || kind == 34 {
        style.arpeggiation_bias.into()
    } else if kind == 35 {
        style.pedal_bias.into()
    } else if kind == 31 || kind == 32 {
        style.jazz_enclosure_bias.into()
    } else {
        style.density.into()
    }
}

pub fn rule_prefers_strong_beat(kind: u8) -> bool {
    kind == 14 || kind == 15 || kind == 8 || kind == 9 || kind == 10
}

pub fn rule_is_chromatic(kind: u8) -> bool {
    kind == 29 || kind == 30 || kind == 31 || kind == 32
}

pub fn rule_crosses_boundary(kind: u8) -> bool {
    kind == 7 || kind >= 8 && kind <= 13 || kind == 35
}

pub fn rule_is_canon_safe(kind: u8) -> bool {
    kind == 1 || kind == 2 || kind == 3 || kind == 4 || kind == 5 || kind == 6 || kind == 7
}

pub fn weight_rule(kind: u8, ctx: OrnamentContext, style: OrnamentStyleProfile) -> u32 {
    let mut w = base_weight_for_kind(kind, style);
    if ctx.beat_strength > 75 && rule_prefers_strong_beat(kind) {
        w = w * 3 / 2;
    }
    if ctx.has_applied_transform && rule_is_canon_safe(kind) {
        w = w * 13 / 10;
    }
    if rule_is_chromatic(kind) && style.chromaticism < 20 {
        w = w / 10;
    }
    if w == 0 {
        1_u32
    } else {
        w
    }
}

pub fn build_candidate_weights(
    candidates: Span<u8>, ctx: OrnamentContext, style: OrnamentStyleProfile,
) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= candidates.len() {
            break;
        }
        out.append(weight_rule(*candidates.at(i), ctx, style));
        i += 1;
    };
    out
}

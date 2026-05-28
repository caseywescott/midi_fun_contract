use core::array::ArrayTrait;
use koji::rng::bounded;

/// A 1-D weighted probability table over discrete outcomes.
/// `total` must equal `sum(weights)`.
#[derive(Copy, Drop)]
pub struct TendencyMask {
    pub weights: Span<u32>,
    pub total: u32,
}

/// Build a TendencyMask by summing the provided weights.
pub fn new_tendency_mask(weights: Span<u32>) -> TendencyMask {
    let mut total: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= weights.len() {
            break;
        }
        total += *weights.at(i);
        i += 1;
    };
    TendencyMask { weights, total }
}

/// Roulette-wheel selection: map `raw` to an index according to `mask.weights`.
pub fn pick_weighted_index(mask: @TendencyMask, raw: u32) -> usize {
    let total = *mask.total;
    assert(total > 0, 'zero total weight');
    let pick = raw % total;
    let mut acc: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= (*mask.weights).len() {
            // Fallback: last index (shouldn't happen when total == sum(weights)).
            break (*mask.weights).len() - 1;
        }
        acc += *(*mask.weights).at(i);
        if pick < acc {
            break i;
        }
        i += 1;
    }
}

/// Collect MIDI pitches from `scale` (semitone offsets from `root`) that fall in
/// `[lo, hi]`, then pick one uniformly using `raw`.
pub fn pick_pitch_in_range(
    scale: Span<u8>,
    root: u8,
    lo: u32,
    hi: u32,
    raw: u32,
) -> u8 {
    let mut candidates: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= scale.len() {
            break;
        }
        let degree = *scale.at(i);
        let midi: u32 = root.into() + degree.into();
        if midi >= lo && midi <= hi {
            candidates.append(midi.try_into().unwrap());
        }
        i += 1;
    };
    let n = candidates.len();
    assert(n > 0, 'empty range');
    if n == 1 {
        return *candidates.at(0);
    }
    let idx: usize = bounded(raw, n.try_into().unwrap()).try_into().unwrap();
    return *candidates.at(idx);
}

/// Apply a tendency mask to pick a weighted scale degree (semitone offset).
pub fn masked_scale_degree(mask: @TendencyMask, scale: Span<u8>, raw: u32) -> u8 {
    let idx = pick_weighted_index(mask, raw);
    *scale.at(idx)
}

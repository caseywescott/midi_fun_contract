//! Barry Harris v2 idiomatic voicing styles.
//!
//! See `docs/barry_harris_v2.md` §BH17.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::{stable_chord_tones, voicelead, HarmonicState};
use koji::composition::barry_v2_types::{BarryVoicingStyle, VoiceMotionPolicy};
use koji::composition::barry_voice_motion::voicelead_with_policy;

pub fn apply_drop_two(voicing: Span<i16>) -> Array<i16> {
    if voicing.len() < 4 {
        return clone_i16(voicing);
    }
    let sorted = sort_asc(clone_i16(voicing));
    let drop_idx = sorted.len() - 2;
    let dropped = *sorted.at(drop_idx) - 12;
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= sorted.len() {
            break;
        }
        if i == drop_idx {
            out.append(dropped);
        } else {
            out.append(*sorted.at(i));
        }
        i += 1;
    };
    sort_asc(out)
}

pub fn apply_drop_three(voicing: Span<i16>) -> Array<i16> {
    if voicing.len() < 4 {
        return clone_i16(voicing);
    }
    let sorted = sort_asc(clone_i16(voicing));
    let drop_idx = sorted.len() - 3;
    let dropped = *sorted.at(drop_idx) - 12;
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= sorted.len() {
            break;
        }
        if i == drop_idx {
            out.append(dropped);
        } else {
            out.append(*sorted.at(i));
        }
        i += 1;
    };
    sort_asc(out)
}

pub fn realize_rootless_shell(
    state: HarmonicState, register_min: i16, register_max: i16,
) -> Array<i16> {
    let stable = stable_chord_tones(@state);
    let mut pcs: Array<u8> = ArrayTrait::new();
    let start: usize = if stable.len() > 3 { 1 } else { 0 };
    let mut i: usize = start;
    loop {
        if i >= stable.len() {
            break;
        }
        pcs.append(*stable.at(i));
        i += 1;
    };
    voicelead(array![].span(), pcs.span(), register_min, register_max, 0)
}

pub fn realize_voicing_style(
    target_pcs: Span<u8>,
    previous_voicing: Span<i16>,
    register_min: i16,
    register_max: i16,
    style: BarryVoicingStyle,
    policy: VoiceMotionPolicy,
    tie_break: u32,
) -> Array<i16> {
    let close = voicelead_with_policy(
        previous_voicing, target_pcs, register_min, register_max, policy, tie_break,
    );
    let voiced = match style {
        BarryVoicingStyle::ClosedPosition => close,
        BarryVoicingStyle::DropTwo => apply_drop_two(close.span()),
        BarryVoicingStyle::DropThree => apply_drop_three(close.span()),
        BarryVoicingStyle::FourWayClose => close,
        BarryVoicingStyle::RootlessShell => {
            if target_pcs.len() > 1 {
                let mut pcs: Array<u8> = ArrayTrait::new();
                let mut j: usize = 1;
                loop {
                    if j >= target_pcs.len() {
                        break;
                    }
                    pcs.append(*target_pcs.at(j));
                    j += 1;
                };
                voicelead_with_policy(
                    previous_voicing, pcs.span(), register_min, register_max, policy, tie_break,
                )
            } else {
                close
            }
        },
        BarryVoicingStyle::TwoHandBlock => two_hand_block(close.span(), register_min, register_max),
    };
    clamp_voicing(voiced.span(), register_min, register_max)
}

fn two_hand_block(
    voicing: Span<i16>, register_min: i16, register_max: i16,
) -> Array<i16> {
    let mid = (register_min + register_max) / 2;
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= voicing.len() {
            break;
        }
        let k = *voicing.at(i);
        if i == 0 && k > mid {
            out.append(k - 12);
        } else if i > 0 && k < mid {
            out.append(k + 12);
        } else {
            out.append(k);
        }
        i += 1;
    };
    out
}

fn clamp_voicing(voicing: Span<i16>, register_min: i16, register_max: i16) -> Array<i16> {
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= voicing.len() {
            break;
        }
        let mut k = *voicing.at(i);
        loop {
            if k >= register_min {
                break;
            }
            k += 12;
        };
        loop {
            if k <= register_max {
                break;
            }
            k -= 12;
        };
        out.append(k);
        i += 1;
    };
    out
}

fn idx_picked(picked: Span<usize>, idx: usize) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= picked.len() {
            break;
        }
        if *picked.at(i) == idx {
            return true;
        }
        i += 1;
    };
    false
}

fn sort_asc(arr: Array<i16>) -> Array<i16> {
    let n = arr.len();
    let mut out: Array<i16> = ArrayTrait::new();
    let mut picked_idxs: Array<usize> = ArrayTrait::new();
    let mut count: usize = 0;
    loop {
        if count >= n {
            break;
        }
        let mut best_idx: usize = 0;
        let mut best_val: i16 = 127;
        let mut j: usize = 0;
        loop {
            if j >= n {
                break;
            }
            if !idx_picked(picked_idxs.span(), j) {
                let v = *arr.at(j);
                if v < best_val {
                    best_val = v;
                    best_idx = j;
                }
            }
            j += 1;
        };
        out.append(best_val);
        picked_idxs.append(best_idx);
        count += 1;
    };
    out
}

fn clone_i16(src: Span<i16>) -> Array<i16> {
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= src.len() {
            break;
        }
        out.append(*src.at(i));
        i += 1;
    };
    out
}

pub fn closed_position_span(voicing: Span<i16>) -> i16 {
    if voicing.len() == 0 {
        return 0;
    }
    let sorted = sort_asc(clone_i16(voicing));
    *sorted.at(sorted.len() - 1) - *sorted.at(0)
}

pub fn drop_two_lowered_second_highest(voicing: Span<i16>) -> bool {
    if voicing.len() < 4 {
        return true;
    }
    let dropped = apply_drop_two(voicing);
    let sorted = sort_asc(clone_i16(voicing));
    let second_high = *sorted.at(sorted.len() - 2);
    let mut i: usize = 0;
    loop {
        if i >= dropped.len() {
            break;
        }
        if *dropped.at(i) == second_high - 12 {
            return true;
        }
        i += 1;
    };
    false
}

pub fn voicing_in_register(voicing: Span<i16>, register_min: i16, register_max: i16) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= voicing.len() {
            break;
        }
        let k = *voicing.at(i);
        if k < register_min || k > register_max {
            return false;
        }
        i += 1;
    };
    true
}
